import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import '../models/device_state.dart';
import '../models/camera_model.dart';
import '../models/imou_camera_model.dart';
import 'secure_storage_service.dart';

/// [DIRECT MAC BINDING] Kết quả gõ kiểu của ApiService.addDevice — phân biệt RÕ RÀNG 4 tình
/// huống mà LinkDeviceToHomeHandler (Backend Go) có thể trả về, để UI phản hồi đúng từng loại
/// thay vì gộp chung "lỗi" mù mờ:
///   success        : 200 — đã gán vào nhà thành công
///   notOnlineYet   : 404 — thiết bị CHƯA kịp phát MQTT về Broker (vừa đổi WiFi, có thể còn
///                    đang associate/DHCP) — TẠM THỜI, đáng để thử lại sau vài giây
///   ownershipConflict: 409 — MAC đã thuộc về MỘT nhà/tài khoản KHÁC — VĨNH VIỄN, không thử lại
///   forbidden      : 403 — user hiện tại không có quyền thêm thiết bị vào nhà đích
///   otherError     : lỗi HTTP khác từ Backend
///   networkError   : không tới được Backend (mất mạng, timeout...)
enum AddDeviceStatus { success, notOnlineYet, ownershipConflict, forbidden, otherError, networkError }

class AddDeviceResult {
  final AddDeviceStatus status;
  final String? message; // câu chữ THẬT server trả về (giữ nguyên để hiện cho user)
  // [LUỒNG CHUYỂN GIAO] Chỉ có giá trị khi status == ownershipConflict — email chủ cũ ĐÃ CHE
  // sẵn từ Backend (vd "sale.****@gmail.com"), App KHÔNG BAO GIỜ tự ý xử lý/tính toán việc che
  // này, chỉ hiển thị y nguyên những gì server trả.
  final String? maskedOwnerEmail;
  final String? conflictMac;
  const AddDeviceResult(this.status, [this.message, this.maskedOwnerEmail, this.conflictMac]);
}

/// [GIAO DIỆN QUẢN TRỊ TOÀN CỤC] 1 dòng trong bảng PaginatedDataTable của SUPER_USER — khớp
/// đúng khuôn adminDeviceRow (Backend Go, admin_system.go).
class AdminDeviceRow {
  final String mac;
  final String name;
  final String homeId;
  final String homeName;
  final String ownerEmail; // SUPER_USER thấy email THẬT, không che
  final bool online;
  final String category;
  final String fwType;

  const AdminDeviceRow({
    required this.mac,
    required this.name,
    required this.homeId,
    required this.homeName,
    required this.ownerEmail,
    required this.online,
    this.category = '',
    this.fwType = '',
  });

  factory AdminDeviceRow.fromJson(Map<String, dynamic> j) => AdminDeviceRow(
        mac: j['mac_address']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        homeId: j['home_id']?.toString() ?? '',
        homeName: j['home_name']?.toString() ?? '',
        ownerEmail: j['owner_email']?.toString() ?? '',
        online: j['online'] == true,
        category: j['category']?.toString() ?? '',
        fwType: j['fw_type']?.toString() ?? '',
      );
}

/// Kết quả 1 trang GET /api/admin/devices — kèm total để PaginatedDataTable tính số trang.
class AdminDevicePage {
  final List<AdminDeviceRow> rows;
  final int total;
  const AdminDevicePage(this.rows, this.total);
}

class ApiService {
  // Trỏ chính xác vào IP Box Armbian của bạn
  static const String baseUrl = 'https://api.iot-smart.vn/api';

