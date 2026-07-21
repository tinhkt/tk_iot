import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [3 CẤP ĐỘ XEM — cấp 2/3: Phóng to] Mở qua [showCameraEnlargedDialog] khi user bấm nút
/// Maximize trên thẻ Dashboard (hoặc chạm vào video). VẪN nằm trên Dashboard (showAppDialog,
/// không đổi route) — khác cấp 3 (CameraFullscreenScreen) là một Navigator.push thật sự có ép
/// xoay ngang. Phát LUỒNG CHÍNH (camera.rtspUrl) vì dialog đủ lớn để đáng xem nét, không dùng
/// luồng phụ như thẻ Dashboard.
///
/// Bên dưới video là cụm nút D-pad PTZ (Lên/Xuống/Trái/Phải) — CHỈ LÀ UI CHỜ (placeholder) cho
/// tính năng xoay camera qua ONVIF sau này, chưa có backend/lệnh thật đứng sau — bấm vào chỉ
/// hiện SnackBar "Chưa hỗ trợ" để không đánh lừa người dùng rằng camera đã thật sự xoay.
///
/// [XÓA CAMERA] Icon thùng rác trên thanh tiêu đề — nơi TRUNG TÂM duy nhất để xóa 1 camera cụ
/// thể (mở qua Maximize từ đúng camera đó, không cần màn "quản lý camera" riêng). Trả về `true`
/// khi camera đã bị xóa thật (Server xác nhận 200) để Dashboard tự gỡ khỏi `_cameras` — trả
/// `false`/đóng thường (nút X, chạm ra ngoài) coi như không đổi gì.
Future<bool> showCameraEnlargedDialog(BuildContext context, {required String homeId, required CameraModel camera}) async {
  final double dialogWidth = MediaQuery.sizeOf(context).width * 0.9;
  final bool? deleted = await showAppDialog<bool>(
    context: context,
    maxWidth: dialogWidth,
    contentPadding: EdgeInsets.zero,
    child: _CameraEnlargedDialogBody(homeId: homeId, camera: camera),
  );
  return deleted ?? false;
}

class _CameraEnlargedDialogBody extends StatefulWidget {
  final String homeId;
  final CameraModel camera;
  const _CameraEnlargedDialogBody({required this.homeId, required this.camera});

  @override
  State<_CameraEnlargedDialogBody> createState() => _CameraEnlargedDialogBodyState();
}

class _CameraEnlargedDialogBodyState extends State<_CameraEnlargedDialogBody> {
  late final Player _player;
  late final VideoController _controller;
  String? _errorMessage;
  bool _deleting = false;

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
    if (widget.camera.rtspUrl.isEmpty) {
      setState(() => _errorMessage = 'Camera này chưa cấu hình luồng chính (stream_path)');
      return;
    }
    setState(() => _errorMessage = null);
    _player.open(Media(widget.camera.rtspUrl));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _ptzPlaceholderTap(String direction) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Xoay camera ($direction) — chưa hỗ trợ, sẽ nối ONVIF sau'), duration: const Duration(seconds: 2)),
    );
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
              Text('Toàn bộ cấu hình kết nối (địa chỉ IP, tài khoản, đường dẫn luồng) của camera này sẽ bị xóa khỏi hệ thống. Bạn có thể thêm lại sau nếu cần.', style: TextStyle(color: textSub)),
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
    final bool ok = await ApiService().deleteCamera(widget.homeId, widget.camera.id);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true); // đóng dialog Phóng to, báo Dashboard tự gỡ camera này.
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
            // Thanh tiêu đề + nút đóng.
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
            // Khung video 16:9 — bo góc lớn theo đúng đặc tả "Dialog bo góc lớn".
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _errorMessage != null
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
            // Cụm nút PTZ placeholder — UI chờ ONVIF, đặt ngay dưới video như đặc tả yêu cầu.
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

    Widget dirButton(IconData iconData, String direction) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _ptzPlaceholderTap(direction),
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
        dirButton(Icons.keyboard_arrow_up_rounded, 'Lên'),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dirButton(Icons.keyboard_arrow_left_rounded, 'Trái'),
            const SizedBox(width: 4),
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: Icon(Icons.videocam_rounded, color: icon.withValues(alpha: 0.4), size: 16),
            ),
            const SizedBox(width: 4),
            dirButton(Icons.keyboard_arrow_right_rounded, 'Phải'),
          ],
        ),
        const SizedBox(height: 4),
        dirButton(Icons.keyboard_arrow_down_rounded, 'Xuống'),
      ],
    );
  }
}
