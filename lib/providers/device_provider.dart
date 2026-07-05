import 'package:flutter/material.dart';
import '../models/device_state.dart';
import '../services/api_service.dart';
import '../services/mqtt_service.dart';
import '../services/auth_service.dart'; // [CẬP NHẬT 1]: Import AuthService

class DeviceProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final MqttService _mqttService = MqttService();
  final AuthService _authService = AuthService(); // [CẬP NHẬT 2]: Khởi tạo AuthService

  DeviceState? _deviceState;
  bool _isLoading = false;

  DeviceState? get deviceState => _deviceState;
  bool get isLoading => _isLoading;

  DeviceProvider() {
    _mqttService.connect();
  }

  // Hàm tải trạng thái thiết bị
  Future<void> fetchDeviceState(String mac) async {
    _isLoading = true;
    notifyListeners(); 

    try {
      // _apiService.getDeviceState đã được lồng ghép authorizedGet bên trong
      _deviceState = await _apiService.getDeviceState(mac);
      
      if (_deviceState == null) {
        print("⚠️ Cảnh báo: Không lấy được dữ liệu thiết bị (API trả về null)");
      }
    } catch (e) {
      print("❌ Lỗi trong Provider: $e");
      
      // [CẬP NHẬT 3]: Bắt lỗi 401 Unauthorized và "Đá" người dùng văng ra Login
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
        print("⚠️ Token hết hạn! Đang tiến hành Force Logout...");
        _authService.handleUnauthorized();
      }
    }
    
    _isLoading = false;
    notifyListeners(); 
  }

  // Cập nhật khi có MQTT bắn về (WebSockets)
  void updateStateFromMqtt(String mac, Map<String, dynamic> newData) {
    if (_deviceState != null && _deviceState!.mac == mac) {
      Map<String, SubDevice> updatedEndpoints = Map.from(_deviceState!.endpoints);
      
      newData.forEach((key, value) {
        // Kiểm tra dữ liệu mới trước khi ép kiểu
        if (value is Map<String, dynamic>) {
          updatedEndpoints[key] = SubDevice.fromJson(value);
        }
      });
      
      _deviceState = DeviceState(
        mac: mac, 
        success: true, 
        endpoints: updatedEndpoints
      );
      
      notifyListeners(); 
    }
  }

  // --- HÀM ĐIỀU KHIỂN ---
  void toggleDevice(String mac, String endpoint, bool currentState) {
    _mqttService.sendCommand(mac, endpoint, !currentState);

    // Cập nhật giao diện tạm thời (Optimistic Update)
    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      final oldDevice = _deviceState!.endpoints[endpoint]!;
      _deviceState!.endpoints[endpoint] = SubDevice(
        power: oldDevice.power,
        on: oldDevice.on,
        active: oldDevice.active,
        state: currentState ? 'OFF' : 'ON',
        speed: oldDevice.speed,
      );
      notifyListeners(); 
    }
  }

  void setFanSpeed(String mac, String endpoint, int speed, bool isSwing) {
    bool isTurningOn = speed > 0;
    _mqttService.sendCommand(mac, endpoint, isTurningOn, speed: speed, swing: isSwing);

    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      final oldDevice = _deviceState!.endpoints[endpoint]!;
      _deviceState!.endpoints[endpoint] = SubDevice(
        power: oldDevice.power,
        on: oldDevice.on,
        active: oldDevice.active,
        state: isTurningOn ? 'ON' : 'OFF',
        speed: speed,
      );
      notifyListeners();
    }
  }
}