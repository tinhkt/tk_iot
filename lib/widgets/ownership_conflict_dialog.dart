import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../localization/app_translations.dart';

// ============================================================================
// 🤝 [LUỒNG CHUYỂN GIAO — DÙNG CHUNG] Dialog "Thiết bị đã có chủ"
// ============================================================================
// Bung ra khi BẤT KỲ luồng thêm thiết bị nào (AP Mode trực tiếp, QR/Nhập tay/Quét LAN qua
// dashboard) nhận HTTP 409 từ POST /api/homes/{id}/devices. Tách thành hàm top-level DÙNG CHUNG
// thay vì viết riêng ở từng nơi gọi — trước đây chỉ luồng AP Mode (add_device_dialog.dart) có
// Dialog này, còn luồng QR/Nhập tay/Quét LAN (_linkScannedDevice trong dashboard_screen.dart)
// vẫn hiện SnackBar lỗi chung chung — đúng bug user report bằng ảnh chụp màn hình thật.
const Color _tkGreen = Color(0xFF00A651);

/// [BẮT BUỘC] Gọi hàm này ngay khi bắt được HTTP 409 — không tự chế Dialog/SnackBar khác.
/// [maskedOwnerEmail] đã được Backend CHE SẴN (vd "sale.****@gmail.com") — hiển thị y nguyên,
/// KHÔNG tự ý xử lý/giải mã gì thêm phía App.
Future<void> showOwnershipConflictDialog(
  BuildContext context, {
  required String mac,
  String? maskedOwnerEmail,
}) {
  bool sending = false;
  bool requestSent = false;

  return showDialog<void>(
    context: context,
    barrierDismissible: false, // chống người dùng lỡ tay tắt Dialog giữa lúc đang gọi API dở dang
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final t = AppTranslations.of(dialogContext);
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
          title: Text(t.text('device_conflict_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.text('device_conflict_body')),
              if (maskedOwnerEmail?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text('${t.text('device_conflict_account_label')}: $maskedOwnerEmail',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              const SizedBox(height: 12),
              Text(t.text('device_conflict_instruction'), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.of(dialogContext).pop(),
              child: Text(t.text('cancel')),
            ),
            ElevatedButton(
              onPressed: (sending || requestSent)
                  ? null
                  : () async {
                      setDialogState(() => sending = true);
                      final bool ok = await ApiService().requestUnbind(mac);
                      if (!context.mounted) return; // màn hình gốc đã bị gỡ trong lúc chờ (hiếm) -> không đụng gì nữa
                      if (ok) {
                        Navigator.of(dialogContext).pop(); // ĐÓNG Dialog khi thành công — đúng yêu cầu
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(t.text('device_conflict_request_sent')),
                          backgroundColor: _tkGreen,
                        ));
                      } else {
                        setDialogState(() { sending = false; requestSent = false; });
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(t.text('device_conflict_request_failed')),
                          backgroundColor: Colors.redAccent,
                        ));
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: _tkGreen),
              child: sending
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Text(t.text('device_conflict_request_btn')),
            ),
          ],
        );
      },
    ),
  );
}
