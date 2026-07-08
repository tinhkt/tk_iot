import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Lưu JWT token trong Keychain (iOS/macOS), Keystore (Android) hoặc DPAPI (Windows)
// thay vì SharedPreferences dạng file XML/plist đọc được nếu máy bị root/jailbreak hoặc bị adb backup.
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _tokenKey = 'jwt_token';

  static Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  static Future<String?> getToken() async {
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

  static Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
