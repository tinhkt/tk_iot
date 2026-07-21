import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _fridgeBlue = Color(0xFF64B5F6);
const Color _tvPurple = Color(0xFF9575CD);
const Color _washerBlue = Color(0xFF4FC3F7);
const Color _vacuumGreen = Color(0xFF66BB6A);
const Color _kettleOrange = Color(0xFFFFA726);
const Color _heaterRed = Color(0xFFFF7043);
const Color _cooktopRed = Color(0xFFE53935);

/// Icon + trạng thái ĐƠN GIẢN dùng CHUNG cho các thiết bị chỉ có on/off, không cần animation
/// riêng (Tủ lạnh luôn chạy nền/không tắt hẳn, Tivi chỉ cần glow màn hình).
class _ApplianceIconAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;
  final IconData icon;
  final Color color;
  final String? statusOn;
  final String? statusOff;

  const _ApplianceIconAvatar({required this.state, required this.callbacks, required this.icon, required this.color, this.statusOn, this.statusOff});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: color,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? color.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.12)),
            child: Icon(icon, size: 32, color: on ? color : Colors.grey),
          ),
          if (statusOn != null) ...[
            const SizedBox(height: 8),
            Text(on ? statusOn! : (statusOff ?? ''), style: TextStyle(color: on ? color : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}

/// Máy giặt — lồng giặt (icon) xoay khi đang chạy.
class WashingMachineAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const WashingMachineAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<WashingMachineAvatar> createState() => _WashingMachineAvatarState();
}

class _WashingMachineAvatarState extends State<WashingMachineAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _applySpin();
  }

  @override
  void didUpdateWidget(covariant WashingMachineAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.isOn != widget.state.isOn || oldWidget.state.isOffline != widget.state.isOffline) _applySpin();
  }

  void _applySpin() {
    if (widget.state.isOn && !widget.state.isOffline) {
      _spin.repeat();
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
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _washerBlue,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? _washerBlue.withValues(alpha: 0.18) : Colors.grey.withValues(alpha: 0.12),
              border: Border.all(color: on ? _washerBlue : Colors.grey.withValues(alpha: 0.4), width: 3),
            ),
            child: RotationTransition(turns: _spin, child: Icon(Icons.local_laundry_service_rounded, size: 30, color: on ? _washerBlue : Colors.grey)),
          ),
          const SizedBox(height: 8),
          Text(on ? 'ĐANG GIẶT' : 'SẴN SÀNG', style: TextStyle(color: on ? _washerBlue : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Ấm đun nước siêu tốc — 3 hạt hơi nước bay lên khi đang đun.
class ElectricKettleAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const ElectricKettleAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<ElectricKettleAvatar> createState() => _ElectricKettleAvatarState();
}

class _ElectricKettleAvatarState extends State<ElectricKettleAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _steam;

  @override
  void initState() {
    super.initState();
    _steam = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _steam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.isOn && !widget.state.isOffline;
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _kettleOrange,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 26,
            child: on
                ? AnimatedBuilder(
                    animation: _steam,
                    builder: (context, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < 3; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Opacity(
                              opacity: (1 - ((_steam.value + i / 3) % 1.0)).clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: Offset(0, -14 * ((_steam.value + i / 3) % 1.0)),
                                child: const Icon(Icons.circle, size: 5, color: Colors.white70),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : null,
          ),
          Icon(Icons.local_cafe_rounded, size: 34, color: on ? _kettleOrange : Colors.grey),
          const SizedBox(height: 6),
          Text(on ? 'ĐANG ĐUN' : 'TẮT', style: TextStyle(color: on ? _kettleOrange : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Bếp từ — vòng nhiệt đỏ pulse quanh biểu tượng khi đang nấu, `state.value` = mức công suất (%).
class InductionCooktopAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const InductionCooktopAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    final double level = (state.value ?? 0).clamp(0, 100);
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _cooktopRed,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: on ? _cooktopRed : Colors.grey.withValues(alpha: 0.3), width: 4),
              boxShadow: on ? [BoxShadow(color: _cooktopRed.withValues(alpha: 0.6), blurRadius: 16, spreadRadius: 1)] : null,
            ),
            child: Icon(Icons.whatshot_rounded, size: 30, color: on ? _cooktopRed : Colors.grey),
          ),
          const SizedBox(height: 6),
          Text(on ? 'Mức ${level.round()}' : 'TẮT', style: TextStyle(color: on ? _cooktopRed : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// [Điện gia dụng | appliance] Tủ lạnh, Tivi, Máy giặt, Robot hút bụi, Ấm đun nước siêu tốc, Bình
/// nóng lạnh, Bếp từ — nhóm mới của Bước 5.
final List<DeviceAvatarDefinition> applianceAvatars = [
  DeviceAvatarDefinition(
    id: 'fridge',
    name: 'Tủ lạnh',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => _ApplianceIconAvatar(state: state, callbacks: callbacks, icon: Icons.kitchen_rounded, color: _fridgeBlue, statusOn: 'ĐANG LÀM LẠNH', statusOff: 'TẮT'),
  ),
  DeviceAvatarDefinition(
    id: 'tv',
    name: 'Tivi',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => _ApplianceIconAvatar(state: state, callbacks: callbacks, icon: Icons.tv_rounded, color: _tvPurple, statusOn: 'ĐANG PHÁT', statusOff: 'TẮT'),
  ),
  DeviceAvatarDefinition(
    id: 'washing_machine',
    name: 'Máy giặt',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => WashingMachineAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'robot_vacuum',
    name: 'Robot hút bụi',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => _ApplianceIconAvatar(state: state, callbacks: callbacks, icon: Icons.smart_toy_rounded, color: _vacuumGreen, statusOn: 'ĐANG DỌN', statusOff: 'VỀ SẠC'),
  ),
  DeviceAvatarDefinition(
    id: 'electric_kettle',
    name: 'Ấm đun nước siêu tốc',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => ElectricKettleAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'water_heater',
    name: 'Bình nóng lạnh',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => _ApplianceIconAvatar(state: state, callbacks: callbacks, icon: Icons.hot_tub_rounded, color: _heaterRed, statusOn: 'ĐANG ĐUN NƯỚC', statusOff: 'TẮT'),
  ),
  DeviceAvatarDefinition(
    id: 'induction_cooktop',
    name: 'Bếp từ',
    category: 'appliance',
    buildWidget: (context, state, callbacks) => InductionCooktopAvatar(state: state, callbacks: callbacks),
  ),
];
