import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _fanBlue = Color(0xFF5BC0EB);
const Color _coolBlue = Color(0xFF4FC3F7);

enum _FanMount { ceiling, stand }

/// Quạt trần & Quạt cây dùng CHUNG cánh quạt + cơ chế quay — khác nhau ở phần "chân đế" trang
/// trí (trần: cần treo phía trên; cây: cổ + đế phía dưới). Quy ước trục dữ liệu: `state.speed` =
/// nấc 1-3, quay càng nhanh khi nấc càng cao; dừng hẳn khi isOn=false.
class _FanAvatar extends StatefulWidget {
  final _FanMount mount;
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const _FanAvatar({required this.mount, required this.state, required this.callbacks});

  @override
  State<_FanAvatar> createState() => _FanAvatarState();
}

class _FanAvatarState extends State<_FanAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: _durationForSpeed(widget.state.speed));
    _applySpin();
  }

  @override
  void didUpdateWidget(covariant _FanAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isOn != widget.state.isOn ||
        oldWidget.state.isOffline != widget.state.isOffline ||
        oldWidget.state.speed != widget.state.speed) {
      _spin.duration = _durationForSpeed(widget.state.speed);
      _applySpin();
    }
  }

  Duration _durationForSpeed(int? speed) {
    final int s = (speed ?? 1).clamp(1, 3);
    return Duration(milliseconds: 1400 - (s - 1) * 450); // nấc 1=1400ms/vòng, nấc 2=950ms, nấc 3=500ms
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
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _fanBlue,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.mount == _FanMount.ceiling) Container(width: 3, height: 10, color: Colors.grey.shade500),
          Expanded(
            child: RotationTransition(
              turns: _spin,
              child: CustomPaint(
                size: const Size(84, 84),
                painter: _FanBladesPainter(color: widget.state.isOn ? _fanBlue : Colors.grey),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int s = 1; s <= 3; s++)
                AvatarDot(
                  active: widget.state.isOn && (widget.state.speed ?? 1) >= s,
                  color: _fanBlue,
                  onTap: () {
                    widget.callbacks.onChange('speed', s);
                    if (!widget.state.isOn) widget.callbacks.onToggle(true);
                  },
                ),
            ],
          ),
          if (widget.mount == _FanMount.stand) ...[
            const SizedBox(height: 4),
            Container(width: 3, height: 10, color: Colors.grey.shade500),
            Container(width: 28, height: 4, decoration: BoxDecoration(color: Colors.grey.shade500, borderRadius: BorderRadius.circular(2))),
          ],
        ],
      ),
    );
  }
}

class _FanBladesPainter extends CustomPainter {
  final Color color;
  _FanBladesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.width / 2;
    final Paint bladePaint = Paint()..color = color;
    for (int i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 2 * math.pi / 3);
      final Path blade = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(r * 0.35, -r * 0.15, r * 0.92, -r * 0.08)
        ..quadraticBezierTo(r * 0.98, 0, r * 0.92, r * 0.08)
        ..quadraticBezierTo(r * 0.35, r * 0.15, 0, 0)
        ..close();
      canvas.drawPath(blade, bladePaint);
      canvas.restore();
    }
    canvas.drawCircle(center, r * 0.16, Paint()..color = color.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _FanBladesPainter oldDelegate) => oldDelegate.color != color;
}

/// Điều hòa không khí — nhiệt độ đặt hiển thị to giữa avatar + hoạt ảnh "gió lạnh" (2 đường sóng
/// trôi ngang) khi đang bật. Quy ước trục dữ liệu: `state.value` = nhiệt độ đặt (°C, 16-30).
class AirConditionerAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const AirConditionerAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<AirConditionerAvatar> createState() => _AirConditionerAvatarState();
}

class _AirConditionerAvatarState extends State<AirConditionerAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _breeze;

  @override
  void initState() {
    super.initState();
    _breeze = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _breeze.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double temp = (widget.state.value ?? 25).clamp(16, 30);
    final bool on = widget.state.isOn && !widget.state.isOffline;

    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _coolBlue,
      width: 316,
      height: 150,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(shape: BoxShape.circle, color: on ? _coolBlue.withValues(alpha: 0.18) : Colors.grey.withValues(alpha: 0.12)),
              child: Icon(Icons.ac_unit_rounded, color: on ? _coolBlue : Colors.grey, size: 30),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${temp.round()}', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: on ? _coolBlue : Colors.grey, height: 1)),
                    Padding(padding: const EdgeInsets.only(top: 6, left: 2), child: Text('°C', style: TextStyle(fontSize: 16, color: on ? _coolBlue : Colors.grey))),
                  ],
                ),
                const SizedBox(height: 4),
                if (on)
                  SizedBox(
                    height: 16,
                    width: 140,
                    child: AnimatedBuilder(
                      animation: _breeze,
                      builder: (context, _) => CustomPaint(size: const Size(140, 16), painter: _BreezePainter(phase: _breeze.value, color: _coolBlue)),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                color: _coolBlue,
                onPressed: () => widget.callbacks.onChange('value', (temp + 1).clamp(16, 30)),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                color: _coolBlue,
                onPressed: () => widget.callbacks.onChange('value', (temp - 1).clamp(16, 30)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreezePainter extends CustomPainter {
  final double phase; // 0..1, một chu kỳ lặp
  final Color color;
  _BreezePainter({required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int line = 0; line < 2; line++) {
      final double y = size.height * (line == 0 ? 0.3 : 0.75);
      final double shift = phase * 20 + line * 6;
      final Path path = Path();
      bool started = false;
      for (double x = 0; x <= size.width; x += 4) {
        final double wave = math.sin((x + shift) / 8) * 2.5;
        if (!started) {
          path.moveTo(x, y + wave);
          started = true;
        } else {
          path.lineTo(x, y + wave);
        }
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _BreezePainter oldDelegate) => oldDelegate.phase != phase;
}

/// [Không khí | climate] Quạt trần, Quạt cây, Điều hòa không khí.
final List<DeviceAvatarDefinition> climateAvatars = [
  DeviceAvatarDefinition(
    id: 'fan_ceiling',
    name: 'Quạt trần',
    category: 'climate',
    buildWidget: (context, state, callbacks) => _FanAvatar(mount: _FanMount.ceiling, state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'fan_stand',
    name: 'Quạt cây',
    category: 'climate',
    buildWidget: (context, state, callbacks) => _FanAvatar(mount: _FanMount.stand, state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'ac_unit',
    name: 'Điều hòa không khí',
    category: 'climate',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => AirConditionerAvatar(state: state, callbacks: callbacks),
  ),
];
