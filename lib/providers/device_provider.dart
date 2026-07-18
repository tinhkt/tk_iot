import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/mqtt_service.dart';

// ============================================================================
// 📦 DEVICE MODEL — QUẢN LÝ TRẠNG THÁI ĐỘNG THEO CHUẨN DPS (DATA POINTS)
// ============================================================================
// Mô phỏng kiến trúc thương mại lớn (Tuya): thay vì đóng cứng từng thuộc tính
// (power, speed, swing...) vào model, mọi trạng thái được lưu trong một Map
// `dps` linh hoạt. Nhờ đó thêm loại thiết bị mới (rèm, đèn RGB, cảm biến...)
// KHÔNG cần sửa model — chỉ cần thêm khóa dps mới.
//
// Quy ước khóa dps trong hệ sinh thái này:
//   "S_ABCD1234"        : trạng thái công tắc ("ON"/"OFF")
//   "S_ABCD1234_2"      : kênh 2 của công tắc nhiều kênh ("ON"/"OFF")
//   "D1", "F1"          : thiết bị/quạt trên Smart Hub V38 ("ON"/"OFF")
//   "F1_speed"          : tốc độ quạt (int 0-3)
//   "F1_swing"          : trạng thái đảo gió (bool)
//   "S_XXXX_name"       : tên hiển thị do Backend/Hub gửi kèm (String)
//   "S_XXXX_type"       : nhóm thiết bị do Backend gắn ("fan" | "switch") — UI dựa
//                         vào đây để chọn thẻ SmartFanCard hay SmartSwitchCard
class DeviceModel {
  /// Địa chỉ MAC đã chuẩn hóa (bỏ dấu ":", viết HOA) — dùng làm khóa định danh duy nhất
  final String mac;

  /// Kho trạng thái động (Data Points) — trái tim của model
  final Map<String, dynamic> dps;

  /// Thiết bị còn phát tín hiệu hay không (cập nhật khi có gói tin MQTT mới)
  bool online;

  /// Dấu thời gian của gói tin cuối cùng — tiện cho việc hiển thị "Cập nhật x giây trước"
  DateTime lastUpdated;

  DeviceModel({
    required this.mac,
    Map<String, dynamic>? dps,
    this.online = true,
    DateTime? lastUpdated,
  })  : dps = dps ?? {},
        lastUpdated = lastUpdated ?? DateTime.now();

