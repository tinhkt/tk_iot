import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io' show Platform, Process;
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // [ĐỢT 24] Nhớ mật khẩu WiFi cục bộ
import 'package:app_settings/app_settings.dart'; // Thư viện mở WiFi Settings
import 'package:permission_handler/permission_handler.dart'; // Xin quyền Camera trước khi quét QR
import '../../services/lan_discovery_service.dart'; // Quét thiết bị LAN qua UDP Broadcast
import '../../services/api_service.dart'; // [ĐỢT 25] Direct MAC Binding — đăng ký thẳng bằng MAC
import '../../localization/app_translations.dart';
import '../../widgets/ownership_conflict_dialog.dart'; // [LUỒNG CHUYỂN GIAO] Dialog 409 dùng chung

// ============================================================================
// POPUP CHÍNH: THÊM THIẾT BỊ
// ============================================================================
class AddDeviceDialog extends StatefulWidget {
  /// [LAN SCAN] "Sổ hộ khẩu" — tập MAC đã sở hữu (đã chuẩn hóa HOA + bỏ ":") do màn hình
  /// chính truyền vào, dùng để ẩn nút "Thêm ngay" cho thiết bị đã có trong hệ thống.
  final Set<String> ownedMacs;
  /// [ĐỢT 25 — DIRECT MAC BINDING] Nhà đích để đăng ký thiết bị ngay sau khi cấu hình WiFi AP
  /// Mode xong — BẮT BUỘC khác null để luồng AP Mode hoạt động (dialog tự gọi thẳng
  /// ApiService.addDevice, không còn đi vòng qua màn Quét mạng LAN nữa). Null vẫn hợp lệ cho
  /// các luồng khác (QR/Nhập tay/Quét LAN) — những luồng đó vẫn trả MAC về cho màn hình chính
  /// tự link như trước.
  final String? homeId;
  const AddDeviceDialog({super.key, this.ownedMacs = const {}, this.homeId});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> with SingleTickerProviderStateMixin {
  final MobileScannerController _cameraController = MobileScannerController();
  final TextEditingController _macController = TextEditingController();
  
  final Color tkGreen = const Color(0xFF00A651);

  // 0: Menu, 1: Quét QR, 2: Nhập tay, 3: Chế độ AP Tự động, 4: Quét mạng LAN (menu độc lập),
  // 5: Nhập WiFi nhà (App-driven provisioning — [ĐỢT 31] cũng là nơi hiện spinner lúc đang gửi,
  // xem _isSending),
  // 6: [GIAI ĐOẠN 110] Hướng dẫn cấp nguồn thiết bị — bước đệm TRƯỚC View 3 (số 6 trước đây bỏ
  // trống từ Đợt 31, nay tái dùng).
  // 7: [ĐỢT 25] Đăng ký trực tiếp bằng MAC (Direct MAC Binding — thay auto-jump sang View 4)
  int _currentView = 0;
  bool _isProcessing = false;

  // Trạng thái cho luồng quét AP Mode
  Timer? _apDetectionTimer;
  late AnimationController _pulseController;
  bool isConnectedToHub = false;

  // --- [ĐỢT 22] Trạng thái cho luồng CÀI ĐẶT WIFI App-driven (thay thế captive portal HTML) ---
  // Luồng: phát hiện đã nối vào AP thiết bị (isConnectedToHub, ở trên) -> quét WiFi xung quanh
  // qua chính thiết bị (GET /api/scan + poll /api/scan_res) -> user chọn/gõ SSID+mật khẩu ngay
  // trong App -> gọi POST /api/setup_connect (form-urlencoded, [ĐỢT 27] — KHÔNG phải JSON) ->
  // thiết bị tự lưu + khởi động lại vào mạng nhà -> App đăng ký TRỰC TIẾP bằng MAC đã biết
  // ([ĐỢT 25], View 7) — KHÔNG còn quét mạng LAN ở bước này nữa.
  final TextEditingController _wifiSsidController = TextEditingController();
  final TextEditingController _wifiPassController = TextEditingController();
  bool _obscureWifiPass = true;
  // [ĐỢT 26] User tự quyết định có lưu mật khẩu WiFi cục bộ hay không — mặc định BẬT (tối ưu
  // UX auto-fill lần sau), nhưng tắt đi phải tôn trọng tuyệt đối (xóa cả bản ghi cũ nếu có).
  bool _saveWifi = true;
  List<Map<String, dynamic>> _wifiScanResults = [];
  bool _isScanningWifi = false;
  Timer? _wifiScanPollTimer;
  // [ĐỢT 31 — GATEKEEPER] Không còn chuyển sang View riêng khi gửi WiFi nữa — spinner hiện
  // NGAY TRÊN View 5 (form nhập WiFi), user không bao giờ rời màn hình này cho tới khi có kết
  // quả THẬT (200 OK -> View 7, hoặc hết 3 lần thử -> SnackBar, vẫn đứng nguyên tại đây).
  bool _isSending = false;

  // --- Trạng thái cho luồng QUÉT MẠNG LAN (dùng LanDiscoveryService) — vẫn dùng cho mục menu
  // "Quét mạng LAN" độc lập (View 4); KHÔNG còn tự động nhảy tới đây sau khi cấu hình AP Mode.
  final LanDiscoveryService _lanService = LanDiscoveryService();
  StreamSubscription<List<LanDevice>>? _lanSub;
  List<LanDevice> _lanDevices = [];
  bool _isScanning = false;

  // --- [ĐỢT 25] Trạng thái ĐĂNG KÝ TRỰC TIẾP BẰNG MAC (Direct MAC Binding) ---
  // Luồng mới: /api/check_ip (View 3) giờ trả kèm MAC thật của thiết bị -> lưu vào
  // _provisioningMac -> sau khi /api/setup_connect (View 5) thành công, KHÔNG còn nhảy sang
  // Quét mạng LAN nữa — gọi thẳng ApiService.addDevice(homeId, _provisioningMac) ở View 7.
  String? _provisioningMac;
  bool _isRegisteringDevice = false;
  // null = đang chạy/chưa thử; khác null = đã dừng hẳn, đang hiện lỗi cho user quyết định
  AddDeviceStatus? _registerFailStatus;
  String? _registerFailMessage;
  // [LUỒNG CHUYỂN GIAO] Chỉ có giá trị khi _registerFailStatus == ownershipConflict — email chủ
  // cũ ĐÃ CHE sẵn từ Backend (vd "sale.****@gmail.com"), hiển thị y nguyên trong Dialog chuyên
  // biệt (xem _buildOwnershipConflictDialog) thay vì SnackBar lỗi chung chung.
  String? _conflictOwnerEmailMask;
  int _registerAttempts = 0;
  Timer? _registerRetryTimer;
  static const int _maxRegisterAttempts = 8; // ~ (chờ Internet tối đa 10s) + 7×2s retry ≈ 24s tổng
  // [ĐỢT 29] true = đang chờ điện thoại có Internet thật (chưa gọi Cloud), khác với
  // _isRegisteringDevice (đang gọi ApiService.addDevice thật) — 2 trạng thái hiển thị khác nhau.
  bool _isWaitingForInternet = false;
  // [ĐỢT 32 — HARD GATEKEEPER] true = đã hết 15s chờ mà VẪN không có Internet thật — dừng hẳn,
  // hiện thông báo + nút "HOÀN TẤT ĐĂNG KÝ" thủ công, KHÔNG tự ý gọi Backend mù quáng.
  bool _noInternetGate = false;

  @override
  void initState() {
    super.initState();
    // Tạo hiệu ứng sóng Radar chớp tắt
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // Lắng nghe kết quả quét LAN từ service (đã khử trùng MAC) -> vẽ lại UI
    _lanSub = _lanService.devices.listen((list) {
      if (!mounted) return;
      setState(() {
        _lanDevices = list;
        _isScanning = _lanService.isScanning;
      });
    });
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _macController.dispose();
    _stopAPDetection();
    _lanSub?.cancel();
    _lanService.dispose(); // đóng UDP socket + hủy timer khi thoát, tránh rò tài nguyên
    _pulseController.dispose();
    _wifiScanPollTimer?.cancel();
    _wifiSsidController.dispose();
    _wifiPassController.dispose();
    _registerRetryTimer?.cancel();
    super.dispose();
  }

  // ==========================================================================
  // 🔑 [ĐỢT 24] GHI NHỚ MẬT KHẨU WIFI CỤC BỘ (SharedPreferences) — một khóa duy nhất chứa
  // JSON map {"Tên WiFi":"mật khẩu"}. KHÔNG dùng flutter_secure_storage vì đây chỉ là tiện ích
  // auto-fill lại đúng mật khẩu nhà đã gõ trước đó (giảm gõ lại khi cài thêm thiết bị mới cùng
  // WiFi), không phải bí mật cấp tài khoản như JWT/refresh token.
  static const String _wifiCredsPrefsKey = 'saved_wifi_credentials';

  Future<Map<String, String>> _loadSavedWifiCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_wifiCredsPrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveWifiCredential(String ssid, String password) async {
    if (ssid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final creds = await _loadSavedWifiCredentials();
    creds[ssid] = password;
    await prefs.setString(_wifiCredsPrefsKey, jsonEncode(creds));
  }

  // [ĐỢT 26] User tắt Checkbox "Lưu mạng WiFi này" -> tôn trọng TUYỆT ĐỐI: nếu SSID này từng
  // được lưu ở một lần cài đặt trước, xóa hẳn bản ghi cũ khỏi Local Storage thay vì chỉ đơn
  // giản "không lưu thêm" — tránh mật khẩu cũ vẫn còn sống sót khi user chủ ý không muốn nhớ nữa.
  Future<void> _forgetWifiCredential(String ssid) async {
    if (ssid.isEmpty) return;
    final creds = await _loadSavedWifiCredentials();
    if (!creds.containsKey(ssid)) return;
    creds.remove(ssid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wifiCredsPrefsKey, jsonEncode(creds));
  }

  // ==========================================================================
  // 📶 [ĐỢT 22] CÀI ĐẶT WIFI APP-DRIVEN — thay hẳn giao diện HTML captive portal thủ công.
  // Gọi thẳng API cục bộ trên chính thiết bị (192.168.4.1) mà firmware vừa được bổ sung
  // (wm.setWebServerCallback -> /api/check_ip, /api/scan, /api/scan_res, /api/setup_connect).
  // ==========================================================================
  Future<void> _scanWifiNetworks() async {
    setState(() {
      _isScanningWifi = true;
      _wifiScanResults = [];
    });
    try {
      await http.get(Uri.parse('http://192.168.4.1/api/scan')).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Bỏ qua — có thể thiết bị chưa kịp phục vụ request đầu, vòng poll bên dưới vẫn thử tiếp
    }

    _wifiScanPollTimer?.cancel();
    int attempts = 0;
    _wifiScanPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      attempts++;
      if (!mounted) { timer.cancel(); return; }
      try {
        final res = await http.get(Uri.parse('http://192.168.4.1/api/scan_res')).timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          if (data['status'] == 'done') {
            timer.cancel();
            final raw = (data['data'] as List?) ?? [];
            final list = raw
                .map((e) => {'ssid': (e['s'] ?? '').toString(), 'rssi': (e['r'] is int) ? e['r'] as int : int.tryParse('${e['r']}') ?? -100})
                .where((e) => (e['ssid'] as String).isNotEmpty)
                .toList();
            list.sort((a, b) => (b['rssi'] as int).compareTo(a['rssi'] as int));
            if (mounted) setState(() { _wifiScanResults = list; _isScanningWifi = false; });
            return;
          }
          if (data['status'] == 'error') {
            timer.cancel();
            if (mounted) setState(() => _isScanningWifi = false);
            return;
          }
        }
      } catch (_) {
        // Rớt 1 nhịp poll — thử lại ở lần kế, chỉ dừng hẳn khi hết số lần cho phép bên dưới
      }
      if (attempts >= 10) {
        timer.cancel();
        if (mounted) setState(() => _isScanningWifi = false);
      }
    });
  }

  Future<void> _submitWifiCredentials() async {
    final String ssid = _wifiSsidController.text.trim();
    final String pass = _wifiPassController.text;
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppTranslations.of(context, listen: false).text('wifi_ssid_required')),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    _wifiScanPollTimer?.cancel();

    // [ĐỢT 31 — GATEKEEPER] KHÔNG chuyển _currentView nữa — spinner bật ngay trên View 5 (form
    // nhập WiFi hiện tại) qua _isSending. User chỉ rời màn này khi có 200 OK THẬT (sang View 7)
    // hoặc bấm thử lại thủ công — không còn "nhảy cóc" sang bất kỳ view nào khác giữa chừng.
    bool isSuccess = false;
    setState(() { _isSending = true; });

    for (int i = 0; i < 3; i++) { // Thử tối đa 3 lần
      try {
        // TUYỆT ĐỐI không dùng jsonEncode/header JSON — truyền thẳng Map<String,String> làm
        // body, gói http tự set application/x-www-form-urlencoded + tự mã hoá, khớp CHÍNH XÁC
        // cách ESP8266WebServer::arg() (và httpd_query_key_value() bên Hub V38) giải mã native.
        final response = await http.post(
          Uri.parse('http://192.168.4.1/api/setup_connect'),
          body: {'ssid': ssid, 'pass': pass},
        ).timeout(const Duration(seconds: 4)); // Đợi mỗi lần 4 giây

        // [HOÀN TÁC] Bỏ xác thực body "tuan_kiet_ok" — "Erase All Flash Contents" +
        // ESP.eraseConfig() (firmware) đã trị dứt điểm gốc rễ thật (Flash Corruption/Crash),
        // không phải do 200 OK giả mạo. Quay về điều kiện gốc để đồng bộ tuyệt đối với các
        // thiết bị cũ trên thị trường (chỉ trả "\"status\":\"ok\"", không có mật mã mới).
        if (response.statusCode == 200) {
          isSuccess = true;
          break; // ĐÃ NHẬN 200 OK TỪ ESP -> THOÁT LẶP
        }
      } catch (e) {
        // [CHẨN ĐOÁN] In rõ loại Exception thật (vd "SocketException: Network is
        // unreachable" khi máy đang route qua 4G, không có đường tới 192.168.4.1) — lỗi
        // này KHÔNG được coi là thành công, isSuccess vẫn giữ nguyên false, vòng lặp
        // chỉ đợi 1s rồi thử lại lần kế (KHÔNG break, KHÔNG set isSuccess=true ở đây).
        if (kDebugMode) print('⚠️ [WIFI SETUP] Lỗi gửi WiFi lần ${i + 1}/3: $e');
        await Future.delayed(const Duration(seconds: 1)); // Lỗi thì chờ 1s rồi thử lại
      }
    }

    if (!mounted) return;
    setState(() { _isSending = false; });

    if (isSuccess) {
      // CHỈ KHI CHẮC CHẮN 100% ESP NHẬN LỆNH MỚI ĐI TIẾP — lưu mật khẩu SAU khi đã xác nhận
      // thành công thật, không lưu "chạy trước" như các đợt cũ.
      if (_saveWifi) {
        await _saveWifiCredential(ssid, pass);
      } else {
        await _forgetWifiCredential(ssid);
      }
      if (!mounted) return;
      _proceedToDeviceRegistration();
    } else {
      // THẤT BẠI: Giữ nguyên View 5, báo lỗi nhẹ nhàng, tuyệt đối không nhảy View.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppTranslations.of(context, listen: false).text('wifi_send_failed_error')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  // [ĐỢT 25 — DIRECT MAC BINDING] Trước đây ở đây chờ 6s rồi TỰ NHẢY sang màn Quét mạng LAN
  // (UDP Broadcast) để "mò" lại thiết bị — rườm rà, dễ tịt ngòi nếu Router chặn Broadcast, và
  // còn bắt user tự bấm "Thêm ngay" thêm một bước nữa. Đã có MAC thật từ /api/check_ip (View 3,
  // lưu trong _provisioningMac) nên đăng ký THẲNG lên Backend bằng chính MAC đó.
  void _proceedToDeviceRegistration() {
    setState(() => _currentView = 7);
    _registerDeviceDirect();
  }

  // ==========================================================================
  // 🎯 [ĐỢT 25] ĐĂNG KÝ TRỰC TIẾP BẰNG MAC (Direct MAC Binding)
  // ==========================================================================
  /// Gọi ApiService.addDevice(homeId, mac) — tự thử lại khi thiết bị CHƯA kịp lên tiếng MQTT
  /// (notOnlineYet, 404 — tạm thời, do vừa đổi WiFi cần vài giây associate + kết nối Broker),
  /// nhưng DỪNG NGAY LẬP TỨC khi gặp lỗi VĨNH VIỄN (ownershipConflict 409 / forbidden 403) —
  /// không có ý nghĩa gì để thử lại một MAC đã thuộc về người khác.
  Future<void> _registerDeviceDirect() async {
    final String? homeId = widget.homeId;
    final String? mac = _provisioningMac;

    setState(() {
      _isRegisteringDevice = true;
      _registerFailStatus = null;
      _registerFailMessage = null;
      _conflictOwnerEmailMask = null;
      _registerAttempts = 0;
      _noInternetGate = false;
    });

    if (homeId == null || homeId.isEmpty || mac == null || mac.isEmpty) {
      // Không đủ dữ liệu để đăng ký (firmware cũ chưa cập nhật JSON, hoặc dialog được mở mà
      // không truyền homeId) — báo lỗi rõ ràng thay vì treo màn Loading vô thời hạn.
      if (mounted) {
        setState(() {
          _isRegisteringDevice = false;
          _registerFailStatus = AddDeviceStatus.otherError;
          _registerFailMessage = null; // View tự dịch theo status khi message null
        });
      }
      return;
    }

    // [ĐỢT 32 — HARD GATEKEEPER] Lỗi "Không kết nối máy chủ" trước đây xảy ra vì App gọi
    // ApiService().addDevice() lúc điện thoại CHƯA KỊP nhả AP của ESP. Bản trước (Đợt 31) hết
    // 15s vẫn CỐ gọi _attemptRegister() mù quáng dù chưa có mạng — sửa dứt điểm: hasInternet
    // khai báo NGOÀI vòng lặp, biết CHẮC CHẮN giá trị cuối cùng sau khi thoát vòng lặp, và chỉ
    // gọi Backend khi giá trị đó THẬT SỰ là true.
    final bool hasInternet = await _waitForInternetOnce();
    if (!mounted) return;

    if (hasInternet) {
      await _attemptRegister(homeId, mac);
    } else {
      // TUYỆT ĐỐI KHÔNG gọi _attemptRegister() — dừng hẳn, tắt spinner, chờ user tự xác nhận
      // đã có mạng rồi bấm nút "HOÀN TẤT ĐĂNG KÝ" (xem _retryAfterInternetGate + View 7).
      setState(() {
        _isRegisteringDevice = false;
        _noInternetGate = true;
      });
    }
  }

  // Poll Internet mỗi 2 giây, tối đa maxWaitMs — trả về giá trị CUỐI CÙNG thật sự đo được (không
  // suy đoán). Dùng chung cho cả lần chờ tự động đầu tiên VÀ nút "HOÀN TẤT ĐĂNG KÝ" thủ công.
  //
  // [CHỐNG DNS HIJACKING — lỗ hổng thật] Trước đây dùng InternetAddress.lookup('google.com') —
  // SAI: khi điện thoại còn nối AP của ESP, DNSServer captive portal (WiFiManager) trả lời MỌI
  // truy vấn DNS bằng chính IP của nó (192.168.4.1) thay vì lỗi NXDOMAIN, nên lookup() "thành
  // công" giả tạo NGAY LẬP TỨC dù máy chưa hề thoát khỏi AP -> Gatekeeper bị xuyên thủng, gọi
  // thẳng Cloud API khi vẫn kẹt trong mạng ESP -> văng lỗi tức thời. Thay bằng HTTPS GET thật tới
  // Backend: ESP không có chứng chỉ TLS hợp lệ cho api.iot-smart.vn nên KHÔNG THỂ giả mạo được
  // response HTTPS — round-trip chỉ thành công khi điện thoại đã thật sự thoát AP và có Internet.
  Future<bool> _waitForInternetOnce({int maxWaitMs = 15000}) async {
    // Ép chờ ESP tắt sóng AP (firmware đợi ~1.5s rồi mới softAPdisconnect/chuyển WIFI_STA) TRƯỚC
    // KHI làm bất cứ việc kiểm tra nào — bắt kịp đúng lúc AP vẫn còn sống sẽ luôn fail giả.
    await Future.delayed(const Duration(seconds: 2));

    setState(() => _isWaitingForInternet = true);
    bool hasInternet = false;
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < maxWaitMs) {
      try {
        // Endpoint công khai (không cần JWT), nhẹ — chỉ cần round-trip HTTPS thành công là đủ
        // bằng chứng, không quan tâm nội dung trả về.
        final checkRes = await http
            .get(Uri.parse('${ApiService.baseUrl}/firmware/device-check'))
            .timeout(const Duration(seconds: 3));
        hasInternet = checkRes.statusCode >= 200; // Chạm được Backend thật -> chắc chắn có Internet
      } catch (_) {
        // Lỗi bắt tay TLS / timeout / rớt mạng -> vẫn kẹt ở ESP (không có TLS thật) hoặc chưa
        // có 4G/WiFi thật nào
        hasInternet = false;
      }
      if (hasInternet) break;
      if (!mounted) return false;
      await Future.delayed(const Duration(seconds: 2));
    }
    if (mounted) setState(() => _isWaitingForInternet = false);
    return hasInternet;
  }

  // [ĐỢT 32] Nút "HOÀN TẤT ĐĂNG KÝ" — user tự xác nhận đã đổi mạng xong rồi bấm, App kiểm tra
  // lại Internet MỘT LẦN NỮA (không đoán mò) trước khi thật sự gọi lên Backend.
  Future<void> _retryAfterInternetGate() async {
    final String? homeId = widget.homeId;
    final String? mac = _provisioningMac;
    if (homeId == null || homeId.isEmpty || mac == null || mac.isEmpty) return;

    setState(() => _noInternetGate = false);
    final bool hasInternet = await _waitForInternetOnce(maxWaitMs: 5000); // đã bấm nút = user tin là có mạng rồi, chỉ xác nhận nhanh
    if (!mounted) return;

    if (hasInternet) {
      setState(() => _isRegisteringDevice = true);
      await _attemptRegister(homeId, mac);
    } else {
      setState(() => _noInternetGate = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppTranslations.of(context, listen: false).text('still_no_internet_error')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _attemptRegister(String homeId, String mac) async {
    _registerAttempts++;
    final result = await ApiService().addDevice(homeId, mac);
    if (!mounted) return;

    if (result.status == AddDeviceStatus.success) {
      // Thành công -> đóng TOÀN BỘ dialog, trả MAC về màn hình chính (idempotent — Backend
      // cho phép gọi lại cùng homeId) để tái dùng NGUYÊN VẸN luồng SnackBar+làm mới danh sách
      // đã có sẵn ở dashboard_screen.dart/_linkScannedDevice, không cần viết lại UI thành công.
      Navigator.pop(context, mac);
      return;
    }

    if (result.status == AddDeviceStatus.notOnlineYet && _registerAttempts < _maxRegisterAttempts) {
      // Lỗi TẠM THỜI — thiết bị có thể vẫn đang associate WiFi/kết nối Broker, thử lại sau 2s.
      setState(() {}); // vẽ lại số lần thử cho user thấy tiến trình
      _registerRetryTimer?.cancel();
      _registerRetryTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _attemptRegister(homeId, mac);
      });
      return;
    }

    // Lỗi VĨNH VIỄN (ownershipConflict/forbidden) hoặc đã hết số lần thử cho phép -> dừng hẳn.
    setState(() {
      _isRegisteringDevice = false;
      _registerFailStatus = result.status;
      _registerFailMessage = result.message;
      _conflictOwnerEmailMask = result.maskedOwnerEmail;
    });

    // [LUỒNG CHUYỂN GIAO] 409 -> bung Dialog chuyên biệt NGAY (thay vì chỉ đổi View 7 âm thầm) —
    // đúng yêu cầu "không báo lỗi chung chung", user thấy ngay tài khoản đã che + nút hành động.
    if (result.status == AddDeviceStatus.ownershipConflict && mac.isNotEmpty) {
      _showOwnershipConflictDialog(mac);
    }
  }

  // [LUỒNG CHUYỂN GIAO] Dialog chuyên biệt khi MAC đã có chủ — nay DÙNG CHUNG với luồng QR/Nhập
  // tay/Quét LAN (xem showOwnershipConflictDialog trong widgets/ownership_conflict_dialog.dart),
  // tránh 2 nơi cùng vẽ 1 Dialog dễ lệch nhau khi sửa sau này.
  Future<void> _showOwnershipConflictDialog(String mac) {
    return showOwnershipConflictDialog(context, mac: mac, maskedOwnerEmail: _conflictOwnerEmailMask);
  }

  // ==========================================================================
  // 🛰️ QUÉT MẠNG LAN — ủy quyền cho LanDiscoveryService (UDP Broadcast)
  // ==========================================================================
  // Chuyển sang View 4 rồi khởi động service; kết quả chảy về qua _lanSub -> setState.
  Future<void> _startLanScan() async {
    setState(() => _currentView = 4);
    await _lanService.start();
  }

  // --- XIN QUYỀN CAMERA THEO CHUẨN (TRƯỚC KHI MỞ LUỒNG STREAM) ---
  /// Trình tự chuẩn Apple/Google:
  ///   1. Đã cấp quyền -> đi tiếp ngay.
  ///   2. Chưa hỏi lần nào -> bật hộp thoại xin quyền của hệ điều hành.
  ///   3. Bị từ chối VĨNH VIỄN (iOS chỉ cho hỏi 1 lần) -> hướng dẫn mở Cài đặt App.
  /// Desktop (Windows/macOS/Linux) bỏ qua — permission_handler chỉ quản Android/iOS.
  /// Không có bước này + thiếu NSCameraUsageDescription trong Info.plist là iOS
  /// kill app ngay khoảnh khắc chạm vào camera (đúng hiện tượng văng về màn hình chính).
  Future<bool> _ensureCameraPermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    // Gọi từ chuỗi tap-handler (InkWell.onTap của mục "Quét mã QR") -> listen: false, tránh
    // "liệt nút" (context.watch() ngoài pha build thật — xem app_translations.dart).
    final t = AppTranslations.of(context, listen: false);

    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    // Chưa có quyền -> bật hộp thoại hệ thống hỏi người dùng
    status = await Permission.camera.request();
    if (status.isGranted) return true;
    if (!mounted) return false;

    if (status.isPermanentlyDenied) {
      // iOS không bao giờ hiện lại hộp thoại lần 2 — chỉ còn đường vào Cài đặt
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.text('camera_permission_locked')),
        backgroundColor: Colors.orange,
        action: SnackBarAction(label: t.text('open_settings_action'), textColor: Colors.white, onPressed: openAppSettings),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.text('camera_permission_needed')),
        backgroundColor: Colors.redAccent,
      ));
    }
    return false;
  }

  // --- HÀM MỞ CÀI ĐẶT WIFI CỦA ĐIỆN THOẠI ---
  void _openWiFiSettings() async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', 'ms-settings:network-wifi']);
      } else {
        AppSettings.openAppSettings(type: AppSettingsType.wifi);
      }
    } catch (e) {
      if (kDebugMode) print("Lỗi mở cài đặt mạng: $e");
    }
  }

  // --- QUÉT NGẦM MẠNG WIFI CỦA THIẾT BỊ ---
  void _startAPDetection() {
    _stopAPDetection();
    setState(() {
      isConnectedToHub = false;
    });
    _pulseController.repeat(reverse: true);

    // Cứ 2 giây sẽ Ping vào mạch ESP32 một lần
    _apDetectionTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;
      
      try {
        // IP mặc định của ESP32 khi ở chế độ AP Mode
        final response = await http.get(
          Uri.parse('http://192.168.4.1/api/check_ip'),
        ).timeout(const Duration(seconds: 1)); // Timeout cực nhanh để không đơ app
        
        if (response.statusCode == 200) {
          // Bắt được mạch ESP32! [ĐỢT 25] Firmware nay trả kèm JSON {"mac":"...","device_type":"..."}
          // thay vì text/plain IP — lưu lại MAC NGAY TẠI ĐÂY để Đăng ký trực tiếp sau này, không
          // cần quét LAN UDP để "mò" lại MAC như luồng cũ.
          String? mac;
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            mac = (data['mac'] as String?)?.trim().toUpperCase();
          } catch (_) {
            // Firmware cũ chưa cập nhật (còn trả text/plain) — vẫn coi là "đã kết nối AP" để
            // không chặn luồng, nhưng _provisioningMac null thì View 7 sẽ báo lỗi rõ ràng.
          }
          _stopAPDetection();
          if (mounted) {
            setState(() {
              isConnectedToHub = true;
              _provisioningMac = (mac != null && mac.isNotEmpty) ? mac : null;
            });
            _pulseController.stop();
            
            // Đợi 1.5s cho người dùng nhìn thấy dấu Check Xanh rồi chuyển sang màn hình nhập
            // WiFi nhà NGAY TRONG APP (thay vì bắt user tự mở trình duyệt vào captive portal).
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                setState(() => _currentView = 5);
                _scanWifiNetworks();
              }
            });
          }
        }
      } catch (e) {
        // Bỏ qua lỗi kết nối (Do người dùng chưa bấm chọn WiFi hoặc đang dùng 4G/WiFi nhà)
      }
    });
  }

  void _stopAPDetection() {
    _apDetectionTimer?.cancel();
    _apDetectionTimer = null;
    _pulseController.stop();
  }

  // --- [BẢN CẬP NHẬT MỚI]: HÀM TRẢ VỀ MÃ MAC CHO MÀN HÌNH CHÍNH XỬ LÝ ---
  Future<void> _processLinkDevice(String rawMac) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Chuẩn hóa định dạng chuỗi
    String cleanMac = rawMac.replaceAll('MAC:', '').replaceAll('SN:', '').replaceAll(':', '').trim();

    if (cleanMac.isEmpty) {
      // Gọi từ chuỗi tap-handler (onPressed/onDetect/onTap "Thêm ngay") -> listen: false.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppTranslations.of(context, listen: false).text('invalid_device_id')), backgroundColor: Colors.redAccent));
      setState(() => _isProcessing = false);
      return;
    }

    if (_currentView == 1) _cameraController.stop();

    // 👈 KHÔNG GỌI API Ở ĐÂY NỮA. CHỈ ĐÓNG POPUP VÀ NÉM MÃ MAC VỀ CHO MÀN HÌNH CHÍNH
    Navigator.pop(context, cleanMac); 
  }

  // --- WIDGET HEADER ---
  Widget _buildHeader(String title, Color textMain, Color textSub) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_currentView != 0)
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: textMain, size: 18),
            onPressed: () {
              if (_currentView == 1) _cameraController.stop();
              _stopAPDetection();
              _lanService.stop(); // đóng socket UDP khi rời màn quét LAN
              _wifiScanPollTimer?.cancel(); // dừng poll /api/scan_res khi rời màn nhập WiFi
              setState(() => _currentView = 0);
            },
            splashRadius: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          )
        else
          const SizedBox(width: 18), 

        Expanded(
          child: Text(
            title, 
            style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        
        IconButton(
          icon: Icon(Icons.close_rounded, color: textSub, size: 20),
          onPressed: () => Navigator.pop(context),
          splashRadius: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }

  // --- VIEW 0: MENU ---
  Widget _buildSelectionMenu(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    return Padding(
      // [FIX — Whitespace lãng phí] showAppDialog() ĐÃ tự thêm padding 24 quanh toàn bộ nội
      // dung (xem app_ui_wrappers.dart) — Padding 20 cũ ở đây CỘNG DỒN thành 44px mỗi bên,
      // ép cột nội dung hẹp lại khiến 4 thẻ tính năng trông co cụm dù viền ngoài popup lại
      // rất thừa trắng. Giảm còn 12 — chỉ áp dụng RIÊNG cho add_device_dialog.dart, không đụng
      // vào padding 24 dùng chung của showAppDialog (sẽ ảnh hưởng MỌI popup khác trong app).
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t.text('add_new_device_title'), textMain, textSub),
          const SizedBox(height: 16),
          Text(t.text('add_device_intro'), style: TextStyle(color: textSub, fontSize: 13, height: 1.4)),
          const SizedBox(height: 20),

          // [CHỐNG LỒNG KÍNH] 4 mục menu dưới đây PHẲNG VĨNH VIỄN (Material+InkWell, không
          // BackdropFilter riêng) — cả khối build() ở trên đã là 1 lớp kính (showAppDialog),
          // KHÔNG được đổi sang AppCard (sẽ lồng 2 lớp BackdropFilter, xem comment build()).
          // 1. Quét QR
          Material(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                // [FIX CRASH iOS] Xin quyền Camera xong xuôi rồi MỚI mở luồng stream;
                // bị từ chối thì đứng lại ở menu kèm hướng dẫn, không đâm đầu vào camera
                final bool granted = await _ensureCameraPermission();
                if (!granted || !mounted) return;
                setState(() => _currentView = 1);
                _cameraController.start();
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.qr_code_scanner_rounded, color: tkGreen, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.text('scan_qr_title'), style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(t.text('scan_qr_sub'), style: TextStyle(color: textSub, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 2. Chế độ Wi-Fi AP Tự động
          Material(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              // [GIAI ĐOẠN 110] Trước đây bấm vào đây NHẢY THẲNG vào radar dò AP (View 3) —
              // người dùng chưa kịp đọc hướng dẫn gì đã phải chờ máy dò trong khi có thể còn
              // chưa cắm nguồn/chưa đợi đèn nháy xong. Nay chèn View 6 (hướng dẫn cấp nguồn)
              // làm bước ĐỆM bắt buộc trước — _startAPDetection() dời qua nút "Tiếp tục" của
              // View 6 (xem _buildApInstructionView), KHÔNG gọi ở đây nữa.
              onTap: () => setState(() => _currentView = 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.wifi_tethering_rounded, color: Colors.orange, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.text('ap_mode_title'), style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(t.text('ap_mode_sub'), style: TextStyle(color: textSub, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. Nhập tay
          Material(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _currentView = 2),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.keyboard_alt_outlined, color: Colors.blue, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.text('manual_entry_title'), style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(t.text('manual_entry_sub'), style: TextStyle(color: textSub, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 4. Quét mạng LAN (UDP Broadcast tự động tìm thiết bị cùng WiFi)
          Material(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _startLanScan,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.wifi_find_rounded, color: Colors.purple, size: 24)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.text('lan_scan_title'), style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(t.text('lan_scan_sub'), style: TextStyle(color: textSub, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- VIEW 4: QUÉT MẠNG LAN — DANH SÁCH THIẾT BỊ TÌM THẤY ---
  Widget _buildLanScanView(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    final devices = _lanDevices;
    final bool empty = devices.isEmpty;
    return Padding(
      // [FIX — Whitespace lãng phí] showAppDialog() ĐÃ tự thêm padding 24 quanh toàn bộ nội
      // dung (xem app_ui_wrappers.dart) — Padding 20 cũ ở đây CỘNG DỒN thành 44px mỗi bên,
      // ép cột nội dung hẹp lại khiến 4 thẻ tính năng trông co cụm dù viền ngoài popup lại
      // rất thừa trắng. Giảm còn 12 — chỉ áp dụng RIÊNG cho add_device_dialog.dart, không đụng
      // vào padding 24 dùng chung của showAppDialog (sẽ ảnh hưởng MỌI popup khác trong app).
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t.text('lan_scan_header'), textMain, textSub),
          const SizedBox(height: 16),

          // Dòng trạng thái: đang quét (spinner "Đang tìm kiếm...") hoặc đã xong
          Row(
            children: [
              if (_isScanning)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple))
              else
                Icon(empty ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: empty ? Colors.redAccent : tkGreen, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isScanning
                      ? t.text('lan_scanning_status')
                      : (empty
                          ? t.text('lan_scan_empty')
                          // [GIỮ NGUYÊN BIẾN ĐỘNG] devices.length — số thiết bị tìm thấy thật.
                          : '${t.text('found_devices_prefix')}${devices.length}${t.text('found_devices_suffix')}'),
                  style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              // Hết giờ không thấy gì -> nút "Thử lại"
              if (!_isScanning)
                TextButton.icon(
                  onPressed: _startLanScan,
                  icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.purple),
                  label: Text(t.text('retry'), style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Danh sách thiết bị: mỗi hàng tên + MAC + IP (+ loại), kèm nút "Thêm ngay"
          if (!empty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: devices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final LanDevice d = devices[index];
                  // [CHUẨN HÓA MAC] Đưa MAC quét được về cùng dạng "sổ hộ khẩu": HOA + bỏ ":"
                  final String scannedMac = d.mac.toUpperCase().replaceAll(':', '');
                  final bool isAlreadyAdded = widget.ownedMacs.contains(scannedMac);
                  // [CHỐNG LỒNG KÍNH] Phẳng vĩnh viễn — cùng lý do 4 mục menu ở trên
                  // (_buildSelectionMenu), thẻ này nằm trong nội dung ĐÃ được showAppDialog
                  // bọc kính ở lớp ngoài cùng rồi.
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.developer_board_rounded, color: tkGreen, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.deviceType.isNotEmpty ? '${d.name}  •  ${d.deviceType}' : d.name,
                                style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text('MAC: ${d.mac}', style: TextStyle(color: textSub, fontSize: 11, fontFamily: 'monospace')),
                              Text('IP: ${d.ip}', style: TextStyle(color: textSub, fontSize: 11, fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                        // [CHECK SỔ HỘ KHẨU] Đã có trong hệ thống -> nhãn "Đã thêm" (không cho thêm lại);
                        // chưa có -> giữ nút "Thêm ngay" như cũ (tái sử dụng _processLinkDevice).
                        if (isAlreadyAdded)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle, color: tkGreen, size: 18),
                              const SizedBox(width: 6),
                              Text(t.text('already_added_label'), style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          )
                        else
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: tkGreen, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: _isProcessing ? null : () => _processLinkDevice(d.mac),
                            child: Text(t.text('add_now_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // --- VIEW 1: CAMERA SCANNER ---
  Widget _buildScannerView(Color textMain, Color textSub, AppTranslations t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // [FIX — Whitespace lãng phí] showAppDialog() ĐÃ tự thêm padding 24 quanh toàn bộ nội
      // dung (xem app_ui_wrappers.dart) — Padding 20 cũ ở đây CỘNG DỒN thành 44px mỗi bên,
      // ép cột nội dung hẹp lại khiến 4 thẻ tính năng trông co cụm dù viền ngoài popup lại
      // rất thừa trắng. Giảm còn 12 — chỉ áp dụng RIÊNG cho add_device_dialog.dart, không đụng
      // vào padding 24 dùng chung của showAppDialog (sẽ ảnh hưởng MỌI popup khác trong app).
      padding: const EdgeInsets.all(12.0),
          child: _buildHeader(t.text('scan_qr_header'), textMain, textSub),
        ),
        SizedBox(
          height: 300, 
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                MobileScanner(
                  controller: _cameraController,
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                      _processLinkDevice(barcodes.first.rawValue!);
                    }
                  },
                ),
                CustomPaint(painter: ScannerOverlayPainter(), child: Container()),
                Positioned(
                  top: 12, right: 16,
                  child: IconButton(
                    icon: ValueListenableBuilder(
                      valueListenable: _cameraController,
                      builder: (context, state, child) {
                        return Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off, color: state.torchState == TorchState.on ? tkGreen : Colors.white, size: 20);
                      },
                    ),
                    onPressed: () => _cameraController.toggleTorch(),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(t.text('scan_qr_hint'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
        )
      ],
    );
  }

  // --- VIEW 2: NHẬP THỦ CÔNG ---
  Widget _buildManualEntryView(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    return Padding(
      // [FIX — Whitespace lãng phí] showAppDialog() ĐÃ tự thêm padding 24 quanh toàn bộ nội
      // dung (xem app_ui_wrappers.dart) — Padding 20 cũ ở đây CỘNG DỒN thành 44px mỗi bên,
      // ép cột nội dung hẹp lại khiến 4 thẻ tính năng trông co cụm dù viền ngoài popup lại
      // rất thừa trắng. Giảm còn 12 — chỉ áp dụng RIÊNG cho add_device_dialog.dart, không đụng
      // vào padding 24 dùng chung của showAppDialog (sẽ ảnh hưởng MỌI popup khác trong app).
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t.text('manual_entry_header'), textMain, textSub),
          const SizedBox(height: 20),
          // [FORM SWEEP — GIỮ NGUYÊN TextField] Cần textCapitalization.characters +
          // style/letterSpacing tùy biến mà AppTextField chưa hỗ trợ (cùng lý do SN/MAC
          // field trong admin_system_screen.dart) — để nguyên tránh mất UX viết hoa MAC.
          TextField(
            controller: _macController,
            style: TextStyle(color: textMain, fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.bold),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: t.text('mac_sn_hint'),
              hintStyle: TextStyle(color: textSub.withValues(alpha: 0.4), letterSpacing: 0, fontWeight: FontWeight.normal, fontSize: 14),
              filled: true,
              fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => _processLinkDevice(_macController.text),
              child: _isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(t.text('confirm_connection_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // --- VIEW 6: [GIAI ĐOẠN 110] HƯỚNG DẪN CẤP NGUỒN — bước đệm TRƯỚC khi vào radar dò AP (View
  // 3). Thuần hiển thị hướng dẫn (icon minh hoạ vẽ bằng Icon/Animation có sẵn — dự án chưa có
  // asset GIF thật, dùng icon động thay thế để không tham chiếu file không tồn tại) — không gọi
  // bất kỳ API/HTTP nào, không có logic nào để "vỡ", nên không cần try-catch ở view này.
  Widget _buildApInstructionView(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    Widget step(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_outline_rounded, color: tkGreen, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: textMain, fontSize: 13, height: 1.45))),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t.text('ap_instruction_header'), textMain, textSub),
          const SizedBox(height: 24),

          // Minh hoạ: icon nguồn điện + sóng Wi-Fi nhấp nháy — thay cho GIF thật (chưa có asset
          // trong dự án). AnimatedBuilder dùng lại _pulseController đã có sẵn (khởi tạo ở
          // initState, dùng chung cho cả radar View 3) — tránh tạo thêm AnimationController mới.
          SizedBox(
            height: 110,
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final double t2 = _pulseController.isAnimating ? _pulseController.value : 0.5;
                  return Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.10 + t2 * 0.08), shape: BoxShape.circle),
                    child: Icon(Icons.bolt_rounded, color: Colors.orange.withValues(alpha: 0.6 + t2 * 0.4), size: 48),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          step(t.text('ap_instruction_step1')),
          step(t.text('ap_instruction_step2')),
          step(t.text('ap_instruction_step3')),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: tkGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: () {
                setState(() => _currentView = 3);
                _startAPDetection(); // Chỉ bắt đầu dò radar SAU KHI user xác nhận đã cấp nguồn
              },
              child: Text(t.text('ap_instruction_continue_btn'), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ),
        ],
      ),
    );
  }

  // --- VIEW 3: LUỒNG AP MODE TỰ ĐỘNG ---
  Widget _buildAPModeView(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    return Padding(
      // [FIX — Whitespace lãng phí] showAppDialog() ĐÃ tự thêm padding 24 quanh toàn bộ nội
      // dung (xem app_ui_wrappers.dart) — Padding 20 cũ ở đây CỘNG DỒN thành 44px mỗi bên,
      // ép cột nội dung hẹp lại khiến 4 thẻ tính năng trông co cụm dù viền ngoài popup lại
      // rất thừa trắng. Giảm còn 12 — chỉ áp dụng RIÊNG cho add_device_dialog.dart, không đụng
      // vào padding 24 dùng chung của showAppDialog (sẽ ảnh hưởng MỌI popup khác trong app).
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(t.text('ap_mode_header'), textMain, textSub),
          const SizedBox(height: 32),

          // HIỆU ỨNG RADAR HOẶC DẤU CHECK THÀNH CÔNG
          SizedBox(
            height: 120,
            child: Center(
              child: isConnectedToHub
                  ? TweenAnimationBuilder(
                      tween: Tween<double>(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      builder: (context, double value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            width: 100, height: 100,
                            decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: Icon(Icons.check_circle_rounded, color: tkGreen, size: 64),
                          ),
                        );
                      },
                    )
                  : AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 100 + (_pulseController.value * 20),
                          height: 100 + (_pulseController.value * 20),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.1 + (_pulseController.value * 0.1)),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.5 - (_pulseController.value * 0.3)),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(color: Colors.blueAccent.withValues(alpha: 0.2), shape: BoxShape.circle),
                              child: const Icon(Icons.wifi_tethering, color: Colors.blueAccent, size: 40),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          
          const SizedBox(height: 24),

          // TRẠNG THÁI VÀ HƯỚNG DẪN
          Text(
            isConnectedToHub ? t.text('connected_to_hub') : t.text('searching_device_network'),
            style: TextStyle(color: isConnectedToHub ? tkGreen : textMain, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            isConnectedToHub
              ? t.text('preparing_open_settings')
              : t.text('wifi_ap_instructions'),
            style: TextStyle(color: textSub, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // NÚT BẤM MỞ WIFI SETTINGS
          if (!isConnectedToHub)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.settings_suggest_rounded, size: 20),
                label: Text(t.text('open_wifi_settings_btn'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                onPressed: _openWiFiSettings,
              ),
            ),
        ],
      ),
    );
  }

  // --- VIEW 5: [ĐỢT 22] NHẬP WIFI NHÀ — App-driven, thay hẳn captive portal HTML ---
  Widget _buildWifiCredentialView(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    return Padding(
      // [FIX — Whitespace lãng phí] xem giải thích ở các _build*View khác trong file này.
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(t.text('wifi_setup_header'), textMain, textSub),
          const SizedBox(height: 16),

          // Danh sách mạng WiFi quét được TỪ CHÍNH thiết bị (App gọi /api/scan + /api/scan_res
          // qua 192.168.4.1) — không dùng WiFi scan của điện thoại vì điện thoại đang nối vào
          // AP thiết bị, không "thấy" được sóng nhà theo góc của chính thiết bị.
          Row(
            children: [
              if (_isScanningWifi)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent))
              else
                Icon(Icons.wifi_rounded, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isScanningWifi ? t.text('wifi_scanning_status') : (_wifiScanResults.isEmpty ? t.text('wifi_scan_empty_hint') : ''),
                  style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (!_isScanningWifi)
                TextButton.icon(
                  onPressed: _scanWifiNetworks,
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: Colors.blueAccent),
                  label: Text(t.text('wifi_rescan_btn'), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
          // [ĐỢT 24 — Bước 1] Lần quét ĐẦU TIÊN (chưa có kết quả nào) hiện khối Loading nổi
          // bật căn giữa thay vì chỉ dòng trạng thái nhỏ ở Row trên — đúng yêu cầu "vòng quay
          // Loading với text 'Đang tìm kiếm mạng WiFi xung quanh...'".
          if (_isScanningWifi && _wifiScanResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.blueAccent)),
                  const SizedBox(height: 14),
                  Text(t.text('wifi_scanning_status'), style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                ],
              ),
            ),
          if (_wifiScanResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: _wifiScanResults.length,
                itemBuilder: (context, index) {
                  final net = _wifiScanResults[index];
                  final String ssid = net['ssid'] as String;
                  final int rssi = net['rssi'] as int;
                  final bool selected = _wifiSsidController.text == ssid;
                  final IconData signalIcon = rssi >= -60 ? Icons.wifi_rounded : (rssi >= -75 ? Icons.wifi_2_bar_rounded : Icons.wifi_1_bar_rounded);
                  // [CHỐNG LỒNG KÍNH] Phẳng vĩnh viễn — cùng lý do các thẻ khác trong dialog này.
                  return Material(
                    color: selected ? tkGreen.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      // [ĐỢT 24 — AUTO-FILL] Chọn SSID xong -> tra ngay Local Storage; nếu WiFi
                      // này đã từng nhập mật khẩu ở lần cài thiết bị trước, tự điền lại luôn.
                      onTap: () async {
                        setState(() => _wifiSsidController.text = ssid);
                        final saved = await _loadSavedWifiCredentials();
                        final String? knownPass = saved[ssid];
                        if (knownPass != null && mounted) {
                          setState(() => _wifiPassController.text = knownPass);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(signalIcon, size: 18, color: selected ? tkGreen : textSub),
                            const SizedBox(width: 10),
                            Expanded(child: Text(ssid, style: TextStyle(color: selected ? tkGreen : textMain, fontSize: 13, fontWeight: selected ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (selected) Icon(Icons.check_circle_rounded, size: 16, color: tkGreen),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Ô SSID luôn hiện — cho phép gõ tay đè lên lựa chọn từ danh sách quét (mạng ẩn/2.4GHz
          // trùng tên 5GHz...), khớp đúng khả năng mà captive portal HTML gốc cũng cho phép.
          TextField(
            controller: _wifiSsidController,
            style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: t.text('wifi_ssid_hint'),
              hintStyle: TextStyle(color: textSub.withValues(alpha: 0.5), fontWeight: FontWeight.normal, fontSize: 13),
              prefixIcon: Icon(Icons.wifi_rounded, color: textSub, size: 18),
              filled: true,
              fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _wifiPassController,
            obscureText: _obscureWifiPass,
            style: TextStyle(color: textMain, fontSize: 14),
            decoration: InputDecoration(
              hintText: t.text('wifi_password_hint'),
              hintStyle: TextStyle(color: textSub.withValues(alpha: 0.5), fontSize: 13),
              prefixIcon: Icon(Icons.lock_outline_rounded, color: textSub, size: 18),
              suffixIcon: IconButton(
                icon: Icon(_obscureWifiPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: textSub, size: 18),
                onPressed: () => setState(() => _obscureWifiPass = !_obscureWifiPass),
              ),
              filled: true,
              fillColor: isDark ? Colors.black26 : Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          // [ĐỢT 26] Checkbox "Lưu mạng WiFi này cho lần sau" — gọn (Row tự dựng, không dùng
          // CheckboxListTile mặc định vì padding ngang của nó khá rộng, dễ đẩy form dài thêm).
          // Cả Row bắt onTap để chạm vào phần chữ cũng tích/bỏ tích được, không chỉ riêng ô vuông.
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _saveWifi = !_saveWifi),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _saveWifi,
                      onChanged: (v) => setState(() => _saveWifi = v ?? true),
                      activeColor: tkGreen,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.text('save_wifi_checkbox'),
                      style: TextStyle(color: textSub, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // [ĐỢT 31 — GATEKEEPER] Spinner hiện NGAY TRÊN nút này (thay vì rời sang View riêng)
          // trong lúc _submitWifiCredentials đang thử gửi — nút tự khóa (onPressed: null) để
          // user không bấm chồng lệnh trong lúc vòng lặp 3 lần thử đang chạy.
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _isSending ? null : _submitWifiCredentials,
              child: _isSending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(t.text('wifi_install_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // [ĐỢT 31] View 6 (màn "Đang cài đặt WiFi" riêng) đã XÓA HẲN — luồng gửi WiFi không còn rời
  // View 5 nữa (xem _submitWifiCredentials/_isSending), nên view trung gian này không còn ai
  // gọi tới, giữ lại chỉ là dead code.

  // --- VIEW 7: [ĐỢT 25] ĐĂNG KÝ TRỰC TIẾP BẰNG MAC (Direct MAC Binding) ---
  String _registerErrorText(AppTranslations t) {
    switch (_registerFailStatus) {
      case AddDeviceStatus.ownershipConflict:
        // Câu chữ CHÍNH XÁC theo yêu cầu — không lấy nguyên văn lỗi server (dù server đã trả
        // đúng ý này) để đảm bảo hiển thị ổn định dù Backend đổi câu chữ log nội bộ sau này.
        return t.text('device_owned_by_other_error');
      case AddDeviceStatus.forbidden:
        return _registerFailMessage?.isNotEmpty == true ? _registerFailMessage! : t.text('device_register_forbidden_error');
      case AddDeviceStatus.notOnlineYet:
        return t.text('device_register_timeout_error');
      case AddDeviceStatus.networkError:
        return t.text('device_register_network_error');
      case AddDeviceStatus.otherError:
      default:
        return _registerFailMessage?.isNotEmpty == true ? _registerFailMessage! : t.text('device_register_generic_error');
    }
  }

  Widget _buildDeviceRegisteringView(bool isDark, Color textMain, Color textSub, AppTranslations t) {
    // [ĐỢT 29] "Đang xử lý" gộp cả 2 pha: chờ Internet hồi phục (_isWaitingForInternet) VÀ
    // đang gọi Cloud thật (_isRegisteringDevice) — 2 pha nối tiếp nhau, chỉ khác câu chữ hiển thị.
    final bool inProgress = _isWaitingForInternet || _isRegisteringDevice;
    // [ĐỢT 32 — HARD GATEKEEPER] Trạng thái RIÊNG, không lẫn với lỗi Backend (_registerFailStatus)
    // — đây là "chưa từng gọi Backend" chứ không phải "Backend từ chối", nên cần icon/nút khác hẳn.
    final bool gateActive = _noInternetGate && !inProgress;
    final bool failed = !inProgress && !gateActive && _registerFailStatus != null;
    // Xung đột sở hữu/Không đủ quyền là lỗi VĨNH VIỄN — không có ý nghĩa để "Thử lại" (MAC vẫn
    // sẽ thuộc người khác), chỉ còn đường Hủy. Các lỗi còn lại (mạng, timeout...) mới đáng thử lại.
    final bool permanentError = _registerFailStatus == AddDeviceStatus.ownershipConflict || _registerFailStatus == AddDeviceStatus.forbidden;

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(t.text('device_register_header'), textMain, textSub),
          const SizedBox(height: 32),
          SizedBox(
            height: 90,
            child: Center(
              child: inProgress
                  ? const CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 3)
                  : Icon(
                      gateActive ? Icons.wifi_off_rounded : (failed ? (permanentError ? Icons.block_rounded : Icons.error_rounded) : Icons.check_circle_rounded),
                      color: gateActive ? Colors.orange : (failed ? (permanentError ? Colors.orange : Colors.redAccent) : tkGreen),
                      size: 64,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            // [ĐỢT 29+32] Chờ Internet / đang gọi Cloud / Cửa ải hết giờ vẫn chưa có mạng — 3 câu
            // chữ RIÊNG, user cần biết App đang ở pha nào, tránh tưởng App treo hoặc đơ.
            _isWaitingForInternet
                ? t.text('device_waiting_internet_status')
                : (_isRegisteringDevice
                    ? t.text('device_registering_status')
                    : (gateActive ? t.text('device_no_internet_gate_message') : (failed ? _registerErrorText(t) : ''))),
            style: TextStyle(color: gateActive ? Colors.orange.shade800 : (failed ? (permanentError ? Colors.orange.shade800 : Colors.redAccent) : textMain), fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (_isRegisteringDevice && _registerAttempts > 1) ...[
            const SizedBox(height: 6),
            Text('${t.text('device_registering_attempt_prefix')}$_registerAttempts', style: TextStyle(color: textSub, fontSize: 11)),
          ],
          // [ĐỢT 32] Cửa ải Internet — CHỈ một nút thủ công, không tự động gọi lại Backend.
          if (gateActive) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: tkGreen, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _retryAfterInternetGate,
                child: Text(t.text('complete_registration_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          if (failed) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                if (!permanentError)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _registerDeviceDirect(),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), side: BorderSide(color: textSub.withValues(alpha: 0.4)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text(t.text('wifi_retry_btn'), style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (!permanentError) const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: permanentError ? tkGreen : Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.pop(context),
                    child: Text(t.text('close'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final t = AppTranslations.of(context);

    // [GLASS THEME — BOSS FIGHT] Dialog/ConstrainedBox/GlassCard thủ công cũ ĐÃ BỎ khỏi
    // build() của chính class này — caller (dashboard_screen.dart ×2, device_list_screen.dart)
    // nay đưa thẳng AddDeviceDialog vào showAppDialog(child: ...), showAppDialog tự cấp khung
    // Dialog/kính bên ngoài. Giữ ConstrainedBox để khóa đúng maxWidth 400 như cũ.
    //
    // [CHỐNG LỒNG KÍNH] Vì showAppDialog ĐÃ là 1 lớp kính bao trọn toàn bộ nội dung dưới đây
    // (cả 5 view: menu, quét LAN, camera, nhập tay, AP mode), 6 GlassCard cũ NẰM BÊN TRONG
    // các hàm _build*View KHÔNG được đổi sang AppCard — làm vậy sẽ tạo lớp BackdropFilter
    // THỨ HAI lồng ngay trong lớp kính ngoài cùng, đúng thứ bị cấm tuyệt đối. Đã đổi 6 chỗ đó
    // sang Material+InkWell PHẲNG VĨNH VIỄN (không blur riêng) — xem từng hàm _build*View.
    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _currentView == 0
                  ? _buildSelectionMenu(isDark, textMain, textSub, t)
                  : _currentView == 1
                      ? _buildScannerView(textMain, textSub, t)
                      : _currentView == 2
                          ? _buildManualEntryView(isDark, textMain, textSub, t)
                          : _currentView == 3
                              ? _buildAPModeView(isDark, textMain, textSub, t) // View 3: AP Mode
                              : _currentView == 4
                                  ? _buildLanScanView(isDark, textMain, textSub, t) // View 4: Quét LAN
                                  : _currentView == 5
                                      ? _buildWifiCredentialView(isDark, textMain, textSub, t) // View 5: Nhập WiFi nhà (kể cả lúc đang gửi, xem _isSending)
                                      : _currentView == 6
                                          ? _buildApInstructionView(isDark, textMain, textSub, t) // View 6: [GIAI ĐOẠN 110] Hướng dẫn cấp nguồn, TRƯỚC AP Mode
                                          : _buildDeviceRegisteringView(isDark, textMain, textSub, t), // View 7: Đăng ký trực tiếp MAC
            ),
        ),
    );
  }
}

// ============================================================================
// WIDGET HỖ TRỢ VẼ KHUNG QUÉT QR CODE
// ============================================================================
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black45;
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final double scanAreaSize = size.width * 0.55;
    final double left = (size.width - scanAreaSize) / 2;
    final double top = (size.height - scanAreaSize) / 2;
    final Rect scanRect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);
    
    path.addRect(scanRect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);

    final borderPaint = Paint()..color = const Color(0xFF00A651)..style = PaintingStyle.stroke..strokeWidth = 3.5;
    const double cornerLen = 20.0;
    
    canvas.drawPath(Path()..moveTo(left, top + cornerLen)..lineTo(left, top)..lineTo(left + cornerLen, top), borderPaint);
    canvas.drawPath(Path()..moveTo(scanRect.right - cornerLen, top)..lineTo(scanRect.right, top)..lineTo(scanRect.right, top + cornerLen), borderPaint);
    canvas.drawPath(Path()..moveTo(left, scanRect.bottom - cornerLen)..lineTo(left, scanRect.bottom)..lineTo(left + cornerLen, scanRect.bottom), borderPaint);
    canvas.drawPath(Path()..moveTo(scanRect.right - cornerLen, scanRect.bottom)..lineTo(scanRect.right, scanRect.bottom)..lineTo(scanRect.right, scanRect.bottom - cornerLen), borderPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}