import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [TUYA CLOUD-TO-CLOUD — LIÊN KẾT TÀI KHOẢN] Mở trang đăng nhập Tuya/Smart Life qua trình duyệt
/// NGOÀI (url_launcher, KHÔNG phải WebView trong App) — redirect_uri là 1 URL Backend thật
/// (GET /api/tuya/oauth-callback), Tuya redirect thẳng tới đó nên trình duyệt ngoài xử lý được
/// trọn vẹn, App không cần bắt navigation.
///
/// [TÍN HIỆU HOÀN TẤT — POLLING, KHÔNG PHẢI MQTT] Sau khi mở trình duyệt, màn này tự POLL
/// GET .../tuya/link-status mỗi 2s (cùng khuôn _startAPDetection() ở add_device_dialog.dart) để
/// biết Backend đã lưu liên kết xong chưa — KHÔNG dùng MQTT cho tín hiệu 1 lần này vì topic
/// "smarthub/{home}/tuya/..." không khớp shape "{home}/{mac}/{suffix}" mà bộ định tuyến MQTT
/// phía App (device_provider.dart updateDeviceStateFromMQTT) đang giả định cho MỌI topic nhận
/// được — thêm 1 nhánh đặc biệt ở đó rủi ro cao hơn nhiều so với 1 endpoint GET nhẹ.
///
/// [ĐIỀU KHIỂN/HIỂN THỊ THIẾT BỊ TUYA] KHÔNG cần code Flutter riêng — sau khi Đồng bộ, thiết bị
/// Tuya xuất hiện NGAY trong dashboard-sync hiện có (Backend gắn qua repository.LinkDeviceAtomic,
/// cùng home_devices:{homeID} với thiết bị vật lý) và điều khiển được NGAY qua publishCommand()
/// có sẵn (mqtt_service.dart) — Backend tự định tuyến sang Tuya OpenAPI ở broker.go.
class TuyaLinkScreen extends StatefulWidget {
  final String homeId;
  const TuyaLinkScreen({super.key, required this.homeId});

  @override
  State<TuyaLinkScreen> createState() => _TuyaLinkScreenState();
}

enum _Phase { loading, notLinked, waitingBrowser, linked }

class _TuyaLinkScreenState extends State<TuyaLinkScreen> {
  final ApiService _api = ApiService();
  _Phase _phase = _Phase.loading;
  Timer? _pollTimer;
  int _pollElapsedSeconds = 0;
  static const int _pollTimeoutSeconds = 300; // 5 phút — đủ để user đăng nhập xong trên trình duyệt

  int? _syncedCount;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final linked = await _api.getTuyaLinkStatus(widget.homeId);
    if (!mounted) return;
    setState(() => _phase = (linked == true) ? _Phase.linked : _Phase.notLinked);
  }

  Future<void> _startLink() async {
    final result = await _api.getTuyaLinkURL(widget.homeId);
    if (!mounted) return;
    if (result.url == null || result.url!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Không lấy được URL liên kết Tuya'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    final uri = Uri.tryParse(result.url!);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không mở được trình duyệt — kiểm tra lại URL liên kết Tuya'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() {
      _phase = _Phase.waitingBrowser;
      _pollElapsedSeconds = 0;
    });
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    _pollElapsedSeconds += 2;
    final linked = await _api.getTuyaLinkStatus(widget.homeId);
    if (!mounted) return;

    if (linked == true) {
      _pollTimer?.cancel();
      setState(() => _phase = _Phase.linked);
      await _sync(showSnackbar: false);
      return;
    }

    if (_pollElapsedSeconds >= _pollTimeoutSeconds) {
      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() => _phase = _Phase.notLinked);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Hết thời gian chờ — nếu bạn đã đăng nhập xong trên trình duyệt, thử bấm Liên kết lại'),
        backgroundColor: Colors.orange,
      ));
    }
  }

  void _cancelWaiting() {
    _pollTimer?.cancel();
    setState(() => _phase = _Phase.notLinked);
  }

  Future<void> _sync({bool showSnackbar = true}) async {
    final result = await _api.syncTuyaDevices(widget.homeId);
    if (!mounted) return;
    if (result.count != null) {
      setState(() => _syncedCount = result.count);
      if (showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã đồng bộ ${result.count} thiết bị Tuya')));
      }
    } else if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Lỗi đồng bộ'), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _unlink() async {
    final bool ok = await _api.unlinkTuya(widget.homeId);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _phase = _Phase.notLinked;
        _syncedCount = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hủy liên kết thất bại'), backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: const Text('Liên kết Tuya / Smart Life'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildBody(isDark, textMain, textSub),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark, Color textMain, Color textSub) {
    switch (_phase) {
      case _Phase.loading:
        return const CircularProgressIndicator(color: _tkGreen);

      case _Phase.notLinked:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_queue_rounded, color: _tkGreen, size: 56),
            const SizedBox(height: 16),
            Text('Chưa liên kết tài khoản Tuya', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Liên kết để đồng bộ và điều khiển thiết bị Tuya/Smart Life ngay trong Dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSub, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startLink,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Liên kết tài khoản Tuya'),
              style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
            ),
          ],
        );

      case _Phase.waitingBrowser:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _tkGreen),
            const SizedBox(height: 20),
            Text('Đang chờ bạn hoàn tất đăng nhập trên trình duyệt...', textAlign: TextAlign.center, style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Quay lại App sau khi đăng nhập/ủy quyền xong.', style: TextStyle(color: textSub, fontSize: 12)),
            const SizedBox(height: 20),
            TextButton(onPressed: _cancelWaiting, child: const Text('Hủy')),
          ],
        );

      case _Phase.linked:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: _tkGreen, size: 56),
            const SizedBox(height: 16),
            Text('Đã liên kết Tuya thành công', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
            if (_syncedCount != null) ...[
              const SizedBox(height: 8),
              Text('Đã đồng bộ $_syncedCount thiết bị', style: TextStyle(color: textSub, fontSize: 13)),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _sync(),
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Đồng bộ lại thiết bị'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _unlink,
              child: const Text('Hủy liên kết', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
    }
  }
}
