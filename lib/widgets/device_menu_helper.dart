import 'package:flutter/material.dart';
import 'glass_container.dart';

/// Một mục menu tùy biến (card-specific) truyền thêm vào [DeviceMenuHelper] — ví dụ
/// "Chọn nhiều thiết bị", "Xem thiết bị ẩn"... để không phá vỡ tính dùng chung.
class DeviceMenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;
  final VoidCallback onTap;
  const DeviceMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.color,
  });
}

/// DeviceMenuHelper — MENU NGỮ CẢNH DÙNG CHUNG cho MỌI thẻ thiết bị (công tắc/quạt/cảm biến
/// và bất kỳ loại mới trong tương lai). Gom toàn bộ logic vẽ Hộp thoại tùy chọn (Cài đặt,
/// Đổi tên, Ẩn/Hiện, CHUYỂN NHÀ, Xóa + xác nhận) về một nơi. Thẻ chỉ cần gọi
/// [showGenericDeviceMenu] và truyền callback — thêm loại thiết bị mới KHÔNG phải chép lại menu.
///
/// Nguyên tắc "render theo callback": mục nào có callback != null thì tự hiện; ví dụ
/// 'Chuyển sang nhà khác' LUÔN tự render nếu [onAssignHome] != null (tức user là SUPER_USER).
class DeviceMenuHelper {
  static const Color tkGreen = Color(0xFF00A651);

