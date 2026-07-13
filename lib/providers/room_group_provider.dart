import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

/// Phòng (Room) — nay là bản chiếu của bảng SQL `rooms` bên Backend.
class Room {
  final String id;
  String name;
  int orderIndex; // thứ tự hiển thị do user kéo-thả (nhỏ đứng trước)
  final DateTime? createdAt;
  Room({required this.id, required this.name, this.orderIndex = 0, this.createdAt});

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      );
}

/// Nhóm thiết bị / Công tắc ảo (Virtual Switch Group). mac dạng "GROUP_xxx" để render
/// bằng chính SmartSwitchCard (phân biệt bằng badge). memberMacs = MAC các thiết bị con.
/// (Nhóm vẫn là mock cục bộ — Backend chưa có bảng groups.)
class DeviceGroup {
  final String mac; // "GROUP_xxx" — dùng như MAC ảo
  String name;
  int iconCodePoint; // icon do user chọn (lưu codePoint để dễ serialize sau này)
  final Set<String> memberMacs;
  DeviceGroup({required this.mac, required this.name, required this.iconCodePoint, Set<String>? members})
      : memberMacs = members ?? {};

  /// Bộ icon nhóm user chọn được (đồng bộ với showCreateGroupDialog) — CONST để tra
  /// ngược từ codePoint, không dựng IconData động (giữ icon tree-shaking + analyze sạch).
  static const List<IconData> groupIcons = [
    Icons.lightbulb_outline, Icons.grid_view_rounded, Icons.power_settings_new_rounded,
    Icons.blinds_closed, Icons.home_rounded, Icons.bolt_rounded, Icons.tv_rounded, Icons.ac_unit_rounded,
  ];

  IconData get icon =>
      groupIcons.firstWhere((i) => i.codePoint == iconCodePoint, orElse: () => Icons.grid_view_rounded);
}

/// RoomGroupProvider — QUẢN LÝ PHÒNG NỐI API THẬT (cụm /api/rooms bên Backend Golang)
/// + Nhóm công tắc ảo (vẫn mock cục bộ). Giữ NGUYÊN chữ ký các hàm UI đang gọi
/// (rooms, devicesInRoom, createRoom, renameRoom, deleteRoom, assignDevicesToRoom(macs, roomId),
/// removeDeviceFromRoom(mac)...) — chỉ thay ruột mock bằng HTTP; hàm ghi trả về
/// `Future<String?>`: null = thành công, chuỗi = câu báo lỗi cho UI hiện SnackBar.
class RoomGroupProvider extends ChangeNotifier {
  // ===================== HTTP HELPER =====================
  // Dùng chung Base URL + kho token với ApiService để không lệch cấu hình
  static const String _apiBase = ApiService.baseUrl; // vd: https://api.iot-smart.vn/api

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorageService.getToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  /// Bóc câu báo lỗi thân thiện từ body Backend ({"error": "..."}); rơi về HTTP code.
  String _errorFrom(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {}
    return '$fallback (HTTP ${res.statusCode})';
  }

  // ===================== PHÒNG (ROOMS) — API THẬT =====================
  List<Room> _rooms = [];
  final Map<String, String> _deviceRoom = {}; // MAC(HOA) -> roomId (dựng lại từ device_macs)
  String _homeId = ''; // nhà đang hoạt động — fetchRooms ghi nhớ để createRoom dùng lại

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Room> get rooms => List.unmodifiable(_rooms);
  String get activeHomeId => _homeId;

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

  String? roomOf(String mac) => _deviceRoom[mac.toUpperCase()];
  String roomName(String roomId) => _rooms.firstWhere((r) => r.id == roomId, orElse: () => Room(id: '', name: '—')).name;

