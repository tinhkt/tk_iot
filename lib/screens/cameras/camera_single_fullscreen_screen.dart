import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/camera_entry.dart';
import 'imou_ptz_pad.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [THAY showCameraTilePopup — theo yêu cầu user] Trước đây là 1 Dialog giữa màn hình — giờ là 1
/// TRANG TOÀN MÀN HÌNH THẬT (Navigator.push, thay thế hoàn toàn màn hình hiện tại), phát luồng
/// CHÍNH (nét hơn preview), có PTZ (CHỈ Imou), 3 icon Cài đặt/Xem lại/Đàm thoại + nút thu nhỏ
/// (quay lại) + nút xoay ngang thủ công.
///
/// [XOAY MÀN HÌNH — KHÔNG ép cứng landscape như CameraFullscreenScreen/ImouCameraFullscreenScreen
/// cũ (đã xóa)] Cho phép CẢ portrait lẫn landscape ngay từ đầu — nếu máy đang bật xoay màn hình tự
/// động (OS-level auto-rotate), xoay máy sẽ tự xoay theo, ĐÚNG yêu cầu "tự động xoay nếu máy bật
/// chế độ xoay". Nút xoay thủ công (góc trên) bù cho trường hợp máy TẮT auto-rotate — ép landscape
/// ngay không cần chờ xoay máy thật, bấm lại để về portrait.
Future<void> openCameraSingleFullscreen(
  BuildContext context, {
  required CameraEntry entry,
  required VoidCallback onOpenSettings,
  required VoidCallback onOpenRecords,
  required VoidCallback onOpenTalk,
}) {
  return Navigator.push(context, MaterialPageRoute(
    builder: (_) => _CameraSingleFullscreenScreen(entry: entry, onOpenSettings: onOpenSettings, onOpenRecords: onOpenRecords, onOpenTalk: onOpenTalk),
  ));
}

class _CameraSingleFullscreenScreen extends StatefulWidget {
  final CameraEntry entry;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRecords;
  final VoidCallback onOpenTalk;
  const _CameraSingleFullscreenScreen({required this.entry, required this.onOpenSettings, required this.onOpenRecords, required this.onOpenTalk});

  @override
  State<_CameraSingleFullscreenScreen> createState() => _CameraSingleFullscreenScreenState();
}

class _CameraSingleFullscreenScreenState extends State<_CameraSingleFullscreenScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  String? _errorMessage;
  bool _forcedLandscape = false;

  @override
  void initState() {
    super.initState();
    // Cho phép CẢ 3 hướng — máy tự xoay theo cảm biến NẾU auto-rotate hệ thống đang bật (không ép
    // cứng landscape như thiết kế cũ).
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
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
    final url = await widget.entry.resolveFullUrl();
    if (!mounted) return;
    if (url.isEmpty) {
      setState(() { _loading = false; _errorMessage = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    await _player.open(Media(url));
    if (mounted) setState(() => _loading = false);
  }

  // [NÚT XOAY THỦ CÔNG] Bù cho máy đang TẮT auto-rotate hệ thống — ép landscape ngay, bấm lại để
  // quay về cho phép cả 2 hướng (không ép cứng portrait, vẫn tự xoay landscape nếu xoay máy thật).
  void _toggleManualRotate() {
    setState(() => _forcedLandscape = !_forcedLandscape);
    if (_forcedLandscape) {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp, DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  @override
  void dispose() {
    // [BẮT BUỘC] Trả về portrait-only + hiện lại thanh hệ thống trước khi rời màn hình — phần còn
    // lại của app chỉ thiết kế cho Portrait, quên bước này sẽ vỡ giao diện màn khác ngay khi Back.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isImou = widget.entry.provider == CameraProviderType.imou;
    final bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    // [NÚT THU NHỎ] Quay lại màn trước — thay nút "Đóng" của Dialog cũ.
                    IconButton(icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.white), tooltip: 'Thu nhỏ', onPressed: () => Navigator.of(context).pop()),
                    Expanded(child: Text(widget.entry.name, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    IconButton(
                      icon: Icon(isLandscape ? Icons.screen_lock_rotation_rounded : Icons.screen_rotation_rounded, color: Colors.white),
                      tooltip: 'Xoay ngang',
                      onPressed: _toggleManualRotate,
                    ),
                    IconButton(icon: const Icon(Icons.settings_rounded, color: Colors.white), tooltip: 'Cài đặt', onPressed: () { Navigator.of(context).pop(); widget.onOpenSettings(); }),
                    IconButton(icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white), tooltip: 'Xem lại', onPressed: () { Navigator.of(context).pop(); widget.onOpenRecords(); }),
                    IconButton(icon: const Icon(Icons.mic_rounded, color: Colors.white), tooltip: 'Đàm thoại', onPressed: () { Navigator.of(context).pop(); widget.onOpenTalk(); }),
                  ],
                ),
              ),
              Expanded(
                child: Center(
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
                          // [GIỮ NGUYÊN TỈ LỆ] contain — xem chi tiết 1 camera nên hiện TRỌN khung
                          // hình (khác ô lưới nhỏ dùng cover để lấp đầy) — không cắt góc nào.
                          : Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain),
                ),
              ),
              // [CHỈ IMOU] RTSP hệ thống chưa có API PTZ nào.
              if (isImou) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: ImouPtzPad(homeId: widget.entry.homeId, cameraId: widget.entry.imouCamera!.id)),
            ],
          ),
        ),
      ),
    );
  }
}
