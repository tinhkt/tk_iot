import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/automation_provider.dart';
import '../providers/device_provider.dart';
import 'glass_popup.dart';

/// scene_step_pickers — Bộ picker chọn Hành động (THÌ) / Điều kiện (NẾU) THẬT cho
/// màn tạo/sửa Ngữ cảnh. Đầu ra là SceneStep có params đúng khuôn Backend:
///   Hành động thiết bị : {"mac", "endpoint", "action": "set|speed", "value": "ON|OFF|0..3"}
///   Điều kiện thời gian: {"type": "time", "time": "HH:MM", "repeat": "daily|..."}
///   Điều kiện thiết bị : {"type": "device_state", "mac", "endpoint", "state": "ON|OFF"}
///   Điều kiện cảm biến : {"type": "sensor", "mac", "endpoint", "attribute": "temperature|humidity|speed", "operator": ">|<|==", "value": 30}
///   Điều kiện thời tiết: {"type": "weather", "condition": "temp|rain", "operator", "value"}
///
/// [TÁCH NGỮ CẢNH NẾU/THÌ] _pickEndpoint có 2 chế độ:
///   forTrigger=false (THÌ)  : CHỈ thiết bị điều khiển được (relay, quạt) — loại cảm biến.
///   forTrigger=true  (NẾU)  : TẤT CẢ nguồn kích hoạt — thêm cảm biến môi trường
///                             (DHT11...), chọn xong sinh UI thuộc tính động (Nhiệt độ/Độ ẩm
///                             + toán tử + ngưỡng) khớp Sensor Trigger Engine phía Backend.
///
/// RESPONSIVE: Mobile (≤600) = BottomSheet kính mờ kéo từ dưới (isScrollControlled,
/// khóa vuốt-tắt); PC/Web (>600) = Dialog kính mờ nổi giữa màn hình (barrier khóa,
/// chỉ đóng bằng nút X). Mọi tầng đều đi qua MỘT khung _GlassPanel duy nhất.

const Color _tkGreen = Color(0xFF00A651);

/// Các lựa chọn lặp lại của điều kiện thời gian: (nhãn hiển thị, mã gửi Backend).
const List<(String, String)> kRepeatOptions = [
  ('Một lần', 'once'),
  ('Hàng ngày', 'daily'),
  ('T2 - T6', 'mon-fri'),
  ('Cuối tuần', 'weekend'),
];

// ============================================================================
// 🪟 PRESENTER — ủy quyền hoàn toàn cho showGlassPopup dùng chung toàn App
// (glass_popup.dart: >600px = Dialog giữa màn hình, ≤600px = BottomSheet;
// panel tự ép tương phản chữ/icon trên nền kính)
// ============================================================================
Future<T?> _showGlassPicker<T>(BuildContext context, {required String title, required WidgetBuilder body}) =>
    showGlassPopup<T>(context, title: title, body: body);

// ============================================================================
// 🔌 TẦNG DÙNG CHUNG: CHỌN THIẾT BỊ/KÊNH + CHỌN ON/OFF
// ============================================================================

/// Một endpoint đã phẳng hóa từ kho DPS (mỗi kênh/cảm biến một dòng).
class _EndpointOption {
  final String mac;
  final String endpoint;
  final String name;
  final bool online;
  final bool isFan;    // true -> UI chọn Tốc độ (Số 1/2/3) thay vì chỉ Bật/Tắt
  final bool isSensor; // true -> UI chọn thuộc tính (Nhiệt độ/Độ ẩm + toán tử + ngưỡng)
  final String? reading; // số đo hiện tại của cảm biến (hiển thị tham khảo)
  const _EndpointOption({required this.mac, required this.endpoint, required this.name, required this.online, this.isFan = false, this.isSensor = false, this.reading});
}

