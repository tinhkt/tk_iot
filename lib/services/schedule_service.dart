import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'secure_storage_service.dart';

/// Một dòng hẹn giờ/lịch trình của MỘT thiết bị — bản chiếu bảng SQL `device_schedules`.
class ScheduleItem {
  final String id;
  // [FIX MULTI-RELAY] Kênh cụ thể ("S_{mac}_2", "D1"...) — rỗng = cả thiết bị (lịch cũ,
  // Backend fallback bắn mọi kênh). Lịch tạo mới từ DeviceTimerScreen LUÔN mang endpoint.
  final String endpoint;
  String time;       // 'HH:MM' 24h
  String repeatDays; // nhãn lặp lại tự do (Backend lưu varchar): 'Hàng ngày', 'T2 - T6'...
  String action;     // 'ON' | 'OFF' — trùng payload lệnh MQTT
  bool isEnabled;
  // Chỉ có giá trị khi lấy từ GET /api/homes/:id/schedules (tab "Lịch trình" gộp) — rỗng khi
  // lấy từ GET /api/devices/:mac/schedules (đã biết sẵn thiết bị nào qua context màn hình).
  final String deviceMac;
  final String deviceName;
  // [LỆNH PHỨC TẠP] Khớp models.DeviceSchedule.ActionPayload bên Go — {"action":"speed",
  // "value":"2"} cho quạt/kênh không phải ON-OFF đơn thuần. 'set' (mặc định, tương thích
  // ngược 100% với lịch cũ chỉ có Action ON/OFF) | 'speed' | 'osc' | bất kỳ action khác do
  // Backend/firmware định nghĩa sau này (không giới hạn cứng danh sách ở Flutter).
  final String actionKind;
  final String actionValue;

  ScheduleItem({
    required this.id,
    required this.time,
    required this.repeatDays,
    required this.action,
    required this.isEnabled,
    this.endpoint = '',
    this.deviceMac = '',
    this.deviceName = '',
    String? actionKind,
    String? actionValue,
  })  : actionKind = actionKind ?? 'set',
        actionValue = actionValue ?? (action == 'ON' ? 'ON' : 'OFF');

  bool get isOn => action == 'ON';

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final String action = (json['action'] ?? 'OFF').toString().toUpperCase();
    String kind = 'set';
    String value = action;
    // action_payload là object JSON lồng ({"action":"speed","value":"2"}) hoặc null/rỗng
    // với lịch cũ chưa từng dùng lệnh phức tạp — datatypes.JSON bên Go serialize thẳng,
    // không phải chuỗi cần jsonDecode thêm lần nữa.
    final payload = json['action_payload'];
    if (payload is Map && payload['action'] != null) {
      kind = payload['action'].toString();
      value = payload['value']?.toString() ?? value;
    }
    return ScheduleItem(
      id: (json['id'] ?? '').toString(),
      endpoint: (json['endpoint'] ?? '').toString(),
      time: (json['time'] ?? '00:00').toString(),
      repeatDays: (json['repeat_days'] ?? '').toString(),
      action: action,
      isEnabled: json['is_enabled'] != false,
      deviceMac: (json['device_mac'] ?? '').toString(),
      deviceName: (json['device_name'] ?? '').toString(),
      actionKind: kind,
      actionValue: value,
    );
  }
}

/// ScheduleService — HTTP client gọn nhẹ cho cụm API Hẹn giờ (không cần global
/// provider: lịch trình sống theo TỪNG thiết bị, state do màn DeviceTimerScreen giữ).
/// Hàm ghi trả về `String?` lỗi (null = thành công) — cùng khuôn RoomGroupProvider.
class ScheduleService {
  static const String _apiBase = ApiService.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorageService.getToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  String _errorFrom(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {}
    return '$fallback (HTTP ${res.statusCode})';
  }

