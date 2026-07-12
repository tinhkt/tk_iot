import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../services/auth_service.dart';
import '../services/mqtt_credentials_service.dart';

class NotificationItem {
  final String id; // định danh duy nhất Backend cấp — dùng chống trùng khi broker phát lại (QoS 1)
  final String type;
  final String title;
  final String message;
  final String time;
  final String color;

  /// MAC thiết bị đính kèm (tin firmware mới / thiết bị ngoại tuyến) — App dùng để
  /// DEEPLINK: bấm vào dòng thông báo là mở thẳng Popup Cài đặt của đúng thiết bị đó.
  final String mac;

  /// [OTA_UPDATE] Phiên bản mới + mô tả thay đổi — chỉ có ở tin type OTA_UPDATE, App dùng
  /// để dựng hộp thoại "Bản cập nhật mới" (không có ở các loại tin khác -> chuỗi rỗng).
  final String version;
  final String changelog;

  /// Đã đọc hay chưa. Backend lưu is_read dạng chuỗi "false" (tin mới) hoặc bool true
  /// (sau mark-read) — fromJson chấp nhận cả hai để không lệch khi nạp lịch sử.
  bool isRead;

  NotificationItem({this.id = '', required this.type, required this.title, required this.message, required this.time, required this.color, this.mac = '', this.version = '', this.changelog = '', this.isRead = false});

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    final raw = json['is_read'];
    final read = raw == true || raw == 'true' || raw == 1;
    return NotificationItem(
      id: (json['id'] ?? '').toString(),
      type: json['type'] ?? 'INFO',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      time: json['time'] ?? '',
      color: json['color'] ?? '0xFF10B981',
      mac: (json['mac'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      changelog: (json['changelog'] ?? '').toString(),
      isRead: read,
    );
  }

  /// Mã màu đã GIẢI MÃ AN TOÀN: chuỗi color rác/lệch định dạng từ bất kỳ nguồn nào
  /// cũng không thể ném FormatException giữa hàm build (crash ngầm làm cả panel
  /// trắng trơn + chuông đứng số) — hỏng thì rơi về xanh hệ thống.
  int get colorValue {
    try {
      return int.parse(color);
    } catch (_) {
      return 0xFF10B981;
    }
  }
}

class NotificationProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  List<NotificationItem> _list = [];
  bool _hasNewNotification = false;
  MqttServerClient? _mqttClient;

  List<NotificationItem> get list => _list;
  bool get hasNewNotification => _hasNewNotification;

  /// Số tin CHƯA ĐỌC — badge chuông và nút "Đọc tất cả" đều dựa vào con số này.
  int get unreadCount => _list.where((n) => !n.isRead).length;

  // 1. Tải lịch sử thông báo cũ khi người dùng mở App
  Future<void> fetchHistory() async {
    final data = await _authService.getNotifications();
    if (data != null) {
      _list = data.map((json) => NotificationItem.fromJson(json)).toList();
      notifyListeners();
    }
  }

