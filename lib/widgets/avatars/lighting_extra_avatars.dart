import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _nightAmber = Color(0xFFFFB74D);
const Color _warmWhite = Color(0xFFFFF3C4);
const Color _coolWhite = Color(0xFFB3E5FC);

/// Đèn tròn phát sáng dùng CHUNG cho Đèn ngủ/Downlight — bấm để bật/tắt, glow radial khi ON,
/// xám mờ khi OFF. Icon/màu khác nhau tạo bản sắc riêng cho từng loại đèn.
class _GlowLampAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;
  final IconData icon;
  final Color color;
  final double iconSize;

  const _GlowLampAvatar({required this.state, required this.callbacks, required this.icon, required this.color, this.iconSize = 38});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: color,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Center(
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: on ? RadialGradient(colors: [color.withValues(alpha: 0.85), color.withValues(alpha: 0.05)]) : null,
            color: on ? null : Colors.grey.withValues(alpha: 0.12),
          ),
          child: Icon(icon, size: iconSize, color: on ? Colors.white : Colors.grey),
        ),
      ),
    );
  }
}

/// Đèn chùm — 3 bóng nhỏ (giữa to hơn) cùng sáng/tắt đồng bộ theo isOn.
class ChandelierAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const ChandelierAvatar({super.key, required this.state, required this.callbacks});

  Widget _bulb(bool on, bool center) => Container(
        margin: EdgeInsets.only(top: center ? 0 : 10),
        width: center ? 26 : 18,
        height: center ? 26 : 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: on ? _warmWhite : Colors.grey.withValues(alpha: 0.25),
          boxShadow: on ? [BoxShadow(color: _warmWhite.withValues(alpha: 0.85), blurRadius: 10, spreadRadius: 1)] : null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _warmWhite,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [_bulb(on, false), const SizedBox(width: 8), _bulb(on, true), const SizedBox(width: 8), _bulb(on, false)],
        ),
      ),
    );
  }
}

/// Đèn ống tuýp — thanh dài bo tròn phát sáng ngang (mô phỏng đèn huỳnh quang/LED tuýp).
class TubeLightAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const TubeLightAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool on = state.isOn && !state.isOffline;
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _coolWhite,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Center(
        child: Container(
          width: 106,
          height: 22,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: on ? _coolWhite : Colors.grey.withValues(alpha: 0.2),
            boxShadow: on ? [BoxShadow(color: _coolWhite.withValues(alpha: 0.8), blurRadius: 18, spreadRadius: 1)] : null,
          ),
        ),
      ),
    );
  }
}

/// [Chiếu sáng | lighting] Đèn ngủ, Đèn chùm, Đèn Downlight, Đèn ống tuýp — bổ sung Bước 5.
final List<DeviceAvatarDefinition> lightingExtraAvatars = [
  DeviceAvatarDefinition(
    id: 'light_night',
    name: 'Đèn ngủ',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => _GlowLampAvatar(state: state, callbacks: callbacks, icon: Icons.bedtime_rounded, color: _nightAmber, iconSize: 32),
  ),
  DeviceAvatarDefinition(
    id: 'light_chandelier',
    name: 'Đèn chùm',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => ChandelierAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'light_downlight',
    name: 'Đèn Downlight',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => _GlowLampAvatar(state: state, callbacks: callbacks, icon: Icons.wb_incandescent_rounded, color: _coolWhite, iconSize: 36),
  ),
  DeviceAvatarDefinition(
    id: 'light_tube',
    name: 'Đèn ống tuýp',
    category: 'lighting',
    buildWidget: (context, state, callbacks) => TubeLightAvatar(state: state, callbacks: callbacks),
  ),
];
