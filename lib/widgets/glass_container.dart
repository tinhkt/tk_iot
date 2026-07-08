import 'dart:ui';
import 'package:flutter/material.dart';

// ============================================================================
// WIDGET KÍNH MỜ DÙNG CHUNG TOÀN APP (Glassmorphism)
// Trước đây GlassContainer/GlassCard bị định nghĩa lặp lại ở 5 màn hình khác
// nhau — nay gom về đây để chỉnh style một chỗ là đổi toàn app.
// ============================================================================

/// Panel kính mờ lớn: nền các khối Bento trên Dashboard, dialog, popup.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width, height;
  final BorderRadiusGeometry? borderRadius;

  const GlassContainer({super.key, required this.child, this.padding, this.width, this.height, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.6),
            borderRadius: radius,
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white, width: 1.5),
            boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Thẻ kính mờ nhỏ: các item trong danh sách/menu, có thể bấm được qua [onTap].
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const GlassCard({super.key, required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: padding ?? const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15), width: 1.5),
                boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
