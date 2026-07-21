import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/camera_model.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [PHẦN 3 — KHUNG XEM TRƯỚC DASHBOARD] Phát [camera.previewUrl] (luồng PHỤ nếu có cấu hình,
/// tự rơi về luồng chính nếu không — xem CameraModel.previewUrl), LUÔN tắt tiếng (an ninh —
/// camera xem trước không cần âm thanh, cũng giảm tải giải mã audio không cần thiết). Bọc
/// RepaintBoundary — cùng kỹ thuật hiệu năng đã dùng cho _buildRoomTabs (dashboard_screen.dart):
/// cô lập vùng video khỏi vòng lặp vẽ lại của phần còn lại Dashboard khi cuộn/MQTT cập nhật.
///
/// [3 CẤP ĐỘ XEM] Thẻ này = cấp 1 (Thumbnail). Overlay góc trên-phải có 2 nút riêng biệt:
/// [onMaximize] mở popup Phóng to (cấp 2, xem camera_enlarged_dialog.dart — vẫn nằm giữa
/// Dashboard, không rời màn hình), [onFullscreen] mở CameraFullscreenScreen (cấp 3, route
/// riêng + ép xoay ngang). Chạm vào vùng video (ngoài 2 nút) cũng kích [onMaximize] — hành vi
/// "chạm nhanh = xem to hơn 1 chút" phổ biến ở app camera an ninh, nút Fullscreen tường minh
/// mới thật sự rời khỏi Dashboard.
///
/// [GIỚI HẠN ĐÃ BIẾT] Widget này KHÔNG tự phát hiện "đang cuộn ra khỏi màn hình" để tạm dừng
/// giải mã — chỉ giảm tải bằng luồng phụ (bitrate thấp hơn nhiều luồng chính) + RepaintBoundary.
/// Cũng KHÔNG tự tạm dừng khi popup Phóng to/Fullscreen đang mở đè lên (2-3 luồng RTSP có thể
/// cùng giải mã song song một lúc) — nếu máy yếu, cân nhắc thêm cơ chế pause/resume phối hợp ở
/// đợt sau, không âm thầm bỏ qua.
class CameraPreviewCard extends StatefulWidget {
  final CameraModel camera;
  final VoidCallback? onMaximize;
  final VoidCallback? onFullscreen;

  const CameraPreviewCard({super.key, required this.camera, this.onMaximize, this.onFullscreen});

  @override
  State<CameraPreviewCard> createState() => _CameraPreviewCardState();
}

class _CameraPreviewCardState extends State<CameraPreviewCard> {
  late final Player _player;
  late final VideoController _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _errorMessage = e);
    });
    _openStream();
  }

  void _openStream() {
    final String url = widget.camera.previewUrl;
    if (url.isEmpty) return;
    setState(() => _errorMessage = null);
    _player.open(Media(url));
    _player.setVolume(0); // Khung xem trước LUÔN câm — chỉ Fullscreen mới có âm thanh.
  }

  @override
  void didUpdateWidget(covariant CameraPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camera.previewUrl != widget.camera.previewUrl) _openStream();
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
          onTap: widget.onMaximize,
          child: Container(
            color: isDark ? Colors.black45 : Colors.grey.shade300,
            child: _errorMessage != null
                ? _buildErrorState(textSub)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(controller: _controller, controls: NoVideoControls),
                      // Nhãn tên camera góc dưới-trái, luôn hiện đè lên khung hình — người dùng
                      // biết đang xem camera nào ngay cả ở chế độ lưới 4 ô nhỏ.
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(4)),
                          child: Text(widget.camera.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      // Overlay góc trên-phải: 2 nút riêng biệt Phóng to / Toàn màn hình. Container
                      // mờ nền đen bọc chung 2 icon — tách biệt rõ với nhãn tên camera góc dưới-trái.
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildOverlayIconButton(icon: Icons.open_in_full_rounded, tooltip: 'Phóng to', onPressed: widget.onMaximize),
                              _buildOverlayIconButton(icon: Icons.fullscreen_rounded, tooltip: 'Toàn màn hình', onPressed: widget.onFullscreen),
                            ],
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

  Widget _buildOverlayIconButton({required IconData icon, required String tooltip, required VoidCallback? onPressed}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, color: Colors.white, size: 16),
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
          Text('Không kết nối được', style: TextStyle(color: textSub, fontSize: 11)),
          const SizedBox(height: 4),
          InkWell(
            onTap: _openStream,
            child: Text('Thử lại', style: TextStyle(color: _tkGreen, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// [PHẦN 3 — TOÀN MÀN HÌNH IMMERSIVE, cấp độ 3/3] Mở qua Navigator.push khi user bấm nút
/// Fullscreen (từ thẻ ngoài hoặc từ Dialog Phóng to) — phát LUỒNG CHÍNH (camera.rtspUrl, nét,
/// bitrate cao) thay vì luồng phụ ở khung xem trước. Có âm thanh (unmute mặc định) + nút đóng
/// quay lại Dashboard.
///
/// [ÉP XOAY NGANG + ẨN THANH HỆ THỐNG] `initState`/`dispose` là NƠI DUY NHẤT trong toàn bộ
/// codebase gọi `SystemChrome.setPreferredOrientations`/`setEnabledSystemUIMode` (đã grep xác
/// nhận không đâu khác dùng — không có xung đột). Đã xác nhận trước khi viết: KHÔNG có
/// `android:screenOrientation` khóa cứng trên `<activity>` trong AndroidManifest.xml (chỉ có
/// `android:configChanges` bao gồm "orientation" — nghĩa là Activity giao quyền xoay cho
/// Flutter, không tự ý chặn), và `Info.plist` (`UISupportedInterfaceOrientations`) đã khai báo
/// sẵn cả Portrait lẫn LandscapeLeft/Right nên iOS cũng không chặn. BẮT BUỘC trả về Portrait ở
/// `dispose()` — nếu quên, các màn hình khác của app (vốn chỉ thiết kế cho Portrait) sẽ vỡ giao
/// diện ngay khi người dùng bấm Back.
class CameraFullscreenScreen extends StatefulWidget {
  final CameraModel camera;
  const CameraFullscreenScreen({super.key, required this.camera});

  @override
  State<CameraFullscreenScreen> createState() => _CameraFullscreenScreenState();
}

class _CameraFullscreenScreenState extends State<CameraFullscreenScreen> {
  late final Player _player;
  late final VideoController _controller;
  String? _errorMessage;
  bool _muted = false;

  @override
  void initState() {
    super.initState();

    // Ép xoay ngang + giấu thanh trạng thái/điều hướng — CHỈ áp dụng cho riêng màn hình này,
    // PHẢI trả lại nguyên trạng ở dispose() bên dưới.
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() => _errorMessage = e);
    });
    _openStream();
  }

  void _openStream() {
    if (widget.camera.rtspUrl.isEmpty) {
      setState(() => _errorMessage = 'Camera này chưa cấu hình luồng chính (stream_path)');
      return;
    }
    setState(() => _errorMessage = null);
    _player.open(Media(widget.camera.rtspUrl));
  }

  @override
  void dispose() {
    // Trả điện thoại về portrait + hiện lại thanh hệ thống TRƯỚC KHI rời màn hình — bắt buộc,
    // nếu không toàn bộ phần còn lại của app (chỉ thiết kế cho Portrait) sẽ kẹt xoay ngang.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _errorMessage != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 40),
                        const SizedBox(height: 10),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13))),
                        const SizedBox(height: 10),
                        TextButton(onPressed: _openStream, child: const Text('Thử lại', style: TextStyle(color: _tkGreen, fontWeight: FontWeight.bold))),
                      ],
                    )
                  : Video(controller: _controller),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
                onPressed: () {
                  setState(() => _muted = !_muted);
                  _player.setVolume(_muted ? 0 : 100);
                },
              ),
            ),
            Positioned(
              top: 12,
              left: 56,
              right: 56,
              child: Text(widget.camera.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
