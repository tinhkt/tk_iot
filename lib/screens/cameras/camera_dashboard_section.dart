import 'package:flutter/material.dart';

import '../../models/camera_entry.dart';
import '../../models/camera_model.dart';
import '../../models/imou_camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import 'add_camera_dialog.dart';
import 'add_imou_camera_dialog.dart';
import 'camera_fullscreen_grid_screen.dart';
import 'camera_grid_page_view.dart';
import 'imou_camera_records_screen.dart';
import 'imou_camera_settings_screen.dart';

/// [ĐẬP BỎ UI CAMERA — KHỐI DASHBOARD DUY NHẤT] Thay THẲNG `_buildCameraWidget()` cũ trong
/// dashboard_screen.dart — gộp camera RTSP + Imou vào ĐÚNG 1 lưới (yêu cầu #1), không còn tách
/// khối "Camera Imou (P2P)" riêng bên dưới. Tự trị về state UI (chế độ lưới) — cùng tiền lệ tách
/// StatefulWidget riêng khỏi _DashboardScreenState như `_EnergySliderCard` đã làm (file đó đã quá
/// lớn, không vá thêm state mới vào).
///
/// Dữ liệu camera (danh sách RTSP/Imou) VẪN sống ở `_DashboardScreenState` (`_loadCameras()` giữ
/// nguyên) — widget này CHỈ là lớp trình bày, nhận list qua constructor + báo ngược thay đổi
/// (thêm/xóa) qua [onCamerasChanged].
class CameraDashboardSection extends StatefulWidget {
  final List<CameraModel> cameras;
  final List<ImouCameraModel> imouCameras;
  final String homeId;
  final void Function(List<CameraModel> rtsp, List<ImouCameraModel> imou) onCamerasChanged;

  const CameraDashboardSection({
    super.key,
    required this.cameras,
    required this.imouCameras,
    required this.homeId,
    required this.onCamerasChanged,
  });

  @override
  State<CameraDashboardSection> createState() => _CameraDashboardSectionState();
}

class _CameraDashboardSectionState extends State<CameraDashboardSection> {
  // [MẶC ĐỊNH THEO KÍCH THƯỚC MÀN HÌNH — theo yêu cầu user] Mobile mặc định lưới 2x2 (4 cam/trang)
  // — Desktop/tablet vẫn 1x1 (camera đơn đã đủ lớn để xem rõ, không cần chia sẵn). null = "chưa
  // quyết định" (chờ có context ở build() để đọc MediaQuery — field initializer/initState không
  // đảm bảo có context ổn định).
  CameraGridMode? _gridMode;

  CameraGridMode _defaultModeFor(BuildContext context) {
    final bool isMobile = MediaQuery.sizeOf(context).width < 600;
    return isMobile ? CameraGridMode.grid2x2 : CameraGridMode.single;
  }

  List<CameraEntry> get _entries => [
        for (final c in widget.cameras) CameraEntry.rtsp(homeId: widget.homeId, rtspCamera: c),
        for (final c in widget.imouCameras) CameraEntry.imou(homeId: widget.homeId, imouCamera: c),
      ];

  Future<void> _addCamera(int type) async {
    if (type == 0) {
      final added = await showAddCameraDialog(context, homeId: widget.homeId);
      if (added != null && mounted) widget.onCamerasChanged([...widget.cameras, added], widget.imouCameras);
    } else {
      final added = await showAddImouCameraDialog(context, homeId: widget.homeId);
      if (added != null && mounted) widget.onCamerasChanged(widget.cameras, [...widget.imouCameras, added]);
    }
  }

