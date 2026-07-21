import 'dart:math' as math;
import 'package:flutter/material.dart';

const Color industrialAmber = Color(0xFFFFB300);
const Color industrialRed = Color(0xFFE53935);

/// Khung DÙNG CHUNG cho nhóm Công nghiệp (Bước 4) — phong cách "Rugged": nền kim loại tối, góc
/// bo NHỎ (khác hẳn Neumorphism/Glassmorphism bo tròn mềm mại ở AvatarShell của Bước 2/3), viền
/// hổ phách cảnh báo khi offline, glow theo màu trạng thái khi đang chạy. KHÔNG dùng chung
/// AvatarShell — ngôn ngữ thị giác 2 nhóm khác hẳn nhau THEO ĐÚNG YÊU CẦU từng Bước, tự quản lý
/// AnimationController pulse riêng (chấp nhận trùng lặp NHỎ về cơ chế để giữ styling độc lập,
/// thà rõ ràng còn hơn ép chung một shell rồi phải if/else phong cách bên trong nó).
class RuggedShell extends StatefulWidget {
  final Widget child;
  final bool isOn;
  final bool isOffline;
  final Color glowColor;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const RuggedShell({
    super.key,
    required this.child,
    required this.isOn,
    this.isOffline = false,
    required this.glowColor,
    this.width = 150,
    this.height = 150,
    this.onTap,
  });

  @override
  State<RuggedShell> createState() => _RuggedShellState();
}

class _RuggedShellState extends State<RuggedShell> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _active => widget.isOn && !widget.isOffline;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final double glow = _active ? (0.5 + _pulse.value * 0.5) : 0.0;
          return Container(
            width: widget.width,
            height: widget.height,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A3F47), Color(0xFF20232A)]),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isOffline
                    ? industrialAmber.withValues(alpha: 0.6)
                    : (_active ? widget.glowColor.withValues(alpha: 0.4 + glow * 0.4) : Colors.white24),
                width: widget.isOffline || _active ? 2 : 1,
              ),
              boxShadow: [
                const BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(3, 4)),
                if (_active) BoxShadow(color: widget.glowColor.withValues(alpha: glow * 0.55), blurRadius: 20, spreadRadius: 1),
              ],
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Nút DỪNG KHẨN CẤP (Emergency Stop) kiểu nút nấm đỏ vật lý — dùng CHUNG cho mọi avatar Công
/// nghiệp có động cơ/tải cần dừng ngay. Gọi thẳng onToggle(false) — KHÔNG bao giờ gọi onChange:
/// E-STOP chỉ có đúng MỘT ý nghĩa duy nhất (NGẮT NGAY), không mơ hồ theo field nào khác.
class EStopButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;

  const EStopButton({super.key, required this.onPressed, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFF5252), Color(0xFFB71C1C)]),
          border: Border.all(color: Colors.black87, width: 2),
          boxShadow: [BoxShadow(color: industrialRed.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1)],
        ),
        child: Icon(Icons.power_settings_new_rounded, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}

/// Đồng hồ đo kim (Vol/Ampe/Áp suất...) DÙNG CHUNG — cung 240° (chừa hở 120° ở đáy, kiểu đồng hồ
/// analog công nghiệp thật), có vạch NGƯỠNG ĐỎ (danger zone) tuỳ chỉnh theo từng loại đại lượng.
class GaugeDial extends StatelessWidget {
  final double value; // giá trị thật (đơn vị theo [unit])
  final double min;
  final double max;
  final double dangerFrom; // giá trị này trở lên -> tô đỏ + kim đỏ
  final String unit;
  final Color color;
  final double size;

  const GaugeDial({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.dangerFrom,
    required this.unit,
    required this.color,
    this.size = 90,
  });

  @override
  Widget build(BuildContext context) {
    final double pct = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final double dangerPct = ((dangerFrom - min) / (max - min)).clamp(0.0, 1.0);
    final bool danger = value >= dangerFrom;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _GaugePainter(pct: pct, dangerPct: dangerPct, color: danger ? industrialRed : color)),
          Padding(
            padding: EdgeInsets.only(top: size * 0.16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.abs() >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1),
                  style: TextStyle(color: danger ? industrialRed : Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.2),
                ),
                Text(unit, style: TextStyle(color: Colors.white54, fontSize: size * 0.11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double pct; // 0..1 vị trí kim
  final double dangerPct; // 0..1 điểm bắt đầu vùng đỏ trên cung
  final Color color;
  _GaugePainter({required this.pct, required this.dangerPct, required this.color});

  static const double _startAngle = -210 * math.pi / 180; // cung 240°, hở 120° ở đáy
  static const double _sweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2 - 6;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = Colors.white12;
    canvas.drawArc(rect, _startAngle, _sweep, false, track);

    if (dangerPct < 1) {
      final Paint dangerTrack = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = industrialRed.withValues(alpha: 0.35);
      canvas.drawArc(rect, _startAngle + _sweep * dangerPct, _sweep * (1 - dangerPct), false, dangerTrack);
    }

    final Paint active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, _startAngle, _sweep * pct, false, active);

    final double needleAngle = _startAngle + _sweep * pct;
    final Offset needleEnd = center + Offset(math.cos(needleAngle), math.sin(needleAngle)) * (radius - 10);
    canvas.drawLine(center, needleEnd, Paint()
      ..color = Colors.white70
      ..strokeWidth = 2);
    canvas.drawCircle(center, 3, Paint()..color = Colors.white70);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) => oldDelegate.pct != pct || oldDelegate.color != color;
}
