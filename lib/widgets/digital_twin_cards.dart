import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../providers/device_provider.dart';
import '../services/api_service.dart';
import '../localization/app_translations.dart';
import 'device_menu_helper.dart';
import 'app_ui_wrappers.dart';

// ============================================================================
// 🪞 DIGITAL TWIN — THẺ THIẾT BỊ MÔ PHỎNG TRỰC QUAN (Đợt 23)
// ============================================================================
// 3 thẻ "siêu cấp" (Cửa cuốn / Bơm nước / Đèn Chiết áp) + GenericDeviceCard (lưới an toàn
// cho category chưa có thẻ riêng, vd "ac"/"fridge"). Cùng ĐỨNG NGOÀI dashboard_screen.dart
// (file đó đã 4000+ dòng) — dashboard_screen.dart CHỈ dựng danh sách dữ liệu rồi truyền vào
// đây, tránh vòng import: mọi callback (rename/settings/xóa...) đều nhận qua tham số thay vì
// tự gọi ngược showDeviceSettingsPopup() (định nghĩa trong dashboard_screen.dart).
//
// Ảnh động: Lottie.asset() trỏ vào assets/animations/*.json — CHƯA có file thật (xem
// assets/animations/README.md) nên errorBuilder luôn rơi về hình vẽ CustomPainter/Icon tự
// dựng bên dưới, card vẫn đẹp + đúng chức năng ngay hôm nay; thả file .json đúng tên vào là
// tự nâng cấp lên ảnh động thật, KHÔNG cần sửa code.
// ============================================================================

const Color _tkGreen = Color(0xFF00A651);

