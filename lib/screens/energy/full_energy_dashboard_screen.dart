import 'package:flutter/material.dart';
import '../../models/energy_models.dart';
import '../../widgets/app_ui_wrappers.dart';
import 'power_flow_diagram.dart';
import 'energy_charts.dart';
import 'device_electrical_detail_list.dart';
import 'energy_sample_data.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [GIAI ĐOẠN 131 — MÀN HÌNH CHI TIẾT NĂNG LƯỢNG, 3 TAB] Điểm đến của nút "Mở rộng" trên thẻ
/// Điện năng thu gọn (xem `_buildEnergyWidget` trong dashboard_screen.dart). KHÁC
/// `EnergyDashboardScreen` (Giai đoạn 130, bố cục CUỘN DỌC 1 trang liên tục) — màn hình này dùng
/// `DefaultTabController` + `TabBar`/`TabBarView` 3 tab riêng biệt theo đúng yêu cầu: Sơ đồ mô
/// phỏng / Biểu đồ thống kê / Chi tiết thiết bị. TÁI DÙNG NGUYÊN các widget đã dựng ở Giai đoạn
/// 130 ([PowerFlowDiagram]/[PowerLineChart]/[SolarGridBarChart] — đã có animation CustomPaint +
/// fl_chart THẬT SỰ hoạt động, không còn là placeholder tĩnh) — chỉ thêm MỚI
/// [DeviceElectricalDetailList] cho Tab 3 (thông số Dòng/Áp/Cos φ chi tiết, khác bảng xếp hạng
/// rút gọn của Giai đoạn 130) và bộ lọc Dropdown 4 mức Ngày/Tuần/Tháng/Năm cho Tab 2.
///
/// [KIẾN TRÚC DATA] Cùng nguyên tắc "Server mù" với Giai đoạn 130 — xem cảnh báo đầy đủ ở
/// energy_sample_data.dart. [dataForRange] null (mặc định) -> dùng dữ liệu mẫu.
class FullEnergyDashboardScreen extends StatefulWidget {
  final EnergyDashboardData Function(EnergyTimeRange range)? dataForRange;

  const FullEnergyDashboardScreen({super.key, this.dataForRange});

  @override
  State<FullEnergyDashboardScreen> createState() => _FullEnergyDashboardScreenState();
}

class _FullEnergyDashboardScreenState extends State<FullEnergyDashboardScreen> {
  EnergyTimeRange _chartRange = EnergyTimeRange.today;

  EnergyDashboardData get _data => (widget.dataForRange ?? buildSampleEnergyData)(_chartRange);

  static const Map<EnergyTimeRange, String> _rangeLabel = {
    EnergyTimeRange.today: 'Ngày',
    EnergyTimeRange.week: 'Tuần',
    EnergyTimeRange.month: 'Tháng',
    EnergyTimeRange.year: 'Năm',
  };

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final EnergyDashboardData data = _data;

    return DefaultTabController(
      length: 3,
      child: AppScaffold(
        backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
        appBar: AppBar(
          title: const Text('Giám sát Điện năng'),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          foregroundColor: textMain,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: _tkGreen,
            labelColor: _tkGreen,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
            tabs: const [
              Tab(icon: Icon(Icons.hub_outlined, size: 20), text: 'Sơ đồ hệ thống'),
              Tab(icon: Icon(Icons.bar_chart_rounded, size: 20), text: 'Biểu đồ thống kê'),
              Tab(icon: Icon(Icons.list_alt_rounded, size: 20), text: 'Chi tiết thiết bị'),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildFlowTab(data, isDark, textMain),
              _buildChartsTab(data, isDark, textMain),
              _buildDeviceTab(data, isDark),
            ],
          ),
        ),
      ),
    );
  }

  // ================= TAB 1 — SƠ ĐỒ MÔ PHỎNG HỆ THỐNG =================
  Widget _buildFlowTab(EnergyDashboardData data, bool isDark, Color textMain) {
    final EnergyFlowSnapshot s = data.flow;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppContainer(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: PowerFlowDiagram(snapshot: s, height: 360),
        ),
        const SizedBox(height: 16),
        // [3 BIẾN TRẠNG THÁI CỐT LÕI — Grid Power / PV Power / Battery Flow] Đúng yêu cầu tường
        // minh "Thiết lập sẵn các biến trạng thái... để sau này ghép CustomPaint" — thực tế đã
        // ghép THẬT ở PowerFlowDiagram (Giai đoạn 130, không chỉ khai báo suông), dải tóm tắt này
        // chỉ hiển thị LẠI đúng 3 giá trị đó dạng số cho dễ đọc nhanh, không phải nguồn dữ liệu
        // riêng thứ 2 (đọc thẳng từ [s], không tự tính lại).
        AppContainer(
          child: Row(
            children: [
              _flowStatCell('LƯỚI ĐIỆN', '${s.gridKw.toStringAsFixed(2)} kW', s.isGridImporting ? Colors.green : (s.isGridExporting ? Colors.orange : Colors.grey), textMain),
              _flowStatCell('PV MẶT TRỜI', '${s.solarKw.toStringAsFixed(2)} kW', const Color(0xFFFFC107), textMain),
              _flowStatCell('ẮC QUY', '${s.batteryKw.toStringAsFixed(2)} kW', const Color(0xFF2196F3), textMain),
            ],
          ),
        ),
      ],
    );
  }

  Widget _flowStatCell(String label, String value, Color color, Color textMain) => Expanded(
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: color)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textMain)),
          ],
        ),
      );

  // ================= TAB 2 — BIỂU ĐỒ THỐNG KÊ =================
  Widget _buildChartsTab(EnergyDashboardData data, bool isDark, Color textMain) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Khung thời gian', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textMain)),
            _buildRangeDropdown(isDark, textMain),
          ],
        ),
        const SizedBox(height: 12),
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
              Text('Sản lượng Solar vs Điện lưới tiêu thụ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textMain)),
              const SizedBox(height: 12),
              SolarGridBarChart(stats: data.dailyStats),
            ],
          ),
        ),
      ],
    );
  }

  // [YÊU CẦU TƯỜNG MINH — Dropdown, KHÁC AppSegmentedButton pill đã dùng ở thẻ Dashboard thu gọn]
  // 4 lựa chọn Ngày/Tuần/Tháng/Năm — nhiều hơn 3 lựa chọn của thẻ thu gọn nên dùng Dropdown thay
  // vì hàng nút ngang (4 pill trên màn hẹp dễ vỡ dòng/chật).
  Widget _buildRangeDropdown(bool isDark, Color textMain) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<EnergyTimeRange>(
          value: _chartRange,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textMain),
          items: [for (final r in EnergyTimeRange.values) DropdownMenuItem(value: r, child: Text(_rangeLabel[r]!))],
          onChanged: (v) {
            if (v != null) setState(() => _chartRange = v);
          },
        ),
      ),
    );
  }

  // ================= TAB 3 — CHI TIẾT THIẾT BỊ & CÀI ĐẶT THÔNG SỐ =================
  Widget _buildDeviceTab(EnergyDashboardData data, bool isDark) {
    return DeviceElectricalDetailList(devices: data.devicesSortedByPower);
  }
}