/// Tầng chọn thiết bị/kênh — DÙNG CHUNG cho Action lẫn Condition.
/// [forTrigger] quyết định bộ lọc: false (THÌ) = chỉ thiết bị điều khiển được;
/// true (NẾU) = thêm cả cảm biến môi trường làm nguồn kích hoạt.
/// Danh sách nằm trong ListView.builder + Flexible của GlassPopupPanel (trần 0.75/0.8
/// chiều cao màn hình) — danh sách dài tự cuộn, không bao giờ tràn đáy.
Future<_EndpointOption?> _pickEndpoint(BuildContext context, {required String title, bool forTrigger = false}) {
  final devices = Provider.of<DeviceProvider>(context, listen: false).devices;
  final options = <_EndpointOption>[];
  devices.forEach((mac, d) {
    final String last4 = mac.length >= 4 ? mac.substring(mac.length - 4) : mac;
    String displayName(String ep, String fallback) {
      final String? backendName = d.nameOf(ep);
      return (backendName != null && backendName.trim().isNotEmpty) ? backendName : fallback;
    }

    // ---- KÊNH ĐIỀU KHIỂN ĐƯỢC (relay/quạt) — có mặt ở CẢ HAI chế độ ----
    for (final ep in d.endpointIds) {
      if (d.typeOf(ep) == 'sensor') continue; // cảm biến xử lý riêng bên dưới
      // Quạt: Backend gắn type "fan" HOẶC endpoint có khóa tốc độ (_speed) -> render UI Tốc độ
      final bool isFan = d.typeOf(ep) == 'fan' || d.dps.containsKey('${ep}_speed');
      options.add(_EndpointOption(mac: mac, endpoint: ep, name: displayName(ep, '$ep · $last4'), online: d.online, isFan: isFan));
    }

    // ---- CẢM BIẾN MÔI TRƯỜNG — CHỈ chế độ NẾU (trigger) ----
    // Endpoint cảm biến KHÔNG có dps trần (không state ON/OFF) nên không nằm trong
    // endpointIds — nhận diện qua khóa phụ *_type == 'sensor' hoặc có số đo *_temperature/_humidity.
    if (forTrigger) {
      final sensorIds = <String>{};
      d.dps.forEach((k, v) {
        if (k.endsWith('_type') && v?.toString() == 'sensor') sensorIds.add(k.substring(0, k.length - 5));
        if (k.endsWith('_temperature')) sensorIds.add(k.substring(0, k.length - 12));
        if (k.endsWith('_humidity')) sensorIds.add(k.substring(0, k.length - 9));
      });
      for (final ep in sensorIds) {
        final String? t = d.telemetryOf(ep, 'temperature');
        final String? h = d.telemetryOf(ep, 'humidity');
        final String reading = [if (t != null) '$t°C', if (h != null) '$h%'].join(' • ');
        options.add(_EndpointOption(
          mac: mac, endpoint: ep, name: displayName(ep, 'Cảm biến · $last4'),
          online: d.online, isSensor: true, reading: reading.isEmpty ? null : reading,
        ));
      }
    }
  });
  options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return _showGlassPicker<_EndpointOption>(
    context,
    title: title,
    body: (ctx) {
      final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
      // [CHUẨN CONTRAST TRÊN KÍNH] Main: white / black87 (w600) — Sub: white70 / black54
      // (đọc rõ nhưng không tranh chấp với tiêu đề). Không bao giờ nhạt hơn các mốc này.
      final Color textMain = isDark ? Colors.white : Colors.black87;
      final Color textSub = isDark ? Colors.white70 : Colors.black54;

      // Empty State thân thiện — thông điệp đúng theo ngữ cảnh NẾU/THÌ
      if (options.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.devices_other_rounded, size: 56, color: textSub.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
                forTrigger
                    ? 'Chưa có thiết bị hay cảm biến nào làm điều kiện được.\nHãy thêm thiết bị vào nhà trước nhé.'
                    : 'Chưa có thiết bị nào điều khiển được.\nHãy thêm thiết bị vào nhà trước nhé.',
                textAlign: TextAlign.center, style: TextStyle(color: textSub)),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: _tkGreen, side: const BorderSide(color: _tkGreen), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đã hiểu'),
            ),
          ]),
        );
      }

      return ListView.builder(
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (_, i) {
          final o = options[i];
          // Icon theo bản chất nguồn: cảm biến / quạt / công tắc
          final IconData leadIcon = o.isSensor ? Icons.thermostat : (o.isFan ? Icons.air : Icons.lightbulb_outline);
          // Cảm biến: ưu tiên khoe số đo hiện tại thay cho chuỗi MAC khô khan
          final String subtitle = o.isSensor && o.reading != null ? 'Đang đo: ${o.reading}' : '${o.mac} • ${o.endpoint}';
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _tkGreen.withValues(alpha: 0.15),
              child: Icon(leadIcon, color: _tkGreen, size: 20),
            ),
            title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textSub, fontSize: 11.5)),
            // Chấm trạng thái chỉ để tham khảo — thiết bị offline vẫn chọn được
            // (ngữ cảnh chạy sau này, lúc đó thiết bị có thể đã online lại)
            trailing: Icon(Icons.circle, size: 10, color: o.online ? _tkGreen : textSub.withValues(alpha: 0.4)),
            onTap: () => Navigator.pop(ctx, o),
          );
        },
      );
    },
  );
}