  /// GET /api/devices/:mac/schedules — trả (danh sách, lỗi); lỗi != null thì list rỗng.
  /// [FIX MULTI-RELAY] [endpoint] khác rỗng -> chỉ lấy lịch của ĐÚNG kênh đó (+ lịch "cả
  /// thiết bị" đời cũ, Backend tự gộp) — DeviceTimerScreen giờ luôn truyền endpoint của thẻ
  /// vừa mở, nên danh sách không còn lẫn lịch của các relay khác cùng MAC.
  Future<(List<ScheduleItem>, String?)> fetchSchedules(String mac, {String endpoint = ''}) async {
    try {
      final uri = Uri.parse('$_apiBase/devices/${Uri.encodeComponent(mac)}/schedules')
          .replace(queryParameters: endpoint.isEmpty ? null : {'endpoint': endpoint});
      final res = await http.get(uri, headers: await _authHeaders());
      if (res.statusCode != 200) return (<ScheduleItem>[], _errorFrom(res, 'Không tải được lịch trình'));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['schedules'] as List? ?? [])
          .whereType<Map>()
          .map((e) => ScheduleItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return (list, null);
    } catch (e) {
      if (kDebugMode) print('❌ [SCHEDULE] Lỗi tải lịch: $e');
      return (<ScheduleItem>[], 'Lỗi kết nối máy chủ');
    }
  }

