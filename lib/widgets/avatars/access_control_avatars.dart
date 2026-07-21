import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _lockRed = Color(0xFFE53935);
const Color _unlockGreen = Color(0xFF00A651);

/// Cửa từ / Kiểm soát ra vào (Access Control) — quy ước `isOn = true` nghĩa là ĐANG MỞ
/// (unlocked), `false` = ĐÃ KHÓA (locked). Không dùng speed/value/metric. Cho phép chạm để
/// khoá/mở từ xa — đây là thao tác PHỔ BIẾN và mong đợi ở một BMS thật (khác với thang máy/cảm
/// biến an toàn ở các file khác trong Bước 3, nơi một cú chạm bất cẩn có thể gây hậu quả nghiêm
/// trọng hơn nhiều nên KHÔNG wiring tương tự — xem ghi chú tại từng file).
class AccessControlAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const AccessControlAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool unlocked = state.isOn;
    final Color statusColor = state.isOffline ? Colors.grey : (unlocked ? _unlockGreen : _lockRed);

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: statusColor,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              // Biểu tượng thẻ từ/RFID làm nền mờ phía sau icon khoá — gợi hình "quẹt thẻ".
              Icon(Icons.badge_outlined, size: 46, color: statusColor.withValues(alpha: 0.35)),
              Icon(unlocked ? Icons.lock_open_rounded : Icons.lock_rounded, size: 30, color: statusColor),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(
              state.isOffline ? 'MẤT KẾT NỐI' : (unlocked ? 'ĐANG MỞ' : 'ĐÃ KHÓA'),
              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// [Cửa từ / Access Control | access_control]
final List<DeviceAvatarDefinition> accessControlAvatars = [
  DeviceAvatarDefinition(
    id: 'access_control_door',
    name: 'Cửa từ / Kiểm soát ra vào',
    category: 'access_control',
    buildWidget: (context, state, callbacks) => AccessControlAvatar(state: state, callbacks: callbacks),
  ),
];