  /// GET /api/rooms?home_id=... — nạp danh sách phòng (Backend đã sort mới nhất trước)
  /// KÈM device_macs từng phòng -> dựng lại map MAC->room trong MỘT lời gọi.
  /// Dashboard gọi sau khi biết home_id (cả luồng user thường lẫn SUPER_USER chọn nhà).
  Future<String?> fetchRooms(String homeId) async {
    if (homeId.isEmpty) return 'Thiếu home_id';
    _homeId = homeId;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/rooms?home_id=${Uri.encodeComponent(homeId)}'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return _errorFrom(res, 'Không tải được danh sách phòng');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['rooms'] as List? ?? []);
      _rooms = list.map((e) => Room.fromJson(Map<String, dynamic>.from(e))).toList();

      _deviceRoom.clear();
      for (final e in list) {
        final roomId = (e['id'] ?? '').toString();
        for (final mac in (e['device_macs'] as List? ?? [])) {
          _deviceRoom[mac.toString().toUpperCase()] = roomId;
        }
      }
      // Phòng đang chọn trên Dashboard đã bị xóa ở máy khác -> quay về "Tất cả"
      if (_selectedRoomId != null && !_rooms.any((r) => r.id == _selectedRoomId)) {
        _selectedRoomId = null;
      }
      // Log chẩn đoán: đối chiếu số phòng/thiết bị server trả về với UI đang vẽ
      if (kDebugMode) {
        print('🏠 [ROOMS] Server trả ${_rooms.length} phòng, ${_deviceRoom.length} thiết bị đã gán (home $homeId)');
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [ROOMS] Lỗi tải phòng: $e');
      return 'Lỗi kết nối máy chủ';
    } finally {
      _isLoading = false;
      notifyListeners(); // một notify duy nhất cho cả thành công lẫn thất bại
    }
  }

  /// POST /api/rooms — tạo phòng mới. Giữ chữ ký cũ createRoom(name); [homeId] tùy chọn
  /// (mặc định dùng nhà đã fetchRooms). Thành công: chèn phòng server trả về lên ĐẦU list
  /// (khớp thứ tự "mới nhất trước" của Backend).
  Future<String?> createRoom(String name, {String? homeId}) async {
    final home = homeId ?? _homeId;
    if (home.isEmpty) return 'Chưa xác định được nhà hiện tại';
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/rooms'),
        headers: await _authHeaders(),
        body: jsonEncode({'home_id': home, 'name': name.trim()}),
      );
      if (res.statusCode != 201) return _errorFrom(res, 'Không tạo được phòng');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // Backend gán order_index = max+1 nên phòng mới nằm CUỐI danh sách -> chèn cuối cho khớp
      _rooms.add(Room.fromJson(Map<String, dynamic>.from(body['room'] ?? {})));
      notifyListeners();
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [ROOMS] Lỗi tạo phòng: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// Kéo-thả sắp lại thứ tự phòng — Optimistic UI: đảo vị trí trong _rooms NGAY cho
  /// giao diện mượt, gán lại orderIndex tuần tự rồi mới PUT /api/rooms/reorder ngầm.
  /// API lỗi -> revert nguyên trạng danh sách cũ + trả câu báo lỗi.
  /// [newIndex] đã được ReorderableListView (onReorderItem) chỉnh sẵn cho item bị gỡ.
  Future<String?> reorderRooms(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= _rooms.length) return null;
    if (newIndex < 0) newIndex = 0;
    if (newIndex >= _rooms.length) newIndex = _rooms.length - 1;

    final List<Room> backup = List.of(_rooms); // ảnh chụp để revert khi lỗi
    final moved = _rooms.removeAt(oldIndex);
    _rooms.insert(newIndex, moved);
    // Gán lại orderIndex theo vị trí mới (0..n-1) — nguồn sự thật gửi lên server
    for (int i = 0; i < _rooms.length; i++) {
      _rooms[i].orderIndex = i;
    }
    notifyListeners();

