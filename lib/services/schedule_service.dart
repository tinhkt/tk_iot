import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'secure_storage_service.dart';

/// Một dòng hẹn giờ/lịch trình của MỘT thiết bị — bản chiếu bảng SQL `device_schedules`.
class ScheduleItem {
  final String id;
  String time;       // 'HH:MM' 24h
  String repeatDays; // nhãn lặp lại tự do (Backend lưu varchar): 'Hàng ngày', 'T2 - T6'...
  String action;     // 'ON' | 'OFF' — trùng payload lệnh MQTT
  bool isEnabled;

  ScheduleItem({required this.id, required this.time, required this.repeatDays, required this.action, required this.isEnabled});

  bool get isOn => action == 'ON';

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        id: (json['id'] ?? '').toString(),
        time: (json['time'] ?? '00:00').toString(),
        repeatDays: (json['repeat_days'] ?? '').toString(),
        action: (json['action'] ?? 'OFF').toString().toUpperCase(),
        isEnabled: json['is_enabled'] != false,
      );
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
  Future<(List<ScheduleItem>, String?)> fetchSchedules(String mac) async {
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/devices/${Uri.encodeComponent(mac)}/schedules'),
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
}
