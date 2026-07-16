import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import 'secure_storage_service.dart';

/// AdminService — cầu nối tới nhóm API /api/admin (chỉ tài khoản SUPER_USER gọi được).
/// Gồm: Whitelist cấp phép thiết bị, bật/tắt Chế độ nghiêm ngặt, và quản lý kho Firmware OTA.
/// Mọi hàm bọc try-catch, trả kiểu an toàn (bool/null/[]), KHÔNG ném lỗi ra UI.
class AdminService {
  static const String baseUrl = 'https://api.iot-smart.vn/api';

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorageService.getToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ==========================================================================
  // A. CHẾ ĐỘ NGHIÊM NGẶT (STRICT MODE)
  // ==========================================================================

  /// Đọc trạng thái Chế độ nghiêm ngặt. Lỗi mạng -> mặc định false.
  Future<bool> getStrictMode() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/security/strict-mode'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['strict_mode'] == true;
      }
    } catch (e) {
      if (kDebugMode) print('❌ getStrictMode: $e');
    }
    return false;
  }

  /// Bật/tắt Chế độ nghiêm ngặt. Trả true nếu server xác nhận.
  Future<bool> setStrictMode(bool enabled) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/security/strict-mode'),
        headers: await _authHeaders(),
        body: jsonEncode({'enabled': enabled}),
      );
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ setStrictMode: $e');
      return false;
    }
  }

  // ==========================================================================
  // B. WHITELIST (CẤP PHÉP THIẾT BỊ)
  // ==========================================================================

  /// Lấy danh sách thiết bị đã cấp phép. Lỗi -> danh sách rỗng.
  Future<List<Map<String, dynamic>>> getWhitelist() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/whitelist'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['whitelist'] as List?) ?? [];
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      if (kDebugMode) print('❌ getWhitelist: $e');
    }
    return [];
  }

  /// Thêm 1 thiết bị vào whitelist. Trả về chuỗi lỗi (null nếu thành công).
  Future<String?> addWhitelist(String snMac, String deviceType) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/whitelist'),
        headers: await _authHeaders(),
        body: jsonEncode({'sn_mac': snMac, 'device_type': deviceType}),
      );
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body);
      return body['error']?.toString() ?? 'Lỗi không xác định (HTTP ${res.statusCode})';
    } catch (e) {
      if (kDebugMode) print('❌ addWhitelist: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// Xóa 1 thiết bị khỏi whitelist (theo SN). Trả true nếu thành công.
  Future<bool> deleteWhitelist(String sn) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/admin/whitelist/${Uri.encodeComponent(sn)}'),
        headers: await _authHeaders(),
      );
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ deleteWhitelist: $e');
      return false;
    }
  }

  // ==========================================================================
  // C. KHO FIRMWARE OTA
  // ==========================================================================

  /// [DYNAMIC] Lấy danh sách loại thiết bị gợi ý (quét động trên server). Lỗi -> defaults.
  Future<List<String>> getDeviceTypes() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/device-types'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['device_types'] as List?) ?? [];
        return list.map((e) => e.toString()).toList();
      }
    } catch (e) {
      if (kDebugMode) print('❌ getDeviceTypes: $e');
    }
    return const ['hub', 'switch', 'sensor']; // fallback khi mất mạng
  }

  /// Lấy danh sách firmware đang có trên server. Lỗi -> rỗng.
  Future<List<Map<String, dynamic>>> getFirmwareList() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/firmware'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['firmware'] as List?) ?? [];
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      if (kDebugMode) print('❌ getFirmwareList: $e');
    }
    return [];
  }

  /// Tải file .bin lên server (multipart). Truyền path (mobile/desktop) HOẶC bytes (web).
  /// Trả về chuỗi lỗi (null nếu thành công) để UI hiển thị SnackBar chính xác.
  Future<String?> uploadFirmware({
    required String deviceType,
    required String version,
    required String changelog,
    String? filePath,
    Uint8List? fileBytes,
    String fileName = 'firmware.bin',
  }) async {
    try {
      final token = await SecureStorageService.getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/admin/firmware/upload'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['device_type'] = deviceType;
      req.fields['version'] = version;
      req.fields['changelog'] = changelog;

      if (filePath != null) {
        req.files.add(await http.MultipartFile.fromPath('firmware', filePath));
      } else if (fileBytes != null) {
        req.files.add(http.MultipartFile.fromBytes('firmware', fileBytes, filename: fileName));
      } else {
        return 'Chưa chọn file firmware';
      }

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) return null;

      try {
        return jsonDecode(res.body)['error']?.toString() ?? 'Lỗi HTTP ${res.statusCode}';
      } catch (_) {
        return 'Tải lên thất bại (HTTP ${res.statusCode})';
      }
    } catch (e) {
      if (kDebugMode) print('❌ uploadFirmware: $e');
      return 'Lỗi kết nối khi tải lên: $e';
    }
  }

  // ==========================================================================
  // D. PHÂN BỔ / CHUYỂN THIẾT BỊ SANG NHÀ KHÁC
  // ==========================================================================

  /// Lấy danh sách nhà trên hệ thống (dùng cho Dropdown chọn nhà đích). Lỗi -> [].
  /// Trả list {home_id, home_name}.
  Future<List<Map<String, dynamic>>> getHomes() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/homes'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final list = (decoded is List) ? decoded : (decoded['homes'] ?? decoded['data'] ?? []);
        return (list as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      if (kDebugMode) print('❌ getHomes: $e');
    }
    return [];
  }

  /// Chuyển 1 thiết bị sang nhà khác (chỉ SUPER_USER). Trả chuỗi lỗi (null nếu thành công).
  Future<String?> assignDeviceToHome(String mac, String targetHomeId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/admin/devices/assign-home'),
        headers: await _authHeaders(),
        body: jsonEncode({'mac': mac, 'target_home_id': targetHomeId}),
      );
      if (res.statusCode == 200) return null;
      return jsonDecode(res.body)['error']?.toString() ?? 'Lỗi HTTP ${res.statusCode}';
    } catch (e) {
      if (kDebugMode) print('❌ assignDeviceToHome: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  // ==========================================================================
  // E. OTA ZERO-TRUST — KHÓA KÝ ECDSA (chỉ đọc Public Key, Private Key không rời Server)
  // ==========================================================================

  /// Lấy Public Key ECDSA (P-256) mà Server đang dùng để ký firmware — để dán vào mảng
  /// `OTA_PUBLIC_KEY[65]` (PROGMEM) trong mã nguồn C++ trước khi build firmware mới.
  /// Trả (hexKey, lỗi) — hexKey null khi lỗi.
  Future<(String?, String?)> getOtaPublicKey() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/admin/ota/public-key'),
        headers: await _authHeaders(),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final hexKey = body['public_key_hex']?.toString();
        if (hexKey == null || hexKey.isEmpty) return (null, 'Server không trả về Public Key');
        return (hexKey, null);
      }
      final body = jsonDecode(res.body);
      return (null, body['error']?.toString() ?? 'Lỗi HTTP ${res.statusCode}');
    } catch (e) {
      if (kDebugMode) print('❌ getOtaPublicKey: $e');
      return (null, 'Lỗi kết nối máy chủ');
    }
  }

  /// Xóa 1 file firmware khỏi server (server tự os.Remove file rồi xóa record). Trả true nếu OK.
  Future<bool> deleteFirmware(String id) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/admin/firmware/${Uri.encodeComponent(id)}'),
        headers: await _authHeaders(),
      );
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ deleteFirmware: $e');
      return false;
    }
  }
}
