import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _doorColor = Color(0xFF7C8AA5);
const Color _curtainColor = Color(0xFFB08968);
const Color _plugAmber = Color(0xFFFFA726);

/// Cửa cuốn — lá cửa mô phỏng bằng các "nan" ngang kéo lên/xuống theo %, kèm slider dọc chỉnh
/// trực tiếp. Quy ước trục dữ liệu: `state.value` = % mở (0 = đóng kín, 100 = mở hết).
class RollingDoorAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const RollingDoorAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final double openPct = (state.value ?? 0).clamp(0, 100);

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _doorColor,
      width: 316,
      height: 150,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: openPct, end: openPct),
                  duration: const Duration(milliseconds: 400),
                  builder: (context, animatedPct, _) => CustomPaint(
                    size: Size.infinite,
                    painter: _DoorSlatsPainter(openFraction: animatedPct / 100, color: _doorColor),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8)),
                      child: Slider(value: openPct, min: 0, max: 100, activeColor: _doorColor, onChanged: (v) => callbacks.onChange('value', v)),
                    ),
                  ),
                ),
                Text('${openPct.round()}%', style: const TextStyle(color: _doorColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoorSlatsPainter extends CustomPainter {
  final double openFraction; // 0 = đóng kín, 1 = mở hết
  final Color color;
  _DoorSlatsPainter({required this.openFraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const double slatHeight = 8;
    final double visibleHeight = size.height * (1 - openFraction);
    final int slatCount = (visibleHeight / slatHeight).ceil();
    final Paint slat = Paint()..color = color;
    final Paint gap = Paint()..color = color.withValues(alpha: 0.4);
    for (int i = 0; i < slatCount; i++) {
      final double y = size.height - visibleHeight + i * slatHeight;
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, slatHeight - 1.5), i.isEven ? slat : gap);
    }
  }

  @override
  bool shouldRepaint(covariant _DoorSlatsPainter oldDelegate) => oldDelegate.openFraction != openFraction;
}

/// Rèm cửa thông minh — 2 tấm rèm trượt vào/ra từ 2 mép theo %. Quy ước: `state.value` = % mở
/// (0 = 2 tấm khép kín ở giữa, 100 = 2 tấm thu hết về 2 bên).
class SmartCurtainAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const SmartCurtainAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final double openPct = (state.value ?? 0).clamp(0, 100);

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _curtainColor,
      width: 316,
      height: 150,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.12)),
                  LayoutBuilder(builder: (context, constraints) {
                    final double panelWidth = (constraints.maxWidth / 2) * (1 - openPct / 100);
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 350),
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: panelWidth,
                          child: Container(color: _curtainColor),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 350),
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: panelWidth,
                          child: Container(color: _curtainColor),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
            child: Slider(value: openPct, min: 0, max: 100, activeColor: _curtainColor, onChanged: (v) => callbacks.onChange('value', v)),
          ),
        ],
      ),
    );
  }
}

/// Ổ cắm thông minh — chỉ có on/off; hiển thị thêm công suất tiêu thụ (W) đọc từ `state.metric`
/// (CHỈ-ĐỌC, không có onChange tương ứng — do Dashboard/telemetry cấp, avatar không tự đo).
class SmartPlugAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const SmartPlugAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    final double watt = state.metric ?? 0;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _plugAmber,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? _plugAmber.withValues(alpha: 0.18) : Colors.grey.withValues(alpha: 0.12),
              boxShadow: on ? [BoxShadow(color: _plugAmber.withValues(alpha: 0.6), blurRadius: 16, spreadRadius: 1)] : null,
            ),
            child: Icon(Icons.power_rounded, color: on ? _plugAmber : Colors.grey, size: 32),
          ),
          const SizedBox(height: 10),
          Text(
            '${watt.toStringAsFixed(watt >= 100 ? 0 : 1)} W',
            style: TextStyle(color: on ? _plugAmber : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

/// [An ninh/Cửa | security] Cửa cuốn, Rèm cửa thông minh, Ổ cắm thông minh.
final List<DeviceAvatarDefinition> securityAvatars = [
  DeviceAvatarDefinition(
    id: 'door_rolling',
    name: 'Cửa cuốn',
    category: 'security',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => RollingDoorAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'curtain_smart',
    name: 'Rèm cửa thông minh',
    category: 'security',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => SmartCurtainAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'plug_smart',
    name: 'Ổ cắm thông minh',
    category: 'security',
    buildWidget: (context, state, callbacks) => SmartPlugAvatar(state: state, callbacks: callbacks),
  ),
];
