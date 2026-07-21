import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _spotWhite = Color(0xFFFFF8E1);
const Color _streetAmber = Color(0xFFFFA726);
const Color _stripCyan = Color(0xFF64FFDA);

/// Đèn rọi/Đèn hắt (Spotlight) — hình nón ánh sáng chiếu XUỐNG từ 1 điểm, mô phỏng đúng đặc tính
/// định hướng của đèn rọi (khác đèn tròn tỏa đều của Downlight/Đèn ngủ).
class SpotlightAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const SpotlightAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _spotWhite,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 26,
            height: 14,
            decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          ),
          CustomPaint(size: const Size(80, 64), painter: _ConeBeamPainter(on: on, color: _spotWhite)),
        ],
      ),
    );
  }
}

class _ConeBeamPainter extends CustomPainter {
  final bool on;
  final Color color;
  _ConeBeamPainter({required this.on, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Path cone = Path()
      ..moveTo(size.width / 2 - 6, 0)
      ..lineTo(size.width / 2 + 6, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final Paint fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (on ? color : Colors.grey).withValues(alpha: on ? 0.75 : 0.15),
          (on ? color : Colors.grey).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(cone, fill);
  }

  @override
  bool shouldRepaint(covariant _ConeBeamPainter oldDelegate) => oldDelegate.on != on;
}

/// Đèn cao áp sân vườn/đường nội khu (Street light) — cột đèn cao + chóa đèn phát sáng cam ấm,
/// mô phỏng đúng hình dáng đèn đường quen thuộc thay vì bóng đèn tròn thông thường.
class StreetLightAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const StreetLightAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    final Color color = state.isOffline ? Colors.grey : _streetAmber;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _streetAmber,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: on ? RadialGradient(colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.05)]) : null,
              color: on ? null : Colors.grey.withValues(alpha: 0.12),
            ),
          ),
          Container(width: 3, height: 8, color: Colors.grey.shade600),
          Container(width: 4, height: 46, color: Colors.grey.shade600),
          Container(width: 22, height: 4, decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(2))),
        ],
      ),
    );
  }
}

/// Đèn LED dây/LED viền (LED strip) — thanh dài mảnh với gradient nhiều màu "chạy" liên tục khi
/// BẬT (mô phỏng hiệu ứng RGB dây LED trang trí thật, khác Đèn ống tuýp trắng tĩnh 1 màu).
class LedStripAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const LedStripAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<LedStripAvatar> createState() => _LedStripAvatarState();
}

class _LedStripAvatarState extends State<LedStripAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _shift;

  @override
  void initState() {
    super.initState();
    _shift = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    if (widget.state.isOn && !widget.state.isOffline) _shift.repeat();
  }

  @override
  void didUpdateWidget(covariant LedStripAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool on = widget.state.isOn && !widget.state.isOffline;
    if (on) {
      if (!_shift.isAnimating) _shift.repeat();
    } else {
      _shift.stop();
    }
  }

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.isOn && !widget.state.isOffline;
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _stripCyan,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Center(
        child: AnimatedBuilder(
          animation: _shift,
          builder: (context, _) => Container(
            width: 106,
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: on
                  ? LinearGradient(
                      begin: Alignment(-1 + _shift.value * 2, 0),
                      end: Alignment(1 + _shift.value * 2, 0),
                      colors: const [Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF64FFDA), Color(0xFF448AFF), Color(0xFFE040FB), Color(0xFFFF5252)],
                    )
                  : null,
              color: on ? null : Colors.grey.withValues(alpha: 0.2),
              boxShadow: on ? [BoxShadow(color: _stripCyan.withValues(alpha: 0.55), blurRadius: 16, spreadRadius: 1)] : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// [Chiếu sáng | lighting] Đèn rọi, Đèn cao áp sân vườn, Đèn LED dây — bổ sung nhóm BMS chuyên
/// nghiệp (Đèn chùm đã có sẵn ở lighting_extra_avatars.dart, không lặp lại ở đây).
final List<DeviceAvatarDefinition> lightingBmsAvatars = [
  DeviceAvatarDefinition(
    id: 'spotlight',
    name: 'Đèn rọi / Đèn hắt',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => SpotlightAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'street_light',
    name: 'Đèn cao áp sân vườn',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => StreetLightAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'led_strip',
    name: 'Đèn LED dây / LED viền',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => LedStripAvatar(state: state, callbacks: callbacks),
  ),
];
