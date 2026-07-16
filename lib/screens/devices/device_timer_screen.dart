import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode, CupertinoTheme, CupertinoThemeData, CupertinoTextThemeData;
import 'package:flutter/material.dart';

import '../../services/constraint_engine.dart';
import '../../services/schedule_service.dart';
import '../../widgets/glass_popup.dart';

/// DeviceTimerScreen — Hẹn giờ & Lịch trình cho MỘT thiết bị (hoặc ĐÚNG MỘT kênh của thiết
/// bị nhiều relay — xem [endpoint]).
/// 2 tab: Đếm ngược (API THẬT: /api/devices/:mac/countdown, sống ở Backend — Postgres +
/// ticker 5s, KHÔNG còn Timer.periodic cục bộ) + Lịch trình (API THẬT: /api/devices/:mac/
/// schedules qua ScheduleService).
/// CHẠM vào lịch trình / bộ đếm ngược đang hoạt động -> mở trình CHỈNH SỬA tương ứng
/// (không chỉ xem); FAB "Thêm lịch" dùng chung editor với chế độ sửa.
class DeviceTimerScreen extends StatefulWidget {
  final String mac;
  final String deviceName;
  // [FIX MULTI-RELAY] Kênh CỤ THỂ mà thẻ vừa mở menu đại diện ("S_{mac}_2", "D1"...) — rỗng
  // = thiết bị 1 kênh (SSW01/quạt/Hub) hoặc lối gọi cũ chưa nâng cấp. MỌI lịch/đếm ngược tạo
  // từ màn hình này đều mang endpoint này, đảm bảo lệnh CHỈ tác động đúng kênh đang xem.
  final String endpoint;
  const DeviceTimerScreen({super.key, required this.mac, required this.deviceName, this.endpoint = ''});

  @override
  State<DeviceTimerScreen> createState() => _DeviceTimerScreenState();
}

class _DeviceTimerScreenState extends State<DeviceTimerScreen> {
  static const Color tkGreen = Color(0xFF00A651);
  static const List<String> _repeatOptions = ['Một lần', 'Hàng ngày', 'T2 - T6', 'Cuối tuần'];

