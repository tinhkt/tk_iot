import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/imou_camera_model.dart';
import '../../services/api_service.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [CAMERA P2P — IMOU, PHA 2 — PLAYER THẬT] Thay `imou_camera_placeholder_card.dart` (Pha 1,
/// chỉ hiện tên+badge). PHÁT HIỆN KIẾN TRÚC (xem giai-doan-136 mục Imou P2P): `getLiveStreamInfo`
/// trả THẲNG URL "hls" phát được — KHÔNG cần SDK gốc/Platform Channel như thiết kế Pha 2 ban đầu
/// giả định. Dùng NGUYÊN media_kit — cùng thư viện đã tích hợp cho camera RTSP (Giai đoạn 136).
///
/// [KHÁC RTSP] `CameraModel.rtspUrl` biết TRƯỚC (App tự ghép sẵn) — Imou phải GỌI API mỗi lần mở
/// xem để lấy URL HLS mới (`ApiService.getImouLiveURL`, ngắn hạn, không cache) — nên widget này
/// có thêm state "đang tải URL" trước khi mở Player, khác CameraPreviewCard.
class ImouPreviewCard extends StatefulWidget {
  final String homeId;
  final ImouCameraModel camera;
  final VoidCallback? onMaximize;
  final VoidCallback? onFullscreen;

  const ImouPreviewCard({super.key, required this.homeId, required this.camera, this.onMaximize, this.onFullscreen});

  @override
  State<ImouPreviewCard> createState() => _ImouPreviewCardState();
}

class _ImouPreviewCardState extends State<ImouPreviewCard> {
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  String? _errorMessage;

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

  Future<void> _openStream() async {
    setState(() { _loading = true; _errorMessage = null; });
    final result = await ApiService().getImouLiveURL(widget.homeId, widget.camera.id);
    if (!mounted) return;

    // Ưu tiên luồng phụ cho khung xem trước (nhẹ hơn) — CameraModel.previewUrl (RTSP) đã dùng
    // đúng nguyên tắc này, Imou lặp lại cùng ý tưởng dù không dùng chung field.
    final String url = (result?.subHlsUrl.isNotEmpty ?? false) ? result!.subHlsUrl : (result?.hlsUrl ?? '');
    if (url.isEmpty) {
      setState(() { _loading = false; _errorMessage = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    _player.open(Media(url));
    _player.setVolume(0); // Khung xem trước LUÔN câm, cùng quy ước CameraPreviewCard (RTSP).
    setState(() => _loading = false);
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
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _tkGreen, strokeWidth: 2))
                : _errorMessage != null
                    ? _buildErrorState(textSub)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Video(controller: _controller, controls: NoVideoControls),
                          Positioned(
                            left: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(4)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.cloud_queue_rounded, color: Colors.white, size: 10),
                                const SizedBox(width: 3),
                                Text(widget.camera.name, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
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
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, color: Colors.white, size: 16)),
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
          InkWell(onTap: _openStream, child: Text('Thử lại', style: TextStyle(color: _tkGreen, fontSize: 11, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}

/// [TOÀN MÀN HÌNH — cấp 3/3] Phát luồng CHÍNH (hls_url) — cùng cơ chế ép xoay ngang/immersive đã
/// xác nhận an toàn cho camera RTSP (Giai đoạn 136, xem camera_player_card.dart).
class ImouCameraFullscreenScreen extends StatefulWidget {
  final String homeId;
  final ImouCameraModel camera;
  const ImouCameraFullscreenScreen({super.key, required this.homeId, required this.camera});

  @override
  State<ImouCameraFullscreenScreen> createState() => _ImouCameraFullscreenScreenState();
}

class _ImouCameraFullscreenScreenState extends State<ImouCameraFullscreenScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  String? _errorMessage;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _player = Player();
    _controller = VideoController(_player);
    _player.stream.error.listen((e) {
      if (mounted) setState(() { _errorMessage = e; _loading = false; });
    });
    _openStream();
  }

  Future<void> _openStream() async {
    setState(() { _loading = true; _errorMessage = null; });
    final result = await ApiService().getImouLiveURL(widget.homeId, widget.camera.id);
    if (!mounted) return;
    if (result == null || result.hlsUrl.isEmpty) {
      setState(() { _loading = false; _errorMessage = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    _player.open(Media(result.hlsUrl));
    setState(() => _loading = false);
  }

  @override
  void dispose() {
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
              child: _loading
                  ? const CircularProgressIndicator(color: _tkGreen)
                  : _errorMessage != null
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
              child: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
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
