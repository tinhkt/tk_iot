import 'package:flutter/material.dart';
import 'app_ui_wrappers.dart';
import '../localization/app_translations.dart';

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
    // ("Thông tin thiết bị" đã GỘP vào onOpenSettings — hiển thị IP/MAC/Firmware trong Popup Cài đặt.)
    VoidCallback? onDeviceTimer, // "Hẹn giờ & Lịch trình"
    VoidCallback? onDeviceHistory, // "Lịch sử hoạt động"
    VoidCallback? onDeviceAutomation, // "Thêm vào Ngữ cảnh/Automation"
    VoidCallback? onDeviceShare, // "Chia sẻ thiết bị"
    VoidCallback? onRename, // "Sửa tên thiết bị" — ẩn nếu null
    VoidCallback? onChangeAvatar, // [BƯỚC 5] "Thay đổi giao diện (Avatar)" — ẩn nếu null
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

    // [GLASS THEME] Dialog/ConstrainedBox/GlassContainer thủ công cũ ĐÃ THAY bằng
    // showAppDialog() — bỏ GlassContainer lồng trong đây (showAppDialog tự cấp khung kính),
    // giữ Builder để `ctx` bên trong VẪN LÀ context riêng của dialog (mọi Navigator.pop(ctx)
    // rải rác khắp các mục menu cần đúng context này). Giữ Material(transparent) vì ListTile
    // (dùng trong row()) cần 1 Material ancestor để vẽ ripple — _GlassSurface không tự cấp.
    showAppDialog(
      context: context,
      child: Builder(
        builder: (ctx) {
        // Builder.builder chạy TRONG pha build thật của route dialog -> AppTranslations.of(ctx)
        // (dùng ctx của Builder, KHÔNG phải context tham số ngoài) an toàn ở đây.
        final t = AppTranslations.of(ctx);
        return ConstrainedBox(
          // [FIX OVERFLOW] Giới hạn chiều cao 85% màn hình -> danh sách chức năng dài sẽ CUỘN
          // (SingleChildScrollView bên dưới) thay vì tràn "Bottom overflowed by X pixels".
          constraints: BoxConstraints(maxWidth: 400, maxHeight: MediaQuery.of(context).size.height * 0.85),
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
                  // (5) Ngữ cảnh -> (6) Chia sẻ -> (7) Sửa tên -> (7b) [BƯỚC 5] Đổi giao diện
                  // (Avatar) -> (8) Chuyển phòng -> (9) Chuyển nhà [+Chỉnh sửa nhóm] -> (10) Ẩn ->
                  // (11) extraItems -> (12) Xóa (đỏ).
                  // Mục nào callback null thì TỰ ẩn.
                  // [FIX OVERFLOW] Flexible + SingleChildScrollView: header cố định, danh sách chức năng CUỘN.
                  // ============================================================
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (onOpenSettings != null)
                    row(Icons.settings_rounded, t.text('device_settings_menu'), textMain, () { Navigator.pop(ctx); onOpenSettings(); }),
                  if (onDeviceTimer != null)
                    row(Icons.access_time, t.text('timer_schedule_menu'), textMain, () { Navigator.pop(ctx); onDeviceTimer(); }),
                  if (onDeviceHistory != null)
                    row(Icons.history, t.text('activity_log_menu'), textMain, () { Navigator.pop(ctx); onDeviceHistory(); }, sub: t.text('activity_log_sub')),
                  if (onDeviceAutomation != null)
                    row(Icons.auto_awesome, t.text('add_to_routine_menu'), textMain, () { Navigator.pop(ctx); onDeviceAutomation(); }),
                  if (onDeviceShare != null)
                    row(Icons.share, t.text('share_device_menu'), textMain, () { Navigator.pop(ctx); onDeviceShare(); }),
                  if (onRename != null)
                    row(Icons.edit_rounded, t.text('edit_device_name_menu'), textMain, () { Navigator.pop(ctx); onRename(); }),
                  if (onChangeAvatar != null)
                    row(Icons.palette_outlined, t.text('change_avatar_menu'), textMain, () { Navigator.pop(ctx); onChangeAvatar(); }),
                  if (onAssignRoom != null)
                    row(Icons.meeting_room, t.text('move_to_room_menu'), textMain, () { Navigator.pop(ctx); onAssignRoom(); }),
                  if (onAssignHome != null)
                    row(Icons.swap_horiz, t.text('transfer_home_menu'), tkGreen, () { Navigator.pop(ctx); onAssignHome(); }, sub: t.text('transfer_home_sub')),
                  if (onEditGroup != null)
                    row(Icons.category, t.text('edit_group_menu'), tkGreen, () { Navigator.pop(ctx); onEditGroup(); }, sub: t.text('edit_group_sub')),
                  if (onToggleHide != null)
                    row(
                      isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      hideLabel ?? (isHidden ? t.text('show_device_again') : t.text('hide_from_dashboard_menu')),
                      textMain,
                      () { Navigator.pop(ctx); onToggleHide(!isHidden); },
                      sub: isHidden ? null : hideSubtitle,
                    ),

                  // (6) Mục mở rộng card-specific (chọn nhiều, xem ẩn...)
                  ...extraItems.map((e) => row(e.icon, e.title, e.color ?? textMain, () { Navigator.pop(ctx); e.onTap(); }, sub: e.subtitle)),

                  // (7) Xóa — cuối cùng, màu đỏ, kèm xác nhận dùng chung
                  if (onDelete != null) ...[
                    Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, thickness: 1)),
                    row(Icons.delete_outline_rounded, t.text('delete_device_menu'), Colors.redAccent, () { Navigator.pop(ctx); _confirmDelete(context, currentName, onDelete); }, destructive: true),
                  ],
                        ], // inner Column children
                      ), // inner Column
                    ), // SingleChildScrollView
                  ), // Flexible
                ], // outer Column children
              ),
            ),
          );
        },
      ),
    );
  }



  // Hộp xác nhận xóa DÙNG CHUNG — không còn _confirmDeleteDevice/_confirmDeleteFan lặp mỗi thẻ.
  static void _confirmDelete(BuildContext context, String name, VoidCallback onDelete) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog().
    showAppDialog(
      context: context,
      child: Builder(
        builder: (ctx) {
          final t = AppTranslations.of(ctx);
          return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [GIỮ NGUYÊN BIẾN ĐỘNG] $name (tên thiết bị) — chỉ câu văn quanh dịch.
              Text('${t.text('delete_device_confirm_prefix')}$name?', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(t.text('delete_device_confirm_body'), style: TextStyle(color: textSub)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.text('cancel'), style: const TextStyle(color: Colors.grey))),
                  const SizedBox(width: 8),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { Navigator.pop(ctx); onDelete(); }, child: Text(t.text('delete_now'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                ],
              ),
            ],
          ),
          );
        },
      ),
    );
  }
}