  // 2. Kích hoạt lắng nghe luồng tin thời gian thực từ EMQX Broker ngoài Internet
  void initMQTTListener(String email) async {
    _mqttClient?.disconnect();

    // [BẢO MẬT] Dùng credentials MQTT động theo user do Backend cấp,
    // thay cho tài khoản iot_admin hardcode dùng chung mọi nhà trước đây.
    final creds = await MqttCredentialsService.get();
    if (creds == null) {
      if (kDebugMode) print('⚠️ [CHUÔNG] Chưa có credentials MQTT, bỏ qua kênh thông báo.');
      return;
    }

    // [CHỐNG ĐÁ PHIÊN] ID độc nhất: timestamp + random — nhiều máy cùng tài khoản
    // không bao giờ trùng ID để EMQX kick phiên của nhau
    final clientId = 'app_notif_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';
    _mqttClient = MqttServerClient(creds.host, clientId);
    _mqttClient!.port = creds.port;
    _mqttClient!.secure = creds.secure;
    _mqttClient!.keepAlivePeriod = 30;
    _mqttClient!.logging(on: false);

    // [AUTO-RECONNECT] Kênh chuông cũng phải tự hồi sinh sau khi PC ngủ mạng:
    // thư viện tự nối lại + tự subscribe lại topic notifications/{email} —
    // trước đây rớt ngầm là chuông "điếc" vĩnh viễn cho tới khi mở lại App.
    _mqttClient!.autoReconnect = true;
    _mqttClient!.resubscribeOnAutoReconnect = true;
    _mqttClient!.onDisconnected = () {
      if (kDebugMode) print('⚠️ [CHUÔNG] Mất kết nối kênh thông báo — autoReconnect đang tự cứu...');
    };
    _mqttClient!.onAutoReconnected = () {
      if (kDebugMode) print('✅ [CHUÔNG] Kênh thông báo đã tự nối lại + subscribe lại thành công!');
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(creds.username, creds.password)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);
    _mqttClient!.connectionMessage = connMessage;

    try {
      if (kDebugMode) print('⏳ [CHUÔNG] Đang kết nối kênh thông báo tới ${creds.host}:${creds.port} (TLS: ${creds.secure})...');
      await _mqttClient!.connect();
      if (_mqttClient!.connectionStatus!.state == MqttConnectionState.connected) {
        String topic = 'notifications/$email';
        _mqttClient!.subscribe(topic, MqttQos.atMostOnce);
        if (kDebugMode) print('✅ [CHUÔNG TCP] Đã kết nối và Subscribe thành công topic: $topic');

        _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

          // LUỒNG CHUẨN: jsonDecode -> ép kiểu NotificationItem (mọi key đều có
          // fallback, không bao giờ ném lỗi vì thiếu trường) -> chèn đầu danh sách
          // -> bật chấm đỏ -> notifyListeners() => badge trên chuông nhảy số TỨC THÌ.
          try {
            final decoded = jsonDecode(payload);
            if (decoded is! Map<String, dynamic>) return; // gói rác không phải object -> bỏ qua
            final newItem = NotificationItem.fromJson(decoded);

            // Chống trùng: broker QoS 1 có thể phát lại cùng một gói khi mạng chờn
            if (newItem.id.isNotEmpty && _list.any((n) => n.id == newItem.id)) return;

            _list.insert(0, newItem);
            _hasNewNotification = true;
            notifyListeners();
          } catch (e) {
            if (kDebugMode) print("Lỗi parse gói tin thông báo MQTT: $e");
          }
        });
      }
    } catch (e) {
      if (kDebugMode) print("❌ Không thể kết nối MQTT thông báo Cloud: $e");
    }
  }

  // Xóa chấm đỏ khi người dùng đã click mở xem danh sách
  void clearNewBadge() {
    _hasNewNotification = false;
    notifyListeners();
  }

  // [ĐÃ ĐỌC 1 TIN] Cập nhật UI ngay (optimistic) rồi đồng bộ Backend nền.
  Future<void> markAsRead(String id) async {
    final idx = _list.indexWhere((n) => n.id == id);
    if (idx == -1 || _list[idx].isRead) return;
    _list[idx].isRead = true;
    notifyListeners();
    await _authService.markNotificationRead(id);
  }

  // [ĐỌC TẤT CẢ] Làm mờ hết danh sách ngay lập tức rồi báo Backend một lần.
  Future<void> markAllRead() async {
    if (unreadCount == 0) return;
    for (final n in _list) {
      n.isRead = true;
    }
    _hasNewNotification = false;
    notifyListeners();
    await _authService.markAllNotificationsRead();
  }

  // [VUỐT ĐỂ XÓA] Gỡ khỏi danh sách ngay rồi xóa bản ghi trên Redis.
  Future<void> dismiss(String id) async {
    _list.removeWhere((n) => n.id == id);
    notifyListeners();
    await _authService.deleteNotification(id);
  }
}