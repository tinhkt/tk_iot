import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;
import '../models/device_state.dart';
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
  /// GET devices/dashboard-sync sau đó. Trả về true/false đơn giản, App tự optimistic-update
  /// UI trước rồi gọi hàm này, revert nếu false (giống RoomGroupProvider.reorderRooms).
  Future<bool> setDeviceOrder(String homeId, List<String> orderedMacs) async {
    try {
      final response = await authorizedPut(
        '$baseUrl/homes/${Uri.encodeComponent(homeId)}/device-order',
        {'ordered_macs': orderedMacs},
      );
      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('❌ Lỗi mạng khi setDeviceOrder: $e');
      return false;
    }
  }
}