/// Tầng chọn BẬT/TẮT — dùng chung cho lệnh hành động lẫn trạng thái điều kiện.
Future<String?> _pickOnOff(BuildContext context, {required String title}) {
  return _showGlassPicker<String>(
    context,
    title: title,
    body: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.power_settings_new),
            label: const Text('BẬT', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, 'ON'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.power_off),
            label: const Text('TẮT', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, 'OFF'),
          ),
        ),
      ]),
    ),
  );
}

/// ListTile chuẩn cho các tầng menu lựa chọn.
Widget _optionTile(BuildContext ctx, {required IconData icon, required String title, String? subtitle, required VoidCallback onTap}) {
  final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
  // [CHUẨN CONTRAST TRÊN KÍNH] — đồng bộ với danh sách thiết bị (main w600, sub white70/black54)
  final Color textMain = isDark ? Colors.white : Colors.black87;
  final Color textSub = isDark ? Colors.white70 : Colors.black54;
  return ListTile(
    leading: Icon(icon, color: _tkGreen),
    title: Text(title, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
    subtitle: subtitle == null ? null : Text(subtitle, style: TextStyle(color: textSub, fontSize: 12)),
    onTap: onTap,
  );
}

// ============================================================================
// 🎬 ACTION PICKER (THÌ...) — thiết bị thật -> endpoint -> BẬT/TẮT
// ============================================================================

/// Trả về SceneStep hoàn chỉnh (label tự sinh + params chuẩn Fan-out), null nếu thoát.
Future<SceneStep?> showActionPicker(BuildContext context) async {
  final Object? choice = await _showGlassPicker<Object>(
    context,
    title: 'Chọn hành động (THÌ...)',
    body: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      _optionTile(ctx, icon: Icons.settings_remote, title: 'Điều khiển thiết bị',
          subtitle: 'Bật/Tắt một thiết bị thật trong nhà', onTap: () => Navigator.pop(ctx, 'device')),
      _optionTile(ctx, icon: Icons.notifications_active_outlined, title: 'Gửi thông báo',
          onTap: () => Navigator.pop(ctx, const SceneStep(Icons.notifications_active_outlined, 'Gửi thông báo'))),
      _optionTile(ctx, icon: Icons.timelapse, title: 'Chờ (Delay)',
          onTap: () => Navigator.pop(ctx, const SceneStep(Icons.timelapse, 'Chờ (Delay)'))),
    ]),
  );
  if (choice is SceneStep) return choice;
  if (choice != 'device' || !context.mounted) return null;

  final _EndpointOption? picked = await _pickEndpoint(context, title: 'Chọn thiết bị');
  if (picked == null || !context.mounted) return null;

  // [UI ĐỘNG THEO LOẠI THIẾT BỊ] Quạt -> chọn Tốc độ (Số 1/2/3); còn lại -> Bật/Tắt.
  // Tương lai mở rộng dimmer (độ sáng) / điều hòa (nhiệt độ) theo cùng khuôn action/value.
  if (picked.isFan) {
    return _pickFanAction(context, picked);
  }

  final String? command = await _pickOnOff(context, title: picked.name);
  if (command == null) return null;

  final String verb = command == 'ON' ? 'Bật' : 'Tắt';
  return SceneStep(
    Icons.power_settings_new,
    '$verb ${picked.name}',
    // Khuôn lệnh LINH HOẠT {action,value} — Backend fan-out bắn nguyên khối xuống firmware
    params: {'mac': picked.mac, 'endpoint': picked.endpoint, 'action': 'set', 'value': command},
  );
}

