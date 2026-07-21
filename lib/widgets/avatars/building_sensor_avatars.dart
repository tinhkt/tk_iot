import 'package:flutter/material.dart';
import '../../models/device_avatar_definition.dart';
import 'avatar_shell.dart';

const Color _presenceIdle = Color(0xFF29B6F6);
const Color _presenceDetected = Color(0xFFFFA726);
const Color _alarmOk = Color(0xFF00A651);
const Color _alarmTriggered = Color(0xFFE53935);

/// Cảm biến hiện diện (PIR) — mô phỏng vùng quét sóng bằng 3 vòng tròn lan toả liên tục (LUÔN
/// chạy, vì PIR luôn đang quét). Quy ước: `isOn = true` = ĐANG PHÁT HIỆN người/vật chuyển động.
/// [KHÔNG wiring onTap -> onToggle] Đây là cảm biến CHỈ-ĐỌC — người dùng không "bật/tắt" việc
/// phát hiện chuyển động bằng một cú chạm; callbacks vẫn nhận theo đúng chữ ký buildWidget nhưng
/// không dùng ở đây.
class PresenceSensorAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const PresenceSensorAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<PresenceSensorAvatar> createState() => _PresenceSensorAvatarState();
}

class _PresenceSensorAvatarState extends State<PresenceSensorAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool detected = widget.state.isOn && !widget.state.isOffline;
    final Color color = widget.state.isOffline ? Colors.grey : (detected ? _presenceDetected : _presenceIdle);

    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: color,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) => CustomPaint(size: const Size(88, 88), painter: _RadarSweepPainter(t: _sweep.value, color: color, strongPulse: detected)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.state.isOffline ? 'MẤT KẾT NỐI' : (detected ? 'CÓ NGƯỜI' : 'KHÔNG PHÁT HIỆN'),
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

class _RadarSweepPainter extends CustomPainter {
  final double t; // 0..1, một chu kỳ lặp
  final Color color;
  final bool strongPulse;
  _RadarSweepPainter({required this.t, required this.color, required this.strongPulse});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double maxR = size.width / 2;
    for (int i = 0; i < 3; i++) {
      final double phase = (t + i / 3) % 1.0;
      final double r = maxR * phase;
      final double alpha = (1 - phase) * (strongPulse ? 0.55 : 0.3);
      canvas.drawCircle(center, r, Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    canvas.drawCircle(center, maxR * 0.16, Paint()..color = color);
    // Dấu cảm biến (tam giác nhỏ) đè giữa tâm, gợi hình icon PIR thật.
    final Path mark = Path()
      ..moveTo(center.dx, center.dy - 6)
      ..lineTo(center.dx - 5, center.dy + 4)
      ..lineTo(center.dx + 5, center.dy + 4)
      ..close();
    canvas.drawPath(mark, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) => true; // t đổi liên tục mỗi frame khi đang animate
}

/// Cảm biến khói/Báo cháy — chớp đỏ liên tục khi có cảnh báo, xanh lá tĩnh khi bình thường, xám
/// khi mất kết nối (3 trạng thái RÕ RÀNG, không lẫn giữa "an toàn" và "không rõ tình trạng").
/// [KHÔNG wiring onTap -> onToggle] Thiết bị AN TOÀN CHÁY NỔ, CHỈ-ĐỌC — một cú chạm đơn giản
/// TUYỆT ĐỐI không được ngầm hiểu là "tắt/xác nhận báo cháy"; quy trình xử lý cảnh báo thật (nếu
/// có) phải đi qua luồng riêng của BMS, không gộp vào avatar hiển thị này.
class FireAlarmSensorAvatar extends StatefulWidget {
  final DeviceAvatarState state;
  final DeviceAvatarCallbacks callbacks;

  const FireAlarmSensorAvatar({super.key, required this.state, required this.callbacks});

  @override
  State<FireAlarmSensorAvatar> createState() => _FireAlarmSensorAvatarState();
}

class _FireAlarmSensorAvatarState extends State<FireAlarmSensorAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 450))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool alarm = widget.state.isOn && !widget.state.isOffline;
    final Color color = widget.state.isOffline ? Colors.grey : (alarm ? _alarmTriggered : _alarmOk);

    return AvatarShell(
      isOn: widget.state.isOn,
      isOffline: widget.state.isOffline,
      glowColor: color,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _blink,
            builder: (context, _) {
              final double flash = alarm ? _blink.value : 1.0;
              return Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: alarm ? _alarmTriggered.withValues(alpha: 0.25 + flash * 0.5) : color.withValues(alpha: 0.15),
                  boxShadow: alarm ? [BoxShadow(color: _alarmTriggered.withValues(alpha: flash * 0.8), blurRadius: 22, spreadRadius: 2)] : null,
                ),
                child: Icon(alarm ? Icons.local_fire_department_rounded : Icons.smoke_free_rounded, color: alarm ? Colors.white : color, size: 28),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(
              widget.state.isOffline ? 'MẤT KẾT NỐI' : (alarm ? 'BÁO CHÁY!' : 'BÌNH THƯỜNG'),
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// [Cảm biến tòa nhà | building_sensor] PIR hiện diện, Khói/Báo cháy.
final List<DeviceAvatarDefinition> buildingSensorAvatars = [
  DeviceAvatarDefinition(
    id: 'sensor_pir',
    name: 'Cảm biến hiện diện (PIR)',
    category: 'building_sensor',
    buildWidget: (context, state, callbacks) => PresenceSensorAvatar(state: state, callbacks: callbacks),
  ),
  DeviceAvatarDefinition(
    id: 'sensor_fire_alarm',
    name: 'Cảm biến khói / Báo cháy',
    category: 'building_sensor',
    buildWidget: (context, state, callbacks) => FireAlarmSensorAvatar(state: state, callbacks: callbacks),
  ),
];
