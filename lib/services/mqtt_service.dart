import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'mqtt_credentials_service.dart';

class MqttService {
  MqttServerClient? client;
  bool isConnected = false;

  // Callback để truyền dữ liệu thời gian thực về cho DeviceProvider
  Function(String topic, String message)? onMessageReceived;

  bool get _isClientConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect() async {
    if (isConnected && _isClientConnected) return;

    // [BẢO MẬT] Không còn tài khoản MQTT chung hardcode trong App:
    // lấy credentials động (username + JWT password, kèm danh sách topic được phép)
    // từ Backend theo đúng user đang đăng nhập.
    final creds = await MqttCredentialsService.get();
    if (creds == null) {
      if (kDebugMode) print('⚠️ [MQTT] Chưa có credentials MQTT (chưa đăng nhập hoặc chưa liên kết nhà), bỏ qua kết nối.');
      return;
    }

    final clientId = 'tk_app_${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient(creds.host, clientId);
    c.port = creds.port;
    c.secure = creds.secure; // Tự bật TLS khi server trả broker_url dạng mqtts://
    c.logging(on: false);
    c.keepAlivePeriod = 30;
    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(creds.username, creds.password)
        .startClean();
    client = c;

    try {
      if (kDebugMode) print('⏳ [MQTT] Đang kết nối kênh điều khiển tới ${creds.host}:${creds.port} (TLS: ${creds.secure})...');
      await c.connect();
      isConnected = true;
      if (kDebugMode) print('✅ [MQTT] KẾT NỐI ĐIỀU KHIỂN THÀNH CÔNG!');

      // Subscribe đúng các cụm topic mà ACL của user này được cấp (smarthub/{home_id}/#),
      // thay cho wildcard smarthub/# nghe lén được mọi nhà như trước đây.
      for (final prefix in creds.topicPrefixes) {
        c.subscribe(prefix, MqttQos.atLeastOnce);
      }

      // Bắt đầu lắng nghe luồng tin nhắn đổ về
      c.updates!.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
        final MqttPublishMessage recMess = messages[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final String topic = messages[0].topic;

        if (kDebugMode) print('📥 [MQTT NHẬN]: Topic: $topic | Payload: $message');

        // Bắn dữ liệu về cho DeviceProvider bóc tách và vẽ lại UI
        if (onMessageReceived != null) {
          onMessageReceived!(topic, message);
        }
      });

    } catch (e) {
      if (kDebugMode) print('❌ [MQTT] Lỗi kết nối: $e');
      isConnected = false;
      c.disconnect();
    }
  }

  // --- HÀM MỚI ĐƯỢC THÊM VÀO ĐỂ GỬI LỆNH ĐÃ PHÂN LUỒNG TỪ PROVIDER ---
  Future<void> publish(String topic, String payload) async {
    // Ép đợi khôi phục mạng ngầm trước khi bắn lệnh (chống rớt mạng)
    if (!isConnected || !_isClientConnected) {
      if (kDebugMode) print('⚠️ Mất kết nối, đang tự động khôi phục...');
      await connect();
      if (!_isClientConnected) return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    // Log ra terminal để bác dễ kiểm soát
    if (kDebugMode) print('📤 [MQTT PUBLISH]: $payload -> Topic: $topic');
  }

  // --- GIỮ NGUYÊN HÀM CŨ ĐỂ SAU NÀY BÁC DÙNG CHO QUẠT (Tốc độ, Túp năng) ---
  Future<void> sendCommand(String mac, String endpoint, bool currentState, {int? speed, bool? swing}) async {
    if (!isConnected || !_isClientConnected) {
      if (kDebugMode) print('⚠️ Mất kết nối, đang tự động khôi phục...');
      await connect();
      if (!_isClientConnected) return;
    }

    String cleanMac = mac.replaceAll(':', '').toUpperCase();
    String topic = endpoint.contains(cleanMac)
        ? '$cleanMac/control'
        : 'smarthub/$cleanMac/$endpoint/set';

    // Bắn lệnh TẮT/BẬT tổng
    final command = currentState ? "ON" : "OFF";
    client!.publishMessage(topic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(command).payload!);
    if (kDebugMode) print('⚡ [BẮN LỆNH]: $command -> Topic: $topic');

    // Bắn lệnh chỉnh TỐC ĐỘ QUẠT (nếu có)
    if (speed != null) {
      String speedTopic = 'smarthub/$cleanMac/$endpoint/speed/set';
      client!.publishMessage(speedTopic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(speed.toString()).payload!);
    }

    // Bắn lệnh chỉnh TÚP NĂNG (nếu có)
    if (swing != null) {
      String oscTopic = 'smarthub/$cleanMac/$endpoint/osc/set';
      client!.publishMessage(oscTopic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(swing ? "swing" : "off").payload!);
    }
  }

  /// Ngắt kết nối và quên client cũ — gọi khi đăng xuất để phiên MQTT
  /// của tài khoản trước không tiếp tục nhận dữ liệu.
  void disconnect() {
    client?.disconnect();
    client = null;
    isConnected = false;
  }
}
