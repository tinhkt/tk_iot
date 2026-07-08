import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import 'secure_storage_service.dart';

/// Bộ thông tin đăng nhập MQTT động do Backend cấp riêng cho từng user sau khi đăng nhập
/// (GET /api/mqtt/credentials). Password thực chất là JWT chứa claim ACL — EMQX xác thực
/// chữ ký và tự giới hạn quyền publish/subscribe đúng cụm topic smarthub/{home_id}/# của user.
class MqttCredentials {
  final String host;
  final int port;
  final bool secure; // true nếu broker_url là mqtts:// (kết nối TLS)
  final String username;
  final String password;
  final DateTime expiresAt;
  final List<String> topicPrefixes;

  MqttCredentials({
    required this.host,
    required this.port,
    required this.secure,
    required this.username,
    required this.password,
    required this.expiresAt,
    required this.topicPrefixes,
  });

  /// Coi như hết hạn sớm 5 phút để kịp làm mới trước khi Broker từ chối
  bool get isExpiringSoon =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));
}

/// Quản lý vòng đời credentials MQTT: gọi API lấy mới, cache trong RAM theo hạn token,
/// và xóa sạch khi đổi tài khoản (login/logout) để không dùng nhầm quyền của user trước.
class MqttCredentialsService {
  static const String _baseUrl = "https://api.iot-smart.vn/api";
  static MqttCredentials? _cached;

  /// Trả về credentials còn hạn (ưu tiên cache). Trả về null nếu chưa đăng nhập,
  /// token REST hết hạn, hoặc tài khoản chưa liên kết nhà nào (server trả 403).
  static Future<MqttCredentials?> get() async {
    if (_cached != null && !_cached!.isExpiringSoon) return _cached;

    final token = await SecureStorageService.getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/mqtt/credentials'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('⚠️ [MQTT CREDS] Server từ chối cấp credentials (HTTP ${response.statusCode}): ${response.body}');
        }
        return null;
      }

      final data = jsonDecode(response.body);
      final brokerUri = Uri.parse(data['broker_url'] as String);
      final secure = brokerUri.scheme == 'mqtts' ||
          brokerUri.scheme == 'ssl' ||
          brokerUri.scheme == 'tls';

      _cached = MqttCredentials(
        host: brokerUri.host,
        port: brokerUri.hasPort ? brokerUri.port : (secure ? 8883 : 1883),
        secure: secure,
        username: data['mqtt_username'] as String,
        password: data['mqtt_password'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch((data['expires_at'] as int) * 1000),
        topicPrefixes: List<String>.from(data['topic_prefixes'] ?? const []),
      );

      if (kDebugMode) {
        print('🔑 [MQTT CREDS] Đã nhận credentials cho ${_cached!.username}, quyền trên: ${_cached!.topicPrefixes}');
      }
      return _cached;
    } catch (e) {
      if (kDebugMode) print('❌ [MQTT CREDS] Lỗi lấy credentials MQTT: $e');
      return null;
    }
  }

  /// Gọi khi đăng nhập tài khoản mới hoặc đăng xuất
  static void clear() => _cached = null;
}
