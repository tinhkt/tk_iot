import 'dart:ui';

import 'package:flutter/material.dart';

/// glass_popup — CỬA DUY NHẤT cho mọi popup của App (chuẩn hóa toàn dự án):
/// - PC/tablet (>600px): Dialog kính mờ nổi GIỮA màn hình (không còn sheet đáy "lố bịch").
/// - Mobile (≤600px):    BottomSheet kính mờ (isScrollControlled, khóa vuốt-tắt nhầm).
///
/// [CONTRAST] Panel tự ÉP màu chữ/icon qua DefaultTextStyle + IconTheme:
/// nền tối -> trắng alpha 0.95, nền sáng -> xanh đen 0xFF0F172A. Widget con không
/// set màu riêng cũng KHÔNG bao giờ chìm vào nền kính.
///
/// Body có TextField vẫn an toàn: sheet tự đệm viewInsets nên bàn phím không che ô nhập.

Future<T?> showGlassPopup<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder body,
  double dialogMaxWidth = 460,
}) {
  final bool isDesktop = MediaQuery.of(context).size.width > 600;
  if (isDesktop) {
    return showDialog<T>(
      context: context,
      // PC: chỉ đóng bằng nút X — không mất thao tác đang dở vì lỡ click ra nền
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogMaxWidth, maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: GlassPopupPanel(title: title, isSheet: false, child: body(ctx)),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    enableDrag: false, // cuộn danh sách không kéo sập sheet — đóng bằng nút X
    backgroundColor: Colors.transparent, // bắt buộc để nhìn xuyên thấu lớp kính
    elevation: 0,
    builder: (ctx) => Padding(
      // Bàn phím bật lên thì sheet tự nâng theo — TextField không bị che
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: GlassPopupPanel(title: title, isSheet: true, child: body(ctx)),
      ),
    ),
  );
}

/// Khung kính mờ chuẩn dự án: BackdropFilter blur 16 + nền scaffold bán trong suốt
/// + gradient phủ trắng nhẹ + viền hairline; header có tiêu đề + nút X đóng rõ ràng.
/// Thân đặt trong Flexible: nội dung ngắn panel ôm gọn, dài thì cuộn trong trần cao.
class GlassPopupPanel extends StatelessWidget {
  final String title;
  final bool isSheet;
  final Widget child;
  const GlassPopupPanel({super.key, required this.title, required this.isSheet, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [CONTRAST] Chữ/icon trên nền kính: Dark = Trắng tinh, Light = black87 (đậm w600+) —
    // tương phản do MÀU CHỮ đảm nhận, KHÔNG phải do làm đục nền.
    final Color onGlass = isDark ? Colors.white : Colors.black87;
    final BorderRadius radius = isSheet ? const BorderRadius.vertical(top: Radius.circular(20)) : BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            // [KÍNH THẬT] Tint BÁN TRONG SUỐT — tuyệt đối không màu đặc: lớp blur phía sau
            // phải nhìn thấy được thì mới ra glassmorphism. (Lưu ý Flutter: color phải nằm
            // TRONG BoxDecoration — Container không cho dùng đồng thời color + decoration.)
            color: isDark ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.65),
            borderRadius: radius,
            // Viền SÁNG nhẹ bắt sáng ở mép — tạo khối tách panel khỏi nền
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.02)],
            ),
          ),
          child: SafeArea(
            top: false,
            // Ép tương phản cho MỌI Text/Icon con chưa tự set màu
            child: DefaultTextStyle.merge(
              style: TextStyle(color: onGlass),
              child: IconTheme.merge(
                data: IconThemeData(color: onGlass),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSheet)
                      Container(
                        width: 42, height: 4, margin: const EdgeInsets.only(top: 10),
                        decoration: BoxDecoration(color: onGlass.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(2)),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
                      child: Row(children: [
                        Expanded(
                          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: onGlass, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          tooltip: 'Đóng',
                          // Icon đậm full-color — sắc nét trên nền kính, không còn mờ 0.75
                          icon: Icon(Icons.close, color: onGlass, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ]),
                    ),
                    Flexible(child: child),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
