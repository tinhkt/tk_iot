import 'dart:ui'; // BackdropFilter / ImageFilter.blur cho hiệu ứng kính mờ
import 'package:flutter/material.dart';
import '../providers/room_group_provider.dart';

const Color _tkGreen = Color(0xFF00A651);

// ============================================================================
// DIALOG CHỌN PHÒNG (RoomSelectionDialog) — trả về Room được chọn (hoặc null nếu hủy)
// ============================================================================
Future<Room?> showRoomSelectionDialog(BuildContext context, RoomGroupProvider provider) {
  return showDialog<Room>(
    context: context,
    builder: (ctx) {
      final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
      final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      return StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          title: Row(children: [
            const Icon(Icons.meeting_room, color: _tkGreen),
            const SizedBox(width: 10),
            Text('Chọn phòng', style: TextStyle(color: textMain)),
          ]),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Danh sách phòng hiện có
                ...provider.rooms.map((r) => ListTile(
                      leading: const Icon(Icons.chair_alt_outlined, color: _tkGreen),
                      title: Text(r.name, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                      onTap: () => Navigator.pop(ctx, r),
                    )),
                const Divider(),
                // Nút tạo phòng mới -> popup nhập tên -> thêm vào provider -> refresh danh sách
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                  title: const Text('Tạo phòng mới', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  onTap: () async {
                    final name = await _promptText(ctx, 'Tên phòng mới', 'vd: Phòng làm việc');
                    if (name != null && name.trim().isNotEmpty) {
                      provider.createRoom(name);
                      setDialog(() {}); // vẽ lại danh sách có phòng vừa tạo
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy'))],
        ),
      );
    },
  );
}

// ============================================================================
// DIALOG TẠO NHÓM (CreateGroupDialog) — trả về {name, iconCodePoint} hoặc null
// ============================================================================
class CreateGroupResult {
  final String name;
  final int iconCodePoint;
  const CreateGroupResult(this.name, this.iconCodePoint);
}

Future<CreateGroupResult?> showCreateGroupDialog(BuildContext context) {
  // Bộ icon gợi ý cho nhóm (đèn/ổ cắm/rèm/toàn nhà...)
  const List<IconData> icons = [
    Icons.lightbulb_outline, Icons.grid_view_rounded, Icons.power_settings_new_rounded,
    Icons.blinds_closed, Icons.home_rounded, Icons.bolt_rounded, Icons.tv_rounded, Icons.ac_unit_rounded,
  ];
  final TextEditingController nameCtrl = TextEditingController();
  int selectedIcon = icons.first.codePoint;

  return showDialog<CreateGroupResult>(
    context: context,
    builder: (ctx) {
      final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
      final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
      // [KÍNH MỜ] Dialog trong suốt + BackdropFilter làm mờ nền + Container bán trong suốt bo góc 24
      return StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 360,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).scaffoldBackgroundColor.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.category, color: _tkGreen),
                      const SizedBox(width: 10),
                      Text('Tạo nhóm công tắc', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: textMain),
                      decoration: InputDecoration(
                        labelText: 'Tên nhóm (vd: Đèn toàn nhà)',
                        labelStyle: TextStyle(color: textSub),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Chọn biểu tượng:', style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10, runSpacing: 10,
                      children: icons.map((ic) {
                        final bool sel = ic.codePoint == selectedIcon;
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setDialog(() => selectedIcon = ic.codePoint),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: sel ? _tkGreen.withValues(alpha: 0.18) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: sel ? _tkGreen : textSub.withValues(alpha: 0.3), width: sel ? 2 : 1),
                            ),
                            child: Icon(ic, color: sel ? _tkGreen : textSub, size: 24),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white),
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            Navigator.pop(ctx, CreateGroupResult(name, selectedIcon));
                          },
                          child: const Text('Tạo nhóm'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// Popup nhập text đơn giản dùng chung (tên phòng mới...)
Future<String?> _promptText(BuildContext context, String title, String hint) {
  final TextEditingController ctrl = TextEditingController();
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      title: Text(title, style: TextStyle(color: textMain)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: TextStyle(color: textMain),
        decoration: InputDecoration(hintText: hint, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );
}
