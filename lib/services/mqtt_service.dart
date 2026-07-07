import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
// Phục vụ đọc/ghi JSON nếu sau này cần mở rộng

class MqttService {
  late MqttServerClient client;
  bool isConnected = false;

  // Callback để truyền dữ liệu thời gian thực về cho DeviceProvider
  Function(String topic, String message)? onMessageReceived;

  MqttService() {
    client = MqttServerClient('mqtt.iot-smart.vn', 'tk_app_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 21883; 
  }

  Future<void> connect() async {
    if (isConnected && client.connectionStatus?.state == MqttConnectionState.connected) return;

    client.logging(on: false);
    client.keepAlivePeriod = 30;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('tk_app_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs('iot_admin', 'Mqtttk')
        .startClean();

    client.connectionMessage = connMessage;

    try {
      print('⏳ [MQTT TCP] Đang kết nối kênh điều khiển...');
      await client.connect();
      isConnected = true;
      print('✅ [MQTT TCP] KẾT NỐI ĐIỀU KHIỂN THÀNH CÔNG!');

      // --- [CHUẨN HÓA LẮNG NGHE ĐÚNG CODE ESP32] ---
      // Dùng '#' để bắt trọn mọi báo cáo từ SmartHub (Bật/Tắt, Tốc độ, Túp năng)
      client.subscribe('smarthub/#', MqttQos.atLeastOnce);
      
      // LƯU Ý: Nếu công tắc Hass của bác trả trạng thái về topic khác (ví dụ: stat/MAC/RESULT), 
      // bác có thể thêm dòng subscribe ở đây sau này.
      
      // Bắt đầu lắng nghe luồng tin nhắn đổ về
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final String topic = c[0].topic;

        print('📥 [MQTT NHẬN]: Topic: $topic | Payload: $message');

        // Bắn dữ liệu về cho DeviceProvider bóc tách và vẽ lại UI
        if (onMessageReceived != null) {
          onMessageReceived!(topic, message);
        }
      });

    } catch (e) {
      print('❌ [MQTT TCP] Lỗi kết nối: $e');
      isConnected = false;
      client.disconnect();
    }
  }

  // --- HÀM MỚI ĐƯỢC THÊM VÀO ĐỂ GỬI LỆNH ĐÃ PHÂN LUỒNG TỪ PROVIDER ---
  Future<void> publish(String topic, String payload) async {
    // Ép đợi khôi phục mạng ngầm trước khi bắn lệnh (chống rớt mạng)
    if (!isConnected || client.connectionStatus?.state != MqttConnectionState.connected) {
      print('⚠️ Mất kết nối, đang tự động khôi phục...');
      await connect();
      if (client.connectionStatus?.state != MqttConnectionState.connected) return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);
    
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    // Log ra terminal để bác dễ kiểm soát
    print('📤 [MQTT PUBLISH]: $payload -> Topic: $topic');
  }

  // --- GIỮ NGUYÊN HÀM CŨ ĐỂ SAU NÀY BÁC DÙNG CHO QUẠT (Tốc độ, Túp năng) ---
  Future<void> sendCommand(String mac, String endpoint, bool currentState, {int? speed, bool? swing}) async {
    if (!isConnected || client.connectionStatus?.state != MqttConnectionState.connected) {
      print('⚠️ Mất kết nối, đang tự động khôi phục...');
      await connect();
      if (client.connectionStatus?.state != MqttConnectionState.connected) return;
    }

    String cleanMac = mac.replaceAll(':', '').toUpperCase();
    String topic = endpoint.contains(cleanMac) 
        ? '$cleanMac/control' 
        : 'smarthub/$cleanMac/$endpoint/set'; 
    
    // Bắn lệnh TẮT/BẬT tổng
    final command = currentState ? "ON" : "OFF";
    client.publishMessage(topic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(command).payload!);
    print('⚡ [BẮN LỆNH]: $command -> Topic: $topic');

    // Bắn lệnh chỉnh TỐC ĐỘ QUẠT (nếu có)
    if (speed != null) {
      String speedTopic = 'smarthub/$cleanMac/$endpoint/speed/set';
      client.publishMessage(speedTopic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(speed.toString()).payload!);
    }
    
    // Bắn lệnh chỉnh TÚP NĂNG (nếu có)
    if (swing != null) {
      String oscTopic = 'smarthub/$cleanMac/$endpoint/osc/set';
      client.publishMessage(oscTopic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(swing ? "swing" : "off").payload!);
    }
  }
}