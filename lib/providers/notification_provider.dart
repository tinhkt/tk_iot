import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../services/auth_service.dart';

class NotificationItem {
  final String type;
  final String title;
  final String message;
  final String time;
  final String color;

  NotificationItem({required this.type, required this.title, required this.message, required this.time, required this.color});

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      type: json['type'] ?? 'INFO',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      time: json['time'] ?? '',
      color: json['color'] ?? '0xFF10B981',
    );
  }
}

class NotificationProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  List<NotificationItem> _list = [];
  bool _hasNewNotification = false;
  MqttServerClient? _mqttClient;

  List<NotificationItem> get list => _list;
  bool get hasNewNotification => _hasNewNotification;

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

    // [CHUẨN TCP] Đồng bộ với MqttService
    _mqttClient = MqttServerClient('mqtt.iot-smart.vn', 'app_client_${DateTime.now().millisecondsSinceEpoch}');
    _mqttClient!.port = 21883; 
    _mqttClient!.keepAlivePeriod = 20;
    _mqttClient!.logging(on: false);

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('app_client_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs('iot_admin', 'Mqtttk') 
        .startClean()
        .withWillQos(MqttQos.atMostOnce);
    _mqttClient!.connectionMessage = connMessage;

    try {
      if (kDebugMode) print('⏳ [CHUÔNG TCP] Đang kết nối kênh thông báo tới mqtt.iot-smart.vn:21883...');
      await _mqttClient!.connect();
      if (_mqttClient!.connectionStatus!.state == MqttConnectionState.connected) {
        String topic = 'notifications/$email';
        _mqttClient!.subscribe(topic, MqttQos.atMostOnce);
        if (kDebugMode) print('✅ [CHUÔNG TCP] Đã kết nối và Subscribe thành công topic: $topic');

        _mqttClient!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          
          try {
            final Map<String, dynamic> json = jsonDecode(payload);
            final newItem = NotificationItem.fromJson(json);
            
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
}