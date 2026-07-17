import 'package:flutter/cupertino.dart' show CupertinoTimerPicker, CupertinoTimerPickerMode, CupertinoTheme, CupertinoThemeData, CupertinoTextThemeData;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/device_provider.dart';
import '../../services/schedule_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../localization/app_translations.dart';
import 'create_automation_screen.dart';

/// AddSceneOrScheduleScreen — Popup "Thêm mới" GỘP 2 loại: Ngữ cảnh (Scene) và Lịch trình
/// (Schedule/Countdown). Trước đây nút FAB "Thêm" chỉ mở được CreateAutomationScreen — không
/// có đường tạo lịch trình độc lập kèm chọn đúng thiết bị/kênh.
///
/// [editingSchedule] != null -> mở thẳng tab "Lịch trình", form đổ sẵn dữ liệu của lịch đó,
/// nút Lưu gọi UPDATE (PUT, giữ nguyên id) thay vì CREATE (POST) — dùng khi chạm vào 1 dòng
/// trong danh sách Lịch trình gộp để sửa.
class AddSceneOrScheduleScreen extends StatelessWidget {
  final ScheduleItem? editingSchedule;
  const AddSceneOrScheduleScreen({super.key, this.editingSchedule});

  static const Color tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : Colors.black87;
    final Color textSub = isDark ? Colors.white70 : Colors.black54;

