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
  final int initialPage;
  final ValueChanged<int>? onPageChanged;

  const CameraGridPageView({
    super.key,
    required this.entries,
    required this.mode,
    required this.onOpenSettings,
    this.initialPage = 0,
    this.onPageChanged,
  });

  @override
  State<CameraGridPageView> createState() => _CameraGridPageViewState();
}

class _CameraGridPageViewState extends State<CameraGridPageView> {
  // [VUỐT QUAY VÒNG TRÒN — theo yêu cầu user] PageView.builder KHÔNG hỗ trợ loop tự nhiên với
  // itemCount hữu hạn — mẹo chuẩn: itemCount=null (vô hạn CẢ 2 CHIỀU), bắt đầu ở 1 mốc xa 0
  // (_loopAnchor) để vuốt lùi cũng có "trang" để đi tới, itemBuilder dùng index % pages.length để
  // luôn trỏ đúng 1 trang thật. Chỉ áp dụng khi >1 trang — 1 trang thì loop vô nghĩa.
  static const int _loopAnchor = 10000;
  late PageController _pageController;
  late int _rawPage; // index THẬT của PageView (có thể rất lớn/âm khi đang loop) — _rawPage % pages.length mới là trang hiển thị thật.

  @override
  void initState() {
    super.initState();
    _rawPage = _loopAnchor + widget.initialPage;
    _pageController = PageController(initialPage: _rawPage);
  }

  @override
  void didUpdateWidget(covariant CameraGridPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Đổi chế độ lưới (số ô/trang đổi) -> số trang đổi theo, PageController cũ có thể trỏ ra
    // ngoài phạm vi trang mới -> reset về trang 0 an toàn thay vì giữ index cũ có thể lỗi.
    if (oldWidget.mode != widget.mode) {
      _rawPage = _loopAnchor;
      _pageController.dispose();
      _pageController = PageController(initialPage: _rawPage);
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
    final bool canLoop = pages.length > 1;
    // Dart % luôn trả kết quả CÙNG DẤU với số chia (khi số chia dương) — an toàn với _rawPage âm,
    // không cần tự xử lý âm riêng như C/Java.
    final int currentPageIndex = _rawPage % pages.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: canLoop ? null : 1,
            onPageChanged: (i) {
              setState(() => _rawPage = i);
              widget.onPageChanged?.call(i % pages.length);
            },
            itemBuilder: (context, index) => _buildPageLayout(pages[canLoop ? index % pages.length : 0]),
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
                  width: i == currentPageIndex ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == currentPageIndex ? _tkGreen : Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
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

    // [FIX — key theo identity, Trụ cột 1/4 rà soát hiệu năng] Thiếu key khiến GridView tái dùng
    // Element theo VỊ TRÍ thay vì camera thật khi danh sách đổi thứ tự/số lượng — Player bên trong
    // CameraTile có thể bị gán nhầm camera, phải tự dò qua didUpdateWidget thay vì Flutter tự nhận
    // biết đúng ngay từ đầu.
    Widget tileFor(CameraEntry e) => CameraTile(
          key: ValueKey(e.id),
          entry: e,
          onOpenSettings: () => widget.onOpenSettings(e),
        );

    // [FIX — ĐÍNH CHÍNH lần sửa trước] childAspectRatio PHẢI cố định 16:9 (tỉ lệ THẬT của camera),
    // KHÔNG "đo theo khung chứa" như bản trước — đo theo khung chứa nghĩa là MỖI Ô bị BÓP/GIÃN
    // méo theo hình dạng khung ngoài (đúng triệu chứng user báo: "kéo dài kích thước khung hình
    // xuống dưới"), dù khung ngoài đó có hình dạng gì. Toán học xác nhận: lưới NxN chia đều (N
    // cột = N hàng, đúng 1x1/2x2/3x3 ở đây) gồm các ô 16:9 THẬT thì TOÀN KHỐI cũng LUÔN ra đúng
    // 16:9 (co giãn đều 2 chiều theo cùng hệ số N không đổi tỉ lệ) — nên khung ngoài 16:9 (xem
    // camera_dashboard_section.dart) + childAspectRatio 16/9 cố định ở đây khớp nhau HOÀN HẢO,
    // không cần đo động, không còn rủi ro méo ô theo hình dạng khung ngoài bất kỳ (vd màn hình
    // ngang ở CameraFullscreenGridScreen, tỉ lệ thật KHÁC 16:9).
    const double kCameraAspectRatio = 16 / 9;

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
              childAspectRatio: kCameraAspectRatio,
              children: [for (final e in smalls) Padding(padding: const EdgeInsets.all(4), child: tileFor(e))],
            ),
          ),
        ],
      );
    }

    final int crossAxisCount = widget.mode == CameraGridMode.single ? 1 : (widget.mode == CameraGridMode.grid2x2 ? 2 : 3);
    // [KHÔNG NeverScrollableScrollPhysics ở đây — CÓ CHỦ Ý] Khối nhúng trong Dashboard (bọc
    // AspectRatio 16:9 khớp CHÍNH XÁC lưới 16:9 thật, xem camera_dashboard_section.dart) không
    // bao giờ cần cuộn (vừa khít). Nhưng CameraFullscreenGridScreen (màn hình ngang thật) có tỉ
    // lệ khác 16:9 (thường RỘNG hơn) — lưới 16:9 thật có thể cần chiều cao NHIỀU hơn khoảng trống
    // thật còn lại; cho phép cuộn dọc làm lưới an toàn thay vì cắt mất hàng cuối.
    return GridView.count(
      crossAxisCount: crossAxisCount,
      padding: const EdgeInsets.all(4),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: kCameraAspectRatio,
      children: [for (final e in pageEntries) tileFor(e)],
    );
  }
}