/// Chọn hành động cho QUẠT: Tắt / Số 1 / Số 2 / Số 3 -> params {action:"speed", value:"0..3"}.
Future<SceneStep?> _pickFanAction(BuildContext context, _EndpointOption picked) async {
  const List<(int, String)> speeds = [(0, 'Tắt'), (1, 'Số 1'), (2, 'Số 2'), (3, 'Số 3')];
  final int? speed = await _showGlassPicker<int>(
    context,
    title: 'Tốc độ ${picked.name}',
    body: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: speeds
          .map((s) => _optionTile(ctx,
              icon: s.$1 == 0 ? Icons.power_off : Icons.air,
              title: s.$2,
              onTap: () => Navigator.pop(ctx, s.$1)))
          .toList(),
    ),
  );
  if (speed == null) return null;

  final String label = speed == 0 ? 'Tắt ${picked.name}' : 'Bật ${picked.name} — Số $speed';
  return SceneStep(
    Icons.air,
    label,
    params: {'mac': picked.mac, 'endpoint': picked.endpoint, 'action': 'speed', 'value': '$speed'},
  );
}

// ============================================================================
// ⏱️ CONDITION PICKER (NẾU...) — Thời gian / Thiết bị đổi trạng thái / Thời tiết
// ============================================================================

/// Trả về SceneStep điều kiện với params có "type" phân loại, null nếu thoát.
Future<SceneStep?> showConditionPicker(BuildContext context) async {
  final String? kind = await _showGlassPicker<String>(
    context,
    title: 'Chọn điều kiện (NẾU...)',
    body: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      _optionTile(ctx, icon: Icons.access_time, title: 'Theo thời gian',
          subtitle: 'Chạy vào một giờ cố định trong ngày', onTap: () => Navigator.pop(ctx, 'time')),
      _optionTile(ctx, icon: Icons.toggle_on, title: 'Thiết bị thay đổi trạng thái',
          subtitle: 'Công tắc BẬT/TẮT, hoặc cảm biến vượt ngưỡng nhiệt độ/độ ẩm',
          onTap: () => Navigator.pop(ctx, 'device_state')),
      _optionTile(ctx, icon: Icons.cloud, title: 'Thời tiết thay đổi',
          subtitle: 'Nhiệt độ vượt ngưỡng hoặc trời mưa', onTap: () => Navigator.pop(ctx, 'weather')),
    ]),
  );
  if (kind == null || !context.mounted) return null;

  switch (kind) {
    case 'time':
      return _pickTimeCondition(context);
    case 'device_state':
      return _pickDeviceStateCondition(context);
    case 'weather':
      return _pickWeatherCondition(context);
  }
  return null;
}

/// NẾU theo thời gian: TimePicker Material -> chọn lặp lại.
Future<SceneStep?> _pickTimeCondition(BuildContext context) async {
  final TimeOfDay? time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 7, minute: 0));
  if (time == null || !context.mounted) return null;

  final (String, String)? repeat = await _showGlassPicker<(String, String)>(
    context,
    title: 'Lặp lại',
    body: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: kRepeatOptions
          .map((r) => _optionTile(ctx, icon: Icons.event_repeat, title: r.$1, onTap: () => Navigator.pop(ctx, r)))
          .toList(),
    ),
  );
  if (repeat == null) return null;

  final String hhmm = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  return SceneStep(
    Icons.access_time,
    'Lúc $hhmm • ${repeat.$1}',
    params: {'type': 'time', 'time': hhmm, 'repeat': repeat.$2},
  );
}

