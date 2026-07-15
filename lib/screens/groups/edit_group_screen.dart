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
  // ==========================================================================
  // PICKER THÀNH VIÊN — [CONSTRAINT-BASED] danh sách PHẲNG phân cấp MAC > Endpoint
  // ==========================================================================
  // Kiến trúc chịu tải 16-32 kênh:
  //   - Hàng render qua ListView.builder trên danh sách _PickRow đã PHẲNG HÓA
  //     (header thiết bị + từng kênh) — không lồng ExpansionTile, không rebuild cả cây.
  //   - Mỗi checkbox kênh là MỘT ĐƠN VỊ ĐỘC LẬP: tick/untick không đụng kênh khác,
  //     TRỪ KHI GroupConstraintEngine ra lệnh (vd nhóm Quạt auto-uncheck kênh cũ).
  //   - UI KHÔNG chứa quy tắc: thêm loại nhóm mới chỉ cần thêm entry vào
  //     GroupConstraint.byGroupType (provider) — file này không phải sửa.
  //   - Xác nhận một lần -> provider.replaceMembers (một PUT duy nhất).
  void _pickDevices(BuildContext context, RoomGroupProvider provider, DeviceGroup group) {
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);

    // ---- PHẲNG HÓA: MAC > Endpoint ----
    final rows = <_PickRow>[];
    for (final d in availableDevices) {
      final mac = (d['mac'] ?? '').toString().toUpperCase();
      if (mac.isEmpty || mac.startsWith('GROUP_')) continue;
      final name = deviceProv.displayNameOf(mac, fallback: (d['name'] ?? mac).toString());
      final device = deviceProv.deviceOf(mac);
      final eps = (device?.endpointIds ?? const []).toList()..sort();

      if (eps.length <= 1) {
        // Đơn kênh: một hàng checkbox mang tên thiết bị
        rows.add(_PickRow.channel(mac: mac, endpoint: eps.isEmpty ? '' : eps.first, label: name, subtitle: mac));
        continue;
      }
      // Đa kênh: header (không checkbox) + từng kênh một hàng độc lập
      rows.add(_PickRow.header(mac: mac, label: name, subtitle: '$mac • ${eps.length} kênh'));
      // Thành viên "cả thiết bị" kiểu cũ (endpoint rỗng) của thiết bị đa kênh:
      // hiện hàng riêng để user thấy và gỡ được (di sản trước multi-channel)
      if (group.hasMember(mac)) {
        rows.add(_PickRow.channel(mac: mac, endpoint: '', label: 'Cả thiết bị (kiểu cũ)', subtitle: 'lệnh chung "all" — bỏ tick để chuyển sang từng kênh'));
      }
      for (final ep in eps) {
        final String? epName = device?.nameOf(ep);
        final String label = (epName != null && epName.trim().isNotEmpty) ? epName.trim() : _channelLabel(ep);
        rows.add(_PickRow.channel(mac: mac, endpoint: ep, label: label, subtitle: ep));
      }
    }

    // ---- BẢN NHÁP THÀNH VIÊN: copy đầy đủ (giữ floor + thành viên không hiện trong picker) ----
    final working = [
      for (final m in group.members) GroupMemberRef(mac: m.mac, endpoint: m.endpoint, floor: m.floor)
    ];

    showGlassPopup(
      context,
      title: 'Chọn thành viên nhóm',
      body: (ctx) => rows.isEmpty
          ? const Padding(padding: EdgeInsets.fromLTRB(24, 8, 24, 16), child: Text('Không có thiết bị/kênh nào để chọn.'))
          : StatefulBuilder(
              builder: (ctx, setSheet) {
                bool isChecked(_PickRow r) => working.any((m) => m.key == '${r.mac}|${r.endpoint}');

                void toggle(_PickRow r) {
                  final key = '${r.mac}|${r.endpoint}';
                  if (isChecked(r)) {
                    setSheet(() => working.removeWhere((m) => m.key == key)); // untick độc lập
                    return;
                  }
                  // [CONSTRAINT ENGINE] mọi lần tick đều xin phán quyết
                  final attempt = GroupMemberRef(mac: r.mac, endpoint: r.endpoint);
                  final res = GroupConstraintEngine.resolve(
                      groupType: group.groupType, current: working, attempt: attempt);
                  if (!res.allowed) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(res.reason ?? 'Vi phạm quy tắc nhóm'), backgroundColor: Colors.redAccent));
                    return;
                  }
                  setSheet(() {
                    // Engine ra lệnh bỏ kênh nào thì auto-uncheck đúng kênh đó (vd nhóm Quạt)
                    working.removeWhere((m) => res.removeFirst.any((x) => x.key == m.key));
                    working.add(attempt);
                  });
                }

                return Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        if (r.isHeader) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                            child: Row(children: [
                              const Icon(Icons.grid_view_rounded, color: tkGreen, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                              Text(r.subtitle, style: const TextStyle(fontSize: 10.5)),
                            ]),
                          );
                        }
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.only(left: r.endpoint.isEmpty && r.subtitle == r.mac ? 16 : 32, right: 16),
                          activeColor: tkGreen,
                          value: isChecked(r),
                          title: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5)),
                          onChanged: (_) => toggle(r),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          // MỘT PUT duy nhất cho cả phiên chọn — persist thật + revert nguyên khối khi lỗi
                          final err = await provider.replaceMembers(group.mac, working);
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                          }
                        },
                        child: Text('Lưu thành viên (${working.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ]);
              },
            ),
    );
  }
}

/// Một hàng trong picker phẳng hóa: header thiết bị (đa kênh) hoặc checkbox kênh.
class _PickRow {
  final bool isHeader;
  final String mac;
  final String endpoint;
  final String label;
  final String subtitle;
  const _PickRow._(this.isHeader, this.mac, this.endpoint, this.label, this.subtitle);
  const _PickRow.header({required String mac, required String label, required String subtitle})
      : this._(true, mac, '', label, subtitle);
  const _PickRow.channel({required String mac, required String endpoint, required String label, required String subtitle})
      : this._(false, mac, endpoint, label, subtitle);
}
