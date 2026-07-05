import 'package:flutter/material.dart';
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

  DeviceState? get deviceState => _deviceState;
  bool get isLoading => _isLoading;

  DeviceProvider() {
    _initializeMqtt();
  }

  // --- HÀM KHỞI TẠO VÀ LẮNG NGHE MQTT ---
  void _initializeMqtt() {
    _mqttService.onMessageReceived = (topic, message) {
      if (_deviceState == null) return;
      
      String currentMac = _deviceState!.mac.replaceAll(':', '').toUpperCase();
      
      // Chỉ xử lý nếu Topic chứa MAC của Hub đang mở trên màn hình
      if (topic.contains(currentMac)) {
        // Tách chuỗi theo dấu "/". 
        // VD 1: smarthub/MAC/S_1234/state -> Length = 4
        // VD 2: smarthub/MAC/F_1234/speed/state -> Length = 5
        List<String> parts = topic.split('/');
        
        if (parts.length >= 4 && parts[0] == 'smarthub') {
          String endpoint = parts[2];

          // Bắt trạng thái BẬT/TẮT CHUNG (Công tắc & Quạt)
          if (parts.length == 4 && parts[3] == 'state') {
            if (message == "ON" || message == "OFF") {
              _updateStateRealTime(endpoint, state: message);
            }
          } 
          // Bắt trạng thái TỐC ĐỘ QUẠT
          else if (parts.length == 5 && parts[3] == 'speed' && parts[4] == 'state') {
            int speedVal = int.tryParse(message) ?? 0;
            _updateStateRealTime(endpoint, speed: speedVal);
          }
          // Bắt trạng thái TÚP NĂNG QUẠT (SWING)
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

      // Chuẩn bị biến mới để so sánh
      String newState = state ?? oldDevice.state;
      
      // [ĐÃ VÁ LỖI WINDOWS BUILD]: Chuyển thành var để tương thích với int? (Null Safety)
      var newSpeed = speed ?? oldDevice.speed;
      
      // Kiểm tra xem có gì thay đổi so với hiện tại không
      if (state != null && state != oldDevice.state) isChanged = true;
      if (speed != null && speed != oldDevice.speed) isChanged = true;
      if (isSwing != null) isChanged = true; 

      if (isChanged) {
        _deviceState!.endpoints[endpoint] = SubDevice(
          power: newState == 'ON',
          on: newState == 'ON',
          active: newState == 'ON',
          state: newState,
          speed: newSpeed, // Sử dụng biến an toàn
        );
        
        print('🔄 [UI CẬP NHẬT] Đã cập nhật $endpoint - Trạng thái: $newState | Tốc độ: $newSpeed');
        notifyListeners(); // Ra lệnh vẽ lại màn hình điện thoại
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
      print("❌ Lỗi trong Provider: $e");
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
        _authService.handleUnauthorized();
      }
    }
    
    _isLoading = false;
    notifyListeners(); 
  }

  void toggleDevice(String mac, String endpoint, bool currentState) {
    _mqttService.sendCommand(mac, endpoint, !currentState);

    // Optimistic Update (Tạm thời thay đổi ngay để UI mượt mà)
    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      final oldDevice = _deviceState!.endpoints[endpoint]!;
      _deviceState!.endpoints[endpoint] = SubDevice(
        power: !currentState,
        on: !currentState,
        active: !currentState,
        state: currentState ? 'OFF' : 'ON',
        speed: oldDevice.speed,
      );
      notifyListeners(); 
    }
  }

  void setFanSpeed(String mac, String endpoint, int speed, bool isSwing) {
    bool isTurningOn = speed > 0;
    _mqttService.sendCommand(mac, endpoint, isTurningOn, speed: speed, swing: isSwing);

    // Optimistic Update (Tạm thời thay đổi ngay để UI mượt mà)
    if (_deviceState != null && _deviceState!.endpoints.containsKey(endpoint)) {
      final oldDevice = _deviceState!.endpoints[endpoint]!;
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