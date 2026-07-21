import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_ui_wrappers.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [ĐẨY THÔNG BÁO OS — CÀI ĐẶT] Cho phép người dùng bật/tắt TỪNG loại thông báo muốn nhận
/// đẩy (khớp đúng 4 category Backend đã dùng — xem push.AllCategories, internal/push/prefs.go).
/// Không có màn "Cài đặt" độc lập trong app này — mở từ 1 mục trong panel Cài đặt nhúng
/// trong dashboard_screen.dart (_buildMobileSettingsView).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final AuthService _auth = AuthService();
  Map<String, bool> _prefs = {'DEVICE': true, 'ALERT': true, 'OTA_UPDATE': true, 'SYSTEM': true};
  bool _pushConfigured = true;
  bool _loading = true;

  // [KHỚP CATEGORY BACKEND] Đúng 4 giá trị notif["type"] đã dùng xuyên suốt hệ thống (xem
  // internal/mqtt/notify.go) — nhãn tiếng Việt dễ hiểu cho người dùng, không phải tên kỹ thuật.
  static const Map<String, String> _labels = {
    'DEVICE': 'Thiết bị trực tuyến trở lại',
    'ALERT': 'Thiết bị ngoại tuyến (quan trọng)',
    'OTA_UPDATE': 'Có bản cập nhật firmware (hàng loạt)',
    'SYSTEM': 'Có bản cập nhật firmware (theo thiết bị)',
  };
  static const Map<String, IconData> _icons = {
    'DEVICE': Icons.power_off_outlined,
    'ALERT': Icons.warning_amber_rounded,
    'OTA_UPDATE': Icons.system_update_alt_rounded,
    'SYSTEM': Icons.system_security_update_good_rounded,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _auth.getNotificationPreferences();
    if (!mounted) return;
    if (data != null) {
      setState(() {
        final rawPrefs = data['preferences'];
        if (rawPrefs is Map) {
          _prefs = rawPrefs.map((k, v) => MapEntry(k.toString(), v == true));
        }
        _pushConfigured = data['push_configured'] != false;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String category, bool value) async {
    final bool previous = _prefs[category] ?? true;
    setState(() => _prefs[category] = value); // optimistic — cùng phong cách NotificationProvider
    final bool ok = await _auth.setNotificationPreference(category, value);
    if (!ok && mounted) setState(() => _prefs[category] = previous); // rollback nếu Backend lỗi
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: const Text('Cài đặt thông báo'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _tkGreen))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_pushConfigured)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppContainer(
                        color: Colors.orange.withValues(alpha: 0.12),
                        child: Row(children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Máy chủ chưa bật đẩy thông báo hệ thống — bạn vẫn nhận chuông trong ứng dụng như bình thường.',
                              style: TextStyle(color: isDark ? Colors.orange.shade200 : Colors.orange.shade800, fontSize: 12.5),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      'Chọn loại thông báo bạn muốn nhận đẩy lên màn hình khóa/khay thông báo — chuông trong ứng dụng luôn nhận đủ mọi loại.',
                      style: TextStyle(color: textSub, fontSize: 12.5),
                    ),
                  ),
                  AppContainer(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final entry in _labels.entries) ...[
                          if (entry.key != _labels.keys.first) Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                          SwitchListTile(
                            secondary: Icon(_icons[entry.key], color: (_prefs[entry.key] ?? true) ? _tkGreen : textSub),
                            title: Text(entry.value, style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                            value: _prefs[entry.key] ?? true,
                            activeThumbColor: _tkGreen,
                            onChanged: (v) => _toggle(entry.key, v),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
