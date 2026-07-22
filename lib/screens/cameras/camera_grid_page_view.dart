import 'package:flutter/material.dart';

import '../../models/camera_entry.dart';
import 'camera_tile.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [ĐẬP BỎ UI CAMERA — LƯỚI ĐỘNG] 4 chế độ chia ô — yêu cầu #2. `itemsPerPage` quyết định
/// PHÂN TRANG ở CameraGridPageView bên dưới (yêu cầu #3): N camera / M ô-mỗi-trang -> ceil(N/M)
/// trang.
enum CameraGridMode {
  single(1, '1x1', Icons.crop_din_rounded),
  grid2x2(4, '2x2', Icons.grid_view_rounded),
  grid3x3(9, '3x3', Icons.apps_rounded),
  oneMainFour(5, '1 lớn + 4 nhỏ', Icons.dashboard_customize_rounded);

  final int itemsPerPage;
  final String label;
  final IconData icon;
  const CameraGridMode(this.itemsPerPage, this.label, this.icon);
}

/// CameraGridPageView — DÙNG CHUNG cho cả CameraDashboardSection (nhúng trong Dashboard) LẪN
/// CameraFullscreenGridScreen (toàn màn hình xoay ngang) — KHÔNG viết lại logic lưới/phân trang
/// lần 2 (yêu cầu #3 + #4).
class CameraGridPageView extends StatefulWidget {
  final List<CameraEntry> entries;
  final CameraGridMode mode;
  final void Function(CameraEntry) onOpenSettings;
  final void Function(CameraEntry) onOpenRecords;
  final void Function(CameraEntry) onOpenTalk;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  const CameraGridPageView({
    super.key,
    required this.entries,
    required this.mode,
    required this.onOpenSettings,
    required this.onOpenRecords,
    required this.onOpenTalk,
    this.initialPage = 0,
    this.onPageChanged,
  });

  @override
  State<CameraGridPageView> createState() => _CameraGridPageViewState();
}

class _CameraGridPageViewState extends State<CameraGridPageView> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  @override
  void didUpdateWidget(covariant CameraGridPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Đổi chế độ lưới (số ô/trang đổi) -> số trang đổi theo, PageController cũ có thể trỏ ra
    // ngoài phạm vi trang mới -> reset về trang 0 an toàn thay vì giữ index cũ có thể lỗi.
    if (oldWidget.mode != widget.mode) {
      _currentPage = 0;
      _pageController.dispose();
      _pageController = PageController(initialPage: 0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<List<CameraEntry>> get _pages {
    final int perPage = widget.mode.itemsPerPage;
    final List<List<CameraEntry>> pages = [];
    for (int i = 0; i < widget.entries.length; i += perPage) {
      pages.add(widget.entries.sublist(i, i + perPage > widget.entries.length ? widget.entries.length : i + perPage));
    }
    return pages.isEmpty ? [[]] : pages;
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: pages.length,
            onPageChanged: (i) {
              setState(() => _currentPage = i);
              widget.onPageChanged?.call(i);
            },
            itemBuilder: (context, pageIndex) => _buildPageLayout(pages[pageIndex]),
          ),
        ),
        if (pages.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < pages.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _currentPage ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == _currentPage ? _tkGreen : Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPageLayout(List<CameraEntry> pageEntries) {
    if (pageEntries.isEmpty) {
      return const Center(child: Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 32));
    }

    Widget tileFor(CameraEntry e) => CameraTile(
          entry: e,
          onOpenSettings: () => widget.onOpenSettings(e),
          onOpenRecords: () => widget.onOpenRecords(e),
          onOpenTalk: () => widget.onOpenTalk(e),
        );

    if (widget.mode == CameraGridMode.oneMainFour) {
      final main = pageEntries.first;
      final smalls = pageEntries.length > 1 ? pageEntries.sublist(1) : <CameraEntry>[];
      return Row(
        children: [
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.all(4), child: tileFor(main))),
          Expanded(
            flex: 1,
            child: GridView.count(
              crossAxisCount: 2,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: [for (final e in smalls) Padding(padding: const EdgeInsets.all(4), child: tileFor(e))],
            ),
          ),
        ],
      );
    }

    final int crossAxisCount = widget.mode == CameraGridMode.single ? 1 : (widget.mode == CameraGridMode.grid2x2 ? 2 : 3);
    return GridView.count(
      crossAxisCount: crossAxisCount,
      padding: const EdgeInsets.all(4),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [for (final e in pageEntries) tileFor(e)],
    );
  }
}