/// NẾU thiết bị đổi trạng thái: chọn nguồn kích hoạt (forTrigger=true — CÓ cảm biến)
/// -> UI thuộc tính động theo bản chất nguồn: cảm biến = Nhiệt độ/Độ ẩm + toán tử +
/// ngưỡng; công tắc/quạt = trạng thái BẬT/TẮT.
Future<SceneStep?> _pickDeviceStateCondition(BuildContext context) async {
  final _EndpointOption? picked = await _pickEndpoint(context, title: 'Thiết bị nào thay đổi?', forTrigger: true);
  if (picked == null || !context.mounted) return null;

  // [DYNAMIC ATTRIBUTES] UI thuộc tính sinh theo bản chất nguồn kích hoạt
  if (picked.isSensor) {
    return _pickSensorCondition(context, picked); // Nhiệt độ/Độ ẩm + toán tử + ngưỡng nhập tay
  }
  if (picked.isFan) {
    return _pickFanTriggerCondition(context, picked); // BẬT/TẮT hoặc "ở đúng Số N"
  }

  final String? state = await _pickOnOff(context, title: 'Khi "${picked.name}" chuyển sang...');
  if (state == null) return null;

  return SceneStep(
    Icons.toggle_on,
    'Khi ${picked.name} ${state == 'ON' ? 'BẬT' : 'TẮT'}',
    params: {'type': 'device_state', 'mac': picked.mac, 'endpoint': picked.endpoint, 'state': state},
  );
}

/// Các toán tử so sánh của điều kiện cảm biến: (mã gửi Backend, nhãn hiển thị).
const List<(String, String)> kSensorOperators = [
  ('>', 'Lớn hơn  ( > )'),
  ('<', 'Nhỏ hơn  ( < )'),
  ('==', 'Bằng  ( == )'),
];

