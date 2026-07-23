import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Lưu JWT token trong Keychain (iOS/macOS), Keystore (Android) hoặc DPAPI (Windows)
// thay vì SharedPreferences dạng file XML/plist đọc được nếu máy bị root/jailbreak hoặc bị adb backup.
//
// [FIX — Web: "đăng nhập được nhưng Rooms/Dashboard/Ngữ cảnh/Camera đều không tải"] MỌI API xác
// thực (authorizedGet/Post/Put/Delete trong api_service.dart) đều gọi getToken() ở đây trước khi
// gắn header "Authorization: Bearer $token" — trên Flutter Web, FlutterSecureStorage không đáng
// tin cậy bằng native (không có Keychain/Keystore thật, phải tự mô phỏng qua WebCrypto + Indexed
// DB/localStorage, dễ vỡ giữa các phiên/port debug khác nhau) khiến getToken() có thể trả về null
// dù saveToken() lúc đăng nhập ĐÃ chạy — mọi request sau đó gửi "Bearer null" và bị 401 hàng loạt,
// ĐÚNG triệu chứng "Login qua được (không cần token) nhưng mọi màn cần token đều trống". Trên Web,
// bỏ hẳn FlutterSecureStorage, dùng thẳng SharedPreferences (localStorage trình duyệt) — không có
// OS Keychain thật để bảo vệ trên Web dù dùng thư viện nào (khác biệt "mã hoá thêm 1 lớp" không có
// ý nghĩa bảo mật thực chất so với localStorage thuần trên chính nền tảng Web), ĐỔI LẠI ổn định
// tuyệt đối — KHÔNG đụng gì tới Android/iOS/Desktop (vẫn qua FlutterSecureStorage y hệt cũ).
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'jwt_token';

  static Future<void> saveToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      return;
    }
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      return (token != null && token.isNotEmpty) ? token : null;
    }

    final token = await _storage.read(key: _tokenKey);
    if (token != null) return token;

    // Di chuyển token cũ (nếu app được nâng cấp từ bản trước) từ SharedPreferences
    // sang secure storage rồi xoá bản không mã hoá, để người dùng không bị đăng xuất đột ngột.
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      await _storage.write(key: _tokenKey, value: legacyToken);
      await prefs.remove(_tokenKey);
      return legacyToken;
    }
    return null;
  }

  static Future<void> deleteToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      return;
    }
    await _storage.delete(key: _tokenKey);
  }
}