  // Lịch trình từ API thật (bảng device_schedules bên Backend)
  final ScheduleService _scheduleApi = ScheduleService();
  List<ScheduleItem> _schedules = [];
  bool _loadingSchedules = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _loadCountdown();
  }

  Future<void> _loadSchedules() async {
    setState(() => _loadingSchedules = true);
    final (list, err) = await _scheduleApi.fetchSchedules(widget.mac, endpoint: widget.endpoint);
    if (!mounted) return;
    setState(() {
      _schedules = list;
      _loadingSchedules = false;
    });
    if (err != null) _snack(err, isError: true);
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.redAccent : tkGreen));
  }

  // ----- ĐẾM NGƯỢC — API THẬT (bảng device_countdowns, ticker Backend 5s) -----
  // _ticker ở đây CHỈ vẽ lại đồng hồ trên màn hình mỗi giây (UI thuần) — việc BẮN LỆNH thật
  // khi hết giờ do Backend tự làm dù App có đang mở hay không, KHÔNG phụ thuộc widget này.
  final CountdownService _countdownApi = CountdownService();
  CountdownItem? _countdown; // null = chưa đặt
  bool _loadingCountdown = true;
  Duration _countdownDuration = const Duration(hours: 1); // giá trị gợi ý cho lần đặt tiếp theo
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Gọi lúc mở màn hình để KHÔI PHỤC đếm ngược đang chạy (nếu có) — trước đây đóng/mở lại
  /// App là mất trắng bộ đếm vì nó chỉ sống trong biến State cục bộ.
  Future<void> _loadCountdown() async {
    setState(() => _loadingCountdown = true);
    final (cd, err) = await _countdownApi.fetchActive(widget.mac, endpoint: widget.endpoint);
    if (!mounted) return;
    setState(() {
      _countdown = cd;
      _loadingCountdown = false;
    });
    if (err != null) {
      _snack(err, isError: true);
    } else if (cd != null) {
      _startTicker();
    }
  }

  Duration get _remaining => _countdown?.remaining ?? Duration.zero;

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_countdown != null && _remaining == Duration.zero) {
        // Hiển thị hết 00:00:00 — Backend là nơi QUYẾT ĐỊNH thật sự đã bắn lệnh hay chưa
        // (ticker Server 5s có thể trễ vài giây so với đồng hồ App). Poll lại 1 lần để đồng
        // bộ UI với sự thật thay vì tự đoán đã xong.
        _ticker?.cancel();
        _loadCountdown().then((_) {
          if (mounted && _countdown == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Hết giờ đếm ngược cho "${widget.deviceName}"'), backgroundColor: tkGreen));
          }
        });
        return;
      }
      setState(() {}); // tick: cập nhật số giây còn lại
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [KÍNH MỜ] Màn này sống TRONG _GlassShell của openAdaptiveScreen — nền/AppBar phải
    // TRONG SUỐT, chữ contrast chuẩn kính, thẻ nội dung dùng dải alpha (không màu đặc).
    final Color textMain = isDark ? Colors.white : Colors.black87;
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final Color cardColor = Colors.white.withValues(alpha: isDark ? 0.08 : 0.55);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent, // vỏ kính bên ngoài lo phần nền
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Hẹn giờ & Lịch trình', style: TextStyle(fontSize: 16)),
            Text(widget.deviceName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: textSub, fontWeight: FontWeight.normal)),
          ]),
          backgroundColor: Colors.transparent,
          foregroundColor: textMain,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: tkGreen, labelColor: tkGreen,
            tabs: [Tab(icon: Icon(Icons.timelapse), text: 'Đếm ngược'), Tab(icon: Icon(Icons.event_repeat), text: 'Lịch trình')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: tkGreen, foregroundColor: Colors.white,
          icon: const Icon(Icons.add), label: const Text('Thêm lịch'),
          onPressed: () => _editSchedule(null), // editor dùng chung: null = thêm mới
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildCountdownTab(cardColor, textMain, textSub),
              _buildScheduleTab(cardColor, textMain, textSub),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // TAB ĐẾM NGƯỢC — chạm vào đồng hồ đang chạy để CHỈNH SỬA lại thời lượng
  // ==========================================================================
  Widget _buildCountdownTab(Color cardColor, Color textMain, Color textSub) {
    if (_loadingCountdown) {
      return const Center(child: CircularProgressIndicator(color: tkGreen));
    }
    final bool active = _countdown != null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: active ? _editCountdown : null, // đang chạy -> chạm mở chỉnh sửa
              customBorder: const CircleBorder(),
              child: Container(
                width: 180, height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: cardColor,
                  border: Border.all(color: tkGreen.withValues(alpha: active ? 0.9 : 0.4), width: 6),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(active ? _fmtDuration(_remaining) : '00:00:00',
                        style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold)),
                    if (active) ...[
                      const SizedBox(height: 6),
                      Text('${_countdown!.turnOn ? 'Bật' : 'Tắt'} khi hết giờ', style: TextStyle(color: textSub, fontSize: 11)),
                      Text('Chạm để chỉnh sửa', style: TextStyle(color: tkGreen, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(active ? 'Đếm ngược đang hoạt động' : 'Chưa đặt hẹn giờ đếm ngược', style: TextStyle(color: textSub)),
            const SizedBox(height: 16),
            if (!active)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Đặt đếm ngược'),
                onPressed: _editCountdown,
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: tkGreen, side: const BorderSide(color: tkGreen), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Chỉnh sửa'),
                    onPressed: _editCountdown,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    icon: const Icon(Icons.stop_rounded, size: 18),
                    label: const Text('Hủy'),
                    onPressed: () async {
                      _ticker?.cancel();
                      final prev = _countdown;
                      setState(() => _countdown = null); // optimistic
                      final err = await _countdownApi.cancel(widget.mac, endpoint: widget.endpoint);
                      if (!mounted) return;
                      if (err != null) {
                        setState(() => _countdown = prev); // hoàn tác
                        _snack(err, isError: true);
                      } else {
                        _snack('Đã hủy đếm ngược');
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Popup đặt/chỉnh đếm ngược — [KÍNH MỜ ĐỒNG BỘ] qua showGlassPopup (PC: dialog
  /// giữa màn hình; Mobile: sheet). Đang chạy -> picker đổ sẵn thời gian CÒN LẠI.
  /// [API THẬT] Bấm "Bắt đầu" -> POST /api/devices/:mac/countdown (seconds tính từ LÚC GỌI,
  /// Server tự cộng vào đồng hồ của nó — tránh lệch giờ App/Server).
  void _editCountdown() {
    Duration picked = _countdown != null ? _remaining : _countdownDuration;
    if (picked < const Duration(minutes: 1)) picked = const Duration(minutes: 1);
    bool turnOn = _countdown?.turnOn ?? false;
    final bool wasActive = _countdown != null;

    showGlassPopup(
      context,
      title: wasActive ? 'Chỉnh sửa đếm ngược' : 'Đặt đếm ngược',
      body: (ctx) {
        final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
        final Color pickerColor = isDark ? Colors.white.withValues(alpha: 0.95) : const Color(0xFF0F172A);
        bool submitting = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 170,
                  // Ép chữ picker theo màu nền kính (Cupertino không ăn theme Material)
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      textTheme: CupertinoTextThemeData(pickerTextStyle: TextStyle(color: pickerColor, fontSize: 20)),
                    ),
                    child: CupertinoTimerPicker(
                      mode: CupertinoTimerPickerMode.hm,
                      initialTimerDuration: Duration(hours: picked.inHours, minutes: picked.inMinutes % 60),
                      onTimerDurationChanged: (d) => picked = d,
                    ),
                  ),
                ),
                SwitchListTile(
                  value: turnOn,
                  activeThumbColor: tkGreen,
                  title: Text('Hành động khi hết giờ: ${turnOn ? 'Bật' : 'Tắt'} thiết bị',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  onChanged: submitting ? null : (v) => setSheet(() => turnOn = v),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    icon: submitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(wasActive ? 'Lưu thay đổi' : 'Bắt đầu đếm ngược'),
                    onPressed: submitting
                        ? null
                        : () async {
                            if (picked < const Duration(minutes: 1)) picked = const Duration(minutes: 1);
                            setSheet(() => submitting = true);
                            final (cd, err) = await _countdownApi.start(
                              widget.mac,
                              endpoint: widget.endpoint,
                              seconds: picked.inSeconds,
                              turnOn: turnOn,
                            );
                            if (!ctx.mounted) return;
                            if (err != null || cd == null) {
                              setSheet(() => submitting = false);
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(err ?? 'Không đặt được đếm ngược'), backgroundColor: Colors.redAccent));
                              return;
                            }
                            Navigator.pop(ctx);
                            _countdownDuration = picked;
                            if (!mounted) return;
                            setState(() => _countdown = cd);
                            _startTicker();
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // TAB LỊCH TRÌNH (API THẬT) — chạm vào hàng để CHỈNH SỬA; Switch bật/tắt nhanh
  // ==========================================================================
  Widget _buildScheduleTab(Color cardColor, Color textMain, Color textSub) {
    if (_loadingSchedules) {
      return const Center(child: CircularProgressIndicator(color: tkGreen));
    }
    if (_schedules.isEmpty) {
      return Center(child: Text('Chưa có lịch trình nào.\nBấm "Thêm lịch" để tạo mới.', textAlign: TextAlign.center, style: TextStyle(color: textSub)));
    }
    return RefreshIndicator(
      color: tkGreen,
      onRefresh: _loadSchedules,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _schedules.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final s = _schedules[index];
          final bool on = s.isOn;
          return Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onTap: () => _editSchedule(index), // chạm cả hàng -> mở trình chỉnh sửa
              leading: CircleAvatar(backgroundColor: (on ? tkGreen : Colors.redAccent).withValues(alpha: 0.15), child: Icon(on ? Icons.power_settings_new : Icons.power_off, color: on ? tkGreen : Colors.redAccent)),
              title: Text(s.time, style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
              subtitle: Text('${s.repeatDays} • ${on ? 'Bật thiết bị' : 'Tắt thiết bị'} • Chạm để sửa', style: TextStyle(color: textSub, fontSize: 12)),
              // Optimistic: gạt ngay, API lỗi thì hoàn tác + báo lỗi
              trailing: Switch(
                value: s.isEnabled, activeThumbColor: tkGreen,
                onChanged: (v) async {
                  setState(() => s.isEnabled = v);
                  final err = await _scheduleApi.toggleSchedule(s.id, v);
                  if (err != null && mounted) {
                    setState(() => s.isEnabled = !v);
                    _snack(err, isError: true);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Editor dùng chung Thêm/Sửa lịch trình — [KÍNH MỜ ĐỒNG BỘ] qua showGlassPopup
  /// (PC: dialog GIỮA màn hình thay vì sheet bị đẩy xuống đáy; Mobile: sheet kính mờ).
  /// [index]=null -> thêm mới; khác null -> đổ sẵn dữ liệu lịch đó + nút Xóa.
  Future<void> _editSchedule(int? index) async {
    // Sửa -> đổ sẵn dữ liệu lịch đang có; Thêm -> giá trị mặc định
    final ScheduleItem? editing = index != null ? _schedules[index] : null;
    final parts = (editing?.time ?? '07:00').split(':');
    TimeOfDay time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 7, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    String repeat = _repeatOptions.contains(editing?.repeatDays) ? editing!.repeatDays : _repeatOptions[1];
    bool turnOn = editing?.isOn ?? true;

    await showGlassPopup(
      context,
      title: index != null ? 'Chỉnh sửa lịch trình' : 'Thêm lịch trình',
      body: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Giờ chạy -> mở TimePicker chuẩn Material (màu chữ kế thừa panel kính)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.access_time, color: tkGreen),
                  title: const Text('Thời gian', style: TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: time);
                    if (picked != null) setSheet(() => time = picked);
                  },
                ),
                const SizedBox(height: 8),

                const Text('Lặp lại', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _repeatOptions.map((r) => ChoiceChip(
                        label: Text(r),
                        selected: repeat == r,
                        selectedColor: tkGreen.withValues(alpha: 0.2),
                        labelStyle: TextStyle(color: repeat == r ? tkGreen : null, fontWeight: FontWeight.w600),
                        onSelected: (_) => setSheet(() => repeat = r),
                      )).toList(),
                ),
                const SizedBox(height: 8),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: turnOn,
                  activeThumbColor: tkGreen,
                  title: Text('Hành động: ${turnOn ? 'Bật' : 'Tắt'} thiết bị',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  onChanged: (v) => setSheet(() => turnOn = v),
                ),
                const SizedBox(height: 8),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(editing != null ? 'Lưu thay đổi' : 'Thêm lịch'),
                    onPressed: () async {
                      // [CONSTRAINT ENGINE] Quy tắc 'schedule.times': mỗi mốc giờ chỉ 1 lịch
                      // (2 lịch trùng giờ = xung đột ON/OFF không xác định) — chặn NGAY tại
                      // đây trước khi gọi API; sửa lịch thì loại chính nó khỏi phép so.
                      final String newTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                      final conflict = ValidationEngine.validateFor('schedule.times',
                          current: [
                            for (final s in _schedules)
                              if (s.id != (editing?.id ?? '')) SelectionItem(key: 's${s.id}', scopeKey: s.time),
                          ],
                          attempt: SelectionItem(key: 'new', scopeKey: newTime));
                      if (!conflict.allowed) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(conflict.reason ?? 'Trùng giờ với lịch khác'),
                            backgroundColor: Colors.redAccent));
                        return; // giữ nguyên editor để user chỉnh lại giờ
                      }

                      Navigator.pop(ctx);
                      // API THẬT: POST /devices/:mac/schedules (upsert theo id; id rỗng = tạo mới)
                      // [FIX MULTI-RELAY] endpoint LUÔN gửi kèm — scheduler.go chỉ bắn đúng
                      // kênh này, không còn dò mọi kênh của thiết bị rồi bắn tất (nổ cả cụm).
                      final (saved, err) = await _scheduleApi.saveSchedule(widget.mac, {
                        'id': editing?.id ?? '',
                        'endpoint': widget.endpoint,
                        'time': newTime,
                        'repeat_days': repeat,
                        'action': turnOn ? 'ON' : 'OFF',
                        'is_enabled': editing?.isEnabled ?? true,
                      });
                      if (!mounted) return;
                      if (err != null || saved == null) {
                        _snack(err ?? 'Không lưu được lịch trình', isError: true);
                        return;
                      }
                      // Đắp bản server trả về (id thật) vào list, giữ thứ tự theo giờ chạy
                      setState(() {
                        final i = _schedules.indexWhere((x) => x.id == saved.id);
                        if (i == -1) {
                          _schedules.add(saved);
                        } else {
                          _schedules[i] = saved;
                        }
                        _schedules.sort((a, b) => a.time.compareTo(b.time));
                      });
                      _snack(editing != null ? 'Đã lưu lịch trình' : 'Đã thêm lịch trình mới');
                    },
                  ),
                ),

                // Xóa lịch (chỉ khi đang sửa) — optimistic: gỡ ngay, API lỗi thì gắn lại
                if (editing != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa lịch trình này'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        setState(() => _schedules.removeAt(index!));
                        final err = await _scheduleApi.deleteSchedule(editing.id);
                        if (!mounted) return;
                        if (err != null) {
                          setState(() => _schedules.insert(index!, editing));
                          _snack(err, isError: true);
                        } else {
                          _snack('Đã xóa lịch trình ${editing.time}');
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
        ),
      ),
    );
  }
}
