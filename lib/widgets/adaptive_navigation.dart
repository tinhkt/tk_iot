import 'package:flutter/material.dart';

/// openAdaptiveScreen — điều hướng THÍCH ỨNG cho các màn hình con
/// (Tạo/Sửa ngữ cảnh, Hẹn giờ & Lịch trình, Lịch sử hoạt động, Chi tiết phòng...):
///
/// - Mobile (≤600px): Navigator.push toàn màn hình như cũ (chuẩn UX mobile).
/// - PC (>600px): mở dạng CỬA SỔ DIALOG LỚN nổi TRÊN Dashboard — Sidebar trái +
///   Topbar phía sau GIỮ NGUYÊN, route mới không bao giờ đè mất layout chính.
///
/// Màn hình con giữ nguyên Scaffold/AppBar của nó: bên trong dialog route,
/// AppBar tự sinh nút Back (canPop=true) và mọi Navigator.pop(context) trong màn
/// (nút Lưu, nút Back...) sẽ đóng đúng cửa sổ này; click nền mờ cũng đóng được.
Future<T?> openAdaptiveScreen<T>(BuildContext context, Widget screen, {double maxWidth = 760}) {
  if (MediaQuery.of(context).size.width <= 600) {
    return Navigator.push<T>(context, MaterialPageRoute(builder: (_) => screen));
  }
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        child: ClipRRect(
          // Bo góc 24 như cửa sổ ứng dụng — nội dung (Scaffold màn con) tự lấp đầy
          borderRadius: BorderRadius.circular(24),
          child: screen,
        ),
      ),
    ),
  );
}
