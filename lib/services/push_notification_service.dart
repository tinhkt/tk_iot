import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../main.dart'; // navigatorKey — điều hướng khi App đang chạy nền hoặc vừa mở lại
import '../screens/dashboard_screen.dart';
import 'auth_service.dart';

// [BẮT BUỘC] Handler nền PHẢI là hàm TOP-LEVEL (ngoài mọi class) + @pragma('vm:entry-point')
// — Flutter chạy hàm này trên 1 isolate RIÊNG khi App bị kill hẳn, không truy cập được
// state/context/Provider của isolate UI chính. Chỉ log — KHÔNG gọi flutter_local_notifications
// ở đây (App có thể đã bị kill, plugin channel không đảm bảo sẵn sàng); nếu payload FCM có kèm
// block "notification" (luôn có, xem push.SendToUser phía Backend), hệ điều hành TỰ hiển thị
// thông báo mà không cần code nào ở đây xử lý thêm.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) print('📩 [PUSH-BG] Nhận tin nền: ${message.data}');
}

/// [ĐẨY THÔNG BÁO OS] Lớp bổ sung SONG SONG với NotificationProvider (chuông trong-app qua
/// MQTT, chỉ hoạt động khi App đang mở) — KHÔNG thay thế, chỉ thêm đường hiển thị hệ thống
/// thật (khay thông báo/lock screen) hoạt động cả khi App nền/bị kill. Tái dùng NGUYÊN khuôn
/// dữ liệu NotificationItem (id/type/title/message/mac/version/changelog) làm FCM data
/// payload — bấm vào push OS sẽ deep-link lại ĐÚNG logic đã có trong dashboard_screen.dart
/// (_showUpdateDialog cho OTA_UPDATE, _openDeviceSettingsByMac cho các loại còn lại), không
/// viết logic deeplink mới.
class PushNotificationService {
  static final FirebaseMessaging _fm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  // [KHỚP CHANNEL ID BACKEND] PHẢI trùng androidChannelID khai trong
  // internal/push/send.go (iot-core-server) — lệch tên thì Android tạo ra 2 channel riêng
  // biệt, notification gửi lên channel KHÔNG được user cấu hình sẽ câm lặng.
  static const String _channelId = 'tk_iot_important';

  static Future<void> init() async {
    // 1. Xin quyền OS (Android 13+ cần POST_NOTIFICATIONS, iOS luôn cần xin tường minh).
    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // 2. Tạo Notification Channel Android (bắt buộc Android 8+, làm 1 lần, idempotent) —
    // độ ưu tiên cao đúng yêu cầu "sáng màn hình như tin nhắn mới".
    const channel = AndroidNotificationChannel(
      _channelId,
      'Thông báo quan trọng',
      description: 'Thiết bị trực tuyến/ngoại tuyến, cập nhật firmware',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // 3. Foreground: FCM KHÔNG tự hiện gì -> tự vẽ bằng flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // 4. App đang chạy nền, user bấm vào notification hệ thống -> mở lại + deeplink.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTapData);

    // 5. App bị kill hẳn, user bấm notification để MỞ App -> đọc tin khởi động lạnh.
    final initialMsg = await _fm.getInitialMessage();
    if (initialMsg != null) _handleTapData(initialMsg);
  }

  /// Gọi SAU khi có JWT hợp lệ (từ DashboardScreen._bootstrapSync, ngay cạnh
  /// initMQTTListener) — lấy token thiết bị + gửi lên Backend đăng ký, và lắng nghe token
  /// refresh (Firebase tự xoay token định kỳ/khi cài lại App).
  static Future<void> registerWithBackend() async {
    try {
      final token = await _fm.getToken();
      if (token != null) await AuthService().registerPushToken(token);
      _fm.onTokenRefresh.listen((newToken) => AuthService().registerPushToken(newToken));
    } catch (e) {
      if (kDebugMode) print('⚠️ [PUSH] Lỗi đăng ký token FCM: $e');
    }
  }

  /// Gọi từ AuthService.logout() TRƯỚC khi xóa JWT — gỡ token khỏi Backend để máy vừa đăng
  /// xuất không còn nhận đẩy thay người dùng mới đăng nhập trên cùng thiết bị.
  static Future<void> unregisterFromBackend() async {
    try {
      final token = await _fm.getToken();
      if (token != null) await AuthService().unregisterPushToken(token);
    } catch (e) {
      if (kDebugMode) print('⚠️ [PUSH] Lỗi gỡ token FCM: $e');
    }
  }

  static void _showForegroundNotification(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    _local.show(
      id: n.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(_channelId, 'Thông báo quan trọng', importance: Importance.high, priority: Priority.high),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: _encodeDeeplinkPayload(message.data),
    );
  }

  static void _onLocalNotificationTap(NotificationResponse response) {
    final data = _decodeDeeplinkPayload(response.payload);
    if (data != null) _navigateToDeeplink(data);
  }

  static void _handleTapData(RemoteMessage message) {
    _navigateToDeeplink(message.data);
  }

  // [TÁI DÙNG PAYLOAD] message.data chính là khuôn notif Backend đã gửi (id/type/title/
  // message/mac/version/changelog) — không cần định nghĩa khuôn dữ liệu mới, chỉ cần đọc
  // đúng 4 field cần cho deeplink.
  static void _navigateToDeeplink(Map<String, dynamic> data) {
    final String mac = (data['mac'] ?? '').toString();
    if (mac.isEmpty) return;
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => DashboardScreen(
        initialDeeplinkMac: mac,
        initialDeeplinkType: (data['type'] ?? '').toString(),
        initialDeeplinkVersion: (data['version'] ?? '').toString(),
        initialDeeplinkChangelog: (data['changelog'] ?? '').toString(),
      ),
    ));
  }

  // flutter_local_notifications chỉ nhận payload dạng String phẳng — nén 4 field cần cho
  // deeplink thành 1 chuỗi "type|mac|version" tối giản (changelog thường dài/nhiều ký tự đặc
  // biệt, cắt bỏ khi tap từ notification NỀN TRƯỚC — trường hợp hiếm OTA_UPDATE bấm từ
  // notification tự vẽ foreground vẫn mở đúng popup thiết bị, chỉ thiếu đúng đoạn changelog
  // dài, chấp nhận được).
  static String _encodeDeeplinkPayload(Map<String, dynamic> data) {
    final mac = (data['mac'] ?? '').toString();
    final type = (data['type'] ?? '').toString();
    final version = (data['version'] ?? '').toString();
    return '$type|$mac|$version';
  }

  static Map<String, dynamic>? _decodeDeeplinkPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final parts = payload.split('|');
    if (parts.isEmpty) return null;
    return {
      'type': parts.isNotEmpty ? parts[0] : '',
      'mac': parts.length > 1 ? parts[1] : '',
      'version': parts.length > 2 ? parts[2] : '',
      'changelog': '',
    };
  }
}
