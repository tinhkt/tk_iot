import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/camera_entry.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [ĐẬP BỎ UI CAMERA — Ô CAMERA DUY NHẤT] Thay THẲNG CameraPreviewCard (RTSP) + ImouPreviewCard
/// (Imou) — dùng chung [CameraEntry.resolvePreviewUrl] nên KHÔNG cần biết loại camera cụ thể.
///
/// [OVERLAY CHẠM-HIỆN-RỒI-TỰ-ẨN — yêu cầu #5] Khác thẻ CŨ (overlay LUÔN hiện góc trên-phải) —
/// giờ toàn khung hình là 1 GestureDetector: chạm -> hiện overlay 3 nút (Cài đặt/Xem lại/Đàm
/// thoại) đè giữa khung hình, tự ẩn sau 3 giây (hoặc chạm lại để reset đồng hồ). KHÔNG còn nút
/// Phóng to/Fullscreen riêng trong ô — mở rộng toàn màn hình giờ là hành động CẤP TRANG (nút ở
/// header CameraDashboardSection), không phải cấp từng ô nữa.
///
/// LUÔN câm tiếng (kể cả khi dùng lại ở trang Fullscreen dạng lưới nhiều ô — nhiều luồng audio
/// chồng nhau cùng lúc sẽ hỗn loạn, đúng quy ước NVR chuyên nghiệp: lưới luôn câm, âm thanh chỉ
/// có ở tính năng Đàm thoại 2 chiều thật sự — hiện CHƯA triển khai, xem CameraEntry.hasTalk).
class CameraTile extends StatefulWidget {
  final CameraEntry entry;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenRecords;
  final VoidCallback? onOpenTalk;

  const CameraTile({super.key, required this.entry, this.onOpenSettings, this.onOpenRecords, this.onOpenTalk});

  @override
  State<CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<CameraTile> {
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  String? _errorMessage;
  bool _overlayVisible = false;
  Timer? _overlayHideTimer;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() { _errorMessage = e; _loading = false; });
    });
    _openStream();
  }

  @override
  void didUpdateWidget(covariant CameraTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) _openStream();
  }

  Future<void> _openStream() async {
    setState(() { _loading = true; _errorMessage = null; });
    final url = await widget.entry.resolvePreviewUrl();
    if (!mounted) return;
    if (url.isEmpty) {
      setState(() { _loading = false; _errorMessage = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    await _player.open(Media(url));
    await _player.setVolume(0);
    if (mounted) setState(() => _loading = false);
  }

  void _toggleOverlay() {
    _overlayHideTimer?.cancel();
    setState(() => _overlayVisible = true);
    _overlayHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  @override
  void dispose() {
    _overlayHideTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: _toggleOverlay,
          child: Container(
            color: isDark ? Colors.black45 : Colors.grey.shade300,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _tkGreen, strokeWidth: 2))
                : _errorMessage != null
                    ? _buildErrorState(textSub)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(controller: _controller, controls: NoVideoControls),
                          // Nhãn tên camera — LUÔN hiện (không phụ thuộc overlay), user biết đang
                          // xem camera nào ngay cả ở ô nhỏ nhất (lưới 3x3).
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(4)),
                              child: Text(widget.entry.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          IgnorePointer(
                            ignoring: !_overlayVisible,
                            child: AnimatedOpacity(
                              opacity: _overlayVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.35),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _overlayButton(icon: Icons.settings_rounded, tooltip: 'Cài đặt', onPressed: widget.onOpenSettings),
                                      _overlayButton(icon: Icons.play_circle_outline_rounded, tooltip: 'Xem lại', onPressed: widget.onOpenRecords),
                                      _overlayButton(icon: Icons.mic_rounded, tooltip: 'Đàm thoại', onPressed: widget.onOpenTalk),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _overlayButton({required IconData icon, required String tooltip, required VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Color textSub) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded, color: textSub, size: 28),
          const SizedBox(height: 6),
          Text('Không kết nối được', style: TextStyle(color: textSub, fontSize: 11), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          InkWell(onTap: _openStream, child: Text('Thử lại', style: TextStyle(color: _tkGreen, fontSize: 11, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
