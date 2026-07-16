import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../providers/device_provider.dart';
import '../../providers/room_group_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/device_menu_helper.dart';
import '../../widgets/room_group_dialogs.dart';
import '../dashboard_screen.dart' show showDeviceSettingsPopup;
import '../devices/add_device_dialog.dart';

/// Một dòng trong danh sách thiết bị — bản chiếu mỏng của `DeviceListItem` (Go,
/// `dashboard_handler.go`) trả về từ GET /api/homes/{id}/devices.
///
/// [isOnline] LÀ NGUỒN SỰ THẬT DUY NHẤT cho dấu chấm trạng thái — trước đây UI so sánh
/// thẳng `device['status'] == 'ONLINE'` (chữ HOA) trong khi Backend luôn trả chữ THƯỜNG
/// (`buildHomeDevices()`: `status := "offline"` / `status = "online"`) -> so sánh KHÔNG
/// BAO GIỜ khớp, dấu chấm im lặng luôn xám dù thiết bị đang online thật. Chuẩn hóa
/// `.toUpperCase()` một lần duy nhất ở đây để không lặp lại lỗi tại bất kỳ nơi nào khác đọc
/// field này.
///
/// [raw] giữ nguyên map JSON gốc (schema/settings/state_data/system_data...) — CÁC POPUP
/// khác (showDeviceSettingsPopup cần system_data để hiện IP/RSSI/OTA) vẫn cần đủ dữ liệu
/// thô, model này KHÔNG thay thế hoàn toàn map gốc, chỉ bọc thêm phần đã gõ kiểu.
class DeviceListItem {
  final String mac;
  final String name;
  final bool isOnline;
  final Map<String, dynamic> raw;

  const DeviceListItem({required this.mac, required this.name, required this.isOnline, required this.raw});

  factory DeviceListItem.fromJson(Map<String, dynamic> json) {
    final String mac = (json['mac_address'] ?? json['mac'] ?? '').toString();
    return DeviceListItem(
      mac: mac,
      name: (json['name'] ?? 'Thiết bị $mac').toString(),
      isOnline: (json['status'] ?? '').toString().toUpperCase() == 'ONLINE',
      raw: json,
    );
  }
}

/// Danh sách thiết bị của MỘT nhà — dữ liệu thật từ GET /api/homes/{id}/devices.
///
/// [NHÚNG, KHÔNG PUSH] Cùng nguyên tắc với MemberListScreen: KHÔNG Navigator.push, KHÔNG
/// AppBar riêng — HomeManagementScreen hoán đổi (setState) làm nội dung trong CÙNG Content
/// Area, Sidebar/Header của Dashboard không hề bị che. [onBack] là lối thoát duy nhất.
class DeviceListScreen extends StatefulWidget {
  final Map<String, dynamic> homeData;
  final VoidCallback onBack;
  const DeviceListScreen({super.key, required this.homeData, required this.onBack});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  static const Color _tkGreen = Color(0xFF00A651);
  static const String _baseUrl = "https://api.iot-smart.vn/api";

