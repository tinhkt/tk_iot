import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/camera_entry.dart';
import 'camera_grid_page_view.dart';

/// [ĐẬP BỎ UI CAMERA — TRANG DEDICATED, yêu cầu #4] Toàn màn hình, xoay ngang, nhúng NGUYÊN
/// CameraGridPageView (cùng widget Dashboard đang dùng — không viết lại lưới lần 2).
///
/// [ÉP XOAY NGANG + ẨN THANH HỆ THỐNG] COPY NGUYÊN cơ chế đã xác nhận AN TOÀN từ
/// CameraFullscreenScreen (camera_player_card.dart, nay đã xóa) — initState/dispose là nơi duy
/// nhất gọi SystemChrome.setPreferredOrientations/setEnabledSystemUIMode, PHẢI trả về Portrait ở
/// dispose() nếu không các màn khác (chỉ thiết kế Portrait) sẽ vỡ giao diện.
class CameraFullscreenGridScreen extends StatefulWidget {
  final List<CameraEntry> entries;
  final CameraGridMode initialMode;
  final int initialPage;
  final void Function(CameraEntry) onOpenSettings;

  const CameraFullscreenGridScreen({
    super.key,
    required this.entries,
    required this.initialMode,
    required this.onOpenSettings,
    this.initialPage = 0,
  });

  @override
  State<CameraFullscreenGridScreen> createState() => _CameraFullscreenGridScreenState();
}

class _CameraFullscreenGridScreenState extends State<CameraFullscreenGridScreen> {
  late CameraGridMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 44),
              child: CameraGridPageView(
                entries: widget.entries,
                mode: _mode,
                initialPage: widget.initialPage,
                onOpenSettings: widget.onOpenSettings,
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.of(context).pop()),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: PopupMenuButton<CameraGridMode>(
                icon: const Icon(Icons.grid_view_rounded, color: Colors.white),
                tooltip: 'Chia lưới',
                onSelected: (m) => setState(() => _mode = m),
                itemBuilder: (ctx) => [for (final m in CameraGridMode.values) PopupMenuItem(value: m, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.icon, size: 18), const SizedBox(width: 8), Text(m.label)]))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
