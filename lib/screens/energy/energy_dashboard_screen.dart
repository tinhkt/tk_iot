import 'package:flutter/material.dart';
import '../../models/energy_models.dart';
import '../../widgets/app_ui_wrappers.dart';
import 'power_flow_diagram.dart';
import 'energy_charts.dart';
import 'device_energy_table.dart';
import 'energy_sample_data.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [MÀN HÌNH GIÁM SÁT ĐIỆN NĂNG — BMS] Ghép 3 phần theo đúng yêu cầu: (1) Sơ đồ luồng năng
/// lượng sống động [PowerFlowDiagram], (2) 2 biểu đồ lịch sử [PowerLineChart]/[SolarGridBarChart]
/// + toggle khung thời gian, (3) bảng chi tiết thiết bị [DeviceEnergyTable].
///
/// [KIẾN TRÚC DATA] "Server mù" — màn hình này KHÔNG tự gọi API/MQTT. [dataForRange] là điểm nối
/// DUY NHẤT với dữ liệu thật: truyền 1 hàm đọc từ Provider/API thật (lọc theo khung thời gian
/// đang chọn) khi Backend đã có endpoint tương ứng. Khi CHƯA truyền (null, mặc định) — dùng
/// [buildSampleEnergyData] (energy_sample_data.dart) làm placeholder DỰNG UI, KHÔNG phải dữ liệu
/// sản xuất (xem cảnh báo đầy đủ trong file đó).
class EnergyDashboardScreen extends StatefulWidget {
  final EnergyDashboardData Function(EnergyTimeRange range)? dataForRange;
  final bool embedded; // true khi nhúng làm tab con (bỏ AppBar riêng, giữ đồng bộ pattern AutomationScreen)

  const EnergyDashboardScreen({super.key, this.dataForRange, this.embedded = false});

  @override
  State<EnergyDashboardScreen> createState() => _EnergyDashboardScreenState();
}

class _EnergyDashboardScreenState extends State<EnergyDashboardScreen> {
  EnergyTimeRange _range = EnergyTimeRange.today;

  EnergyDashboardData get _data => (widget.dataForRange ?? buildSampleEnergyData)(_range);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final EnergyDashboardData data = _data;

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Giám sát Điện năng'),
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              foregroundColor: textMain,
              elevation: 0,
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  const Icon(Icons.bolt_rounded, color: _tkGreen, size: 26),
                  const SizedBox(width: 12),
                  Text('Giám sát Điện năng', style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),

            // ================= PHẦN 1 — SƠ ĐỒ LUỒNG NĂNG LƯỢNG =================
            _SectionHeader(title: 'Luồng năng lượng trực tiếp', isDark: isDark),
            const SizedBox(height: 8),
            AppContainer(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
              child: PowerFlowDiagram(snapshot: data.flow),
            ),
            const SizedBox(height: 20),

            // ================= PHẦN 2 — BIỂU ĐỒ THỐNG KÊ =================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SectionHeader(title: 'Thống kê lịch sử', isDark: isDark),
                AppSegmentedButton<EnergyTimeRange>(
                  segments: const [
                    (value: EnergyTimeRange.today, label: 'Hôm nay', icon: null),
                    (value: EnergyTimeRange.week, label: 'Tuần này', icon: null),
                    (value: EnergyTimeRange.month, label: 'Tháng này', icon: null),
                  ],
                  selected: {_range},
                  onSelectionChanged: (v) => setState(() => _range = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Công suất tiêu thụ (W)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMain)),
                  const SizedBox(height: 12),
                  PowerLineChart(points: data.powerHistory),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Solar sinh ra vs Điện lưới tiêu thụ theo ngày', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMain)),
                  const SizedBox(height: 12),
                  SolarGridBarChart(stats: data.dailyStats),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ================= PHẦN 3 — BẢNG CHI TIẾT THIẾT BỊ =================
            _SectionHeader(title: 'Chi tiết theo thiết bị', isDark: isDark),
            const SizedBox(height: 8),
            AppContainer(
              child: DeviceEnergyTable(devices: data.devicesSortedByPower),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;
  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF0F172A)));
  }
}
