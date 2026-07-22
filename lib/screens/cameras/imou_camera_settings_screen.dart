import 'package:flutter/material.dart';

import '../../models/imou_camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import 'imou_ptz_pad.dart';

const Color _tkGreen = Color(0xFF00A651);

// [ĐÃ XÁC NHẬN QUA TÀI LIỆU — KHÔNG PHẢI ĐOÁN] Nhãn tiếng Việt cho các giá trị "mode" hồng ngoại
// thật (getNightVisionMode.data.modes) — camera chỉ hiện ĐÚNG tập con nó hỗ trợ, không hiện cứng
// cả 6 cho mọi camera.
const Map<String, String> _nightVisionLabels = {
  'Intelligent': 'Thông minh (tự động)',
  'FullColor': 'Toàn thời gian màu',
  'Infrared': 'Hồng ngoại (đen trắng)',
  'Off': 'Tắt',
  'LowLight': 'Ánh sáng yếu',
  'SmartLowLight': 'Ánh sáng yếu thông minh',
};

/// [CÀI ĐẶT ĐẦY ĐỦ CAMERA IMOU] Toàn bộ field/endpoint đã xác nhận qua tài liệu chính thức +
/// đọc thẳng mã nguồn thư viện tham chiếu github.com/user2684/imouapi (nền tích hợp Home
/// Assistant CHÍNH THỨC của Imou) — KHÔNG có mục nào đoán mò.
class ImouCameraSettingsScreen extends StatefulWidget {
  final String homeId;
  final ImouCameraModel camera;
  const ImouCameraSettingsScreen({super.key, required this.homeId, required this.camera});

  @override
  State<ImouCameraSettingsScreen> createState() => _ImouCameraSettingsScreenState();
}

