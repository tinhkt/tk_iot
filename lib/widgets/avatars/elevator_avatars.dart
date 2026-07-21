import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _elevatorAmber = Color(0xFFFFB300);

// Danh sách tầng CỐ ĐỊNH làm mẫu (B1, Trệt, 2-5). Hợp đồng buildWidget(context, state, callbacks)
// từ Bước 1 không mang theo cấu hình riêng-từng-tòa-nhà (vd "toà này có 12 tầng") — mở rộng để
// nhận cấu hình per-installation là thay đổi CHỮ KÝ buildWidget, vượt phạm vi Bước 3. Avatar này
// vẽ đúng 6 nút làm blueprint mẫu; nối với tòa nhà thật cần Dashboard tự thay danh sách tầng.
const List<int> _floors = [-1, 0, 2, 3, 4, 5]; // 0 = Trệt/Ground

String _floorLabel(int f) => f < 0 ? 'B${-f}' : (f == 0 ? 'T' : '$f');

/// Hệ thống thang máy — bảng gọi/điều khiển. Quy ước trục dữ liệu: `state.speed` = tầng HIỆN TẠI
/// (số nguyên), `state.value` = tầng ĐANG GỌI/ĐÍCH (null = không có lệnh gọi đang chờ). Chiều
/// mũi tên lên/xuống được TÍNH RA từ so sánh 2 trục này (không cần thêm field riêng).
/// [KHÔNG wiring onTap toàn khung -> onToggle] Khác Cửa từ (Access Control) — "isOn" ở đây là
/// trạng thái ĐANG HOẠT ĐỘNG/NGOÀI HOẠT ĐỘNG của cả hệ thang máy: một cú chạm nhầm vào vùng nền
/// panel không nên vô tình đưa thang máy ra khỏi hoạt động. Chỉ các nút gọi tầng mới có hành vi
/// tương tác — đúng tinh thần "nghiêm túc" yêu cầu ở Bước 3.
class ElevatorPanelAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const ElevatorPanelAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool inService = state.isOn && !state.isOffline;
    final int current = state.speed ?? 0;
    final double? target = state.value;
    final bool goingUp = target != null && target > current;
    final bool goingDown = target != null && target < current;
    final Color color = state.isOffline ? Colors.grey : (inService ? _elevatorAmber : Colors.grey);

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _elevatorAmber,
      width: 316,
      height: 150,
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_floorLabel(current), style: TextStyle(color: color, fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_upward_rounded, size: 18, color: goingUp ? _elevatorAmber : color.withValues(alpha: 0.25)),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_downward_rounded, size: 18, color: goingDown ? _elevatorAmber : color.withValues(alpha: 0.25)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.isOffline
                      ? 'MẤT KẾT NỐI'
                      : !inService
                          ? 'NGOÀI HOẠT ĐỘNG'
                          : goingUp
                              ? 'ĐANG LÊN'
                              : goingDown
                                  ? 'ĐANG XUỐNG'
                                  : 'ĐANG DỪNG',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final f in _floors)
                  _FloorButton(
                    label: _floorLabel(f),
                    called: target == f.toDouble(),
                    enabled: inService,
                    color: _elevatorAmber,
                    onTap: () => callbacks.onChange('value', f.toDouble()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorButton extends StatelessWidget {
  final String label;
  final bool called;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  const _FloorButton({required this.label, required this.called, required this.enabled, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: called ? color : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          border: Border.all(color: called ? color : (isDark ? Colors.white24 : Colors.black12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: called ? Colors.white : (enabled ? (isDark ? Colors.white70 : Colors.black87) : Colors.grey),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// [Hệ thống thang máy | elevator]
final List<DeviceAvatarDefinition> elevatorAvatars = [
  DeviceAvatarDefinition(
    id: 'elevator_panel',
    name: 'Bảng gọi thang máy',
    category: 'elevator',
    gridSpanX: 2,
    buildWidget: (context, state, callbacks) => ElevatorPanelAvatar(state: state, callbacks: callbacks),
  ),
];
