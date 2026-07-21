import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/energy_models.dart';

const Color _solarYellow = Color(0xFFFFC107);
const Color _gridGreen = Color(0xFF00A651);
const Color _batteryBlue = Color(0xFF2196F3);
const Color _loadNeutral = Color(0xFFFF7043);
const Color _idleGrey = Color(0xFF64748B);

/// [PHẦN 1 — SƠ ĐỒ LUỒNG NĂNG LƯỢNG] Stack 4 khối góc (Lưới/PV/Tải/Ắc quy) quanh 1 Hub trung
/// tâm (Inverter), nối bằng 4 đường nét đứt do [_FlowLinesPainter] tự vẽ theo toạ độ hình học cố
/// định (KHÔNG dùng GlobalKey đo RenderBox — 5 khối đặt theo đúng % kích thước khung, painter tính
/// lại CÙNG công thức % nên luôn khớp pixel-perfect với vị trí hiển thị thật, không lệch khung
/// hình nào dù xoay/resize). Thuần hiển thị theo [snapshot] truyền vào — không tự gọi API/MQTT
/// (xem energy_models.dart).
class PowerFlowDiagram extends StatefulWidget {
  final EnergyFlowSnapshot snapshot;
  final double height;

  const PowerFlowDiagram({super.key, required this.snapshot, this.height = 340});

  @override
  State<PowerFlowDiagram> createState() => _PowerFlowDiagramState();
}

class _PowerFlowDiagramState extends State<PowerFlowDiagram> with SingleTickerProviderStateMixin {
  late final AnimationController _flowController;