  // --- [DIRECT MAC BINDING] ĐĂNG KÝ THIẾT BỊ THẲNG BẰNG MAC (thay luồng Quét LAN cũ) ---
  /// POST /api/homes/{homeId}/devices {"mac_address": mac} — Backend (LinkDeviceToHomeHandler)
  /// tự kiểm: MAC hợp lệ, user sở hữu nhà đích, thiết bị đã "lên tiếng" MQTT (handshake
  /// liveness), và MAC chưa thuộc nhà/tài khoản khác (chống cướp thiết bị). Gọi lại nhiều lần
  /// với CÙNG homeId là AN TOÀN (idempotent) — Backend chỉ chặn khi chủ sở hữu THỰC SỰ khác.
  Future<AddDeviceResult> addDevice(String homeId, String mac) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}/devices'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'mac_address': mac}),
      );

      String? serverMsg;
      String? maskedOwnerEmail;
      String? conflictMac;
      try {
        final body = json.decode(response.body);
        if (body is Map) {
          serverMsg = (body['error'] ?? body['message'])?.toString();
          // [LUỒNG CHUYỂN GIAO] Chỉ 409 mới có 2 trường này (xem LinkDeviceToHomeHandler) — Map
          // rỗng/thiếu key vẫn an toàn nhờ toán tử ?. + ?? null, không throw.
          maskedOwnerEmail = body['owner_email_mask']?.toString();
          conflictMac = body['mac']?.toString();
        }
      } catch (_) {}

      switch (response.statusCode) {
        case 200:
          return AddDeviceResult(AddDeviceStatus.success, serverMsg);
        case 404:
          return AddDeviceResult(AddDeviceStatus.notOnlineYet, serverMsg);
        case 409:
          return AddDeviceResult(AddDeviceStatus.ownershipConflict, serverMsg, maskedOwnerEmail, conflictMac);
        case 403:
          return AddDeviceResult(AddDeviceStatus.forbidden, serverMsg);
        default:
          if (kDebugMode) print('⚠️ addDevice($mac) -> HTTP ${response.statusCode}: ${response.body}');
          return AddDeviceResult(AddDeviceStatus.otherError, serverMsg);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi addDevice($mac): $e');
      return const AddDeviceResult(AddDeviceStatus.networkError);
    }
  }

  // --- HÀM LẤY TRẠNG THÁI THIẾT BỊ (ĐÃ ĐƯỢC LỒNG GHÉP AUTH) ---
  Future<DeviceState?> getDeviceState(String mac) async {
    try {
      // THAY ĐỔI Ở ĐÂY: Dùng authorizedGet thay vì http.get trực tiếp
      final response = await authorizedGet('$baseUrl/devices/${Uri.encodeComponent(mac)}/state');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Lưu ý: Nếu server trả về dạng {"success": true, "data": {...}}
        // Bạn có thể cần truy cập data['data'] tùy vào cấu trúc model của bạn.
        // Ở đây tôi giữ nguyên logic cũ theo file bạn gửi:
        return DeviceState.fromJson(data);
      } else {
        if (kDebugMode) print('⚠️ Server Golang báo lỗi (Status ${response.statusCode}): ${response.body}');
        return null;
      }
    } catch (e) {
      if (kDebugMode) print('❌ Không thể kết nối tới Box Armbian: $e');
      return null;
    }
  }

  // --- HÀM GỠ THIẾT BỊ KHỎI NHÀ (UNPAIR) ---
  /// Gửi DELETE /api/devices/{mac} tới Backend Golang. Backend sẽ xác minh chủ quyền,
  /// dọn bản ghi Redis, xóa retained message và ngắt phiên MQTT của thiết bị trên EMQX.
  /// Trả về true khi server xác nhận xóa thành công (HTTP 200/204).
  Future<bool> deleteDevice(String mac) async {
    try {
      final response = await authorizedDelete('$baseUrl/devices/${Uri.encodeComponent(mac)}');
      if (response.statusCode == 200 || response.statusCode == 204) return true;
      if (kDebugMode) print('⚠️ Server từ chối xóa thiết bị $mac (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi xóa thiết bị $mac: $e');
      return false;
    }
  }

  // --- HÀM ĐỔI TÊN ENDPOINT THIẾT BỊ ---
  /// PUT /api/devices/{mac}/name — lưu tên user đặt vào database (Redis hash device_names).
  /// Tên này được ưu tiên tuyệt đối trước tên tự sinh sw-/Fan-; gửi name rỗng = xóa tên,
  /// quay về tên tự động. Backend đồng thời phát lại state để mọi App cập nhật realtime.
  Future<bool> renameDeviceEndpoint(String mac, String endpoint, String name) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/name'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'endpoint': endpoint, 'name': name}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối đổi tên $mac/$endpoint (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi đổi tên thiết bị: $e');
      return false;
    }
  }

  // --- CÀI ĐẶT "TRẠNG THÁI KHI CÓ ĐIỆN" (POWER-ON BEHAVIOR) ---
  /// PUT /api/devices/{mac}/power-behavior với {"mode": 0|1|2}
  /// (0 = Nhớ trạng thái cũ, 1 = Luôn Tắt, 2 = Luôn Bật).
  /// Backend lưu Redis device_settings:{mac} rồi đẩy cấu hình xuống mạch qua MQTT
  /// (kèm bản retained để thiết bị đang mất điện vẫn nhận được khi lên mạng lại).
  Future<bool> setPowerBehavior(String mac, int mode) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/power-behavior'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'mode': mode}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối lưu power-behavior $mac (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi lưu power-behavior: $e');
      return false;
    }
  }

  // --- [CỬA CUỐN ĐA NĂNG — "SERVER MÙ"] CHỌN LOẠI ĐỘNG CƠ ---
  /// PUT /api/devices/{mac}/motor-type với {"motor_type": "AC_220V"|"DC_24V"}. Backend tra bảng
  /// preset (pulse_ms/interlock_ms) rồi đẩy xuống mạch qua đúng cơ chế devices_v2/{mac}/config
  /// (retained) đã có sẵn trong firmware — App KHÔNG tự tính pulse/interlock, chỉ chọn loại.
  Future<bool> setMotorType(String mac, String motorType) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/motor-type'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'motor_type': motorType}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối lưu motor-type $mac (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi lưu motor-type: $e');
      return false;
    }
  }

  // --- [DIGITAL TWIN] CÀI ĐẶT TỔNG QUÁT KHÁC (Thời gian hành trình cửa cuốn, vị trí %...) ---
  /// PUT /api/devices/{mac}/setting {"key":"...","value":"..."} — mirror setPowerBehavior
  /// nhưng dùng chung MỘT endpoint cho mọi field mới (key phải nằm trong allowlist phía Backend:
  /// travel_time_sec, door_position_pct). Không đẩy MQTT xuống mạch (thuần App/Backend dùng).
  Future<bool> setDeviceSetting(String mac, String key, String value) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/setting'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: json.encode({'key': key, 'value': value}),
      );
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ Server từ chối lưu cài đặt $mac.$key (HTTP ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi lưu cài đặt $key: $e');
      return false;
    }
  }

  // --- KIỂM TRA KHO FIRMWARE OTA ---
  /// GET /api/firmware/check — trả về meta {version, url, sha256} khi kho có bản MỚI HƠN
  /// (HTTP 200); trả null khi đang ở bản mới nhất (304) hoặc kho chưa có firmware (404).
  Future<Map<String, dynamic>?> checkFirmwareUpdate(String deviceType, String currentVersion) async {
    final token = await SecureStorageService.getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/firmware/check?device_type=${Uri.encodeComponent(deviceType)}&current_version=${Uri.encodeComponent(currentVersion)}'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) return json.decode(response.body) as Map<String, dynamic>;
    if (kDebugMode) print('ℹ️ [OTA] Check firmware $deviceType v$currentVersion -> HTTP ${response.statusCode}');
    return null;
  }

  // --- RA LỆNH NẠP FIRMWARE OTA ---
  /// POST /api/devices/{mac}/ota — Backend xác minh chủ quyền + thiết bị Trực tuyến rồi
  /// bắn lệnh MQTT xuống chip tự tải file .bin về nạp (kèm SHA256 tự kiểm trước khi ghi flash).
  Future<bool> triggerOtaUpdate(String mac) async {
    try {
      final token = await SecureStorageService.getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}/ota'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ [OTA] Lỗi ra lệnh nạp firmware: $e');
      return false;
    }
  }

  // --- [LUỒNG CHUYỂN GIAO] User bị 409 bấm "Gửi yêu cầu gỡ" -> Backend gửi email kèm link tự
  // xác thực tới chủ hiện tại (RequestUnbindHandler). success=false không phải lúc nào cũng là
  // lỗi thật — Backend cố ý trả 200 im lặng khi bị rate-limit (chống spam 1 email/giờ/MAC).
  Future<bool> requestUnbind(String mac) async {
    try {
      final response = await authorizedPost('$baseUrl/devices/${Uri.encodeComponent(mac)}/request-unbind');
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ requestUnbind($mac) -> HTTP ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi requestUnbind($mac): $e');
      return false;
    }
  }

  // --- [GIAO DIỆN QUẢN TRỊ TOÀN CỤC — CHỈ SUPER_USER] ---
  /// GET /api/admin/devices?search=&page=&page_size= — Backend tự lọc "Smart Search" (tên thiết
  /// bị/tên nhà/email chủ/MAC cùng lúc) + phân trang. Trả null khi lỗi mạng/HTTP (UI tự hiện lại
  /// nút Thử lại, không đoán mò dữ liệu rỗng nghĩa là "không có thiết bị nào").
  Future<AdminDevicePage?> listAllDevicesAdmin({String search = '', int page = 1, int pageSize = 20}) async {
    try {
      final uri = Uri.parse('$baseUrl/admin/devices').replace(queryParameters: {
        if (search.isNotEmpty) 'search': search,
        'page': '$page',
        'page_size': '$pageSize',
      });
      final token = await SecureStorageService.getToken();
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ listAllDevicesAdmin -> HTTP ${response.statusCode}: ${response.body}');
        return null;
      }
      final body = json.decode(response.body);
      final List<dynamic> raw = (body['devices'] as List?) ?? [];
      final rows = raw.map((e) => AdminDeviceRow.fromJson(e as Map<String, dynamic>)).toList();
      return AdminDevicePage(rows, (body['total'] as num?)?.toInt() ?? rows.length);
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi listAllDevicesAdmin: $e');
      return null;
    }
  }

  /// POST /api/admin/devices/{mac}/force-unbind — "Quyền Tối cao": SUPER_USER ép gỡ thiết bị
  /// khỏi BẤT KỲ tài khoản nào ngay lập tức, không cần email xác nhận (khác requestUnbind()).
  Future<bool> forceUnbindDevice(String mac) async {
    try {
      final response = await authorizedPost('$baseUrl/admin/devices/${Uri.encodeComponent(mac)}/force-unbind');
      if (response.statusCode == 200) return true;
      if (kDebugMode) print('⚠️ forceUnbindDevice($mac) -> HTTP ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi forceUnbindDevice($mac): $e');
      return false;
    }
  }

  // --- HÀM TRỢ GIÚP GẮN TOKEN VÀO HEADER ---
  Future<http.Response> authorizedGet(String url) async {
    final token = await SecureStorageService.getToken();

    return await http.get(
      Uri.parse(url),
      headers: {
        // Đảm bảo đúng định dạng: "Bearer <token>" (có dấu cách)
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  // --- HÀM TRỢ GIÚP GỬI LỆNH DELETE KÈM TOKEN ---
  Future<http.Response> authorizedDelete(String url) async {
    final token = await SecureStorageService.getToken();

    return await http.delete(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
  }

  // --- HÀM TRỢ GIÚP GỬI LỆNH POST KÈM TOKEN + BODY JSON ---
  Future<http.Response> authorizedPost(String url, [Map<String, dynamic>? body]) async {
    final token = await SecureStorageService.getToken();

    return await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body != null ? json.encode(body) : null,
    );
  }

  // --- HÀM TRỢ GIÚP GỬI LỆNH PUT KÈM TOKEN + BODY JSON ---
  Future<http.Response> authorizedPut(String url, [Map<String, dynamic>? body]) async {
    final token = await SecureStorageService.getToken();

    return await http.put(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body != null ? json.encode(body) : null,
    );
  }

  // --- [GIAI ĐOẠN 72 — KÉO THẢ SẮP XẾP] Lưu thứ tự thẻ thiết bị theo Nhà ---
  /// PUT /api/homes/{homeId}/device-order {"ordered_macs": [...]} — SetDeviceOrderHandler (Go)
  /// lưu vào Redis device_order:{homeId}; applyDeviceOrder() sẽ tự sắp lại danh sách mỗi lần
  /// GET devices/dashboard-sync sau đó.
  /// [FIX GIAI ĐOẠN 97 — KHÔNG NUỐT LỖI] Trước đây MỌI lỗi (404 route chưa deploy, 403 hết quyền,
  /// 500...) đều rơi về `false` trần trụi — App chỉ hiện được "Không thể lưu thứ tự" chung chung,
  /// không cách nào phân biệt "Backend chưa có route này" với "lỗi thật khác". Nay LUÔN log status
  /// code + response body ra console khi thất bại — cùng nguyên tắc đã áp cho uploadAvatar().
  Future<bool> setDeviceOrder(String homeId, List<String> orderedMacs) async {
    try {
      final response = await authorizedPut(
        '$baseUrl/homes/${Uri.encodeComponent(homeId)}/device-order',
        {'ordered_macs': orderedMacs},
      );
      // [FIX GIAI ĐOẠN 100 — CHỨNG MINH API ĐÃ ĐƯỢC GỌI] Log CẢ status code + body khi THÀNH
      // CÔNG (trước đây chỉ log lúc thất bại) — người dùng cần thấy bằng chứng request thật sự
      // đã bắn đi và Server đã trả lời gì, không chỉ suy đoán qua hành vi UI.
      if (kDebugMode) print('📡 [DEVICE ORDER] HTTP ${response.statusCode} — ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi setDeviceOrder: $e');
      return false;
    }
  }

  // --- [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Bố cục lưới riêng theo Nhà ---
  /// PUT /api/homes/{homeId}/grid-layout {"slots": [...]} — SetGridLayoutHandler (Go) lưu NGUYÊN
  /// VĂN mảng token (hideKey thiết bị / "EMPTY" / "SKIP") vào Redis device_grid_layout:{homeId},
  /// TÁCH BIỆT HOÀN TOÀN với device-order ở trên (xem giải thích tại SetGridLayoutHandler phía
  /// Backend — device-order KHÔNG thể biểu diễn "khoảng trống" vì applyDeviceOrder() chỉ xếp hạng
  /// thiết bị THẬT, không có khái niệm ô ảo).
  Future<bool> setGridLayout(String homeId, List<String> slots) async {
    try {
      final response = await authorizedPut(
        '$baseUrl/homes/${Uri.encodeComponent(homeId)}/grid-layout',
        {'slots': slots},
      );
      if (kDebugMode) print('📡 [GRID LAYOUT] HTTP ${response.statusCode} — ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi setGridLayout: $e');
      return false;
    }
  }

  /// GET /api/homes/{homeId}/grid-layout — trả null khi lỗi mạng (khác [] rỗng = "đã fetch
  /// thành công nhưng chưa từng tuỳ biến lưới"), để nơi gọi phân biệt được "chưa có dữ liệu, đừng
  /// ghi đè local" với "server xác nhận rỗng thật, được phép ghi đè local".
  Future<List<String>?> getGridLayout(String homeId) async {
    try {
      final response = await authorizedGet('$baseUrl/homes/${Uri.encodeComponent(homeId)}/grid-layout');
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ [GRID LAYOUT] Lỗi tải bố cục (HTTP ${response.statusCode}): ${response.body}');
        return null;
      }
      final Map<String, dynamic> decoded = json.decode(response.body);
      final List<dynamic> raw = (decoded['slots'] as List?) ?? const [];
      return raw.map((e) => e.toString()).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getGridLayout: $e');
      return null;
    }
  }

  // ============================================================================
  // 📷 CAMERA IP (RTSP) — Backend chỉ lưu cấu hình + tự ghép rtsp_url, KHÔNG proxy video
  // ============================================================================

  /// GET /api/homes/{homeId}/cameras — trả null khi lỗi mạng/HTTP (khác [] rỗng = "đã fetch
  /// thành công nhưng nhà chưa có camera nào"), cùng quy ước với getGridLayout ở trên.
  Future<List<CameraModel>?> getCameras(String homeId) async {
    try {
      final response = await authorizedGet('$baseUrl/homes/${Uri.encodeComponent(homeId)}/cameras');
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ [CAMERA] Lỗi tải danh sách (HTTP ${response.statusCode}): ${response.body}');
        return null;
      }
      final Map<String, dynamic> decoded = json.decode(response.body);
      final List<dynamic> raw = (decoded['data'] as List?) ?? const [];
      return raw.map((e) => CameraModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getCameras: $e');
      return null;
    }
  }

  /// POST /api/homes/{homeId}/cameras — thêm camera mới. Trả (camera, error): camera khác null
  /// = thành công (kèm rtsp_url Backend đã ghép sẵn); error khác null = câu chữ THẬT server trả
  /// về để hiện cho user, KHÔNG tự đoán.
  Future<({CameraModel? camera, String? error})> addCamera({
    required String homeId,
    required String name,
    required String ipAddress,
    required int port,
    String username = '',
    String password = '',
    String streamPath = '',
    String subStreamPath = '',
  }) async {
    try {
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/cameras', {
        'name': name,
        'ip_address': ipAddress,
        'port': port,
        'username': username,
        'password': password,
        'stream_path': streamPath,
        'sub_stream_path': subStreamPath,
      });
      final Map<String, dynamic> decoded = json.decode(response.body);
      if (response.statusCode == 200) {
        return (camera: CameraModel.fromJson(decoded['data'] as Map<String, dynamic>), error: null);
      }
      return (camera: null, error: (decoded['error'] ?? 'Lỗi không xác định từ Server').toString());
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi addCamera: $e');
      return (camera: null, error: 'Không thể kết nối đến máy chủ');
    }
  }

  /// GET /api/cameras/discover — quét WS-Discovery (ONVIF) trên mạng LAN của SERVER (KHÔNG phải
  /// mạng của điện thoại/PC đang mở App — xem giới hạn kiến trúc ở internal/onvif/discovery.go).
  /// Trả (cameras, error) cùng khuôn addCamera(): cameras rỗng [] hợp lệ = quét xong nhưng không
  /// thấy camera nào, KHÁC null (lỗi mạng/HTTP — hiện thông báo lỗi thay vì "không tìm thấy").
  Future<({List<DiscoveredCameraModel>? cameras, String? error})> discoverCameras() async {
    try {
      final response = await authorizedGet('$baseUrl/cameras/discover');
      final Map<String, dynamic> decoded = json.decode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> raw = (decoded['data'] as List?) ?? const [];
        return (cameras: raw.map((e) => DiscoveredCameraModel.fromJson(e as Map<String, dynamic>)).toList(), error: null);
      }
      return (cameras: null, error: (decoded['error'] ?? 'Lỗi không xác định từ Server').toString());
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi discoverCameras: $e');
      return (cameras: null, error: 'Không thể kết nối đến máy chủ');
    }
  }

  /// DELETE /api/homes/{homeId}/cameras/{cameraId} — xóa cấu hình camera khỏi nhà. Trả true chỉ
  /// khi Server xác nhận đã xóa (HTTP 200) — false cho MỌI trường hợp khác (404/403/lỗi mạng),
  /// cùng quy ước "không nuốt lỗi" đã áp cho setDeviceOrder/setGridLayout ở trên.
  Future<bool> deleteCamera(String homeId, int cameraId) async {
    try {
      final response = await authorizedDelete('$baseUrl/homes/${Uri.encodeComponent(homeId)}/cameras/$cameraId');
      if (kDebugMode) print('📡 [CAMERA] Xóa camera $cameraId — HTTP ${response.statusCode}: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi deleteCamera: $e');
      return false;
    }
  }

  // ============================================================================
  // 📷 CAMERA P2P (IMOU) — xem qua Internet, không cần cùng LAN với Server/App
  // ============================================================================

  /// GET /api/homes/{homeId}/imou-cameras — cùng quy ước null-khi-lỗi với getCameras().
  Future<List<ImouCameraModel>?> getImouCameras(String homeId) async {
    try {
      final response = await authorizedGet('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras');
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ [IMOU] Lỗi tải danh sách (HTTP ${response.statusCode}): ${response.body}');
        return null;
      }
      final Map<String, dynamic> decoded = json.decode(response.body);
      final List<dynamic> raw = (decoded['data'] as List?) ?? const [];
      return raw.map((e) => ImouCameraModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getImouCameras: $e');
      return null;
    }
  }

  /// POST /api/homes/{homeId}/imou-cameras — gắn camera Imou mới bằng Device Serial + mã xác
  /// thực in trên nhãn camera thật. Cùng khuôn trả (camera, error) với addCamera().
  Future<({ImouCameraModel? camera, String? error})> addImouCamera({
    required String homeId,
    required String name,
    required String deviceSerial,
    required String verifyCode,
  }) async {
    try {
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras', {
        'name': name,
        'device_serial': deviceSerial,
        'verify_code': verifyCode,
      });
      final Map<String, dynamic> decoded = json.decode(response.body);
      if (response.statusCode == 200) {
        return (camera: ImouCameraModel.fromJson(decoded['data'] as Map<String, dynamic>), error: null);
      }
      return (camera: null, error: (decoded['error'] ?? 'Lỗi không xác định từ Server').toString());
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi addImouCamera: $e');
      return (camera: null, error: 'Không thể kết nối đến máy chủ');
    }
  }

  /// DELETE /api/homes/{homeId}/imou-cameras/{cameraId} — gỡ camera khỏi Cloud Imou + Postgres.
  Future<bool> deleteImouCamera(String homeId, int cameraId) async {
    try {
      final response = await authorizedDelete('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId');
      if (kDebugMode) print('📡 [IMOU] Xóa camera $cameraId — HTTP ${response.statusCode}: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi deleteImouCamera: $e');
      return false;
    }
  }

  /// GET /api/homes/{homeId}/imou-cameras/{cameraId}/live-url — URL HLS (luồng chính + luồng phụ
  /// nếu có) cho 1 phiên xem trực tiếp — phát THẲNG qua media_kit, KHÔNG cần SDK gốc (xem
  /// internal/imou/token.go GetLiveStreamURLs — phát hiện kiến trúc mới thay thế hẳn access_token
  /// +psk của thiết kế Pha 1 cũ). Gọi lại MỖI LẦN mở xem (Maximize/Fullscreen), KHÔNG cache lâu
  /// dài. Trả null khi lỗi mạng/chưa cấu hình.
  Future<({String hlsUrl, String subHlsUrl})?> getImouLiveURL(String homeId, int cameraId) async {
    try {
      final response = await authorizedGet('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/live-url');
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ [IMOU] Lỗi lấy live-url (HTTP ${response.statusCode}): ${response.body}');
        return null;
      }
      final Map<String, dynamic> decoded = json.decode(response.body);
      final Map<String, dynamic> data = decoded['data'] as Map<String, dynamic>;
      return (
        hlsUrl: (data['hls_url'] ?? '').toString(),
        subHlsUrl: (data['sub_hls_url'] ?? '').toString(),
      );
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getImouLiveURL: $e');
      return null;
    }
  }

  // ============================================================================
  // ⚙️ CÀI ĐẶT + ĐIỀU KHIỂN + XEM LẠI CAMERA IMOU
  // ============================================================================

  /// GET .../imou-cameras/{cameraId}/settings — gộp nhiều thông tin (riêng tư/hồng ngoại/chuyển
  /// động/SD card/dung lượng/pin/trực tuyến) thành 1 lần gọi. Trả null khi lỗi mạng — từng field
  /// bên trong có thể rỗng riêng lẻ (best-effort phía Backend, không phải lỗi toàn bộ).
  Future<Map<String, dynamic>?> getImouCameraSettings(String homeId, int cameraId) async {
    try {
      final response = await authorizedGet('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/settings');
      if (response.statusCode != 200) return null;
      final Map<String, dynamic> decoded = json.decode(response.body);
      return decoded['data'] as Map<String, dynamic>?;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getImouCameraSettings: $e');
      return null;
    }
  }

  Future<bool> setImouPrivacyMode(String homeId, int cameraId, bool enable) async {
    try {
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/privacy', {'enable': enable});
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi setImouPrivacyMode: $e');
      return false;
    }
  }

  Future<bool> setImouNightVision(String homeId, int cameraId, String mode) async {
    try {
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/night-vision', {'mode': mode});
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi setImouNightVision: $e');
      return false;
    }
  }

  /// [enabled]/[sensitivity] đều tùy chọn — chỉ gửi field khác null.
  Future<bool> setImouMotionDetection(String homeId, int cameraId, {bool? enabled, String? sensitivity}) async {
    try {
      final body = <String, dynamic>{};
      if (enabled != null) body['enabled'] = enabled;
      if (sensitivity != null) body['sensitivity'] = sensitivity;
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/motion-detection', body);
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi setImouMotionDetection: $e');
      return false;
    }
  }

  Future<bool> restartImouCamera(String homeId, int cameraId) async {
    try {
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/restart');
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi restartImouCamera: $e');
      return false;
    }
  }

  /// PTZ THẬT (khác D-pad placeholder camera RTSP) — direction: UP/DOWN/LEFT/RIGHT/ZOOM_IN/
  /// ZOOM_OUT/STOP. App gọi "STOP" ngay khi người dùng nhả nút, KHÔNG chỉ dựa vào durationMs.
  Future<bool> controlImouPTZ(String homeId, int cameraId, String direction, {int durationMs = 500}) async {
    try {
      final response = await authorizedPost(
        '$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/ptz',
        {'direction': direction, 'duration_ms': durationMs},
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi controlImouPTZ: $e');
      return false;
    }
  }

  /// GET .../imou-cameras/{cameraId}/records?source=local|cloud&begin=...&end=... — CHỈ trả
  /// metadata (KHÔNG có URL phát được — xem giới hạn đã xác nhận trong internal/imou/records.go
  /// phía Backend). Trả null khi lỗi mạng/nghiệp vụ (vd chưa có gói Cloud Storage).
  Future<List<Map<String, dynamic>>?> getImouCameraRecords(
    String homeId,
    int cameraId, {
    required String source, // 'local' | 'cloud'
    required DateTime begin,
    required DateTime end,
  }) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    try {
      final uri = Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/records').replace(queryParameters: {
        'source': source,
        'begin': fmt(begin),
        'end': fmt(end),
      });
      final response = await authorizedGet(uri.toString());
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ [IMOU] Lỗi lấy đoạn ghi (HTTP ${response.statusCode}): ${response.body}');
        return null;
      }
      final Map<String, dynamic> decoded = json.decode(response.body);
      final List<dynamic> raw = (decoded['data'] as List?) ?? const [];
      return raw.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getImouCameraRecords: $e');
      return null;
    }
  }

  /// GET .../imou-cameras/{cameraId}/events?begin=...&end=... — danh sách SỰ KIỆN báo động THẬT
  /// kèm ảnh thumbnail (getAlarmMessage, xem internal/imou/alarms.go phía Backend) — KHÁC HẲN
  /// records: API công khai dùng ĐẦY ĐỦ qua HTTP, không vướng giới hạn "cần SDK gốc" như phát lại
  /// video ghi hình liên tục.
  Future<List<Map<String, dynamic>>?> getImouCameraEvents(
    String homeId,
    int cameraId, {
    required DateTime begin,
    required DateTime end,
  }) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    try {
      final uri = Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}/imou-cameras/$cameraId/events').replace(queryParameters: {
        'begin': fmt(begin),
        'end': fmt(end),
      });
      final response = await authorizedGet(uri.toString());
      if (response.statusCode != 200) {
        if (kDebugMode) print('⚠️ [IMOU] Lỗi lấy sự kiện (HTTP ${response.statusCode}): ${response.body}');
        return null;
      }
      final Map<String, dynamic> decoded = json.decode(response.body);
      final List<dynamic> raw = (decoded['data'] as List?) ?? const [];
      return raw.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi getImouCameraEvents: $e');
      return null;
    }
  }

  // ============================================================================
  // ☁️ TUYA OPEN API (CLOUD-TO-CLOUD) — 1 tài khoản Tuya CHUNG cho cả hệ thống
  // ============================================================================
  // [KIẾN TRÚC — ĐÃ ĐỔI] Bỏ hẳn OAuth "Link App Account" (project Custom Development không hỗ
  // trợ, xác nhận qua tài liệu Tuya) — Backend dùng 1 tài khoản Tuya/Smart Life CHUNG
  // (TUYA_ACCOUNT_USERNAME/PASSWORD trong .env server) cho TOÀN hệ thống, không phân biệt theo
  // nhà ở tầng liên kết. App chỉ cần gọi "Đồng bộ" — không còn màn liên kết/trình duyệt/poll.
  // KHÔNG có method điều khiển riêng — thiết bị Tuya sau khi đồng bộ điều khiển được NGAY qua
  // publishCommand() có sẵn (mqtt_service.dart), y hệt thiết bị vật lý.

  /// POST /api/homes/{homeId}/tuya/sync — đăng nhập tài khoản Tuya chung (Backend tự lo) rồi
  /// đồng bộ TOÀN BỘ thiết bị của tài khoản đó vào nhà này. Trả (count, error).
  Future<({int? count, String? error})> syncTuyaDevices(String homeId) async {
    try {
      final response = await authorizedPost('$baseUrl/homes/${Uri.encodeComponent(homeId)}/tuya/sync');
      final Map<String, dynamic> decoded = json.decode(response.body);
      if (response.statusCode == 200) {
        final data = decoded['data'] as Map<String, dynamic>;
        return (count: (data['synced_count'] as num?)?.toInt() ?? 0, error: null);
      }
      return (count: null, error: (decoded['error'] ?? 'Lỗi không xác định từ Server').toString());
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi syncTuyaDevices: $e');
      return (count: null, error: 'Không thể kết nối đến máy chủ');
    }
  }
}