  static void showGenericDeviceMenu({
    required BuildContext context,
    required String mac,
    required String currentName,
    String? subtitle, // dòng phụ dưới MAC (vd "Endpoint: relay1" / "Cảm biến môi trường")
    IconData headerIcon = Icons.settings_input_component_rounded,
    bool isSuperUser = false, // giữ theo hợp đồng; UI thực tế dựa vào onAssignHome != null
    VoidCallback? onOpenSettings, // "Cài đặt thiết bị" (Popup chi tiết) — ẩn nếu null
    // [CHUẨN TUYA/GOOGLE HOME] Bộ chức năng mở rộng — mục nào callback null thì tự ẩn.
    VoidCallback? onDeviceInfo, // "Thông tin thiết bị" (IP/MAC/Firmware/Mạng)
    VoidCallback? onDeviceTimer, // "Hẹn giờ & Lịch trình"
    VoidCallback? onDeviceHistory, // "Lịch sử hoạt động"
    VoidCallback? onDeviceAutomation, // "Thêm vào Ngữ cảnh/Automation"
    VoidCallback? onDeviceShare, // "Chia sẻ thiết bị"
    VoidCallback? onRename, // "Sửa tên thiết bị" — ẩn nếu null
    VoidCallback? onAssignHome, // "Chuyển sang nhà khác" — TỰ render nếu != null
    VoidCallback? onAssignRoom, // "Chuyển / Thêm vào phòng" — TỰ render nếu != null
    VoidCallback? onEditGroup, // "Chỉnh sửa nhóm" — CHỈ hiện với Công tắc ảo (nhóm)
    VoidCallback? onDelete, // "Xóa thiết bị" (kèm hộp xác nhận) — ẩn nếu null
    bool isHidden = false,
    String? hideLabel, // nhãn tùy biến cho nút Ẩn/Hiện (mặc định chung nếu null)
    String? hideSubtitle,
    ValueChanged<bool>? onToggleHide, // "Ẩn/Hiện khỏi Bảng điều khiển" — ẩn nếu null
    List<DeviceMenuItem> extraItems = const [], // mục card-specific (Chọn nhiều, Xem ẩn...)
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    Widget row(IconData icon, String title, Color color, VoidCallback onTap,
        {String? sub, bool destructive = false}) {
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        hoverColor: destructive ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10,
        leading: Icon(icon, color: color, size: 24),
        title: Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: destructive ? FontWeight.bold : FontWeight.w600)),
        subtitle: sub != null ? Text(sub, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.2)) : null,
        onTap: onTap,
      );
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Header: icon + tên + MAC (+ dòng phụ) ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(headerIcon, color: tkGreen, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(currentName, style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Text('MAC: $mac', style: TextStyle(color: textSub, fontSize: 12)),
                            if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle, style: TextStyle(color: textSub, fontSize: 12))],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ============================================================
                  // THỨ TỰ MENU CỐ ĐỊNH (chuẩn Tuya/Google Home):
                  // (1) Cài đặt -> (2) Thông tin -> (3) Hẹn giờ -> (4) Lịch sử ->
                  // (5) Ngữ cảnh -> (6) Chia sẻ -> (7) Sửa tên -> (8) Chuyển phòng ->
                  // (9) Chuyển nhà [+Chỉnh sửa nhóm] -> (10) Ẩn -> (11) extraItems -> (12) Xóa (đỏ).
                  // Mục nào callback null thì TỰ ẩn.
                  // ============================================================
                  if (onOpenSettings != null)
                    row(Icons.settings_rounded, 'Cài đặt thiết bị', textMain, () { Navigator.pop(ctx); onOpenSettings(); }),
                  if (onDeviceInfo != null)
                    row(Icons.info_outline, 'Thông tin thiết bị', textMain, () { Navigator.pop(ctx); onDeviceInfo(); }, sub: 'IP, MAC, Firmware, Mạng'),
                  if (onDeviceTimer != null)
                    row(Icons.access_time, 'Hẹn giờ & Lịch trình', textMain, () { Navigator.pop(ctx); onDeviceTimer(); }),
                  if (onDeviceHistory != null)
                    row(Icons.history, 'Lịch sử hoạt động', textMain, () { Navigator.pop(ctx); onDeviceHistory(); }, sub: 'Nhật ký bật/tắt'),
                  if (onDeviceAutomation != null)
                    row(Icons.auto_awesome, 'Thêm vào Ngữ cảnh', textMain, () { Navigator.pop(ctx); onDeviceAutomation(); }),
                  if (onDeviceShare != null)
                    row(Icons.share, 'Chia sẻ thiết bị', textMain, () { Navigator.pop(ctx); onDeviceShare(); }),
                  if (onRename != null)
                    row(Icons.edit_rounded, 'Sửa tên thiết bị', textMain, () { Navigator.pop(ctx); onRename(); }),
                  if (onAssignRoom != null)
                    row(Icons.meeting_room, 'Chuyển / Thêm vào phòng', textMain, () { Navigator.pop(ctx); onAssignRoom(); }),
                  if (onAssignHome != null)
                    row(Icons.swap_horiz, 'Chuyển sang nhà khác', tkGreen, () { Navigator.pop(ctx); onAssignHome(); }, sub: 'Phân bổ thiết bị cho ngôi nhà khác (Admin)'),
                  if (onEditGroup != null)
                    row(Icons.category, 'Chỉnh sửa nhóm', tkGreen, () { Navigator.pop(ctx); onEditGroup(); }, sub: 'Thêm/bớt thiết bị trong nhóm'),
                  if (onToggleHide != null)
                    row(
                      isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      hideLabel ?? (isHidden ? 'Hiển thị lại thiết bị này' : 'Ẩn khỏi Bảng điều khiển'),
                      textMain,
                      () { Navigator.pop(ctx); onToggleHide(!isHidden); },
                      sub: isHidden ? null : hideSubtitle,
                    ),

                  // (6) Mục mở rộng card-specific (chọn nhiều, xem ẩn...)
                  ...extraItems.map((e) => row(e.icon, e.title, e.color ?? textMain, () { Navigator.pop(ctx); e.onTap(); }, sub: e.subtitle)),

                  // (7) Xóa — cuối cùng, màu đỏ, kèm xác nhận dùng chung
                  if (onDelete != null) ...[
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, thickness: 1)),
                    row(Icons.delete_outline_rounded, 'Xóa thiết bị', Colors.redAccent, () { Navigator.pop(ctx); _confirmDelete(context, currentName, onDelete); }, destructive: true),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Hộp xác nhận xóa DÙNG CHUNG — không còn _confirmDeleteDevice/_confirmDeleteFan lặp mỗi thẻ.
  static void _confirmDelete(BuildContext context, String name, VoidCallback onDelete) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Xóa $name?', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn gỡ thiết bị này khỏi hệ thống không?', style: TextStyle(color: textSub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { Navigator.pop(ctx); onDelete(); }, child: const Text('Xóa ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
