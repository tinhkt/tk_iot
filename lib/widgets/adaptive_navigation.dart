import 'dart:ui';

import 'package:flutter/material.dart';

/// openAdaptiveScreen — điều hướng THÍCH ỨNG cho các màn hình con
/// (Tạo/Sửa ngữ cảnh, Hẹn giờ & Lịch trình, Lịch sử hoạt động, Chi tiết phòng...):
///
/// - Mobile (≤600px): mở dạng TẤM KÍNH TRƯỢT TỪ ĐÁY phủ gần hết màn hình.
///   Route TRONG SUỐT (opaque: false) — màn cũ vẫn được vẽ phía sau để
///   BackdropFilter có thứ mà làm mờ; không còn MaterialPageRoute nền đen đặc.
/// - PC (>600px): CỬA SỔ DIALOG KÍNH nổi TRÊN Dashboard — Sidebar trái +
///   Topbar phía sau GIỮ NGUYÊN, route mới không bao giờ đè mất layout chính.
///
/// [HỢP ĐỒNG VỚI MÀN CON] Vỏ kính (_glassShell) đặt TẠI ĐÂY — đúng một chỗ cho mọi
/// màn hình con. Màn con muốn "trong như kính" phải tự đặt Scaffold/AppBar
/// backgroundColor: Colors.transparent và dùng thẻ nền alpha (white .08/.55) —
/// màn con giữ nền đặc thì trông như cũ, không vỡ (History/RoomDetail chuyển dần sau).
///
/// Màn hình con giữ nguyên Scaffold/AppBar của nó: AppBar tự sinh nút Back
/// (canPop=true) và mọi Navigator.pop(context) trong màn sẽ đóng đúng tầng này.
Future<T?> openAdaptiveScreen<T>(BuildContext context, Widget screen, {double maxWidth = 760}) {
  if (MediaQuery.of(context).size.width <= 600) {
    return Navigator.push<T>(
      context,
      PageRouteBuilder<T>(
        opaque: false, // SỐNG CÒN: giữ màn cũ phía sau cho lớp blur nhìn xuyên
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, _, _) => Padding(
          // Chừa dải status bar + 12px: thấy màn cũ ló ra ở đỉnh — đúng cảm giác bottom-sheet
          padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 12),
          child: _GlassShell(isSheet: true, child: screen),
        ),
        transitionsBuilder: (_, anim, _, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent, // Bắt buộc để nhìn xuyên thấu
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        child: _GlassShell(isSheet: false, child: screen),
      ),
    ),
  );
}

/// _GlassShell — vỏ kính chuẩn dự án (đồng bộ thông số với GlassPopupPanel):
/// blur 24 + tint bán trong suốt black .55 / white .65 + viền sáng white .2.
/// isSheet: bo góc TRÊN + viền chỉ ở mép trên (bottom-sheet); ngược lại bo tròn 24 (dialog).
class _GlassShell extends StatelessWidget {
  final bool isSheet;
  final Widget child;
  const _GlassShell({required this.isSheet, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final BorderRadius radius =
        isSheet ? const BorderRadius.vertical(top: Radius.circular(24)) : BorderRadius.circular(24);

    // Sheet đã tự chừa status bar bằng Padding bên ngoài — gỡ padding top khỏi
    // MediaQuery để AppBar của màn con không cộng thêm một dải trống nữa.
    final Widget content = isSheet
        ? MediaQuery.removePadding(context: context, removeTop: true, child: child)
        : child;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            // Tint BÁN TRONG SUỐT — tuyệt đối không màu đặc, lớp blur phải nhìn thấy được
            color: isDark ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.65),
            borderRadius: radius,
            border: isSheet
                ? Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.2))) // viền sáng bắt sáng mép trên
                : Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: content,
        ),
      ),
    );
  }
}
