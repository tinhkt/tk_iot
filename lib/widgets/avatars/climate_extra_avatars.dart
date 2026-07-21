import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _coolerBlue = Color(0xFF4FC3F7);
const Color _heaterRed = Color(0xFFFF7043);
const Color _hoodSteel = Color(0xFF90A4AE);
const Color _ventTeal = Color(0xFF26A69A);

/// Icon quay liên tục khi ON (dùng CHUNG cho Quạt hơi nước/Quạt hút mùi/Quạt thông gió — 3 loại
/// quạt chỉ khác icon/màu, không cần cánh quạt vẽ tay riêng như Bước 2/4 vì đây là avatar THỨ
/// YẾU, giữ nhẹ nhưng vẫn có animation thật, không phải icon tĩnh).
class _SpinningIconAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;
  final IconData icon;
  final Color color;

  const _SpinningIconAvatar({required this.state, required this.callbacks, required this.icon, required this.color});

  @override
  State<_SpinningIconAvatar> createState() => _SpinningIconAvatarState();
}

class _SpinningIconAvatarState extends State<_SpinningIconAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _applySpin();
  }

  @override
  void didUpdateWidget(covariant _SpinningIconAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isOn != widget.state.isOn || oldWidget.state.isOffline != widget.state.isOffline) _applySpin();
  }

  void _applySpin() {
    if (widget.state.isOn && !widget.state.isOffline) {
      _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.isOn && !widget.state.isOffline;
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: widget.color,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Center(
        child: RotationTransition(
          turns: _spin,
          child: Icon(widget.icon, size: 48, color: on ? widget.color : Colors.grey),
        ),
      ),
    );
  }
}

/// Đèn sưởi — vòng nhiệt đỏ cam "thở" (pulse) khi ON, mô phỏng bức xạ nhiệt.
class HeaterLampAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const HeaterLampAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<HeaterLampAvatar> createState() => _HeaterLampAvatarState();
}

class _HeaterLampAvatarState extends State<HeaterLampAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.isOn && !widget.state.isOffline;
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _heaterRed,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final double t = on ? _pulse.value : 0;
            return Container(
              width: 70 + t * 14,
              height: 70 + t * 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: on ? RadialGradient(colors: [_heaterRed.withValues(alpha: 0.55 + t * 0.25), _heaterRed.withValues(alpha: 0.0)]) : null,
                color: on ? null : Colors.grey.withValues(alpha: 0.12),
              ),
              child: Icon(Icons.local_fire_department_rounded, size: 34, color: on ? Colors.white : Colors.grey),
            );
          },
        ),
      ),
    );
  }
}

/// [Không khí & Nhiệt độ | climate] Quạt hơi nước, Đèn sưởi, Quạt hút mùi, Quạt thông gió — bổ
/// sung Bước 5 (Điều hòa không khí AC đã có sẵn từ Bước 2 — ac_unit, không lặp lại ở đây).
final List<DeviceAvatarDefinition> climateExtraAvatars = [
  DeviceAvatarDefinition(
    id: 'evaporative_cooler',
    name: 'Quạt điều hòa hơi nước',
    category: 'climate',
    buildWidget: (context, state, callbacks) => _SpinningIconAvatar(state: state, callbacks: callbacks, icon: Icons.ac_unit_rounded, color: _coolerBlue),
  ),
  DeviceAvatarDefinition(
    id: 'heater_lamp',
    name: 'Đèn sưởi',
    category: 'climate',
    buildWidget: (context, state, callbacks) => HeaterLampAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'range_hood_fan',
    name: 'Quạt hút mùi',
    category: 'climate',
    buildWidget: (context, state, callbacks) => _SpinningIconAvatar(state: state, callbacks: callbacks, icon: Icons.mode_fan_off_rounded, color: _hoodSteel),
  ),
  DeviceAvatarDefinition(
    id: 'ventilation_fan',
    name: 'Quạt thông gió',
    category: 'climate',
    buildWidget: (context, state, callbacks) => _SpinningIconAvatar(state: state, callbacks: callbacks, icon: Icons.air_rounded, color: _ventTeal),
  ),
];
