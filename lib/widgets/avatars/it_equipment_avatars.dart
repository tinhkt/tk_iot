import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _pcBlue = Color(0xFF42A5F5);
const Color _serverGreen = Color(0xFF00A651);

/// Máy tính PC — icon màn hình phát sáng khi bật, không có animation liên tục (đúng bản chất
/// PC — không nhấp nháy vô cớ, chỉ đổi trạng thái rõ ràng khi bật/tắt).
class PcAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const PcAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _pcBlue,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.desktop_windows_rounded, size: 46, color: on ? _pcBlue : Colors.grey),
          const SizedBox(height: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: on ? _pcBlue : Colors.grey.withValues(alpha: 0.4), boxShadow: on ? [BoxShadow(color: _pcBlue.withValues(alpha: 0.7), blurRadius: 6)] : null),
          ),
        ],
      ),
    );
  }
}

/// Server — 3 chấm LED nhấp nháy LỆCH PHA khi đang chạy (mô phỏng đèn báo hoạt động ổ cứng thật).
class ServerAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const ServerAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<ServerAvatar> createState() => _ServerAvatarState();
}

class _ServerAvatarState extends State<ServerAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = widget.state.isOn && !widget.state.isOffline;
    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: _serverGreen,
      onTap: () => widget.callbacks.onToggle(!widget.state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_rounded, size: 44, color: on ? _serverGreen : Colors.grey),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _blink,
            builder: (context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  AvatarDot(active: on && ((_blink.value * 3).floor() % 3) == i, color: _serverGreen),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [IT & Bơm chuyên dụng | it_equipment] Máy tính PC, Server — nhóm mới của Bước 5.
final List<DeviceAvatarDefinition> itEquipmentAvatars = [
  DeviceAvatarDefinition(
    id: 'pc_desktop',
    name: 'Máy tính PC',
    category: 'it_equipment',
    buildWidget: (context, state, callbacks) => PcAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'server_rack',
    name: 'Server',
    category: 'it_equipment',
    buildWidget: (context, state, callbacks) => ServerAvatar(state: state, callbacks: callbacks),
  ),
];
