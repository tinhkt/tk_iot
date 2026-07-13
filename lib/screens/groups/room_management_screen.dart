import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/room_group_provider.dart';
import '../../widgets/adaptive_navigation.dart';
import '../../widgets/glass_popup.dart';
import 'room_detail_screen.dart';

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
            // Đang tải lần đầu từ server -> spinner thay vì chớp màn "Chưa có phòng nào"
            if (provider.isLoading && rooms.isEmpty) {
              return const Center(child: CircularProgressIndicator(color: tkGreen));
            }
            if (rooms.isEmpty) {
              return Center(child: Text('Chưa có phòng nào.\nBấm "Thêm phòng" để tạo mới.', textAlign: TextAlign.center, style: TextStyle(color: textSub)));
            }
            // [KÉO-THẢ] ReorderableListView: kéo qua icon drag_handle để sắp lại thứ tự;
            // vuốt trái vẫn xóa (Dismissible), chạm mở chi tiết. buildDefaultDragHandles=false
            // để KÉO CHỈ qua handle (không xung đột với vuốt-xóa / chạm).
            return ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: rooms.length,
              buildDefaultDragHandles: false,
              // Drag proxy: giữ card trong suốt + đổ bóng nhẹ, KHÔNG để Material trắng
              // mặc định phủ lên (vỡ hiệu ứng kính); bo góc như thẻ gốc.
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                child: child,
              ),
              // onReorderItem (chuẩn mới): newIndex ĐÃ được chỉnh cho item bị gỡ ở oldIndex,
              // không cần tự trừ 1 nữa
              onReorderItem: (oldIndex, newIndex) async {
                final err = await provider.reorderRooms(oldIndex, newIndex);
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                }
              },
              itemBuilder: (context, index) {
                final room = rooms[index];
                final int devCount = provider.devicesInRoom(room.id).length;
                // Key BẮT BUỘC trên widget gốc trả về cho ReorderableListView; margin thay separator
                return Padding(
                  key: ValueKey(room.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey('dismiss_${room.id}'),
                    direction: DismissDirection.endToStart, // vuốt sang trái để xóa
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(14)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Xóa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), SizedBox(width: 8), Icon(Icons.delete_outline, color: Colors.white)]),
                    ),
                    confirmDismiss: (_) async => await _confirmDeleteRoom(context, room.name),
                    // API lỗi -> provider tự fetch lại để khôi phục list; ở đây chỉ báo SnackBar
                    onDismissed: (_) async {
                      final err = await provider.deleteRoom(room.id);
                      if (err != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                      }
                    },
                    child: Material(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(14),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        leading: CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.15), child: const Icon(Icons.meeting_room, color: tkGreen)),
                        title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600)),
                        subtitle: Text('$devCount thiết bị • Chạm để xem chi tiết', style: TextStyle(color: textSub, fontSize: 12)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Sửa tên phòng',
                            icon: Icon(Icons.edit_outlined, color: textSub, size: 20),
                            onPressed: () => _renameRoom(context, provider, room),
                          ),
                          // Tay nắm kéo-thả: chỉ vùng này khởi động kéo (đỡ đụng chạm/vuốt)
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.drag_handle, color: textSub),
                            ),
                          ),
                        ]),
                        // Bấm cả khối -> mở chi tiết phòng (PC: dialog lớn giữ Sidebar; Mobile: push)
                        onTap: () => openAdaptiveScreen(context, RoomDetailScreen(roomId: room.id)),
                      ),
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
    // API thật: null = thành công, chuỗi = câu báo lỗi từ Backend
    final err = await Provider.of<RoomGroupProvider>(context, listen: false).createRoom(name);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _renameRoom(BuildContext context, RoomGroupProvider provider, Room room) async {
    final name = await _promptRoomName(context, 'Sửa tên phòng', room.name);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final err = await provider.renameRoom(room.id, name);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
    }
  }

  // [KÍNH MỜ ĐỒNG BỘ] Popup xác nhận xóa — qua showGlassPopup (PC: dialog giữa
  // màn hình; Mobile: sheet), không còn AlertDialog nền đặc
  Future<bool> _confirmDeleteRoom(BuildContext context, String name) async {
    final res = await showGlassPopup<bool>(
      context,
      title: 'Xóa phòng "$name"?',
      body: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Thiết bị trong phòng KHÔNG bị xóa, chỉ gỡ khỏi phòng này.'),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Xóa'),
            ),
          ]),
        ]),
      ),
    );
    return res ?? false;
  }

  // [KÍNH MỜ ĐỒNG BỘ] Popup nhập tên phòng — TextField an toàn bàn phím nhờ
  // showGlassPopup tự đệm viewInsets ở chế độ sheet
  Future<String?> _promptRoomName(BuildContext context, String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showGlassPopup<String>(
      context,
      title: title,
      body: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl, autofocus: true,
            decoration: InputDecoration(hintText: 'Tên phòng', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Lưu'),
            ),
          ]),
        ]),
      ),
    );
  }
}
