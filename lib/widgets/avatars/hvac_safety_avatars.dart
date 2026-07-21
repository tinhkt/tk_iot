import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _centralAcBlue = Color(0xFF29B6F6);
const Color _exhaustSteel = Color(0xFF90A4AE);
const Color _valveTeal = Color(0xFF00BFA5);

/// Điều hòa trung tâm / Cassette âm trần — khác [HvacThermostatAvatar] (bảng Thermostat núm xoay
/// đầy đủ, dùng cho phòng riêng): đây là avatar ĐƠN GIẢN cho dàn lạnh Cassette gắn trần khu vực
/// lớn — 4 cánh gió xòe đều mô phỏng đúng hình dáng miệng gió Cassette 4 hướng khi đang chạy.
class CentralAcAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const CentralAcAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    final double temp = (state.value ?? 25).clamp(16, 30);
    final Color color = state.isOffline ? Colors.grey : _centralAcBlue;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _centralAcBlue,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.ac_unit_rounded, size: 44, color: color.withValues(alpha: on ? 1 : 0.5)),
              if (on)
                Positioned(
                  bottom: -2,
                  child: Icon(Icons.expand_more_rounded, size: 16, color: color),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${temp.round()}°C', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          Text('CASSETTE ÂM TRẦN', style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
        ],
      ),
    );
  }
}

/// Quạt thông gió/hút công nghiệp — cánh quạt xoay liên tục khi ON, khung lưới bảo vệ tĩnh phía
/// sau mô phỏng đúng quạt hút công nghiệp gắn tường/trần.
class ExhaustFanAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const ExhaustFanAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<ExhaustFanAvatar> createState() => _ExhaustFanAvatarState();
}

class _ExhaustFanAvatarState extends State<ExhaustFanAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    if (widget.state.isOn && !widget.state.isOffline) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant ExhaustFanAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool on = widget.state.isOn && !widget.state.isOffline;
    if (on) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.isOn && !widget.state.isOffline;
    final Color color = widget.state.isOffline ? Colors.grey : _exhaustSteel;
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _exhaustSteel,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.circle_outlined, size: 66, color: color.withValues(alpha: 0.4)),
            RotationTransition(
              turns: _spin,
              child: Icon(Icons.mode_fan_off_rounded, size: 42, color: on ? color : color.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Van nước tổng tự động — biểu tượng van xoay 90° giữa trạng thái MỞ (dòng chảy song song ống,
/// isOn=true) và ĐÓNG (chắn ngang dòng chảy). Quy ước giống Cửa từ: isOn=true = MỞ.
class WaterValveAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const WaterValveAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool open = state.isOn;
    final Color color = state.isOffline ? Colors.grey : _valveTeal;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _valveTeal,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Ống dẫn nằm ngang cố định.
              Container(width: 60, height: 12, decoration: BoxDecoration(color: color.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(4))),
              Icon(Icons.plumbing_rounded, size: 26, color: color.withValues(alpha: 0.7)),
              // Tay van — xoay 90° khi MỞ (song song ống) vs ĐÓNG (vuông góc chắn ống).
              AnimatedRotation(
                duration: const Duration(milliseconds: 350),
                turns: open ? 0 : 0.25,
                child: Container(width: 42, height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(
              state.isOffline ? 'MẤT KẾT NỐI' : (open ? 'ĐANG MỞ' : 'ĐÃ ĐÓNG'),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// [Môi trường & An toàn | hvac] Điều hòa trung tâm Cassette, Quạt thông gió/hút công nghiệp, Van
/// nước tổng tự động — bổ sung nhóm BMS chuyên nghiệp. (Cảm biến khói/Báo cháy ĐÃ CÓ SẴN với ĐÚNG
/// vai trò "smoke_detector" ở building_sensor_avatars.dart — id `sensor_fire_alarm` — không tạo
/// bản sao trùng lặp UI; nó hiển thị chung nhóm "Môi trường & An toàn" ở picker qua gộp category.)
final List<DeviceAvatarDefinition> hvacSafetyAvatars = [
  DeviceAvatarDefinition(
    id: 'air_conditioner_central',
    name: 'Điều hòa trung tâm (Cassette)',
    category: 'hvac',
    buildWidget: (context, state, callbacks) => CentralAcAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'exhaust_fan',
    name: 'Quạt thông gió / hút công nghiệp',
    category: 'hvac',
    buildWidget: (context, state, callbacks) => ExhaustFanAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'water_valve',
    name: 'Van nước tổng tự động',
    category: 'hvac',
    buildWidget: (context, state, callbacks) => WaterValveAvatar(state: state, callbacks: callbacks),
  ),
];
