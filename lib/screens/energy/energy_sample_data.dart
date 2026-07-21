import 'dart:math' as math;
import '../../models/energy_models.dart';

/// [CHỈ PHỤC VỤ DỰNG KHUNG UI — KHÔNG PHẢI DỮ LIỆU THẬT] Backend HIỆN CHƯA có endpoint cấp
/// EnergyDashboardData thật (chưa tồn tại cảm biến dòng điện/công tơ nào bắn số liệu này lên
/// Server ở thời điểm viết file này) — hàm này CHỈ dùng làm giá trị mặc định để
/// `EnergyDashboardScreen` có gì đó để vẽ khi mở thử/preview UI, KHÔNG được coi là nguồn dữ liệu
/// sản xuất. Khi nối dây Backend thật, truyền `dataForRange:` riêng vào `EnergyDashboardScreen`
/// (đọc từ Provider/API thật) — tham số đó LUÔN ghi đè hàm này, không cần xoá file.
/// Dùng công thức lượng giác CỐ ĐỊNH (không `Random()`) để dữ liệu ỔN ĐỊNH giữa các lần rebuild —
/// tránh UI/animation giật do số liệu "nhảy" ngẫu nhiên mỗi khi setState.
EnergyDashboardData buildSampleEnergyData(EnergyTimeRange range) {
  final DateTime now = DateTime.now();

  final EnergyFlowSnapshot flow = EnergyFlowSnapshot(
    solarKw: 3.2,
    gridKw: 0.8,
    batteryKw: -1.1, // đang sạc
    loadKw: 2.9,
    batterySocPct: 68,
    gridVoltage: 220,
    gridCurrent: 3.6,
    solarVoltage: 380,
    solarCurrent: 8.4,
  );

  final int pointCount = switch (range) {
    EnergyTimeRange.today => 24,
    EnergyTimeRange.week => 7 * 4,
    EnergyTimeRange.month => 30,
    EnergyTimeRange.year => 12,
  };
  final Duration step = switch (range) {
    EnergyTimeRange.today => const Duration(hours: 1),
    EnergyTimeRange.week => const Duration(hours: 6),
    EnergyTimeRange.month => const Duration(days: 1),
    EnergyTimeRange.year => const Duration(days: 30),
  };
  final List<PowerHistoryPoint> power = [
    for (int i = 0; i < pointCount; i++)
      PowerHistoryPoint(
        time: now.subtract(step * (pointCount - i)),
        watts: 400 + 900 * (0.5 + 0.5 * math.sin(i / pointCount * math.pi * 2 - math.pi / 2)).abs(),
      ),
  ];

  final int dayCount = switch (range) {
    EnergyTimeRange.today || EnergyTimeRange.week => 7,
    EnergyTimeRange.month => 30,
    EnergyTimeRange.year => 12,
  };
  final List<DailyEnergyStat> daily = [
    for (int i = 0; i < dayCount; i++)
      DailyEnergyStat(
        day: range == EnergyTimeRange.year ? DateTime(now.year, now.month - (dayCount - 1 - i)) : now.subtract(Duration(days: dayCount - 1 - i)),
        solarKwh: 8 + 4 * (0.5 + 0.5 * math.sin(i * 0.6)).abs(),
        gridKwh: 5 + 3 * (0.5 + 0.5 * math.cos(i * 0.5)).abs(),
      ),
  ];

  const List<DeviceEnergyStat> devices = [
    DeviceEnergyStat(mac: 'AA:BB:CC:01', name: 'Điều hòa Phòng khách', currentWatts: 1450, todayKwh: 6.8, monthKwh: 142.5, voltage: 220, current: 6.6, cosPhi: 0.92),
    DeviceEnergyStat(mac: 'AA:BB:CC:02', name: 'Công tơ tổng', currentWatts: 2980, todayKwh: 18.2, monthKwh: 410.0, voltage: 219, current: 13.6, cosPhi: 0.88),
    DeviceEnergyStat(mac: 'AA:BB:CC:03', name: 'Bình nóng lạnh', currentWatts: 0, todayKwh: 2.1, monthKwh: 48.6, voltage: 220, current: 0, cosPhi: 0.99),
    DeviceEnergyStat(mac: 'AA:BB:CC:04', name: 'Công tắc Bếp (đo dòng)', currentWatts: 320, todayKwh: 1.4, monthKwh: 33.2, voltage: 221, current: 1.45, cosPhi: 0.95),
    DeviceEnergyStat(mac: 'AA:BB:CC:05', name: 'Máy giặt', currentWatts: 0, todayKwh: 0.6, monthKwh: 12.4),
  ];

  return EnergyDashboardData(flow: flow, powerHistory: power, dailyStats: daily, devices: devices);
}
