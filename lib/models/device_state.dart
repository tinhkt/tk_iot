class DeviceState {
  final String mac;
  final bool success;
  final Map<String, SubDevice> endpoints;

  DeviceState({required this.mac, required this.success, required this.endpoints});

  factory DeviceState.fromJson(Map<String, dynamic> json) {
    Map<String, SubDevice> eps = {};
    if (json['data'] != null) {
      json['data'].forEach((key, value) {
        eps[key] = SubDevice.fromJson(value);
      });
    }
    return DeviceState(
      mac: json['mac'] ?? '',
      success: json['success'] ?? false,
      endpoints: eps,
    );
  }
}

class SubDevice {
  final String? name; // Thêm biến lưu tên
  final bool power;
  final bool on;
  final bool active;
  final String state;
  final int? speed;
  final int? fanSpeed;
  final bool swing; 

  SubDevice({
    this.name, // Thêm vào constructor
    required this.power,
    required this.on,
    required this.active,
    required this.state,
    this.speed,
    this.fanSpeed,
    this.swing = false,
  });

  factory SubDevice.fromJson(Map<String, dynamic> json) {
    return SubDevice(
      name: json['name'], // Bắt tên từ Hub gửi về
      power: json['power'] ?? false,
      on: json['on'] ?? false,
      active: json['active'] ?? false,
      state: json['state'] ?? 'OFF',
      speed: json['speed'],
      fanSpeed: json['fan_speed'],
      swing: json['swing'] ?? json['oscillate'] ?? false, 
    );
  }
}