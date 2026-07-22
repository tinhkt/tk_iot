import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/imou_camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import 'imou_camera_settings_screen.dart';
import 'imou_camera_records_screen.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [CAMERA P2P — IMOU — cấp 2/3: Phóng to] Cùng khuôn `camera_enlarged_dialog.dart` (RTSP) —
/// showAppDialog 90% width + D-pad PTZ placeholder + nút xóa trên thanh tiêu đề. Trả `true` khi
/// camera đã bị xóa (Server xác nhận) để Dashboard tự gỡ khỏi `_imouCameras`.
Future<bool> showImouCameraEnlargedDialog(BuildContext context, {required String homeId, required ImouCameraModel camera}) async {
  final double dialogWidth = MediaQuery.sizeOf(context).width * 0.9;
  final bool? deleted = await showAppDialog<bool>(
    context: context,
    maxWidth: dialogWidth,
    contentPadding: EdgeInsets.zero,
    child: _ImouCameraEnlargedDialogBody(homeId: homeId, camera: camera),
  );
  return deleted ?? false;
}

class _ImouCameraEnlargedDialogBody extends StatefulWidget {
  final String homeId;
  final ImouCameraModel camera;
  const _ImouCameraEnlargedDialogBody({required this.homeId, required this.camera});

  @override
  State<_ImouCameraEnlargedDialogBody> createState() => _ImouCameraEnlargedDialogBodyState();
}

class _ImouCameraEnlargedDialogBodyState extends State<_ImouCameraEnlargedDialogBody> {
  late final Player _player;
  late final VideoController _controller;
  bool _loading = true;
  String? _errorMessage;
  bool _deleting = false;

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
    if (result == null || result.hlsUrl.isEmpty) {
      setState(() { _loading = false; _errorMessage = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    _player.open(Media(result.hlsUrl));
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // [PTZ THẬT] Nhấn giữ = xoay liên tục (gọi lại mỗi 400ms trong lúc giữ), nhả ra = "STOP" ngay —
  // KHÔNG chỉ dựa vào duration_ms tự hết hạn phía camera (an toàn 2 lớp, cùng tinh thần các nơi
  // khác trong hệ thống không tin 1 cơ chế timeout đơn lẻ).
  bool _ptzHolding = false;

  Future<void> _ptzStart(String direction) async {
    if (_ptzHolding) return;
    _ptzHolding = true;
    while (_ptzHolding) {
      await ApiService().controlImouPTZ(widget.homeId, widget.camera.id, direction, durationMs: 500);
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  void _ptzStop(String direction) {
    if (!_ptzHolding) return;
    _ptzHolding = false;
    ApiService().controlImouPTZ(widget.homeId, widget.camera.id, 'STOP');
  }

  Future<void> _confirmDelete() async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : Colors.black54;

    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      maxWidth: 400,
      child: Builder(
        builder: (ctx) {
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
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final bool ok = await ApiService().deleteImouCamera(widget.homeId, widget.camera.id);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xóa camera thất bại — kiểm tra kết nối và thử lại')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.camera.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1E293B)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.history_rounded, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                    tooltip: 'Xem lại',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImouCameraRecordsScreen(homeId: widget.homeId, camera: widget.camera))),
                  ),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                    tooltip: 'Cài đặt',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ImouCameraSettingsScreen(homeId: widget.homeId, camera: widget.camera))),
                  ),
                  _deleting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          tooltip: 'Xóa camera',
                          onPressed: _confirmDelete,
                        ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            // [FIX — BOTTOM OVERFLOWED BY 159 PIXELS ở màn hình ngang] AspectRatio 16:9 tính chiều
            // cao THEO CHIỀU RỘNG dialog (90% màn hình) — trên màn ngang, chiều rộng lớn nên chiều
            // cao suy ra cũng lớn, cộng thêm header+PTZ pad bên dưới vượt quá chiều cao thật màn
            // hình. Bọc Flexible (KHÔNG phải Expanded — Column bên ngoài vẫn mainAxisSize.min):
            // Flexible cho phép khối video TỰ THU NHỎ vừa đúng phần chiều cao còn lại sau khi trừ
            // header/PTZ pad, thay vì luôn giữ nguyên chiều cao suy ra từ chiều rộng. AN TOÀN dùng
            // Flexible/Expanded ở đây vì Dialog (showAppDialog) luôn nhận maxHeight HỮU HẠN từ màn
            // hình thật (khác hẳn trường hợp trong SingleChildScrollView chiều cao vô hạn từng gây
            // crash ở các Card Dashboard khác — xem giai-doan-121-122/132 memory).
            Flexible(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: _tkGreen))
                      : _errorMessage != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 32),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(onPressed: _openStream, child: const Text('Thử lại', style: TextStyle(color: _tkGreen, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            )
                          : Video(controller: _controller),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _buildPtzPad(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPtzPad(bool isDark) {
    final Color bg = isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9);
    final Color icon = isDark ? Colors.white70 : const Color(0xFF334155);

    // [PTZ THẬT] direction PHẢI khớp ĐÚNG ptzOperations phía Go (internal/imou/settings.go) —
    // "UP"/"DOWN"/"LEFT"/"RIGHT" — nhấn giữ = xoay liên tục, nhả ra = STOP ngay (xem _ptzStart/
    // _ptzStop ở trên).
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
