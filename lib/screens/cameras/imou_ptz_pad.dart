import 'package:flutter/material.dart';

import '../../services/api_service.dart';

/// [DÙNG CHUNG — trước đây trùng lặp giữa imou_camera_settings_screen.dart VÀ
/// imou_camera_enlarged_dialog.dart (đã xóa)] PTZ THẬT (không phải D-pad placeholder) — nhấn giữ
/// = xoay liên tục (gọi lại mỗi 400ms), nhả ra = "STOP" ngay — KHÔNG chỉ dựa vào duration_ms tự
/// hết hạn phía camera (an toàn 2 lớp). direction PHẢI khớp ĐÚNG ptzOperations phía Go
/// (internal/imou/settings.go) — "UP"/"DOWN"/"LEFT"/"RIGHT"/"ZOOM_IN"/"ZOOM_OUT".
class ImouPtzPad extends StatefulWidget {
  final String homeId;
  final int cameraId;
  const ImouPtzPad({super.key, required this.homeId, required this.cameraId});

  @override
  State<ImouPtzPad> createState() => _ImouPtzPadState();
}

class _ImouPtzPadState extends State<ImouPtzPad> {
  final ApiService _api = ApiService();
  bool _ptzHolding = false;

  Future<void> _ptzStart(String direction) async {
    if (_ptzHolding) return;
    _ptzHolding = true;
    while (_ptzHolding) {
      await _api.controlImouPTZ(widget.homeId, widget.cameraId, direction, durationMs: 500);
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  void _ptzStop(String direction) {
    if (!_ptzHolding) return;
    _ptzHolding = false;
    _api.controlImouPTZ(widget.homeId, widget.cameraId, 'STOP');
  }

  // [FIX — RÀ SOÁT HIỆU NĂNG, Ưu tiên 1] _ptzStart() là vòng while chạy async ĐỘC LẬP vòng đời
  // widget — trước đây CHỈ _ptzStop() (gọi từ onTapUp/onTapCancel) mới hạ được _ptzHolding. Nếu
  // widget bị dispose (màn hình bị pop) trong lúc đang giữ nút mà 2 callback đó không kịp bắn ra,
  // vòng lặp chạy MÃI MÃI sau khi widget đã chết — spam API PTZ ra Imou Cloud mỗi 400ms vô thời
  // hạn. dispose() là lưới an toàn CUỐI CÙNG, độc lập với gesture, luôn chạy khi widget bị huỷ dù
  // vì lý do gì (pop, đổi cây widget cha, hot reload...).
  @override
  void dispose() {
    if (_ptzHolding) {
      _ptzHolding = false;
      _api.controlImouPTZ(widget.homeId, widget.cameraId, 'STOP');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);
    final Color icon = isDark ? Colors.white70 : const Color(0xFF334155);

    Widget dirButton(IconData iconData, String direction) {
      return GestureDetector(
        onTapDown: (_) => _ptzStart(direction),
        onTapUp: (_) => _ptzStop(direction),
        onTapCancel: () => _ptzStop(direction),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Icon(iconData, color: icon, size: 20),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dirButton(Icons.keyboard_arrow_up_rounded, 'UP'),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dirButton(Icons.keyboard_arrow_left_rounded, 'LEFT'),
            const SizedBox(width: 4),
            Container(width: 40, height: 40, alignment: Alignment.center, child: Icon(Icons.videocam_rounded, color: icon.withValues(alpha: 0.4), size: 16)),
            const SizedBox(width: 4),
            dirButton(Icons.keyboard_arrow_right_rounded, 'RIGHT'),
          ],
        ),
        const SizedBox(height: 4),
        dirButton(Icons.keyboard_arrow_down_rounded, 'DOWN'),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dirButton(Icons.zoom_in_rounded, 'ZOOM_IN'),
            const SizedBox(width: 8),
            dirButton(Icons.zoom_out_rounded, 'ZOOM_OUT'),
          ],
        ),
      ],
    );
  }
}
