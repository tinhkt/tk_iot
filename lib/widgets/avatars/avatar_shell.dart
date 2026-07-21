import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Khung DÙNG CHUNG cho mọi Avatar trong avatarLibrary — Neumorphism (2 bóng đối hướng, nền
/// đục) ở giao diện Sáng, Glassmorphism (nền tối trong mờ + viền sáng nhẹ) ở giao diện Tối, cùng
/// MỘT viền glow "thở" (pulse) quanh khung khi isOn=true. Gộp animation phát sáng vào ĐÚNG MỘT
/// chỗ này thay vì lặp lại AnimationController ở từng avatar — mỗi avatar con chỉ cần lo phần
/// hình vẽ ĐẶC TRƯNG của riêng nó (cánh quạt quay, vòng màu...), không cần tự quản lý glow.
class AvatarShell extends StatefulWidget {
  final Widget child;
  final bool isOn;
  final bool isOffline;
  final Color glowColor;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const AvatarShell({
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
  State<AvatarShell> createState() => _AvatarShellState();
}

class _AvatarShellState extends State<AvatarShell> with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  bool get _active => widget.isOn && !widget.isOffline;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color base = isDark ? const Color(0xFF1B2333) : const Color(0xFFEEF1F6);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final double pulse = _active ? (0.55 + _glowController.value * 0.45) : 0.0;
          return Opacity(
            opacity: widget.isOffline ? 0.45 : 1.0,
            child: Container(
              width: widget.width,
              height: widget.height,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: _active
                      ? widget.glowColor.withValues(alpha: 0.25 + pulse * 0.35)
                      : Colors.white.withValues(alpha: isDark ? 0.06 : 0.7),
                  width: _active ? 1.6 : 1,
                ),
                boxShadow: isDark
                    ? [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 16, offset: const Offset(6, 6)),
                        BoxShadow(color: Colors.white.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(-6, -6)),
                        if (_active) BoxShadow(color: widget.glowColor.withValues(alpha: pulse * 0.5), blurRadius: 26, spreadRadius: 1),
                      ]
                    : [
                        BoxShadow(color: const Color(0xFFB9C1D1).withValues(alpha: 0.7), blurRadius: 14, offset: const Offset(7, 7)),
                        const BoxShadow(color: Colors.white, blurRadius: 14, offset: Offset(-7, -7)),
                        if (_active) BoxShadow(color: widget.glowColor.withValues(alpha: pulse * 0.35), blurRadius: 22, spreadRadius: 1),
                      ],
              ),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Núm xoay vật lý DÙNG CHUNG (270°, chừa khoảng hở 90° ở đáy như núm âm lượng thật) — tách ra
/// từ DimmerLightAvatar (Bước 2) vì HVAC (Bước 3) cần ĐÚNG cơ chế này cho núm xoay nhiệt độ.
/// Giữ MỘT chỗ duy nhất cho phần toán góc (atan2) tương đối tinh vi thay vì chép lại lần 2 —
/// tránh 2 bản dễ lệch nhau khi sửa sau này. [value] LUÔN chuẩn hoá 0..1; đơn vị thật (%, °C...)
/// do widget gọi tự quy đổi trước khi truyền vào / sau khi nhận ra từ onChanged.
class RotaryKnob extends StatelessWidget {
  final double value; // 0..1
  final ValueChanged<double> onChanged; // trả về 0..1
  final Color color;
  final double size;
  final Widget? centerContent; // nội dung hiển thị đè giữa núm (vd số nhiệt độ, % độ sáng)

  const RotaryKnob({
    super.key,
    required this.value,
    required this.onChanged,
    required this.color,
    this.size = 110,
    this.centerContent,
  });

  void _updateFromLocal(Offset local) {
    final Offset center = Offset(size / 2, size / 2);
    // atan2 chuẩn (0 = phải, tăng theo chiều kim đồng hồ vì trục y hướng xuống) -> quy về "0° ở
    // đỉnh 12h" bằng +90, rồi gập về [-180,180] và kẹp trong [-135,135] (chừa hở 90° ở đáy).
    final double rawAngle = math.atan2(local.dy - center.dy, local.dx - center.dx) * 180 / math.pi;
    double topReferenced = rawAngle + 90;
    if (topReferenced > 180) topReferenced -= 360;
    final double clamped = topReferenced.clamp(-135.0, 135.0);
    onChanged(((clamped + 135) / 270).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final double pct = value.clamp(0.0, 1.0);
    final double knobAngleDeg = -135 + pct * 270;

    return GestureDetector(
      onPanUpdate: (d) => _updateFromLocal(d.localPosition),
      onTapDown: (d) => _updateFromLocal(d.localPosition),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: Size(size, size), painter: _RotaryTrackPainter(pct: pct, color: color)),
            Transform.rotate(
              angle: knobAngleDeg * math.pi / 180,
              child: Container(
                width: size * 0.53,
                height: size * 0.53,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.95), Colors.grey.shade400]),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2))],
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: EdgeInsets.only(top: size * 0.07),
                    width: 4,
                    height: size * 0.13,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ),
            // [KHÔNG bọc IgnorePointer] Cố ý ĐỂ centerContent nhận được tap riêng (vd nút bật/tắt
            // đè giữa núm) — đánh đổi: vì onTapDown của GestureDetector NGOÀI (kéo núm) phủ TOÀN
            // BỘ vùng núm và luôn bắn trước khi gesture arena phân xử xong, một cú chạm đúng vào
            // centerContent CŨNG khiến giá trị núm nhích nhẹ theo vị trí chạm đó (thường về sát
            // biên 0%/100% vì centerContent thường đặt ở đáy, gần khe hở 90°) — chấp nhận được,
            // không chặn hẳn tap như trước.
            ?centerContent,
          ],
        ),
      ),
    );
  }
}

