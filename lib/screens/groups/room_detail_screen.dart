import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/device_provider.dart';
import '../../providers/room_group_provider.dart';
import '../../widgets/glass_popup.dart';

/// RoomDetailScreen — Chi tiết MỘT phòng: danh sách thiết bị đang thuộc phòng
/// (VUỐT sang trái hoặc bấm nút gỡ để xóa khỏi phòng), nút "Thêm thiết bị" mở
/// bottom sheet liệt kê các thiết bị CHƯA thuộc phòng nào để gán vào.
/// Tên thiết bị đọc trực tiếp từ kho DPS (DeviceProvider) — không cần truyền list.
class RoomDetailScreen extends StatelessWidget {
  final String roomId;
  const RoomDetailScreen({super.key, required this.roomId});

  static const Color tkGreen = Color(0xFF00A651);

  /// Tên hiển thị của thiết bị: ưu tiên tên Backend gắn cho endpoint đầu tiên,
  /// chưa có tên thì hiện "Thiết bị {4 ký tự cuối MAC}".
  static String displayName(DeviceProvider deviceProvider, String mac) {
    final device = deviceProvider.deviceOf(mac);
    if (device != null) {
      for (final ep in device.endpointIds) {
        final name = device.nameOf(ep);
        if (name != null && name.trim().isNotEmpty) return name;
      }
    }
    final clean = mac.replaceAll(':', '').toUpperCase();
    return 'Thiết bị ${clean.length >= 4 ? clean.substring(clean.length - 4) : clean}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Consumer2<RoomGroupProvider, DeviceProvider>(
      builder: (context, roomProvider, deviceProvider, _) {
        final macs = roomProvider.devicesInRoom(roomId);
        final String roomName = roomProvider.roomName(roomId);

        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
          appBar: AppBar(
            title: Text(roomName, maxLines: 1, overflow: TextOverflow.ellipsis),
            backgroundColor: cardColor,
            foregroundColor: textMain,
            elevation: 0,
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: tkGreen,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Thêm thiết bị'),
            onPressed: () => _pickDevices(context, roomProvider, deviceProvider),
          ),
          body: SafeArea(
            child: macs.isEmpty
                ? Center(
                    child: Text('Phòng chưa có thiết bị nào.\nBấm "Thêm thiết bị" để gán vào phòng.',
                        textAlign: TextAlign.center, style: TextStyle(color: textSub)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: macs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final mac = macs[index];
                      return Dismissible(
                        key: ValueKey('room_dev_$mac'),
                        direction: DismissDirection.endToStart, // vuốt sang trái để gỡ khỏi phòng
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(14)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('Gỡ khỏi phòng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            SizedBox(width: 8),
                            Icon(Icons.remove_circle_outline, color: Colors.white),
                          ]),
                        ),
                        onDismissed: (_) => _removeDevice(context, roomProvider, deviceProvider, mac, roomName),
                        child: Material(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            leading: CircleAvatar(
                              backgroundColor: tkGreen.withValues(alpha: 0.15),
                              child: const Icon(Icons.devices_other, color: tkGreen),
                            ),
                            title: Text(displayName(deviceProvider, mac),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600)),
                            subtitle: Text(mac, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textSub, fontSize: 11)),
                            trailing: IconButton(
                              tooltip: 'Gỡ khỏi phòng',
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                              onPressed: () => _removeDevice(context, roomProvider, deviceProvider, mac, roomName),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _removeDevice(BuildContext context, RoomGroupProvider roomProvider, DeviceProvider deviceProvider, String mac, String roomName) async {
    final name = displayName(deviceProvider, mac);
    // API thật (optimistic bên provider — UI gỡ ngay, lỗi thì provider tự gắn lại)
    final err = await roomProvider.removeDeviceFromRoom(mac, roomId: roomId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'Đã gỡ "$name" khỏi phòng "$roomName"'),
      backgroundColor: err == null ? tkGreen : Colors.redAccent,
    ));
  }

  /// Picker chọn thiết bị CHƯA thuộc phòng nào — [KÍNH MỜ ĐỒNG BỘ] qua showGlassPopup
  /// (PC: dialog giữa màn hình; Mobile: sheet). Màu chữ kế thừa panel kính (ép tương phản).
  void _pickDevices(BuildContext context, RoomGroupProvider roomProvider, DeviceProvider deviceProvider) {
    final candidates = deviceProvider.devices.keys
        .where((mac) => roomProvider.roomOf(mac) == null && !roomProvider.isGroupMac(mac))
        .toList();

    showGlassPopup(
      context,
      title: 'Chọn thiết bị thêm vào phòng',
      body: (ctx) => candidates.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text('Không còn thiết bị trống — tất cả đã thuộc một phòng.'),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final mac = candidates[i];
                return ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: tkGreen),
                  title: Text(displayName(deviceProvider, mac),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(mac, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final err = await roomProvider.assignDevicesToRoom([mac], roomId);
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                    }
                  },
                );
              },
            ),
    );
  }
}
