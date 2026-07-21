import 'package:flutter/material.dart';
import '../../models/energy_models.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [TAB 3 — CHI TIẾT THIẾT BỊ & CÀI ĐẶT THÔNG SỐ] Khác [DeviceEnergyTable] (bảng RÚT GỌN xếp
/// hạng theo công suất, dùng cho Phần 3 gốc/thẻ tổng quan) — widget này hiển thị ĐẦY ĐỦ 4 thông
/// số điện của TỪNG thiết bị (Dòng/Áp/Công suất/Cos phi) dạng danh sách chi tiết, phục vụ mục
/// đích "xem thông số kỹ thuật" thay vì "so sánh ai tốn điện nhất". [onTapDevice] để hở sẵn chỗ
/// nối tới màn hình Cài đặt thông số riêng của từng thiết bị sau này (null = chưa nối, chỉ hiển
/// thị, không chặn nếu chưa có màn hình đích).
class DeviceElectricalDetailList extends StatelessWidget {
  final List<DeviceEnergyStat> devices;
  final ValueChanged<DeviceEnergyStat>? onTapDevice;

  const DeviceElectricalDetailList({super.key, required this.devices, this.onTapDevice});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.tune_rounded, size: 32, color: isDark ? Colors.white24 : Colors.black26),
            const SizedBox(height: 8),
            Text('Chưa có thiết bị nào hỗ trợ đo thông số điện', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
          ]),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _DeviceElectricalCard(stat: devices[i], isDark: isDark, onTap: onTapDevice == null ? null : () => onTapDevice!(devices[i])),
    );
  }
}

class _DeviceElectricalCard extends StatelessWidget {
  final DeviceEnergyStat stat;
  final bool isDark;
  final VoidCallback? onTap;
  const _DeviceElectricalCard({required this.stat, required this.isDark, this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final bool active = stat.currentWatts > 0.01;

    return Material(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.electric_meter_rounded, size: 18, color: active ? _tkGreen : textSub),
                const SizedBox(width: 8),
                Expanded(child: Text(stat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: textMain))),
                if (onTap != null) Icon(Icons.chevron_right_rounded, size: 20, color: textSub),
              ]),
              const SizedBox(height: 10),
              Row(
                children: [
                  _paramCell('CÔNG SUẤT', '${stat.currentWatts.toStringAsFixed(0)} W', textMain, textSub),
                  _paramCell('ĐIỆN ÁP', stat.voltage != null ? '${stat.voltage!.toStringAsFixed(0)} V' : '--', textMain, textSub),
                  _paramCell('DÒNG ĐIỆN', stat.current != null ? '${stat.current!.toStringAsFixed(2)} A' : '--', textMain, textSub),
                  _paramCell('COS φ', stat.cosPhi != null ? stat.cosPhi!.toStringAsFixed(2) : '--', textMain, textSub),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paramCell(String label, String value, Color textMain, Color textSub) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: textSub)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: textMain))),
          ],
        ),
      );
}