class _RotaryTrackPainter extends CustomPainter {
  final double pct; // 0..1
  final Color color;
  _RotaryTrackPainter({required this.pct, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.width / 2 - 4;
    const double startAngle = -225 * math.pi / 180; // -135° (đỉnh-quy-chiếu) quy về hệ toán chuẩn (-90 lệch trục)
    const double sweep = 270 * math.pi / 180;
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.withValues(alpha: 0.25);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep, false, track);
    final Paint active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweep * pct, false, active);
  }

  @override
  bool shouldRepaint(covariant _RotaryTrackPainter oldDelegate) => oldDelegate.pct != pct || oldDelegate.color != color;
}

/// Sparkline mini DÙNG CHUNG cho avatar BMS cần hiển thị xu hướng (HVAC nhiệt độ/độ ẩm...).
/// [history] null/< 2 điểm -> KHÔNG bịa dữ liệu giả, chỉ vẽ đường đứt nét trung tính để người
/// vận hành biết đây là "chưa có log lịch sử", không nhầm là "ổn định tuyệt đối".
class MiniSparkline extends StatelessWidget {
  final List<double>? history;
  final Color color;
  final double width;
  final double height;

  const MiniSparkline({super.key, required this.history, required this.color, this.width = 100, this.height = 26});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, height), painter: _SparklinePainter(history: history, color: color));
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double>? history;
  final Color color;
  _SparklinePainter({required this.history, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final List<double>? h = history;
    if (h == null || h.length < 2) {
      final Paint dash = Paint()
        ..color = Colors.grey.withValues(alpha: 0.4)
        ..strokeWidth = 1.5;
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, size.height / 2), Offset(x + 4, size.height / 2), dash);
        x += 8;
      }
      return;
    }

    double minV = h.first, maxV = h.first;
    for (final v in h) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final double range = (maxV - minV).abs() < 0.01 ? 1 : (maxV - minV);
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path();
    for (int i = 0; i < h.length; i++) {
      final double x = size.width * i / (h.length - 1);
      final double y = size.height - ((h[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.history != history || oldDelegate.color != color;
}

/// Chấm LED nhỏ (vd hàng chấm chọn tốc độ quạt) — bật sáng theo [active], dùng CHUNG cho mọi
/// avatar cần hiển thị "nấc đang chọn" (tốc độ quạt, kênh switch nhiều gang...).
class AvatarDot extends StatelessWidget {
  final bool active;
  final Color color;
  final VoidCallback? onTap;

  const AvatarDot({super.key, required this.active, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 9,
        height: 9,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : color.withValues(alpha: 0.18),
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6, spreadRadius: 0.5)] : null,
        ),
      ),
    );
  }
}