  // --------------------------------------------------------------------------
  // 🛡️ BỘ GIẢI MÃ JSON AN TOÀN — CHỐNG CRASH TUYỆT ĐỐI
  // --------------------------------------------------------------------------
  /// Firmware/Broker có thể gửi gói tin lỗi (JSON cụt, payload rác, chuỗi rỗng).
  /// Hàm này bảo đảm KHÔNG BAO GIỜ ném exception ra ngoài:
  /// trả về Map nếu giải mã được, ngược lại trả về null để nơi gọi tự bỏ qua.
  static Map<String, dynamic>? safeDecode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      return null; // JSON hợp lệ nhưng không phải object (vd: mảng, số) -> bỏ qua
    } catch (e) {
      if (kDebugMode) print('🛡️ [DPS] Payload không phải JSON hợp lệ, bỏ qua: $e');
      return null;
    }
  }

  /// Gộp một loạt giá trị mới vào kho dps (chỉ ghi đè khóa được gửi lên,
  /// giữ nguyên các khóa còn lại). Trả về true nếu có ít nhất 1 thay đổi thật sự
  /// — để Provider quyết định có cần vẽ lại UI hay không.
  ///
  /// [QUY TẮC THÉP Ở MỨC NHÂN — PHÂN QUYỀN TÊN] mergeDps mặc định TỪ CHỐI mọi khóa
  /// tên ("name" / "*_name"): dù update đến từ MQTT, echo lệnh, optimistic update
  /// hay bất kỳ luồng nào thêm sau này, tên hiển thị KHÔNG THỂ bị ghi đè — quên
  /// truyền cờ là bị chặn, không thể "lọt lưới". DUY NHẤT luồng HTTP Sync
  /// (hydrateFromRest / fetchDeviceState) được mở khóa qua [allowNameKeys]=true:
  /// HTTP quản lý Tên, mọi luồng khác chỉ quản lý trạng thái vật lý.
  bool mergeDps(Map<String, dynamic> updates, {bool allowNameKeys = false}) {
    if (!allowNameKeys) {
      updates.removeWhere((k, _) => k == 'name' || k.endsWith('_name'));
    }
    bool changed = false;
    updates.forEach((key, value) {
      if (dps[key] != value) {
        dps[key] = value;
        changed = true;
      }
    });
    if (changed) {
      online = true;
      lastUpdated = DateTime.now();
    }
    return changed;
  }

  // ----- CÁC GETTER TIỆN ÍCH ĐỂ UI ĐỌC NHANH, KHỎI TỰ BÓC dps -----

  /// Trạng thái bật/tắt của một endpoint: dps["F1"] == "ON"
  bool isOn(String endpoint) => dps[endpoint]?.toString().toUpperCase() == 'ON';

  /// Tốc độ quạt của một endpoint (0 nếu chưa có dữ liệu)
  int speedOf(String endpoint) =>
      int.tryParse(dps['${endpoint}_speed']?.toString() ?? '') ?? 0;

  /// Trạng thái đảo gió (túp năng) của một endpoint
  bool isSwinging(String endpoint) => dps['${endpoint}_swing'] == true;

  /// Tên hiển thị của endpoint (null nếu Backend chưa gửi tên)
  String? nameOf(String endpoint) => dps['${endpoint}_name']?.toString();

  /// [DISPLAY NAME — NGUỒN DUY NHẤT] Tên cấp THIẾT BỊ: quét các khóa *_name trong kho
  /// DPS (REST overlay đã đặt tên NGƯỜI DÙNG lên trước tên tự sinh — hash device_names
  /// thắng tuyệt đối) theo thứ tự khóa ổn định, lấy tên đầu tiên không rỗng.
  /// null = thiết bị chưa từng có tên nào trong DPS.
  String? get primaryName {
    final keys = dps.keys.where((k) => k.endsWith('_name') && !k.startsWith('__')).toList()..sort();
    for (final k in keys) {
      final v = dps[k]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// Tên hiển thị CHỐT cho mọi danh sách thiết bị (sửa nhóm, picker, dialog...):
  /// tên user đặt (primaryName) -> [fallback] (vd name cấp thiết bị từ REST) -> "Thiết bị {4 cuối}".
  String displayName([String? fallback]) {
    final n = primaryName;
    if (n != null) return n;
    if (fallback != null && fallback.trim().isNotEmpty) return fallback.trim();
    return 'Thiết bị ${mac.length >= 4 ? mac.substring(mac.length - 4) : mac}';
  }

  /// Nhóm thiết bị của endpoint do Backend gắn: "fan" | "switch" (null nếu chưa biết)
  String? typeOf(String endpoint) => dps['${endpoint}_type']?.toString();

  /// Tiến trình nạp firmware OTA (0-100, -1 khi lỗi, null khi không nạp)
  int? get otaProgress => (dps['__ota_progress'] as num?)?.toInt();

  /// Mã lỗi OTA hạt nhân, namespace chuẩn hóa `ERR_*` (vd "ERR_SIGNATURE_MISMATCH",
  /// "ERR_HTTP_STATUS_404") — firmware cũ chưa vá có thể còn gửi mã không tiền tố, cả hai
  /// dạng đều được otaErrorMessageVi() chuẩn hóa khi tra cứu. null khi không có lỗi.
  /// Dùng để tra bảng dịch tiếng Việt (kOtaErrorMessages) — KHÔNG hiển thị thẳng ra UI.
  String? get otaErrorCode {
    final v = dps['__ota_error_code']?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Câu gốc từ thư viện firmware (Update.errorString()/HTTPClient::errorToString()) —
  /// hiện kèm bản dịch cho người dùng kỹ thuật/hỗ trợ đối chiếu, không thay thế bản dịch.
  String? get otaErrorDetail {
    final v = dps['__ota_error']?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Số đo môi trường của endpoint cảm biến (null nếu không có)
  String? telemetryOf(String endpoint, String field) =>
      dps['${endpoint}_$field']?.toString();

  /// Liệt kê các endpoint điều khiển được (lọc bỏ khóa phụ _speed/_swing/_name/_type/
  /// _temperature/_humidity và các khóa hệ thống bắt đầu bằng "__" như __ota_progress)
  List<String> get endpointIds => dps.keys
      .where((k) =>
          !k.startsWith('__') &&
          !k.endsWith('_speed') &&
          !k.endsWith('_swing') &&
          !k.endsWith('_name') &&
          !k.endsWith('_type') &&
          !k.endsWith('_temperature') &&
          !k.endsWith('_humidity'))
      .toList();
}

// ============================================================================
// 🧠 DEVICE PROVIDER — BỘ NÃO TRẠNG THÁI TOÀN CỤC (SINGLE SOURCE OF TRUTH)
// ============================================================================
// Nguyên tắc vận hành (chuẩn thương mại):
//   1. REST API chỉ dùng để NẠP LẦN ĐẦU (hydrate) khi mở màn hình.
//   2. Mọi thay đổi sau đó đến từ MQTT -> cập nhật ĐÚNG MỘT thiết bị trong RAM
//      -> notifyListeners() -> UI tự vẽ lại NGAY LẬP TỨC, không gọi lại HTTP.
//   3. Lệnh điều khiển bắn qua Cầu nối Backend (smarthub/{home_id}/{mac}/command)
//      kèm cập nhật lạc quan (optimistic update) để nút gạt phản hồi tức thì.
class DeviceProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final MqttService _mqttService = MqttService();
  final AuthService _authService = AuthService();

  /// Kho thiết bị trong RAM, khóa là MAC đã chuẩn hóa. Đây là nguồn sự thật
  /// duy nhất cho mọi màn hình (Dashboard, chi tiết thiết bị, automation...).
  final Map<String, DeviceModel> _devices = {};

  /// Getter công khai — trả về VIEW chỉ đọc (không copy dữ liệu) để widget
  /// không sửa lén được kho trạng thái mà quên notifyListeners().
  Map<String, DeviceModel> get devices => UnmodifiableMapView(_devices);

  /// Lấy nhanh một thiết bị theo MAC (null nếu chưa từng có tín hiệu)
  DeviceModel? deviceOf(String mac) => _devices[_cleanMac(mac)];

  /// [DISPLAY NAME] Tên hiển thị của thiết bị theo MAC — cửa DUY NHẤT cho mọi UI
  /// danh sách (sửa nhóm, dialog tạo nhóm, picker...). Ưu tiên tên user đặt trong DPS,
  /// rơi về [fallback] (tên cấp thiết bị từ REST), cuối cùng là "Thiết bị {4 cuối MAC}".
  String displayNameOf(String mac, {String? fallback}) {
    final d = _devices[_cleanMac(mac)];
    if (d != null) return d.displayName(fallback);
    if (fallback != null && fallback.trim().isNotEmpty) return fallback.trim();
    final sn = _cleanMac(mac);
    return 'Thiết bị ${sn.length >= 4 ? sn.substring(sn.length - 4) : sn}';
  }

  /// [DISPLAY NAME — ĐÚNG KÊNH] Khác [displayNameOf] (tên CHUNG của cả thiết bị — với máy
  /// nhiều relay, trả về tên của BẤT KỲ endpoint nào tìm thấy trước, không phân biệt kênh):
  /// hàm này tra ĐÚNG tên user đặt cho [endpoint] cụ thể trước (vd "Đèn phòng khách" cho
  /// riêng relay 1, khác "Quạt trần" của relay 2 CÙNG một MAC SSW04). Dùng cho mọi danh sách
  /// gắn với 1 kênh xác định (Lịch trình, Đếm ngược) — sai chỗ này sẽ hiện nhầm tên relay
  /// khác trên cùng thiết bị. Rỗng ở kênh đó -> rơi về [displayNameOf] (tên chung) -> [fallback].
  String displayNameOfEndpoint(String mac, String endpoint, {String? fallback}) {
    final d = _devices[_cleanMac(mac)];
    if (d != null) {
      final epName = endpoint.isNotEmpty ? d.nameOf(endpoint) : null;
      if (epName != null && epName.trim().isNotEmpty) return epName.trim();
      return d.displayName(fallback);
    }
    if (fallback != null && fallback.trim().isNotEmpty) return fallback.trim();
    final sn = _cleanMac(mac);
    return 'Thiết bị ${sn.length >= 4 ? sn.substring(sn.length - 4) : sn}';
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// Kênh chia sẻ gói tin MQTT thô cho các màn hình cần tự xử lý thêm
  /// (Dashboard đang dùng để debounce việc làm mới danh sách nhà).
  Function(String topic, String message)? _globalListener;

  /// Trạng thái sống của kênh MQTT: false = đang đứt/đang nối lại.
  /// Dashboard dựa vào đây để hiện dải trạng thái "Đang kết nối lại máy chủ..."
  bool get brokerOnline => _mqttService.brokerOnline.value;

  DeviceProvider() {
    _initializeMqtt();
    // Kênh MQTT đứt/nối lại là mọi màn hình đang watch biết ngay lập tức
    _mqttService.brokerOnline.addListener(notifyListeners);
  }

  // ==========================================================================
  // 🔌 KHỞI TẠO & ĐỊNH TUYẾN MQTT
  // ==========================================================================

  void setGlobalMqttListener(Function(String topic, String message) callback) {
    _globalListener = callback;
  }

  /// Dashboard gọi trong dispose(): gỡ listener trỏ vào State đã unmount để gói tin
  /// MQTT về trễ không gọi ngược vào widget chết (an toàn vòng đời khi đăng xuất).
  void clearGlobalMqttListener() => _globalListener = null;

  /// Hook do Dashboard đăng ký (trỏ tới _initializeHome) để các nơi KHÔNG giữ context
  /// (vd AutomationProvider sau khi chạy Scene) có thể "ép" App kéo lại trạng thái thật
  /// từ REST — lưới an toàn khi sóng MQTT state feedback về trễ/rớt.
  Future<void> Function()? onRefreshRequested;

  /// Chủ động yêu cầu Dashboard nạp lại trạng thái thiết bị từ Server (no-op nếu chưa
  /// đăng ký hook, vd đang ở màn Login).
  Future<void> requestRefresh() async => onRefreshRequested?.call();

  /// Dashboard gọi sau khi đăng nhập thành công: lúc app khởi động chưa có token
  /// nên kết nối trong constructor bị bỏ qua, cần kích hoạt lại với credentials mới.
  Future<void> connectMqtt() => _mqttService.connect();

  void _initializeMqtt() {
    _mqttService.onMessageReceived = (topic, message) {
      // 1. Chia sẻ gói tin thô cho listener toàn cục (nếu có màn hình đăng ký)
      _globalListener?.call(topic, message);

      // 2. Bóc MAC từ topic rồi giao cho bộ máy cập nhật RAM xử lý.
      //    Các dạng topic trong hệ sinh thái:
      //    - smarthub/{home_id}/{MAC}/state          (Bridge phát lại, payload JSON map)
      //    - smarthub/{MAC}/{endpoint}/state          (Hub V38 kiểu Hass, payload "ON"/"OFF")
      //    - smarthub/{MAC}/{endpoint}/speed/state    (payload "0".."3")
      //    - smarthub/{MAC}/{endpoint}/osc/state      (payload "swing"/"off")
      final mac = _extractMac(topic);
      if (mac != null) {
        updateDeviceStateFromMQTT(mac, topic, message);
      }
    };

    // [INITIAL STATE SYNC] KHÔNG tự connect ở đây nữa. Thứ tự chuẩn khi mở App:
    //   1) Dashboard gọi REST GET /api/homes/{id}/devices -> hydrateFromRest() nạp
    //      trạng thái tĩnh thật vào kho DPS -> các nút sáng ĐÚNG ngay lập tức;
    //   2) Sau đó Dashboard mới gọi connectMqtt() để hứng biến động realtime.
    // Nhờ vậy giao diện không còn khoảng "xám mặc định" chờ sóng MQTT về.
  }

  /// Tìm segment trong topic trông giống địa chỉ MAC (12 ký tự hex).
  /// Lấy segment khớp CUỐI CÙNG: với nhà đặt tên theo MAC Hub (luồng LinkHub),
  /// topic bridge smarthub/{home_id=MAC hub}/{MAC thiết bị}/state chứa 2 segment
  /// dạng MAC — MAC thiết bị luôn đứng sau home_id.
  String? _extractMac(String topic) {
    String? found;
    for (final part in topic.split('/')) {
      if (part.length == 12 && RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(part)) {
        found = part.toUpperCase();
      }
    }
    return found;
  }

  String _cleanMac(String mac) => mac.replaceAll(':', '').toUpperCase();

  // ==========================================================================
  // 🧩 BỘ DỊCH ENDPOINT-MAP DÙNG CHUNG (MQTT + REST)
  // ==========================================================================
  /// Dịch một map JSON trạng thái thiết bị sang gói cập nhật dps. Chấp nhận cả 2 dạng:
  ///   (a) Map endpoint phẳng: {"S_xxx": {"state":"ON","speed":2,"swing":false,"name":"Đèn"}, ...}
  ///   (b) Gói dps trực tiếp:  {"power":"ON","speed":2}
  /// Dùng chung cho sóng MQTT (updateDeviceStateFromMQTT) và ảnh REST (hydrateFromRest)
  /// để hai nguồn dữ liệu không bao giờ lệch khuôn nhau.
  static Map<String, dynamic> endpointJsonToDps(Map<String, dynamic> json) {
    final Map<String, dynamic> updates = {};
    json.forEach((key, value) {
      if (value is Map) {
        // Trường hợp (a): value là object mô tả endpoint
        final v = Map<String, dynamic>.from(value);
        if (v.containsKey('state')) updates[key] = v['state'];
        if (v.containsKey('speed') || v.containsKey('fan_speed')) {
          updates['${key}_speed'] =
              ((v['speed'] ?? v['fan_speed']) as num?)?.toInt() ?? 0;
        }
        if (v.containsKey('swing') || v.containsKey('oscillate')) {
          updates['${key}_swing'] = v['swing'] == true || v['oscillate'] == true;
        }
        if (v['name'] != null) updates['${key}_name'] = v['name'];
        if (v['type'] != null) updates['${key}_type'] = v['type'];
        // Số đo môi trường của endpoint cảm biến (DHT11...) — thẻ SmartSensorCard đọc realtime
        for (final f in const ['temperature', 'humidity']) {
          if (v.containsKey(f)) updates['${key}_$f'] = v[f];
        }
      } else {
        // Trường hợp (b): giá trị đơn -> coi như một dps code trực tiếp
        updates[key] = value;
      }
    });
    return updates;
  }

  // ==========================================================================
  // 💧 INITIAL STATE SYNC — NẠP ẢNH TRẠNG THÁI TĨNH TỪ REST VÀO KHO DPS
  // ==========================================================================
  /// Dashboard gọi hàm này NGAY khi REST GET /api/homes/{id}/devices trả về, cho
  /// từng thiết bị: bơm state_data (trạng thái thật Backend đọc từ Redis) + cờ
  /// online vào kho DPS -> notifyListeners() -> mọi nút sáng đúng thực tế TỨC THÌ,
  /// không phải chờ sóng MQTT/retained về. Sóng MQTT đến sau vẫn mergeDps đè lên
  /// bình thường (realtime luôn thắng ảnh tĩnh).
  void hydrateFromRest(String mac, Map<String, dynamic>? stateData, {bool? online}) {
    final cleanMac = _cleanMac(mac);
    final device = _devices.putIfAbsent(cleanMac, () => DeviceModel(mac: cleanMac));

    bool changed = false;
    if (stateData != null && stateData.isNotEmpty) {
      // allowNameKeys: REST Sync là NGUỒN DUY NHẤT được quyền ghi tên hiển thị
      changed = device.mergeDps(endpointJsonToDps(stateData), allowNameKeys: true);
    }
    // Đặt cờ online SAU mergeDps (mergeDps tự bật online=true khi có dữ liệu mới):
    // trạng thái Trực tuyến/Ngoại tuyến thật từ Backend (device_online) phải thắng
    if (online != null && device.online != online) {
      device.online = online;
      changed = true;
    }

    if (changed) {
      if (kDebugMode) print('💧 [HYDRATE] $cleanMac nạp ảnh REST -> ${device.dps} (online=$online)');
      notifyListeners();
    }
  }

  // ==========================================================================
  // ⚡ CẬP NHẬT TRẠNG THÁI TỪ MQTT — CHỈ SỬA RAM, KHÔNG GỌI HTTP
  // ==========================================================================
  /// Nhận một gói tin MQTT, cập nhật đúng MỘT thiết bị trong `_devices` rồi
  /// notifyListeners() để mọi widget đang watch tự vẽ lại tức thì.
  /// Tuyệt đối không gọi REST API ở đây — đó là chìa khóa cho độ trễ ~0ms.
  void updateDeviceStateFromMQTT(String mac, String topic, String payload) {
    final cleanMac = _cleanMac(mac);

    // Lấy model sẵn có hoặc khai sinh model mới nếu thiết bị lần đầu lên tiếng
    final device = _devices.putIfAbsent(cleanMac, () => DeviceModel(mac: cleanMac));

    bool changed = false;
    final parts = topic.split('/');

    // ---------- KÊNH AVAILABILITY (LWT): smarthub/{home_id}/{mac}/availability ----------
    // Broker phát "offline" (Last Will) khi thiết bị mất nguồn/rớt mạng đột ngột,
    // firmware phát "online" khi nối lại — App đổi màu thẻ xám/khóa điều khiển tức thì.
    if (parts.last == 'availability') {
      final bool nowOnline = payload.trim() == 'online';
      if (device.online != nowOnline) {
        device.online = nowOnline;
        device.lastUpdated = DateTime.now();
        if (kDebugMode) print('📶 [DPS] $cleanMac -> ${nowOnline ? "Trực tuyến" : "NGOẠI TUYẾN"}');
        notifyListeners();
      }
      return;
    }

    // ---------- KÊNH TIẾN TRÌNH OTA: smarthub/{home_id}/{mac}/ota/progress ----------
    // Thiết bị báo {"percent":0-100} (hoặc -1 khi lỗi, kèm "error_code"/"error" — mã hạt
    // nhân + câu gốc từ Update.h/HTTPClient) trong lúc tự nạp firmware; lưu vào dps khóa
    // hệ thống "__ota_progress"/"__ota_error_code"/"__ota_error" để Popup Cài đặt vẽ
    // thanh % + dịch lỗi tiếng Việt realtime.
    if (parts.length >= 2 && parts[parts.length - 2] == 'ota' && parts.last == 'progress') {
      final json = DeviceModel.safeDecode(payload);
      final percent = (json?['percent'] as num?)?.toInt();
      if (percent != null) {
        final updates = <String, dynamic>{'__ota_progress': percent};
        // Lỗi cũ phải bị XÓA khi bắt đầu lượt nạp mới (percent quay về 0) — nếu không UI
        // vẫn hiện lỗi lần trước dù lần này đang chạy tốt.
        if (percent == -1) {
          updates['__ota_error_code'] = (json?['error_code'] ?? '').toString();
          updates['__ota_error'] = (json?['error'] ?? '').toString();
        } else {
          updates['__ota_error_code'] = '';
          updates['__ota_error'] = '';
        }
        if (device.mergeDps(updates)) {
          if (kDebugMode) print('📥 [OTA] $cleanMac nạp firmware: $percent% ${percent == -1 ? "(${updates['__ota_error_code']}: ${updates['__ota_error']})" : ""}');
          notifyListeners();
        }
      }
      return;
    }

    // [CHẶN TIẾNG VỌNG LỆNH — GỐC RỄ "THẺ MA value"] App publish lệnh
    // {"endpoint","action","value"} vào smarthub/{home}/{mac}/command và cũng subscribe
    // smarthub/{home}/# nên NHẬN LẠI chính gói lệnh đó (MQTT 3.1.1 không có No-Local).
    // Nếu để lọt xuống endpointJsonToDps, các khóa của KHUÔN LỆNH thành dps rác
    // ("value":"ON" qua được bộ lọc ON/OFF) -> grid mọc thẻ ma "value" -> user đổi tên
    // thẻ ma -> hash device_names dính field "value". Từ đây: CHỈ topic đuôi /state
    // mới được coi là dữ liệu trạng thái.
    if (parts.last != 'state') return;

    final json = DeviceModel.safeDecode(payload);

    if (json != null) {
      // ---------- DẠNG 1: PAYLOAD JSON (map endpoint từ Backend republish) ----------
      // Đây chính là gói STATE FEEDBACK: Hass/thiết bị bấm -> Backend dịch + republish
      // smarthub/{home}/{mac}/state -> App nhận Ở ĐÂY -> mergeDps -> notifyListeners -> UI đổi màu.
      // Cùng một bộ dịch với hydrateFromRest — sóng MQTT và ảnh REST không bao giờ lệch khuôn.
      final updates = endpointJsonToDps(json);

      // [QUY TẮC THÉP] Khóa tên trong payload MQTT bị chặn NGAY TRONG NHÂN mergeDps
      // (mặc định allowNameKeys=false) — nơi này không cần và không được lọc tay nữa,
      // mọi luồng trạng thái đều đi qua đúng một cửa kiểm soát duy nhất.
      changed = device.mergeDps(updates);
      if (kDebugMode && parts.last == 'state') {
        debugPrint('📥 [STATE FEEDBACK] $cleanMac nhận state realtime -> ${json.keys.toList()} (đổi: $changed)');
      }
    } else {
      // ---------- DẠNG 2: PAYLOAD TRẦN ("ON", "2", "swing") ----------
      // Suy ra endpoint từ vị trí trong topic: smarthub/{MAC}/{endpoint}/...
      final macIndex = parts.indexWhere((p) => p.toUpperCase() == cleanMac);
      if (macIndex != -1 && macIndex + 1 < parts.length) {
        final endpoint = parts[macIndex + 1];
        if (parts.last == 'state') {
          if (parts[parts.length - 2] == 'speed') {
            changed = device.mergeDps({'${endpoint}_speed': int.tryParse(payload) ?? 0});
          } else if (parts[parts.length - 2] == 'osc') {
            changed = device.mergeDps({'${endpoint}_swing': payload == 'swing'});
          } else if (payload == 'ON' || payload == 'OFF') {
            changed = device.mergeDps({endpoint: payload});
          }
        }
      }
    }

    // Chỉ đánh thức UI khi dữ liệu THẬT SỰ đổi — tránh vẽ lại vô ích khi
    // broker phát lại gói retained trùng lặp.
    if (changed) {
      if (kDebugMode) {
        print('🔄 [DPS] $cleanMac cập nhật từ $topic -> ${device.dps}');
      }
      notifyListeners();
    }
  }

  // ==========================================================================
  // 🌊 NẠP LẦN ĐẦU TỪ REST API (HYDRATE) — CHỈ GỌI KHI MỞ MÀN HÌNH
  // ==========================================================================
  /// Kéo trạng thái mới nhất của một thiết bị từ Backend về làm "ảnh nền" ban đầu.
  /// Sau lời gọi này, mọi cập nhật tiếp theo đều đến từ MQTT (realtime).
  Future<void> fetchDeviceState(String mac) async {
    _isLoading = true;
    notifyListeners();

    try {
      final state = await _apiService.getDeviceState(mac);
      if (state != null) {
        final cleanMac = _cleanMac(mac);
        final device = _devices.putIfAbsent(cleanMac, () => DeviceModel(mac: cleanMac));
        final Map<String, dynamic> updates = {};
        state.endpoints.forEach((id, sub) {
          updates[id] = sub.state;
          if (sub.speed != null) updates['${id}_speed'] = sub.speed;
          updates['${id}_swing'] = sub.swing;
          if (sub.name != null) updates['${id}_name'] = sub.name;
        });
        // allowNameKeys: đây là REST GET (HTTP quản lý Tên) — cùng đặc quyền với hydrateFromRest
        device.mergeDps(updates, allowNameKeys: true);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi nạp trạng thái thiết bị $mac: $e');
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('401') || errorStr.contains('unauthorized')) {
        _authService.handleUnauthorized();
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // ==========================================================================
  // 🕹️ CÁC HÀM ĐIỀU KHIỂN — BẮN LỆNH QUA CẦU NỐI BACKEND
  // ==========================================================================

  /// Gạt công tắc theo cơ chế PHẢN HỒI THỰC (Real-State Response):
  /// CHỈ bắn lệnh qua Cầu nối Backend — KHÔNG cập nhật lạc quan trong RAM.
  /// Icon chỉ sáng lên khi thiết bị THẬT SỰ đóng/cắt rơ-le xong và báo state
  /// ngược về qua smarthub/{home_id}/{mac}/state — nhờ đó mọi máy đang mở App
  /// (PC lẫn điện thoại) cùng sáng đồng thời, và nút không "sáng ma" khi
  /// thiết bị kẹt lệnh/mất mạng.
  /// `currentStatus` là trạng thái HIỆN TẠI của phím — hàm sẽ tự lật ngược.
  void toggleSwitch(String mac, String endpoint, bool currentStatus) {
    // Chặn bấm vô vọng vào thiết bị đã Ngoại tuyến (LWT báo offline)
    final device = _devices[_cleanMac(mac)];
    if (device != null && !device.online) {
      if (kDebugMode) print('🚫 [DPS] ${_cleanMac(mac)} đang Ngoại tuyến — bỏ qua lệnh');
      return;
    }
    _mqttService.publishCommand(mac, endpoint, !currentStatus ? 'ON' : 'OFF');
  }

  /// Gửi lệnh TUYỆT ĐỐI bật/tắt (KHÔNG lật như toggleSwitch) — dùng cho ĐIỀU KHIỂN NHÓM:
  /// nút nhóm cần ép TẤT CẢ thành viên về cùng một trạng thái, không phụ thuộc trạng thái
  /// hiện tại của từng cái. Bỏ qua thiết bị Ngoại tuyến.
  void setSwitchState(String mac, String endpoint, bool on) {
    final device = _devices[_cleanMac(mac)];
    if (device != null && !device.online) return;
    _mqttService.publishCommand(mac, endpoint, on ? 'ON' : 'OFF');
  }

  /// Thiết bị có BẤT KỲ endpoint nào đang bật không — để nút nhóm sáng khi ít nhất
  /// một thành viên đang bật (và chỉ tắt khi TẤT CẢ đều tắt).
  bool anyEndpointOn(String mac) {
    final d = _devices[_cleanMac(mac)];
    if (d == null) return false;
    return d.endpointIds.any((ep) => d.isOn(ep));
  }

  /// Chỉnh tốc độ quạt (0 = tắt, 1-3 = các cấp gió) — cũng theo Real-State:
  /// vòng quay icon chỉ đổi nhịp khi mạch quạt báo tốc độ thật ngược về.
  /// `endpoint` mặc định 'F1' cho quạt đầu tiên trên Hub V38; truyền endpoint khác
  /// khi Hub có nhiều quạt hoặc điều khiển hộp Fan_Control rời.
  /// `swing` (tùy chọn): đồng thời chỉnh chế độ đảo gió trong cùng thao tác.
  void setFanSpeed(String mac, int speed, {String endpoint = 'F1', bool? swing}) {
    final device = _devices[_cleanMac(mac)];
    if (device != null && !device.online) {
      if (kDebugMode) print('🚫 [DPS] ${_cleanMac(mac)} đang Ngoại tuyến — bỏ qua lệnh quạt');
      return;
    }
    _mqttService.sendCommand(mac, endpoint, speed > 0, speed: speed, swing: swing);
  }

  /// [DIGITAL TWIN] Kích relay Cửa cuốn (UP/DOWN) đúng [durationMs] mili-giây — dùng khi kéo
  /// Slider % (SmartRollingDoorCard tự tính durationMs theo Thời gian hành trình đã hiệu chỉnh).
  void pulseDoorRelay(String mac, String endpoint, int durationMs) {
    final device = _devices[_cleanMac(mac)];
    if (device != null && !device.online) {
      if (kDebugMode) print('🚫 [DPS] ${_cleanMac(mac)} đang Ngoại tuyến — bỏ qua lệnh cửa cuốn');
      return;
    }
    _mqttService.sendDoorPulse(mac, endpoint, durationMs);
  }

  /// [DIGITAL TWIN] Chỉnh độ sáng Đèn Chiết áp (Dimmer) 0-100.
  void setDimmerBrightness(String mac, String endpoint, int brightness) {
    final device = _devices[_cleanMac(mac)];
    if (device != null && !device.online) {
      if (kDebugMode) print('🚫 [DPS] ${_cleanMac(mac)} đang Ngoại tuyến — bỏ qua lệnh độ sáng');
      return;
    }
    _mqttService.sendBrightness(mac, endpoint, brightness);
  }

  // ==========================================================================
  // 🗑️ GỠ THIẾT BỊ KHỎI NHÀ (UNPAIR) — ĐỒNG BỘ SERVER + RAM
  // ==========================================================================
  /// Gọi Backend xóa liên kết thiết bị (DELETE /api/devices/{mac}).
  /// Nếu server xác nhận thành công: gỡ luôn DeviceModel khỏi kho RAM và
  /// notifyListeners() — mọi lưới đang watch tự cập nhật NGAY, thẻ của thiết bị
  /// không thể "hồi sinh" từ dps cũ. Trả về true/false để UI hiện thông báo.
  Future<bool> deleteDevice(String mac) async {
    final ok = await _apiService.deleteDevice(mac);
    if (ok) {
      _devices.remove(_cleanMac(mac));
      if (kDebugMode) print('🗑️ [DPS] Đã gỡ thiết bị ${_cleanMac(mac)} khỏi kho RAM');
      notifyListeners();
    }
    return ok;
  }

  // ==========================================================================
  // ♻️ HÀM TƯƠNG THÍCH NGƯỢC (giữ cho dashboard_screen.dart cũ không gãy)
  // ==========================================================================

  /// Tên cũ của [toggleSwitch] — các màn hình cũ vẫn gọi toggleDevice.
  @Deprecated('Dùng toggleSwitch() — cùng hành vi, tên chuẩn hóa theo DPS')
  void toggleDevice(String mac, String endpoint, bool currentState) =>
      toggleSwitch(mac, endpoint, currentState);
}
