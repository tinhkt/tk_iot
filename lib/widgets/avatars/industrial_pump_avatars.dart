import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'industrial_shell.dart';

const Color _pumpBlue = Color(0xFF29ABE2);

/// Máy bơm nước công suất lớn — hoạt ảnh luân chuyển dòng nước trong ống khi đang chạy + cảnh
/// báo mức bồn CẠN/ĐẦY. Quy ước: `state.metric` = mức nước trong bồn (%, 0-100, CHỈ-ĐỌC — cảm
/// biến phao/siêu âm, không phải thứ người dùng "chỉnh" qua onChange).
/// [Bước 5] Tham số hoá icon/màu/nhãn — dùng CHUNG khung+animation dòng nước này cho 3 loại bơm
/// chuyên dụng khác (Tăng áp/Cứu hỏa/Bể lớn) thay vì chép lại nguyên khối 3 lần.
class IndustrialPumpAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;
  final IconData icon;
  final Color baseColor;
  final String runningLabel;

  const IndustrialPumpAvatar({
    super.key,
    required this.state,
    required this.callbacks,
    this.icon = Icons.opacity_rounded,
    this.baseColor = _pumpBlue,
    this.runningLabel = 'ĐANG BƠM',
  });

  @override
  State<IndustrialPumpAvatar> createState() => _IndustrialPumpAvatarState();
}

class _IndustrialPumpAvatarState extends State<IndustrialPumpAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _flow;

  @override
  void initState() {
    super.initState();
    _flow = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool running = widget.state.isOn && !widget.state.isOffline;
    final double level = (widget.state.metric ?? 50).clamp(0, 100);
    final bool low = level <= 15;
    final bool full = level >= 90;
    final Color statusColor = widget.state.isOffline ? Colors.grey : (low ? industrialRed : (full ? industrialAmber : widget.baseColor));

    return RuggedShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: statusColor,
      width: 316,
      height: 150,
      child: Row(
        children: [
          // Cột mức bồn chứa — thanh dâng theo % mức nước, đổi màu theo ngưỡng cạn/đầy.
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(4)),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: level / 100,
                        widthFactor: 1,
                        child: Container(color: statusColor.withValues(alpha: 0.6)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${level.round()}%', style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Icon(widget.icon, color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 20,
                        child: AnimatedBuilder(
                          animation: _flow,
                          builder: (context, _) => CustomPaint(painter: _FlowPainter(phase: _flow.value, moving: running, color: statusColor)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    widget.state.isOffline
                        ? 'MẤT KẾT NỐI'
                        : (low ? 'CẢNH BÁO: BỒN CẠN' : (full ? 'CẢNH BÁO: BỒN ĐẦY' : (running ? widget.runningLabel : 'SẴN SÀNG'))),
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(6)),
                  child: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              EStopButton(onPressed: () => widget.callbacks.onToggle(false)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  final double phase; // 0..1
  final bool moving;
  final Color color;
  _FlowPainter({required this.phase, required this.moving, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint pipe = Paint()
      ..color = Colors.white10
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(4, size.height / 2), Offset(size.width - 4, size.height / 2), pipe);

    if (!moving) return;
    final Paint chevron = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const double step = 16;
    final double offset = phase * step;
    for (double x = -step + offset % step; x < size.width; x += step) {
      final Path p = Path()
        ..moveTo(x, size.height * 0.25)
        ..lineTo(x + 5, size.height / 2)
        ..lineTo(x, size.height * 0.75);
      canvas.drawPath(p, chevron);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) => oldDelegate.phase != phase || oldDelegate.moving != moving;
}

/// [Quản lý trạm bơm | industrial_pump] Bơm công suất lớn (chung) + 3 bơm chuyên dụng Bước 5
/// (Tăng áp/Cứu hỏa/Bể lớn) — dùng CHUNG IndustrialPumpAvatar (khung+animation dòng nước), chỉ
/// khác icon/màu/nhãn để giữ bản sắc riêng từng loại.
final List<DeviceAvatarDefinition> industrialPumpAvatars = [
  DeviceAvatarDefinition(
    id: 'industrial_pump',
    name: 'Máy bơm nước công suất lớn',
    category: 'industrial_pump',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => IndustrialPumpAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'booster_pump',
    name: 'Bơm tăng áp',
    category: 'industrial_pump',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => IndustrialPumpAvatar(
      state: state,
      callbacks: callbacks,
      icon: Icons.speed_rounded,
      baseColor: const Color(0xFF7E57C2),
      runningLabel: 'ĐANG TĂNG ÁP',
    ),
  ),
  DeviceAvatarDefinition(
    id: 'fire_pump',
    name: 'Bơm cứu hỏa',
    category: 'industrial_pump',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => IndustrialPumpAvatar(
      state: state,
      callbacks: callbacks,
      icon: Icons.local_fire_department_rounded,
      baseColor: industrialRed,
      runningLabel: 'SẴN SÀNG CHỮA CHÁY',
    ),
  ),
  DeviceAvatarDefinition(
    id: 'large_tank_pump',
    name: 'Bơm bể lớn',
    category: 'industrial_pump',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => IndustrialPumpAvatar(
      state: state,
      callbacks: callbacks,
      icon: Icons.water_rounded,
      baseColor: const Color(0xFF26A69A),
      runningLabel: 'ĐANG BƠM BỂ',
    ),
  ),
];
