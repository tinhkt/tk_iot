import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  late MqttServerClient client;
  bool isConnected = false;

  MqttService() {
    // [CHUẨN TCP] Trả về đúng tên miền sạch và cổng 21883 y hệt Home Assistant
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
      print('⏳ [MQTT TCP] Đang kết nối kênh điều khiển tới mqtt.iot-smart.vn:21883...');
      await client.connect();
      isConnected = true;
      print('✅ [MQTT TCP] KẾT NỐI ĐIỀU KHIỂN THÀNH CÔNG!');
    } catch (e) {
      print('❌ [MQTT TCP] Lỗi kết nối: $e');
      isConnected = false;
      client.disconnect();
    }
  }

  // Ép đợi khôi phục mạng ngầm trước khi bắn lệnh
  Future<void> sendCommand(String mac, String endpoint, bool currentState, {int? speed, bool? swing}) async {
    if (!isConnected || client.connectionStatus?.state != MqttConnectionState.connected) {
      print('⚠️ Mất kết nối, đang tự động khôi phục đường truyền ngầm...');
      await connect();
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        print('❌ Không thể thực thi lệnh đóng cắt do chưa có mạng Internet.');
        return;
      }
    }

    String cleanMac = mac.replaceAll(':', '').toUpperCase();
    String topic;
    
    if (endpoint.contains(cleanMac)) {
      topic = '$cleanMac/control'; 
    } else {
      topic = 'smarthub/$cleanMac/$endpoint/set'; 
    }
    
    final command = currentState ? "ON" : "OFF";

    client.publishMessage(topic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(command).payload!);
    print('⚡ [BẮN LỆNH]: $command -> Topic: $topic');

    if (speed != null) {
      String speedTopic = 'smarthub/$cleanMac/$endpoint/speed/set';
      client.publishMessage(speedTopic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(speed.toString()).payload!);
    }

    if (swing != null) {
      String oscTopic = 'smarthub/$cleanMac/$endpoint/osc/set';
      client.publishMessage(oscTopic, MqttQos.atLeastOnce, MqttClientPayloadBuilder().addString(swing ? "swing" : "off").payload!);
    }
  }
}