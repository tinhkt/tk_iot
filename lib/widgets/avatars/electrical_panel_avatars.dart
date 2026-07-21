import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'industrial_shell.dart';

const Color _voltColor = Color(0xFF42A5F5);
const Color _ampColor = Color(0xFFFFB300);

/// Hệ thống giám sát năng lượng 3 pha — 2 đồng hồ kim RIÊNG BIỆT: Điện áp (V) và Dòng điện (A).
/// Quy ước: `state.metric` = Dòng điện (A, đúng bản chất CHỈ-ĐỌC sẵn có của field này).
/// [DÙNG TẠM `value` LÀM Ô SỐ CHỈ-ĐỌC THỨ 2] Thiết bị này thuần GIÁM SÁT — không có gì để người
/// dùng "chỉnh" (không ai kéo thanh trượt để đổi điện áp lưới!). Hợp đồng DeviceAvatarState chỉ
/// có ĐÚNG MỘT trục chỉ-đọc (`metric`); ở đây tái dùng `value` (vốn dành cho trục CHỈNH ĐƯỢC) làm
/// ô số-2 hiển thị Điện áp, nhưng KHÔNG BAO GIỜ gọi onChange cho nó — cố tình ghi rõ đánh đổi này
/// thay vì âm thầm lạm dụng field.
class ThreePhaseMonitorAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const ThreePhaseMonitorAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final double volt = state.value ?? 0;
    final double amp = state.metric ?? 0;
    final bool danger = amp >= 80; // ngưỡng quá dòng mẫu

    return RuggedShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: danger ? industrialRed : industrialAmber,
      width: 316,
      height: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GaugeDial(value: volt, min: 0, max: 500, dangerFrom: 460, unit: 'V', color: _voltColor, size: 92),
              GaugeDial(value: amp, min: 0, max: 100, dangerFrom: 80, unit: 'A', color: _ampColor, size: 92),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state.isOffline ? 'MẤT KẾT NỐI' : (danger ? 'CẢNH BÁO QUÁ DÒNG' : '3 PHA — BÌNH THƯỜNG'),
            style: TextStyle(color: state.isOffline ? Colors.grey : (danger ? industrialRed : Colors.white70), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// Relay/Contactor công suất lớn — đóng/mở tải nặng. Quy ước: `state.metric` = dòng tải đang
/// chạy qua (A, CHỈ-ĐỌC). Có E-STOP ép MỞ (ngắt) ngay lập tức.
class HeavyDutyRelayAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const HeavyDutyRelayAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool closed = state.isOn; // ĐÓNG = đang cấp điện cho tải
    final Color color = state.isOffline ? Colors.grey : (closed ? industrialAmber : Colors.white54);
    final double load = state.metric ?? 0;

    return RuggedShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: industrialAmber,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => callbacks.onToggle(!state.isOn),
            child: Container(
              width: 60,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: closed ? industrialAmber.withValues(alpha: 0.25) : Colors.black26,
                border: Border.all(color: color, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(closed ? Icons.horizontal_rule_rounded : Icons.power_off_rounded, color: color, size: 22),
            ),
          ),
          const SizedBox(height: 6),
          Text('${load.toStringAsFixed(1)} A', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            state.isOffline ? 'MẤT KẾT NỐI' : (closed ? 'ĐÓNG (CẤP ĐIỆN)' : 'MỞ (NGẮT)'),
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.3),
          ),
          const SizedBox(height: 6),
          EStopButton(onPressed: () => callbacks.onToggle(false), size: 28),
        ],
      ),
    );
  }
}

/// [Tủ điện & Tải nặng | electrical_panel]
final List<DeviceAvatarDefinition> electricalPanelAvatars = [
  DeviceAvatarDefinition(
    id: 'panel_3phase_monitor',
    name: 'Giám sát năng lượng 3 pha',
    category: 'electrical_panel',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => ThreePhaseMonitorAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'panel_heavy_relay',
    name: 'Relay / Contactor công suất lớn',
    category: 'electrical_panel',
    buildWidget: (context, state, callbacks) => HeavyDutyRelayAvatar(state: state, callbacks: callbacks),
  ),
];
