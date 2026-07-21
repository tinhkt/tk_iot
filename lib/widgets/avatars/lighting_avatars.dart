import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

/// Đèn RGB — vòng tròn quét hue (0-360°) để chọn màu, bóng đèn ở tâm đổi màu sống theo hue đang
/// chọn. Quy ước trục dữ liệu: `state.value` = hue (độ, 0-360); không có trục riêng cho độ
/// bão hòa/độ sáng (đúng phạm vi "vòng tròn chọn màu" yêu cầu ở Bước 2, giữ full saturation/value
/// để đơn giản, không mở rộng quá yêu cầu).
class RgbLightAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const RgbLightAvatar({super.key, required this.state, required this.callbacks});

  static const double _wheelSize = 118;

  void _handlePointer(Offset local) {
    const Offset center = Offset(_wheelSize / 2, _wheelSize / 2);
    final Offset delta = local - center;
    // atan2 chuẩn (0 = phải, tăng theo chiều kim đồng hồ vì trục y hướng xuống) -> quy về "0° ở
    // đỉnh 12h, tăng theo chiều kim đồng hồ" bằng cách +90 rồi chuẩn hoá về [0,360).
    final double hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 90 + 360) % 360;
    callbacks.onChange('value', hue);
  }

  @override
  Widget build(BuildContext context) {
    final double hue = (state.value ?? 0) % 360;
    final Color liveColor = HSVColor.fromAHSV(1, hue, 0.85, 1).toColor();

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: liveColor,
      child: Center(
        child: SizedBox(
          width: _wheelSize,
          height: _wheelSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                onPanUpdate: (d) => _handlePointer(d.localPosition),
                onTapDown: (d) => _handlePointer(d.localPosition),
                child: CustomPaint(size: const Size(_wheelSize, _wheelSize), painter: _HueRingPainter()),
              ),
              IgnorePointer(
                child: _HueHandle(hue: hue, radius: _wheelSize / 2 - 9, color: liveColor),
              ),
              // Bóng đèn trung tâm — chạm để bật/tắt, tách riêng khỏi vùng kéo vòng màu bên ngoài.
              GestureDetector(
                onTap: () => callbacks.onToggle(!state.isOn),
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.isOn ? liveColor : Colors.grey.withValues(alpha: 0.25),
                    boxShadow: state.isOn ? [BoxShadow(color: liveColor.withValues(alpha: 0.8), blurRadius: 20, spreadRadius: 2)] : null,
                  ),
                  child: Icon(Icons.lightbulb_rounded, color: state.isOn ? Colors.white : Colors.white54, size: 26),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HueHandle extends StatelessWidget {
  final double hue;
  final double radius;
  final Color color;
  const _HueHandle({required this.hue, required this.radius, required this.color});

  @override
  Widget build(BuildContext context) {
    final double rad = (hue - 90) * math.pi / 180;
    final Offset pos = Offset(math.cos(rad), math.sin(rad)) * radius;
    return Transform.translate(
      offset: pos,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)],
        ),
      ),
    );
  }
}

class _HueRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2 - 6;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..shader = SweepGradient(
        transform: const GradientRotation(-math.pi / 2), // hue 0 bắt đầu ở đỉnh 12h, khớp _handlePointer/_HueHandle
        colors: [for (int i = 0; i <= 360; i += 30) HSVColor.fromAHSV(1, (i % 360).toDouble(), 0.85, 1).toColor()],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, ring);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Đèn Dimmer — núm xoay vật lý (270°, chừa khoảng hở 90° ở đáy như núm âm lượng thật) điều
/// khiển độ sáng 0-100%. Quy ước: `state.value` = % độ sáng.
class DimmerLightAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const DimmerLightAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<DimmerLightAvatar> createState() => _DimmerLightAvatarState();
}

class _DimmerLightAvatarState extends State<DimmerLightAvatar> {
  // [FIX BƯỚC 3 — DÙNG CHUNG RotaryKnob] Phần toán góc (atan2 + track vẽ cung 270°) trước đây
  // tự viết riêng ở đây; HVAC (Bước 3) cần Y HỆT cơ chế này cho núm xoay nhiệt độ nên đã tách
  // thành RotaryKnob dùng chung ở avatar_shell.dart — tránh 2 bản atan2 dễ lệch nhau khi sửa sau.
  @override
  Widget build(BuildContext context) {
    const Color amber = Color(0xFFFFC96B);
    final double brightness = (widget.state.value ?? 0).clamp(0, 100);

    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: amber,
      child: Center(
        child: RotaryKnob(
          value: brightness / 100,
          color: widget.state.isOn ? amber : Colors.grey,
          onChanged: (pct) => widget.callbacks.onChange('value', (pct * 100).clamp(0, 100)),
          centerContent: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
                child: Text(
                  '${brightness.round()}%',
                  style: TextStyle(color: widget.state.isOn ? amber : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [Chiếu sáng | lighting] Đèn RGB (vòng chọn màu) + Đèn Dimmer (núm xoay).
final List<DeviceAvatarDefinition> lightingAvatars = [
  DeviceAvatarDefinition(
    id: 'light_rgb',
    name: 'Đèn RGB',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => RgbLightAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'light_dimmer',
    name: 'Đèn Dimmer',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => DimmerLightAvatar(state: state, callbacks: callbacks),
  ),
];
