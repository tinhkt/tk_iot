import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [TUYA CLOUD-TO-CLOUD — ĐÃ ĐỔI KIẾN TRÚC] Ban đầu thiết kế OAuth "Link App Account" (mở trình
/// duyệt ngoài đăng nhập + poll trạng thái) — sau khi xác nhận project Cloud loại "Custom
/// Development" của user KHÔNG hỗ trợ tính năng này (chỉ loại "Smart Home PaaS" mới có, cơ chế
/// QR code thủ công trong console chứ không phải API tự động cho từng user) — ĐỔI sang mô hình
/// đơn giản hơn: 1 tài khoản Tuya/Smart Life CHUNG cho cả hệ thống (cấu hình ở Backend .env,
/// TUYA_ACCOUNT_USERNAME/PASSWORD), App chỉ cần bấm "Đồng bộ" — không còn màn liên kết/trình
/// duyệt/chờ nào cả.
class TuyaLinkScreen extends StatefulWidget {
  final String homeId;
  const TuyaLinkScreen({super.key, required this.homeId});

  @override
  State<TuyaLinkScreen> createState() => _TuyaLinkScreenState();
}

class _TuyaLinkScreenState extends State<TuyaLinkScreen> {
  bool _syncing = false;
  int? _lastSyncedCount;
  String? _errorMessage;

  Future<void> _sync() async {
    setState(() { _syncing = true; _errorMessage = null; });
    final result = await ApiService().syncTuyaDevices(widget.homeId);
    if (!mounted) return;
    setState(() {
      _syncing = false;
      if (result.count != null) {
        _lastSyncedCount = result.count;
      } else {
        _errorMessage = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: const Text('Đồng bộ Tuya / Smart Life'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_sync_rounded, color: _tkGreen, size: 56),
                const SizedBox(height: 16),
                Text('Đồng bộ thiết bị Tuya', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Hệ thống dùng chung 1 tài khoản Tuya/Smart Life — bấm Đồng bộ để kéo toàn bộ thiết bị trong tài khoản đó vào nhà này.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSub, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync_rounded),
                  label: Text(_syncing ? 'Đang đồng bộ...' : 'Đồng bộ thiết bị Tuya'),
                  style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                ),
                if (_lastSyncedCount != null) ...[
                  const SizedBox(height: 16),
                  Text('Đã đồng bộ $_lastSyncedCount thiết bị', style: TextStyle(color: _tkGreen, fontWeight: FontWeight.w600)),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
