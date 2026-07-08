import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import '../models/device_state.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import '../services/auth_service.dart';

class DeviceProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final MqttService _mqttService = MqttService();
  final AuthService _authService = AuthService();

  DeviceState? _deviceState;
  bool _isLoading = false;

  // THÊM: Biến hứng data phụ cho Bảng Điều Khiển
  Function(String topic, String message)? _globalListener;

  DeviceState? get deviceState => _deviceState;
  bool get isLoading => _isLoading;

  DeviceProvider() {
    _initializeMqtt();
  }

  // --- HÀM MỚI: Bảng điều khiển (Dashboard) sẽ gọi hàm này để hứng tin nhắn MQTT ---
  void setGlobalMqttListener(Function(String topic, String message) callback) {
    _globalListener = callback;
  }

  // --- HÀM KHỞI TẠO VÀ LẮNG NGHE MQTT ---
  void _initializeMqtt() {
    _mqttService.onMessageReceived = (topic, message) {
      
      // 1. CHIA SẺ DATA CHO BẢNG ĐIỀU KHIỂN (Dành cho mọi thiết bị: Hass, Hub...)
      if (_globalListener != null) {
        _globalListener!(topic, message);
      }

      // 2. LOGIC CŨ CHO MÀN HÌNH CHI TIẾT HUB V38
      if (_deviceState == null) return;
      
      String currentMac = _deviceState!.mac.replaceAll(':', '').toUpperCase();
      if (topic.contains(currentMac)) {
        List<String> parts = topic.split('/');
        
        if (parts.length >= 4 && parts[0] == 'smarthub') {
          String endpoint = parts[2];
          if (parts.length == 4 && parts[3] == 'state') {
            if (message == "ON" || message == "OFF") {
              _updateStateRealTime(endpoint, state: message);
            }
          } 
          else if (parts.length == 5 && parts[3] == 'speed' && parts[4] == 'state') {
            int speedVal = int.tryParse(message) ?? 0;
            _updateStateRealTime(endpoint, speed: speedVal);
          }
          else if (parts.length == 5 && parts[3] == 'osc' && parts[4] == 'state') {
            bool isSwing = (message == 'swing');
            _updateStateRealTime(endpoint, isSwing: isSwing);
          }
        }
      }
    };
    
    // Bắt đầu kết nối
    _mqttService.connect();
  }

  // --- HÀM TỔNG HỢP: CẬP NHẬT GIAO DIỆN THEO BẤT KỲ CHỈ SỐ NÀO ---
  void _updateStateRealTime(String endpoint, {String? state, int? speed, bool? isSwing}) {
    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      final oldDevice = _deviceState!.endpoints[endpoint]!;
      bool isChanged = false;

      String newState = state ?? oldDevice.state;
      var newSpeed = speed ?? oldDevice.speed;
      
      if (state != null && state != oldDevice.state) isChanged = true;
      if (speed != null && speed != oldDevice.speed) isChanged = true;
      if (isSwing != null) isChanged = true; 

      if (isChanged) {
        _deviceState!.endpoints[endpoint] = SubDevice(
          power: newState == 'ON',
          on: newState == 'ON',
          active: newState == 'ON',
          state: newState,
          speed: newSpeed, 
        );
        
        if (kDebugMode) print('🔄 [UI CẬP NHẬT] Đã cập nhật $endpoint - Trạng thái: $newState | Tốc độ: $newSpeed');
        notifyListeners(); 
      }
    }
  }

  // --- CÁC HÀM CÒN LẠI GIỮ NGUYÊN NHƯ CŨ ---
  Future<void> fetchDeviceState(String mac) async {
    _isLoading = true;
    notifyListeners(); 

    try {
      _deviceState = await _apiService.getDeviceState(mac);
    } catch (e) {
      if (kDebugMode) print("❌ Lỗi trong Provider: $e");
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
        _authService.handleUnauthorized();
      }
    }
    
    _isLoading = false;
    notifyListeners(); 
  }

  void toggleDevice(String mac, String endpoint, bool currentState) {
    bool turnOn = !currentState;
    String payload = turnOn ? "ON" : "OFF";
    String topic = "";

    List<String> smartHubMacs = ['ECE334468B64']; 
    if (smartHubMacs.contains(mac)) {
      topic = 'smarthub/$mac/$endpoint/set';
    } else {
      topic = '$mac/control'; 
    }

    if (kDebugMode) print("⚡ [BẮN LỆNH PROVIDER]: $payload -> Topic: $topic");
    _mqttService.publish(topic, payload); 

    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      final oldDevice = _deviceState!.endpoints[endpoint]!;
      _deviceState!.endpoints[endpoint] = SubDevice(
        power: turnOn,
        on: turnOn,
        active: turnOn,
        state: turnOn ? 'ON' : 'OFF',
        speed: oldDevice.speed,
      );
      notifyListeners(); 
    }
  }

  void setFanSpeed(String mac, String endpoint, int speed, bool isSwing) {
    bool isTurningOn = speed > 0;
    _mqttService.sendCommand(mac, endpoint, isTurningOn, speed: speed, swing: isSwing);

    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      _deviceState!.endpoints[endpoint] = SubDevice(
        power: isTurningOn,
        on: isTurningOn,
        active: isTurningOn,
        state: isTurningOn ? 'ON' : 'OFF',
        speed: speed,
      );
      notifyListeners();
    }
  }
}