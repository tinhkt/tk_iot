import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/device_provider.dart';
import '../../providers/room_group_provider.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../widgets/glass_popup.dart';
import '../../localization/app_translations.dart';

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

  /// [TÁCH RELAY] Vị trí (0-based) của [endpoint] trong danh sách kênh điều khiển được
  /// (bỏ cảm biến) của thiết bị + tổng số kênh — dùng để hiển thị "Số N". [device] null
  /// (thiết bị chưa từng có tín hiệu MQTT) hoặc không tìm thấy endpoint -> (0, 1) an toàn,
  /// không hiện hậu tố "- Số" (channelCount <= 1 ở nơi gọi).
  static (int, int) _channelPosition(DeviceModel? device, String endpoint) {
    if (device == null) return (0, 1);
    final chans = device.endpointIds.where((ep) => device.typeOf(ep) != 'sensor').toList();
    final idx = chans.indexOf(endpoint);
    return (idx < 0 ? 0 : idx, chans.isEmpty ? 1 : chans.length);
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
        final channelEntries = roomProvider.endpointsInRoom(roomId);
        final String roomName = roomProvider.roomName(roomId);
        final t = AppTranslations.of(context);

        // [TÁCH RELAY] Gộp 2 nguồn hiển thị: nguyên khối (whole-device, đường cũ) +
        // kênh tách riêng (đường mới) thành MỘT danh sách duy nhất — endpoint rỗng =
        // nguyên khối, không rỗng = đúng 1 kênh cụ thể.
        final List<({String mac, String endpoint})> entries = [
          for (final m in macs) (mac: m, endpoint: ''),
          for (final e in channelEntries) (mac: e.mac, endpoint: e.endpoint),
        ];

        return AppScaffold(
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
            label: Text(t.text('add_device_label')),
            onPressed: () => _pickChannels(context, roomProvider, deviceProvider),
          ),
          body: SafeArea(
            child: entries.isEmpty
                ? Center(
                    child: Text(t.text('no_devices_in_room'),
                        textAlign: TextAlign.center, style: TextStyle(color: textSub)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final bool isChannel = entry.endpoint.isNotEmpty;
                      // "Tên thiết bị - Số N" CHỈ khi thiết bị thật sự có nhiều hơn 1 kênh điều
                      // khiển được — thiết bị 1 relay hiển thị tên trơn, không thêm hậu tố thừa.
                      final (int channelIndex, int channelCount) = isChannel
                          ? _channelPosition(deviceProvider.deviceOf(entry.mac), entry.endpoint)
                          : (0, 1);
                      final String title = isChannel && channelCount > 1
                          ? '${displayName(deviceProvider, entry.mac)}${t.text('channel_number_prefix')}${channelIndex + 1}'
                          : displayName(deviceProvider, entry.mac);
                      void doRemove() => isChannel
                          ? _removeEndpoint(context, roomProvider, deviceProvider, entry.mac, entry.endpoint, roomName)
                          : _removeDevice(context, roomProvider, deviceProvider, entry.mac, roomName);

                      return Dismissible(
                        key: ValueKey('room_dev_${entry.mac}_${entry.endpoint}'),
                        direction: DismissDirection.endToStart, // vuốt sang trái để gỡ khỏi phòng
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(14)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(t.text('remove_from_room'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            const Icon(Icons.remove_circle_outline, color: Colors.white),
                          ]),
                        ),
                        onDismissed: (_) => doRemove(),
                        child: Material(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            leading: CircleAvatar(
                              backgroundColor: tkGreen.withValues(alpha: 0.15),
                              child: Icon(isChannel ? Icons.toggle_on_outlined : Icons.devices_other, color: tkGreen),
                            ),
                            title: Text(title,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600)),
                            // [GIỮ NGUYÊN BIẾN ĐỘNG] MAC/endpoint thật — không dịch.
                            subtitle: Text(isChannel ? '${entry.mac} • ${entry.endpoint}' : entry.mac,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: textSub, fontSize: 11)),
                            trailing: IconButton(
                              tooltip: t.text('remove_from_room'),
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                              onPressed: doRemove,
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
    // Gọi từ Dismissible.onDismissed/IconButton.onPressed (tap/vuốt handler) -> listen: false,
    // tránh "liệt nút" (context.watch() ngoài pha build thật — xem app_translations.dart).
    final t = AppTranslations.of(context, listen: false);
    final name = displayName(deviceProvider, mac);
    // API thật (optimistic bên provider — UI gỡ ngay, lỗi thì provider tự gắn lại)
    final err = await roomProvider.removeDeviceFromRoom(mac, roomId: roomId);
    if (!context.mounted) return;
    // [MAPPING HIỂN THỊ — NỐI CHUỖI AN TOÀN] name/roomName GIỮ NGUYÊN động — chỉ 2 đoạn văn
    // quanh dịch qua removed_success_1/removed_success_2.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '${t.text('removed_success_1')}$name${t.text('removed_success_2')}"$roomName"'),
      backgroundColor: err == null ? tkGreen : Colors.redAccent,
    ));
  }

  /// [TÁCH RELAY] Gỡ MỘT kênh đã tách riêng khỏi phòng — song song _removeDevice ở trên,
  /// KHÔNG đụng các kênh khác cùng thiết bị (vẫn ở phòng của chúng nếu có).
  Future<void> _removeEndpoint(BuildContext context, RoomGroupProvider roomProvider, DeviceProvider deviceProvider, String mac, String endpoint, String roomName) async {
    // Gọi từ Dismissible.onDismissed/IconButton.onPressed (tap/vuốt handler) -> listen: false.
    final t = AppTranslations.of(context, listen: false);
    final (channelIndex, channelCount) = _channelPosition(deviceProvider.deviceOf(mac), endpoint);
    final String name = channelCount > 1
        ? '${displayName(deviceProvider, mac)}${t.text('channel_number_prefix')}${channelIndex + 1}'
        : displayName(deviceProvider, mac);
    final err = await roomProvider.removeEndpointFromRoom(mac, endpoint);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '${t.text('removed_success_1')}$name${t.text('removed_success_2')}"$roomName"'),
      backgroundColor: err == null ? tkGreen : Colors.redAccent,
    ));
  }

  /// [TÁCH RELAY — NHIỆM VỤ 2] Picker chọn KÊNH (endpoint) CHƯA thuộc phòng nào, thay vì cả
  /// thiết bị — công tắc đa relay giờ liệt kê từng nút riêng (tick chọn nhiều), cho phép chia
  /// các kênh của CÙNG một thiết bị vào các phòng khác nhau. [KÍNH MỜ ĐỒNG BỘ] qua
  /// showGlassPopup (PC: dialog giữa màn hình; Mobile: sheet).
  void _pickChannels(BuildContext context, RoomGroupProvider roomProvider, DeviceProvider deviceProvider) {
    // Gọi từ FAB onPressed (tap handler) -> listen: false, tránh "liệt nút" (xem giải thích ở
    // app_translations.dart).
    final t = AppTranslations.of(context, listen: false);

    // Ứng viên: MỌI kênh điều khiển được (bỏ cảm biến) của thiết bị THẬT (bỏ nhóm ảo GROUP_xxx)
    // mà CHƯA thuộc phòng nào — dù trước đây gán nguyên khối hay đã tách riêng. "Hiệu lực"
    // ưu tiên kênh đã tách (endpointRoomOf) trước, rơi về nguyên khối (roomOf) nếu chưa tách.
    final candidates = <({String mac, String endpoint, String deviceName, int channelIndex, int channelCount})>[];
    deviceProvider.devices.forEach((mac, device) {
      if (roomProvider.isGroupMac(mac)) return;
      final chans = device.endpointIds.where((ep) => device.typeOf(ep) != 'sensor').toList();
      for (int i = 0; i < chans.length; i++) {
        final ep = chans[i];
        final effectiveRoom = roomProvider.endpointRoomOf(mac, ep) ?? roomProvider.roomOf(mac);
        if (effectiveRoom != null) continue; // đã ở phòng khác (hoặc chính phòng này) -> ẩn
        candidates.add((mac: mac, endpoint: ep, deviceName: deviceProvider.displayNameOf(mac), channelIndex: i, channelCount: chans.length));
      }
    });

    showGlassPopup(
      context,
      title: t.text('pick_devices_title'),
      body: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        final Color textMain = isDark ? Colors.white : Colors.black87;
        final Color textSub = isDark ? Colors.white70 : Colors.black54;

        if (candidates.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(t.text('no_unassigned_devices'), style: TextStyle(color: textMain)),
          );
        }

        // "mac|endpoint" đang được tick — sống NGOÀI StatefulBuilder.builder để giữ nguyên
        // qua các lần setSheet (đúng khuôn _pickSensorCondition trong scene_step_pickers.dart).
        final selected = <String>{};
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.text('pick_channels_hint'), style: TextStyle(color: textSub, fontSize: 12)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final c = candidates[i];
                      final key = '${c.mac}|${c.endpoint}';
                      final bool isSel = selected.contains(key);
                      final String label = c.channelCount > 1 ? '${c.deviceName}${t.text('channel_number_prefix')}${c.channelIndex + 1}' : c.deviceName;
                      return CheckboxListTile(
                        value: isSel,
                        activeColor: tkGreen,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                        // [GIỮ NGUYÊN BIẾN ĐỘNG] mac/endpoint thật — không dịch.
                        subtitle: Text('${c.mac} • ${c.endpoint}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textSub, fontSize: 11)),
                        onChanged: (v) => setSheet(() {
                          if (v ?? false) {
                            selected.add(key);
                          } else {
                            selected.remove(key);
                          }
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            final items = [for (final key in selected) (mac: key.split('|')[0], endpoint: key.split('|')[1])];
                            final err = await roomProvider.assignEndpointsToRoom(items, roomId);
                            if (err != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                            }
                          },
                    child: Text(t.text('save')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
