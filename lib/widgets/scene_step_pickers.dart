import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/automation_provider.dart';
import '../providers/device_provider.dart';
import 'glass_popup.dart';

/// scene_step_pickers — Bộ picker chọn Hành động (THÌ) / Điều kiện (NẾU) THẬT cho
/// màn tạo/sửa Ngữ cảnh. Đầu ra là SceneStep có params đúng khuôn Backend:
///   Hành động thiết bị : {"mac", "endpoint", "command": "ON|OFF"}
///   Điều kiện thời gian: {"type": "time", "time": "HH:MM", "repeat": "daily|..."}
///   Điều kiện thiết bị : {"type": "device_state", "mac", "endpoint", "state": "ON|OFF"}
///   Điều kiện thời tiết: {"type": "weather", "condition": "temp|rain", "operator", "value"}
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

/// Một endpoint điều khiển được, đã phẳng hóa từ kho DPS (mỗi kênh một dòng).
class _EndpointOption {
  final String mac;
  final String endpoint;
  final String name;
  final bool online;
  final bool isFan; // true -> hiện thêm bước chọn Tốc độ (Số 1/2/3) thay vì chỉ Bật/Tắt
  const _EndpointOption({required this.mac, required this.endpoint, required this.name, required this.online, this.isFan = false});
}

/// Tầng chọn thiết bị/kênh — DÙNG CHUNG cho Action lẫn Condition 'device_state'.
/// Danh sách nằm trong ListView.builder + Flexible của _GlassPanel (trần 0.72/0.75
/// chiều cao màn hình) — danh sách dài tự cuộn, không bao giờ tràn đáy.
Future<_EndpointOption?> _pickEndpoint(BuildContext context, {required String title}) {
  final devices = Provider.of<DeviceProvider>(context, listen: false).devices;
  final options = <_EndpointOption>[];
  devices.forEach((mac, d) {
    for (final ep in d.endpointIds) {
      if (d.typeOf(ep) == 'sensor') continue; // cảm biến không điều khiển được
      final String last4 = mac.length >= 4 ? mac.substring(mac.length - 4) : mac;
      final String? backendName = d.nameOf(ep);
      final String name = (backendName != null && backendName.trim().isNotEmpty) ? backendName : '$ep · $last4';
      // Quạt: Backend gắn type "fan" HOẶC endpoint có khóa tốc độ (_speed) -> render UI Tốc độ
      final bool isFan = d.typeOf(ep) == 'fan' || d.dps.containsKey('${ep}_speed');
      options.add(_EndpointOption(mac: mac, endpoint: ep, name: name, online: d.online, isFan: isFan));
    }
  });
  options.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return _showGlassPicker<_EndpointOption>(
    context,
    title: title,
    body: (ctx) {
      final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
      final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
      final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

      // Empty State thân thiện: nhà chưa có thiết bị điều khiển được
      if (options.isEmpty) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.devices_other_rounded, size: 56, color: textSub.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text('Chưa có thiết bị nào điều khiển được.\nHãy thêm thiết bị vào nhà trước nhé.',
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
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _tkGreen.withValues(alpha: 0.15),
              child: const Icon(Icons.lightbulb_outline, color: _tkGreen, size: 20),
            ),
            title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
            subtitle: Text('${o.mac} • ${o.endpoint}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textSub, fontSize: 11)),
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
  final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
  final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
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
          subtitle: 'Khi một thiết bị BẬT hoặc TẮT', onTap: () => Navigator.pop(ctx, 'device_state')),
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

/// NẾU thiết bị đổi trạng thái: chọn thiết bị/kênh -> trạng thái kích hoạt (ON/OFF).
Future<SceneStep?> _pickDeviceStateCondition(BuildContext context) async {
  final _EndpointOption? picked = await _pickEndpoint(context, title: 'Thiết bị nào thay đổi?');
  if (picked == null || !context.mounted) return null;

  final String? state = await _pickOnOff(context, title: 'Khi "${picked.name}" chuyển sang...');
  if (state == null) return null;

  return SceneStep(
    Icons.toggle_on,
    'Khi ${picked.name} ${state == 'ON' ? 'BẬT' : 'TẮT'}',
    params: {'type': 'device_state', 'mac': picked.mac, 'endpoint': picked.endpoint, 'state': state},
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
