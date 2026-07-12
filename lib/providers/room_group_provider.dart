import 'package:flutter/material.dart';

/// Phòng (Room) — mock tĩnh trước khi đấu API Backend.
class Room {
  final String id;
  String name;
  Room({required this.id, required this.name});
}

/// Nhóm thiết bị / Công tắc ảo (Virtual Switch Group). mac dạng "GROUP_xxx" để render
/// bằng chính SmartSwitchCard (phân biệt bằng badge). memberMacs = MAC các thiết bị con.
class DeviceGroup {
  final String mac; // "GROUP_xxx" — dùng như MAC ảo
  String name;
  int iconCodePoint; // icon do user chọn (lưu codePoint để dễ serialize sau này)
  final Set<String> memberMacs;
  DeviceGroup({required this.mac, required this.name, required this.iconCodePoint, Set<String>? members})
      : memberMacs = members ?? {};

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');
}

/// RoomGroupProvider — QUẢN LÝ TĨNH (mock) danh sách Phòng + Nhóm + gán thiết bị.
/// Đây là lớp state trung gian: UI thao tác qua đây, sau này chỉ cần thay phần thân hàm
/// bằng call API Backend là xong, KHÔNG phải đụng lại UI.
class RoomGroupProvider extends ChangeNotifier {
  // ===================== PHÒNG (ROOMS) =====================
  final List<Room> _rooms = [
    Room(id: 'room_living', name: 'Phòng khách'),
    Room(id: 'room_bed', name: 'Phòng ngủ'),
    Room(id: 'room_kitchen', name: 'Bếp'),
  ];
  final Map<String, String> _deviceRoom = {}; // MAC(HOA) -> roomId

  List<Room> get rooms => List.unmodifiable(_rooms);

  // Phòng đang xem trên Dashboard (null = "Tất cả")
  String? _selectedRoomId;
  String? get selectedRoomId => _selectedRoomId;
  void selectRoom(String? id) {
    _selectedRoomId = id;
    notifyListeners();
  }

  // Trạng thái BẬT/TẮT mock của công tắc tổng từng phòng (UI phản ánh ngay; fan-out thật do Dashboard lo)
  final Map<String, bool> _roomOn = {};
  bool roomOn(String roomId) => _roomOn[roomId] ?? false;
  void toggleRoom(String roomId, bool on) {
    _roomOn[roomId] = on;
    notifyListeners();
  }

  // MAC các thiết bị đang thuộc một phòng
  List<String> devicesInRoom(String roomId) =>
      _deviceRoom.entries.where((e) => e.value == roomId).map((e) => e.key).toList();

  void renameRoom(String roomId, String name) {
    final r = _rooms.firstWhere((x) => x.id == roomId, orElse: () => Room(id: '', name: ''));
    if (r.id.isNotEmpty) {
      r.name = name.trim();
      notifyListeners();
    }
  }

  void deleteRoom(String roomId) {
    _rooms.removeWhere((r) => r.id == roomId);
    _deviceRoom.removeWhere((mac, rid) => rid == roomId);
    _roomOn.remove(roomId);
    if (_selectedRoomId == roomId) _selectedRoomId = null;
    notifyListeners();
  }

  Room createRoom(String name) {
    final r = Room(id: 'room_${DateTime.now().millisecondsSinceEpoch}', name: name.trim());
    _rooms.add(r);
    notifyListeners();
    return r;
  }

  /// Chuyển/Thêm HÀNG LOẠT thiết bị vào một phòng (mock). Đấu API sau: POST /rooms/:id/devices.
  Future<void> assignDevicesToRoom(List<String> macs, String roomId) async {
    await Future.delayed(const Duration(milliseconds: 400)); // giả lập độ trễ mạng để test loading
    for (final m in macs) {
      _deviceRoom[m.toUpperCase()] = roomId;
    }
    notifyListeners();
  }

  String? roomOf(String mac) => _deviceRoom[mac.toUpperCase()];
  String roomName(String roomId) => _rooms.firstWhere((r) => r.id == roomId, orElse: () => Room(id: '', name: '—')).name;

  // ===================== NHÓM (GROUPS) =====================
  final List<DeviceGroup> _groups = [];

  List<DeviceGroup> get groups => List.unmodifiable(_groups);

  bool isGroupMac(String mac) => mac.toUpperCase().startsWith('GROUP_');

  DeviceGroup? groupOf(String mac) {
    for (final g in _groups) {
      if (g.mac == mac) return g;
    }
    return null;
  }

  /// Tạo nhóm mới từ tập MAC đã chọn (mock). Đấu API sau: POST /groups.
  DeviceGroup createGroup(String name, int iconCodePoint, List<String> members) {
    final g = DeviceGroup(
      mac: 'GROUP_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      iconCodePoint: iconCodePoint,
      members: members.map((e) => e.toUpperCase()).toSet(),
    );
    _groups.add(g);
    notifyListeners();
    return g;
  }

  void addToGroup(String groupMac, String deviceMac) {
    groupOf(groupMac)?.memberMacs.add(deviceMac.toUpperCase());
    notifyListeners();
  }

  void removeFromGroup(String groupMac, String deviceMac) {
    groupOf(groupMac)?.memberMacs.remove(deviceMac.toUpperCase());
    notifyListeners();
  }

  void renameGroup(String groupMac, String name) {
    final g = groupOf(groupMac);
    if (g != null) {
      g.name = name.trim();
      notifyListeners();
    }
  }

  void deleteGroup(String groupMac) {
    _groups.removeWhere((g) => g.mac == groupMac);
    notifyListeners();
  }
}
