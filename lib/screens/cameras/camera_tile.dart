import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/camera_entry.dart';
import 'camera_single_fullscreen_screen.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [ĐẬP BỎ UI CAMERA — Ô CAMERA DUY NHẤT] Thay THẲNG CameraPreviewCard (RTSP) + ImouPreviewCard
/// (Imou) — dùng chung [CameraEntry.resolvePreviewUrl] nên KHÔNG cần biết loại camera cụ thể.
///
/// [SỬA THEO YÊU CẦU — chạm mở popup thay vì overlay tại chỗ] Chạm (tap) MỘT LẦN -> mở
/// [showCameraTilePopup] (khôi phục tinh thần "cấp 2" cũ — video lớn hơn + PTZ (Imou) + 3 icon
/// Cài đặt/Xem lại/Đàm thoại trên thanh tiêu đề của popup, KHÔNG còn overlay tự ẩn ngay tại ô nhỏ
/// nữa). Chạm ĐÚP (double tap) -> phóng to nhanh luồng xem trước tại chỗ (Transform.scale 1x/2x),
/// không rời khỏi lưới.
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
  bool _zoomedIn = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (kDebugMode) print('❌ [CameraTile ${widget.entry.id}] player error: $e');
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
    if (kDebugMode) print('📷 [CameraTile ${widget.entry.id}] resolvePreviewUrl -> "$url"');
    if (!mounted) return;
    if (url.isEmpty) {
      setState(() { _loading = false; _errorMessage = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    await _player.open(Media(url));
    await _player.setVolume(0);
    if (mounted) setState(() => _loading = false);
  }

  void _openFullscreen() {
    openCameraSingleFullscreen(
      context,
      entry: widget.entry,
      onOpenSettings: () => widget.onOpenSettings?.call(),
      onOpenRecords: () => widget.onOpenRecords?.call(),
      onOpenTalk: () => widget.onOpenTalk?.call(),
    );
  }

  @override
  void dispose() {
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
          onTap: _openFullscreen,
          onDoubleTap: () => setState(() => _zoomedIn = !_zoomedIn),
          child: Container(
            color: isDark ? Colors.black45 : Colors.grey.shade300,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: _tkGreen, strokeWidth: 2))
                else if (_errorMessage != null)
                  _buildErrorState(textSub)
                else
                  ClipRect(
                    child: AnimatedScale(
                      scale: _zoomedIn ? 2.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      // [TRÀN FULL KHUNG] BoxFit.cover — video LUÔN lấp đầy toàn bộ ô, cắt bớt
                      // rìa dư thay vì để trống viền (trước đây mặc định contain gây "video như
                      // trôi nổi giữa khung", đúng phàn nàn user).
                      child: Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.cover),
                    ),
                  ),
                // Nhãn tên camera — LUÔN hiện, user biết đang xem camera nào ngay cả ở ô nhỏ nhất
                // (lưới 3x3).
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(4)),
                      child: Text(widget.entry.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Widget _buildErrorState(Color textSub) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded, color: textSub, size: 28),
          const SizedBox(height: 6),
          Text('Không kết nối được', style: TextStyle(color: textSub, fontSize: 11), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          // [FIX — xóa được camera ngay cả khi lỗi] Chạm vùng này vẫn kích _openFullscreen() của
          // GestureDetector cha (không có onTap riêng ở đây) -> vẫn mở được trang toàn màn hình ->
          // Cài đặt -> Xóa, dù camera đang báo lỗi kết nối. Nút "Thử lại" bên dưới tách riêng để
          // không mở nhầm khi chỉ muốn thử kết nối lại.
          InkWell(onTap: _openStream, child: Text('Thử lại', style: TextStyle(color: _tkGreen, fontSize: 11, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
