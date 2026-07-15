import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/device_provider.dart';
import '../../providers/room_group_provider.dart';
import '../../widgets/glass_popup.dart';

/// EditGroupScreen — Chỉnh sửa Nhóm công tắc ảo: xem thành viên (xóa khỏi nhóm) + Thêm thiết bị.
/// [availableDevices] là danh sách công tắc thật đang có (mỗi phần tử {mac, name}) để chọn thêm.
class EditGroupScreen extends StatelessWidget {
  final String groupMac;
  final List<Map<String, dynamic>> availableDevices;
  /// [embedded]=true khi làm child của Dialog trên PC: dùng nút X đóng thay vì nút Back.
  final bool embedded;

  const EditGroupScreen({super.key, required this.groupMac, this.availableDevices = const [], this.embedded = false});

  static const Color tkGreen = Color(0xFF00A651);

  /// [DISPLAY NAME] Tên hiển thị: ưu tiên tên NGƯỜI DÙNG ĐẶT từ kho DPS
  /// (DeviceProvider.displayNameOf — nguồn duy nhất toàn app), fallback = name cấp
  /// thiết bị trong [availableDevices] (có thể là tên tự sinh sw-xxxx), cuối cùng MAC.
  String _nameOf(DeviceProvider deviceProv, String mac) {
    String? restName;
    for (final d in availableDevices) {
      if ((d['mac'] ?? '').toString().toUpperCase() == mac.toUpperCase()) {
        restName = (d['name'] ?? '').toString();
        break;
      }
    }
    return deviceProv.displayNameOf(mac, fallback: restName ?? mac);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: const Text('Chỉnh sửa nhóm'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
        automaticallyImplyLeading: !embedded,
        // PC (Dialog): nút X đóng dialog; Mobile (push): giữ nút Back mặc định
        leading: embedded ? IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)) : null,
      ),
      body: SafeArea(
        child: Consumer<RoomGroupProvider>(
          builder: (context, provider, _) {
            // watch DeviceProvider: đổi tên thiết bị ở nơi khác -> danh sách này tự cập nhật
            final deviceProv = context.watch<DeviceProvider>();
            final group = provider.groupOf(groupMac);
            if (group == null) {
              return Center(child: Text('Nhóm không tồn tại', style: TextStyle(color: textSub)));
            }
            final members = group.memberMacs.toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header nhóm
                Row(children: [
                  CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.15), child: Icon(group.icon, color: tkGreen)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(group.name, style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 20),
                Text('Thiết bị trong nhóm (${members.length})',
                    style: TextStyle(color: textSub, fontSize: 15, height: 1.3, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 8),
                if (members.isEmpty)
                  Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('Nhóm chưa có thiết bị nào.', style: TextStyle(color: textSub))))
                else
                  ...members.map((mac) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: Icon(Icons.lightbulb_outline, color: tkGreen),
                          title: Text(_nameOf(deviceProv, mac), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                          subtitle: Text(mac, style: TextStyle(color: textSub, fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                            // await + báo lỗi rõ ràng: gỡ mà server không lưu được thì
                            // thành viên tự quay lại danh sách (revert) kèm SnackBar đỏ
                            onPressed: () async {
                              final err = await provider.removeFromGroup(groupMac, mac);
                              if (err != null && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                              }
                            },
                          ),
                        ),
                      )),
                const SizedBox(height: 16),
                // Nút thêm thiết bị -> picker
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: tkGreen, side: const BorderSide(color: tkGreen), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm thiết bị vào nhóm'),
                    onPressed: () => _pickDevices(context, provider, group),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Picker chọn thêm công tắc CHƯA thuộc nhóm — [KÍNH MỜ ĐỒNG BỘ] qua showGlassPopup
  // (PC: dialog giữa màn hình; Mobile: sheet; màu chữ do panel kính ép tương phản)
  void _pickDevices(BuildContext context, RoomGroupProvider provider, DeviceGroup group) {
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    final candidates = availableDevices.where((d) {
      final mac = (d['mac'] ?? '').toString().toUpperCase();
      return mac.isNotEmpty && !group.memberMacs.contains(mac) && !mac.startsWith('GROUP_');
    }).toList();

    showGlassPopup(
      context,
      title: 'Thêm thiết bị vào nhóm',
      body: (ctx) => candidates.isEmpty
          ? const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 16), child: Text('Không còn thiết bị nào để thêm.'))
          : ListView(
              shrinkWrap: true,
              children: candidates.map((d) {
                final mac = (d['mac'] ?? '').toString();
                // [DISPLAY NAME] danh sách khả dụng cũng ưu tiên tên user đặt từ DPS
                final name = deviceProv.displayNameOf(mac, fallback: (d['name'] ?? mac).toString());
                return ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: tkGreen),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(mac, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    // await kết quả persist thật — thất bại là thấy SnackBar đỏ ngay,
                    // không còn cảnh thêm "thành công" trên RAM rồi bốc hơi sau restart
                    final err = await provider.addToGroup(group.mac, mac);
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                    }
                  },
                );
              }).toList(),
            ),
    );
  }
}
