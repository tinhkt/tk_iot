import 'package:flutter/material.dart';
import '../../models/energy_models.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [PHẦN 3 — BẢNG THỐNG KÊ CHI TIẾT THIẾT BỊ] Nhận [devices] đã sort sẵn theo công suất giảm dần
/// (xem `EnergyDashboardData.devicesSortedByPower`) — widget này KHÔNG tự sort, chỉ vẽ đúng thứ
/// tự được truyền vào (tách rời trách nhiệm data khỏi UI, cùng triết lý mọi widget khác trong
/// app). Dùng `ListView.builder` bên trong `shrinkWrap` (KHÔNG dùng `DataTable`) — DataTable ép
/// bố cục dạng bảng cứng-cột, không tự xuống dòng đẹp trên màn hình hẹp; ListView cho phép mỗi
/// hàng tự bố cục responsive (tên dài tự ellipsis, 3 số liệu co giãn đều).
class DeviceEnergyTable extends StatelessWidget {
  final List<DeviceEnergyStat> devices;

  const DeviceEnergyTable({super.key, required this.devices});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color subColor = isDark ? Colors.white54 : Colors.black54;

    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.electric_meter_outlined, size: 32, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 8),
            Text('Chưa có thiết bị nào hỗ trợ đo năng lượng', style: TextStyle(fontSize: 12, color: subColor)),
          ]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(children: [
            Expanded(flex: 3, child: Text('THIẾT BỊ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: subColor))),
            Expanded(flex: 2, child: Text('HIỆN TẠI', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: subColor))),
            Expanded(flex: 2, child: Text('HÔM NAY', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: subColor))),
            Expanded(flex: 2, child: Text('THÁNG NÀY', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4, color: subColor))),
          ]),
        ),
        Divider(height: 1, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08)),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: devices.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
          itemBuilder: (context, i) => _DeviceEnergyRow(rank: i + 1, stat: devices[i], isDark: isDark),
        ),
      ],
    );
  }
}

class _DeviceEnergyRow extends StatelessWidget {
  final int rank;
  final DeviceEnergyStat stat;
  final bool isDark;
  const _DeviceEnergyRow({required this.rank, required this.stat, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Color textMain = isDark ? Colors.white : Colors.black87;
    final Color textSub = isDark ? Colors.white54 : Colors.black54;
    // [TOP 3 — NGỐN ĐIỆN NHẤT] Huy hiệu số thứ hạng chỉ tô nổi bật 3 hàng đầu (đã sort giảm dần
    // từ nơi gọi) — trực quan hoá đúng yêu cầu "sort theo thiết bị ngốn nhiều điện nhất lên đầu".
    final Color rankColor = rank <= 3 ? _tkGreen : textSub;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              SizedBox(
                width: 20,
                child: Text('$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: rankColor)),
              ),
              Expanded(
                child: Text(stat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textMain)),
              ),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Text('${stat.currentWatts.toStringAsFixed(0)} W', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: stat.currentWatts > 0 ? _tkGreen : textSub)),
          ),
          Expanded(
            flex: 2,
            child: Text('${stat.todayKwh.toStringAsFixed(2)} kWh', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: textSub)),
          ),
          Expanded(
            flex: 2,
            child: Text('${stat.monthKwh.toStringAsFixed(1)} kWh', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: textSub)),
          ),
        ],
      ),
    );
  }
}