  /// POST /api/devices/:mac/schedules — upsert theo id (id rỗng = tạo mới).
  /// Trả (bản ghi server đã lưu, lỗi).
  Future<(ScheduleItem?, String?)> saveSchedule(String mac, Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/devices/${Uri.encodeComponent(mac)}/schedules'),
        headers: await _authHeaders(),
        body: jsonEncode(data),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        return (null, _errorFrom(res, 'Không lưu được lịch trình'));
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (ScheduleItem.fromJson(Map<String, dynamic>.from(body['schedule'] ?? {})), null);
    } catch (e) {
      if (kDebugMode) print('❌ [SCHEDULE] Lỗi lưu lịch: $e');
      return (null, 'Lỗi kết nối máy chủ');
    }
  }

  /// PUT /api/schedules/:id/toggle — null = thành công.
  Future<String?> toggleSchedule(String id, bool isEnabled) async {
    try {
      final res = await http.put(
        Uri.parse('$_apiBase/schedules/${Uri.encodeComponent(id)}/toggle'),
        headers: await _authHeaders(),
        body: jsonEncode({'is_enabled': isEnabled}),
      );
      if (res.statusCode != 200) return _errorFrom(res, 'Không cập nhật được trạng thái lịch');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [SCHEDULE] Lỗi toggle: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// DELETE /api/schedules/:id — null = thành công.
  Future<String?> deleteSchedule(String id) async {
    // id rỗng sẽ biến URL thành DELETE /api/schedules/ (route KHÔNG tồn tại) ->
    // server trả 404 lạc đề. Chặn từ gốc, báo đúng bản chất lỗi.
    if (id.trim().isEmpty) {
      debugPrint('DELETE_SCHEDULE_ERROR: id rỗng — lịch chưa được lưu lên server?');
      return 'Lịch trình chưa có mã hợp lệ — kéo làm mới rồi thử lại';
    }
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/schedules/${Uri.encodeComponent(id)}'),
        headers: await _authHeaders(),
      );
      // Mọi mã 2xx đều là XÓA THÀNH CÔNG. Tuyệt đối KHÔNG parse body ở nhánh này —
      // server đời cũ có thể trả 200/204 body rỗng, jsonDecode sẽ ném FormatException
      // và biến một lần xóa thành công thành "Lỗi kết nối máy chủ" oan.
      if (res.statusCode >= 200 && res.statusCode < 300) return null;

      debugPrint('DELETE_SCHEDULE_ERROR: HTTP ${res.statusCode} — body: ${res.body}');
      return _errorFrom(res, 'Không xóa được lịch trình');
    } catch (e) {
      // Lộ NGUYÊN HÌNH exception (trước đây chỉ in khi debug, chạy release là nuốt ngầm):
      // HandshakeException/SocketException = mạng thật; FormatException = server trả rác.
      debugPrint('DELETE_SCHEDULE_ERROR: ${e.runtimeType}: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// GET /api/homes/:id/schedules — TỔNG HỢP lịch trình của MỌI thiết bị trong nhà (tab
  /// "Lịch trình" gộp) — MỘT lần gọi thay vì loop fetchSchedules() từng mac (chống N+1,
  /// cùng nguyên tắc DashboardSyncService).
  Future<(List<ScheduleItem>, String?)> fetchHomeSchedules(String homeId) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/homes/${Uri.encodeComponent(homeId)}/schedules'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return (<ScheduleItem>[], _errorFrom(res, 'Không tải được lịch trình'));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['schedules'] as List? ?? [])
          .whereType<Map>()
          .map((e) => ScheduleItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return (list, null);
    } catch (e) {
      if (kDebugMode) print('❌ [SCHEDULE] Lỗi tải lịch trình cả nhà: $e');
      return (<ScheduleItem>[], 'Lỗi kết nối máy chủ');
    }
  }
}

/// Đếm ngược đang chạy của MỘT (mac, endpoint) — bản chiếu bảng SQL `device_countdowns`.
/// Sống ở Backend (Postgres + ticker quét 5s), KHÔNG còn Timer.periodic cục bộ — mất mạng/
/// tắt App/khởi động lại Server đều không làm mất đếm ngược.
class CountdownItem {
  final String id;
  final DateTime targetTime; // thời điểm kết thúc THẬT theo đồng hồ Server (UTC qua JSON)
  final String action;       // 'ON' | 'OFF'

  const CountdownItem({required this.id, required this.targetTime, required this.action});

  bool get turnOn => action == 'ON';
  Duration get remaining {
    final d = targetTime.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  factory CountdownItem.fromJson(Map<String, dynamic> json) => CountdownItem(
        id: (json['id'] ?? '').toString(),
        targetTime: DateTime.tryParse((json['target_time'] ?? '').toString())?.toLocal() ?? DateTime.now(),
        action: (json['action'] ?? 'OFF').toString().toUpperCase(),
      );
}

/// CountdownService — HTTP client cho cụm API Đếm ngược (song song ScheduleService, tách
/// riêng vì khuôn dữ liệu/vòng đời khác hẳn: đếm ngược chỉ có ĐÚNG 1 bản ghi hoạt động cho
/// mỗi (mac, endpoint), không phải danh sách nhiều lịch như Hẹn giờ).
class CountdownService {
  static const String _apiBase = ApiService.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorageService.getToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  String _errorFrom(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {}
    return '$fallback (HTTP ${res.statusCode})';
  }

  Uri _uri(String mac, String endpoint) => Uri.parse('$_apiBase/devices/${Uri.encodeComponent(mac)}/countdown')
      .replace(queryParameters: endpoint.isEmpty ? null : {'endpoint': endpoint});

  /// GET — đếm ngược đang hoạt động của (mac, endpoint), null nếu chưa đặt cái nào. Gọi lúc
  /// mở màn hình để KHÔI PHỤC đúng thời gian còn lại — trước đây _countdownEndsAt luôn về
  /// null sau khi đóng/mở lại App vì chỉ sống trong biến State.
  Future<(CountdownItem?, String?)> fetchActive(String mac, {String endpoint = ''}) async {
    try {
      final res = await http.get(_uri(mac, endpoint), headers: await _authHeaders());
      if (res.statusCode != 200) return (null, _errorFrom(res, 'Không tải được đếm ngược'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = body['countdown'];
      if (raw == null) return (null, null); // chưa đặt — KHÔNG phải lỗi
      return (CountdownItem.fromJson(Map<String, dynamic>.from(raw as Map)), null);
    } catch (e) {
      if (kDebugMode) print('❌ [COUNTDOWN] Lỗi tải: $e');
      return (null, 'Lỗi kết nối máy chủ');
    }
  }

  /// POST — đặt/ghi đè đếm ngược. [seconds] tính từ THỜI ĐIỂM GỌI API (Server tự cộng vào
  /// đồng hồ của nó — không gửi target_time thẳng từ App để tránh lệch giờ 2 máy).
  Future<(CountdownItem?, String?)> start(String mac, {String endpoint = '', required int seconds, required bool turnOn}) async {
    try {
      final res = await http.post(
        _uri(mac, endpoint),
        headers: await _authHeaders(),
        body: jsonEncode({'endpoint': endpoint, 'seconds': seconds, 'action': turnOn ? 'ON' : 'OFF'}),
      );
      if (res.statusCode != 200) return (null, _errorFrom(res, 'Không đặt được đếm ngược'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (CountdownItem.fromJson(Map<String, dynamic>.from(body['countdown'] as Map)), null);
    } catch (e) {
      if (kDebugMode) print('❌ [COUNTDOWN] Lỗi đặt: $e');
      return (null, 'Lỗi kết nối máy chủ');
    }
  }

  /// DELETE — hủy đếm ngược đang chạy. null = thành công.
  Future<String?> cancel(String mac, {String endpoint = ''}) async {
    try {
      final res = await http.delete(_uri(mac, endpoint), headers: await _authHeaders());
      if (res.statusCode < 200 || res.statusCode >= 300) return _errorFrom(res, 'Không hủy được đếm ngược');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [COUNTDOWN] Lỗi hủy: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }
}