/// Định dạng số gọn: 30.0 -> "30", 30.5 -> "30.5".
String _fmtNum(num v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

/// [DYNAMIC ATTRIBUTES] NẾU cảm biến vượt ngưỡng — form 3 tầng theo spec:
///   1. Chip Thuộc tính (DPS) — SINH ĐỘNG theo số đo thiết bị thật đang báo
///      (temperature/humidity; thiết bị tương lai báo thêm trường nào sẽ tự mọc chip đó).
///   2. Dropdown Toán tử: Lớn hơn (>) / Nhỏ hơn (<) / Bằng (==).
///   3. TextField SỐ TỰ DO (keyboardType number) — user gõ ngưỡng bất kỳ, prefill số đo hiện tại.
/// Params khớp Sensor Trigger Engine (edge-trigger) phía Backend:
/// {"type":"sensor","mac","endpoint","attribute":"temperature|humidity","operator":">|<|==","value":N}
Future<SceneStep?> _pickSensorCondition(BuildContext context, _EndpointOption picked) async {
  final d = Provider.of<DeviceProvider>(context, listen: false).deviceOf(picked.mac);
  String? currentOf(String attr) => d?.telemetryOf(picked.endpoint, attr);

  // Bộ thuộc tính khả dụng: (id, nhãn, icon, đơn vị, ngưỡng mặc định)
  var attrs = <(String, String, IconData, String, double)>[
    if (currentOf('temperature') != null) ('temperature', 'Nhiệt độ', Icons.thermostat, '°C', 30),
    if (currentOf('humidity') != null) ('humidity', 'Độ ẩm', Icons.water_drop, '%', 80),
  ];
  // Cảm biến vừa cắm chưa báo số đo nào: vẫn cho cấu hình đủ 2 thuộc tính chuẩn DHT11
  if (attrs.isEmpty) {
    attrs = [
      ('temperature', 'Nhiệt độ', Icons.thermostat, '°C', 30),
      ('humidity', 'Độ ẩm', Icons.water_drop, '%', 80),
    ];
  }

  final Map<String, dynamic>? result = await _showGlassPicker<Map<String, dynamic>>(
    context,
    title: 'Điều kiện cho "${picked.name}"',
    body: (ctx) {
      final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
      final Color textMain = isDark ? Colors.white : Colors.black87;
      final Color hintColor = isDark ? Colors.white70 : Colors.black54;

      var selected = attrs.first;
      String operator = '>';
      String? errorText;
      // Prefill = số đo hiện tại (nếu có) — user thấy ngay bối cảnh để đặt ngưỡng
      final controller = TextEditingController(
          text: currentOf(selected.$1) ?? _fmtNum(selected.$5));

      Widget chip({required String label, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
        return Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? _tkGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isSelected ? _tkGreen : textMain.withValues(alpha: 0.25)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: isSelected ? Colors.white : textMain),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: isSelected ? Colors.white : textMain, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
      }

      InputBorder fieldBorder(Color c) =>
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c));

      return StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // ---- 1. THUỘC TÍNH (DPS) — sinh động theo số đo thật ----
            Row(children: [
              for (int i = 0; i < attrs.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                chip(
                  label: attrs[i].$2, icon: attrs[i].$3, isSelected: selected.$1 == attrs[i].$1,
                  onTap: () => setSheet(() {
                    selected = attrs[i];
                    controller.text = currentOf(selected.$1) ?? _fmtNum(selected.$5);
                    errorText = null;
                  }),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            // ---- 2. DROPDOWN TOÁN TỬ ----
            DropdownButtonFormField<String>(
              initialValue: operator,
              // Nền menu thả xuống phải ĐẶC (không kính) để item luôn đọc được
              dropdownColor: isDark ? const Color(0xFF2A2D31) : Colors.white,
              style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Phép so sánh',
                labelStyle: TextStyle(color: hintColor),
                enabledBorder: fieldBorder(textMain.withValues(alpha: 0.25)),
                focusedBorder: fieldBorder(_tkGreen),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              ),
              items: kSensorOperators
                  .map((op) => DropdownMenuItem(value: op.$1, child: Text(op.$2)))
                  .toList(),
              onChanged: (v) => setSheet(() => operator = v ?? '>'),
            ),
            const SizedBox(height: 12),
            // ---- 3. INPUT GIÁ TRỊ TỰ DO ----
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Ngưỡng ${selected.$2.toLowerCase()}',
                labelStyle: TextStyle(color: hintColor),
                suffixText: selected.$4,
                suffixStyle: TextStyle(color: textMain.withValues(alpha: 0.7), fontSize: 18, fontWeight: FontWeight.w700),
                helperText: currentOf(selected.$1) != null ? 'Đang đo: ${currentOf(selected.$1)}${selected.$4}' : null,
                helperStyle: TextStyle(color: hintColor, fontSize: 12),
                errorText: errorText,
                enabledBorder: fieldBorder(textMain.withValues(alpha: 0.25)),
                focusedBorder: fieldBorder(_tkGreen),
                errorBorder: fieldBorder(Colors.redAccent),
                focusedErrorBorder: fieldBorder(Colors.redAccent),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  final num? value = num.tryParse(controller.text.trim().replaceAll(',', '.'));
                  if (value == null) {
                    setSheet(() => errorText = 'Hãy nhập một con số hợp lệ (vd: 30 hoặc 30.5)');
                    return;
                  }
                  Navigator.pop(ctx, {'attribute': selected.$1, 'operator': operator, 'value': value, 'label': selected.$2, 'unit': selected.$4});
                },
                child: const Text('Dùng điều kiện này', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
    },
  );
  if (result == null) return null;

  return SceneStep(
    result['attribute'] == 'humidity' ? Icons.water_drop : Icons.thermostat,
    'Khi ${picked.name}: ${result['label']} ${result['operator']} ${_fmtNum(result['value'] as num)}${result['unit']}',
    params: {
      'type': 'sensor',
      'mac': picked.mac,
      'endpoint': picked.endpoint,
      'attribute': result['attribute'],
      'operator': result['operator'],
      'value': result['value'],
    },
  );
}

/// [DYNAMIC ATTRIBUTES] NẾU cho QUẠT: hoặc trạng thái BẬT/TẮT (device_state hook),
/// hoặc "đang ở đúng tốc độ N" (đi qua Sensor Trigger Engine với attribute:"speed",
/// operator:"==" — backend bắn hook speed kèm mỗi gói state feedback của quạt).
Future<SceneStep?> _pickFanTriggerCondition(BuildContext context, _EndpointOption picked) async {
  final String? mode = await _showGlassPicker<String>(
    context,
    title: 'Điều kiện cho "${picked.name}"',
    body: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      _optionTile(ctx, icon: Icons.power_settings_new, title: 'Trạng thái BẬT/TẮT',
          subtitle: 'Khi quạt được bật hoặc tắt hẳn', onTap: () => Navigator.pop(ctx, 'state')),
      _optionTile(ctx, icon: Icons.air, title: 'Chuyển sang tốc độ...',
          subtitle: 'Khi quạt vào đúng Số 1 / 2 / 3', onTap: () => Navigator.pop(ctx, 'speed')),
    ]),
  );
  if (mode == null || !context.mounted) return null;

  if (mode == 'state') {
    final String? state = await _pickOnOff(context, title: 'Khi "${picked.name}" chuyển sang...');
    if (state == null) return null;
    return SceneStep(
      Icons.toggle_on,
      'Khi ${picked.name} ${state == 'ON' ? 'BẬT' : 'TẮT'}',
      params: {'type': 'device_state', 'mac': picked.mac, 'endpoint': picked.endpoint, 'state': state},
    );
  }

  final int? speed = await _showGlassPicker<int>(
    context,
    title: 'Khi "${picked.name}" ở tốc độ...',
    body: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [1, 2, 3]
          .map((s) => _optionTile(ctx, icon: Icons.air, title: 'Số $s', onTap: () => Navigator.pop(ctx, s)))
          .toList(),
    ),
  );
  if (speed == null) return null;

  return SceneStep(
    Icons.air,
    'Khi ${picked.name} ở Số $speed',
    params: {'type': 'sensor', 'mac': picked.mac, 'endpoint': picked.endpoint, 'attribute': 'speed', 'operator': '==', 'value': speed},
  );
}

