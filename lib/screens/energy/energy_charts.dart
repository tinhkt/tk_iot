import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/energy_models.dart';

const Color _tkGreen = Color(0xFF00A651);
const Color _solarYellow = Color(0xFFFFC107);

/// [PHẦN 2A — LineChart] Công suất tiêu thụ (W) theo thời gian. [points] rỗng -> vẽ khung trục
/// trống + dòng chữ "Chưa có dữ liệu" (KHÔNG bịa đường cong giả trông như dữ liệu thật — cùng
/// nguyên tắc `metricHistory` null ở device_avatar_definition.dart).
class PowerLineChart extends StatelessWidget {
  final List<PowerHistoryPoint> points;
  final double height;

  const PowerLineChart({super.key, required this.points, this.height = 220});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color gridColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    final Color labelColor = isDark ? Colors.white54 : Colors.black54;

    if (points.isEmpty) {
      return _EmptyChartPlaceholder(height: height, isDark: isDark, message: 'Chưa có dữ liệu công suất trong khung thời gian này');
    }

    final double maxY = points.map((p) => p.watts).fold<double>(0, (a, b) => b > a ? b : a) * 1.2;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 100 : maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY <= 0 ? 100 : maxY) / 4, getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) => Text('${value.toInt()}W', style: TextStyle(fontSize: 9, color: labelColor)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: points.length > 6 ? (points.length / 6).ceilToDouble() : 1,
                getTitlesWidget: (value, meta) {
                  final int i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox();
                  final DateTime t = points[i].time;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 9, color: labelColor)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem('${s.y.toStringAsFixed(0)} W', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].watts)],
              isCurved: true,
              curveSmoothness: 0.25,
              color: _tkGreen,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: _tkGreen.withValues(alpha: 0.15)),
            ),
          ],
        ),
      ),
    );
  }
}

/// [PHẦN 2B — BarChart] So sánh Sản lượng Solar (kWh) vs Điện lưới tiêu thụ (kWh) theo từng ngày.
/// 2 cột cạnh nhau mỗi ngày (Solar vàng, Lưới xanh lá) — khớp đúng bảng màu đã dùng ở
/// [PowerFlowDiagram] (Phần 1) để người xem liên kết trực quan 2 phần của cùng màn hình.
class SolarGridBarChart extends StatelessWidget {
  final List<DailyEnergyStat> stats;
  final double height;

  const SolarGridBarChart({super.key, required this.stats, this.height = 220});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color labelColor = isDark ? Colors.white54 : Colors.black54;
    final Color gridColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);

    if (stats.isEmpty) {
      return _EmptyChartPlaceholder(height: height, isDark: isDark, message: 'Chưa có dữ liệu thống kê ngày trong khung thời gian này');
    }

    final double maxVal = stats.fold<double>(0, (a, s) => [a, s.solarKwh, s.gridKwh].reduce((x, y) => x > y ? x : y));
    final double maxY = maxVal <= 0 ? 10 : maxVal * 1.25;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(children: [
            _legendDot(_solarYellow, 'Solar sinh ra (kWh)', labelColor),
            const SizedBox(width: 14),
            _legendDot(_tkGreen, 'Điện lưới tiêu thụ (kWh)', labelColor),
          ]),
        ),
        SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY / 4, getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (value, meta) => Text(value.toStringAsFixed(0), style: TextStyle(fontSize: 9, color: labelColor)))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final int i = value.toInt();
                      if (i < 0 || i >= stats.length) return const SizedBox();
                      return Padding(padding: const EdgeInsets.only(top: 4), child: Text('${stats[i].day.day}', style: TextStyle(fontSize: 9, color: labelColor)));
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem('${rod.toY.toStringAsFixed(1)} kWh', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
              barGroups: [
                for (int i = 0; i < stats.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(toY: stats[i].solarKwh, color: _solarYellow, width: 6, borderRadius: BorderRadius.circular(2)),
                    BarChartRodData(toY: stats[i].gridKwh, color: _tkGreen, width: 6, borderRadius: BorderRadius.circular(2)),
                  ], barsSpace: 3),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label, Color textColor) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: textColor)),
      ]);
}

class _EmptyChartPlaceholder extends StatelessWidget {
  final double height;
  final bool isDark;
  final String message;
  const _EmptyChartPlaceholder({required this.height, required this.isDark, required this.message});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded, size: 32, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
          ],
        ),
      ),
    );
  }
}
