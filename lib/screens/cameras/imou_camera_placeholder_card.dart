import 'package:flutter/material.dart';

import '../../models/imou_camera_model.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [CAMERA P2P — IMOU, PHA 1] Thẻ TẠM cho camera Imou — CHƯA có video sống (Native SDK live-view
/// thuộc Pha 2, xem kế hoạch giai-doan-136 mục Imou P2P: cần AppId/AppSecret thật + AAR Android +
/// camera/thiết bị thật để viết). Thẻ này CỐ Ý không giả vờ có luồng video, chỉ hiện tên + badge
/// "Imou" + nút Xóa — tránh đánh lừa người dùng rằng tính năng đã xem được ngay.
class ImouCameraPlaceholderCard extends StatelessWidget {
  final ImouCameraModel camera;
  final VoidCallback? onDelete;

  const ImouCameraPlaceholderCard({super.key, required this.camera, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_queue_rounded, color: _tkGreen, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(camera.name, style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text('Imou · Chờ cấu hình SDK gốc', style: TextStyle(color: textSub, fontSize: 10)),
                ],
              ),
            ),
            if (onDelete != null)
              InkWell(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withValues(alpha: 0.8), size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