  bool _isLoading = true;
  List<DeviceListItem> _devices = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  String get _homeId => widget.homeData['home_id'].toString();
  String get _homeName => (widget.homeData['home_name'] ?? _homeId).toString();

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDevices() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('$_baseUrl/homes/${Uri.encodeComponent(_homeId)}/devices'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> rawList = jsonDecode(response.body);
        final parsed = rawList.map((e) => DeviceListItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        if (mounted) setState(() { _devices = parsed; _isLoading = false; });
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải thiết bị: Mã ${response.statusCode}'), backgroundColor: Colors.redAccent));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _linkDeviceToHome(String macAddress) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: _tkGreen)));
    try {
      final token = await AuthService().getToken();
      final response = await http.post(
        Uri.parse('$_baseUrl/homes/${Uri.encodeComponent(_homeId)}/devices'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({"mac_address": macAddress}),
      );
      if (!mounted) return;
      Navigator.pop(context); // đóng loading
      final resData = jsonDecode(response.body);
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resData['message'] ?? 'Thêm thiết bị thành công!'), backgroundColor: _tkGreen));
        _fetchDevices();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resData['error'] ?? 'Lỗi khi thêm thiết bị'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent));
    }
  }

  // ==========================================================================
  // [TÁI SỬ DỤNG 100% — KHÔNG DỰNG LUỒNG MỚI] Đây CHÍNH là menu long-press của thẻ thiết
  // bị trên Dashboard (DeviceMenuHelper.showGenericDeviceMenu — cùng 1 class, cùng 1 UI).
  // Dashboard tự lắp callback này trong các State private (_showDeviceOptions/
  // _openDeviceSettingsByMac trong dashboard_screen.dart) — Dart không cho gọi thẳng method
  // riêng (_prefix) từ file khác, nên ở đây lắp lại đúng CÙNG các hàm PUBLIC mà chính những
  // method đó gọi bên trong: showDeviceSettingsPopup() (top-level, cùng file dashboard_screen.dart
  // — đã import), DeviceProvider.deleteDevice(), RoomGroupProvider.assignDevicesToRoom(),
  // ApiService().renameDeviceEndpoint(). KHÔNG có logic API nào bị viết lại — chỉ là lắp lại
  // đúng những khối đã có sẵn từ một điểm gọi khác.
  // ==========================================================================
  void _showDeviceSettingsMenu(DeviceListItem device) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String mac = device.mac;
    final String name = device.name;
    final deviceProvider = context.read<DeviceProvider>();
    final roomProvider = context.read<RoomGroupProvider>();

    DeviceMenuHelper.showGenericDeviceMenu(
      context: context,
      mac: mac,
      currentName: name,
      subtitle: _homeName,
      // "Cài đặt thiết bị" — popup thông số/OTA thật, giống hệt Dashboard.
      onOpenSettings: () => showDeviceSettingsPopup(
        context,
        isDark: isDark,
        mac: mac,
        displayName: name,
        rawDeviceData: device.raw,
        provider: deviceProvider,
        onRename: () => _showRenameDialog(mac, name),
      ),
      onRename: () => _showRenameDialog(mac, name),
      onAssignRoom: () async {
        final room = await showRoomSelectionDialog(context, roomProvider);
        if (room == null || !mounted) return;
        final err = await roomProvider.assignDevicesToRoom([mac], room.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? 'Đã thêm vào "${room.name}"'),
          backgroundColor: err == null ? _tkGreen : Colors.redAccent,
        ));
      },
      // onEditGroup: null — DeviceListScreen liệt kê thiết bị PHẦN CỨNG thật (từ
      // /homes/{id}/devices), không phải Công tắc ảo (DeviceGroup) nên không có gì để "sửa
      // nhóm"; DeviceMenuHelper tự ẩn mục này khi callback null (đúng hành vi Dashboard).
      onDelete: () => _deleteDeviceAndRefresh(mac),
    );
  }

  /// Đổi tên — NGUYÊN VĂN logic `_showRenameDialog` của Dashboard (cùng gọi
  /// `ApiService().renameDeviceEndpoint`), chỉ khác nơi refresh list sau khi lưu.
  /// [LƯU Ý] Dùng endpoint rỗng — đúng cho thiết bị 1 kênh (SSW01/quạt/Hub); thiết bị NHIỀU
  /// kênh (SSW04 4 relay) danh sách này đang hiển thị Ở CẤP THIẾT BỊ nên đổi tên áp dụng cho
  /// endpoint mặc định, KHÔNG đổi từng kênh riêng — giống hạn chế hiện có của trang này với
  /// mọi thao tác khác (Dashboard mới có UI chọn đúng từng kênh).
  void _showRenameDialog(String mac, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên thiết bị', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nhập tên mới (để trống = tên tự động)...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _tkGreen),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ApiService().renameDeviceEndpoint(mac, '', controller.text.trim());
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? 'Đã lưu tên mới: ${controller.text.trim().isEmpty ? "(tên tự động)" : controller.text.trim()}' : 'Không thể lưu tên — kiểm tra kết nối!'),
                backgroundColor: ok ? _tkGreen : Colors.redAccent,
              ));
              if (ok) _fetchDevices();
            },
            child: const Text('Lưu thay đổi', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Xóa — NGUYÊN VĂN logic `_deleteDevice` của Dashboard (cùng gọi
  /// `DeviceProvider.deleteDevice`); DeviceMenuHelper đã tự lo hộp xác nhận trước khi gọi tới.
  Future<void> _deleteDeviceAndRefresh(String mac) async {
    final bool ok = await context.read<DeviceProvider>().deleteDevice(mac);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Đã xóa thiết bị thành công!' : 'Không thể xóa thiết bị — kiểm tra kết nối hoặc quyền tài khoản!'),
      backgroundColor: ok ? _tkGreen : Colors.redAccent,
    ));
    if (ok) _fetchDevices();
  }

  List<DeviceListItem> get _filteredDevices {
    if (_searchQuery.isEmpty) return _devices;
    return _devices.where((d) {
      return d.name.toLowerCase().contains(_searchQuery) || d.mac.toLowerCase().contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final devices = _filteredDevices;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBreadcrumb(textMain, textSub),
              const SizedBox(height: 20),
              _buildHeader(textMain, textSub),
              const SizedBox(height: 18),
              _buildSearchField(isDark, textMain, textSub),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _tkGreen))
                    : devices.isEmpty
                        ? _buildEmptyState(isDark, textSub)
                        : RefreshIndicator(
                            color: _tkGreen,
                            onRefresh: _fetchDevices,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: devices.length,
                              itemBuilder: (context, index) => _buildDeviceCard(devices[index], isDark, textMain, textSub),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await showDialog(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.6),
            builder: (context) => AddDeviceDialog(),
          );
          if (result != null) {
            if (result == true) {
              _fetchDevices();
            } else if (result is String && result.isNotEmpty) {
              _linkDeviceToHome(result);
            }
          }
        },
        backgroundColor: _tkGreen,
        icon: const Icon(Icons.add_link_rounded, color: Colors.white),
        label: const Text("Khai báo Hub/Device", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBreadcrumb(Color textMain, Color textSub) {
    return Row(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onBack,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_rounded, size: 18, color: textSub),
                  const SizedBox(width: 6),
                  Text('Quản lý Nhà', style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: textSub.withValues(alpha: 0.6)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(_homeName, style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: textSub.withValues(alpha: 0.6)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text('Thiết bị', style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildHeader(Color textMain, Color textSub) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Thiết bị', style: TextStyle(color: textMain, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(_homeName, style: TextStyle(color: textSub, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(bool isDark, Color textMain, Color textSub) {
    return TextField(
      controller: _searchCtrl,
      style: TextStyle(color: textMain, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Tìm theo Tên hoặc MAC...',
        hintStyle: TextStyle(color: textSub),
        prefixIcon: Icon(Icons.search_rounded, color: textSub, size: 22),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(icon: Icon(Icons.close_rounded, color: textSub, size: 18), onPressed: () => _searchCtrl.clear()),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textSub) {
    final bool searching = _searchQuery.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(searching ? Icons.search_off_rounded : Icons.router_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            searching ? 'Không tìm thấy thiết bị khớp "$_searchQuery"' : 'Nhà này chưa có thiết bị/Hub nào được khai báo.',
            style: TextStyle(color: textSub),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(DeviceListItem device, bool isDark, Color textMain, Color textSub) {
    final bool isOnline = device.isOnline;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
        boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: isOnline ? _tkGreen.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2), shape: BoxShape.circle),
          child: Icon(Icons.router_rounded, color: isOnline ? _tkGreen : Colors.grey),
        ),
        title: Text(device.name, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
        // [DẤU CHẤM TRẠNG THÁI] Online: xanh sáng + BoxShadow tỏa quầng (cảm giác đèn LED thật
        // đang sáng). Offline: xám, KHÔNG bóng đổ — dẹt hẳn, không gây hiểu nhầm là còn sống.
        // Row căn `CrossAxisAlignment.center` (mặc định) nên chấm và text MAC luôn ngang tâm
        // nhau bất kể font MAC (monospace) cao thấp khác chấm tròn 8px.
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? Colors.greenAccent.shade400 : Colors.grey.shade400,
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: Colors.greenAccent.shade400.withValues(alpha: 0.7),
                            blurRadius: 6,
                            spreadRadius: 1.5,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                device.mac.isEmpty ? 'UNKNOWN_MAC' : device.mac,
                style: TextStyle(color: textSub, fontSize: 12, fontFamily: 'monospace', height: 1.0),
              ),
            ],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.settings_outlined, color: textSub),
          tooltip: 'Cài đặt thiết bị',
          onPressed: () => _showDeviceSettingsMenu(device),
        ),
      ),
    );
  }
}