  @override
  void initState() {
    super.initState();
    // [ANIMATEDBUILDER — MỘT CONTROLLER DUY NHẤT CHO CẢ 4 ĐƯỜNG] repeat() vô hạn, giá trị 0..1
    // lặp lại mỗi 1.6s — _FlowLinesPainter tự diễn giải giá trị này thành vị trí các chấm chạy
    // TRÊN TỪNG ĐƯỜNG riêng (mỗi đường tự cộng thêm pha lệch + tự đảo chiều theo dấu công suất),
    // không cần 4 AnimationController riêng biệt (tốn tài nguyên, khó đồng bộ nhịp thị giác).
    _flowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _flowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final EnergyFlowSnapshot s = widget.snapshot;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double w = constraints.maxWidth;
          final double h = widget.height;
          const double nodeSize = 84;

          // [TOẠ ĐỘ HÌNH HỌC — DÙNG CHUNG GIỮA PAINTER VÀ NODE WIDGET] 5 điểm neo theo % kích
          // thước khung — đổi số ở ĐÂY là đủ, painter đọc lại đúng hàm này nên luôn khớp.
          Offset anchor(double fx, double fy) => Offset(w * fx, h * fy);
          final Offset gridPos = anchor(0.18, 0.18);
          final Offset pvPos = anchor(0.82, 0.18);
          final Offset loadPos = anchor(0.18, 0.82);
          final Offset batteryPos = anchor(0.82, 0.82);
          final Offset hubPos = anchor(0.5, 0.5);

          return Stack(
            children: [
              // Lớp đường dây LUÔN vẽ TRƯỚC (dưới cùng) — các khối node đè lên trên che 2 đầu mút.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _flowController,
                  builder: (context, _) => CustomPaint(
                    painter: _FlowLinesPainter(
                      t: _flowController.value,
                      gridPos: gridPos,
                      pvPos: pvPos,
                      loadPos: loadPos,
                      batteryPos: batteryPos,
                      hubPos: hubPos,
                      snapshot: s,
                      isDark: isDark,
                    ),
                  ),
                ),
              ),
              _buildNode(
                center: gridPos,
                size: nodeSize,
                icon: Icons.bolt_rounded,
                label: 'LƯỚI ĐIỆN',
                color: s.isGridImporting || s.isGridExporting ? _gridGreen : _idleGrey,
                isDark: isDark,
                lines: [
                  '${s.gridKw.abs().toStringAsFixed(2)} kW',
                  if (s.gridVoltage != null) '${s.gridVoltage!.toStringAsFixed(0)} V',
                  if (s.gridCurrent != null) '${s.gridCurrent!.toStringAsFixed(1)} A',
                ],
              ),
              _buildNode(
                center: pvPos,
                size: nodeSize,
                icon: Icons.solar_power_rounded,
                label: 'TẤM PIN (PV)',
                color: s.hasSolarFlow ? _solarYellow : _idleGrey,
                isDark: isDark,
                lines: [
                  '${s.solarKw.toStringAsFixed(2)} kW',
                  if (s.solarVoltage != null) '${s.solarVoltage!.toStringAsFixed(0)} V',
                  if (s.solarCurrent != null) '${s.solarCurrent!.toStringAsFixed(1)} A',
                ],
              ),
              _buildNode(
                center: loadPos,
                size: nodeSize,
                icon: Icons.home_rounded,
                label: 'TẢI TIÊU THỤ',
                color: s.loadKw > 0.01 ? _loadNeutral : _idleGrey,
                isDark: isDark,
                lines: ['${s.loadKw.toStringAsFixed(2)} kW'],
              ),
              _buildNode(
                center: batteryPos,
                size: nodeSize,
                icon: s.isBatteryCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                label: 'ẮC QUY',
                color: s.isBatteryCharging || s.isBatteryDischarging ? _batteryBlue : _idleGrey,
                isDark: isDark,
                lines: [
                  '${s.batteryKw.abs().toStringAsFixed(2)} kW',
                  if (s.batterySocPct != null) '${s.batterySocPct!.toStringAsFixed(0)}% SOC',
                ],
              ),
              _buildHub(center: hubPos, isDark: isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNode({
    required Offset center,
    required double size,
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required List<String> lines,
  }) {
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border.all(color: color, width: 2),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14, spreadRadius: 1)],
            ),
            child: Icon(icon, size: 32, color: color),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.3, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 2),
          for (final line in lines)
            Text(line, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildHub({required Offset center, required bool isDark}) {
    const double size = 64;
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [Colors.grey.shade700, Colors.grey.shade900]),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 3))],
        ),
        child: const Icon(Icons.device_hub_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

/// [CUSTOMPAINTER — 4 ĐƯỜNG NÉT ĐỨT + CHẤM CHẠY] Vẽ 4 đoạn Hub<->{Grid,PV,Load,Battery}. Mỗi
/// đoạn: nền LUÔN có 1 đường nét đứt xám mờ (đường dây vật lý, hiện diện bất kể có dòng chảy hay
/// không) — nếu [active] (công suất khác 0), phủ thêm 1 đường nét đứt MÀU trên cùng quỹ đạo + 3
/// chấm tròn chạy dọc theo hướng dòng điện thật (đảo chiều qua [reversed]).
class _FlowLinesPainter extends CustomPainter {
  final double t; // 0..1, pha animation hiện tại (lặp vô hạn)
  final Offset gridPos, pvPos, loadPos, batteryPos, hubPos;
  final EnergyFlowSnapshot snapshot;
  final bool isDark;

  _FlowLinesPainter({
    required this.t,
    required this.gridPos,
    required this.pvPos,
    required this.loadPos,
    required this.batteryPos,
    required this.hubPos,
    required this.snapshot,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Color baseLineColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);

    // PV -> Hub: nguồn PHÁT, dòng LUÔN chảy VÀO hub khi solarKw > 0 (không có chiều ngược — tấm
    // pin không "hút" điện).
    _drawSegment(canvas, pvPos, hubPos, baseLineColor, _solarYellow, snapshot.hasSolarFlow, reversed: false);
    // Grid <-> Hub: NHẬP (Grid->Hub) khi mua điện, XUẤT (Hub->Grid) khi hoà lưới bán ngược.
    _drawSegment(canvas, gridPos, hubPos, baseLineColor, _gridGreen, snapshot.isGridImporting || snapshot.isGridExporting, reversed: snapshot.isGridExporting);
    // Hub <-> Battery: SẠC (Hub->Battery) khi batteryKw<0, XẢ (Battery->Hub) khi batteryKw>0 —
    // đường vẽ theo thứ tự (Hub, Battery) nên "reversed=false" nghĩa là Hub->Battery (SẠC).
    _drawSegment(canvas, hubPos, batteryPos, baseLineColor, _batteryBlue, snapshot.isBatteryCharging || snapshot.isBatteryDischarging, reversed: snapshot.isBatteryDischarging);
    // Hub -> Load: tải luôn TIÊU THỤ, dòng luôn chảy từ Hub ra Load khi loadKw > 0.
    _drawSegment(canvas, hubPos, loadPos, baseLineColor, _loadNeutral, snapshot.loadKw > 0.01, reversed: false);
  }

  void _drawSegment(Canvas canvas, Offset from, Offset to, Color baseColor, Color activeColor, bool active, {required bool reversed}) {
    _drawDashedLine(canvas, from, to, baseColor, 1.4);
    if (!active) return;
    _drawDashedLine(canvas, from, to, activeColor.withValues(alpha: 0.55), 2.2);
    _drawFlowDots(canvas, from, to, activeColor, reversed);
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Color color, double strokeWidth) {
    const double dashLen = 6, gapLen = 5;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final double total = (to - from).distance;
    if (total < 1) return;
    final Offset dir = (to - from) / total;
    double covered = 0;
    while (covered < total) {
      final double segEnd = math.min(covered + dashLen, total);
      canvas.drawLine(from + dir * covered, from + dir * segEnd, paint);
      covered = segEnd + gapLen;
    }
  }

  void _drawFlowDots(Canvas canvas, Offset from, Offset to, Color color, bool reversed) {
    final Paint dotPaint = Paint()..color = color;
    final Paint glowPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    const int dotCount = 3;
    for (int i = 0; i < dotCount; i++) {
      double frac = (t + i / dotCount) % 1.0;
      if (reversed) frac = 1.0 - frac;
      final Offset pos = Offset.lerp(from, to, frac)!;
      canvas.drawCircle(pos, 4.5, glowPaint);
      canvas.drawCircle(pos, 2.6, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowLinesPainter oldDelegate) => oldDelegate.t != t || oldDelegate.snapshot != snapshot;
}
