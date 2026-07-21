/// [MÀN HÌNH GIÁM SÁT ĐIỆN NĂNG — BƯỚC 1: DATA CONTRACT] Toàn bộ model ở file này THUẦN DỮ LIỆU
/// (không tự gọi API/MQTT) — đúng nguyên tắc "Server mù" xuyên suốt app: màn hình Energy Dashboard
/// (energy_dashboard_screen.dart) chỉ VẼ theo đúng những gì được TRUYỀN VÀO qua constructor, không
/// tự bịa số. HIỆN TẠI (giai đoạn khung UI) chưa có endpoint Backend thật cấp các số liệu này —
/// khi nối dây thật, chỉ cần 1 tầng chuyển đổi JSON -> các class này, KHÔNG cần sửa bất kỳ widget
/// vẽ nào bên dưới.
library;

/// Ảnh chụp tức thời luồng năng lượng — nguồn cấp cho [PowerFlowDiagram] (Phần 1). Quy ước dấu:
/// `solarKw` LUÔN >= 0 (PV chỉ sinh, không tiêu). `gridKw` > 0 = đang MUA điện lưới (nhập), < 0 =
/// đang BÁN ngược lên lưới (xuất, hệ hoà lưới có export). `batteryKw` > 0 = đang XẢ (cấp cho tải/
/// lưới), < 0 = đang SẠC. `loadKw` LUÔN >= 0 (tải luôn tiêu thụ). Mọi field V/A là CHỈ-ĐỌC, null
/// nếu cảm biến chưa gửi (KHÔNG suy diễn/nội suy — hiển thị "--" thay vì đoán).
class EnergyFlowSnapshot {
  final double solarKw;
  final double gridKw;
  final double batteryKw;
  final double loadKw;
  final double? batterySocPct; // 0-100, null nếu không có BMS ắc quy báo về
  final double? gridVoltage;
  final double? gridCurrent;
  final double? solarVoltage;
  final double? solarCurrent;

  const EnergyFlowSnapshot({
    this.solarKw = 0,
    this.gridKw = 0,
    this.batteryKw = 0,
    this.loadKw = 0,
    this.batterySocPct,
    this.gridVoltage,
    this.gridCurrent,
    this.solarVoltage,
    this.solarCurrent,
  });

  bool get hasSolarFlow => solarKw.abs() > 0.01;
  bool get isGridImporting => gridKw > 0.01;
  bool get isGridExporting => gridKw < -0.01;
  bool get isBatteryCharging => batteryKw < -0.01;
  bool get isBatteryDischarging => batteryKw > 0.01;
}

/// 1 điểm trong biểu đồ đường Công suất tiêu thụ theo thời gian (Phần 2, LineChart).
class PowerHistoryPoint {
  final DateTime time;
  final double watts;
  const PowerHistoryPoint({required this.time, required this.watts});
}

/// 1 cột trong biểu đồ so sánh Solar sinh ra vs Điện lưới tiêu thụ theo ngày (Phần 2, BarChart).
class DailyEnergyStat {
  final DateTime day;
  final double solarKwh;
  final double gridKwh;
  const DailyEnergyStat({required this.day, required this.solarKwh, required this.gridKwh});
}

/// 1 dòng trong Bảng thống kê chi tiết thiết bị (Phần 3). [voltage]/[current]/[cosPhi] — thêm ở
/// Giai đoạn 131 cho Tab "Chi tiết Thiết bị & Cài đặt thông số" của FullEnergyDashboardScreen —
/// CHỈ-ĐỌC, null nếu thiết bị/cảm biến không báo về giá trị đó (KHÔNG suy diễn — vd công tắc
/// thường không đo dòng thì [current]/[cosPhi] mãi mãi null, hiển thị "--" thay vì bịa).
class DeviceEnergyStat {
  final String mac;
  final String name;
  final double currentWatts;
  final double todayKwh;
  final double monthKwh;
  final double? voltage; // V
  final double? current; // A
  final double? cosPhi; // hệ số công suất, 0..1
  const DeviceEnergyStat({
    required this.mac,
    required this.name,
    required this.currentWatts,
    required this.todayKwh,
    required this.monthKwh,
    this.voltage,
    this.current,
    this.cosPhi,
  });
}

/// Khung thời gian chọn ở Phần 2 — "Hôm nay/Tuần này/Tháng này" (thẻ Dashboard thu gọn, 3 lựa
/// chọn) + [year] bổ sung Giai đoạn 131 cho bộ lọc Dropdown ở Tab "Biểu đồ Thống kê" của
/// FullEnergyDashboardScreen (4 lựa chọn: Ngày/Tuần/Tháng/Năm).
enum EnergyTimeRange { today, week, month, year }

/// Gói TOÀN BỘ dữ liệu 1 màn hình Energy Dashboard cần — tách khỏi State của widget để nơi gọi
/// (vd 1 Provider/Stream thật sau này) chỉ cần dựng ĐÚNG 1 object này mỗi lần có dữ liệu mới.
class EnergyDashboardData {
  final EnergyFlowSnapshot flow;
  final List<PowerHistoryPoint> powerHistory; // theo đúng EnergyTimeRange đang chọn, nơi gọi tự lọc
  final List<DailyEnergyStat> dailyStats;
  final List<DeviceEnergyStat> devices;

  const EnergyDashboardData({
    this.flow = const EnergyFlowSnapshot(),
    this.powerHistory = const [],
    this.dailyStats = const [],
    this.devices = const [],
  });

  /// Thiết bị theo thứ tự công suất hiện tại GIẢM DẦN — đúng yêu cầu "ngốn nhiều điện nhất lên
  /// đầu". Tính lại mỗi lần đọc (danh sách gốc không đổi) — số thiết bị BMS thực tế nhỏ (vài chục
  /// tối đa), sort mỗi build không đáng kể chi phí.
  List<DeviceEnergyStat> get devicesSortedByPower =>
      [...devices]..sort((a, b) => b.currentWatts.compareTo(a.currentWatts));
}