    return DefaultTabController(
      length: 2,
      initialIndex: editingSchedule != null ? 1 : 0,
      child: AppScaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(t.text('add_new_title')),
          backgroundColor: Colors.transparent,
          foregroundColor: textMain,
          elevation: 0,
          bottom: TabBar(
            indicatorColor: tkGreen,
            labelColor: tkGreen,
            unselectedLabelColor: textSub,
            tabs: [
              Tab(icon: const Icon(Icons.auto_awesome), text: t.text('routines')),
              Tab(icon: const Icon(Icons.event_repeat), text: t.text('schedule_tab')),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              const CreateAutomationScreen(embedded: true),
              _ScheduleFormTab(editing: editingSchedule),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab "Lịch trình" — Dropdown Thiết bị -> Dropdown Nút/Endpoint (CHỈ hiện kênh THẬT của
/// thiết bị đã chọn) -> Hành động (Bật/Tắt | Tốc độ | Đảo gió | Tùy chỉnh, tùy loại kênh) ->
/// Giờ cố định (Cron) hoặc Đếm ngược.
/// [FIX MULTI-RELAY] endpoint LUÔN đi kèm mac khi gọi API — không có đường nào từ form này
/// tạo được lệnh "cả thiết bị" mơ hồ, tránh tái diễn lỗi "bật 1 nút nổ cả cụm".
class _ScheduleFormTab extends StatefulWidget {
  final ScheduleItem? editing;
  const _ScheduleFormTab({this.editing});

  @override
  State<_ScheduleFormTab> createState() => _ScheduleFormTabState();
}

class _ScheduleFormTabState extends State<_ScheduleFormTab> {
  static const Color tkGreen = Color(0xFF00A651);
  static const List<String> _repeatOptions = ['Một lần', 'Hàng ngày', 'T2 - T6', 'Cuối tuần'];

  final ScheduleService _scheduleApi = ScheduleService();
  final CountdownService _countdownApi = CountdownService();

  String? _selectedMac;
  String? _selectedEndpoint;
  bool _turnOn = true;
  bool _isCountdown = false; // false = Giờ cố định (Cron), true = Đếm ngược
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  late String _repeat;
  Duration _countdownDuration = const Duration(hours: 1);
  bool _saving = false;

  // [ACTION MAPPING — YÊU CẦU 3] Kênh "phức tạp" (quạt: có _speed/_swing) cần chọn LOẠI
  // hành động trước khi biết dựng widget nào: 'set' (Bật/Tắt) | 'speed' (Số 1-3) | 'osc'
  // (Đảo gió, tái dùng _turnOn) | 'custom' (gõ tay Value cho kênh lạ chưa có UI chuyên biệt
  // — chốt chặn an toàn thay vì chặn cứng người dùng khi gặp loại thiết bị mới).
  String _actionKind = 'set';
  int _speedValue = 1;
  final TextEditingController _customValueCtrl = TextEditingController();

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _repeat = _repeatOptions[1];
    final e = widget.editing;
    if (e != null) {
      _selectedMac = e.deviceMac.isNotEmpty ? e.deviceMac : null;
      _selectedEndpoint = e.endpoint;
      _turnOn = e.isOn;
      final parts = e.time.split(':');
      _time = TimeOfDay(hour: int.tryParse(parts[0]) ?? 7, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
      _repeat = _repeatOptions.contains(e.repeatDays) ? e.repeatDays : _repeatOptions[1];
      // Sửa lịch (mở từ danh sách Lịch trình) luôn là Cron — danh sách đó không liệt kê
      // Đếm ngược (bảng dữ liệu Backend hoàn toàn khác nhau).
      _isCountdown = false;

      _actionKind = e.actionKind;
      switch (_actionKind) {
        case 'speed':
          _speedValue = int.tryParse(e.actionValue) ?? 1;
          break;
        case 'osc':
          _turnOn = e.actionValue.toUpperCase() == 'SWING';
          break;
        case 'set':
          break;
        default:
          _customValueCtrl.text = e.actionValue;
      }
    }
  }

  @override
  void dispose() {
    _customValueCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? Colors.redAccent : tkGreen));
  }

  Future<void> _save() async {
    // [SỬA LỖI LIỆT NÚT] context.watch() được Provider assert bằng cờ TOÀN CỤC
    // context.owner!.debugBuilding — luôn false khi đang xử lý sự kiện chạm, kể cả TRƯỚC
    // await đầu tiên. Gọi listen:true ở đây từng khiến nút Lưu lịch trình bấm không phản ứng.
    final t = AppTranslations.of(context, listen: false);
    if (_selectedMac == null || _selectedEndpoint == null || _selectedEndpoint!.isEmpty) {
      _snack(t.text('pick_device_channel_error'), isError: true);
      return;
    }
    if (_actionKind == 'custom' && _customValueCtrl.text.trim().isEmpty) {
      _snack(t.text('pick_custom_value_error'), isError: true);
      return;
    }
    setState(() => _saving = true);

    String? err;
    if (_isCountdown) {
      final (cd, e) = await _countdownApi.start(
        _selectedMac!,
        endpoint: _selectedEndpoint!,
        seconds: _countdownDuration.inSeconds,
        turnOn: _turnOn,
      );
      err = cd == null ? (e ?? 'Không đặt được đếm ngược') : null;
    } else {
      final String newTime = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

      // [ACTION MAPPING] action_payload linh hoạt {action,value} — ĐÚNG khuôn Go đọc ở
      // scheduler.go (scheduleActionFor). Trường action top-level (ON/OFF) Backend BẮT
      // BUỘC phải có dù dùng action_payload hay không -> suy ra ý nghĩa thô "có đang bật
      // gì đó không" để điền cho hợp lệ, KHÔNG dùng để bắn lệnh khi đã có action_payload.
      Map<String, String>? payload;
      final String coarseAction;
      switch (_actionKind) {
        case 'speed':
          payload = {'action': 'speed', 'value': _speedValue.toString()};
          coarseAction = _speedValue > 0 ? 'ON' : 'OFF';
          break;
        case 'osc':
          payload = {'action': 'osc', 'value': _turnOn ? 'swing' : 'off'};
          coarseAction = _turnOn ? 'ON' : 'OFF';
          break;
        case 'custom':
          payload = {'action': 'set', 'value': _customValueCtrl.text.trim()};
          coarseAction = 'ON';
          break;
        default: // 'set' — kênh công tắc/relay/quạt đơn giản, Bật/Tắt thẳng
          payload = null;
          coarseAction = _turnOn ? 'ON' : 'OFF';
      }

      final Map<String, dynamic> body = {
        'id': widget.editing?.id ?? '',
        'endpoint': _selectedEndpoint,
        'time': newTime,
        'repeat_days': _repeat,
        'action': coarseAction,
        'is_enabled': widget.editing?.isEnabled ?? true,
      };
      if (payload != null) body['action_payload'] = payload;

      final (saved, e) = await _scheduleApi.saveSchedule(_selectedMac!, body);
      err = saved == null ? (e ?? 'Không lưu được lịch trình') : null;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      _snack(err, isError: true);
      return; // giữ nguyên form cho user sửa lại — không mất dữ liệu đã nhập
    }
    // true = báo cho AddSceneOrScheduleScreen/caller biết "đã lưu lịch trình" -> refresh list.
    Navigator.pop(context, true);
  }

  Widget _sectionCard(Color cardColor, List<Widget> children) => Container(
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : Colors.black87;
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final Color cardColor = Colors.white.withValues(alpha: isDark ? 0.08 : 0.55);
    final Color infoBg = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);

    final deviceProvider = context.watch<DeviceProvider>();
    final devices = deviceProvider.devices; // Map<mac, DeviceModel>
    final macList = devices.keys.toList()..sort();
    final DeviceModel? selectedDevice = _selectedMac == null ? null : devices[_selectedMac];

    // [YÊU CẦU 1 — RÀ SOÁT endpointIds] endpointIds (device_provider.dart) lọc BẰNG DANH
    // SÁCH ĐEN các hậu tố thuộc tính (_speed/_swing/_name/_type/_temperature/_humidity),
    // KHÔNG PHẢI danh sách trắng "relay/sw_" như dự đoán — đã đối chiếu với scene_step_pickers.dart
    // (nơi picker Ngữ cảnh dùng CHUNG hàm này và hiển thị quạt đúng) nên không sửa lại hàm
    // gốc. Quạt gói speed/swing làm THUỘC TÍNH của một endpoint DUY NHẤT ("S_xxx"/"F1"), nên
    // luôn trả đúng 1 phần tử — không rỗng. Loại cảm biến (không điều khiển được).
    final List<String> endpoints = selectedDevice == null
        ? const []
        : selectedDevice.endpointIds.where((ep) => selectedDevice.typeOf(ep) != 'sensor').toList();

    // [YÊU CẦU 2] Thiết bị chỉ có 0 hoặc 1 kênh thật -> không có gì để CHỌN -> ẩn Dropdown 2,
    // tự ngầm định kênh đó (hoặc '' — quy ước "cả thiết bị" — nếu chưa có dữ liệu kênh nào).
    final bool showEndpointPicker = endpoints.length > 1;
    final String? autoEndpoint = endpoints.length == 1 ? endpoints.first : (endpoints.isEmpty ? '' : null);

    // Đồng bộ _selectedEndpoint với danh sách kênh hiện tại NGAY TRONG build (không dùng
    // setState/postFrameCallback): đang ở trong build() nên sửa field trực tiếp là an toàn
    // — widget dựng ngay sau dòng này đã phản ánh giá trị đúng, không có khung hình nào lọt
    // ra ngoài với giá trị cũ/không khớp danh sách item mới.
    if (!showEndpointPicker) {
      if (_selectedEndpoint != autoEndpoint) _selectedEndpoint = autoEndpoint;
    } else if (_selectedEndpoint != null && !endpoints.contains(_selectedEndpoint)) {
      _selectedEndpoint = null;
    }

    final bool hasSpeed = selectedDevice != null && _selectedEndpoint != null && selectedDevice.dps.containsKey('${_selectedEndpoint}_speed');
    final bool hasSwing = selectedDevice != null && _selectedEndpoint != null && selectedDevice.dps.containsKey('${_selectedEndpoint}_swing');
    final bool isComplexChannel = hasSpeed || hasSwing;

    // Loại hành động đang chọn không còn hợp lệ cho kênh hiện tại (vd đổi sang kênh không
    // có _swing trong khi đang chọn 'osc') -> rơi về 'set' NGAY TRONG build, cùng lý do trên
    // (SegmentedButton assert selected phải nằm trong segments hiện có — sửa trễ 1 khung
    // hình bằng postFrameCallback sẽ vỡ assert đó trước khi kịp sửa).
    if (isComplexChannel) {
      final validKinds = {'set', if (hasSpeed) 'speed', if (hasSwing) 'osc', 'custom'};
      if (!validKinds.contains(_actionKind)) _actionKind = 'set';
    } else if (_actionKind != 'set') {
      _actionKind = 'set';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCard(cardColor, [
                Text(t.text('device_and_channel'), style: TextStyle(color: textMain, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                const SizedBox(height: 10),
                // [FORM SWEEP] DropdownButtonFormField -> AppDropdown. Dropdown 1: Thiết bị
                // (KHÔNG cascading — danh sách macList không phụ thuộc lựa chọn nào khác nên
                // không cần key: ValueKey).
                AppDropdown<String>(
                  value: macList.contains(_selectedMac) ? _selectedMac : null,
                  labelText: t.text('pick_device'),
                  prefixIcon: Icon(Icons.devices_other_rounded, color: textSub, size: 20),
                  items: [
                    for (final mac in macList)
                      DropdownMenuItem(value: mac, child: Text(deviceProvider.displayNameOf(mac), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedMac = v;
                    _selectedEndpoint = null; // đổi thiết bị -> bắt chọn lại kênh, không giữ kênh cũ sai ngữ cảnh
                    _actionKind = 'set'; // loại hành động cũ (vd 'speed') có thể không còn ý nghĩa với thiết bị mới
                  }),
                ),
                const SizedBox(height: 12),
                // Dropdown 2: Nút/Endpoint — CHỈ hiện khi thật sự có NHIỀU HƠN 1 kênh để chọn.
                if (showEndpointPicker)
                  // [FORM SWEEP] DropdownButtonFormField -> AppDropdown. Dropdown 2 (Kênh) LÀ
                  // cascading (danh sách endpoints phụ thuộc _selectedMac) — GIỮ NGUYÊN
                  // key: ValueKey('ep-$_selectedMac') y hệt bản gốc, đúng cảnh báo trong
                  // docstring AppDropdown: thiếu key này sẽ tái diễn lỗi "hộp trắng rỗng" vì
                  // initialValue chỉ đọc 1 lần lúc FormFieldState khởi tạo — key đổi theo thiết
                  // bị ép Flutter hủy + tạo lại toàn bộ subtree (kể cả DropdownButtonFormField
                  // nằm bên trong AppDropdown) mỗi khi đổi thiết bị.
                  AppDropdown<String>(
                    key: ValueKey('ep-$_selectedMac'),
                    value: endpoints.contains(_selectedEndpoint) ? _selectedEndpoint : null,
                    labelText: t.text('pick_channel'),
                    prefixIcon: Icon(Icons.toggle_on_outlined, color: textSub, size: 20),
                    items: [
                      for (final ep in endpoints)
                        DropdownMenuItem(
                          value: ep,
                          child: Text(deviceProvider.displayNameOfEndpoint(_selectedMac!, ep, fallback: ep), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedEndpoint = v;
                      _actionKind = 'set';
                    }),
                  )
                else if (_selectedMac != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: infoBg, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: textSub),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            endpoints.isEmpty
                                ? t.text('no_channels_info')
                                : '${t.text('single_channel_info_prefix')}${deviceProvider.displayNameOfEndpoint(_selectedMac!, endpoints.first, fallback: endpoints.first)}".',
                            style: TextStyle(color: textSub, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              _sectionCard(cardColor, [
                Text(t.text('action_label'), style: TextStyle(color: textMain, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                // [YÊU CẦU 3 — ACTION MAPPING] Kênh phức tạp (quạt: có _speed và/hoặc _swing)
                // -> cho chọn LOẠI hành động trước; kênh công tắc/relay đơn giản -> giữ nguyên
                // Bật/Tắt như cũ, không thêm bước thừa.
                if (isComplexChannel) ...[
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'set', icon: const Icon(Icons.power_settings_new), label: Text(t.text('toggle_segment'))),
                      if (hasSpeed) ButtonSegment(value: 'speed', icon: const Icon(Icons.speed), label: Text(t.text('speed_segment'))),
                      if (hasSwing) ButtonSegment(value: 'osc', icon: const Icon(Icons.autorenew), label: Text(t.text('swing_segment'))),
                      ButtonSegment(value: 'custom', icon: const Icon(Icons.edit_note), label: Text(t.text('custom_segment'))),
                    ],
                    selected: {_actionKind},
                    onSelectionChanged: (s) => setState(() => _actionKind = s.first),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_actionKind == 'speed')
                  Wrap(
                    spacing: 8,
                    children: [1, 2, 3]
                        .map((n) => ChoiceChip(
                              label: Text('Số $n'),
                              selected: _speedValue == n,
                              selectedColor: tkGreen.withValues(alpha: 0.2),
                              labelStyle: TextStyle(color: _speedValue == n ? tkGreen : null, fontWeight: FontWeight.w600),
                              onSelected: (_) => setState(() => _speedValue = n),
                            ))
                        .toList(),
                  )
                else if (_actionKind == 'custom')
                  TextField(
                    controller: _customValueCtrl,
                    style: TextStyle(color: textMain),
                    decoration: InputDecoration(
                      labelText: t.text('custom_value_label'),
                      helperText: t.text('custom_value_helper'),
                      labelStyle: TextStyle(color: textSub),
                      helperStyle: TextStyle(color: textSub, fontSize: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )
                else
                  // 'set' (Bật/Tắt) hoặc 'osc' (Đảo gió/Đứng yên) — cùng dùng SegmentedButton<bool>,
                  // chỉ khác nhãn hiển thị.
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, icon: const Icon(Icons.power_settings_new), label: Text(_actionKind == 'osc' ? t.text('swing_segment') : t.text('turn_on_segment'))),
                      ButtonSegment(value: false, icon: const Icon(Icons.power_off), label: Text(_actionKind == 'osc' ? t.text('standing_still') : t.text('turn_off_segment'))),
                    ],
                    selected: {_turnOn},
                    onSelectionChanged: (s) => setState(() => _turnOn = s.first),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
              ]),
              const SizedBox(height: 16),

              _sectionCard(cardColor, [
                Text(t.text('schedule_type_label'), style: TextStyle(color: textMain, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, icon: const Icon(Icons.access_time), label: Text(t.text('fixed_time'))),
                    ButtonSegment(value: true, icon: const Icon(Icons.timelapse), label: Text(t.text('countdown'))),
                  ],
                  selected: {_isCountdown},
                  // Sửa lịch luôn khóa ở Cron — 2 bảng dữ liệu Backend hoàn toàn khác nhau,
                  // không có khái niệm "chuyển loại" một lịch đã tồn tại.
                  onSelectionChanged: _isEditing ? null : (s) => setState(() => _isCountdown = s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 16),
                if (!_isCountdown) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time, color: tkGreen),
                    title: Text(t.text('time_label'), style: TextStyle(color: textSub, fontSize: 12)),
                    subtitle: Text(
                      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _time);
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(t.text('repeat_label'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _repeatOptions
                        .map((r) => ChoiceChip(
                              label: Text(r),
                              selected: _repeat == r,
                              selectedColor: tkGreen.withValues(alpha: 0.2),
                              labelStyle: TextStyle(color: _repeat == r ? tkGreen : null, fontWeight: FontWeight.w600),
                              onSelected: (_) => setState(() => _repeat = r),
                            ))
                        .toList(),
                  ),
                ] else ...[
                  Center(
                    child: SizedBox(
                      height: 140,
                      child: CupertinoTheme(
                        data: CupertinoThemeData(
                          textTheme: CupertinoTextThemeData(pickerTextStyle: TextStyle(color: textMain, fontSize: 20)),
                        ),
                        child: CupertinoTimerPicker(
                          mode: CupertinoTimerPickerMode.hm,
                          initialTimerDuration: _countdownDuration,
                          onTimerDurationChanged: (d) => _countdownDuration = d,
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tkGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: Text(_isEditing ? t.text('save_changes') : (_isCountdown ? t.text('start_countdown') : t.text('add_schedule'))),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
