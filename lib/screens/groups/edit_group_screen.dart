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

  /// Nhãn ngắn của một kênh: 'S_xxx_2' -> 'Relay 2'; 'D1'/'F1' giữ nguyên; khác -> Kênh.
  static String _channelLabel(String endpoint) {
    final m = RegExp(r'[_-](\d+)$').firstMatch(endpoint);
    if (m != null) return 'Relay ${m.group(1)}';
    if (RegExp(r'^[A-Za-z]\d+$').hasMatch(endpoint)) return endpoint; // D1, F1...
    return 'Kênh';
  }

  /// [MULTI-CHANNEL] Tên hiển thị của MỘT THÀNH VIÊN: ưu tiên tên user đặt cho đúng
  /// kênh đó ("Đèn Bếp"); chưa đặt thì "Tên thiết bị (Relay 2)"; member kiểu cũ
  /// (endpoint rỗng = cả thiết bị) dùng tên thiết bị như trước.
  String _memberName(DeviceProvider deviceProv, GroupMemberRef m) {
    if (m.endpoint.isEmpty) return _nameOf(deviceProv, m.mac);
    final String? epName = deviceProv.deviceOf(m.mac)?.nameOf(m.endpoint);
    if (epName != null && epName.trim().isNotEmpty) return epName.trim();
    return '${_nameOf(deviceProv, m.mac)} (${_channelLabel(m.endpoint)})';
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
            final members = group.members;
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
                  ...members.map((m) {
                    // Subtitle: MAC + kênh (nếu là thành viên đa kênh) + tầng (nhóm cầu thang)
                    final String sub = [
                      m.mac,
                      if (m.endpoint.isNotEmpty) m.endpoint,
                      if (m.floor.isNotEmpty) m.floor,
                    ].join(' • ');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(m.endpoint.isEmpty ? Icons.lightbulb_outline : Icons.power_rounded, color: tkGreen),
                        title: Text(_memberName(deviceProv, m), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                        subtitle: Text(sub, style: TextStyle(color: textSub, fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                          // await + báo lỗi rõ ràng: gỡ mà server không lưu được thì
                          // thành viên tự quay lại danh sách (revert) kèm SnackBar đỏ.
                          // endpoint truyền TƯỜNG MINH — chỉ gỡ đúng kênh này.
                          onPressed: () async {
                            final err = await provider.removeFromGroup(groupMac, m.mac, endpoint: m.endpoint);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                            }
                          },
                        ),
                      ),
                    );
                  }),
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

    // [MULTI-CHANNEL] Ứng viên tính theo TỪNG KÊNH: thiết bị đa kênh (SSW04, Hub) mà
    // mới góp 2/4 kênh vào nhóm thì 2 kênh còn lại VẪN là ứng viên hợp lệ.
    // Loại: MAC ảo nhóm, thiết bị đã vào nhóm kiểu "cả thiết bị" (endpoint rỗng).
    final candidates = availableDevices.where((d) {
      final mac = (d['mac'] ?? '').toString().toUpperCase();
      if (mac.isEmpty || mac.startsWith('GROUP_') || group.hasMember(mac)) return false;
      final eps = deviceProv.deviceOf(mac)?.endpointIds ?? const [];
      if (eps.length <= 1) return !group.memberMacs.contains(mac); // đơn kênh: còn trống mới hiện
      return eps.any((ep) => !group.hasMember(mac, ep)); // đa kênh: còn kênh trống là hiện
    }).toList();

    // Thêm xong một thành viên: đóng picker + báo lỗi đỏ nếu server không persist
    Future<void> addMember(BuildContext ctx, String mac, String endpoint) async {
      Navigator.pop(ctx);
      final err = await provider.addToGroup(group.mac, mac, endpoint: endpoint);
      if (err != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
      }
    }

    showGlassPopup(
      context,
      title: 'Thêm thiết bị vào nhóm',
      body: (ctx) => candidates.isEmpty
          ? const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 16), child: Text('Không còn thiết bị/kênh nào để thêm.'))
          : ListView(
              shrinkWrap: true,
              children: candidates.map((d) {
                final mac = (d['mac'] ?? '').toString();
                // [DISPLAY NAME] danh sách khả dụng cũng ưu tiên tên user đặt từ DPS
                final name = deviceProv.displayNameOf(mac, fallback: (d['name'] ?? mac).toString());
                final device = deviceProv.deviceOf(mac);
                final eps = (device?.endpointIds ?? const []).toList()..sort();

                // ---- THIẾT BỊ ĐƠN KÊNH: một dòng, chạm là thêm (endpoint tường minh nếu biết) ----
                if (eps.length <= 1) {
                  return ListTile(
                    leading: const Icon(Icons.add_circle_outline, color: tkGreen),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(mac, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    onTap: () => addMember(ctx, mac, eps.isEmpty ? '' : eps.first),
                  );
                }

                // ---- [MULTI-CHANNEL] THIẾT BỊ ĐA KÊNH: mở rộng chọn riêng từng relay ----
                return ExpansionTile(
                  leading: const Icon(Icons.grid_view_rounded, color: tkGreen),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('$mac • ${eps.length} kênh — chạm để chọn từng relay',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  iconColor: tkGreen,
                  collapsedIconColor: tkGreen,
                  children: eps.map((ep) {
                    final bool already = group.hasMember(mac, ep);
                    final String? epName = device?.nameOf(ep);
                    final String label = (epName != null && epName.trim().isNotEmpty)
                        ? epName.trim()
                        : _channelLabel(ep);
                    return ListTile(
                      contentPadding: const EdgeInsets.only(left: 40, right: 16),
                      leading: Icon(already ? Icons.check_circle : Icons.add_circle_outline,
                          color: already ? Colors.grey : tkGreen, size: 20),
                      title: Text('$label${already ? '  (đã trong nhóm)' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, color: already ? Colors.grey : null)),
                      subtitle: Text(ep, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                      enabled: !already,
                      onTap: already ? null : () => addMember(ctx, mac, ep),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
    );
  }
}
