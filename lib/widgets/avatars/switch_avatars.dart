import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _switchGreen = Color(0xFF00A651);

/// [1 AVATAR = 1 KÊNH] Hợp đồng DeviceAvatarState/Callbacks (Bước 1) chỉ có MỘT trục isOn/
/// onToggle — mỗi avatar Công tắc cơ N-nút đại diện ĐÚNG MỘT kênh relay (giống cách app hiện có
/// vẽ 1 SmartSwitchCard/kênh trong dashboard_screen.dart). Số N chỉ là KIỂU DÁNG mặt công tắc
/// (mặt 2/3/4 nút thật ngoài đời) — mọi rocker trên MỘT avatar cùng phản ánh và cùng điều khiển
/// đúng 1 isOn/onToggle đó, KHÔNG phải N công tắc độc lập trên 1 avatar.
class _MechSwitchFace extends StatelessWidget {
  final int gangCount;
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const _MechSwitchFace({required this.gangCount, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _switchGreen,
      onTap: () => callbacks.onToggle(!state.isOn),
      // [FIX RIGHT OVERFLOW — mặt 4 nút] 4 x _Rocker(24px) + 3 x SizedBox(8px) = 120px nội dung,
      // cộng padding 14px hai bên của AvatarShell = 148px — chỉ CÒN ĐÚNG ~2px dư so với 150px mặc
      // định của AvatarShell trong điều kiện LÝ TƯỞNG. Trên lưới thật, StaggeredGridTile cấp
      // constraint TIGHT theo stride tính từ bề ngang màn hình (không phải luôn đúng 150px) —
      // bất kỳ lúc nào stride < 148px là tràn phải. FittedBox(scaleDown) khiến Row tự CO LẠI vừa
      // đúng không gian được cấp (không bao giờ phóng to quá 1.0), triệt tiêu hoàn toàn rủi ro
      // tràn viền ở MỌI mặt 1-4 nút, tại MỌI kích thước ô (lưới thật lẫn preview popup chọn Avatar).
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < gangCount; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _Rocker(isOn: state.isOn),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Rocker extends StatelessWidget {
  final bool isOn;
  const _Rocker({required this.isOn});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 24,
      height: 56,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isOn ? _switchGreen : (isDark ? Colors.white24 : Colors.black12), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12), blurRadius: 4, offset: const Offset(1, 2))],
      ),
      alignment: isOn ? Alignment.topCenter : Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: double.infinity,
        height: 22,
        decoration: BoxDecoration(
          color: isOn ? _switchGreen : (isDark ? Colors.white24 : Colors.black26),
          borderRadius: BorderRadius.circular(5),
        ),
      ),
    );
  }
}

/// Công tắc cảm ứng mặt kính — bấm 1 lần bật/tắt, viền LED phát sáng khi bật (glow pulse đã có
/// sẵn ở AvatarShell, ở đây chỉ cần vẽ mặt kính tròn phản chiếu).
class TouchSwitchAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const TouchSwitchAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [FIX ICON NHỎ] LayoutBuilder BỌC NGOÀI CÙNG (trước AvatarShell) để đọc ĐÚNG kích thước
    // khung cha THẬT (ô lưới dashboard thật SỰ được cấp, hoặc preview popup chọn Avatar) thay vì
    // hard-code 92/34px cố định — khung cha lớn hơn thiết kế gốc thì mặt kính + icon TỰ phóng to
    // theo, không còn "bé tí" khi avatar được vẽ ở kích thước khác 150px mặc định. Khi đo trong
    // popup (dưới FittedBox của picker — constraints lúc đó KHÔNG XÁC ĐỊNH/vô hạn) rơi về mốc mặc
    // định 150 làm cơ sở, rồi FittedBox bên ngoài tự co cả khối lại vừa ô preview.
    return LayoutBuilder(builder: (context, constraints) {
      final double parentSize = constraints.maxWidth.isFinite ? constraints.maxWidth : 150;
      final double circleSize = (parentSize * 0.6).clamp(60.0, 130.0);
      final double iconSize = circleSize * 0.5; // icon chiếm nửa đường kính mặt kính — rõ, cân đối

      return AvatarShell(
        isOn: state.isOn,
        isOffline: state.isOffline,
        glowColor: _switchGreen,
        onTap: () => callbacks.onToggle(!state.isOn),
        child: Center(
          child: Container(
            width: circleSize,
            height: circleSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: state.isOn
                    ? [_switchGreen.withValues(alpha: 0.35), _switchGreen.withValues(alpha: 0.08)]
                    : [Colors.white.withValues(alpha: isDark ? 0.08 : 0.55), Colors.white.withValues(alpha: 0.02)],
              ),
              border: Border.all(color: state.isOn ? _switchGreen : (isDark ? Colors.white24 : Colors.black12), width: 2),
              boxShadow: state.isOn ? [BoxShadow(color: _switchGreen.withValues(alpha: 0.6), blurRadius: 18, spreadRadius: 1)] : null,
            ),
            child: Icon(
              Icons.power_settings_new_rounded,
              color: state.isOn ? _switchGreen : (isDark ? Colors.white54 : Colors.black45),
              size: iconSize,
            ),
          ),
        ),
      );
    });
  }
}