    try {
      final res = await http.put(
        Uri.parse('$_apiBase/rooms/reorder'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'orders': [for (final r in _rooms) {'id': r.id, 'order_index': r.orderIndex}],
        }),
      );
      if (res.statusCode != 200) {
        _rooms = backup; // revert
        notifyListeners();
        return _errorFrom(res, 'Không lưu được thứ tự phòng');
      }
      return null;
    } catch (e) {
      _rooms = backup;
      notifyListeners();
      if (kDebugMode) print('❌ [ROOMS] Lỗi sắp xếp phòng: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// PUT /api/rooms/:id — đổi tên phòng. Optimistic: đổi tên cục bộ NGAY cho UI mượt,
  /// API lỗi thì hoàn tác lại tên cũ + trả câu báo lỗi.
  Future<String?> renameRoom(String roomId, String name) async {
    final idx = _rooms.indexWhere((r) => r.id == roomId);
    if (idx == -1) return 'Phòng không tồn tại';
    final room = _rooms[idx];
    final String oldName = room.name;
    room.name = name.trim();
    notifyListeners();
    try {
      final res = await http.put(
        Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(roomId)}'),
        headers: await _authHeaders(),
        body: jsonEncode({'name': name.trim()}),
      );
      if (res.statusCode != 200) {
        room.name = oldName; // hoàn tác
        notifyListeners();
        return _errorFrom(res, 'Không đổi được tên phòng');
      }
      return null;
    } catch (e) {
      room.name = oldName;
      notifyListeners();
      if (kDebugMode) print('❌ [ROOMS] Lỗi đổi tên phòng: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// DELETE /api/rooms/:id — xóa phòng (thiết bị tự rời phòng nhờ SET NULL bên Backend).
  /// Optimistic: gỡ khỏi list ngay (Dismissible đã trượt xong); lỗi thì fetch lại để khôi phục.
  Future<String?> deleteRoom(String roomId) async {
    final removedIndex = _rooms.indexWhere((r) => r.id == roomId);
    if (removedIndex == -1) return null;
    _rooms.removeAt(removedIndex);
    _deviceRoom.removeWhere((mac, rid) => rid == roomId);
    _roomOn.remove(roomId);
    if (_selectedRoomId == roomId) _selectedRoomId = null;
    notifyListeners();
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(roomId)}'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        await fetchRooms(_homeId); // khôi phục từ server — nguồn sự thật
        return _errorFrom(res, 'Không xóa được phòng');
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [ROOMS] Lỗi xóa phòng: $e');
      await fetchRooms(_homeId);
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// POST /api/rooms/:id/devices — gán HÀNG LOẠT thiết bị vào phòng.
  /// GIỮ CHỮ KÝ CŨ (macs, roomId) đúng như Dashboard/RoomDetailScreen đang gọi.
  Future<String?> assignDevicesToRoom(List<String> macs, String roomId) async {
    if (macs.isEmpty) return null;
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(roomId)}/devices'),
        headers: await _authHeaders(),
        body: jsonEncode({'device_macs': macs}),
      );
      if (res.statusCode != 200) return _errorFrom(res, 'Không gán được thiết bị vào phòng');

      for (final m in macs) {
        _deviceRoom[m.toUpperCase()] = roomId;
      }
      notifyListeners();
      // [FIX MẤT THIẾT BỊ SAU RESTART] Đồng bộ lại từ server NGAY sau khi ghi:
      // local state luôn hội tụ về sự thật đã persist trong Postgres — nếu server
      // không lưu được thì thiết bị rời phòng ngay trước mắt (kèm log 🏠 chẩn đoán),
      // không còn cảnh "tưởng đã lưu" rồi mất khi mở lại App.
      if (_homeId.isNotEmpty) fetchRooms(_homeId);
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [ROOMS] Lỗi gán thiết bị: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// DELETE /api/rooms/:id/devices/:mac — gỡ MỘT thiết bị khỏi phòng.
  /// GIỮ CHỮ KÝ CŨ removeDeviceFromRoom(mac): roomId tự suy từ map cục bộ,
  /// hoặc truyền tường minh qua [roomId] nếu nơi gọi có sẵn.
  Future<String?> removeDeviceFromRoom(String mac, {String? roomId}) async {
    final sn = mac.toUpperCase();
    final rid = roomId ?? _deviceRoom[sn];
    if (rid == null) return null; // vốn không thuộc phòng nào — coi như xong (idempotent)

    // Optimistic: gỡ cục bộ ngay, lỗi thì gắn lại
    _deviceRoom.remove(sn);
    notifyListeners();
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/rooms/${Uri.encodeComponent(rid)}/devices/${Uri.encodeComponent(sn)}'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        _deviceRoom[sn] = rid; // hoàn tác
        notifyListeners();
        return _errorFrom(res, 'Không gỡ được thiết bị khỏi phòng');
      }
      // [FIX MẤT THIẾT BỊ SAU RESTART] Hội tụ về sự thật server sau mỗi lần ghi
      if (_homeId.isNotEmpty) fetchRooms(_homeId);
      return null;
    } catch (e) {
      _deviceRoom[sn] = rid;
      notifyListeners();
      if (kDebugMode) print('❌ [ROOMS] Lỗi gỡ thiết bị: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  // ===================== NHÓM (GROUPS) — VẪN MOCK CỤC BỘ =====================
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
