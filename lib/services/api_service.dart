import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import '../models/device_state.dart';
import 'secure_storage_service.dart';

class ApiService {
  // Trỏ chính xác vào IP Box Armbian của bạn
  static const String baseUrl = 'https://api.iot-smart.vn/api';

  // --- HÀM LẤY TRẠNG THÁI THIẾT BỊ (ĐÃ ĐƯỢC LỒNG GHÉP AUTH) ---
  Future<DeviceState?> getDeviceState(String mac) async {
    try {
      // THAY ĐỔI Ở ĐÂY: Dùng authorizedGet thay vì http.get trực tiếp
      final response = await authorizedGet('$baseUrl/devices/${Uri.encodeComponent(mac)}/state');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Lưu ý: Nếu server trả về dạng {"success": true, "data": {...}}
        // Bạn có thể cần truy cập data['data'] tùy vào cấu trúc model của bạn.
        // Ở đây tôi giữ nguyên logic cũ theo file bạn gửi:
        return DeviceState.fromJson(data);
      } else {
        if (kDebugMode) print('⚠️ Server Golang báo lỗi (Status ${response.statusCode}): ${response.body}');
        return null;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Không thể kết nối tới Box Armbian: $e');
      return null;
    }
  }

  // --- HÀM GỠ THIẾT BỊ KHỎI NHÀ (UNPAIR) ---
  /// Gửi DELETE /api/devices/{mac} tới Backend Golang. Backend sẽ xác minh chủ quyền,
  /// dọn bản ghi Redis, xóa retained message và ngắt phiên MQTT của thiết bị trên EMQX.
  /// Trả về true khi server xác nhận xóa thành công (HTTP 200/204).
  Future<bool> deleteDevice(String mac) async {
    try {
      final response = await authorizedDelete('$baseUrl/devices/${Uri.encodeComponent(mac)}');
      if (response.statusCode == 200 || response.statusCode == 204) return true;
      if (kDebugMode) print('⚠️ Server từ chối xóa thiết bị $mac (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi xóa thiết bị $mac: $e');
      return false;
    }
  }

  // --- HÀM ĐỔI TÊN ENDPOINT THIẾT BỊ ---
  /// PUT /api/devices/{mac}/name — lưu tên user đặt vào database (Redis hash device_names).
  /// Tên này được ưu tiên tuyệt đối trước tên tự sinh sw-/Fan-; gửi name rỗng = xóa tên,
  /// quay về tên tự động. Backend đồng thời phát lại state để mọi App cập nhật realtime.
  Future<bool> renameDeviceEndpoint(String mac, String endpoint, String name) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/name'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'endpoint': endpoint, 'name': name}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối đổi tên $mac/$endpoint (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi đổi tên thiết bị: $e');
      return false;
    }
  }

  // --- CÀI ĐẶT "TRẠNG THÁI KHI CÓ ĐIỆN" (POWER-ON BEHAVIOR) ---
  /// PUT /api/devices/{mac}/power-behavior với {"mode": 0|1|2}
  /// (0 = Nhớ trạng thái cũ, 1 = Luôn Tắt, 2 = Luôn Bật).
  /// Backend lưu Redis device_settings:{mac} rồi đẩy cấu hình xuống mạch qua MQTT
  /// (kèm bản retained để thiết bị đang mất điện vẫn nhận được khi lên mạng lại).
  Future<bool> setPowerBehavior(String mac, int mode) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/power-behavior'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'mode': mode}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối lưu power-behavior $mac (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi lưu power-behavior: $e');
      return false;
    }
  }

  // --- [DIGITAL TWIN] CÀI ĐẶT TỔNG QUÁT KHÁC (Thời gian hành trình cửa cuốn, vị trí %...) ---
  /// PUT /api/devices/{mac}/setting {"key":"...","value":"..."} — mirror setPowerBehavior
  /// nhưng dùng chung MỘT endpoint cho mọi field mới (key phải nằm trong allowlist phía Backend:
  /// travel_time_sec, door_position_pct). Không đẩy MQTT xuống mạch (thuần App/Backend dùng).
  Future<bool> setDeviceSetting(String mac, String key, String value) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/setting'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'key': key, 'value': value}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối lưu cài đặt $mac.$key (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi lưu cài đặt $key: $e');
      return false;
    }
  }

  // --- KIỂM TRA KHO FIRMWARE OTA ---
  /// GET /api/firmware/check — trả về meta {version, url, sha256} khi kho có bản MỚI HƠN
  /// (HTTP 200); trả null khi đang ở bản mới nhất (304) hoặc kho chưa có firmware (404).
  Future<Map<String, dynamic>?> checkFirmwareUpdate(String deviceType, String currentVersion) async {
    final token = await SecureStorageService.getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/firmware/check?device_type=${Uri.encodeComponent(deviceType)}&current_version=${Uri.encodeComponent(currentVersion)}'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return json.decode(response.body) as Map<String, dynamic>;
    if (kDebugMode) print('ℹ️ [OTA] Check firmware $deviceType v$currentVersion -> HTTP ${response.statusCode}');
    return null;
  }

  // --- RA LỆNH NẠP FIRMWARE OTA ---
  /// POST /api/devices/{mac}/ota — Backend xác minh chủ quyền + thiết bị Trực tuyến rồi
  /// bắn lệnh MQTT xuống chip tự tải file .bin về nạp (kèm SHA256 tự kiểm trước khi ghi flash).
  Future<bool> triggerOtaUpdate(String mac) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/ota'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ [OTA] Lỗi ra lệnh nạp firmware: $e');
      return false;
    }
  }

  // --- HÀM TRỢ GIÚP GẮN TOKEN VÀO HEADER ---
  Future<http.Response> authorizedGet(String url) async {
    final token = await SecureStorageService.getToken();

    return await http.get(
      Uri.parse(url),
      headers: {
        // Đảm bảo đúng định dạng: "Bearer <token>" (có dấu cách)
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  // --- HÀM TRỢ GIÚP GỬI LỆNH DELETE KÈM TOKEN ---
  Future<http.Response> authorizedDelete(String url) async {
    final token = await SecureStorageService.getToken();

    return await http.delete(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  // --- HÀM TRỢ GIÚP GỬI LỆNH POST KÈM TOKEN + BODY JSON ---
  Future<http.Response> authorizedPost(String url, [Map<String, dynamic>? body]) async {
    final token = await SecureStorageService.getToken();

    return await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body != null ? json.encode(body) : null,
    );
  }
}