import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'industrial_shell.dart';

const Color _welderOrange = Color(0xFFFF7043);

/// Máy hàn điểm (Spot Welder) — thanh trượt chỉnh THỜI GIAN XUNG HÀN (ms) + hiển thị dòng xả cực
/// đại (A, CHỈ-ĐỌC). Quy ước: `state.value` = thời gian xung (ms, 50-500), `state.metric` = dòng
/// xả cực đại đo được ở lần hàn gần nhất (A). Thanh trượt LUÔN chỉnh được kể cả khi đang NGẮT —
/// thợ hàn cần đặt trước thông số RỒI mới đóng điện, khoá thanh trượt lúc tắt sẽ ngược quy trình
/// thao tác thật.
class SpotWelderAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const SpotWelderAvatar({super.key, required this.state, required this.callbacks});

  static const double _minPulse = 50;
  static const double _maxPulse = 500;

  @override
  Widget build(BuildContext context) {
    final bool armed = state.isOn && !state.isOffline;
    final double pulseMs = (state.value ?? 150).clamp(_minPulse, _maxPulse);
    final double peakA = state.metric ?? 0;
    final Color color = state.isOffline ? Colors.grey : _welderOrange;

    return RuggedShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _welderOrange,
      width: 316,
      height: 150,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => callbacks.onToggle(!state.isOn),
            child: Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: armed ? color.withValues(alpha: 0.25) : Colors.black26,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(Icons.bolt_rounded, color: color, size: 26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Xung hàn: ${pulseMs.round()} ms', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: _welderOrange,
                    thumbColor: _welderOrange,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: pulseMs,
                    min: _minPulse,
                    max: _maxPulse,
                    onChanged: (v) => callbacks.onChange('value', v),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 14, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text('Dòng xả cực đại: ${peakA.toStringAsFixed(0)} A', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.isOffline ? 'MẤT KẾT NỐI' : (armed ? 'SẴN SÀNG HÀN' : 'NGẮT'),
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          EStopButton(onPressed: () => callbacks.onToggle(false)),
        ],
      ),
    );
  }
}

/// [Thiết bị chuyên dụng | spot_welder]
final List<DeviceAvatarDefinition> spotWelderAvatars = [
  DeviceAvatarDefinition(
    id: 'spot_welder',
    name: 'Máy hàn điểm (Spot Welder)',
    category: 'spot_welder',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => SpotWelderAvatar(state: state, callbacks: callbacks),
  ),
];