/// [Bước 5] Kiểu mặt công tắc THỨ HAI — nút bấm tròn với BIỂU TƯỢNG NÚT NGUỒN ở giữa. Quy ước
/// hiển thị: OFF -> toàn nút mờ (opacity thấp); ON -> CHỈ riêng biểu tượng nút nguồn đó phát
/// sáng (glow), không đổi màu nền toàn thẻ như kiểu rocker — đúng yêu cầu tách biệt "cái gì sáng".
class _PowerButtonSwitchFace extends StatelessWidget {
  final int gangCount;
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const _PowerButtonSwitchFace({required this.gangCount, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    // [FIX ICON NHỎ] LayoutBuilder đọc kích thước khung cha THẬT (giống TouchSwitchAvatar) —
    // nút tròn + icon nguồn bên trong tự phóng theo, không còn cố định 38px/20px trông bé xíu
    // khi avatar được vẽ lớn hơn 150px mặc định (vd ô lưới rộng trên màn hình to).
    return LayoutBuilder(builder: (context, constraints) {
      final double parentSize = constraints.maxWidth.isFinite ? constraints.maxWidth : 150;
      final double buttonSize = (parentSize * 0.34).clamp(30.0, 64.0);
      final double iconSize = buttonSize * 0.6; // icon chiếm phần lớn nút — rõ, nổi bật

      return AvatarShell(
        isOn: state.isOn,
        isOffline: state.isOffline,
        glowColor: _switchGreen,
        onTap: () => callbacks.onToggle(!state.isOn),
        // [FIX RIGHT OVERFLOW — cùng họ với _MechSwitchFace] Wrap tự nó không "tràn" (chỉ xuống
        // dòng), nhưng 4 nút + khoảng cách vẫn có thể KHÔNG vừa 1 hàng trong ô hẹp — trông như
        // "vỡ" (rớt dòng dưới) dù không phải lỗi kỹ thuật. Bọc FittedBox để LUÔN hiển thị đúng 1
        // hàng, tự co theo không gian thật — nhất quán với mặt cơ rocker.
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [for (int i = 0; i < gangCount; i++) _PowerGlowButton(isOn: state.isOn, size: buttonSize, iconSize: iconSize)],
            ),
          ),
        ),
      );
    });
  }
}

class _PowerGlowButton extends StatelessWidget {
  final bool isOn;
  final double size;
  final double iconSize;
  const _PowerGlowButton({required this.isOn, required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isOn ? 1.0 : 0.35,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
          border: Border.all(color: isOn ? _switchGreen : (isDark ? Colors.white24 : Colors.black26)),
          boxShadow: isOn ? [BoxShadow(color: _switchGreen.withValues(alpha: 0.85), blurRadius: 14, spreadRadius: 1)] : null,
        ),
        child: Icon(Icons.power_settings_new_rounded, size: iconSize, color: isOn ? _switchGreen : (isDark ? Colors.white38 : Colors.black38)),
      ),
    );
  }
}

/// [Công tắc | switch] 1/2/3/4-gang cơ (rocker) + cảm ứng mặt kính + 1/2/3/4-gang nút nguồn glow (Bước 5).
final List<DeviceAvatarDefinition> switchAvatars = [
  for (int n = 1; n <= 4; n++)
    DeviceAvatarDefinition(
      id: 'switch_mech_$n',
      name: 'Công tắc cơ $n nút',
      category: 'switch',
      buildWidget: (context, state, callbacks) => _MechSwitchFace(gangCount: n, state: state, callbacks: callbacks),
    ),
  DeviceAvatarDefinition(
    id: 'switch_touch',
    name: 'Công tắc cảm ứng mặt kính',
    category: 'switch',
    buildWidget: (context, state, callbacks) => TouchSwitchAvatar(state: state, callbacks: callbacks),
  ),
  for (int n = 1; n <= 4; n++)
    DeviceAvatarDefinition(
      id: 'switch_power_$n',
      name: 'Công tắc nút nguồn $n nút',
      category: 'switch',
      buildWidget: (context, state, callbacks) => _PowerButtonSwitchFace(gangCount: n, state: state, callbacks: callbacks),
    ),
];