  Future<void> _openSettings(CameraEntry e) async {
    if (e.provider == CameraProviderType.imou) {
      // ImouCameraSettingsScreen pop(true) khi xóa thành công (xem nút xóa mới thêm ở đó) — tự gỡ
      // khỏi danh sách ngay, cùng quy ước optimistic-update đã dùng cho add/xóa RTSP.
      final bool? deleted = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ImouCameraSettingsScreen(homeId: e.homeId, camera: e.imouCamera!)));
      if (deleted == true && mounted) {
        widget.onCamerasChanged(widget.cameras, widget.imouCameras.where((c) => c.id != e.imouCamera!.id).toList());
      }
      return;
    }
    _showRtspSettingsSheet(e);
  }

  void _openRecords(CameraEntry e) {
    if (e.provider == CameraProviderType.imou) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ImouCameraRecordsScreen(homeId: e.homeId, camera: e.imouCamera!)));
      return;
    }
    _showUnsupportedDialog('Chưa hỗ trợ xem lại', 'Hệ thống hiện chưa hỗ trợ ghi hình/lưu trữ cho camera RTSP.');
  }

  void _openTalk(CameraEntry e) {
    _showUnsupportedDialog('Chưa hỗ trợ đàm thoại 2 chiều', 'Tính năng đàm thoại 2 chiều chưa được tích hợp cho loại camera này.');
  }

  void _showUnsupportedDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
      ),
    );
  }

  // [SHEET CÀI ĐẶT RTSP — TOÀN BỘ KHẢ NĂNG THẬT HIỆN CÓ] RTSP chỉ có 1 hành động thật: xóa camera
  // (trước đây nằm trong camera_enlarged_dialog.dart, nay đã xóa theo kế hoạch "đập bỏ cấp 2").
  void _showRtspSettingsSheet(CameraEntry e) {
    final cam = e.rtspCamera!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(cam.name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${cam.ipAddress}:${cam.port}')),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Xóa camera', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dctx) => AlertDialog(
                    title: Text('Xóa camera "${cam.name}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Hủy')),
                      TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Xóa', style: TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                final ok = await ApiService().deleteCamera(widget.homeId, cam.id);
                if (ok && mounted) {
                  widget.onCamerasChanged(widget.cameras.where((c) => c.id != cam.id).toList(), widget.imouCameras);
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xóa camera thất bại'), backgroundColor: Colors.redAccent));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen() {
    // build() luôn chạy trước khi nút này bấm được (đã render ra màn hình) nên _gridMode chắc
    // chắn đã có giá trị — fallback single() chỉ để thỏa kiểu dữ liệu, không thực sự xảy ra.
    Navigator.push(context, MaterialPageRoute(builder: (_) => CameraFullscreenGridScreen(
          entries: _entries,
          initialMode: _gridMode ?? CameraGridMode.single,
          onOpenSettings: _openSettings,
          onOpenRecords: _openRecords,
          onOpenTalk: _openTalk,
        )));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final entries = _entries;
    // Chỉ gán 1 LẦN (giữ nguyên lựa chọn user nếu đã tự đổi) — những lần build sau _gridMode đã
    // khác null nên dòng này không ghi đè lựa chọn thủ công của user nữa.
    _gridMode ??= _defaultModeFor(context);
    final CameraGridMode gridMode = _gridMode!;

    return AppContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam_rounded, color: Colors.blueAccent, size: 22),
                const SizedBox(width: 8),
                Text('Camera', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<CameraGridMode>(
                    tooltip: 'Chia lưới',
                    icon: Icon(gridMode.icon, color: textSub, size: 20),
                    padding: EdgeInsets.zero,
                    onSelected: (m) => setState(() => _gridMode = m),
                    itemBuilder: (ctx) => [for (final m in CameraGridMode.values) PopupMenuItem(value: m, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.icon, size: 18), const SizedBox(width: 8), Text(m.label)]))],
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<int>(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.blueAccent, size: 20),
                    padding: EdgeInsets.zero,
                    tooltip: 'Thêm Camera',
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 0, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam_rounded, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('Camera RTSP (LAN)')])),
                      PopupMenuItem(value: 1, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_queue_rounded, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('Camera Imou (Internet)')])),
                    ],
                    onSelected: _addCamera,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.open_in_full_rounded, color: entries.isEmpty ? textSub.withValues(alpha: 0.4) : textSub, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: entries.isEmpty ? null : _openFullscreen,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(color: isDark ? Colors.black45 : Colors.grey.shade300, borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.videocam_off_rounded, color: textSub, size: 32),
                    const SizedBox(height: 8),
                    Text('Chưa có camera nào — bấm nút + để thêm', style: TextStyle(color: textSub, fontSize: 12)),
                  ]),
                ),
              ),
            )
          else
            // [ĐÍNH CHÍNH — quay lại 16:9] Toán học xác nhận: lưới NxN chia đều (1x1/2x2/3x3) của
            // các ô camera THẬT (16:9) luôn có TỔNG THỂ cũng ra đúng 16:9 (co giãn đều 2 chiều
            // theo cùng hệ số N, không đổi tỉ lệ) — khớp CHÍNH XÁC childAspectRatio cố định 16/9
            // trong camera_grid_page_view.dart, không cần khối "cao hơn" nào cả. Lần sửa trước ép
            // 8:9 dựa trên suy luận sai (tưởng nhiều hàng cần nhiều chiều cao hơn, quên rằng chiều
            // rộng mỗi ô cũng giảm theo đúng tỉ lệ).
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CameraGridPageView(
                entries: entries,
                mode: gridMode,
                onOpenSettings: _openSettings,
                onOpenRecords: _openRecords,
                onOpenTalk: _openTalk,
              ),
            ),
        ],
      ),
    );
  }
}
