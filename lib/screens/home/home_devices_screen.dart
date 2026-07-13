import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../devices/add_device_dialog.dart'; 
import '../../services/auth_service.dart';

class HomeDevicesScreen extends StatefulWidget {
  final Map<String, dynamic> homeData;
  const HomeDevicesScreen({super.key, required this.homeData});

  @override
  State<HomeDevicesScreen> createState() => _HomeDevicesScreenState();
}

class _HomeDevicesScreenState extends State<HomeDevicesScreen> {
  final Color tkGreen = const Color(0xFF00A651);
  final String baseUrl = "https://api.iot-smart.vn/api"; 
  
  bool _isLoading = true;
  List<dynamic> _devices = []; 

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  // =======================================================================
  // 1. TẢI DANH SÁCH THIẾT BỊ TỪ SERVER
  // =======================================================================
  Future<void> _fetchDevices() async {
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getToken();
      final homeId = widget.homeData['home_id'];
      
      final response = await http.get(
        Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId.toString())}/devices'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _devices = jsonDecode(response.body);
            _isLoading = false;
          });
        }
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

  // =======================================================================
  // 2. LIÊN KẾT THIẾT BỊ VÀO NHÀ
  // =======================================================================
  Future<void> _linkDeviceToHome(String macAddress) async {
    // Hiện loading chờ
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF00A651))));

    try {
      final token = await AuthService().getToken();
      final homeId = widget.homeData['home_id'];

      final response = await http.post(
        Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId.toString())}/devices'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({"mac_address": macAddress}),
      );

      // Đóng loading (guard mounted TRƯỚC mọi lần đụng context sau await)
      if (!mounted) return;
      Navigator.pop(context);

      final resData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resData['message'] ?? 'Thêm thiết bị thành công!'), backgroundColor: tkGreen));
        _fetchDevices(); // Tải lại danh sách
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resData['error'] ?? 'Lỗi khi thêm thiết bị'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quản lý Thiết bị', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textMain)),
            Text(widget.homeData['home_name'], style: TextStyle(fontSize: 12, color: textSub)),
          ],
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A651)))
        : _devices.isEmpty 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.router_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text("Nhà này chưa có thiết bị/Hub nào được khai báo.", style: TextStyle(color: textSub)),
                ],
              )
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                return _buildDeviceCard(device, isDark, textMain, textSub);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Mở Popup Quét QR / Nhập MAC
          final result = await showDialog(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.6),
            builder: (context) => AddDeviceDialog(), 
          );
          
          // XỬ LÝ KẾT QUẢ TỪ DIALOG
          if (result != null) {
            if (result == true) {
              // Trường hợp Dialog tự gọi API thành công và trả về true
              _fetchDevices();
            } else if (result is String && result.isNotEmpty) {
              // Trường hợp Dialog trả về chuỗi MAC Address
              _linkDeviceToHome(result);
            }
          }
        },
        backgroundColor: tkGreen,
        icon: const Icon(Icons.add_link_rounded, color: Colors.white),
        label: const Text("Khai báo Hub/Device", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // =======================================================================
  // WIDGET: THẺ HIỂN THỊ THIẾT BỊ ĐẸP MẮT
  // =======================================================================
  Widget _buildDeviceCard(Map<String, dynamic> device, bool isDark, Color textMain, Color textSub) {
    bool isOnline = device['status'] == 'ONLINE';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isOnline ? tkGreen.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.router_rounded, 
            color: isOnline ? tkGreen : Colors.grey,
          ),
        ),
        title: Text(device['name'] ?? 'Thiết bị không tên', style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: isOnline ? tkGreen : Colors.grey),
              ),
              const SizedBox(width: 6),
              Text(device['mac_address'] ?? 'UNKNOWN_MAC', style: TextStyle(color: textSub, fontSize: 12, fontFamily: 'monospace')),
            ],
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.grey),
          onPressed: () {
            // Chức năng cài đặt thiết bị (đổi tên, xóa...) sẽ làm sau
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sẽ mở trang cài đặt cho MAC: ${device['mac_address']}'), backgroundColor: tkGreen));
          },
        ),
      ),
    );
  }
}