class _ImouCameraSettingsScreenState extends State<ImouCameraSettingsScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  Map<String, dynamic> _data = {};
  bool _restarting = false;

  // Optimistic local state cho toggle/slider — tách khỏi _data để UI phản hồi tức thì.
  bool _privacy = false;
  String _nightVisionMode = '';
  List<String> _nightVisionOptions = [];
  double _sensitivity = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _api.getImouCameraSettings(widget.homeId, widget.camera.id);
    if (!mounted) return;
    if (data != null) {
      setState(() {
        _data = data;
        _privacy = data['privacy_mode'] == true;
        _nightVisionMode = (data['night_vision_mode'] ?? '').toString();
        _nightVisionOptions = ((data['night_vision_options'] as List?) ?? []).map((e) => e.toString()).toList();
        final sensRaw = double.tryParse((data['motion_sensitivity'] ?? '').toString());
        if (sensRaw != null) _sensitivity = sensRaw.clamp(0, 100);
      });
    }
    setState(() => _loading = false);
  }

  Future<void> _togglePrivacy(bool value) async {
    setState(() => _privacy = value);
    final ok = await _api.setImouPrivacyMode(widget.homeId, widget.camera.id, value);
    if (!ok && mounted) {
      setState(() => _privacy = !value);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi chế độ riêng tư thất bại')));
    }
  }

  Future<void> _changeNightVision(String mode) async {
    final prev = _nightVisionMode;
    setState(() => _nightVisionMode = mode);
    final ok = await _api.setImouNightVision(widget.homeId, widget.camera.id, mode);
    if (!ok && mounted) {
      setState(() => _nightVisionMode = prev);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi chế độ hồng ngoại thất bại')));
    }
  }

  Future<void> _changeSensitivity(double value) async {
    setState(() => _sensitivity = value);
  }

  Future<void> _commitSensitivity(double value) async {
    final ok = await _api.setImouMotionDetection(widget.homeId, widget.camera.id, sensitivity: value.round().toString());
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi độ nhạy chuyển động thất bại')));
    }
  }

  // [DỜI TỪ imou_camera_enlarged_dialog.dart — file đó đã xóa theo "đập bỏ UI Camera cấp 2"]
  // Nút xóa camera trước đây nằm trên thanh tiêu đề Dialog Phóng to — bị BỎ SÓT khi dời PTZ, gây
  // hiện tượng "không có cách nào gỡ camera" (báo lỗi thật từ user). Pop(true) khi xóa thành công
  // để CameraDashboardSection tự gỡ khỏi danh sách, cùng quy ước Navigator.pop trả bool đã dùng
  // cho toàn bộ luồng camera khác trong app.
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      maxWidth: 400,
      child: Builder(builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textMain = isDark ? Colors.white : const Color(0xFF0F172A);
        final textSub = isDark ? Colors.white54 : Colors.black54;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Xóa camera "${widget.camera.name}"?', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('Camera sẽ được gỡ khỏi tài khoản Imou và không còn hiện trong danh sách.', style: TextStyle(color: textSub)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Xóa ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        );
      }),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final ok = await _api.deleteImouCamera(widget.homeId, widget.camera.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xóa camera thất bại — kiểm tra kết nối và thử lại')));
    }
  }

  Future<void> _restart() async {
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      maxWidth: 380,
      child: Builder(builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final textMain = isDark ? Colors.white : const Color(0xFF0F172A);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khởi động lại camera?', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Camera sẽ mất kết nối trong ít phút.', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Khởi động lại', style: TextStyle(color: Colors.white)),
              ),
            ]),
          ],
        );
      }),
    );
    if (confirmed != true) return;

    setState(() => _restarting = true);
    final ok = await _api.restartImouCamera(widget.homeId, widget.camera.id);
    if (!mounted) return;
    setState(() => _restarting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Đã gửi lệnh khởi động lại' : 'Khởi động lại thất bại')));
  }

  // [FIX — luôn báo "Không rõ"] Test thật trên camera thật: server trả status "3" cho ngoại
  // tuyến (KHÔNG PHẢI "0" như tài liệu thư viện tham chiếu ban đầu giả định — xem
  // internal/imou/settings.go DeviceOnlineStatus) — map CẢ "0" LẪN "3" về "Ngoại tuyến" để an
  // toàn với cả 2 khả năng (có thể khác theo model/firmware camera) thay vì rơi vào default.
  String _onlineLabel(String status) {
    switch (status) {
      case '1':
        return 'Trực tuyến';
      case '4':
        return 'Ngủ đông';
      case '0':
      case '3':
        return 'Ngoại tuyến';
      default:
        return 'Không rõ';
    }
  }

  String _sdcardLabel(String status) {
    if (status.isEmpty) return 'Không có';
    return status;
  }

  String _formatBytes(num? bytes) {
    if (bytes == null || bytes <= 0) return '—';
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: Text('Cài đặt · ${widget.camera.name}'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
        actions: [
          _deleting
              ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent)))
              : IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), tooltip: 'Xóa camera', onPressed: _confirmDelete),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _tkGreen))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionLabel('Trạng thái', textSub),
                    AppContainer(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        _infoRow('Kết nối', _onlineLabel((_data['online_status'] ?? '').toString()), textMain, textSub, isDark),
                        _divider(isDark),
                        _infoRow('Thẻ nhớ SD', _sdcardLabel((_data['sdcard_status'] ?? '').toString()), textMain, textSub, isDark),
                        if ((_data['storage_total_bytes'] as num?) != null && (_data['storage_total_bytes'] as num) > 0) ...[
                          _divider(isDark),
                          _infoRow('Dung lượng', '${_formatBytes(_data['storage_used_bytes'] as num?)} / ${_formatBytes(_data['storage_total_bytes'] as num?)}', textMain, textSub, isDark),
                        ],
                        if ((_data['battery'] ?? '').toString().isNotEmpty) ...[
                          _divider(isDark),
                          _infoRow('Pin', '${_data['battery']}%', textMain, textSub, isDark),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 20),

                    _sectionLabel('Riêng tư & hình ảnh', textSub),
                    AppContainer(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        SwitchListTile(
                          secondary: Icon(_privacy ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: _privacy ? Colors.redAccent : _tkGreen),
                          title: Text('Chế độ riêng tư', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                          subtitle: Text('Tắt ống kính/luồng hình — camera ngừng ghi hình', style: TextStyle(color: textSub, fontSize: 12)),
                          value: _privacy,
                          activeThumbColor: Colors.redAccent,
                          onChanged: _togglePrivacy,
                        ),
                        if (_nightVisionOptions.isNotEmpty) ...[
                          _divider(isDark),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Chế độ hồng ngoại ban đêm', style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 14)),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final mode in _nightVisionOptions)
                                      ChoiceChip(
                                        label: Text(_nightVisionLabels[mode] ?? mode),
                                        selected: _nightVisionMode == mode,
                                        selectedColor: _tkGreen,
                                        labelStyle: TextStyle(color: _nightVisionMode == mode ? Colors.white : textMain, fontSize: 12),
                                        onSelected: (_) => _changeNightVision(mode),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 20),

                    _sectionLabel('Phát hiện chuyển động', textSub),
                    AppContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.directions_run_rounded, color: _tkGreen, size: 20),
                            const SizedBox(width: 10),
                            Text('Độ nhạy: ${_sensitivity.round()}', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                          ]),
                          Slider(
                            value: _sensitivity,
                            min: 0,
                            max: 100,
                            divisions: 20,
                            activeColor: _tkGreen,
                            label: _sensitivity.round().toString(),
                            onChanged: _changeSensitivity,
                            onChangeEnd: _commitSensitivity,
                          ),
                          Text('0 = ít nhạy nhất, 100 = nhạy nhất', style: TextStyle(color: textSub, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _sectionLabel('Điều khiển hướng (PTZ)', textSub),
                    AppContainer(child: Center(child: ImouPtzPad(homeId: widget.homeId, cameraId: widget.camera.id))),
                    const SizedBox(height: 20),

                    _sectionLabel('Vận hành', textSub),
                    AppContainer(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: _restarting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                            : const Icon(Icons.restart_alt_rounded, color: Colors.redAccent),
                        title: const Text('Khởi động lại camera', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                        onTap: _restarting ? null : _restart,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
      );

  Widget _divider(bool isDark) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12);

  Widget _infoRow(String label, String value, Color textMain, Color textSub, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: textSub, fontSize: 13)),
          Text(value, style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
