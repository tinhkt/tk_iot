import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _gateAmber = Color(0xFFFFB300);
const Color _lockGreen = Color(0xFF00A651);
const Color _lockRed = Color(0xFFE53935);

/// Cổng Barie bãi xe — thanh chắn xoay quanh 1 trục (bản lề trái), NẰM NGANG khi ĐÓNG (isOn =
/// false), DỰNG ĐỨNG ~80° khi MỞ (isOn = true). Sọc đỏ-trắng mô phỏng đúng thanh chắn thật.
class BarrierGateAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const BarrierGateAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool open = state.isOn;
    final Color color = state.isOffline ? Colors.grey : _gateAmber;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _gateAmber,
      onTap: () => callbacks.onToggle(!state.isOn),
      // [FIX GIAI ĐOẠN 129 — OVERFLOW 22px] AvatarShell cấp height CỐ ĐỊNH cho Column con (150 mặc
      // định, hoặc NHỎ HƠN khi widget này bị ép vào 1 ô lưới 1x1 hẹp hơn ở Dashboard thật) — tổng
      // chiều cao "cứng" trước đây (70 + 6 + ~20 chữ) có thể vượt quá không gian thật cấp cho
      // Column, ném RenderFlex overflow. Column vẫn nhận height BOUNDED (không unbounded — AvatarShell
      // luôn ép width/height cụ thể, KHÁC hẳn trường hợp _TwinCardShell từng crash ở Giai đoạn 121)
      // nên Expanded ở đây AN TOÀN, không có rủi ro assertion "unbounded". Expanded bọc FittedBox
      // (không phải bọc thẳng SizedBox 90x70) để co giãn TỈ LỆ toàn bộ đồ họa thanh chắn theo không
      // gian thật cấp — giữ nguyên mọi phép tính Positioned nội bộ (vốn neo theo đúng canvas gốc
      // 90x70), tránh vỡ hình khi bị bóp nhỏ.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 90,
                height: 70,
                child: Stack(
                  alignment: Alignment.bottomLeft,
                  children: [
                    // Cột trụ giữ bản lề.
                    Positioned(left: 4, bottom: 0, child: Container(width: 8, height: 60, decoration: BoxDecoration(color: color.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)))),
                    // Thanh chắn — xoay quanh góc dưới-trái (bản lề), 0° = nằm ngang (đóng), -80° = gần dựng đứng (mở).
                    Positioned(
                      left: 8,
                      bottom: 56,
                      child: AnimatedRotation(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutBack,
                        turns: open ? -0.22 : 0,
                        alignment: Alignment.centerLeft,
                        child: CustomPaint(size: const Size(74, 12), painter: _BarrierStripePainter(color: color)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
              child: Text(
                state.isOffline ? 'MẤT KẾT NỐI' : (open ? 'ĐANG MỞ' : 'ĐÃ ĐÓNG'),
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarrierStripePainter extends CustomPainter {
  final Color color;
  _BarrierStripePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(4));
    canvas.drawRRect(bar, Paint()..color = Colors.white);
    const double stripeW = 12;
    int i = 0;
    for (double x = 0; x < size.width; x += stripeW) {
      if (i.isOdd) {
        canvas.save();
        canvas.clipRRect(bar);
        canvas.drawRect(Rect.fromLTWH(x, 0, stripeW, size.height), Paint()..color = color);
        canvas.restore();
      }
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _BarrierStripePainter oldDelegate) => oldDelegate.color != color;
}

/// Cổng trượt tự động — 1 tấm cổng trượt NGANG sang phải khi MỞ (isOn = true), thu hết chiều
/// rộng khi ĐÓNG. Khác Cửa cuốn (kéo LÊN theo %) — cổng trượt di chuyển NGANG dứt khoát 2 trạng
/// thái (không có khái niệm % mở dở, đúng đặc tính cổng bãi xe/nhà xưởng thật).
class SlidingGateAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const SlidingGateAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool open = state.isOn;
    final Color color = state.isOffline ? Colors.grey : _gateAmber;

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: _gateAmber,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 92,
            height: 56,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(color: Colors.black.withValues(alpha: 0.15)),
                  // Trụ cổng cố định bên phải (điểm cổng thu về khi mở).
                  Positioned(right: 0, top: 0, bottom: 0, width: 6, child: Container(color: color.withValues(alpha: 0.6))),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeInOut,
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: open ? 14 : 86,
                    child: CustomPaint(painter: _GateMeshPainter(color: color)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
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

class _GateMeshPainter extends CustomPainter {
  final Color color;
  _GateMeshPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = color.withValues(alpha: 0.55));
    final Paint bar = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (double x = 4; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), bar);
    }
  }

  @override
  bool shouldRepaint(covariant _GateMeshPainter oldDelegate) => oldDelegate.color != color;
}

/// Khóa cửa thông minh (vân tay/mật mã) — cùng quy ước isOn=mở/false=khóa với Cửa từ, nhưng dùng
/// icon vân tay làm điểm nhấn riêng (khác hẳn thẻ từ RFID của AccessControlAvatar).
class SmartLockAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const SmartLockAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool unlocked = state.isOn;
    final Color color = state.isOffline ? Colors.grey : (unlocked ? _lockGreen : _lockRed);

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: color,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_person_rounded, size: 46, color: color),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(
              state.isOffline ? 'MẤT KẾT NỐI' : (unlocked ? 'ĐANG MỞ' : 'ĐÃ KHÓA'),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cửa xoay tripod (Turnstile) — 3 thanh chắn hình chữ Y nhìn từ trên xuống, xoay 120° mỗi lần
/// có người quẹt thẻ hợp lệ. `isOn = true` = đang MỞ KHÓA cho lượt qua kế tiếp (LED xanh, giống
/// hành vi cổng soát vé thật); tự động về false sau đó ở tầng logic Backend/BMS thật, avatar chỉ
/// vẽ đúng trạng thái tại thời điểm nhận được.
class TurnstileAvatar extends StatelessWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const TurnstileAvatar({super.key, required this.state, required this.callbacks});

  @override
  Widget build(BuildContext context) {
    final bool unlocked = state.isOn;
    final Color color = state.isOffline ? Colors.grey : (unlocked ? _lockGreen : _lockRed);

    return AvatarShell(
      isOn: state.isOn,
      isOffline: state.isOffline,
      glowColor: color,
      onTap: () => callbacks.onToggle(!state.isOn),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(size: const Size(56, 56), painter: _TripodPainter(color: color)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(
              state.isOffline ? 'MẤT KẾT NỐI' : (unlocked ? 'CHO QUA' : 'CHẶN'),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripodPainter extends CustomPainter {
  final Color color;
  _TripodPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.width / 2;
    final Paint arm = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 3; i++) {
      final double angle = (i * 120 - 90) * math.pi / 180;
      final Offset end = center + Offset(r * 0.9 * math.cos(angle), r * 0.9 * math.sin(angle));
      canvas.drawLine(center, end, arm);
    }
    canvas.drawCircle(center, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TripodPainter oldDelegate) => oldDelegate.color != color;
}

/// [Kiểm soát Vào ra & Thang máy | access_control] Cổng Barie, Cổng trượt, Khóa thông minh, Cửa
/// xoay tripod — bổ sung nhóm BMS chuyên nghiệp (elevator_panel đã có sẵn ở elevator_avatars.dart,
/// access_control_door — cửa từ cơ bản — đã có sẵn ở access_control_avatars.dart).
final List<DeviceAvatarDefinition> accessControlExtraAvatars = [
  DeviceAvatarDefinition(
    id: 'barrier_gate',
    name: 'Cổng Barie bãi xe',
    category: 'access_control',
    buildWidget: (context, state, callbacks) => BarrierGateAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'sliding_gate',
    name: 'Cổng trượt tự động',
    category: 'access_control',
    buildWidget: (context, state, callbacks) => SlidingGateAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'smart_lock',
    name: 'Khóa cửa thông minh',
    category: 'access_control',
    buildWidget: (context, state, callbacks) => SmartLockAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'turnstile',
    name: 'Cửa xoay Tripod',
    category: 'access_control',
    buildWidget: (context, state, callbacks) => TurnstileAvatar(state: state, callbacks: callbacks),
  ),
];
