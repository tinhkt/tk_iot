import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'industrial_shell.dart';

const Color _fanSteel = Color(0xFF90A4AE);

/// Hệ thống quạt hút gió/thông gió công nghiệp — cánh quạt 4 lá kiểu quạt hút xưởng, quay theo
/// nấc tốc độ 1-3, có lồng bảo vệ (cage) vẽ đè lên. Quy ước: `state.speed` = nấc tốc độ (1-3).
class IndustrialFanAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const IndustrialFanAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<IndustrialFanAvatar> createState() => _IndustrialFanAvatarState();
}

class _IndustrialFanAvatarState extends State<IndustrialFanAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: _durationForSpeed(widget.state.speed));
    _applySpin();
  }

  @override
  void didUpdateWidget(covariant IndustrialFanAvatar oldWidget) {
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
    return Duration(milliseconds: 900 - (s - 1) * 300); // quạt xưởng quay nhanh hơn quạt gia dụng (Bước 2)
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
    final Color idleColor = widget.state.isOffline ? Colors.grey : _fanSteel;
    final int speed = (widget.state.speed ?? 1).clamp(1, 3);

    return RuggedShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: industrialAmber,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    turns: _spin,
                    child: CustomPaint(size: const Size(76, 76), painter: _IndustrialBladesPainter(color: widget.state.isOn ? industrialAmber : idleColor)),
                  ),
                  CustomPaint(size: const Size(88, 88), painter: _CagePainter(color: Colors.white24)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int s = 1; s <= 3; s++)
                GestureDetector(
                  onTap: () {
                    widget.callbacks.onChange('speed', s);
                    if (!widget.state.isOn) widget.callbacks.onToggle(true);
                  },
                  child: Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.state.isOn && speed >= s ? industrialAmber : Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '$s',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: widget.state.isOn && speed >= s ? Colors.black : Colors.white54),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              EStopButton(onPressed: () => widget.callbacks.onToggle(false), size: 26),
            ],
          ),
        ],
      ),
    );
  }
}

class _IndustrialBladesPainter extends CustomPainter {
  final Color color;
  _IndustrialBladesPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.width / 2;
    final Paint p = Paint()..color = color;
    for (int i = 0; i < 4; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * math.pi / 2);
      final Path blade = Path()
        ..moveTo(0, 0)
        ..lineTo(r * 0.9, -r * 0.22)
        ..lineTo(r * 0.9, r * 0.22)
        ..close();
      canvas.drawPath(blade, p);
      canvas.restore();
    }
    canvas.drawCircle(center, r * 0.18, Paint()..color = Colors.black54);
  }

  @override
  bool shouldRepaint(covariant _IndustrialBladesPainter oldDelegate) => oldDelegate.color != color;
}

class _CagePainter extends CustomPainter {
  final Color color;
  _CagePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawCircle(center, size.width / 2 - 1, ring);
    for (int i = 0; i < 8; i++) {
      final double a = i * math.pi / 4;
      canvas.drawLine(
        center,
        center + Offset(math.cos(a), math.sin(a)) * (size.width / 2 - 1),
        Paint()
          ..color = color
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CagePainter oldDelegate) => false;
}

/// [Quạt công nghiệp | industrial_fan]
final List<DeviceAvatarDefinition> industrialFanAvatars = [
  DeviceAvatarDefinition(
    id: 'industrial_fan',
    name: 'Quạt công nghiệp / Hệ thống thông gió',
    category: 'industrial_fan',
    buildWidget: (context, state, callbacks) => IndustrialFanAvatar(state: state, callbacks: callbacks),
  ),
];