/// NẾU thời tiết: Nhiệt độ cao/thấp hơn ngưỡng (slider chọn °C) hoặc Trời có mưa.
Future<SceneStep?> _pickWeatherCondition(BuildContext context) async {
  final String? kind = await _showGlassPicker<String>(
    context,
    title: 'Thời tiết thay đổi',
    body: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      _optionTile(ctx, icon: Icons.thermostat, title: 'Nhiệt độ CAO hơn ngưỡng',
          subtitle: 'vd: nóng quá 30°C thì bật quạt', onTap: () => Navigator.pop(ctx, 'temp_gt')),
      _optionTile(ctx, icon: Icons.thermostat, title: 'Nhiệt độ THẤP hơn ngưỡng',
          subtitle: 'vd: lạnh dưới 20°C thì tắt quạt', onTap: () => Navigator.pop(ctx, 'temp_lt')),
      _optionTile(ctx, icon: Icons.cloud, title: 'Trời có mưa',
          subtitle: 'Kích hoạt khi khu vực bắt đầu mưa', onTap: () => Navigator.pop(ctx, 'rain')),
    ]),
  );
  if (kind == null || !context.mounted) return null;

  if (kind == 'rain') {
    return const SceneStep(
      Icons.cloud,
      'Trời có mưa',
      params: {'type': 'weather', 'condition': 'rain', 'operator': '=', 'value': 'rain'},
    );
  }

  // Chọn ngưỡng nhiệt độ bằng slider (10-45°C, mặc định 30)
  final int? temp = await _showGlassPicker<int>(
    context,
    title: kind == 'temp_gt' ? 'Nóng hơn bao nhiêu độ?' : 'Lạnh dưới bao nhiêu độ?',
    body: (ctx) {
      double value = 30;
      return StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${value.round()}°C', style: TextStyle(color: _tkGreen, fontSize: 40, fontWeight: FontWeight.w900)),
            Slider(
              value: value, min: 10, max: 45, divisions: 35,
              activeColor: _tkGreen,
              label: '${value.round()}°C',
              onChanged: (v) => setSheet(() => value = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () => Navigator.pop(ctx, value.round()),
                child: const Text('Chọn ngưỡng này', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
    },
  );
  if (temp == null) return null;

  final String op = kind == 'temp_gt' ? '>' : '<';
  return SceneStep(
    Icons.thermostat,
    'Nhiệt độ $op $temp°C',
    params: {'type': 'weather', 'condition': 'temp', 'operator': op, 'value': temp},
  );
}
