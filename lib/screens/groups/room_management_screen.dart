import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/room_group_provider.dart';

/// RoomManagementScreen — Quản lý Phòng: list phòng, VUỐT để xóa, BẤM để sửa tên, FAB thêm phòng.
/// [embedded]=true khi NHÚNG làm tab body của Dashboard: BỎ AppBar (nút Back) để tránh double
/// AppBar, thay bằng hàng tiêu đề trong body; Scaffold vẫn giữ để FAB "Thêm phòng" hoạt động.
/// [embedded]=false (mặc định) khi Navigator.push riêng: có AppBar + nút Back đầy đủ.
class RoomManagementScreen extends StatelessWidget {
  final bool embedded;
  const RoomManagementScreen({super.key, this.embedded = false});

  static const Color tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      // Nhúng (tab body) -> KHÔNG AppBar; đứng riêng (push) -> AppBar + Back
      appBar: embedded
          ? null
          : AppBar(title: const Text('Quản lý phòng'), backgroundColor: cardColor, foregroundColor: textMain, elevation: 0),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: tkGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Thêm phòng'),
        onPressed: () => _addRoom(context),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Tiêu đề trong body khi nhúng (thay cho AppBar đã bỏ)
            if (embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(children: [
                  const Icon(Icons.meeting_room, color: tkGreen, size: 26),
                  const SizedBox(width: 12),
                  Text('Quản lý phòng', style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
            Expanded(
              child: Consumer<RoomGroupProvider>(
          builder: (context, provider, _) {
            final rooms = provider.rooms;
            if (rooms.isEmpty) {
              return Center(child: Text('Chưa có phòng nào.\nBấm "Thêm phòng" để tạo mới.', textAlign: TextAlign.center, style: TextStyle(color: textSub)));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: rooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final room = rooms[index];
                final int devCount = provider.devicesInRoom(room.id).length;
                return Dismissible(
                  key: ValueKey(room.id),
                  direction: DismissDirection.endToStart, // vuốt sang trái để xóa
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(14)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Xóa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(width: 8), Icon(Icons.delete_outline, color: Colors.white)]),
                  ),
                  confirmDismiss: (_) async => await _confirmDeleteRoom(context, room.name),
                  onDismissed: (_) => provider.deleteRoom(room.id),
                  child: Material(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      leading: CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.15), child: const Icon(Icons.meeting_room, color: tkGreen)),
                      title: Text(room.name, style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600)),
                      subtitle: Text('$devCount thiết bị', style: TextStyle(color: textSub, fontSize: 12)),
                      trailing: Icon(Icons.edit_outlined, color: textSub, size: 20),
                      onTap: () => _renameRoom(context, provider, room), // bấm -> sửa tên
                    ),
                  ),
                );
              },
            );
          },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRoom(BuildContext context) async {
    final name = await _promptRoomName(context, 'Thêm phòng mới', '');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    Provider.of<RoomGroupProvider>(context, listen: false).createRoom(name);
  }

  Future<void> _renameRoom(BuildContext context, RoomGroupProvider provider, Room room) async {
    final name = await _promptRoomName(context, 'Sửa tên phòng', room.name);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    provider.renameRoom(room.id, name);
  }

  Future<bool> _confirmDeleteRoom(BuildContext context, String name) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Xóa phòng "$name"?'),
        content: const Text('Thiết bị trong phòng KHÔNG bị xóa, chỉ gỡ khỏi phòng này.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    return res ?? false;
  }

  Future<String?> _promptRoomName(BuildContext context, String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(title, style: TextStyle(color: textMain)),
        content: TextField(
          controller: ctrl, autofocus: true, style: TextStyle(color: textMain),
          decoration: InputDecoration(hintText: 'Tên phòng', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Lưu')),
        ],
      ),
    );
  }
}
