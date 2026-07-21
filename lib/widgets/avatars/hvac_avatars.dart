import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _hvacBlue = Color(0xFF29B6F6);

/// Điều hòa trung tâm (HVAC) — bảng Thermostat: núm xoay chỉnh nhiệt độ đặt (`value`, 16-30°C),
/// độ ẩm CHỈ-ĐỌC (`metric`, %RH) và biểu đồ nhiệt mini CHỈ-ĐỌC (`metricHistory`). Nút nguồn TÁCH
/// RIÊNG khỏi vùng núm xoay (không chồng lên như DimmerLightAvatar ở Bước 2) để tránh vừa bật/tắt
/// vừa vô tình nhích nhiệt độ trong cùng một cú chạm — phù hợp tinh thần "nghiêm túc" của BMS.
class HvacThermostatAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const HvacThermostatAvatar({super.key, required this.state, required this.callbacks});

  static const double _minTemp = 16;
  static const double _maxTemp = 30;

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    final double temp = (state.value ?? 24).clamp(_minTemp, _maxTemp);
    final double normalized = (temp - _minTemp) / (_maxTemp - _minTemp);
    final double? humidity = state.metric;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _hvacBlue,
      width: 316,
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RotaryKnob(
            value: normalized,
            color: on ? _hvacBlue : Colors.grey,
            size: 104,
            onChanged: (pct) => callbacks.onChange('value', _minTemp + pct * (_maxTemp - _minTemp)),
            centerContent: Text('${temp.round()}°C', style: TextStyle(color: on ? _hvacBlue : Colors.grey, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => callbacks.onToggle(!state.isOn),
                      child: Icon(Icons.power_settings_new_rounded, size: 18, color: on ? _hvacBlue : Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.water_drop_outlined, size: 16, color: on ? _hvacBlue : Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      humidity == null ? '--%RH' : '${humidity.round()}%RH',
                      style: TextStyle(color: on ? _hvacBlue : Colors.grey, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Xu hướng nhiệt độ', style: TextStyle(color: (on ? _hvacBlue : Colors.grey).withValues(alpha: 0.7), fontSize: 9, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                MiniSparkline(history: state.metricHistory, color: on ? _hvacBlue : Colors.grey, width: 150, height: 26),
                const SizedBox(height: 4),
                Text(
                  state.isOffline ? 'MẤT KẾT NỐI' : (on ? 'ĐANG HOẠT ĐỘNG' : 'CHỜ'),
                  style: TextStyle(color: (on ? _hvacBlue : Colors.grey), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [Điều hòa trung tâm | hvac]
final List<DeviceAvatarDefinition> hvacAvatars = [
  DeviceAvatarDefinition(
    id: 'hvac_thermostat',
    name: 'Điều hòa trung tâm (Thermostat)',
    category: 'hvac',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => HvacThermostatAvatar(state: state, callbacks: callbacks),
  ),
];