// ----------------------------------------------------------------------------
// KHUNG THẺ DÙNG CHUNG — tiêu đề + trạng thái + bọc AppCard (border/shadow/Glass tự động)
// ----------------------------------------------------------------------------
class _TwinCardShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData headerIcon;
  final Color accentColor;
  final bool offline;
  final Widget child;
  final VoidCallback onLongPress;

  const _TwinCardShell({
    required this.title,
    required this.subtitle,
    required this.headerIcon,
    required this.accentColor,
    required this.offline,
    required this.child,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = offline ? Colors.grey : (isDark ? Colors.white : const Color(0xFF0F172A));
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color effectiveAccent = offline ? Colors.grey : accentColor;

    return SizedBox(
      width: 220,
      child: AppCard(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(16),
        onLongPress: onLongPress,
        child: Opacity(
          opacity: offline ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: effectiveAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(headerIcon, color: effectiveAccent, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(subtitle, style: TextStyle(color: textSub, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bộ callback tiêu chuẩn dùng chung cho cả 3 thẻ Digital Twin — 1:1 với ({...}) _stdCallbacks
/// trả về ở dashboard_screen.dart (record type Dart 3), tránh phải định nghĩa 8 tham số rời rạc.
typedef TwinCardCallbacks = ({
  VoidCallback rename,
  VoidCallback delete,
  VoidCallback assignRoom,
  VoidCallback? assignHome,
  VoidCallback timer,
  VoidCallback history,
  VoidCallback automation,
  VoidCallback share,
});

void _openMenu({
  required BuildContext context,
  required String mac,
  required String name,
  required String subtitle,
  required IconData headerIcon,
  required VoidCallback onOpenSettings,
  required TwinCardCallbacks cb,
  required bool isHidden,
  required ValueChanged<bool> onToggleHide,
}) {
  final t = AppTranslations.of(context, listen: false);
  DeviceMenuHelper.showGenericDeviceMenu(
    context: context,
    mac: mac,
    currentName: name,
    subtitle: subtitle,
    headerIcon: headerIcon,
    onOpenSettings: onOpenSettings,
    onDeviceTimer: cb.timer,
    onDeviceHistory: cb.history,
    onDeviceAutomation: cb.automation,
    onDeviceShare: cb.share,
    onRename: cb.rename,
    onAssignHome: cb.assignHome,
    onAssignRoom: cb.assignRoom,
    onDelete: cb.delete,
    isHidden: isHidden,
    hideLabel: isHidden ? t.text('show_device_again') : t.text('hide_from_dashboard'),
    hideSubtitle: t.text('hide_from_dashboard_desc'),
    onToggleHide: onToggleHide,
  );
}

// ============================================================================
// 🚪 NHIỆM VỤ 1 — SmartRollingDoorCard (Cửa cuốn)
// ============================================================================
// Quy ước kênh (khớp firmware SW_rolling_doors.ino): channel 1 = UP, 2 = DOWN, 3 = STOP.
// Vị trí % là ƯỚC LƯỢNG PHẦN MỀM THUẦN TÚY (không cảm biến hành trình thật) — mỗi lần kéo
// Slider hoặc giữ nút Lên/Xuống, App tự tính số mili-giây theo "Thời gian hành trình" đã hiệu
// chỉnh rồi CỘNG DỒN vào vị trí đang nhớ, lưu bền qua ApiService.setDeviceSetting để đồng bộ
// giữa các phiên/nhiều người dùng cùng nhà. Sai số tích lũy theo thời gian là ĐẶC ĐIỂM CỐ HỮU
// của mọi cửa cuốn không cảm biến — người dùng có thể kéo Slider về 0%/100% để "reset" thủ công.
class SmartRollingDoorCard extends StatefulWidget {
  final String mac;
  final String upEndpoint;
  final String downEndpoint;
  final String stopEndpoint;
  final String? backendName;
  final bool isOffline;
  final int travelTimeSec; // "Thời gian hành trình" đã hiệu chỉnh (giây); 0 = chưa hiệu chỉnh
  final int initialPositionPct; // 0-100, từ device_settings.door_position_pct
  final DeviceProvider provider;
  final bool isHidden;
  final ValueChanged<bool> onToggleHide;
  final VoidCallback onOpenSettings;
  final TwinCardCallbacks callbacks;

  const SmartRollingDoorCard({
    super.key,
    required this.mac,
    required this.upEndpoint,
    required this.downEndpoint,
    required this.stopEndpoint,
    this.backendName,
    this.isOffline = false,
    this.travelTimeSec = 0,
    this.initialPositionPct = 0,
    required this.provider,
    this.isHidden = false,
    required this.onToggleHide,
    required this.onOpenSettings,
    required this.callbacks,
  });

  @override
  State<SmartRollingDoorCard> createState() => _SmartRollingDoorCardState();
}

class _SmartRollingDoorCardState extends State<SmartRollingDoorCard> with SingleTickerProviderStateMixin {
  // Fallback hợp lý khi user CHƯA hiệu chỉnh "Thời gian hành trình" (0) — đủ dùng để Slider/nút
  // giữ vẫn hoạt động ngay từ lần đầu, không bắt buộc phải vào Cài đặt trước khi dùng được.
  static const int _defaultTravelSec = 15;

  late double _positionPct; // 0 = đóng kín, 100 = mở hoàn toàn
  bool _dragging = false;
  double? _dragValue;

  // Giữ nút Lên/Xuống: bấm-giữ = chạy liên tục, thả tay = STOP (vị trí đã được Timer nội suy
  // cập nhật sống trong lúc giữ — xem _liveTimer bên dưới, không còn tính bù một lần lúc thả tay).
  String? _holdingDirection; // 'up' | 'down' | null

  // [DEAD RECKONING — NỘI SUY VỊ TRÍ THEO THỜI GIAN] Phần cứng KHÔNG có cảm biến hành trình thật
  // nên đây là nguồn sự thật DUY NHẤT cho vị trí % hiển thị khi cửa đang chạy. Timer này CHỈ vẽ
  // lại UI (_positionPct) mượt theo thời gian thực trong đúng khoảng thời lượng lệnh MQTT ĐÃ GỬI
  // (pulseDoorRelay gọi trước đó với duration_ms tường minh — firmware tự đóng relay đúng lúc,
  // xem handleDoorLogic() bên SW_rolling_doors.ino) — TUYỆT ĐỐI không tự gửi thêm lệnh MQTT nào
  // ở đây, tránh spam Broker mỗi 16ms.
  Timer? _liveTimer;
  double _liveStartPct = 0;
  double _liveTargetPct = 0;
  DateTime? _liveStartedAt;
  int _liveDurationMs = 0;

  late final AnimationController _motionController; // shimmer khi cửa đang chuyển động

  int get _travelSec => widget.travelTimeSec > 0 ? widget.travelTimeSec : _defaultTravelSec;
  // Cửa "đang chuyển động" khi giữ nút HOẶC khi Timer nội suy còn chạy (kể cả do kéo Slider) —
  // để shimmer/animation phản ánh đúng CẢ 2 nguồn kích hoạt, không riêng nút giữ như trước.
  bool get _isMoving => _holdingDirection != null || _liveTimer != null;

  @override
  void initState() {
    super.initState();
    _positionPct = widget.initialPositionPct.clamp(0, 100).toDouble();
    _motionController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void didUpdateWidget(covariant SmartRollingDoorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Vị trí đổi từ NGUỒN NGOÀI (vd mở App trên máy khác vừa lưu lại) -> chỉ đồng bộ khi
    // KHÔNG đang thao tác dở dang, tránh giật ngược tay người dùng đang kéo/giữ.
    if (!_dragging && _holdingDirection == null && _liveTimer == null && oldWidget.initialPositionPct != widget.initialPositionPct) {
      _positionPct = widget.initialPositionPct.clamp(0, 100).toDouble();
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    _liveTimer?.cancel(); // BẮT BUỘC — tránh Timer sống ngoài đời widget gây memory leak/setState-on-unmounted
    super.dispose();
  }

  void _persistPosition(double pct) {
    ApiService().setDeviceSetting(widget.mac, 'door_position_pct', pct.round().toString());
  }

  // Chạy Timer.periodic 16ms/lần (~60fps) kéo _positionPct tuyến tính từ vị trí hiện tại về
  // [target] trong đúng [durationMs] — khớp CHÍNH XÁC thời lượng lệnh MQTT vừa gửi, để Slider +
  // hình mô phỏng "đi" đồng bộ với những gì phần cứng đang thật sự làm.
  void _startLiveInterpolation(double target, int durationMs) {
    _liveTimer?.cancel();
    _liveStartPct = _positionPct.clamp(0.0, 100.0);
    _liveTargetPct = target.clamp(0.0, 100.0);
    _liveStartedAt = DateTime.now();
    _liveDurationMs = durationMs <= 0 ? 1 : durationMs;

    _liveTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) { timer.cancel(); return; }
      final int elapsedMs = DateTime.now().difference(_liveStartedAt!).inMilliseconds;
      final double t = (elapsedMs / _liveDurationMs).clamp(0.0, 1.0);
      // [AN TOÀN TUYỆT ĐỐI — chống tràn số] Về lý thuyết công thức nội suy tuyến tính giữa 2 đầu
      // ĐÃ kẹp (start/target) không thể vượt biên, nhưng vẫn bọc .clamp() tường minh ở chính nơi
      // gán — không bao giờ để lọt giá trị ngoài [0,100] ra tới Slider dù có sửa code sau này.
      setState(() => _positionPct = (_liveStartPct + (_liveTargetPct - _liveStartPct) * t).clamp(0.0, 100.0));
      if (t >= 1.0) {
        timer.cancel();
        _liveTimer = null;
        // Nếu đang giữ nút mà chạy hết quãng đường lý thuyết (chạm 0%/100%) thì tự dọn trạng
        // thái nút — firmware đã tự đóng relay đúng lúc, không cần tay người dùng thả mới sạch.
        if (_holdingDirection != null) {
          setState(() { _holdingDirection = null; });
        }
        _persistPosition(_positionPct);
      }
    });
  }

  // ---- SLIDER: kéo tới % đích -> tính đúng số ms cần thiết -> phát 1 xung có thời lượng ----
  void _onSliderChangeEnd(double target) {
    final double delta = target - _positionPct;
    setState(() { _dragging = false; _dragValue = null; });
    if (delta.abs() < 1 || widget.isOffline) { setState(() => _positionPct = target.clamp(0.0, 100.0)); return; }
    final int durationMs = ((delta.abs() / 100) * _travelSec * 1000).round().clamp(100, 30000);
    final String endpoint = delta > 0 ? widget.upEndpoint : widget.downEndpoint;
    widget.provider.pulseDoorRelay(widget.mac, endpoint, durationMs); // 1 lệnh MQTT DUY NHẤT
    _startLiveInterpolation(target, durationMs); // UI mượt song song — KHÔNG gửi thêm lệnh nào
  }

  // ---- NÚT LÊN/XUỐNG: bấm-giữ chạy liên tục (kiểu remote thật), thả tay = STOP ----
  void _startHold(String direction) {
    if (widget.isOffline || _holdingDirection != null) return;
    setState(() { _holdingDirection = direction; });
    final String endpoint = direction == 'up' ? widget.upEndpoint : widget.downEndpoint;
    // Chạy "dài" (trọn thời gian hành trình còn lại theo hướng đó) — thả tay sẽ STOP sớm hơn,
    // xem _endHold(). Kẹp trong biên hợp lệ của firmware (100-30000ms).
    final double maxRemaining = direction == 'up' ? (100 - _positionPct) : _positionPct;
    final int durationMs = ((maxRemaining / 100) * _travelSec * 1000).round().clamp(100, 30000);
    widget.provider.pulseDoorRelay(widget.mac, endpoint, durationMs); // 1 lệnh MQTT DUY NHẤT
    final double target = direction == 'up' ? 100.0 : 0.0;
    _startLiveInterpolation(target, durationMs); // cộng/trừ dần liên tục — _endHold() cắt sớm nếu thả tay trước
  }

  void _endHold() {
    if (_holdingDirection == null) return;
    widget.provider.pulseDoorRelay(widget.mac, widget.stopEndpoint, 0); // STOP ngay — dùng xung mặc định
    _liveTimer?.cancel(); // hủy Timer NGAY LẬP TỨC — giữ nguyên _positionPct hiện tại, không nội suy tiếp
    _liveTimer = null;
    setState(() { _holdingDirection = null; });
    _persistPosition(_positionPct);
  }

  void _tapStop() {
    if (widget.isOffline) return;
    widget.provider.pulseDoorRelay(widget.mac, widget.stopEndpoint, 0);
    _liveTimer?.cancel(); // bấm Dừng khi đang kéo Slider dở dang cũng phải cắt nội suy ngay
    _liveTimer = null;
  }

  String _displayName(AppTranslations t) => widget.backendName?.isNotEmpty == true ? widget.backendName! : t.text('rolling_door_default_name');

  Widget _buildHoldButton({required IconData icon, required String direction, required bool isDark}) {
    final bool active = _holdingDirection == direction;
    return GestureDetector(
      // [CÁCH LY CẢM ỨNG] behavior: opaque bắt buộc — không có nó, giữ tay lên nút Lên/Xuống có
      // thể để lọt sự kiện lên GestureDetector.onLongPress của _TwinCardShell bên ngoài (mở Menu
      // Popup ngoài ý muốn giữa lúc đang giữ nút). opaque ép GestureDetector này "nuốt" trọn mọi
      // sự kiện chạm trong vùng của nó, Card cha coi như không hề có cú chạm nào xảy ra.
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _startHold(direction),
      onTapUp: (_) => _endHold(),
      onTapCancel: _endHold,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _tkGreen : (isDark ? Colors.white10 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: active ? Colors.white : (isDark ? Colors.white70 : Colors.black54)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final t = AppTranslations.of(context);
    final double shownPct = _dragging ? (_dragValue ?? _positionPct) : _positionPct;

    return _TwinCardShell(
      title: _displayName(t),
      subtitle: widget.isOffline ? t.text('offline') : '${shownPct.round()}% ${t.text('rolling_door_open_suffix')}',
      headerIcon: Icons.garage_rounded,
      accentColor: Colors.indigo,
      offline: widget.isOffline,
      onLongPress: () => _openMenu(
        context: context,
        mac: widget.mac,
        name: _displayName(t),
        subtitle: t.text('rolling_door_default_name'),
        headerIcon: Icons.garage_rounded,
        onOpenSettings: widget.onOpenSettings,
        cb: widget.callbacks,
        isHidden: widget.isHidden,
        onToggleHide: widget.onToggleHide,
      ),
      child: Column(
        children: [
          // ---- PHẦN TRÊN: ẢNH ĐỘNG MÔ PHỎNG NAN CỬA CUỐN ----
          // [GIAI ĐOẠN 71 — UI POLISH] Đổ bóng nổi khối + viền kính nhẹ (glassmorphism) cho vùng
          // graphic — trước đây chỉ có ClipRRect trơn, không có chiều sâu 3D.
          Container(
            height: 90,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12), blurRadius: 14, offset: const Offset(0, 6)),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.5), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Lottie.asset(
                    'assets/animations/rolling_door.json',
                    fit: BoxFit.cover,
                    animate: _isMoving,
                    errorBuilder: (context, error, stackTrace) => AnimatedBuilder(
                      animation: _motionController,
                      builder: (context, _) => CustomPaint(
                        painter: _RollingDoorPainter(
                          openPct: shownPct / 100,
                          isDark: isDark,
                          moving: _isMoving,
                          shimmerT: _motionController.value,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  // [GLASSMORPHISM NHẸ] Dải sáng chéo mờ ở góc trên — hiệu ứng kính phản chiếu,
                  // không che nội dung graphic bên dưới (IgnorePointer để không nuốt cảm ứng).
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.white.withValues(alpha: isDark ? 0.06 : 0.18), Colors.transparent, Colors.transparent],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ---- PHẦN GIỮA: SLIDER 0-100% (bọc khung đổ bóng + viền gradient nổi bật) ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [_tkGreen.withValues(alpha: isDark ? 0.16 : 0.10), Colors.transparent],
              ),
              boxShadow: [
                BoxShadow(color: _tkGreen.withValues(alpha: isDark ? 0.18 : 0.12), blurRadius: 10, offset: const Offset(0, 3)),
              ],
              border: Border.all(color: _tkGreen.withValues(alpha: isDark ? 0.25 : 0.18), width: 1),
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                // [FIX CRASH THẬT] Slider mặc định min=0.0/max=1.0 nếu KHÔNG khai báo tường minh —
                // value 0-100% (phần trăm) vượt xa max mặc định là văng đúng lỗi Assertion
                // "value ... is not between minimum 0.0 and maximum 1.0". Khai rõ 0-100 để khớp
                // đơn vị currentPosition đang dùng khắp widget này.
                min: 0.0,
                max: 100.0,
                value: shownPct.clamp(0.0, 100.0),
                activeColor: _tkGreen,
                inactiveColor: isDark ? Colors.white24 : Colors.grey.shade300,
                onChanged: widget.isOffline ? null : (v) => setState(() { _dragging = true; _dragValue = v.clamp(0.0, 100.0); }),
                onChangeEnd: widget.isOffline ? null : (v) => _onSliderChangeEnd(v.clamp(0.0, 100.0)),
              ),
            ),
          ),
          // ---- PHẦN DƯỚI: LÊN / DỪNG / XUỐNG ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHoldButton(icon: Icons.keyboard_arrow_up_rounded, direction: 'up', isDark: isDark),
              GestureDetector(
                behavior: HitTestBehavior.opaque, // cùng lý do cách ly cảm ứng như nút Lên/Xuống
                onTap: widget.isOffline ? null : _tapStop,
                child: Container(
                  width: 44, height: 36, alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.stop_rounded, size: 18, color: Colors.redAccent),
                ),
              ),
              _buildHoldButton(icon: Icons.keyboard_arrow_down_rounded, direction: 'down', isDark: isDark),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vẽ tay nan cửa cuốn khi chưa có file Lottie thật — panel kim loại trượt xuống từ trên theo
/// (1 - openPct), có đường kẻ nan ngang + hiệu ứng "đường sáng chạy" khi đang chuyển động.
class _RollingDoorPainter extends CustomPainter {
  final double openPct; // 0 = đóng kín, 1 = mở hoàn toàn
  final bool isDark;
  final bool moving;
  final double shimmerT; // 0..1 tuần hoàn — vị trí đường sáng chạy

  _RollingDoorPainter({required this.openPct, required this.isDark, required this.moving, required this.shimmerT});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect frame = Offset.zero & size;
    final Paint bg = Paint()..color = isDark ? const Color(0xFF0B1220) : const Color(0xFFE2E8F0);
    canvas.drawRect(frame, bg);

    // Khoảng trống phía dưới = phần cửa ĐÃ MỞ (openPct)
    final double panelHeight = size.height * (1 - openPct);
    final Rect panelRect = Rect.fromLTWH(0, 0, size.width, panelHeight);

    final Paint panelPaint = Paint()
      ..shader = LinearGradient(
        colors: isDark ? [const Color(0xFF475569), const Color(0xFF334155)] : [const Color(0xFF94A3B8), const Color(0xFF64748B)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ).createShader(panelRect);
    canvas.drawRect(panelRect, panelPaint);

    // Nan ngang (mỗi 8px một đường) — chỉ vẽ trong vùng panel
    final Paint slatLine = Paint()..color = Colors.black.withValues(alpha: 0.18)..strokeWidth = 1;
    for (double y = 8; y < panelHeight; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), slatLine);
    }

    // Đường viền đáy panel (mép cửa)
    if (panelHeight > 0) {
      final Paint edge = Paint()..color = _tkGreen.withValues(alpha: 0.8)..strokeWidth = 2.5;
      canvas.drawLine(Offset(0, panelHeight), Offset(size.width, panelHeight), edge);
    }

    // Đang chuyển động: 1 dải sáng mờ chạy dọc panel để mắt người nhận ra "đang cuộn"
    if (moving && panelHeight > 4) {
      final double shimmerY = shimmerT * panelHeight;
      final Paint shimmer = Paint()
        ..shader = LinearGradient(
          colors: [Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.0)],
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, shimmerY - 10, size.width, 20));
      canvas.drawRect(Rect.fromLTWH(0, shimmerY - 10, size.width, 20), shimmer);
    }
  }

  @override
  bool shouldRepaint(covariant _RollingDoorPainter oldDelegate) =>
      oldDelegate.openPct != openPct || oldDelegate.moving != moving || oldDelegate.shimmerT != shimmerT || oldDelegate.isDark != isDark;
}

// ============================================================================
// 💧 NHIỆM VỤ 2 — SmartPumpCard (Máy bơm)
// ============================================================================
class SmartPumpCard extends StatefulWidget {
  final String mac;
  final String endpoint;
  final bool isOn;
  final bool isOffline;
  final String? backendName;
  final DeviceProvider provider;
  final bool isHidden;
  final ValueChanged<bool> onToggleHide;
  final VoidCallback onOpenSettings;
  final TwinCardCallbacks callbacks;

  const SmartPumpCard({
    super.key,
    required this.mac,
    required this.endpoint,
    required this.isOn,
    this.isOffline = false,
    this.backendName,
    required this.provider,
    this.isHidden = false,
    required this.onToggleHide,
    required this.onOpenSettings,
    required this.callbacks,
  });

  @override
  State<SmartPumpCard> createState() => _SmartPumpCardState();
}

class _SmartPumpCardState extends State<SmartPumpCard> with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.isOn && !widget.isOffline) _spinController.repeat();
  }

  @override
  void didUpdateWidget(covariant SmartPumpCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool shouldSpin = widget.isOn && !widget.isOffline;
    if (shouldSpin && !_spinController.isAnimating) {
      _spinController.repeat();
    } else if (!shouldSpin && _spinController.isAnimating) {
      _spinController.stop();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  String _displayName(AppTranslations t) => widget.backendName?.isNotEmpty == true ? widget.backendName! : t.text('pump_default_name');

  void _toggle() {
    if (widget.isOffline) return;
    widget.provider.toggleSwitch(widget.mac, widget.endpoint, widget.isOn);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final t = AppTranslations.of(context);
    final bool on = widget.isOn && !widget.isOffline;

    return _TwinCardShell(
      title: _displayName(t),
      subtitle: widget.isOffline ? t.text('offline') : (on ? t.text('pump_running_status') : t.text('pump_idle_status')),
      headerIcon: Icons.water_drop_rounded,
      accentColor: Colors.blue,
      offline: widget.isOffline,
      onLongPress: () => _openMenu(
        context: context,
        mac: widget.mac,
        name: _displayName(t),
        subtitle: t.text('pump_default_name'),
        headerIcon: Icons.water_drop_rounded,
        onOpenSettings: widget.onOpenSettings,
        cb: widget.callbacks,
        isHidden: widget.isHidden,
        onToggleHide: widget.onToggleHide,
      ),
      child: GestureDetector(
        onTap: _toggle,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: on ? Colors.blue.withValues(alpha: 0.12) : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Lottie.asset(
                'assets/animations/pump.json',
                width: 72, height: 72,
                animate: on,
                errorBuilder: (context, error, stackTrace) => AnimatedBuilder(
                  animation: _spinController,
                  builder: (context, _) => Transform.rotate(
                    angle: _spinController.value * 2 * math.pi,
                    child: CustomPaint(size: const Size(56, 56), painter: _ImpellerPainter(color: on ? Colors.blue : Colors.grey)),
                  ),
                ),
              ),
              Icon(Icons.power_settings_new_rounded, size: 16, color: on ? Colors.blue : (isDark ? Colors.white38 : Colors.black26)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cánh quạt/mô-tơ bơm 3 cánh — vẽ tay để không phụ thuộc file Lottie thật.
class _ImpellerPainter extends CustomPainter {
  final Color color;
  _ImpellerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final Paint hub = Paint()..color = color.withValues(alpha: 0.25);
    canvas.drawCircle(center, r, hub);

    final Paint blade = Paint()..color = color..style = PaintingStyle.fill;
    for (int i = 0; i < 3; i++) {
      final double angle = i * (2 * math.pi / 3);
      final Path path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + r * math.cos(angle - 0.28), center.dy + r * math.sin(angle - 0.28))
        ..arcToPoint(Offset(center.dx + r * math.cos(angle + 0.28), center.dy + r * math.sin(angle + 0.28)), radius: Radius.circular(r), clockwise: true)
        ..close();
      canvas.drawPath(path, blade);
    }
    canvas.drawCircle(center, r * 0.22, Paint()..color = color.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _ImpellerPainter oldDelegate) => oldDelegate.color != color;
}

// ============================================================================
// 💡 NHIỆM VỤ 3 — SmartDimmerCard (Đèn Chiết áp / Dimmer)
// ============================================================================
// Rotary Knob TỰ VẼ bằng CustomPainter + GestureDetector.onPanUpdate (không thêm package
// sleek_circular_slider — tránh rủi ro không kiểm chứng được `flutter pub get` ngoại tuyến,
// và CustomPainter tự viết cho toàn quyền tuỳ biến màu/nét đứt theo đúng yêu cầu).
class SmartDimmerCard extends StatefulWidget {
  final String mac;
  final String endpoint;
  final bool isOn;
  final int brightness; // 0-100
  final bool isOffline;
  final String? backendName;
  final DeviceProvider provider;
  final bool isHidden;
  final ValueChanged<bool> onToggleHide;
  final VoidCallback onOpenSettings;
  final TwinCardCallbacks callbacks;

  const SmartDimmerCard({
    super.key,
    required this.mac,
    required this.endpoint,
    required this.isOn,
    this.brightness = 0,
    this.isOffline = false,
    this.backendName,
    required this.provider,
    this.isHidden = false,
    required this.onToggleHide,
    required this.onOpenSettings,
    required this.callbacks,
  });

  @override
  State<SmartDimmerCard> createState() => _SmartDimmerCardState();
}

class _SmartDimmerCardState extends State<SmartDimmerCard> {
  static const double _knobSize = 140;
  late double _pct; // 0-100
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _pct = widget.brightness.clamp(0, 100).toDouble();
  }

  @override
  void didUpdateWidget(covariant SmartDimmerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.brightness != widget.brightness) {
      _pct = widget.brightness.clamp(0, 100).toDouble();
    }
  }

  String _displayName(AppTranslations t) => widget.backendName?.isNotEmpty == true ? widget.backendName! : t.text('dimmer_default_name');

  void _updateFromLocalPosition(Offset local) {
    const Offset center = Offset(_knobSize / 2, _knobSize / 2);
    final Offset v = local - center;
    // atan2 chuẩn bắt đầu từ trục 3 giờ; xoay để 12 giờ = 0% và thuận chiều kim đồng hồ
    double angle = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    final double pct = (angle / (2 * math.pi)) * 100;
    setState(() => _pct = pct.clamp(0, 100));
  }

  void _commit() {
    if (widget.isOffline) return;
    widget.provider.setDimmerBrightness(widget.mac, widget.endpoint, _pct.round());
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final t = AppTranslations.of(context);
    final Color bulbColor = Color.lerp(Colors.grey.shade600, Colors.amber, (widget.isOn ? _pct : 0) / 100)!;

    return _TwinCardShell(
      title: _displayName(t),
      subtitle: widget.isOffline ? t.text('offline') : (widget.isOn ? '${_pct.round()}%' : t.text('off')),
      headerIcon: Icons.lightbulb_rounded,
      accentColor: Colors.amber,
      offline: widget.isOffline,
      onLongPress: () => _openMenu(
        context: context,
        mac: widget.mac,
        name: _displayName(t),
        subtitle: t.text('dimmer_default_name'),
        headerIcon: Icons.lightbulb_rounded,
        onOpenSettings: widget.onOpenSettings,
        cb: widget.callbacks,
        isHidden: widget.isHidden,
        onToggleHide: widget.onToggleHide,
      ),
      child: Center(
        child: GestureDetector(
          onTap: widget.isOffline ? null : () => widget.provider.toggleSwitch(widget.mac, widget.endpoint, widget.isOn),
          onPanStart: widget.isOffline ? null : (d) { setState(() => _dragging = true); _updateFromLocalPosition(d.localPosition); },
          onPanUpdate: widget.isOffline ? null : (d) => _updateFromLocalPosition(d.localPosition),
          onPanEnd: widget.isOffline ? null : (_) { setState(() => _dragging = false); _commit(); },
          child: SizedBox(
            width: _knobSize,
            height: _knobSize,
            child: CustomPaint(
              painter: _DimmerRingPainter(pct: widget.isOn ? _pct : 0, isDark: isDark, active: widget.isOn),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bulbColor.withValues(alpha: 0.18),
                    boxShadow: widget.isOn ? [BoxShadow(color: bulbColor.withValues(alpha: 0.55), blurRadius: 18, spreadRadius: 2)] : null,
                  ),
                  child: Icon(Icons.lightbulb_rounded, color: bulbColor, size: 34),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vòng Rotary Knob: nét nền mờ (nét đứt) + cung tiến trình (nét liền màu vàng) theo pct.
class _DimmerRingPainter extends CustomPainter {
  final double pct; // 0-100
  final bool isDark;
  final bool active;
  _DimmerRingPainter({required this.pct, required this.isDark, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 6;

    // Nét nền dạng chấm (giả lập nét đứt) — trọn 360°
    final Paint trackDot = Paint()..color = (isDark ? Colors.white24 : Colors.black12);
    const int totalDashes = 48;
    for (int i = 0; i < totalDashes; i++) {
      final double a = (i / totalDashes) * 2 * math.pi - math.pi / 2;
      final Offset p = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(p, 1.4, trackDot);
    }

    // Cung tiến trình thật theo pct — bắt đầu từ 12 giờ, thuận chiều kim đồng hồ
    if (pct > 0) {
      final Paint arc = Paint()
        ..color = active ? Colors.amber : Colors.grey
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      final Rect rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(rect, -math.pi / 2, (pct / 100) * 2 * math.pi, false, arc);

      // Núm chỉ vị trí hiện tại (đầu cung)
      final double a = (pct / 100) * 2 * math.pi - math.pi / 2;
      final Offset knob = center + Offset(math.cos(a), math.sin(a)) * radius;
      canvas.drawCircle(knob, 6, Paint()..color = Colors.white);
      canvas.drawCircle(knob, 6, Paint()..color = Colors.amber..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(covariant _DimmerRingPainter oldDelegate) =>
      oldDelegate.pct != pct || oldDelegate.isDark != isDark || oldDelegate.active != active;
}

// ============================================================================
// 🧩 NHIỆM VỤ 4 — GenericDeviceCard (LƯỚI AN TOÀN)
// ============================================================================
// Dùng cho MỌI category "chính chủ" (primaryDeviceCategories) chưa có thẻ chuyên biệt — trước
// bản này, thiết bị category "ac"/"fridge" bị ÂM THẦM RỚT KHỎI LƯỚI (dashboard_screen.dart tự
// continue qua mà không dựng thẻ nào, xem primaryDeviceCategories) — nay LUÔN có ít nhất một
// công tắc bật/tắt đơn giản, không bao giờ "biến mất" khỏi Bảng điều khiển nữa.
class GenericDeviceCard extends StatelessWidget {
  final String mac;
  final String endpoint;
  final String category; // "ac" | "fridge" | ... — chỉ dùng để chọn icon gợi ý
  final bool isOn;
  final bool isOffline;
  final String? backendName;
  final DeviceProvider provider;
  final bool isHidden;
  final ValueChanged<bool> onToggleHide;
  final VoidCallback onOpenSettings;
  final TwinCardCallbacks callbacks;

  const GenericDeviceCard({
    super.key,
    required this.mac,
    required this.endpoint,
    required this.category,
    required this.isOn,
    this.isOffline = false,
    this.backendName,
    required this.provider,
    this.isHidden = false,
    required this.onToggleHide,
    required this.onOpenSettings,
    required this.callbacks,
  });

  IconData get _categoryIcon => switch (category) {
        'ac' => Icons.ac_unit_rounded,
        'fridge' => Icons.kitchen_rounded,
        'light' => Icons.lightbulb_outline_rounded,
        _ => Icons.device_hub_rounded,
      };

  String _displayName(AppTranslations t) => backendName?.isNotEmpty == true ? backendName! : t.text('generic_device_default_name');

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final t = AppTranslations.of(context);
    final bool on = isOn && !isOffline;

    return _TwinCardShell(
      title: _displayName(t),
      subtitle: isOffline ? t.text('offline') : (on ? t.text('on') : t.text('off')),
      headerIcon: _categoryIcon,
      accentColor: Colors.teal,
      offline: isOffline,
      onLongPress: () => _openMenu(
        context: context,
        mac: mac,
        name: _displayName(t),
        subtitle: t.text('generic_device_default_name'),
        headerIcon: _categoryIcon,
        onOpenSettings: onOpenSettings,
        cb: callbacks,
        isHidden: isHidden,
        onToggleHide: onToggleHide,
      ),
      child: GestureDetector(
        onTap: isOffline ? null : () => provider.toggleSwitch(mac, endpoint, isOn),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: on ? _tkGreen : (isDark ? Colors.white10 : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.power_settings_new_rounded, color: on ? Colors.white : (isDark ? Colors.white38 : Colors.black38), size: 26),
        ),
      ),
    );
  }
}
