import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui'; 
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/device_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/language_provider.dart';
import '../localization/app_translations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_sync_service.dart';
import 'auth/login_screen.dart';
import 'admin/role_management_view.dart';
import 'admin/admin_system_screen.dart';
import '../services/admin_service.dart';
import 'devices/add_device_dialog.dart';
import 'admin/profile_management_view.dart';
import '../providers/notification_provider.dart';
import 'home/home_management_screen.dart';
// [GLASS THEME] glass_container.dart (GlassContainer, kính LUÔN BẬT) đã được thay hết bằng
// AppContainer trong file này — mọi khối kính nay theo quyền kiểm soát của isGlassThemeEnabled.
import '../widgets/app_ui_wrappers.dart';
import '../widgets/device_menu_helper.dart';
import '../widgets/digital_twin_cards.dart'; // [ĐỢT 23] SmartRollingDoorCard/SmartPumpCard/SmartDimmerCard/GenericDeviceCard
import '../widgets/room_group_dialogs.dart';
import '../widgets/adaptive_navigation.dart';
import '../providers/room_group_provider.dart';
import '../providers/home_provider.dart';
import '../providers/automation_provider.dart';
import 'groups/edit_group_screen.dart';
import 'groups/room_management_screen.dart';
import 'automation/automation_screen.dart';
import 'automation/create_automation_screen.dart';
import 'devices/device_timer_screen.dart';
import 'devices/device_history_screen.dart';
import '../widgets/share_device_dialog.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lottie/lottie.dart';

class SpinningWidget extends StatefulWidget {
  final Widget child; final bool isSpinning; final int speedLevel;
  const SpinningWidget({super.key, required this.child, required this.isSpinning, this.speedLevel = 1});
  @override
  State<SpinningWidget> createState() => _SpinningWidgetState();
}

class _SpinningWidgetState extends State<SpinningWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000)); if (widget.isSpinning) { _updateSpeed(); _controller.repeat(); } }
  @override
  void didUpdateWidget(SpinningWidget oldWidget) { super.didUpdateWidget(oldWidget); if (widget.isSpinning && !oldWidget.isSpinning) { _updateSpeed(); _controller.repeat(); } else if (!widget.isSpinning && oldWidget.isSpinning) { _controller.stop(); } else if (widget.isSpinning && widget.speedLevel != oldWidget.speedLevel) { _updateSpeed(); _controller.repeat(); } }
  void _updateSpeed() { int durationMs = 1000; if (widget.speedLevel == 2) durationMs = 600; if (widget.speedLevel == 3) durationMs = 300; _controller.duration = Duration(milliseconds: durationMs); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return RotationTransition(turns: _controller, child: widget.child); }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final String baseUrl = "https://api.iot-smart.vn/api";
  String targetMac = '', userEmail = 'Đang tải...', userRole = 'USER', currentHomeId = '';

  /// [ADMIN] Nhận diện quyền cao nhất chống mọi sai lệch chuỗi từ Backend:
  /// bỏ khoảng trắng thừa + so sánh không phân biệt hoa/thường. Chấp nhận cả
  /// 'SUPER_USER' lẫn 'admin' để menu Quản trị luôn hiện đúng.
  bool get _isSuperUser {
    final r = userRole.trim().toUpperCase();
    return r == 'SUPER_USER' || r == 'ADMIN';
  }
  int _selectedIndex = 0, _cameraViewMode = 1; 
  bool _isLoadingDevices = true; 
  bool _isPushEnabled = true;
  Map<String, dynamic> _weatherData = {'temp': '--', 'condition': 'Đang tải...', 'main': ''};
  // [ĐỊA DANH GPS] Tên khu vực hiện tại, dịch ngược từ tọa độ GPS (geocoding) — hiển thị thay
  // cho nút làm mới vị trí thủ công ở đợt trước. Giữ nguyên placeholder tiếng Việt cứng khi
  // khởi tạo (giống quy ước _weatherData ở trên) — giá trị này bị ghi đè gần như ngay lập tức
  // bởi _fetchWeather() gọi từ initState(), không đáng dịch phần khởi tạo thoáng qua.
  String _locationName = 'Đang định vị...';
  Timer? _debounceSync;

  /// [SINGLE-FLIGHT UI] Lượt _initializeHome ĐANG chạy (nếu có). Mutex ở tầng service chỉ
  /// gộp được HTTP request; khóa này gộp cả PIPELINE hydrate/ingest (parse JWT + setState +
  /// đổ provider + fetchScenes/fetchHistory) — nhiều nơi gọi trùng lúc chỉ chạy đúng 1 lượt.
  Future<void>? _initInFlight;

  /// [CHỐNG RE-FETCH VÔ HẠN] MAC lạ đã được cấp 1 lượt re-fetch trong phiên này. Topic của
  /// thiết bị con Hub/echo lệnh không bao giờ vào danh sách nhà -> nếu không ghi sổ, MỖI gói
  /// tin định kỳ của nó lại kích _initializeHome thêm lần nữa (nguồn gốc chuỗi 4 lần gọi).
  final Set<String> _resyncRequestedMacs = {};

  /// Giữ tham chiếu provider để dispose() gỡ hook an toàn (không dùng context sau unmount).
  DeviceProvider? _deviceProviderRef;

  /// [CHUYỂN NHÀ] Tham chiếu HomeProvider để lắng nghe activeHomeId đổi (HomeCard gọi
  /// setActiveHome khi user bấm "Vào điều khiển") — xem _onActiveHomeChanged().
  HomeProvider? _homeProviderRef;
  String? _lastKnownActiveHomeId;

  /// Segment topic dạng MAC (12 hex) — compile 1 lần vì listener MQTT là hot path.
  static final RegExp _macSegmentRegex = RegExp(r'^[0-9A-Fa-f]{12}$');
  bool _isSelectionMode = false;
  final Set<String> _selectedDevices = {}; 
  final Set<String> _hiddenDevices = {}; // Chứa ID (MAC_Endpoint) của các công tắc bị ẩn
  bool _showHiddenFilter = false; // Bật cờ này lên để xem các thiết bị đang bị ẩn
  List<dynamic> _currentHomeDevices = [], _allHomesForSuperUser = [];

  /// [LAN SCAN] Tập MAC đã sở hữu trong nhà đang mở (đã chuẩn hóa HOA + bỏ ":") —
  /// truyền vào AddDeviceDialog để ẩn nút "Thêm ngay" với thiết bị đã có.
  Set<String> get _ownedMacs => _currentHomeDevices
      .map((d) => (d['mac_address'] ?? d['mac'] ?? '').toString().replaceAll(':', '').toUpperCase())
      .where((m) => m.isNotEmpty)
      .toSet();
  Map<String, dynamic>? _selectedHomeForSuperUser;
  final Color tkGreen = const Color(0xFF00A651);

  // [EXCLUDE LIST] Các category là MỘT khối thiết bị được điều khiển TRỌN GÓI trong
  // một thẻ chuyên biệt (quạt, điều hòa, rèm, bơm, tủ lạnh, cảm biến). Gặp thiết bị
  // thuộc nhóm này, lưới CHỈ vẽ thẻ chính và TUYỆT ĐỐI không nứt các endpoint con
  // (relay tốc độ, nút tổng...) ra thành thẻ công tắc ảo rời rạc.
  // CỐ Ý KHÔNG có 'hub': Hub V38 là bộ CHỨA nhiều thiết bị con -> các thẻ con D1..Dn
  // của nó vẫn phải hiện đầy đủ trên lưới (khác hẳn quạt/điều hòa là 1 khối đơn).
  static const List<String> primaryDeviceCategories = ['fan', 'sensor', 'ac', 'curtain', 'pump', 'fridge', 'light'];

  @override
  void initState() {
    super.initState();
    _loadHiddenDevices();
    _fetchWeather();
    // [INITIAL STATE SYNC — THỨ TỰ CHUẨN KHI MỞ APP]
    //   Bước 1: REST GET /api/homes/{id}/devices -> hydrateFromRest() nạp trạng thái
    //           TĨNH thật (ON/OFF + online) vào kho DPS -> nút sáng đúng NGAY LẬP TỨC.
    //   Bước 2: chỉ SAU đó mới mở kênh MQTT smarthub/{home_id}/# hứng biến động realtime,
    //           và kênh chuông notifications/{email} (lúc này email thật đã giải mã từ token,
    //           không còn subscribe nhầm vào placeholder "Đang tải...").
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapSync());
  }

  Future<void> _bootstrapSync() async {
    // [AUTO-REFRESH HOOK] Cho phép nơi khác (vd chạy Scene) ép App kéo lại trạng thái
    // thật từ REST mà không cần giữ context của Dashboard.
    _deviceProviderRef = Provider.of<DeviceProvider>(context, listen: false);
    _deviceProviderRef!.onRefreshRequested = () => _initializeHome(isSilent: true);

    await _initializeHome(); // REST: danh sách + trạng thái thật -> UI tĩnh lên hình trước
    if (!mounted) return;

    // [CHUYỂN NHÀ] Gắn listener SAU KHI lượt khởi tạo đầu đã xong (restoreActiveHome() bên
    // trong _doInitializeHome đã chạy) — tránh notifyListeners() của chính lượt restore đầu
    // tiên kích _onActiveHomeChanged() chạy lại _initializeHome() một cách thừa thãi.
    _homeProviderRef = Provider.of<HomeProvider>(context, listen: false);
    _lastKnownActiveHomeId = _homeProviderRef!.activeHomeId;
    _homeProviderRef!.addListener(_onActiveHomeChanged);

    Provider.of<NotificationProvider>(context, listen: false).initMQTTListener(userEmail);
    _setupRealtimeSync();    // MQTT realtime chỉ kết nối sau khi ảnh tĩnh đã hiển thị đúng
  }

  /// [CHUYỂN NHÀ] HomeProvider.activeHomeId đổi (HomeCard gọi setActiveHome() khi user bấm
  /// "Vào điều khiển" ở màn Quản lý Nhà) -> nhảy về tab Bảng điều khiển NGAY LẬP TỨC + refetch
  /// thiết bị của nhà mới. HomeCard KHÔNG tự điều hướng — chỉ đổi data, Dashboard tự phản ứng.
  void _onActiveHomeChanged() {
    final newId = _homeProviderRef?.activeHomeId;
    if (newId == null || newId == _lastKnownActiveHomeId || !mounted) return;
    _lastKnownActiveHomeId = newId;
    setState(() => _selectedIndex = 0);
    _initializeHome();
  }

  /// Nạp lại danh sách nút bị ẩn từ Local Storage — trạng thái "Ẩn khỏi Bảng điều khiển"
  /// sống bền qua các lần đóng/mở App, không còn mất khi khởi động lại
  Future<void> _loadHiddenDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('hidden_devices') ?? [];
    if (mounted && saved.isNotEmpty) setState(() => _hiddenDevices.addAll(saved));
  }

  /// Ghi danh sách ẩn xuống Local Storage ngay khi có thay đổi
  void _persistHiddenDevices() {
    SharedPreferences.getInstance().then((p) => p.setStringList('hidden_devices', _hiddenDevices.toList()));
  }

  @override
  void dispose() {
    _debounceSync?.cancel();
    // Gỡ hook trỏ vào State đã chết — chống Scene/MQTT về trễ gọi setState sau unmount
    // (vd đăng xuất: Dashboard bị thay bằng Login nhưng provider sống toàn app).
    _deviceProviderRef?.onRefreshRequested = null;
    _deviceProviderRef?.clearGlobalMqttListener();
    _homeProviderRef?.removeListener(_onActiveHomeChanged);
    super.dispose();
  }

  Future<void> _handleRefresh() async { await _initializeHome(isSilent: false); await Future.delayed(const Duration(milliseconds: 500)); }

  /// Cổng CHỐNG GỌI TRÙNG của toàn luồng khởi tạo: đang có lượt chạy thì mọi lời gọi mới
  /// (MQTT thiết bị lạ, hook Scene, pull-to-refresh...) CÙNG CHỜ lượt đó, không mở pipeline
  /// hydrate/ingest thứ hai — API khởi tạo chỉ "nổ" đúng 1 lần cho mỗi đợt.
  Future<void> _initializeHome({bool isSilent = false}) {
    final inFlight = _initInFlight;
    if (inFlight != null) {
      debugPrint('INIT_DEDUP: _initializeHome đang chạy -> tái dùng lượt hiện tại');
      return inFlight;
    }
    final run = _doInitializeHome(isSilent: isSilent);
    _initInFlight = run;
    run.whenComplete(() => _initInFlight = null);
    return run;
  }

  Future<void> _doInitializeHome({bool isSilent = false}) async {
    if (!mounted) return;
    if (!isSilent) setState(() => _isLoadingDevices = true);
    final token = await AuthService().getToken();
    if (token != null) {
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payloadStr = base64Url.normalize(parts[1]);
          final decoded = utf8.decode(base64Url.decode(payloadStr));
          final Map<String, dynamic> payload = jsonDecode(decoded);
          String role = payload['role'] ?? 'USER', homeId = payload['home_id'] ?? '', email = payload['email'] ?? 'Chưa xác định';
          // [DEBUG ROLE] In NGUYÊN VĂN payload JWT + role đã parse ra console. Nếu ở đây KHÔNG phải
          // 'SUPER_USER' nghĩa là token đang cache còn cũ (chưa đăng nhập lại) HOẶC Backend trả role
          // khác — đây là "nguồn sự thật" để đối chiếu, không phải lỗi UI.
          if (kDebugMode) {
            print('🔑 [ROLE DEBUG] JWT payload = $payload');
            print('🔑 [ROLE DEBUG] role parsed = "$role"  (email: $email)');
          }
          if (!mounted) return;

          // [CHUYỂN NHÀ] Với user thường (SUPER_USER tự quản qua _selectedHomeForSuperUser,
          // nhánh riêng bên dưới), "nhà đang xem" KHÔNG còn fix cứng theo home_id trong JWT
          // (giá trị đó chỉ đúng tại thời điểm đăng nhập) — ưu tiên HomeProvider.activeHomeId,
          // do HomeCard cập nhật khi user bấm "Vào điều khiển". Lần đầu (activeHomeId null)
          // khôi phục từ SharedPreferences, rơi về home_id JWT nếu chưa từng chọn nhà nào.
          final homeProvider = Provider.of<HomeProvider>(context, listen: false);
          if (homeProvider.activeHomeId == null) {
            await homeProvider.restoreActiveHome(fallback: homeId);
            if (!mounted) return;
          }
          final effectiveHomeId = (role != 'SUPER_USER' && (homeProvider.activeHomeId?.isNotEmpty ?? false))
              ? homeProvider.activeHomeId!
              : homeId;

          setState(() { currentHomeId = effectiveHomeId; userEmail = email; userRole = role; });

          // [SINGLE FETCH — CHỐNG N+1] MỘT lần gọi duy nhất gộp Homes + Rooms + Devices,
          // thay cho chuỗi "GET /homes rồi loop GET /homes/:id/devices từng nhà" (nghẽn 4G).
          final sync = await DashboardSyncService().fetch();
          if (!mounted) return;
          if (sync.error != null) {
            // Mạng chậm/timeout -> báo nhẹ, KHÔNG sập màn hình
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sync.error!), backgroundColor: Colors.orange));
          } else {
            // Index nhà theo home_id để phân phối nhanh xuống các provider
            final Map<String, Map<String, dynamic>> homeById = {
              for (final h in sync.homes)
                if (h is Map) (h['home_id'] ?? '').toString(): Map<String, dynamic>.from(h),
            };

            if (role == 'SUPER_USER') {
              final homes = sync.homes.whereType<Map>().map((h) => Map<String, dynamic>.from(h)).toList();
              for (final h in homes) { _annotateHomeCounts(h); } // đếm on/off từ devices lồng sẵn
              if (mounted) setState(() => _allHomesForSuperUser = homes);
              if (_selectedHomeForSuperUser != null) {
                final hid = _selectedHomeForSuperUser!['home_id'].toString();
                final h = homeById[hid];
                if (h != null) {
                  await _fetchDevicesForHome(hid, token,
                      preloadedDevices: (h['devices'] as List?) ?? const [],
                      preloadedRooms: (h['rooms'] as List?) ?? const []);
                }
              }
            } else {
              final h = homeById[effectiveHomeId];
              if (effectiveHomeId.isNotEmpty && h != null) {
                await _fetchDevicesForHome(effectiveHomeId, token,
                    preloadedDevices: (h['devices'] as List?) ?? const [],
                    preloadedRooms: (h['rooms'] as List?) ?? const []);
              }
            }
          }
          if (mounted) { Provider.of<NotificationProvider>(context, listen: false).fetchHistory(); }
        }
      } catch (e, st) {
        // [FIX NUỐT LỖI] Trước đây MỌI lỗi (kể cả parse response sync) bị gán nhãn sai
        // "Lỗi giải mã token" rồi nuốt -> thiết bị không lên mà không rõ vì sao. Nay log
        // rõ loại lỗi + stack trace để lộ đúng dòng hỏng (thường là parse/mapping JSON).
        debugPrint('DASHBOARD_INIT_ERROR: ${e.runtimeType}: $e');
        debugPrint('DASHBOARD_INIT_STACK: $st');
      }
    }
    if (mounted && !isSilent) setState(() => _isLoadingDevices = false);
  }

  // [SINGLE FETCH] Đếm số nút bật/tắt của một NHÀ từ mảng devices lồng sẵn (dùng cho thẻ
  // nhà của SUPER_USER) — thay cho việc gọi API thiết bị riêng từng nhà. Ghi kết quả vào
  // chính map home: on_count/off_count/total_endpoints/raw_devices.
  void _annotateHomeCounts(Map<String, dynamic> home) {
    final List devs = (home['devices'] as List?) ?? const [];
    int onCount = 0, offCount = 0, totalEndpoints = 0;
    for (var d in devs) {
      final String dType = '${d['fw_type'] ?? ''} ${d['category'] ?? ''} ${d['type'] ?? ''}'.toUpperCase();
      if (dType.contains('HUB') || dType.contains('SENSOR')) continue; // Hub/Cảm biến không tính bật/tắt
      var rawState = d['state'] ?? d['state_data'] ?? d['properties'] ?? {};
      Map<String, dynamic> stateMap = rawState is String ? (jsonDecode(rawState) ?? {}) : Map<String, dynamic>.from(rawState ?? {});
      bool hasEp = false;
      void countRecursive(String key, dynamic val) {
        final kLow = key.toLowerCase();
        const ignored = ['ip', 'mac', 'rssi', 'signal', 'wifi', 'serial', 'version', 'fw', 'firmware', 'update', 'reset', 'restart', 'online', 'timestamp', 'time', 'led', 'config', 'status', 'ping'];
        for (var ig in ignored) { if (kLow == ig || kLow.contains(ig)) return; }
        if (val is Map) {
          if (val.containsKey('state') || val.containsKey('value')) {
            String s = (val['state'] ?? val['value']).toString().toUpperCase();
            if (s == 'ON' || s == 'TRUE' || s == '1') { hasEp = true; totalEndpoints++; onCount++; }
            else if (s == 'OFF' || s == 'FALSE' || s == '0') { hasEp = true; totalEndpoints++; offCount++; }
          } else {
            val.forEach((k, v) => countRecursive(k, v));
          }
          return;
        }
        String s = val.toString().toUpperCase();
        if (s == 'ON' || s == 'TRUE' || s == '1') { hasEp = true; totalEndpoints++; onCount++; }
        else if (s == 'OFF' || s == 'FALSE' || s == '0') { hasEp = true; totalEndpoints++; offCount++; }
      }
      if (stateMap.isNotEmpty) stateMap.forEach((k, v) => countRecursive(k, v));
      if (!hasEp) { totalEndpoints++; offCount++; }
    }
    home['on_count'] = onCount; home['off_count'] = offCount; home['total_endpoints'] = totalEndpoints; home['raw_devices'] = devs;
  }

  /// Nạp thiết bị + phòng + ngữ cảnh của MỘT nhà. [preloadedDevices]/[preloadedRooms] != null
  /// (từ single-fetch dashboard/sync) -> dùng thẳng, KHÔNG gọi HTTP (chống N+1); null -> fallback
  /// gọi API riêng như cũ (dùng cho các lần refresh lẻ ngoài luồng khởi tạo).
  Future<void> _fetchDevicesForHome(String homeId, String token, {List<dynamic>? preloadedDevices, List<dynamic>? preloadedRooms}) async {
    try {
      List<dynamic> devices;
      if (preloadedDevices != null) {
        devices = preloadedDevices;
      } else {
        final response = await http.get(Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}/devices'), headers: {'Authorization': 'Bearer $token'});
        if (!mounted) return;
        if (response.statusCode != 200) return;
        devices = jsonDecode(response.body);
      }
      if (!mounted) return; // màn hình đã đóng trong lúc chờ mạng -> bỏ, không đụng context

      // [PHÒNG] Rooms: có preloaded (sync) thì nạp thẳng khỏi gọi API; không thì fetch riêng.
      // [NGỮ CẢNH] Scenes KHÔNG nằm trong sync -> luôn fetch riêng (fire-and-forget).
      // [NHÓM] Groups persist bên Redis (/api/groups) — luôn fetch riêng: đây là mắt xích
      // làm nhóm công tắc ảo SỐNG LẠI sau restart/đăng nhập máy khác (trước đây mock RAM).
      final roomGroupProv = Provider.of<RoomGroupProvider>(context, listen: false);
      if (preloadedRooms != null) {
        roomGroupProv.ingestRooms(homeId, preloadedRooms);
      } else {
        roomGroupProv.fetchRooms(homeId);
      }
      roomGroupProv.fetchGroups(homeId);
      Provider.of<AutomationProvider>(context, listen: false).fetchScenes(homeId);

      {
        final dpsProvider = Provider.of<DeviceProvider>(context, listen: false);

        for (var device in devices) {
           var rawState = device['state'] ?? device['state_data'] ?? device['properties'];
           Map<String, dynamic> stateMap = {};

           if (rawState is String) {
             String s = rawState.trim();
             if (s.startsWith('{')) { try { stateMap = Map<String, dynamic>.from(jsonDecode(s)); } catch(_) {} }
             else { stateMap = {'state': s}; }
           } else if (rawState is Map) {
             stateMap = Map<String, dynamic>.from(rawState);
           }

           // [INITIAL STATE SYNC] Bơm ngay ảnh trạng thái thật (Backend vừa đọc từ Redis)
           // + cờ Trực tuyến vào kho DPS — nút công tắc/quạt sáng đúng thực tế ngay từ
           // khung hình đầu tiên, kể cả khi thiết bị được bật từ Hass/máy khác lúc App đóng
           final String devMac = (device['mac_address'] ?? device['mac'] ?? '').toString();
           if (devMac.isNotEmpty) {
             dpsProvider.hydrateFromRest(
               devMac,
               stateMap,
               online: (device['status']?.toString().toLowerCase() ?? '') == 'online',
             );
           }

           // [FIX ĐẾM SAI] Bỏ Hub & Cảm biến khỏi phép đếm bật/tắt (vẫn hydrate state ở trên).
           final String dType = '${device['fw_type'] ?? ''} ${device['category'] ?? ''} ${device['type'] ?? ''}'.toUpperCase();
           if (dType.contains('HUB') || dType.contains('SENSOR')) {
             device['on_count'] = 0; device['off_count'] = 0; device['total_endpoints'] = 0;
             continue;
           }

           // THUẬT TOÁN ÉP PHẲNG JSON ĐỂ ĐẾM SỐ NÚT KHÔNG BAO GIỜ SÓT
           Map<String, dynamic> flatMap = {};
           void flatten(Map m) {
             m.forEach((k, v) { if (v is Map) {
               flatten(v);
             } else {
               flatMap[k] = v;
             } });
           }
           flatten(stateMap);

           int onCount = 0, offCount = 0, totalEndpoints = 0;
           bool hasEp = false;
           final ignored = ['ip', 'mac', 'rssi', 'signal', 'wifi', 'serial', 'version', 'fw', 'firmware', 'update', 'reset', 'restart', 'online', 'timestamp', 'time', 'led', 'config', 'status', 'ping', 'type', 'id'];

           flatMap.forEach((k, v) {
              if (ignored.contains(k.toLowerCase())) return;
              String s = v.toString().toUpperCase();
              if (['ON', 'OFF', 'TRUE', 'FALSE', '1', '0'].contains(s)) {
                 hasEp = true; totalEndpoints++;
                 if (['ON', 'TRUE', '1'].contains(s)) {
                   onCount++;
                 } else {
                   offCount++;
                 }
              }
           });
           
           if (!hasEp) {
             String dNameLow = (device['name'] ?? '').toString().toLowerCase();
             if (dNameLow.contains('quạt') || dNameLow.contains('fan')) { totalEndpoints += 5; offCount += 5; hasEp = true; }
             else if (dNameLow.contains('4b') || dNameLow.contains('4 nút') || dNameLow.contains('4ch')) { totalEndpoints += 4; offCount += 4; hasEp = true; }
           }

           if (!hasEp) { totalEndpoints++; offCount++; }
           
           device['on_count'] = onCount; device['off_count'] = offCount; device['total_endpoints'] = totalEndpoints;
        }

        if (mounted) {
          setState(() {
            _currentHomeDevices = devices;
            if (_selectedHomeForSuperUser != null && _selectedHomeForSuperUser!['home_id'] == homeId) {
               int totalOn = 0, totalDev = 0;
               for(var d in devices) { totalOn += (d['on_count'] as int? ?? 0); totalDev += (d['total_endpoints'] as int? ?? 0); }
               _selectedHomeForSuperUser!['on_count'] = totalOn; _selectedHomeForSuperUser!['total_endpoints'] = totalDev;
            }
          });
          if (devices.isNotEmpty) { 
             setState(() => targetMac = devices[0]['mac_address'] ?? devices[0]['mac'] ?? ''); 
          } else { setState(() => targetMac = ''); }
        }
      }
    } catch (e) { if (kDebugMode) print("Lỗi fetch thiết bị: $e"); }
  }

  // ==========================================================================
  // ➕ LIÊN KẾT THIẾT BỊ VỪA QUÉT/NHẬP VÀO NHÀ (POST /api/homes/:id/devices)
  // ==========================================================================
  /// AddDeviceDialog chỉ trả về mã MAC (String) — hàm này mới là nơi GỌI API THẬT.
  /// [FIX] Trước đây dashboard bỏ quên kết quả dialog: quét QR xong không link gì cả.
  /// Bắt buộc có phản hồi rõ ràng cho người dùng:
  ///   - Thành công  -> SnackBar xanh + làm mới danh sách
  ///   - Server chê  -> SnackBar đỏ kèm ĐÚNG thông báo lỗi server trả về
  ///                    (vd: "Thiết bị (Mã MAC: XXX) hiện không trực tuyến!")
  ///   - Rớt mạng    -> SnackBar đỏ báo lỗi kết nối
  Future<void> _linkScannedDevice(dynamic dialogResult) async {
    // Dialog đóng không quét gì (null) hoặc luồng AP Mode trả bool -> không link
    if (dialogResult is! String || dialogResult.trim().isEmpty) return;
    final String mac = dialogResult.trim().toUpperCase();

    // Nhà đích: user thường = nhà trong token; SUPER_USER = nhà đang mở trên màn hình
    final String homeId = (userRole == 'SUPER_USER' && _selectedHomeForSuperUser != null)
        ? _selectedHomeForSuperUser!['home_id'].toString()
        : currentHomeId;
    if (homeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Chưa xác định được ngôi nhà — hãy mở một nhà cụ thể rồi thêm thiết bị.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    try {
      if (kDebugMode) print('🤝 [LINK] Gửi yêu cầu link $mac vào nhà $homeId...');
      final token = await AuthService().getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}/devices'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'mac_address': mac}),
      );
      if (kDebugMode) print('🤝 [LINK] $mac -> HTTP ${response.statusCode}: ${response.body}');
      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Đã thêm thiết bị $mac vào nhà thành công!'),
          backgroundColor: const Color(0xFF00A651),
        ));
        _handleRefresh(); // kéo danh sách mới -> thẻ thiết bị hiện ra ngay
      } else {
        // Moi đúng câu chữ lỗi server gửi về (MAC sai, thiết bị chưa kết nối mạng...)
        String errMsg = 'Lỗi máy chủ (HTTP ${response.statusCode})';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && (body['error'] ?? '').toString().isNotEmpty) errMsg = body['error'].toString();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ $errMsg'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ Không thể kết nối máy chủ — kiểm tra mạng rồi thử lại.'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  // --- HÀM XÓA THIẾT BỊ (đi qua DeviceProvider để đồng bộ luôn kho RAM/DPS) ---
  Future<void> _deleteDevice(String mac) async {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final bool ok = await provider.deleteDevice(mac);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa thiết bị thành công!'), backgroundColor: Color(0xFF00A651)),
      );
      // Provider đã gỡ thiết bị khỏi RAM; gọi làm mới để cập nhật cả danh sách
      // thiết bị/nhà lấy từ REST (_currentHomeDevices) cho thẻ biến mất hẳn
      _handleRefresh();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa thiết bị — kiểm tra kết nối hoặc quyền tài khoản!'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _setupRealtimeSync() {
    final provider = Provider.of<DeviceProvider>(context, listen: false);

    // Kích hoạt (lại) kết nối MQTT bằng credentials động của user vừa đăng nhập
    provider.connectMqtt();

    provider.setGlobalMqttListener((topic, message) {
      if (!mounted) return;

      // [TỐI ƯU TỐC ĐỘ QUẠT/CÔNG TẮC] DeviceProvider đã cập nhật kho DPS + notifyListeners()
      // NGAY khi gói state về -> thẻ (SmartFanCard/SmartSwitchCard) tự vẽ lại tức thì (<300ms),
      // hoàn toàn hướng sự kiện qua stream MQTT. KHÔNG re-fetch REST cho mỗi gói state nữa.
      // CHỈ nạp lại danh sách REST khi xuất hiện thiết bị LẠ chưa có trong lưới (vừa Add/Link).
      //
      // [FIX GỌI 4 LẦN] Ngay sau subscribe smarthub/{home_id}/#, broker dội cả loạt retained
      // message (bridge status, telemetry, endpoint Hub, echo lệnh). Trước đây MỌI topic không
      // chứa MAC đã biết đều bị coi là "thiết bị mới" -> mỗi cửa sổ debounce 500ms lại nổ thêm
      // một _initializeHome, và topic không bao giờ trở thành "đã biết" thì kích lại VÔ HẠN
      // theo từng gói tin định kỳ. Nay lọc 3 lớp:
      //   (1) Topic KHÔNG có segment dạng MAC (12 hex) -> không bao giờ là thiết bị mới, bỏ.
      //   (2) Có bất kỳ MAC nào đã nằm trong lưới -> realtime đã xử lý qua DPS, bỏ.
      //   (3) MAC lạ chỉ được cấp ĐÚNG 1 lượt re-fetch mỗi phiên: re-fetch xong mà vẫn lạ
      //       (thiết bị con Hub/nhà khác) thì im lặng vĩnh viễn, không kéo REST nữa.
      final List<String> macsInTopic = [
        for (final part in topic.split('/'))
          if (part.length == 12 && _macSegmentRegex.hasMatch(part)) part.toUpperCase(),
      ];
      if (macsInTopic.isEmpty) return; // (1) bridge/status/echo — không phải thiết bị

      final Set<String> owned = _ownedMacs;
      if (macsInTopic.any(owned.contains)) return; // (2) đã có trong lưới

      final newMacs = macsInTopic.where((m) => !_resyncRequestedMacs.contains(m)).toList();
      if (newMacs.isEmpty) return; // (3) đã re-fetch cho MAC này rồi mà vẫn lạ -> bỏ qua
      _resyncRequestedMacs.addAll(newMacs);

      // Debounce 2s: gom trọn cơn bão retained lúc vừa subscribe thành MỘT lần nạp duy nhất
      _debounceSync?.cancel();
      _debounceSync = Timer(const Duration(seconds: 2), () {
        if (mounted) _initializeHome(isSilent: true); // chỉ để nạp thiết bị mới vào danh sách
      });
    });
  }

  /// [GPS THỜI TIẾT] Xin vị trí hiện tại qua Geolocator — xử lý TRỌN VẸN luồng chuẩn: dịch vụ
  /// định vị tắt -> quyền chưa hỏi/bị từ chối -> quyền bị từ chối vĩnh viễn -> lấy tọa độ. Bọc
  /// try-catch NGOÀI CÙNG: bất kỳ lỗi nào (máy không có GPS, plugin lỗi, timeout phần cứng...)
  /// đều rơi về null an toàn — _fetchWeather() hiểu null là "dùng thành phố mặc định phía
  /// Server" (hành vi y hệt trước khi có tính năng này), KHÔNG làm app crash hay treo màn hình.
  Future<Position?> _determinePosition() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (kDebugMode) print('📍 Dịch vụ định vị (GPS) đang tắt trên máy — dùng thời tiết theo thành phố mặc định');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (kDebugMode) print('📍 Người dùng từ chối quyền vị trí');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        // Bị từ chối vĩnh viễn (đặc biệt trên iOS) — không thể tự xin lại, phải vào Cài đặt hệ
        // thống thủ công. Không ném lỗi, chỉ rơi về null.
        if (kDebugMode) print('📍 Quyền vị trí bị từ chối vĩnh viễn — cần bật tay trong Cài đặt hệ thống');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 8)),
      );

      // [ĐỊA DANH GPS — DỊCH NGƯỢC TỌA ĐỘ] TÁCH RIÊNG try-catch: lỗi ở bước này (không mạng,
      // dịch vụ geocoding hệ điều hành lỗi/chưa cài đặt gói ngôn ngữ...) KHÔNG được làm mất
      // luôn tọa độ GPS đã lấy được — position vẫn trả về bình thường cho weather API dùng,
      // _locationName chỉ đơn giản không đổi (giữ 'Đang định vị...' hoặc tên cũ), nơi gọi
      // (_fetchWeather) tự rơi về tên thành phố Backend trả — không hề crash hay treo màn hình.
      try {
        final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final Placemark place = placemarks.first;
          // Ưu tiên Quận/Huyện (subAdministrativeArea); rỗng thì rơi về Phường/Xã (locality).
          final String district = (place.subAdministrativeArea?.trim().isNotEmpty ?? false)
              ? place.subAdministrativeArea!.trim()
              : (place.locality?.trim() ?? '');
          final String province = place.administrativeArea?.trim() ?? '';
          // Dọn dẹp: bỏ phần rỗng thay vì để lại ", " thừa khi 1 trong 2 trường null/rỗng.
          final String combined = [district, province].where((s) => s.isNotEmpty).join(', ');
          if (mounted && combined.isNotEmpty) {
            setState(() => _locationName = combined);
          }
        }
      } catch (e) {
        if (kDebugMode) print('📍 Lỗi dịch ngược tọa độ (geocoding): $e');
        // Không setState lỗi ở đây — _fetchWeather() tự fallback theo tên thành phố API Thời
        // tiết trả về nếu geocoding thất bại hoàn toàn.
      }

      return position;
    } catch (e) {
      if (kDebugMode) print('📍 Lỗi lấy vị trí GPS: $e');
      return null;
    }
  }

  Future<void> _fetchWeather() async {
    final position = await _determinePosition();

    try {
      final token = await AuthService().getToken();
      // Có tọa độ GPS thật -> gắn vào query, Backend gọi OpenWeatherMap ĐÚNG vị trí này (xem
      // WeatherHandler ở weather.go); không có (tắt GPS/từ chối quyền/lỗi) -> Backend tự rơi
      // về thành phố mặc định như trước khi có tính năng này (WEATHER_CITY, không hề gãy luồng).
      final uri = position != null
          ? Uri.parse('$baseUrl/weather/current?lat=${position.latitude}&lon=${position.longitude}')
          : Uri.parse('$baseUrl/weather/current');
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10)); // tránh treo "Đang tải..." vô hạn nếu mạng kẹt (vd. IPv6 lỗi)

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);

        // Trỏ đúng vào lớp "data" bên trong JSON trả về
        final weatherInfo = jsonResponse['data'] ?? {};

        if (mounted) {
          setState(() {
            _weatherData = {
              'temp': weatherInfo['temp']?.toString() ?? '--',
              'condition': weatherInfo['description']?.toString() ?? 'Đang tải...',
              'humidity': weatherInfo['humidity']?.toString() ?? '66', // Lấy luôn độ ẩm
              // [GPS THỜI TIẾT] Nhóm chuẩn hóa (Clear/Clouds/Rain...) từ Backend — dùng để chọn
              // icon Lottie động qua getWeatherIcon(), KHÔNG dùng 'condition' (câu tiếng Việt tự do).
              'main': weatherInfo['main']?.toString() ?? '',
            };
            // [ĐỊA DANH GPS — FALLBACK] _locationName vẫn còn placeholder nghĩa là geocoding
            // thất bại/không có GPS — dùng tên thành phố Backend trả (WEATHER_CITY hoặc theo
            // tọa độ, xem WeatherData.City ở weather.go) thay vì để mãi "Đang định vị...".
            if (_locationName == 'Đang định vị...' || _locationName.trim().isEmpty) {
              final String city = (weatherInfo['city'] ?? '').toString().trim();
              if (city.isNotEmpty) _locationName = city;
            }
          });
        }
      } else {
        // 401 (token hết hạn), 404, 5xx... trước đây bị nuốt lặng lẽ → UI kẹt "Đang tải..."
        if (kDebugMode) print("☁️ API thời tiết trả về ${response.statusCode}: ${response.body}");
        if (mounted) {
          setState(() => _weatherData = {'temp': '--', 'condition': 'Không có dữ liệu', 'humidity': '--', 'main': ''});
        }
      }
    } on TimeoutException {
      if (kDebugMode) print("☁️ API thời tiết timeout sau 10s (kiểm tra mạng/IPv6)");
      if (mounted) {
        setState(() => _weatherData = {'temp': '--', 'condition': 'Không có dữ liệu', 'humidity': '--', 'main': ''});
      }
    } catch (e) {
      if (kDebugMode) print("☁️ Lỗi API thời tiết: $e");
      if (mounted) {
        setState(() => _weatherData = {'temp': '--', 'condition': 'Không có dữ liệu', 'humidity': '--', 'main': ''});
      }
    }
  }

  Future<void> _bulkToggleHome(Map<String, dynamic> home, bool turnOn) async {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    List<dynamic> rawDevices = home['raw_devices'] ?? [];
    int totalEndps = home['total_endpoints'] ?? 0;
    
    // Cập nhật UI ngay lập tức để tạo cảm giác mượt
    setState(() { 
      if (turnOn) { home['on_count'] = totalEndps; home['off_count'] = 0; } 
      else { home['on_count'] = 0; home['off_count'] = totalEndps; } 
    });
    
    for (var device in rawDevices) {
      String mac = device['mac_address'] ?? device['mac'] ?? ''; 
      var rawState = device['state'] ?? device['state_data'] ?? {}; 
      Map<String, dynamic> stateMap = rawState is String ? (jsonDecode(rawState) ?? {}) : Map<String, dynamic>.from(rawState ?? {});
      
      bool hasEndpoints = false;
      stateMap.forEach((k, v) {
        String kl = k.toLowerCase();
        
        // GIẢI QUYẾT LỖI NGƯỢC LỆNH: 
        // Thêm dấu (!) vào !turnOn để đánh lừa "Hàm lật". 
        // VD: Muốn bật (turnOn=true), ta truyền false (!turnOn), hàm lật sẽ lật thành true (ON).
        if (kl.contains('fan') || kl.contains('speed')) { 
          hasEndpoints = true; 
          provider.toggleDevice(mac, 'fan', !turnOn); 
        }
        else if (v.toString().toUpperCase() == 'ON' || v.toString().toUpperCase() == 'OFF' || v.toString() == '1' || v.toString() == '0') {
          hasEndpoints = true; 
          provider.toggleDevice(mac, k, !turnOn);
        }
      });
      
      // Nếu thiết bị không có trạng thái cũ, mặc định bắn vào endpoint S_1
      if (!hasEndpoints) { 
        provider.toggleDevice(mac, 'S_1', !turnOn); 
      }
    }
  }

  void _performLogout(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A), textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    bool confirm = await showAppDialog<bool>(
      context: context,
      // [GLASS THEME] Dialog/ConstrainedBox/AppContainer thủ công cũ ĐÃ THAY bằng
      // showAppDialog() — showAppDialog TỰ cấp khung Dialog/kính, nên bỏ AppContainer lồng
      // trong đây (tránh 2 lớp BackdropFilter chồng nhau); ConstrainedBox giữ lại để khóa
      // đúng maxWidth 400 như cũ ở CẢ 2 nhánh Sáng/Tối lẫn Kính.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.logout_rounded, size: 36, color: Colors.redAccent)),
            const SizedBox(height: 24), Text('Đăng xuất', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
            Text('Bạn có chắc chắn muốn thoát khỏi hệ thống?', textAlign: TextAlign.center, style: TextStyle(color: textSub, fontSize: 14)), const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 16),
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
              ],
            ),
          ],
        ),
      ),
    ) ?? false;
    if (confirm) { await AuthService().logout(); if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false); }
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController(), newPassCtrl = TextEditingController(), confirmPassCtrl = TextEditingController();
    bool isDialogLoading = false;
    showAppDialog(
      context: context,
      barrierDismissible: false,
      // [GLASS THEME] Dialog/ConstrainedBox/AppContainer thủ công cũ ĐÃ THAY bằng
      // showAppDialog() — bỏ AppContainer lồng (showAppDialog tự cấp khung), giữ nguyên
      // StatefulBuilder (state cục bộ isDialogLoading) + ConstrainedBox maxWidth 420.
      child: Builder(
        builder: (context) {
          final bool isDark = Theme.of(context).brightness == Brightness.dark;
          final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.lock_reset_rounded, color: tkGreen, size: 28), const SizedBox(width: 12), Text('Đổi mật khẩu', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold))]), const SizedBox(height: 24),
                    // [FORM SWEEP] 3× TextField -> AppTextField.
                    AppTextField(controller: oldPassCtrl, obscureText: true, labelText: 'Mật khẩu hiện tại'), const SizedBox(height: 16),
                    AppTextField(controller: newPassCtrl, obscureText: true, labelText: 'Mật khẩu mới'), const SizedBox(height: 16),
                    AppTextField(controller: confirmPassCtrl, obscureText: true, labelText: 'Xác nhận mật khẩu mới'), const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: isDialogLoading ? null : () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Colors.grey))), const SizedBox(width: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: tkGreen, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: isDialogLoading ? null : () async {
                            final oldPass = oldPassCtrl.text.trim(), newPass = newPassCtrl.text.trim(), confirmPass = confirmPassCtrl.text.trim();
                            if (oldPass.isEmpty || newPass.isEmpty) return;
                            if (newPass.length < 6) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu mới phải có tối thiểu 6 ký tự'), backgroundColor: Colors.redAccent)); return; }
                            if (newPass != confirmPass) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu xác nhận không khớp!'), backgroundColor: Colors.redAccent)); return; }
                            setDialogState(() => isDialogLoading = true);
                            String? error = await AuthService().changePassword(oldPass, newPass);
                            setDialogState(() => isDialogLoading = false);
                            if (error == null) {
                              if (!context.mounted) return; Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công!'), backgroundColor: Color(0xFF00A651)));
                            } else { if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent)); }
                          },
                          child: isDialogLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Lưu thay đổi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openProfileOrSettings(int tabIndex) {
    if (MediaQuery.of(context).size.width < 900) { setState(() => _selectedIndex = 4); } else { _showSettingsMenu(initialTab: tabIndex); }
  }

  // [FIX — Menu Avatar trắng đục trên nền Kính] PopupMenuButton.itemBuilder CHỈ điều khiển
  // List<PopupMenuEntry> — lớp Material bọc ngoài (nền/elevation/shape) do chính PopupMenuButton
  // tự dựng, itemBuilder không với tới được để thay bằng _GlassSurface. Giải pháp: làm Material
  // ngoài ấy TRONG SUỐT (color/elevation/shadow/surfaceTint = 0/transparent), rồi tự dựng ĐÚNG
  // 1 PopupMenuItem (padding zero, enabled: false — không tranh chấp tap với các hàng con) chứa
  // AppContainer bọc toàn bộ 4 dòng — đây mới là lớp kính thật. `onSelected` GIỮ NGUYÊN 100% —
  // mỗi hàng tự gọi Navigator.pop(context, value), đúng cơ chế PopupMenuItem mặc định vẫn dùng.
  Widget _buildUserAvatarMenu(Color textMain) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final t = AppTranslations.of(context);
    // [ĐỢT 9 — FIX TƯƠNG PHẢN] Trước đây BẬT Glass là ép chữ trắng vô điều kiện — trên nền
    // Sáng Kính (frost gần như trong suốt, tint trắng) chữ trắng gần như vô hình. Quy tắc mới:
    // TỐI khi hệ thống đang Sáng (dù Kính hay Thường), TRẮNG chỉ khi hệ thống đang Tối.
    final Color menuTextMain = isDark ? Colors.white : Colors.black87;
    // Bóng chữ kGlassTextShadow vốn thiết kế cho chữ TRẮNG nổi trên nền Aurora nhiều màu — chỉ
    // còn ý nghĩa ở Tối Kính; Sáng Kính dùng chữ tối trên nền đã phủ tint trắng đục, không cần.
    final List<Shadow>? sh = (isGlass && isDark) ? kGlassTextShadow : null;

    Widget menuRow(int value, IconData icon, String label, {Color? color, bool bold = false}) {
      final Color c = color ?? menuTextMain;
      return InkWell(
        onTap: () => Navigator.pop(context, value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Icon(icon, color: c, size: 20, shadows: sh),
            const SizedBox(width: 12),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c, fontWeight: bold ? FontWeight.bold : FontWeight.normal, shadows: sh))),
          ]),
        ),
      );
    }

    return PopupMenuButton<int>(
      offset: const Offset(0, 50),
      tooltip: t.text('account_tooltip'),
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      padding: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: const CircleAvatar(radius: 20, backgroundColor: Color(0xFF00A651), child: Icon(Icons.person, color: Colors.white)),
      onSelected: (value) { switch (value) { case 0: _openProfileOrSettings(0); break; case 1: _openProfileOrSettings(2); break; case 2: _onMenuTapped(6); break; case 3: _performLogout(context); break; } },
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: AppContainer(
            width: 240,
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            // [ĐỢT 9 — FIX TƯƠNG PHẢN] Sáng Kính: phủ tint trắng đục hơn (0.5) lên mặt kính —
            // frost mặc định (5% trắng) quá trong suốt, khiến chữ tối mới đổi ở trên không đủ
            // tương phản với nền Aurora nhiều màu phía sau.
            glassTint: (isGlass && !isDark) ? Colors.white.withValues(alpha: 0.5) : null,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                menuRow(0, Icons.account_circle_outlined, t.text('profile')),
                menuRow(1, Icons.lock_reset, t.text('change_password')),
                menuRow(2, Icons.security, t.text('manage_permissions')),
                Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                menuRow(3, Icons.logout, t.text('logout'), color: Colors.redAccent, bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // [GLASS THEME] WindowsSettingsDialog TỰ trả về nội dung thô (không còn tự bọc Dialog/
  // AppContainer bên trong build() của nó — xem class WindowsSettingsDialog) nên chỉ cần
  // đưa thẳng vào child: của showAppDialog, không có gì để "bóc lõi" thêm ở đây.
  // [FIX — Chữ vỡ layout] maxWidth: 1000 khớp ĐÚNG ConstrainedBox nội bộ của
  // WindowsSettingsDialog (Row sidebar 240px + Expanded) — showAppDialog mặc định 420 sẽ
  // bóp Expanded về gần 0 width nếu không truyền, vỡ layout chia đôi Menu/Nội dung.
  void _showSettingsMenu({int initialTab = 0}) { showAppDialog(context: context, maxWidth: 1000, child: WindowsSettingsDialog(currentRole: userRole, currentEmail: userEmail, initialTab: initialTab)); }

  void _showThemeDialog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color boxColor = isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1);
    // [GLASS THEME] Dialog/ClipRRect/BackdropFilter/Container thủ công cũ (tự dựng kính mờ
    // sigma 12) ĐÃ THAY bằng showAppDialog(): khi TẮT Glass Theme dựng lại đúng Dialog bo góc
    // 24 quen thuộc (nhánh mặc định của showAppDialog), khi BẬT Glass Theme tự lên Ultra-
    // Glassmorphism (sigma 20 + viền hắt sáng) — không cần định nghĩa lại hiệu ứng kính ở đây
    // nữa, chỉ còn giữ NỘI DUNG (chọn Sáng/Tối/Hệ thống) nguyên vẹn 100%.
    showAppDialog(
      context: context,
      barrierDismissible: true,
      child: Builder(
        builder: (context) {
          final themeProvider = Provider.of<ThemeProvider>(context);
          final languageProvider = Provider.of<LanguageProvider>(context);
          final t = AppTranslations.of(context);
          final bool isGlass = themeProvider.isGlassThemeEnabled;
          final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
          return SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t.text('appearance'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tkGreen)), IconButton(icon: Icon(Icons.close, color: textMain), onPressed: () => Navigator.pop(context))]),
                const SizedBox(height: 8),
                // [LINT] Chuẩn Flutter mới: RadioGroup tổ tiên quản lý groupValue/onChanged chung,
                // từng RadioListTile chỉ khai báo value (groupValue/onChanged per-tile đã deprecated).
                RadioGroup<ThemeMode>(
                  groupValue: themeProvider.themeMode,
                  onChanged: (val) { if (val != null) themeProvider.setThemeMode(val); },
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    RadioListTile<ThemeMode>(title: Text(t.text('light_mode'), style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: ThemeMode.light, activeColor: tkGreen),
                    RadioListTile<ThemeMode>(title: Text(t.text('dark_mode'), style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: ThemeMode.dark, activeColor: tkGreen),
                    RadioListTile<ThemeMode>(title: Text(t.text('system_mode'), style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), subtitle: const Text('Đổi màu theo ban ngày/ban đêm'), value: ThemeMode.system, activeColor: tkGreen),
                  ]),
                ),
                const SizedBox(height: 20),
                // [ĐỒNG BỘ MOBILE] Công tắc Glass Theme trước đây CHỈ có ở popup Cài đặt Desktop
                // (WindowsSettingsDialog._buildAppearanceTab) — mất tích ở đây (popup Giao diện
                // riêng của Mobile, mở từ _buildMobileSettingsView). Copy đúng layout Row + AppSwitch
                // của bản Desktop, cùng boxColor/padding để không lệch giao diện với nhóm Radio trên.
                Container(
                  decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.text('glass_theme'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600, shadows: sh)),
                            const SizedBox(height: 2),
                            Text(t.text('glass_theme_desc'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w500, shadows: sh)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      AppSwitch(
                        value: themeProvider.isGlassThemeEnabled,
                        activeColor: tkGreen,
                        onChanged: (v) => themeProvider.setGlassThemeEnabled(v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // [ĐA NGÔN NGỮ — PROOF OF CONCEPT] Đồng bộ CÙNG cấu trúc với bản Desktop
                // (_buildAppearanceTab) — RadioGroup<String> 'vi'/'en', cùng boxColor/layout với
                // nhóm Sáng/Tối phía trên để không lệch giao diện.
                Text(t.text('language'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, shadows: sh)), const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
                  child: RadioGroup<String>(
                    groupValue: languageProvider.locale.languageCode,
                    onChanged: (val) { if (val != null) languageProvider.changeLanguage(val); },
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      RadioListTile<String>(title: Text(t.text('vietnamese'), style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: 'vi', activeColor: tkGreen),
                      RadioListTile<String>(title: Text(t.text('english'), style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: 'en', activeColor: tkGreen),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // MAC của các thiết bị đang chọn (deviceKey = "MAC_endpoint" -> lấy MAC ở segment đầu)
  List<String> _selectedMacs() => _selectedDevices.map((k) => k.split('_').first).toSet().toList();

  // [PHÒNG] Chuyển HÀNG LOẠT thiết bị đã chọn vào 1 phòng (API thật qua RoomGroupProvider).
  Future<void> _bulkAssignRoom() async {
    final macs = _selectedMacs();
    if (macs.isEmpty) return;
    final provider = Provider.of<RoomGroupProvider>(context, listen: false);
    final room = await showRoomSelectionDialog(context, provider);
    if (room == null || !mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => Center(child: CircularProgressIndicator(color: tkGreen)));
    final err = await provider.assignDevicesToRoom(macs, room.id);
    if (!mounted) return;
    Navigator.pop(context); // đóng loading
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Đã chuyển ${macs.length} thiết bị vào "${room.name}"'),
        backgroundColor: err == null ? tkGreen : Colors.redAccent));
    if (err == null) setState(() { _isSelectionMode = false; _selectedDevices.clear(); });
  }

  // [NHÓM] Tạo Công tắc ảo từ các thiết bị đã chọn — persist thật qua POST /api/groups.
  // Hỗ trợ nhóm CẦU THANG: dialog nhận danh sách MAC + tên để user gán "Tầng" từng công tắc.
  Future<void> _bulkCreateGroup() async {
    final macs = _selectedMacs();
    if (macs.isEmpty) return;
    // [DISPLAY NAME] Tra tên hiển thị theo MAC — tên user đặt (DPS) thắng tên REST cấp
    // thiết bị; fallback 4 số cuối do dialog tự lo khi cả hai đều trống.
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    final Map<String, String> restNameByMac = {
      for (final d in _currentHomeDevices)
        (d['mac_address'] ?? d['mac'] ?? '').toString().replaceAll(':', '').toUpperCase():
            (d['name'] ?? '').toString(),
    };
    final result = await showCreateGroupDialog(context,
        memberMacs: macs,
        memberNameOf: (mac) =>
            deviceProv.displayNameOf(mac, fallback: restNameByMac[mac.toUpperCase()] ?? ''));
    if (result == null || !mounted) return;
    final String? err = await Provider.of<RoomGroupProvider>(context, listen: false)
        .createGroup(result.name, result.iconCodePoint, macs,
            groupType: result.groupType, floors: result.floors);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Đã tạo nhóm "${result.name}" (${macs.length} thiết bị)'),
        backgroundColor: err == null ? tkGreen : Colors.redAccent));
    if (err == null) setState(() { _isSelectionMode = false; _selectedDevices.clear(); });
  }

  // [CHUẨN HÓA — NGUỒN BƠM DUY NHẤT] Bộ callback tiêu chuẩn cho MỌI loại thẻ thiết bị.
  // Thẻ mới (vd SmartCurtainCard) chỉ cần nhận các callback này là có đủ Cài đặt/Thông tin/Hẹn giờ/
  // Lịch sử/Ngữ cảnh/Chia sẻ/Sửa/Xóa/Chuyển phòng/Chuyển nhà — KHÔNG phải viết logic riêng.
  // key = deviceKey/hideKey để đổi tên đúng endpoint.
  ({
    VoidCallback rename,
    VoidCallback delete,
    VoidCallback assignRoom,
    VoidCallback? assignHome,
    VoidCallback timer,
    VoidCallback history,
    VoidCallback automation,
    VoidCallback share,
  }) _stdCallbacks(String mac, String key, String name, {String endpoint = ''}) => (
        rename: () => _showRenameDialog(key, name),
        delete: () => _deleteDevice(mac),
        assignRoom: () => _assignSingleRoom(mac),
        assignHome: _isSuperUser ? () => _showAssignHomeDialog(mac) : null,
        // [RESPONSIVE NAV] Mobile: push toàn màn hình; PC: cửa sổ dialog lớn nổi trên
        // Dashboard — Sidebar/Topbar phía sau GIỮ NGUYÊN, không bị route đè mất
        // [FIX MULTI-RELAY] endpoint truyền xuống DeviceTimerScreen -> Hẹn giờ/Đếm ngược chỉ
        // nhắm ĐÚNG kênh của thẻ vừa mở menu, không còn mù kênh (bắn cả cụm SSW04 4 relay).
        timer: () => openAdaptiveScreen(context, DeviceTimerScreen(mac: mac, endpoint: endpoint, deviceName: name)),
        history: () => openAdaptiveScreen(context, DeviceHistoryScreen(mac: mac, deviceName: name)),
        automation: () => openAdaptiveScreen(context, const CreateAutomationScreen()),
        share: () => showShareDeviceDialog(context, mac: mac, deviceName: name),
      );

  // [PHÒNG] Gán 1 thiết bị vào phòng (từ menu ngữ cảnh của thẻ).
  Future<void> _assignSingleRoom(String mac) async {
    final provider = Provider.of<RoomGroupProvider>(context, listen: false);
    final room = await showRoomSelectionDialog(context, provider);
    if (room == null || !mounted) return;
    final err = await provider.assignDevicesToRoom([mac], room.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Đã thêm vào "${room.name}"'),
        backgroundColor: err == null ? tkGreen : Colors.redAccent));
  }

  // [NHÓM] Đổi tên nhóm (Công tắc ảo) — dialog nhập tên nhanh.
  Future<void> _renameGroup(String groupMac, String current) async {
    final ctrl = TextEditingController(text: current);
    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog().
    final newName = await showAppDialog<String>(
      context: context,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Đổi tên nhóm', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                const SizedBox(width: 8),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Lưu')),
              ],
            ),
          ],
        ),
      ),
    );
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    Provider.of<RoomGroupProvider>(context, listen: false).renameGroup(groupMac, newName);
  }

  // [NHÓM] Mở màn chỉnh sửa nhóm — RESPONSIVE: PC mở dạng Dialog nổi giữa (KHÔNG che Sidebar),
  // Mobile mở full màn hình như cũ. Truyền danh sách công tắc thật để pick thêm thành viên.
  // [NHÓM] Điều khiển TẤT CẢ thành viên của một nhóm ảo về cùng trạng thái [turnOn].
  // [MULTI-CHANNEL] Thành viên có endpoint cụ thể (kênh SSW04, D1/F1 Hub) -> lệnh trỏ
  // ĐÍCH DANH kênh đó, không còn cảnh bật/tắt cả cụm 4 relay. Thành viên kiểu cũ
  // (endpoint rỗng = cả thiết bị) giữ nguyên hành vi 'all' (SSW04 -> cả 4; SSW01/quạt
  // bỏ qua endpoint, chỉ đọc value).
  void _toggleGroup(DeviceGroup g, bool turnOn) {
    if (g.members.isEmpty) return;
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    for (final m in g.members) {
      // [FALLBACK CHUẨN] targetID = member.endpoint (ID đầy đủ "S_{mac}_2"...);
      // rỗng (member đời cũ / cả thiết bị) -> 'all' (SSW04: cả 4 kênh; SSW01/quạt chỉ đọc value)
      final String targetId = m.endpoint.isEmpty ? 'all' : m.endpoint;
      if (kDebugMode) {
        print('🕹️ [GROUP TOGGLE] ${g.name}: ${m.mac} endpoint="$targetId" -> ${turnOn ? 'ON' : 'OFF'}'
            '${m.endpoint.isEmpty ? ' (member kiểu cũ — CẢ THIẾT BỊ; vào Sửa nhóm tick từng kênh nếu muốn per-relay)' : ''}');
      }
      deviceProv.setSwitchState(m.mac, targetId, turnOn);
    }
    // Không optimistic: icon nhóm sáng/tắt theo state feedback thật từ các thành viên
    // (group section watch DeviceProvider -> tự vẽ lại khi member đổi trạng thái).
  }

  void _openEditGroup(String groupMac) {
    // [DISPLAY NAME] Tên user đặt (kho DPS) thắng tên cấp thiết bị từ REST (sw-xxxx)
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    final avail = _currentHomeDevices.map((d) {
      final String mac = (d['mac_address'] ?? d['mac'] ?? '').toString();
      return {
        'mac': mac,
        'name': deviceProv.displayNameOf(mac, fallback: (d['name'] ?? mac).toString()),
      };
    }).where((e) => (e['mac'] ?? '').isNotEmpty).toList();

    if (MediaQuery.of(context).size.width > 800) {
      // PC/Web: Dialog kích thước cố định nổi lên giữa, sidebar vẫn hiện phía sau
      // [GLASS THEME] Dialog/ClipRRect thủ công cũ ĐÃ THAY bằng showAppDialog() — bo góc/
      // khung Dialog nay do showAppDialog tự lo, chỉ còn giữ đúng kích thước 500x600 cố định.
      showAppDialog(
        context: context,
        child: SizedBox(width: 500, height: 600, child: EditGroupScreen(groupMac: groupMac, availableDevices: avail, embedded: true)),
      );
    } else {
      // Mobile: full màn hình như cũ
      Navigator.push(context, MaterialPageRoute(builder: (_) => EditGroupScreen(groupMac: groupMac, availableDevices: avail)));
    }
  }

  void _onMenuTapped(int index, {bool isFromDrawer = false}) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);

    if (isFromDrawer && isMobile) Navigator.pop(context); 

    if (index == 5 && isMobile) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => AppScaffold(appBar: AppBar(title: const Text('Quản lý hệ sinh thái'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: SafeArea(child: HomeManagementScreen(userRole: userRole, userEmail: userEmail))))).then((value) => _initializeHome());
      return; 
    }

    if (index == 6 && isMobile) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => AppScaffold(appBar: AppBar(title: const Text('Phân quyền'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: const SafeArea(child: RoleManagementView()))));
      return; 
    }

    if (index == 4 && !isMobile) { _showSettingsMenu(initialTab: 0); } else { setState(() => _selectedIndex = index); }
  }

  // [ADMIN] Hộp thoại "Chuyển sang nhà khác" — chỉ SUPER_USER mở tới (từ menu thẻ thiết bị).
  // Lấy danh sách nhà -> Dropdown chọn nhà đích -> Xác nhận gọi API -> đóng -> Toast -> fetch lại.
  Future<void> _showAssignHomeDialog(String mac) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final admin = AdminService();

    final homes = await admin.getHomes();
    if (!mounted) return;
    if (homes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không lấy được danh sách nhà'), backgroundColor: Colors.redAccent));
      return;
    }

    String? selectedHomeId = homes.first['home_id']?.toString();
    bool submitting = false;

    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog() — gộp
    // title+content+actions cũ vào 1 Column duy nhất (showAppDialog không có slot title/content
    // riêng), giữ nguyên StatefulBuilder + toàn bộ logic gọi API/callback.
    await showAppDialog(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDialog) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [Icon(Icons.swap_horiz, color: tkGreen), const SizedBox(width: 10), Text('Chuyển nhà thiết bị', style: TextStyle(color: textMain))]),
              const SizedBox(height: 20),
              Text('MAC: $mac', style: TextStyle(color: textSub, fontSize: 12)),
              const SizedBox(height: 16),
              Text('Chọn nhà đích:', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedHomeId,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: textMain),
                items: homes.map((h) => DropdownMenuItem(
                  value: h['home_id']?.toString(),
                  child: Text((h['home_name'] ?? h['home_id'] ?? '—').toString(), overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: submitting ? null : (v) => setDialog(() => selectedHomeId = v),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('Hủy')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white),
                    onPressed: (submitting || selectedHomeId == null) ? null : () async {
                      setDialog(() => submitting = true);
                      final err = await admin.assignDeviceToHome(mac, selectedHomeId!);
                      // ctx (dialog) và context (State) là 2 vòng đời khác nhau -> guard đúng từng cái
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      if (err == null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Đã chuyển thiết bị sang nhà mới'), backgroundColor: tkGreen));
                        _initializeHome(); // fetch lại danh sách thiết bị trên màn hình
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                      }
                    },
                    child: submitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Xác nhận'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // [OTA_UPDATE] Hộp thoại "Bản cập nhật mới" — bật khi chạm tin OTA trên chuông (thay vì deeplink).
  // Nút CẬP NHẬT NGAY gọi API trigger OTA (đã có sẵn) qua MQTT tới thiết bị.
  void _showUpdateDialog(String mac, String version, String changelog) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog() — gộp
    // title+content+actions vào 1 Column, logic gọi API/callback giữ nguyên 100%.
    showAppDialog(
      context: context,
      child: Builder(
        builder: (ctx) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.system_update_alt, color: tkGreen, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text('Bản cập nhật mới', style: TextStyle(color: textMain, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 20),
              Text('Thiết bị: $mac', style: TextStyle(color: textSub, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                Text('Phiên bản mới: ', style: TextStyle(color: textSub, fontSize: 13)),
                Text(version.isEmpty ? '—' : 'v$version', style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              Text('Nội dung thay đổi:', style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(changelog.isEmpty ? 'Không có mô tả.' : changelog,
                      style: TextStyle(color: textSub, fontSize: 13, height: 1.4)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Để sau')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('CẬP NHẬT NGAY'),
                    onPressed: () async {
                      Navigator.pop(ctx); // đóng Dialog trước
                      final ok = await ApiService().triggerOtaUpdate(mac);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Đang tiến hành cập nhật...' : 'Không gửi được lệnh (thiết bị offline?)'),
                        backgroundColor: ok ? tkGreen : Colors.redAccent,
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationPanel(Color textMain, Color textSub) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Provider.of<NotificationProvider>(context, listen: false).clearNewBadge();

    showDialog(
      context: context, barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 900;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Align(
              alignment: Alignment.topRight,
              child: Container(
                margin: EdgeInsets.only(top: isMobile ? 56 : 70, right: isMobile ? 16 : 80), 
                width: isMobile ? MediaQuery.of(context).size.width - 32 : 380,
                child: Material(
                  color: Colors.transparent,
                  child: AppContainer(
                    padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(16),
                    child: Consumer<NotificationProvider>(
                      builder: (context, notifProvider, child) {
                        final listNotif = notifProvider.list;
                        final t = AppTranslations.of(context);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(t.text('notifications_title'), style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                                  // Nút "Đọc tất cả" chỉ bật khi còn tin chưa đọc
                                  notifProvider.unreadCount > 0
                                      ? TextButton.icon(
                                          onPressed: () => notifProvider.markAllRead(),
                                          icon: Icon(Icons.done_all_rounded, size: 16, color: tkGreen),
                                          label: Text(t.text('mark_all_read'), style: TextStyle(color: tkGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                        )
                                      : Text('${t.text('total_count_prefix')}${listNotif.length}', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(t.text('push_notif_toggle'), style: TextStyle(color: textMain, fontSize: 13)),
                                  Switch(
                                    value: _isPushEnabled, activeThumbColor: tkGreen,
                                    onChanged: (val) { setState(() => _isPushEnabled = val); setDialogState(() => _isPushEnabled = val); },
                                  )
                                ]
                              )
                            ),
                            Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                            if (listNotif.isEmpty)
                              Padding(padding: const EdgeInsets.all(32.0), child: Center(child: Text(t.text('no_notifications'), style: TextStyle(color: textSub, fontSize: 13))))
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 400),
                                child: ListView.separated(
                                  shrinkWrap: true, physics: const BouncingScrollPhysics(), itemCount: listNotif.length,
                                  separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: isDark ? Colors.white10 : Colors.grey.shade100),
                                  itemBuilder: (context, index) {
                                    final notif = listNotif[index];
                                    return _buildNotifRow(
                                      notif: notif, isDark: isDark, textMain: textMain, textSub: textSub,
                                      notifProvider: notifProvider,
                                      onTap: notif.mac.isEmpty ? null : () {
                                        Navigator.of(context).pop();
                                        _openDeviceSettingsByMac(notif.mac);
                                      },
                                    );
                                  },
                                ),
                              ),
                          ]
                        );
                      }
                    )
                  )
                )
              )
            );
          }
        );
      }
    );
  }

  // [DISPLAY NAME — CẤM MAC THÔ TRONG THÔNG BÁO] Khử mọi MAC 12-hex còn sót trong nội
  // dung tin (lịch sử đời cũ trong Redis vẫn mang "(MAC: XXXX)" dù server đã sửa):
  //   1. Gỡ hậu tố "(MAC: ...)" server phiên bản cũ chèn vào.
  //   2. MAC trần còn lại -> thay bằng tên thân thiện từ kho DPS (cùng bộ quy tắc
  //      DeviceProvider.displayNameOf toàn app); thiết bị chưa sync tên -> "Thiết bị lạ".
  String _friendlyNotifMessage(NotificationItem notif) {
    final t = AppTranslations.of(context);
    String msg = notif.message.replaceAll(RegExp(r'\s*\(MAC:\s*[0-9A-Fa-f]{12}\)'), '');
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    msg = msg.replaceAllMapped(RegExp(r'\b[0-9A-F]{12}\b'), (m) {
      final d = deviceProv.deviceOf(m.group(0)!);
      return d == null ? t.text('unknown_device') : d.displayName();
    });
    return msg;
  }

  // Hàng thông báo DÙNG CHUNG cho cả popup chuông lẫn tab "Tất cả thông báo":
  //  • Chấm màu bên phải = CHƯA ĐỌC; đọc rồi thì chữ mờ đi (Opacity) đúng chuẩn Tuya/Mi Home.
  //  • Vuốt SANG TRÁI = xóa hẳn (nền đỏ, thùng rác) — gọi provider.dismiss (xóa cả trên Redis).
  //  • Vuốt SANG PHẢI = đánh dấu đã đọc (nền xanh) mà KHÔNG gỡ khỏi danh sách.
  //  • Chạm vào hàng = đánh dấu đã đọc + deeplink mở Popup Cài đặt thiết bị (nếu có MAC).
  Widget _buildNotifRow({
    required NotificationItem notif,
    required bool isDark,
    required Color textMain,
    required Color textSub,
    required NotificationProvider notifProvider,
    VoidCallback? onTap,
  }) {
    final t = AppTranslations.of(context);
    IconData icon = Icons.info_outline_rounded;
    if (notif.type == 'ALERT') {
      icon = Icons.warning_amber_rounded;
    } else if (notif.type == 'SYSTEM') {
      icon = Icons.system_security_update_good_rounded;
    } else if (notif.type == 'DEVICE') {
      icon = Icons.power_off_outlined;
    }
    final Color notifColor = Color(notif.colorValue); // parse an toàn — màu rác không sập panel
    final bool read = notif.isRead;

    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      hoverColor: isDark ? Colors.white10 : Colors.grey.shade50,
      leading: CircleAvatar(
        backgroundColor: notifColor.withValues(alpha: read ? 0.06 : 0.12),
        child: Icon(icon, color: read ? notifColor.withValues(alpha: 0.5) : notifColor, size: 20),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              notif.title,
              style: TextStyle(
                color: read ? textSub : textMain,
                fontWeight: read ? FontWeight.w500 : FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(notif.time, style: TextStyle(color: textSub, fontSize: 11)),
          // Chấm CHƯA ĐỌC nằm cuối hàng tiêu đề
          if (!read) Padding(padding: const EdgeInsets.only(left: 6), child: Container(width: 8, height: 8, decoration: BoxDecoration(color: notifColor, shape: BoxShape.circle))),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        // [DISPLAY NAME] Nội dung đi qua bộ lọc tên — không bao giờ hiện MAC thô
        child: Text(_friendlyNotifMessage(notif), style: TextStyle(color: textSub.withValues(alpha: read ? 0.7 : 1.0), height: 1.4, fontSize: 13)),
      ),
      onTap: () {
        // Chạm là đã đọc (kể cả khi không có MAC để deeplink)
        if (!notif.isRead) notifProvider.markAsRead(notif.id);
        // [OTA_UPDATE] KHÔNG deeplink — mở hộp thoại cập nhật với mac/version/changelog kèm theo
        if (notif.type == 'OTA_UPDATE') {
          _showUpdateDialog(notif.mac, notif.version, notif.changelog);
          return;
        }
        if (onTap != null) onTap();
      },
    );

    return Dismissible(
      key: ValueKey(notif.id.isNotEmpty ? notif.id : '${notif.title}_${notif.time}'),
      // Vuốt sang phải (đầu->cuối) = đánh dấu đã đọc; không cho phép nếu đã đọc rồi
      background: Container(
        color: tkGreen.withValues(alpha: 0.85), alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.done_all_rounded, color: Colors.white), const SizedBox(width: 8), Text(t.text('read'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
      ),
      secondaryBackground: Container(
        color: Colors.redAccent, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(t.text('delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(width: 8), const Icon(Icons.delete_outline_rounded, color: Colors.white)]),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Đánh dấu đã đọc nhưng GIỮ hàng trong danh sách -> trả false
          if (!notif.isRead) notifProvider.markAsRead(notif.id);
          return false;
        }
        return true; // vuốt trái -> cho phép gỡ khỏi cây widget
      },
      onDismissed: (_) => notifProvider.dismiss(notif.id),
      child: tile,
    );
  }

  Widget _buildNotificationBell(Color textMain, Color textSub) {
    return Consumer<NotificationProvider>(
      builder: (context, notifProvider, child) {
        // Badge chỉ đếm tin CHƯA ĐỌC (chuẩn Tuya/Mi Home) — đọc hết là chuông sạch số
        int count = notifProvider.unreadCount;
        final t = AppTranslations.of(context);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // [UX — TOUCH TARGET 48x48 chuẩn Material] Icon vẫn 24 (KHÔNG to thêm) nhưng vùng
            // chạm đảm bảo tối thiểu 48x48: padding 12 + constraints ép tối thiểu 48 + splashRadius
            // 24 cho ripple tròn đầy. Bấm dễ trúng trên cả cảm ứng lẫn chuột, layout không xô lệch.
            IconButton(
              icon: Icon(Icons.notifications_none_rounded, color: textMain),
              iconSize: 24,
              padding: const EdgeInsets.all(12),
              splashRadius: 24,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: t.text('new_notifications_tooltip'),
              onPressed: () => _showNotificationPanel(textMain, textSub),
            ),
            if (count > 0)
              Positioned(
                top: 6, right: 6,
                // IgnorePointer: badge KHÔNG hứng cú chạm -> mọi tap quanh nó đều xuống nút chuông
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                    child: Text(count > 9 ? '9+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1)),
                  ),
                ),
              )
          ],
        );
      },
    );
  }

  Widget _buildFullNotificationView(bool isDark, Color textMain, Color textSub) {
    return AppContainer(
      padding: const EdgeInsets.all(0),
      child: Consumer<NotificationProvider>(
        builder: (context, notifProvider, child) {
          final listNotif = notifProvider.list;
          final t = AppTranslations.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(t.text('notifications_full_title'), style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (notifProvider.unreadCount > 0)
                          TextButton.icon(
                            onPressed: () => notifProvider.markAllRead(),
                            icon: Icon(Icons.done_all_rounded, size: 18, color: tkGreen),
                            label: Text(t.text('mark_all_read'), style: TextStyle(color: tkGreen, fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                        const SizedBox(width: 8),
                        Text(t.text('push_short'), style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w600)),
                        Switch(value: _isPushEnabled, activeThumbColor: tkGreen, onChanged: (val) => setState(() => _isPushEnabled = val)),
                      ],
                    )
                  ],
                ),
              ),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
              Expanded(
                child: listNotif.isEmpty
                    ? Center(child: Text(t.text('no_notifications'), style: TextStyle(color: textSub)))
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(16), itemCount: listNotif.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: isDark ? Colors.white10 : Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final notif = listNotif[index];
                          return _buildNotifRow(
                            notif: notif, isDark: isDark, textMain: textMain, textSub: textSub,
                            notifProvider: notifProvider,
                            onTap: notif.mac.isEmpty ? null : () => _openDeviceSettingsByMac(notif.mac),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- THANH CÔNG CỤ HIỆN LÊN KHI CHỌN NHIỀU THIẾT BỊ ---
  Widget _buildSelectionActionBar(bool isDark) {
    final t = AppTranslations.of(context);
    return Material(
      elevation: 20,
      borderRadius: BorderRadius.circular(24),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shadowColor: Colors.black45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        width: 450, // Giới hạn chiều rộng cho đẹp trên màn hình PC
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // [GIỮ NGUYÊN BIẾN ĐỘNG] _selectedDevices.length — số đếm thật, chỉ nhãn dịch.
            Text('${t.text('selected_count')}${_selectedDevices.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00A651))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: t.text('rename_bulk_tooltip'),
                  icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng đổi tên hàng loạt đang phát triển')));
                    setState(() { _isSelectionMode = false; _selectedDevices.clear(); });
                  }
                ),
                // [PHÒNG] Chuyển hàng loạt thiết bị đã chọn vào một phòng
                IconButton(
                  tooltip: t.text('move_room_bulk_tooltip'),
                  icon: const Icon(Icons.meeting_room, color: Color(0xFF00A651)),
                  onPressed: _bulkAssignRoom,
                ),
                // [NHÓM] Tạo Công tắc ảo từ các thiết bị đã chọn
                IconButton(
                  tooltip: t.text('create_group_bulk_tooltip'),
                  icon: const Icon(Icons.category, color: Colors.purpleAccent),
                  onPressed: _bulkCreateGroup,
                ),
                IconButton(
                  tooltip: t.text('hide_show_bulk_tooltip'),
                  icon: Icon(_showHiddenFilter ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.orange),
                  onPressed: () {
                    setState(() {
                      if (_showHiddenFilter) {
                        _hiddenDevices.removeAll(_selectedDevices);
                      } else {
                        _hiddenDevices.addAll(_selectedDevices);
                      }
                      _isSelectionMode = false; _selectedDevices.clear();
                    });
                  }
                ),
                IconButton(
                  tooltip: t.text('delete_bulk_tooltip'),
                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang xóa ${_selectedDevices.length} thiết bị...')));
                    setState(() { _isSelectionMode = false; _selectedDevices.clear(); });
                  }
                ),
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20), 
                    onPressed: () => setState(() { _isSelectionMode = false; _selectedDevices.clear(); })
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [GLASS THEME — VÍ DỤ ÁP DỤNG] Xem app_ui_wrappers.dart để hiểu cờ này chi phối gì.
    // Scaffold() gốc đổi thành AppScaffold() bên dưới; AppBar/BottomNav tự trong suốt khi
    // bật Glass NHƯNG cần được truyền backgroundColor trong suốt tận đây — AppScaffold không
    // "mổ" được màu của 1 AppBar/BottomNavigationBar tùy ý truyền vào (đã ghi rõ trong docs
    // của AppScaffold).
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final Color bgLight = isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2);
    final Color surfaceLight = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: bgLight,
      appBar: isMobile
          ? AppBar(
              backgroundColor: isGlass ? Colors.transparent : (isDark ? surfaceLight : bgLight), elevation: 0, iconTheme: IconThemeData(color: tkGreen),
              title: Text(_selectedIndex == 3 ? 'THÔNG BÁO' : _selectedIndex == 4 ? 'CÀI ĐẶT' : 'MY HOME', style: TextStyle(color: textMain, fontWeight: FontWeight.w900, letterSpacing: 1.2)), centerTitle: true, 
              actions: _selectedIndex == 4 ? [] : [
                IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded, color: textMain),
                  onPressed: () async {
                    // [FIX] Bắt lấy mã MAC dialog trả về rồi GỌI API LINK THẬT
                    // (kèm SnackBar báo thành công/lỗi chi tiết) — trước đây kết quả bị vứt bỏ
                    final result = await showAppDialog(context: context, contentPadding: const EdgeInsets.all(8), child: AddDeviceDialog(ownedMacs: _ownedMacs));
                    await _linkScannedDevice(result);
                    _handleRefresh();
                  },
                ),
                _buildNotificationBell(textMain, textSub), const SizedBox(width: 8),
              ]
            )
          : null,
      drawer: isMobile ? _buildMobileDrawer(isDark, surfaceLight, textMain, textSub) : null,
      
      body: Column(
        children: [
          if (!kIsWeb && !isMobile && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) _buildCustomTitleBar(isDark),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) _buildDesktopFloatingSidebar(isDark, textMain, textSub),
                Expanded(
                  child: SafeArea(
                    // [ADMIN] index 7 = Quản trị hệ thống, nhúng thẳng vào body (giữ sidebar + header)
                    child: _selectedIndex == 7 ? const AdminSystemScreen(embedded: true)
                         // [PHÒNG] index 1 = Quản lý phòng, nhúng làm tab body (embedded: bỏ AppBar Back)
                         : _selectedIndex == 1 ? const RoomManagementScreen(embedded: true)
                         // [NGỮ CẢNH] index 2 = Automation/Scene, nhúng làm tab body
                         : _selectedIndex == 2 ? const AutomationScreen(embedded: true)
                         : _selectedIndex == 6 ? const RoleManagementView()
                         : _selectedIndex == 3 ? Padding(padding: const EdgeInsets.all(16.0), child: _buildFullNotificationView(isDark, textMain, textSub))
                         : _selectedIndex == 5 ? HomeManagementScreen(userRole: userRole, userEmail: userEmail)
                         : _selectedIndex == 4 && isMobile ? _buildMobileSettingsView(isDark, textMain, textSub) 
                         : isMobile 
                            ? RefreshIndicator(color: tkGreen, backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, onRefresh: _handleRefresh, child: _buildMobileContent(isDark, surfaceLight, textMain, textSub))
                            : Padding(padding: const EdgeInsets.fromLTRB(32.0, 16.0, 32.0, 24.0), child: _buildBentoDashboard(isDark, textMain, textSub)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      
      // THANH CHỌN NHIỀU NỔI LÊN BÊN DƯỚI
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isSelectionMode ? _buildSelectionActionBar(isDark) : null,

      bottomNavigationBar: isMobile ? _buildBottomNav(isGlass ? Colors.transparent : surfaceLight, textSub) : null,
    );
  }

  Widget _buildMobileSettingsView(bool isDark, Color textMain, Color textSub) {
    final t = AppTranslations.of(context);
    Widget buildSettingGroup(List<Widget> children) => Padding(padding: const EdgeInsets.only(bottom: 24.0), child: AppContainer(padding: EdgeInsets.zero, child: Column(children: children)));
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingGroup([
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(radius: 30, backgroundColor: tkGreen.withValues(alpha: 0.2), child: Icon(Icons.person, color: tkGreen, size: 32)),
              // [FIX OVERFLOW] Email dài + trailing menu từng làm tràn ngang tile trên Mobile:
              // ép 1 dòng + ellipsis để title/subtitle luôn nằm gọn trong phần Expanded của ListTile.
              title: Text(userEmail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4.0), child: Text('${t.text('role_label')}: $userRole', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textSub, fontWeight: FontWeight.w600))),
              trailing: PopupMenuButton<int>(
                icon: Icon(Icons.edit_outlined, color: textSub), offset: const Offset(0, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: isDark ? const Color(0xFF1E293B) : Colors.white,
                onSelected: (value) {
                  switch (value) {
                    case 0: Navigator.push(context, MaterialPageRoute(builder: (context) => AppScaffold(appBar: AppBar(title: Text(t.text('profile')), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: SafeArea(child: ProfileManagementView(currentRole: userRole, currentEmail: userEmail))))); break;
                    case 1: _showChangePasswordDialog(); break;
                    case 2: Navigator.push(context, MaterialPageRoute(builder: (context) => AppScaffold(appBar: AppBar(title: Text(t.text('permissions')), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: const SafeArea(child: RoleManagementView())))); break;
                    // [ADMIN DASHBOARD] Chỉ SUPER_USER thấy mục này (item chỉ được render khi đủ quyền)
                    case 4: Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminSystemScreen())); break;
                    case 3: _performLogout(context); break;
                  }
                },
                // [FIX OVERFLOW] Text trong item bọc Flexible + ellipsis — popup bị kẹp bề ngang
                // trên Mobile màn hẹp thì chữ tự co, không còn tràn/vỡ hàng.
                itemBuilder: (context) => [
                  PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.account_circle_outlined, color: textMain), const SizedBox(width: 12), Flexible(child: Text(t.text('profile'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain)))])),
                  PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.lock_reset, color: textMain), const SizedBox(width: 12), Flexible(child: Text(t.text('change_password'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain)))])),
                  PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.security, color: textMain), const SizedBox(width: 12), Flexible(child: Text(t.text('manage_permissions'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain)))])),
                  // [PHÂN QUYỀN] Mục 'Quản trị Hệ thống' chỉ hiển thị cho tài khoản admin (SUPER_USER)
                  if (_isSuperUser)
                    PopupMenuItem(value: 4, child: Row(children: [Icon(Icons.admin_panel_settings_outlined, color: tkGreen), const SizedBox(width: 12), Flexible(child: Text(t.text('system_admin'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)))])),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.logout, color: Colors.redAccent), const SizedBox(width: 12), Flexible(child: Text(t.text('logout'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)))])),
                ],
              ),
              onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => AppScaffold(appBar: AppBar(title: Text(t.text('profile')), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: SafeArea(child: ProfileManagementView(currentRole: userRole, currentEmail: userEmail))))); }
            ),
          ]),
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text(t.text('general_section'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          buildSettingGroup([ListTile(leading: Icon(Icons.palette_outlined, color: textMain), title: Text(t.text('appearance_color'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Icon(Icons.chevron_right, color: textSub), onTap: () => _showThemeDialog())]),
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text(t.text('security_section'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          buildSettingGroup([ListTile(leading: Icon(Icons.lock_outline, color: textMain), title: Text(t.text('change_password'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Icon(Icons.chevron_right, color: textSub), onTap: () => _showChangePasswordDialog())]),
          // [ADMIN] Nhóm QUẢN TRỊ chỉ hiển thị cho tài khoản quyền cao nhất (SUPER_USER)
          if (_isSuperUser) ...[
            Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text(t.text('admin_section'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
            buildSettingGroup([ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined, color: tkGreen),
              title: Text(t.text('system_admin'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
              subtitle: Text(t.text('system_admin_desc'), style: TextStyle(color: textSub, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: textSub),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminSystemScreen())),
            )]),
          ],
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text(t.text('system_section'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          buildSettingGroup([
            ListTile(leading: Icon(Icons.dns_outlined, color: textMain), title: Text(t.text('server'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Text('Armbian OS', style: TextStyle(color: textSub))),
            Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.2)),
            ListTile(leading: Icon(Icons.info_outline, color: textMain), title: Text(t.text('software_version_label'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Text('3.0.1 (Stable)', style: TextStyle(color: textSub))),
          ]),
          buildSettingGroup([ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: Text(t.text('logout_device'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: () => _performLogout(context))]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCustomTitleBar(bool isDark) {
    return DragToMoveArea(
      child: Container(
        height: 36, color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(icon: Icon(Icons.minimize, size: 16, color: isDark ? Colors.white54 : Colors.black54), onPressed: () => windowManager.minimize(), splashRadius: 20),
            IconButton(icon: Icon(Icons.crop_square, size: 16, color: isDark ? Colors.white54 : Colors.black54), onPressed: () async { if (await windowManager.isMaximized()) { windowManager.unmaximize(); } else { windowManager.maximize(); } }, splashRadius: 20),
            IconButton(icon: Icon(Icons.close, size: 16, color: isDark ? Colors.white54 : Colors.black54), hoverColor: Colors.redAccent, onPressed: () => windowManager.close(), splashRadius: 20),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopFloatingSidebar(bool isDark, Color txtMain, Color txtSub) {
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    final t = AppTranslations.of(context);
    return Container(
      width: 260, margin: const EdgeInsets.only(left: 24, bottom: 24, top: 16),
      child: AppContainer(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 40),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.home_rounded, color: tkGreen, size: 28)),
                  const SizedBox(width: 16),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TUAN KIET', style: TextStyle(color: tkGreen, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1, shadows: sh)), Text('CloudPlatform', style: TextStyle(color: txtSub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, shadows: sh))]),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildMenuItem(0, Icons.dashboard_rounded, t.text('dashboard'), txtMain, txtSub),
                  _buildMenuItem(5, Icons.maps_home_work_rounded, t.text('home_management'), txtMain, txtSub),
                  _buildMenuItem(1, Icons.meeting_room_rounded, t.text('rooms'), txtMain, txtSub),
                  _buildMenuItem(2, Icons.auto_awesome_rounded, t.text('routines'), txtMain, txtSub),
                  _buildMenuItem(3, Icons.notifications_active_rounded, t.text('notifications'), txtMain, txtSub),
                  _buildMenuItem(6, Icons.security_rounded, t.text('permissions'), txtMain, txtSub),
                  // [ADMIN] Nút Quản trị hệ thống — chỉ SUPER_USER thấy, đặt NGAY TRÊN 'Cài đặt'
                  if (_isSuperUser) _buildAdminMenuItem(txtMain, txtSub),
                  _buildMenuItem(4, Icons.settings_rounded, t.text('settings'), txtMain, txtSub),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [FIX — Drawer trắng đục lạc quẻ trên nền Kính] Container(color: surface) trần trước đây
  // ĐỨNG NGOÀI hệ thống app_ui_wrappers.dart — không hề đọc isGlassThemeEnabled, nên luôn đục
  // bất kể toàn app đã lên kính. Đồng bộ ĐÚNG pattern _buildDesktopFloatingSidebar bên dưới
  // (component nav-menu song sinh, cũng bọc AppContainer) thay vì tự chế lại lần 2.
  // Drawer(backgroundColor: transparent, elevation: 0) để lộ _GlassSurface bên trong AppContainer;
  // borderRadius: zero + padding: zero để giữ nguyên hình chữ nhật sát mép + không cộng dồn
  // padding với ListView bên trong (tránh "lẹm viền").
  Widget _buildMobileDrawer(bool isDark, Color surface, Color txtMain, Color txtSub) {
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    final t = AppTranslations.of(context);
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: AppContainer(
        width: 260,
        color: surface,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.only(top: 60, bottom: 24, left: 24),
              child: Row(
                children: [
                  Icon(Icons.home_rounded, color: tkGreen, size: 36),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text('TUAN KIET', style: TextStyle(color: tkGreen, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1, shadows: sh)), Text('CloudPlatform', style: TextStyle(color: txtSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, shadows: sh))]),
                ],
              ),
            ),
            Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  _buildMenuItem(0, Icons.dashboard_rounded, t.text('dashboard_short'), txtMain, txtSub, isFromDrawer: true),
                  _buildMenuItem(5, Icons.maps_home_work_rounded, t.text('home_management'), txtMain, txtSub, isFromDrawer: true),
                  _buildMenuItem(1, Icons.meeting_room_rounded, t.text('rooms'), txtMain, txtSub, isFromDrawer: true),
                  _buildMenuItem(2, Icons.auto_awesome_rounded, t.text('routines'), txtMain, txtSub, isFromDrawer: true),
                  _buildMenuItem(6, Icons.security_rounded, t.text('permissions'), txtMain, txtSub, isFromDrawer: true),
                  // [ADMIN] Nút Quản trị hệ thống — chỉ SUPER_USER thấy, đặt NGAY TRÊN 'Cài đặt'
                  if (_isSuperUser) _buildAdminMenuItem(txtMain, txtSub, isFromDrawer: true),
                  _buildMenuItem(4, Icons.settings_rounded, t.text('settings'), txtMain, txtSub, isFromDrawer: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [FIX — Chữ/icon tối trên nền kính] Dùng chung cho cả _buildDesktopFloatingSidebar (đã
  // AppContainer từ trước) và _buildMobileDrawer (vừa lên kính) — thêm shadow gate isGlass,
  // KHÔNG đổi bất kỳ logic onTap/điều hướng nào.
  Widget _buildMenuItem(int index, IconData icon, String title, Color txtMain, Color txtSub, {bool isFromDrawer = false}) {
    bool isSelected = _selectedIndex == index;
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: isSelected ? tkGreen.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? tkGreen.withValues(alpha: 0.3) : Colors.transparent)),

      // SỬA LỖI CẢNH BÁO LIST TILE BẰNG THẺ MATERIAL NÀY
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(icon, color: isSelected ? tkGreen : txtSub, size: 22, shadows: sh),
          title: Text(title, style: TextStyle(color: isSelected ? tkGreen : txtMain, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, shadows: sh)),
          onTap: () => _onMenuTapped(index, isFromDrawer: isFromDrawer),
        ),
      ),
    );
  }

  // Index dành riêng cho màn Quản trị hệ thống (nhúng trong body qua _selectedIndex).
  static const int kAdminIndex = 7;

  // [ADMIN] Nút Sidebar "Quản trị hệ thống" — nhúng qua _selectedIndex (KHÔNG Navigator.push nữa
  // để không đè lên sidebar/header). isSelected sáng xanh như các mục menu khác.
  Widget _buildAdminMenuItem(Color txtMain, Color txtSub, {bool isFromDrawer = false}) {
    final bool isSelected = _selectedIndex == kAdminIndex;
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    final t = AppTranslations.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? tkGreen.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? tkGreen.withValues(alpha: 0.3) : Colors.transparent),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(Icons.admin_panel_settings, color: isSelected ? tkGreen : txtSub, size: 22, shadows: sh),
          title: Text(t.text('system_admin'),
              style: TextStyle(color: isSelected ? tkGreen : txtMain, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, shadows: sh)),
          onTap: () {
            if (isFromDrawer) Navigator.of(context).pop(); // đóng Drawer trượt (Mobile) trước khi đổi tab
            setState(() => _selectedIndex = kAdminIndex);
          },
        ),
      ),
    );
  }

  Widget _buildBottomNav(Color surface, Color txtSub) {
    final t = AppTranslations.of(context);
    return BottomNavigationBar(
      backgroundColor: surface, selectedItemColor: tkGreen, unselectedItemColor: txtSub, type: BottomNavigationBarType.fixed,
      // [FIX CRASH] BottomNav chỉ có 5 item (0-4); các tab nhúng ngoài dải (5 Quản lý Nhà,
      // 6 Phân quyền, 7 Quản trị) sẽ vượt currentIndex -> assert. Kẹp về 0 để an toàn.
      currentIndex: _selectedIndex < 5 ? _selectedIndex : 0, onTap: (index) => _onMenuTapped(index),
      // [ĐA NGÔN NGỮ] items KHÔNG còn const — label giờ đọc runtime qua AppTranslations.
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.dashboard_rounded), label: t.text('dashboard_short')),
        BottomNavigationBarItem(icon: const Icon(Icons.meeting_room_rounded), label: t.text('rooms')),
        BottomNavigationBarItem(icon: const Icon(Icons.auto_awesome), label: t.text('routines')),
        BottomNavigationBarItem(icon: const Icon(Icons.notifications_active_rounded), label: t.text('notifications')),
        BottomNavigationBarItem(icon: const Icon(Icons.settings_rounded), label: t.text('settings')),
      ],
    );
  }

  Widget _buildBentoDashboard(bool isDark, Color textMain, Color textSub) {
    final t = AppTranslations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [DEBUG ROLE] Hiện role ngay cạnh tên để kiểm chứng App nhận diện quyền gì
                // (vd: 'Xin chào, tinhkt.ipca (SUPER_USER)'). Role lấy nguyên văn từ JWT.
                // KHÔNG dùng Flexible/Expanded ở đây: Row này nằm trong ngữ cảnh chiều rộng
                // vô hạn (Column trong Row) -> Flexible sẽ vỡ layout ("never laid out").
                // [GIỮ NGUYÊN BIẾN ĐỘNG] userEmail/$userRole đọc thẳng từ JWT — KHÔNG dịch.
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${t.text('hello')}, ', style: TextStyle(color: textSub, fontSize: 16)),
                  Text(userEmail.split('@')[0], style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(' ($userRole)', style: TextStyle(color: _isSuperUser ? tkGreen : textSub, fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
                Text(t.text('system_overview'), style: TextStyle(color: textMain, fontSize: 28, fontWeight: FontWeight.w900)),
              ],
            ),
            Row(children: [_buildNotificationBell(textMain, textSub), const SizedBox(width: 16), _buildUserAvatarMenu(textMain)])
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(flex: 4, child: _buildWeatherBento(isDark, textMain, textSub)),
            const SizedBox(width: 24),
            Expanded(flex: 6, child: _buildSensorsBento(isDark, textMain, textSub)),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: AppContainer(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (userRole == 'SUPER_USER' && _selectedHomeForSuperUser != null)
                            Expanded(
                              child: Row(
                                children: [
                                  IconButton(icon: Icon(Icons.arrow_back_rounded, color: textMain), onPressed: () { setState(() => _selectedHomeForSuperUser = null); _initializeHome(); }),
                                  Expanded(child: Text('${t.text('all_devices')} - ${_selectedHomeForSuperUser!['home_name']}', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            )
                          else
                            Text(t.text('all_devices'), style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
                          
                          if (userRole != 'SUPER_USER' || _selectedHomeForSuperUser != null) 
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: tkGreen.withValues(alpha: 0.15), foregroundColor: tkGreen, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                              icon: const Icon(Icons.add, size: 20), label: Text(t.text('add_device'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              onPressed: () async {
                                // [FIX] Bắt lấy mã MAC dialog trả về rồi GỌI API LINK THẬT
                                // (kèm SnackBar báo thành công/lỗi chi tiết) — trước đây kết quả bị vứt bỏ
                                final result = await showAppDialog(context: context, contentPadding: const EdgeInsets.all(8), child: AddDeviceDialog(ownedMacs: _ownedMacs));
                                await _linkScannedDevice(result);
                                _handleRefresh();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // [PHÒNG] Thanh chọn phòng ngang — đồng bộ PC/Tablet như Mobile
                              _buildRoomTabs(),
                              const SizedBox(height: 20),
                              _buildDevicesGrid(isDark, textMain, textSub),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(children: [_buildEnergyWidget(isDark, textMain, textSub), const SizedBox(height: 24), _buildCameraWidget(isDark, textMain, textSub)]),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileContent(bool isDark, Color surfaceLight, Color textMain, Color textSub) {
    final t = AppTranslations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeatherBento(isDark, textMain, textSub),
          const SizedBox(height: 16),
          
          // ĐOẠN ĐƯỢC CẬP NHẬT ĐỂ TÍNH TOÁN KÍCH THƯỚC CHUẨN 3 CỘT
          Builder(
            builder: (context) {
              // Chiều rộng màn hình - 32px (padding 2 bên) - 24px (2 khoảng trống 12px giữa 3 thẻ đầu) = chiều rộng chia 3
              double screenWidth = MediaQuery.of(context).size.width;
              double itemWidth = (screenWidth - 56) / 3;

              return SizedBox(
                height: 130,
                child: ListView(
                  scrollDirection: Axis.horizontal, 
                  physics: const BouncingScrollPhysics(), 
                  clipBehavior: Clip.none,
                  children: [
                    // [GIỮ NGUYÊN BIẾN ĐỘNG] '${_weatherData['temp']}°C'/'%' đọc thẳng từ API thời
                    // tiết — CHỈ nhãn (Nhiệt độ/Độ ẩm/Tiêu thụ/An ninh) và 'BẬT' được dịch.
                    _buildMiniStatusMobile(Icons.thermostat, t.text('temperature'), '${_weatherData['temp'] ?? '--'}°C', Colors.orange, textMain, textSub, itemWidth),
                    const SizedBox(width: 12),
                    _buildMiniStatusMobile(Icons.water_drop, t.text('humidity'), '${_weatherData['humidity'] ?? '--'}%', Colors.blue, textMain, textSub, itemWidth),
                    const SizedBox(width: 12),
                    _buildMiniStatusMobile(Icons.bolt, t.text('power_load'), '2.1 kW', tkGreen, textMain, textSub, itemWidth),
                    const SizedBox(width: 12),
                    _buildMiniStatusMobile(Icons.security, t.text('security'), t.text('on_state'), Colors.redAccent, textMain, textSub, itemWidth),
                  ],
                ),
              );
            }
          ),
          
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (userRole == 'SUPER_USER' && _selectedHomeForSuperUser != null)
                Expanded(
                  child: Row(
                    children: [
                      IconButton(icon: Icon(Icons.arrow_back_rounded, color: textMain), onPressed: () { setState(() => _selectedHomeForSuperUser = null); _initializeHome(); }),
                      Expanded(child: Text('Thiết bị - ${_selectedHomeForSuperUser!['home_name']}', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                )
              else
                Text(t.text('all_devices'), style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          // [PHÒNG] Thanh điều hướng phòng ngang (ngay trên lưới thiết bị)
          _buildRoomTabs(),
          const SizedBox(height: 16),
          _buildDevicesGrid(isDark, textMain, textSub),
          const SizedBox(height: 24),
          _buildEnergyWidget(isDark, textMain, textSub),
          const SizedBox(height: 16),
          _buildCameraWidget(isDark, textMain, textSub),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // CẬP NHẬT THÊM HÀM NÀY ĐỂ NHẬN CHIỀU RỘNG TỪ BÊN TRÊN
  Widget _buildMiniStatusMobile(IconData icon, String title, String value, Color color, Color txtMain, Color txtSub, double cardWidth) {
    return AppContainer(
      width: cardWidth, 
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, 
        mainAxisAlignment: MainAxisAlignment.center, 
        children: [
          Icon(icon, color: color, size: 26), 
          const SizedBox(height: 10), 
          
          // ĐÃ BỌC FITTEDBOX CHO TITLE ĐỂ CHỐNG TRÀN RENDERFLEX
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title, 
              style: TextStyle(color: txtSub, fontSize: 11, fontWeight: FontWeight.w600), 
            ),
          ),
          
          const SizedBox(height: 6), 
          FittedBox(
            fit: BoxFit.scaleDown, 
            child: Text(
              value, 
              style: TextStyle(color: txtMain, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          )
        ]
      )
    );
  }

  /// [ICON THỜI TIẾT ĐỘNG] [condition] = nhóm CHUẨN HÓA OpenWeatherMap (weather[0].main —
  /// "Clear"/"Clouds"/"Rain"/"Drizzle"/"Thunderstorm"/"Snow"/"Mist"/"Fog"/"Haze"), KHÔNG PHẢI
  /// câu mô tả tiếng Việt tự do. File .json THẬT chưa có sẵn trong assets/weather/ (xem README
  /// trong thư mục đó) — errorBuilder rơi về Icon tĩnh an toàn, không crash khi thiếu file.
  Widget _getWeatherIcon(String condition, {double size = 40}) {
    final String asset = switch (condition) {
      'Clear' => 'assets/weather/clear.json',
      'Clouds' => 'assets/weather/clouds.json',
      'Rain' || 'Drizzle' => 'assets/weather/rain.json',
      'Thunderstorm' => 'assets/weather/storm.json',
      'Snow' => 'assets/weather/snow.json',
      'Mist' || 'Fog' || 'Haze' => 'assets/weather/mist.json',
      _ => 'assets/weather/clouds.json',
    };
    final IconData fallbackIcon = switch (condition) {
      'Clear' => Icons.wb_sunny_rounded,
      'Rain' || 'Drizzle' => Icons.water_drop_rounded,
      'Thunderstorm' => Icons.thunderstorm_rounded,
      'Snow' => Icons.ac_unit_rounded,
      'Mist' || 'Fog' || 'Haze' => Icons.foggy,
      _ => Icons.cloud_queue_rounded,
    };
    return Lottie.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(fallbackIcon, color: tkGreen, size: size),
    );
  }

  /// Ánh xạ nhóm chuẩn hóa -> nhãn dịch được. null = nhóm lạ/rỗng (Backend chưa trả dữ liệu,
  /// hoặc phiên bản OpenWeatherMap thêm nhóm mới chưa map) -> nơi gọi tự rơi về [condition] gốc.
  String? _weatherConditionLabel(AppTranslations t, String main) {
    switch (main) {
      case 'Clear':
        return t.text('weather_clear');
      case 'Clouds':
        return t.text('weather_clouds');
      case 'Rain':
      case 'Drizzle':
        return t.text('weather_rain');
      case 'Thunderstorm':
        return t.text('weather_thunderstorm');
      case 'Snow':
        return t.text('weather_snow');
      case 'Mist':
      case 'Fog':
      case 'Haze':
        return t.text('weather_mist');
      default:
        return null;
    }
  }

  Widget _buildWeatherBento(bool isDark, Color txtMain, Color txtSub) {
    final t = AppTranslations.of(context);
    // Lấy dữ liệu từ Map, nếu chưa có thì hiển thị giá trị mặc định.
    // [GIỮ NGUYÊN BIẾN ĐỘNG] temp đọc thẳng từ API. 'condition' (câu mô tả tiếng Việt tự do từ
    // Backend) CHỈ còn dùng làm fallback cuối khi 'main' (nhóm chuẩn hóa) rỗng/lạ chưa map được
    // — bình thường nhãn hiển thị đi qua _weatherConditionLabel (dịch được cả 2 ngôn ngữ).
    final String temp = _weatherData['temp']?.toString() ?? '--';
    final String main = _weatherData['main']?.toString() ?? '';
    final String condition = _weatherConditionLabel(t, main) ?? (_weatherData['condition']?.toString() ?? t.text('updating'));

    return AppContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [ĐỊA DANH GPS] Thay cho nút làm mới vị trí thủ công đợt trước — hiển thị thẳng tên
          // khu vực hiện tại (dịch ngược từ tọa độ GPS, xem _determinePosition). Style tinh tế:
          // nhỏ + mờ hơn hẳn nhiệt độ chính, không tranh giành sự chú ý. BẮT BUỘC Expanded +
          // ellipsis vì đang nằm trong Row — tên dài (vd "Thành phố Hồ Chí Minh") không vỡ layout.
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 12, color: txtSub.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _locationName, // [GIỮ NGUYÊN BIẾN ĐỘNG] tên khu vực thật từ GPS/API — không dịch
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: txtSub.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: _getWeatherIcon(main, size: 36),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      condition,
                      style: TextStyle(color: txtSub, fontSize: 13, fontWeight: FontWeight.w600)
                    ),
                    Text(
                      '$temp°C', // Hiển thị nhiệt độ từ API
                      style: TextStyle(color: txtMain, fontSize: 28, fontWeight: FontWeight.w900)
                    )
                  ]
                )
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsBento(bool isDark, Color txtMain, Color txtSub) {
    final t = AppTranslations.of(context);
    return AppContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      // [GIỮ NGUYÊN BIẾN ĐỘNG] '${_weatherData['humidity']}%' đọc thẳng từ API — chỉ nhãn dịch.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildMiniStatusDesktop(Icons.water_drop, t.text('humidity'), '${_weatherData['humidity'] ?? '--'}%', Colors.blue, txtMain, txtSub), Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          _buildMiniStatusDesktop(Icons.bolt, t.text('power_load'), '2.1 kW', tkGreen, txtMain, txtSub), Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          _buildMiniStatusDesktop(Icons.security, t.text('security'), t.text('on_state'), Colors.redAccent, txtMain, txtSub),
        ],
      ),
    );
  }

  Widget _buildEnergyWidget(bool isDark, Color textMain, Color textSub) {
    final t = AppTranslations.of(context);
    // [GIỮ NGUYÊN BIẾN ĐỘNG] '14.5'/'kWh'/'2,104 W'/'124 kWh' là số liệu điện năng (mock chờ
    // tích hợp thật) — CHỈ nhãn (Điện năng/Hôm nay/Đang tiêu thụ/Tháng này) được dịch.
    return AppContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [Icon(Icons.bolt_rounded, color: tkGreen, size: 22), const SizedBox(width: 8), Text(t.text('energy'), style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))]),
              IconButton(icon: Icon(Icons.open_in_new_rounded, color: textSub, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () {})
            ],
          ),
          const SizedBox(height: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(t.text('today'), style: TextStyle(color: textSub, fontSize: 13)), const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text('14.5', style: TextStyle(color: textMain, fontSize: 40, fontWeight: FontWeight.w900)), const SizedBox(width: 4), Text('kWh', style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 16), Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1), const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(child: Column(children: [Text(t.text('consuming'), style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), FittedBox(fit: BoxFit.scaleDown, child: Text('2,104 W', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)))])),
                  Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  Expanded(child: Column(children: [Text(t.text('this_month'), style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), FittedBox(fit: BoxFit.scaleDown, child: Text('124 kWh', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)))])),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCameraWidget(bool isDark, Color textMain, Color textSub) {
    final t = AppTranslations.of(context);
    return AppContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8,
            children: [
              Row(children: [const Icon(Icons.videocam_rounded, color: Colors.blueAccent, size: 22), const SizedBox(width: 8), Text(t.text('camera'), style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 28, decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(onTap: () => setState(() => _cameraViewMode = 1), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: _cameraViewMode == 1 ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(6)), child: Center(child: Icon(Icons.crop_din_rounded, size: 16, color: _cameraViewMode == 1 ? Colors.white : textSub)))),
                        InkWell(onTap: () => setState(() => _cameraViewMode = 4), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: _cameraViewMode == 4 ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(6)), child: Center(child: Icon(Icons.grid_view_rounded, size: 16, color: _cameraViewMode == 4 ? Colors.white : textSub))))
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(icon: Icon(Icons.open_in_new_rounded, color: textSub, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () {})
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          _cameraViewMode == 1 
            ? AspectRatio(aspectRatio: 16 / 9, child: Container(decoration: BoxDecoration(color: isDark ? Colors.black45 : Colors.grey.shade300, borderRadius: BorderRadius.circular(12)), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam_off_rounded, color: textSub, size: 32), const SizedBox(height: 8), Text(t.text('offline'), style: TextStyle(color: textSub, fontSize: 12))]))))
            : GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 4 / 3), itemCount: 4, itemBuilder: (context, index) { return Container(decoration: BoxDecoration(color: isDark ? Colors.black45 : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)), child: Center(child: Icon(Icons.videocam_off_rounded, color: textSub))); })
        ],
      ),
    );
  }

  Widget _buildMiniStatusDesktop(IconData icon, String label, String val, Color color, Color txtMain, Color txtSub) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(color: txtSub, fontSize: 13))]), const SizedBox(height: 8), Text(val, style: TextStyle(color: txtMain, fontSize: 18, fontWeight: FontWeight.bold))]);
  }


  // ==========================================================================
  // THUẬT TOÁN PHÂN LẬP RÕ RÀNG QUẠT VÀ CÔNG TẮC - AUTO DISCOVERY
  // ==========================================================================
  // [PHÒNG] Thanh điều hướng phòng NGANG — "Tất cả" + các phòng + nút Quản lý.
  Widget _buildRoomTabs() {
    return Consumer<RoomGroupProvider>(
      builder: (context, roomProv, _) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
        final Color chipBg = isDark ? const Color(0xFF1E293B) : Colors.white;
        final sel = roomProv.selectedRoomId;
        final t = AppTranslations.of(context);
        // [ĐỢT 16 — TRẢ LẠI KÍNH 3D] Đợt 15 đổi sang AppCard khiến Glass Theme BẬT vô tình bị
        // "kính hóa" luôn thẻ phòng (trước đó vốn LUÔN phẳng bất kể theme) — không đúng ý định.
        // Tự tay rẽ nhánh: Kính 3D (Sáng/Tối) = Y HỆT bản gốc (Material phẳng, không viền/
        // bóng); CHỈ Thường (Sáng/Tối) mới có viền+bóng nổi khối (giữ nguyên hiệu quả Đợt 15).
        final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;

        Widget chip({required String label, IconData? icon, required bool active, required VoidCallback onTap}) {
          final Color bg = active ? tkGreen : chipBg;
          final Widget content = Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 16, color: active ? Colors.white : textSub), const SizedBox(width: 6)],
              Text(label, style: TextStyle(color: active ? Colors.white : textSub, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          );
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: isGlass
                ? Material(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: content),
                  )
                : Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.2), width: 1),
                      boxShadow: [
                        isDark
                            ? BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))
                            : BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: content),
                    ),
                  ),
          );
        }

        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              // [GIỮ NGUYÊN BIẾN ĐỘNG] r.name (tên phòng) đọc từ API/RoomGroupProvider — không dịch.
              chip(label: t.text('all'), icon: Icons.widgets_rounded, active: sel == null, onTap: () => roomProv.selectRoom(null)),
              ...roomProv.rooms.map((r) => chip(label: r.name, icon: Icons.meeting_room, active: sel == r.id, onTap: () => roomProv.selectRoom(r.id))),
              // Nút Quản lý phòng
              isGlass
                  ? Material(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomManagementScreen())),
                        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Icon(Icons.settings, size: 18, color: textSub)),
                      ),
                    )
                  : Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.2), width: 1),
                        boxShadow: [
                          isDark
                              ? BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))
                              : BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomManagementScreen())),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), child: Icon(Icons.settings, size: 18, color: textSub)),
                        ),
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }

  // [PHÒNG] Thẻ Công tắc tổng của phòng — chạm để bật/tắt TOÀN BỘ thiết bị trong phòng.
  Widget _buildRoomMasterCard(bool isDark, String roomId, String roomName) {
    final bool on = context.watch<RoomGroupProvider>().roomOn(roomId);
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    // [GLASS THEME] Material+InkWell+Padding thủ công cũ ĐÃ THAY bằng AppCard — cùng tham số
    // color/borderRadius/padding/onTap 1:1 nên hành vi TẮT Glass Theme y hệt trước (Material
    // solid + InkWell ripple); BẬT Glass Theme tự lên khối kính nén sáng khi chạm.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        color: on ? tkGreen : (isDark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: BorderRadius.circular(18),
        onTap: () => _toggleRoom(roomId),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(children: [
          // [GIỮ NGUYÊN] Badge tròn (shape: BoxShape.circle) — KHÔNG đổi sang AppContainer:
          // (1) AppContainer không hỗ trợ shape tròn, (2) badge này nằm LỒNG trong AppCard —
          // đổi sẽ tạo 2 lớp BackdropFilter chồng trực tiếp, vi phạm quy tắc hiệu năng Phần 4.
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: (on ? Colors.white : tkGreen).withValues(alpha: on ? 0.2 : 0.12), shape: BoxShape.circle), child: AppIcon(Icons.settings_power_rounded, color: on ? Colors.white : tkGreen, size: 26)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Công tắc tổng — $roomName', style: TextStyle(color: on ? Colors.white : textMain, fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(on ? 'Đang BẬT toàn phòng' : 'Chạm để bật/tắt tất cả', style: TextStyle(color: on ? Colors.white70 : (isDark ? Colors.white54 : Colors.black54), fontSize: 12)),
          ])),
          AppIcon(on ? Icons.toggle_on : Icons.toggle_off, color: on ? Colors.white : Colors.grey, size: 40),
        ]),
      ),
    );
  }

  // [PHÒNG] Bật/tắt cả phòng: cập nhật state mock + fan-out lệnh thật xuống từng thiết bị.
  void _toggleRoom(String roomId) {
    final roomProv = Provider.of<RoomGroupProvider>(context, listen: false);
    final deviceProv = Provider.of<DeviceProvider>(context, listen: false);
    final bool turnOn = !roomProv.roomOn(roomId);
    roomProv.toggleRoom(roomId, turnOn);
    // toggleDevice gửi NGƯỢC currentState -> truyền !turnOn để ép về ON/OFF mong muốn.
    // endpoint 'all': SSW04 bật/tắt cả 4 kênh; firmware 1 kênh/quạt bỏ qua endpoint, chỉ đọc value.
    for (final mac in roomProv.devicesInRoom(roomId)) {
      deviceProv.toggleDevice(mac, 'all', !turnOn);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(turnOn ? 'Đã bật tất cả thiết bị trong phòng' : 'Đã tắt tất cả thiết bị trong phòng'), backgroundColor: tkGreen));
  }

  Widget _buildDevicesGrid(bool isDark, Color textMain, Color textSub) {
    if (_isLoadingDevices) return Center(child: Padding(padding: const EdgeInsets.all(40), child: CircularProgressIndicator(color: tkGreen)));

    // listen: true — mỗi notifyListeners() từ DeviceProvider (sóng MQTT đổ vào kho DPS)
    // sẽ tự kích hoạt vẽ lại lưới này NGAY LẬP TỨC, không cần kéo lại HTTP API.
    final provider = Provider.of<DeviceProvider>(context);

    // [PHÒNG] Phòng đang chọn (null = Tất cả) — dùng để LỌC thiết bị + chèn Công tắc tổng.
    final roomProv = context.watch<RoomGroupProvider>();
    final String? selRoom = roomProv.selectedRoomId;

    // VIEW 1: SUPER USER (HIỂN THỊ THẺ NHÀ) - Giữ nguyên của bác
    // [ĐỢT 21] Thẻ Nhà nằm trong ClipRRect+BackdropFilter riêng (như SmartSwitchCard) nên border/
    // shadow mới PHẢI ở một Container bọc NGOÀI ClipRRect — đặt trực tiếp vào AnimatedContainer sẽ
    // bị chính ClipRRect của nó cắt mất, xem bài học "Shadow phải nằm ngoài ClipRRect".
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    if (userRole == 'SUPER_USER' && _selectedHomeForSuperUser == null) {
      if (_allHomesForSuperUser.isEmpty) return _buildEmptyState(isDark, textSub, "Không tìm thấy ngôi nhà nào trên hệ thống.");
      return LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount; double ratio;
          if (constraints.maxWidth < 500) { crossAxisCount = 3; ratio = 1.0; } 
          else { crossAxisCount = (constraints.maxWidth / 140).floor(); if (crossAxisCount < 3) crossAxisCount = 3; ratio = 1.0; }

          return GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _allHomesForSuperUser.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: ratio),
            itemBuilder: (context, index) {
              final home = _allHomesForSuperUser[index];
              int devCount = home['total_endpoints'] ?? 0; int onCount = home['on_count'] ?? 0; bool isAnyOn = onCount > 0;
              final Color bgColor = isAnyOn ? tkGreen : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.6));
              final Color textColor = isAnyOn ? Colors.white : (isDark ? Colors.white : Colors.black87);
              
              // [ĐỢT 21] Viền+bóng đổ CHỈ áp cho Thẻ Nhà CHƯA bật thiết bị nào (chưa "xanh lá") ở
              // Sáng Thường (!isDark && !isGlass) — không đụng thẻ đang isAnyOn (xanh lá) hay Kính.
              final BoxDecoration outerHomeCardDecoration = (!isAnyOn && !isDark && !isGlass)
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    )
                  : BoxDecoration(borderRadius: BorderRadius.circular(16));

              return Container(
                decoration: outerHomeCardDecoration,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: isAnyOn ? tkGreen : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white), width: 1.5)),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () { setState(() => _selectedHomeForSuperUser = home); _initializeHome(); },
                          child: Stack(
                            children: [
                              Positioned(top: 10, left: 10, child: Icon(Icons.maps_home_work_outlined, color: isAnyOn ? Colors.white : tkGreen, size: 18)),
                              Positioned(top: 2, right: 2, child: IconButton(icon: Icon(Icons.power_settings_new_rounded, color: isAnyOn ? Colors.white : (isDark ? Colors.white24 : Colors.grey.shade400), size: 24), onPressed: () => _bulkToggleHome(home, !isAnyOn))),
                              Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.only(bottom: 14.0, top: 10.0), child: Text('$onCount / $devCount', style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 18, fontWeight: FontWeight.bold)))),
                              Positioned(bottom: 8, left: 6, right: 6, child: Text(home['home_name'] ?? 'Home', textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }
      );
    }

    // ==========================================================================
    // VIEW 2: TẤT CẢ THIẾT BỊ — NGUỒN SỰ THẬT: KHO DPS CỦA DeviceProvider
    // REST chỉ cung cấp DANH SÁCH thiết bị + ảnh trạng thái ban đầu; trạng thái
    // sống (realtime) luôn được ƯU TIÊN lấy từ provider.devices (sóng MQTT).
    // ==========================================================================
    if (_currentHomeDevices.isEmpty) return _buildEmptyState(isDark, textSub, "Khu vực này chưa kết nối với thiết bị/Hub nào.");

    // Chụp kho thiết bị sống MỘT LẦN cho cả lượt vẽ này
    final liveDevices = provider.devices;

    // QUY TẮC ĐẶT TÊN TỰ ĐỘNG (khớp từng ký tự với bộ dịch ở Backend Go, dùng khi
    // thiết bị chưa được đặt tên trong database):
    //   1 cổng: "sw-{4 cuối MAC}" | đa kênh: "sw-{4 cuối}-N" | nút tổng ảo: "sw-tog-{4 cuối}"
    String last4Of(String mac) =>
        (mac.length > 4 ? mac.substring(mac.length - 4) : mac).toLowerCase();

    String translateName(String mac, String key, {required bool isMulti}) {
      final last4 = last4Of(mac);
      final k = key.toLowerCase();
      // Kênh vật lý lẻ: S_{MAC}_N, relayN, powerN, hay số trần đều moi ra chỉ số cuối
      // (nút tổng ảo "sw-tog" đã bị TRIỆT TIÊU hoàn toàn — không còn được đặt tên/tạo thẻ)
      final m = RegExp(r'(\d+)$').firstMatch(k);
      if (isMulti && m != null) return 'sw-$last4-${m.group(1)}';
      return 'sw-$last4';
    }

    // Moi số kênh ở CUỐI khóa endpoint: "S_ABCD_2" -> 2, "power3" -> 3, "2" -> 2 (null nếu không có)
    int? channelOf(String key) {
      final m = RegExp(r'(\d+)$').firstMatch(key);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    // Khóa master (nút tổng) — dùng để xếp nút tổng đứng trước các kênh lẻ trong lưới
    bool isMasterKey(String key) {
      final k = key.toLowerCase();
      return k == 'all' || RegExp(r'^s_[0-9a-f]{12}$').hasMatch(k);
    }

    final ignoredKeys = ['ip', 'mac', 'rssi', 'signal', 'wifi', 'serial', 'version', 'fw', 'firmware', 'update', 'reset', 'restart', 'online', 'timestamp', 'time', 'led', 'config', 'status', 'ping', 'type', 'id'];

    final List<Map<String, dynamic>> allFans = [];
    final List<Map<String, dynamic>> allSwitches = [];
    final List<Map<String, dynamic>> allSensors = [];
    // [DIGITAL TWIN — Đợt 23] 3 thẻ siêu cấp + lưới an toàn cho category chính chủ còn lại
    final List<Map<String, dynamic>> allRollingDoors = [];
    final List<Map<String, dynamic>> allPumps = [];
    final List<Map<String, dynamic>> allDimmers = [];
    final List<Map<String, dynamic>> allGenericPrimary = [];

    // ==========================================================================
    // BÓC TÁCH THÔNG MINH: REST làm nền, DPS realtime đè lên trên
    // ==========================================================================
    for (var device in _currentHomeDevices) {
      String mac = (device['mac_address'] ?? device['mac'] ?? 'UNKNOWN').toString().replaceAll(':', '').toUpperCase();
      // [PHÒNG] Đang xem 1 phòng cụ thể -> chỉ giữ thiết bị thuộc phòng đó.
      if (selRoom != null && roomProv.roomOf(mac) != selRoom) continue;
      String deviceName = device['name'] ?? device['home_name'] ?? 'Thiết bị $mac';

      // ---------- LỚP 1: ẢNH TRẠNG THÁI BAN ĐẦU TỪ REST ----------
      var rawState = device['state'] ?? device['state_data'] ?? device['properties'];
      Map<String, dynamic> stateMap = {};
      if (rawState is String) {
        String s = rawState.trim();
        if (s.startsWith('{')) { try { stateMap = Map<String, dynamic>.from(jsonDecode(s)); } catch (_) {} }
        else { stateMap = {'state': s}; }
      } else if (rawState is Map) {
        stateMap = Map<String, dynamic>.from(rawState);
      }

      // TRẢI PHẲNG JSON: bóc được cả dạng lồng {"switch":{"power1":"ON"}} lẫn map endpoint mới
      final Map<String, String> endpointStates = {};
      final Map<String, String> endpointNames = {};
      final Map<String, String> endpointTypes = {};  // "fan" | "switch" | "sensor" do Backend gắn
      final Map<String, int> endpointSpeeds = {};    // tốc độ quạt đi kèm endpoint
      final Map<String, bool> endpointSwings = {};   // trạng thái đảo gió (túp năng)
      final Map<String, String> endpointTemps = {};  // nhiệt độ (°C) của endpoint cảm biến
      final Map<String, String> endpointHums = {};   // độ ẩm (%) của endpoint cảm biến
      void flatten(Map m) {
        m.forEach((k, v) {
          if (v is Map) {
            // Object mô tả endpoint: có state/value (công tắc, quạt) HOẶC có số đo
            // (cảm biến DHT11 chỉ gửi temperature/humidity, KHÔNG có khóa state)
            final bool isEndpointObj = v.containsKey('state') || v.containsKey('value') ||
                v.containsKey('temperature') || v.containsKey('humidity');
            if (isEndpointObj) {
              if (v.containsKey('state') || v.containsKey('value')) {
                String s = (v['state'] ?? v['value']).toString().toUpperCase();
                if (['ON', 'OFF', 'TRUE', 'FALSE', '1', '0'].contains(s)) {
                  endpointStates[k.toString()] = ['ON', 'TRUE', '1'].contains(s) ? 'ON' : 'OFF';
                }
              }
              if (v['name'] != null) endpointNames[k.toString()] = v['name'].toString();
              if (v['type'] != null) endpointTypes[k.toString()] = v['type'].toString();
              final spd = v['speed'] ?? v['fan_speed'];
              if (spd != null) endpointSpeeds[k.toString()] = int.tryParse(spd.toString()) ?? 0;
              if (v.containsKey('swing') || v.containsKey('oscillate')) {
                endpointSwings[k.toString()] = v['swing'] == true || v['oscillate'] == true;
              }
              if (v['temperature'] != null) endpointTemps[k.toString()] = v['temperature'].toString();
              if (v['humidity'] != null) endpointHums[k.toString()] = v['humidity'].toString();
            } else {
              flatten(v);
            }
          } else {
            String s = v.toString().toUpperCase();
            if (['ON', 'OFF', 'TRUE', 'FALSE', '1', '0'].contains(s)) {
              endpointStates[k.toString()] = ['ON', 'TRUE', '1'].contains(s) ? 'ON' : 'OFF';
            }
          }
        });
      }
      flatten(stateMap);

      // ---------- LỚP 2: ĐÈ TRẠNG THÁI SỐNG TỪ KHO DPS (ƯU TIÊN TUYỆT ĐỐI) ----------
      final live = liveDevices[mac];
      if (live != null) {
        for (final id in live.endpointIds) {
          final s = live.dps[id]?.toString().toUpperCase();
          if (s != null && (s == 'ON' || s == 'OFF')) endpointStates[id] = s;
          final n = live.nameOf(id);
          if (n != null) endpointNames[id] = n;
          final t = live.typeOf(id);
          if (t != null) endpointTypes[id] = t;
          if (live.dps.containsKey('${id}_speed')) endpointSpeeds[id] = live.speedOf(id);
          if (live.dps.containsKey('${id}_swing')) endpointSwings[id] = live.isSwinging(id);
        }
        // Endpoint cảm biến không có dps trần (không state) nên không lọt vào endpointIds
        // — quét thẳng các khóa số đo/tên/loại để sóng MQTT realtime đè lên ảnh REST
        live.dps.forEach((k, v) {
          if (k.endsWith('_temperature')) endpointTemps[k.substring(0, k.length - 12)] = v.toString();
          if (k.endsWith('_humidity')) endpointHums[k.substring(0, k.length - 9)] = v.toString();
          if (k.endsWith('_name')) endpointNames.putIfAbsent(k.substring(0, k.length - 5), () => v.toString());
          if (k.endsWith('_type')) endpointTypes.putIfAbsent(k.substring(0, k.length - 5), () => v.toString());
        });
      }

      // ---------- TRẠNG THÁI KẾT NỐI (LWT): sóng availability sống thắng ảnh REST ----------
      final bool deviceOnline = live?.online ??
          ((device['status']?.toString().toLowerCase() ?? '') == 'online');

      // ---------- CATEGORY CHÍNH CHỦ (nguồn: Backend Schema-Driven UI) ----------
      // Ưu tiên tuyệt đối trường category do Backend gắn; chỉ khi trống mới đoán
      // heuristic bên dưới. Đây là "chìa khóa" của cổng loại trừ endpoint tích hợp.
      String deviceCategory = (device['category'] ?? '').toString().toLowerCase();

      // ---------- NHẬN DIỆN CẢM BIẾN (DHT11...) ----------
      // Nhận diện qua 3 dấu hiệu: type "sensor" Backend gắn cho endpoint, endpoint có
      // số đo (temperature/humidity), hoặc dòng firmware/category thiết bị tự khai.
      // Cảm biến lên thẻ SmartSensorCard riêng — KHÔNG nứt thẻ công tắc chờ vô nghĩa.
      final sensorEndpoints = <String>{
        ...endpointTypes.entries.where((e) => e.value == 'sensor').map((e) => e.key),
        ...endpointTemps.keys,
        ...endpointHums.keys,
      };
      final bool isSensorDevice = sensorEndpoints.isNotEmpty ||
          (device['fw_type'] ?? '').toString().toUpperCase().contains('SENSOR') ||
          (device['category'] ?? '').toString().toLowerCase() == 'sensor';
      if (isSensorDevice) {
        // Chưa có gói số đo nào (vừa cắm điện): vẫn dựng thẻ chờ với endpoint chuẩn SENS_{mac}
        final ids = sensorEndpoints.isNotEmpty ? sensorEndpoints : {'SENS_$mac'};
        for (final id in ids) {
          allSensors.add({
            'mac': mac,
            'endpoint': id,
            'name': endpointNames[id] ?? 'Sensor-${last4Of(mac)}',
            'temp': endpointTemps[id],
            'hum': endpointHums[id],
            'online': deviceOnline,
            'rawDevice': device,
          });
        }
        continue; // cảm biến không có relay — dừng tại đây
      }

      // ---------- NHẬN DIỆN QUẠT ----------
      final lowerKeys = endpointStates.keys.map((e) => e.toLowerCase()).toList();
      // Endpoint dạng quạt: F1/F2 trên Hub V38, endpoint được Backend gắn type "fan"
      // (Fan_Control đi qua bridge), hoặc endpoint có chỉ số tốc độ đi kèm
      final fanEndpoints = endpointStates.keys.where((k) =>
          RegExp(r'^[Ff]\d+$').hasMatch(k) ||
          endpointTypes[k] == 'fan' ||
          endpointSpeeds.containsKey(k)).toSet();

      if (fanEndpoints.isNotEmpty) {
        // Mỗi endpoint dạng quạt -> đúng MỘT thẻ SmartFanCard tích hợp (icon cánh quạt
        // quay theo tốc độ thật); speed/swing đã được đè lớp sống từ dps ở trên.
        for (final f in fanEndpoints) {
          allFans.add({
            'mac': mac,
            'endpoint': f,
            'speed': endpointSpeeds[f] ?? (endpointStates[f] == 'ON' ? 1 : 0),
            'swing': endpointSwings[f] ?? false,
            'name': endpointNames[f] ?? 'Fan-${last4Of(mac)}',
            'online': deviceOnline,
            'rawDevice': device,
          });
        }
        if (deviceCategory.isEmpty) deviceCategory = 'fan'; // Backend chưa gắn -> tự suy
      } else {
        // Không có endpoint gắn type quạt -> đoán theo tên/khóa cũ (Fan_Control đời đầu
        // chưa qua bridge): GOM 3 relay tốc độ + relay đảo gió thành MỘT thẻ duy nhất
        final bool isLegacyFanBox =
            deviceName.toLowerCase().contains('quạt') || deviceName.toLowerCase().contains('fan') ||
            lowerKeys.contains('sw') || lowerKeys.contains('swing') || lowerKeys.contains('tupnang') ||
            lowerKeys.any((e) => e.contains('speed')) ||
            (lowerKeys.contains('1') && lowerKeys.contains('2') && lowerKeys.contains('3'));
        if (isLegacyFanBox) {
          int speed = 0;
          bool swing = false;
          bool isOnWhere(bool Function(String lk, int? ch) test) => endpointStates.entries.any((e) {
            final lk = e.key.toLowerCase();
            return e.value == 'ON' && test(lk, channelOf(lk));
          });
          if (isOnWhere((lk, ch) => ch == 3 || lk == 'speed3')) {
            speed = 3;
          } else if (isOnWhere((lk, ch) => ch == 2 || lk == 'speed2')) {
            speed = 2;
          } else if (isOnWhere((lk, ch) => ch == 1 || lk == 'speed1')) {
            speed = 1;
          } else if (isOnWhere((lk, ch) => ['power', 'power0', 'fan_power', 'state'].contains(lk))) {
            speed = 1;
          }
          if (isOnWhere((lk, ch) => ch == 4 || ['sw', 'swing', 'tupnang'].contains(lk))) swing = true;

          allFans.add({'mac': mac, 'endpoint': 'fan', 'speed': speed, 'swing': swing, 'name': 'Fan-${last4Of(mac)}', 'online': deviceOnline, 'rawDevice': device});
          if (deviceCategory.isEmpty) deviceCategory = 'fan';
        }
      }

      // ======================================================================
      // [DIGITAL TWIN — Đợt 23] NHẬN DIỆN CỬA CUỐN / BƠM / ĐÈN CHIẾT ÁP
      // ======================================================================
      // pickPrimaryEndpoint: chọn 1 relay điều khiển chính cho thiết bị 1-cổng (bơm/đèn/lưới an
      // toàn) — cùng bộ lọc ignoredKeys/isMasterKey đã dùng cho công tắc thường, KHÔNG có khái
      // niệm đa kênh vì category này firmware chỉ khai đúng 1 relay hữu ích.
      String? pickPrimaryEndpoint() {
        for (final k in endpointStates.keys) {
          if (isMasterKey(k)) continue;
          final kl = k.toLowerCase();
          if (ignoredKeys.any((w) => kl == w || kl.contains(w))) continue;
          return k;
        }
        return null;
      }

      if (deviceCategory == 'curtain') {
        // Quy ước kênh KHỚP firmware SW_rolling_doors.ino: channel 1=UP, 2=DOWN, 3=STOP.
        String? upEp, downEp, stopEp;
        for (final k in endpointStates.keys) {
          final ch = channelOf(k);
          if (ch == 1) { upEp = k; }
          else if (ch == 2) { downEp = k; }
          else if (ch == 3) { stopEp = k; }
        }
        // Thiết bị chưa từng gửi state (vừa Discovery) -> vẫn dựng thẻ chờ theo endpoint chuẩn
        upEp ??= 'S_${mac}_1'; downEp ??= 'S_${mac}_2'; stopEp ??= 'S_${mac}_3';
        final Map<String, dynamic> settings = Map<String, dynamic>.from(device['settings'] ?? {});
        allRollingDoors.add({
          'mac': mac, 'upEp': upEp, 'downEp': downEp, 'stopEp': stopEp,
          'name': endpointNames[upEp] ?? deviceName,
          'online': deviceOnline, 'rawDevice': device,
          'travelSec': int.tryParse(settings['travel_time_sec']?.toString() ?? '') ?? 0,
          'positionPct': int.tryParse(settings['door_position_pct']?.toString() ?? '') ?? 0,
        });
        continue;
      }

      if (deviceCategory == 'pump') {
        final String ep = pickPrimaryEndpoint() ?? 'S_$mac';
        allPumps.add({
          'mac': mac, 'endpoint': ep,
          'state': endpointStates[ep] ?? 'OFF',
          'name': endpointNames[ep] ?? deviceName,
          'online': deviceOnline, 'rawDevice': device,
        });
        continue;
      }

      if (deviceCategory == 'light') {
        final String ep = pickPrimaryEndpoint() ?? 'S_$mac';
        allDimmers.add({
          'mac': mac, 'endpoint': ep,
          'state': endpointStates[ep] ?? 'OFF',
          'brightness': endpointSpeeds[ep] ?? 0, // "speed" tái dùng làm % độ sáng lưu cuối cùng
          'name': endpointNames[ep] ?? deviceName,
          'online': deviceOnline, 'rawDevice': device,
        });
        continue;
      }

      // ======================================================================
      // [EXCLUDE LIST] LƯỚI AN TOÀN CHO CATEGORY CHÍNH CHỦ CÒN LẠI (vd "ac"/"fridge")
      // ======================================================================
      // Trước đây các category này bị `continue` THẲNG — ÂM THẦM BIẾN MẤT khỏi Bảng điều
      // khiển vì không có thẻ chuyên biệt nào dựng cho chúng. Nay LUÔN có GenericDeviceCard
      // (ít nhất một công tắc bật/tắt) — không còn thiết bị nào "vô hình" nữa.
      // Hub ('hub') KHÔNG nằm trong primaryDeviceCategories nên vẫn chảy xuống bên dưới để
      // hiện đủ thiết bị con — KHÔNG đụng nhánh này.
      if (primaryDeviceCategories.contains(deviceCategory)) {
        final String ep = pickPrimaryEndpoint() ?? 'S_$mac';
        allGenericPrimary.add({
          'mac': mac, 'endpoint': ep, 'category': deviceCategory,
          'state': endpointStates[ep] ?? 'OFF',
          'name': endpointNames[ep] ?? deviceName,
          'online': deviceOnline, 'rawDevice': device,
        });
        continue;
      }

      // ---------- CÔNG TẮC: NỨT MỖI ENDPOINT THÀNH MỘT THẺ ĐỘC LẬP ----------
      // LỌC NỘI BỘ: chỉ giữ endpoint là RELAY THẬT, loại sạch các khóa "thông báo/
      // cấu hình" (đã lọc quạt ở trên). Không chỉ so khớp chính xác như trước mà bắt
      // cả biến thể chứa từ khóa (vd "wifi_signal", "ota_status", "config_x").
      bool isVirtualEndpoint(String key) {
        final k = key.toLowerCase();
        if (fanEndpoints.contains(key)) return true; // đã lên thẻ quạt
        // Bất kỳ khóa nào MANG một trong các từ hệ thống này đều là dữ liệu phụ, không phải relay
        for (final w in ignoredKeys) {
          if (k == w || k.contains(w)) return true;
        }
        return false;
      }
      final controllable = endpointStates.keys.where((k) => !isVirtualEndpoint(k)).toList();

      if (controllable.isEmpty) {
        if (fanEndpoints.isNotEmpty) continue; // thiết bị thuần quạt (Fan_Control qua bridge)
        // Thiết bị chưa có tín hiệu nào: dựng thẻ chờ theo quy tắc đặt tên tự động
        String dLow = deviceName.toLowerCase();
        if (dLow.contains('4b') || dLow.contains('4ch') || dLow.contains('4 nút') || dLow.contains('công tắc 4')) {
          for (var i = 1; i <= 4; i++) {
            allSwitches.add({'mac': mac, 'endpoint': 'power$i', 'state': 'OFF', 'name': 'sw-${last4Of(mac)}-$i', 'online': deviceOnline, 'rawDevice': device});
          }
          // Nút TỔNG cho thẻ chờ 4 kênh (thiết bị chưa gửi state) — vẫn bấm điều khiển được
          allSwitches.add({'mac': mac, 'endpoint': 'all', 'state': 'OFF', 'name': 'Tất cả (4 kênh)', 'online': deviceOnline, 'rawDevice': device, 'isMaster': true});
        } else {
          allSwitches.add({'mac': mac, 'endpoint': 'power1', 'state': 'OFF', 'name': 'sw-${last4Of(mac)}', 'online': deviceOnline, 'rawDevice': device});
        }
      } else {
        final bool isMulti = controllable.length > 1;

        // ====================================================================
        // [DIỆT CÔNG TẮC MA — BẢN BẤT KHẢ XÂM PHẠM] GIỮ ĐÚNG KÊNH VẬT LÝ
        // ====================================================================
        // Thiết bị đa kênh (SSW04) trả về CẢ key gốc (relay / S_{mac} / sw_{mac}) LẪN các key
        // phân kênh (relay1..4, S_{mac}_1..4, sw-{last4}-1..4). Bản cũ cố NHẬN DIỆN key gốc
        // (channelOf==null) nhưng LỌT LƯỚI khi MAC kết thúc bằng chữ số (S_9d78..00 bị hiểu
        // nhầm là "có số kênh"). Nay ĐẢO NGƯỢC: chỉ GIỮ key CÓ hậu tố kênh rõ ràng + LUÔN loại
        // nút tổng ảo (S_{mac}/all). Hậu tố kênh hợp lệ:
        //   • '..._N' hoặc '...-N'  (S_9d78_2, sw-9d78-3, power_1)
        //   • 'chữ+số' liền nhau     (relay1, power4, ch2)
        bool hasChannelSuffix(String key) {
          final k = key.toLowerCase();
          if (RegExp(r'[_-]\d+$').hasMatch(k)) return true;    // S_mac_1 / sw-1234-1 / power_2
          if (RegExp(r'^[a-z]+\d+$').hasMatch(k)) return true; // relay1 / power3 / ch2
          return false;
        }
        // Nhóm CÓ ít nhất 1 kênh đánh số -> ném bỏ mọi key gốc; nhóm toàn tên tùy biến
        // (kitchen/bedroom, không số) -> giữ nguyên để không xóa nhầm.
        final bool groupHasNumberedChannels = controllable.any(hasChannelSuffix);
        final List<String> childKeys = isMulti
            ? controllable.where((k) {
                if (isMasterKey(k)) return false; // LUÔN loại nút tổng ảo S_{mac}/all
                if (groupHasNumberedChannels && !hasChannelSuffix(k)) return false; // loại key gốc relay/sw_{mac}
                return true;
              }).toList()
            : controllable;

        // Log để soi đúng key thực tế nếu ghost còn sống (đối chiếu controllable vs childKeys)
        if (kDebugMode && isMulti) {
          debugPrint('🧹 [DIỆT MA] mac=$mac | controllable=$controllable -> childKeys=$childKeys (giữ ${childKeys.length} kênh)');
        }

        for (final key in childKeys) {
          allSwitches.add({
            'mac': mac,
            'endpoint': key,
            'state': endpointStates[key],
            'name': endpointNames[key] ?? translateName(mac, key, isMulti: isMulti),
            'online': deviceOnline,
            'rawDevice': device,
          });
        }

        // [MASTER SWITCH] Thiết bị đa kênh -> thêm MỘT nút TỔNG CHỦ ĐỘNG (endpoint "all").
        // Khác hẳn nút ma "sw-tog" bị loại ở trên: nút này khi bấm GỬI LỆNH thật tới endpoint
        // "all" — firmware SSW04 đã xử lý sẵn (bật/tắt cả 4 relay cùng lúc). Trạng thái hiển
        // thị = "sáng nếu CÓ kênh nào đang bật" (khớp cách Hass hiển thị nhóm); bấm khi đang
        // sáng -> tắt tất cả, bấm khi tắt hết -> bật tất cả.
        if (childKeys.length > 1) {
          final bool anyOn = childKeys.any((k) => endpointStates[k] == 'ON');
          allSwitches.add({
            'mac': mac,
            'endpoint': 'all',
            'state': anyOn ? 'ON' : 'OFF',
            'name': 'Tất cả (${childKeys.length} kênh)',
            'online': deviceOnline,
            'rawDevice': device,
            'isMaster': true,
          });
        }
      }
    }

    // Sắp thứ tự ổn định: theo MAC, nút tổng đứng trước, rồi đến từng kênh —
    // lưới không nhảy vị trí lung tung mỗi khi có sóng trạng thái mới đổ về
    allSwitches.sort((a, b) {
      final c = (a['mac'] as String).compareTo(b['mac'] as String);
      if (c != 0) return c;
      int rank(Map<String, dynamic> it) => isMasterKey(it['endpoint']) ? -1 : (channelOf(it['endpoint']) ?? 999);
      return rank(a).compareTo(rank(b));
    });

    final visibleSwitches = allSwitches.where((item) => !_hiddenDevices.contains("${item['mac']}_${item['endpoint']}") || _showHiddenFilter).toList();
    // Quạt và cảm biến cũng tôn trọng danh sách ẩn — trước đây thẻ quạt không lọc
    // nên nút "Ẩn khỏi Bảng điều khiển" có gọi được cũng không thấy tác dụng
    final visibleFans = allFans.where((e) => !_hiddenDevices.contains("${e['mac']}_${e['endpoint']}") || _showHiddenFilter).toList();
    final visibleSensors = allSensors.where((e) => !_hiddenDevices.contains("${e['mac']}_${e['endpoint']}") || _showHiddenFilter).toList();
    // [DIGITAL TWIN — Đợt 23] Cửa cuốn dùng upEp làm khóa Ẩn/Hiện đại diện (1 thẻ = 3 relay vật lý)
    final visibleRollingDoors = allRollingDoors.where((e) => !_hiddenDevices.contains("${e['mac']}_${e['upEp']}") || _showHiddenFilter).toList();
    final visiblePumps = allPumps.where((e) => !_hiddenDevices.contains("${e['mac']}_${e['endpoint']}") || _showHiddenFilter).toList();
    final visibleDimmers = allDimmers.where((e) => !_hiddenDevices.contains("${e['mac']}_${e['endpoint']}") || _showHiddenFilter).toList();
    final visibleGenericPrimary = allGenericPrimary.where((e) => !_hiddenDevices.contains("${e['mac']}_${e['endpoint']}") || _showHiddenFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [PHÒNG] Đang xem 1 phòng -> chèn Công tắc tổng phòng lên ĐẦU lưới
        if (selRoom != null) _buildRoomMasterCard(isDark, selRoom, roomProv.roomName(selRoom)),

        // ====================================================================
        // 0. DẢI TRẠNG THÁI KÊNH REALTIME: MQTT đứt (PC ngủ mạng, broker timeout)
        //    là hiện ngay "Đang kết nối lại máy chủ..." — người dùng biết vì sao
        //    nút chưa phản hồi thay vì tưởng App đơ; tự biến mất khi nối lại xong.
        // ====================================================================
        if (!provider.brokerOnline)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Đang kết nối lại máy chủ... Lệnh điều khiển sẽ hoạt động ngay khi kênh realtime hồi phục.', style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          ),

        // ====================================================================
        // 1. KHỐI TRÊN: THẺ QUẠT LỚN (mỗi quạt đúng MỘT thẻ)
        // ====================================================================
        if (visibleFans.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Wrap(
            spacing: 16, runSpacing: 16,
            children: visibleFans.map((e) {
              final String hideKey = "${e['mac']}_${e['endpoint']}";
              // status gói tốc độ + đảo gió + online: đổi bất kỳ chỉ số nào là key đổi,
              // ép Flutter dựng lại thẻ -> vòng quay/màu sắc/trạng thái xám cập nhật tức thì
              final String status = "${e['speed']}_${e['swing']}_${e['online']}";
              // Endpoint dùng để LƯU TÊN: hộp quạt rời gom thẻ ("fan") vẫn phải trỏ về
              // endpoint thật S_{MAC} mà Backend dùng trong Redis hash device_names
              final String renameEndpoint = (e['endpoint'] as String).startsWith('S_') || RegExp(r'^[Ff]\d+$').hasMatch(e['endpoint'])
                  ? e['endpoint'] : 'S_${e['mac']}';
              // [NGUỒN BƠM DUY NHẤT] bộ callback chuẩn (rename theo endpoint thật của quạt)
              final cb = _stdCallbacks(e['mac'], "${e['mac']}_$renameEndpoint", e['name'], endpoint: renameEndpoint);
              return SmartFanCard(
                key: ValueKey("${hideKey}_$status"),
                mac: e['mac'],
                endpoint: e['endpoint'],
                initialSpeed: e['speed'] ?? 0,
                initialSwing: e['swing'] == true,
                backendName: e['name'],
                isOffline: e['online'] != true,
                isHidden: _hiddenDevices.contains(hideKey),
                provider: provider,
                rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}),
                onRefresh: _handleRefresh,
                // [FIX NÚT ẨN BỊ LIỆT] nối thẳng vào kho _hiddenDevices + lưu bền
                onToggleHide: (hide) => setState(() {
                  hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
                  _persistHiddenDevices();
                }),
                // [CHUẨN HÓA] bơm đồng loạt bộ callback chuẩn
                onDelete: cb.delete,
                onRename: cb.rename,
                onAssignHome: cb.assignHome,
                onAssignRoom: cb.assignRoom,
                onDeviceTimer: cb.timer,
                onDeviceHistory: cb.history,
                onDeviceAutomation: cb.automation,
                onDeviceShare: cb.share,
              );
            }).toList(),
          ),
        ),

        // ====================================================================
        // 1b. KHỐI CẢM BIẾN MÔI TRƯỜNG (DHT11...): Nhiệt độ °C + Độ ẩm %
        // ====================================================================
        if (visibleSensors.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Wrap(
            spacing: 16, runSpacing: 16,
            children: visibleSensors.map((e) {
              final String hideKey = "${e['mac']}_${e['endpoint']}";
              final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']); // [NGUỒN BƠM DUY NHẤT]
              return SmartSensorCard(
                // key chứa cả số đo + online: sóng MQTT đổi nhiệt/ẩm là thẻ vẽ lại ngay
                key: ValueKey("${hideKey}_${e['temp']}_${e['hum']}_${e['online']}"),
                mac: e['mac'],
                endpoint: e['endpoint'],
                name: e['name'],
                temperature: e['temp'],
                humidity: e['hum'],
                isOffline: e['online'] != true,
                isHidden: _hiddenDevices.contains(hideKey),
                provider: provider,
                rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}),
                onToggleHide: (hide) => setState(() {
                  hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
                  _persistHiddenDevices();
                }),
                // [CHUẨN HÓA] bơm đồng loạt bộ callback chuẩn (dùng chung mọi loại thẻ)
                onRename: cb.rename,
                onDelete: cb.delete,
                onAssignHome: cb.assignHome,
                onAssignRoom: cb.assignRoom,
                onDeviceTimer: cb.timer,
                onDeviceHistory: cb.history,
                onDeviceAutomation: cb.automation,
                onDeviceShare: cb.share,
              );
            }).toList(),
          ),
        ),

        // ====================================================================
        // 1c. [DIGITAL TWIN — Đợt 23] CỬA CUỐN / BƠM / ĐÈN CHIẾT ÁP / LƯỚI AN TOÀN
        // ====================================================================
        if (visibleRollingDoors.isNotEmpty || visiblePumps.isNotEmpty || visibleDimmers.isNotEmpty || visibleGenericPrimary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Wrap(
              spacing: 16, runSpacing: 16,
              children: [
                ...visibleRollingDoors.map((e) {
                  final String hideKey = "${e['mac']}_${e['upEp']}";
                  final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['upEp']);
                  return SmartRollingDoorCard(
                    key: ValueKey("${hideKey}_${e['positionPct']}_${e['travelSec']}_${e['online']}"),
                    mac: e['mac'],
                    upEndpoint: e['upEp'], downEndpoint: e['downEp'], stopEndpoint: e['stopEp'],
                    backendName: e['name'],
                    isOffline: e['online'] != true,
                    travelTimeSec: e['travelSec'] ?? 0,
                    initialPositionPct: e['positionPct'] ?? 0,
                    provider: provider,
                    isHidden: _hiddenDevices.contains(hideKey),
                    onToggleHide: (hide) => setState(() {
                      hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
                      _persistHiddenDevices();
                    }),
                    onOpenSettings: () => showDeviceSettingsPopup(context, isDark: isDark, mac: e['mac'], displayName: e['name'], rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}), provider: provider, onRename: cb.rename),
                    callbacks: cb,
                  );
                }),
                ...visiblePumps.map((e) {
                  final String hideKey = "${e['mac']}_${e['endpoint']}";
                  final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
                  return SmartPumpCard(
                    key: ValueKey("${hideKey}_${e['state']}_${e['online']}"),
                    mac: e['mac'],
                    endpoint: e['endpoint'],
                    isOn: e['state'] == 'ON',
                    isOffline: e['online'] != true,
                    backendName: e['name'],
                    provider: provider,
                    isHidden: _hiddenDevices.contains(hideKey),
                    onToggleHide: (hide) => setState(() {
                      hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
                      _persistHiddenDevices();
                    }),
                    onOpenSettings: () => showDeviceSettingsPopup(context, isDark: isDark, mac: e['mac'], displayName: e['name'], rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}), provider: provider, onRename: cb.rename),
                    callbacks: cb,
                  );
                }),
                ...visibleDimmers.map((e) {
                  final String hideKey = "${e['mac']}_${e['endpoint']}";
                  final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
                  return SmartDimmerCard(
                    key: ValueKey("${hideKey}_${e['state']}_${e['brightness']}_${e['online']}"),
                    mac: e['mac'],
                    endpoint: e['endpoint'],
                    isOn: e['state'] == 'ON',
                    brightness: e['brightness'] ?? 0,
                    isOffline: e['online'] != true,
                    backendName: e['name'],
                    provider: provider,
                    isHidden: _hiddenDevices.contains(hideKey),
                    onToggleHide: (hide) => setState(() {
                      hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
                      _persistHiddenDevices();
                    }),
                    onOpenSettings: () => showDeviceSettingsPopup(context, isDark: isDark, mac: e['mac'], displayName: e['name'], rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}), provider: provider, onRename: cb.rename),
                    callbacks: cb,
                  );
                }),
                ...visibleGenericPrimary.map((e) {
                  final String hideKey = "${e['mac']}_${e['endpoint']}";
                  final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
                  return GenericDeviceCard(
                    key: ValueKey("${hideKey}_${e['state']}_${e['online']}"),
                    mac: e['mac'],
                    endpoint: e['endpoint'],
                    category: e['category'] ?? '',
                    isOn: e['state'] == 'ON',
                    isOffline: e['online'] != true,
                    backendName: e['name'],
                    provider: provider,
                    isHidden: _hiddenDevices.contains(hideKey),
                    onToggleHide: (hide) => setState(() {
                      hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
                      _persistHiddenDevices();
                    }),
                    onOpenSettings: () => showDeviceSettingsPopup(context, isDark: isDark, mac: e['mac'], displayName: e['name'], rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}), provider: provider, onRename: cb.rename),
                    callbacks: cb,
                  );
                }),
              ],
            ),
          ),

        // ====================================================================
        // 2. KHỐI DƯỚI: LƯỚI CÔNG TẮC (mỗi kênh một thẻ độc lập)
        // ====================================================================
        if (visibleSwitches.isNotEmpty) LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount; double ratio;
            if (constraints.maxWidth < 500) { crossAxisCount = 3; ratio = 1.0; }
            else { crossAxisCount = (constraints.maxWidth / 120).floor(); if (crossAxisCount < 4) crossAxisCount = 4; ratio = 1.0; }

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleSwitches.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: ratio),
              itemBuilder: (context, index) {
                final item = visibleSwitches[index];
                final String mac = item['mac'];
                final String ep = item['endpoint'];
                final String deviceKey = "${mac}_$ep";
                final bool isDevOnline = item['online'] == true;
                final String status = "${item['state']}_$isDevOnline";
                final bool isOn = item['state'] == 'ON';
                // [NGUỒN BƠM DUY NHẤT] bộ callback chuẩn — bơm đồng loạt vào thẻ
                final cb = _stdCallbacks(mac, deviceKey, item['name'], endpoint: ep);

                return SmartSwitchCard(
                  // Key chứa cả trạng thái + online: sóng MQTT đổi ON/OFF hay LWT báo
                  // Ngoại tuyến là thẻ dựng lại ngay -> màu sắc không bao giờ trễ nhịp
                  key: ValueKey("${mac}_${ep}_$status"),
                  mac: mac,
                  endpointKey: ep,
                  backendName: item['name'],
                  initialStatus: isOn,
                  isOffline: !isDevOnline,
                  isMaster: item['isMaster'] == true, // nút TỔNG (endpoint "all") — icon + nhãn riêng
                  provider: provider,
                  onRefresh: _handleRefresh,
                  rawDeviceData: item['rawDevice'],
                  isHidden: _hiddenDevices.contains(deviceKey),
                  isSelectionMode: _isSelectionMode,
                  isSelected: _selectedDevices.contains(deviceKey),
                  hasHiddenDevices: _hiddenDevices.isNotEmpty,
                  isShowingHidden: _showHiddenFilter,
                  onToggleShowHidden: () => setState(() => _showHiddenFilter = !_showHiddenFilter),
                  onEnterSelectionMode: () => setState(() { _isSelectionMode = true; _selectedDevices.add(deviceKey); }),
                  onToggleSelect: () => setState(() { _selectedDevices.contains(deviceKey) ? _selectedDevices.remove(deviceKey) : _selectedDevices.add(deviceKey); if (_selectedDevices.isEmpty) _isSelectionMode = false; }),
                  onToggleHide: (hide) => setState(() { hide ? _hiddenDevices.add(deviceKey) : _hiddenDevices.remove(deviceKey); _persistHiddenDevices(); }),
                  // [CHUẨN HÓA] bơm đồng loạt bộ callback chuẩn
                  onDelete: cb.delete,
                  onRename: cb.rename,
                  onAssignHome: cb.assignHome,
                  onAssignRoom: cb.assignRoom,
                  onDeviceTimer: cb.timer,
                  onDeviceHistory: cb.history,
                  onDeviceAutomation: cb.automation,
                  onDeviceShare: cb.share,
                );
              },
            );
          },
        ),

        // ====================================================================
        // [NHÓM] CÔNG TẮC ẢO — render bằng chính SmartSwitchCard (badge "NHÓM")
        // ====================================================================
        Builder(builder: (context) {
          final groups = context.watch<RoomGroupProvider>().groups;
          // Watch DeviceProvider để trạng thái tổng của nhóm cập nhật LIVE khi thành viên đổi
          final deviceProv = context.watch<DeviceProvider>();
          if (groups.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: LayoutBuilder(builder: (context, constraints) {
              int crossAxisCount = constraints.maxWidth < 500 ? 3 : (constraints.maxWidth / 120).floor().clamp(4, 12);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: groups.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.0),
                itemBuilder: (context, index) {
                  final g = groups[index];
                  // [ĐỒNG BỘ UI NHÓM] Sáng nếu CÓ bất kỳ thành viên nào đang bật; tắt khi TẤT CẢ tắt
                  // [MULTI-CHANNEL] Nhóm sáng khi BẤT KỲ thành viên nào bật: member có
                  // endpoint cụ thể chỉ soi đúng kênh đó; member kiểu cũ soi cả thiết bị.
                  final bool groupOn = g.members.any((m) => m.endpoint.isEmpty
                      ? deviceProv.anyEndpointOn(m.mac)
                      : (deviceProv.deviceOf(m.mac)?.isOn(m.endpoint) ?? false));
                  return SmartSwitchCard(
                    key: ValueKey('group_${g.mac}_${g.members.length}'),
                    mac: g.mac,
                    endpointKey: 'all',
                    backendName: g.name,
                    initialStatus: groupOn,
                    provider: provider,
                    onRefresh: _handleRefresh,
                    rawDeviceData: const {},
                    isGroup: true,
                    onGroupToggle: (turnOn) => _toggleGroup(g, turnOn),
                    onEditGroup: () => _openEditGroup(g.mac),
                    onAssignRoom: () => _assignSingleRoom(g.mac), // [PHÒNG] nhóm cũng gán được vào phòng
                    onRename: () => _renameGroup(g.mac, g.name),
                    onDelete: () => Provider.of<RoomGroupProvider>(context, listen: false).deleteGroup(g.mac),
                    onToggleHide: (_) {},
                    onToggleSelect: () {},
                    onEnterSelectionMode: () {},
                  );
                },
              );
            }),
          );
        }),
      ],
    );
  }

  // ==========================================================================
  // 🔗 DEEPLINK TỪ CHUÔNG THÔNG BÁO: MAC -> mở thẳng Popup Cài đặt thiết bị
  // ==========================================================================
  /// Tìm thiết bị theo MAC trong danh sách nhà đang mở rồi bật Popup Cài đặt của nó,
  /// đồng thời tự chạy luôn một lượt check firmware để nút "Cập nhật" hiện ra ngay.
  void _openDeviceSettingsByMac(String mac) {
    final cleanMac = mac.replaceAll(':', '').toUpperCase();
    Map<String, dynamic>? raw;
    for (final d in _currentHomeDevices) {
      final dMac = (d['mac_address'] ?? d['mac'] ?? '').toString().replaceAll(':', '').toUpperCase();
      if (dMac == cleanMac) { raw = Map<String, dynamic>.from(d); break; }
    }
    if (raw == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Thiết bị $cleanMac không nằm trong khu vực đang mở — hãy chuyển đúng nhà rồi thử lại.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final Map<String, dynamic> deviceData = raw;

    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Nếu là hộp quạt rời (Fan_Control) thì popup mở kèm cụm nút chỉnh tốc độ/đảo gió
    final String fwType = (deviceData['fw_type'] ?? '').toString();
    String? fanEndpoint;
    if (fwType.contains('FAN')) fanEndpoint = 'S_$cleanMac';

    final String deviceName = (deviceData['name'] ?? 'Thiết bị $cleanMac').toString();
    showDeviceSettingsPopup(
      context,
      isDark: isDark,
      mac: cleanMac,
      displayName: deviceName,
      rawDeviceData: deviceData,
      provider: provider,
      fanEndpoint: fanEndpoint,
      autoCheckFirmware: true, // người dùng đến từ tin "có bản mới" -> check ngay cho họ bấm
      onRename: () => _showRenameDialog('${cleanMac}_${fanEndpoint ?? "S_$cleanMac"}', deviceName),
    );
  }

  void _showRenameDialog(String deviceKey, String currentName) {
    TextEditingController controller = TextEditingController(text: currentName);
    // deviceKey = "{MAC 12 hex}_{endpointID}" — MAC chuẩn hóa luôn đúng 12 ký tự
    final String mac = deviceKey.length > 12 ? deviceKey.substring(0, 12) : deviceKey;
    final String endpoint = deviceKey.length > 13 ? deviceKey.substring(13) : '';
    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog() — gộp
    // title+content+actions vào 1 Column, logic lưu tên/callback giữ nguyên 100%.
    showAppDialog(
      context: context,
      child: Builder(
        builder: (ctx) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Đổi tên thiết bị', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nhập tên mới (để trống = tên tự động)...')),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A651)),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      // LƯU THẬT vào database qua Backend; tên user đặt được ưu tiên
                      // tuyệt đối trước tên tự sinh sw-/Fan- ở mọi màn hình
                      final ok = await ApiService().renameDeviceEndpoint(mac, endpoint, controller.text.trim());
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'Đã lưu tên mới: ${controller.text.trim().isEmpty ? "(tên tự động)" : controller.text.trim()}' : 'Không thể lưu tên — kiểm tra kết nối!'),
                        backgroundColor: ok ? const Color(0xFF00A651) : Colors.redAccent,
                      ));
                      if (ok) _handleRefresh();
                    },
                    child: const Text('Lưu thay đổi', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color textSub, String message) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(height: 40), Icon(Icons.devices_other_rounded, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300), const SizedBox(height: 16), Text(message, style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w500)), const SizedBox(height: 40)]));
  }
}
class WindowsSettingsDialog extends StatefulWidget {
  final String currentRole; final String currentEmail; final int initialTab;
  const WindowsSettingsDialog({super.key, required this.currentRole, required this.currentEmail, this.initialTab = 0});
  @override
  State<WindowsSettingsDialog> createState() => _WindowsSettingsDialogState();
}

class _WindowsSettingsDialogState extends State<WindowsSettingsDialog> {
  late int _selectedTab;
  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() { super.initState(); _selectedTab = widget.initialTab; }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [FIX — Low Contrast trên nền Kính] textMain/textSub trước đây CHỈ theo isDark (hệ thống
    // Sáng/Tối), hoàn toàn không biết popup này đang nằm trong showAppDialog kính hay không —
    // khiến chữ dùng đúng màu của nền ĐẶC (trắng/xám) trong khi nền thật là kính mờ xuyên thấu
    // Aurora nhiều màu, gây tương phản thấp. Đồng bộ quy ước glass-aware đã dùng ở AppTextField/
    // AppDropdown: BẬT kính -> luôn trắng/trắng70 bất kể Sáng/Tối hệ thống.
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final Color textMain = isGlass ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A));
    final Color textSub = isGlass ? Colors.white70 : (isDark ? Colors.white54 : const Color(0xFF64748B));
    final Color sidebarColor = isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey.withValues(alpha: 0.05);
    // [ĐA NGÔN NGỮ — PROOF OF CONCEPT] AppTranslations.of(context) dùng context.watch() nội bộ
    // -> build() này tự rebuild khi đổi ngôn ngữ, không cần Hot Restart.
    final t = AppTranslations.of(context);

    // [GLASS THEME] Dialog/ConstrainedBox/AppContainer thủ công cũ ĐÃ BỎ khỏi build() của
    // chính class này — caller (_showSettingsMenu) nay đưa thẳng WindowsSettingsDialog vào
    // showAppDialog(child: ...), showAppDialog tự cấp khung Dialog/kính bên ngoài. Giữ lại
    // ConstrainedBox để khóa đúng kích thước 1000x650 như cũ.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 650),
      child: Row(
        children: [
          Container(
            width: 240, decoration: BoxDecoration(color: sidebarColor, border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.2)))),
            child: Column(
              children: [
                Padding(padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0), child: Container(height: 32, decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.white70, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.3))), child: Row(children: [const SizedBox(width: 8), Icon(Icons.search, size: 16, color: textSub), const SizedBox(width: 8), Text('Tìm kiếm', style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w500, shadows: isGlass ? kGlassTextShadow : null))]))),
                _buildTabButton(0, Icons.person_outline, t.text('profile'), textMain, isGlass), _buildTabButton(1, Icons.palette_outlined, t.text('appearance'), textMain, isGlass), _buildTabButton(2, Icons.shield_outlined, t.text('security_password'), textMain, isGlass), _buildTabButton(3, Icons.info_outline, t.text('system_info'), textMain, isGlass), const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: InkWell(
                    onTap: () async { Navigator.pop(context); await AuthService().logout(); if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false); },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center, decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(t.text('logout'), style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, shadows: isGlass ? kGlassTextShadow : null))),
                  ),
                )
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [Padding(padding: const EdgeInsets.only(top: 12.0, right: 12.0), child: IconButton(icon: Icon(Icons.close, size: 24, color: textSub), hoverColor: Colors.redAccent.withValues(alpha: 0.1), onPressed: () => Navigator.pop(context), splashRadius: 20))]),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32.0, 0, 32.0, 32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedTab != 0) ...[Text(_selectedTab == 1 ? t.text('appearance') : _selectedTab == 2 ? t.text('security_password') : t.text('system_info'), style: TextStyle(color: textMain, fontSize: 26, fontWeight: FontWeight.bold, shadows: isGlass ? kGlassTextShadow : null)), const SizedBox(height: 32)],
                        Expanded(child: _selectedTab == 0 ? ProfileManagementView(currentRole: widget.currentRole, currentEmail: widget.currentEmail) : _selectedTab == 1 ? _buildAppearanceTab(textMain, textSub, isGlass) : _selectedTab == 2 ? _buildSecurityTab(textMain, textSub, isGlass) : _buildInfoTab(textMain, textSub, isGlass)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String title, Color txtMain, bool isGlass) {
    bool isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index), borderRadius: BorderRadius.circular(8),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: isSelected ? tkGreen : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(icon, size: 20, color: isSelected ? Colors.white : txtMain), const SizedBox(width: 12), Text(title, style: TextStyle(color: isSelected ? Colors.white : txtMain, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14, shadows: isGlass ? kGlassTextShadow : null))])),
      ),
    );
  }

  Widget _buildAppearanceTab(Color textMain, Color textSub, bool isGlass) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final t = AppTranslations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color boxColor = isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1);
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.text('color_theme'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, shadows: sh)), const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
          // [LINT] RadioGroup tổ tiên thay cho groupValue/onChanged per-tile (deprecated Flutter 3.32+)
          child: RadioGroup<ThemeMode>(
            groupValue: themeProvider.themeMode,
            onChanged: (val) { if (val != null) themeProvider.setThemeMode(val); },
            child: Column(children: [
              RadioListTile<ThemeMode>(title: Text(t.text('light_mode'), style: TextStyle(color: textMain, fontWeight: FontWeight.w500, shadows: sh)), value: ThemeMode.light, activeColor: tkGreen), Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
              RadioListTile<ThemeMode>(title: Text(t.text('dark_mode'), style: TextStyle(color: textMain, fontWeight: FontWeight.w500, shadows: sh)), value: ThemeMode.dark, activeColor: tkGreen), Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
              RadioListTile<ThemeMode>(title: Text(t.text('system_mode'), style: TextStyle(color: textMain, fontWeight: FontWeight.w500, shadows: sh)), value: ThemeMode.system, activeColor: tkGreen),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        // [GLASS THEME — VÍ DỤ ÁP DỤNG] Trục ĐỘC LẬP với Sáng/Tối ở trên — bật/tắt lớp "vỏ"
        // Ultra-Glassmorphism (AppScaffold/AppCard/... trong app_ui_wrappers.dart tự đọc cờ
        // này qua ThemeProvider, không cần khởi động lại App).
        Text(t.text('interface_effect'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, shadows: sh)), const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          // [FIX — Đúng AppSwitch, không phải Switch trần] SwitchListTile trước đây dùng
          // Switch() mặc định của Material — không có hiệu ứng kính riêng, lệch khỏi mọi
          // control khác trong popup này đã qua app_ui_wrappers.dart. AppSwitch không có
          // sẵn slot title/subtitle như SwitchListTile nên tự dựng Row + Column nhãn.
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.text('glass_theme'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600, shadows: sh)),
                    const SizedBox(height: 2),
                    Text(t.text('glass_theme_desc'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w500, shadows: sh)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppSwitch(
                value: themeProvider.isGlassThemeEnabled,
                activeColor: tkGreen,
                onChanged: (v) => themeProvider.setGlassThemeEnabled(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // [ĐA NGÔN NGỮ — PROOF OF CONCEPT] Mục "Ngôn ngữ / Language" mới — cùng layout
        // Container(boxColor, borderRadius:12) + RadioGroup như khối Sáng/Tối phía trên, để
        // không lệch giao diện. Đổi ngôn ngữ gọi languageProvider.changeLanguage() ->
        // notifyListeners() -> mọi AppTranslations.of(context) trong cây widget tự vẽ lại NGAY.
        Text(t.text('language'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, shadows: sh)), const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
          child: RadioGroup<String>(
            groupValue: languageProvider.locale.languageCode,
            onChanged: (val) { if (val != null) languageProvider.changeLanguage(val); },
            child: Column(children: [
              RadioListTile<String>(title: Text(t.text('vietnamese'), style: TextStyle(color: textMain, fontWeight: FontWeight.w500, shadows: sh)), value: 'vi', activeColor: tkGreen), Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
              RadioListTile<String>(title: Text(t.text('english'), style: TextStyle(color: textMain, fontWeight: FontWeight.w500, shadows: sh)), value: 'en', activeColor: tkGreen),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityTab(Color textMain, Color textSub, bool isGlass) {
    final t = AppTranslations.of(context);
    final oldPassCtrl = TextEditingController(), newPassCtrl = TextEditingController(), confirmPassCtrl = TextEditingController();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.text('change_password_title'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, shadows: isGlass ? kGlassTextShadow : null)), const SizedBox(height: 16),
          // [FIX — Input mờ trên nền kính] TextField trần (fillColor/border tự chế) ĐÃ THAY
          // bằng AppTextField — dùng đúng khối kính "chìm" trung tâm (_GlassSurface inverted)
          // của cả hệ thống thay vì tự vẽ lại một phiên bản viền/fill khác ở đây.
          AppTextField(controller: oldPassCtrl, obscureText: true, labelText: t.text('old_password')), const SizedBox(height: 16),
          AppTextField(controller: newPassCtrl, obscureText: true, labelText: t.text('new_password')), const SizedBox(height: 16),
          AppTextField(controller: confirmPassCtrl, obscureText: true, labelText: t.text('confirm_new_password')), const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                final oldPass = oldPassCtrl.text.trim(), newPass = newPassCtrl.text.trim();
                if (oldPass.isEmpty || newPass.isEmpty) return;
                if (newPass != confirmPassCtrl.text.trim()) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.text('password_mismatch')), backgroundColor: Colors.redAccent)); return; }
                String? error = await AuthService().changePassword(oldPass, newPass);
                // context ở đây là context của State -> guard bằng mounted của State
                if (!mounted) return;
                if (error == null) {
                  oldPassCtrl.clear(); newPassCtrl.clear(); confirmPassCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.text('password_change_success')), backgroundColor: const Color(0xFF00A651)));
                } else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent)); }
              },
              child: Text(t.text('update_password_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoTab(Color textMain, Color textSub, bool isGlass) {
    final t = AppTranslations.of(context);
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    // [GIỮ NGUYÊN BIẾN ĐỘNG] Tên thương hiệu "TK_IOT CloudPlatform", số phiên bản "3.0.1
    // (Stable)", giá trị kỹ thuật "MQTT Core Golang (Armbian)" và dòng bản quyền "© 2026 Tuan
    // Kiet Solutions." KHÔNG dịch — đây là tên riêng/số liệu thật, không phải câu UI chung.
    // Chỉ NHÃN đứng trước (Phiên bản/Máy chủ/Bản quyền) được bọc AppTranslations.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Column(children: [Container(width: 80, height: 80, decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)), child: Icon(Icons.home_rounded, color: tkGreen, size: 48)), const SizedBox(height: 16), Text('TK_IOT CloudPlatform', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.w900, shadows: sh)), Text('${t.text('app_version_label')} 3.0.1 (Stable)', style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w500, shadows: sh))])),
        const SizedBox(height: 40),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.dns, color: textSub), title: Text(t.text('server'), style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w500, shadows: sh)), subtitle: Text('MQTT Core Golang (Armbian)', style: TextStyle(color: textMain, fontWeight: FontWeight.bold, shadows: sh))),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.copyright, color: textSub), title: Text(t.text('copyright'), style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w500, shadows: sh)), subtitle: Text('© 2026 Tuan Kiet Solutions.', style: TextStyle(color: textMain, fontWeight: FontWeight.bold, shadows: sh))),
      ],
    );
  }
}

// ============================================================================
// 💡 CÔNG TẮC ĐÈN CHIA 3 CỘT (MOBILE) VÀ NỀN SOLID GREEN KHI BẬT
// ============================================================================
class SmartSwitchCard extends StatefulWidget {
  final String mac;
  final String endpointKey;
  final bool initialStatus;
  final bool isOffline; // LWT báo Ngoại tuyến -> xám mờ + khóa điều khiển
  final DeviceProvider provider;
  final Function onRefresh;
  final String? backendName;
  final Map<String, dynamic> rawDeviceData; // <--- CHỨA CẢM BIẾN & CHẨN ĐOÁN

  final bool isSelectionMode;
  final bool isSelected;
  final bool isHidden;
  final bool isMaster; // nút TỔNG (endpoint "all") — bấm bật/tắt cả cụm relay
  final VoidCallback onToggleSelect;
  final VoidCallback onEnterSelectionMode;
  final Function(bool) onToggleHide;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final bool hasHiddenDevices;
  final bool isShowingHidden;
  final VoidCallback? onToggleShowHidden;
  final VoidCallback? onAssignHome; // [ADMIN] Chuyển nhà — non-null CHỈ khi user là SUPER_USER
  final VoidCallback? onAssignRoom; // [PHÒNG] Chuyển/Thêm vào phòng
  final VoidCallback? onOpenSettings; // [CHUẨN HÓA] Cài đặt thiết bị (null -> dùng settings nội bộ)
  // [CHUẨN TUYA/GOOGLE HOME] bộ chức năng mở rộng (Thông tin đã gộp vào onOpenSettings)
  final VoidCallback? onDeviceTimer;
  final VoidCallback? onDeviceHistory;
  final VoidCallback? onDeviceAutomation;
  final VoidCallback? onDeviceShare;
  final bool isGroup;               // [NHÓM] true = Công tắc ảo (nhóm) -> hiện badge phân biệt
  final VoidCallback? onEditGroup;  // [NHÓM] Chỉnh sửa nhóm — chỉ non-null khi isGroup
  // [NHÓM] Bấm nút tổng của nhóm ảo -> điều khiển TẤT CẢ thành viên (turnOn = trạng thái
  // muốn chuyển tới). non-null CHỈ khi isGroup; nhóm KHÔNG bắn lệnh vào MAC ảo "GROUP_xxx".
  final void Function(bool turnOn)? onGroupToggle;

  const SmartSwitchCard({
    super.key,
    required this.mac, required this.endpointKey, required this.initialStatus,
    this.isOffline = false,
    this.isMaster = false,
    required this.provider, required this.onRefresh, this.backendName,
    required this.rawDeviceData,
    this.isSelectionMode = false, this.isSelected = false, this.isHidden = false,
    required this.onToggleSelect, required this.onEnterSelectionMode,
    required this.onToggleHide, required this.onDelete, required this.onRename,
    this.hasHiddenDevices = false, this.isShowingHidden = false, this.onToggleShowHidden,
    this.onAssignHome,
    this.onAssignRoom,
    this.onOpenSettings,
    this.onDeviceTimer, this.onDeviceHistory, this.onDeviceAutomation, this.onDeviceShare,
    this.isGroup = false,
    this.onEditGroup,
    this.onGroupToggle,
  });

  @override
  State<SmartSwitchCard> createState() => _SmartSwitchCardState();
}

class _SmartSwitchCardState extends State<SmartSwitchCard> {
  late bool isOnline;
  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() { super.initState(); isOnline = widget.initialStatus; }

  @override
  void didUpdateWidget(SmartSwitchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus) setState(() => isOnline = widget.initialStatus);
  }

  void _handleTap() {
    if (widget.isSelectionMode) {
      widget.onToggleSelect();
      return;
    }
    // Thiết bị Ngoại tuyến: khóa hẳn điều khiển (vẫn cho long-press mở menu để xóa/ẩn)
    if (widget.isOffline) return;

    // [NHÓM] Nút tổng nhóm ảo: KHÔNG bắn lệnh vào MAC ảo "GROUP_xxx" (Backend không định
    // tuyến được) — mà lặp điều khiển TỪNG thành viên qua callback. isOnline = trạng thái
    // tổng hiện tại (bật nếu có bất kỳ thành viên bật) -> !isOnline = trạng thái muốn chuyển tới.
    if (widget.isGroup) {
      widget.onGroupToggle?.call(!isOnline);
      return;
    }

    // [REAL-STATE] KHÔNG lật màu ngay (bỏ Optimistic UI): chỉ bắn lệnh qua Bridge,
    // icon chỉ sáng khi rơ-le đóng cắt thật và state ngược về qua MQTT —
    // nhờ đó PC và Điện thoại cùng sáng ĐỒNG THỜI theo trạng thái thật.
    widget.provider.toggleDevice(widget.mac, widget.endpointKey, isOnline);
  }

  String _formatName() {
    if (widget.backendName != null && widget.backendName!.isNotEmpty) return widget.backendName!;
    return widget.endpointKey;
  }

  // --- MÀN HÌNH CÀI ĐẶT CHI TIẾT (POPUP GIỮA MÀN HÌNH - KÍNH MỜ CHUẨN) ---
  void _showDeviceSettingsDialog(BuildContext context, bool isDark) {
    // Popup Cài đặt được tách thành hàm dùng chung showDeviceSettingsPopup —
    // cùng một giao diện cho thẻ công tắc, thẻ quạt và deeplink từ chuông thông báo
    showDeviceSettingsPopup(
      context,
      isDark: isDark,
      mac: widget.mac,
      displayName: _formatName(),
      rawDeviceData: widget.rawDeviceData,
      provider: widget.provider,
      onRename: widget.onRename,
    );
  }

  // [REFACTOR] Menu ngữ cảnh nay DÙNG CHUNG qua DeviceMenuHelper — không còn code lặp cục bộ.
  // Các mục đặc thù công tắc (Chọn nhiều, Xem thiết bị ẩn) truyền qua extraItems.
  void _showDeviceOptions(BuildContext context, bool isDark) {
    // Gọi từ onLongPress (tap handler) -> listen: false, tránh "liệt nút".
    final t = AppTranslations.of(context, listen: false);
    DeviceMenuHelper.showGenericDeviceMenu(
      context: context,
      mac: widget.mac,
      currentName: _formatName(),
      subtitle: 'Endpoint: ${widget.endpointKey}',
      // [CHUẨN HÓA] ưu tiên callback bơm từ Dashboard; null -> settings nội bộ của thẻ
      onOpenSettings: widget.onOpenSettings ?? () => _showDeviceSettingsDialog(context, isDark),
      onDeviceTimer: widget.onDeviceTimer,
      onDeviceHistory: widget.onDeviceHistory,
      onDeviceAutomation: widget.onDeviceAutomation,
      onDeviceShare: widget.onDeviceShare,
      onRename: widget.onRename,
      isHidden: widget.isHidden,
      hideLabel: widget.isHidden ? t.text('show_device_again') : t.text('hide_from_dashboard'),
      hideSubtitle: t.text('hide_from_dashboard_desc'),
      onToggleHide: (v) => widget.onToggleHide(v),
      onAssignRoom: widget.onAssignRoom,   // [PHÒNG] tự render "Chuyển/Thêm vào phòng"
      onEditGroup: widget.onEditGroup,     // [NHÓM] chỉ hiện nếu là Công tắc ảo
      onAssignHome: widget.onAssignHome, // tự render "Chuyển nhà" nếu != null (SUPER_USER)
      onDelete: widget.onDelete,
      extraItems: [
        DeviceMenuItem(icon: Icons.checklist_rtl_rounded, title: t.text('select_multiple_devices'), onTap: widget.onEnterSelectionMode),
        if (widget.hasHiddenDevices)
          DeviceMenuItem(
            icon: widget.isShowingHidden ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
            title: widget.isShowingHidden ? t.text('close_hidden_view') : t.text('show_hidden_devices'),
            color: Colors.orange,
            onTap: () { if (widget.onToggleShowHidden != null) widget.onToggleShowHidden!(); },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool offline = widget.isOffline;
    final t = AppTranslations.of(context);
    // [ĐỢT 18 — ĐÁNH NỔI KHỐI] Widget này KHÔNG đi qua AppContainer (tự dựng ClipRRect+
    // BackdropFilter+AnimatedContainer riêng, luôn có blur nhẹ bất kể Glass Theme bật/tắt) nên
    // không tự thừa hưởng border/shadow chuẩn Sáng Thường — phải tự kiểm tra isGlass ở đây.
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    // Ngoại tuyến: ép toàn thẻ về tông xám mờ (Greyscale), bỏ qua màu bật/tắt
    final Color bgColor = offline
        ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade200)
        : (isOnline ? tkGreen : (isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.6)));
    final Color textColor = offline ? Colors.grey : (isOnline ? Colors.white : (isDark ? Colors.white : Colors.black87));
    final Color powerIconColor = offline ? Colors.grey.withValues(alpha: 0.4) : (isOnline ? Colors.white : (isDark ? Colors.white24 : Colors.grey.shade400));

    // [ĐỢT 18] Viền + đổ bóng "nổi khối" CHỈ áp cho Sáng Thường (không Kính) — đặt ở Container
    // NGOÀI CÙNG (trước ClipRRect/BackdropFilter) vì boxShadow tràn ra ngoài rìa hộp, đặt bên
    // trong ClipRRect sẽ bị cắt mất (cùng bài học đã sửa cho _GlassSurface/AppContainer/
    // SmartFanCard). Border MÀU TRẠNG THÁI (selected/online/offline) bên trong AnimatedContainer
    // giữ NGUYÊN không đổi — đây là lớp viền THỨ HAI, riêng biệt, chỉ để tách khối khỏi nền.
    final BoxDecoration outerDecoration = (!isDark && !isGlass)
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
          )
        : BoxDecoration(borderRadius: BorderRadius.circular(16));

    return Container(
      decoration: outerDecoration,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          foregroundDecoration: widget.isHidden ? BoxDecoration(color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.7)) : null,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.isSelected ? tkGreen : (offline ? Colors.grey.withValues(alpha: 0.3) : (isOnline ? tkGreen : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white))), width: widget.isSelected ? 3.0 : 1.5), boxShadow: [if (!isDark && !isOnline && !offline) BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))]),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleTap, onLongPress: () { if (!widget.isSelectionMode) _showDeviceOptions(context, isDark); },
              child: Stack(
                children: [
                  // Nút TỔNG (master) mang icon lưới riêng để phân biệt với kênh lẻ (bóng đèn)
                  // Công tắc ảo (nhóm) mang icon "category"; nút tổng -> lưới; kênh lẻ -> bóng đèn
                  Positioned(top: 10, left: 10, child: Icon(offline ? Icons.cloud_off_rounded : (widget.isGroup ? Icons.category : (widget.isMaster ? Icons.grid_view_rounded : Icons.lightbulb_outline)), color: offline ? Colors.grey : (isOnline ? Colors.white : tkGreen), size: 18)),
                  // [NHÓM] Badge góc phải phân biệt Công tắc ảo với thiết bị thật
                  if (widget.isGroup && !widget.isSelected)
                    Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purpleAccent.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)), child: const Text('NHÓM', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)))),
                  // Nhãn "Ngoại tuyến" nhỏ ở góc phải trên khi mất kết nối
                  if (offline && !widget.isSelected) Positioned(top: 10, right: 8, child: Text(t.text('offline'), style: TextStyle(color: Colors.grey.withValues(alpha: 0.9), fontSize: 9, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic))),
                  if (widget.isSelected) Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: tkGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.check, color: Colors.white, size: 14))),
                  // Nút tổng: icon "power" viền tròn nổi bật; kênh lẻ: power thường
                  Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.only(bottom: 14.0, top: 10.0), child: Icon(widget.isMaster ? Icons.settings_power_rounded : Icons.power_settings_new_rounded, color: powerIconColor, size: 36))),
                  Positioned(bottom: 8, left: 6, right: 6, child: Text(_formatName(), textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ============================================================================
// 🌀 QUẠT THÔNG MINH 
// ============================================================================
class SmartFanCard extends StatefulWidget {
  final String mac, endpoint; final int initialSpeed; final bool initialSwing; final DeviceProvider provider;
  final String? backendName;  // Tên từ Backend theo quy tắc "Fan-{4 cuối MAC}" (hoặc tên user tự đặt)
  final bool isOffline;       // LWT báo Ngoại tuyến -> xám mờ + khóa điều khiển
  final VoidCallback onRefresh;
  final VoidCallback onDelete;
  final VoidCallback? onRename;
  final bool isHidden;                       // đang nằm trong danh sách ẩn của Bảng điều khiển
  final ValueChanged<bool>? onToggleHide;    // callback ẩn/hiện — [FIX] trước đây nút Ẩn bị liệt vì thiếu hàm này
  final Map<String, dynamic> rawDeviceData; // gói REST đầy đủ (system_data, fw_type...) cho Popup Cài đặt
  final VoidCallback? onAssignHome; // [ADMIN] Chuyển nhà — non-null CHỈ khi user là SUPER_USER
  final VoidCallback? onAssignRoom; // [PHÒNG] Chuyển/Thêm vào phòng
  final VoidCallback? onOpenSettings; // [CHUẨN HÓA] Cài đặt thiết bị (null -> settings nội bộ)
  // [CHUẨN TUYA/GOOGLE HOME] bộ chức năng mở rộng (Thông tin đã gộp vào onOpenSettings)
  final VoidCallback? onDeviceTimer, onDeviceHistory, onDeviceAutomation, onDeviceShare;

  const SmartFanCard({super.key, required this.mac, required this.endpoint, required this.initialSpeed, required this.initialSwing, this.backendName, this.isOffline = false, required this.provider, required this.onRefresh, required this.onDelete, this.onRename, this.isHidden = false, this.onToggleHide, this.rawDeviceData = const {}, this.onAssignHome, this.onAssignRoom, this.onOpenSettings, this.onDeviceTimer, this.onDeviceHistory, this.onDeviceAutomation, this.onDeviceShare});
  @override
  State<SmartFanCard> createState() => _SmartFanCardState();
}

class _SmartFanCardState extends State<SmartFanCard> {
  late int speed; late bool swing; final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() { super.initState(); speed = widget.initialSpeed; swing = widget.initialSwing; }

  @override
  void didUpdateWidget(SmartFanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSwing != widget.initialSwing) swing = widget.initialSwing;
    if (oldWidget.initialSpeed != widget.initialSpeed) speed = widget.initialSpeed;
  }

  // [REAL-STATE] KHÔNG setState đổi giao diện ngay (bỏ Optimistic UI): chỉ bắn lệnh
  // qua Bridge; nút số và vòng quay chỉ đổi khi mạch quạt báo tốc độ THẬT ngược về
  // (state mới -> key thẻ đổi -> thẻ dựng lại) — PC và Điện thoại đồng bộ tuyệt đối.
  void _changeSpeed(int newSpeed) { if (widget.isOffline) return; widget.provider.setFanSpeed(widget.mac, newSpeed, endpoint: widget.endpoint, swing: swing); }
  void _toggleSwing() { if (widget.isOffline || speed == 0) return; widget.provider.setFanSpeed(widget.mac, speed, endpoint: widget.endpoint, swing: !swing); }

  // [REFACTOR] Menu quạt nay DÙNG CHUNG DeviceMenuHelper — hết code lặp _showDeviceOptions/_confirmDeleteFan.
  void _showDeviceOptions(BuildContext context, bool isDark) {
    // Gọi từ IconButton.onPressed (tap handler) -> listen: false, tránh "liệt nút".
    final t = AppTranslations.of(context, listen: false);
    DeviceMenuHelper.showGenericDeviceMenu(
      context: context,
      mac: widget.mac,
      currentName: widget.backendName ?? 'Quạt thông minh',
      headerIcon: Icons.all_out_rounded,
      // [CHUẨN HÓA] ưu tiên callback bơm từ Dashboard; null -> settings nội bộ (kèm fanEndpoint)
      onOpenSettings: widget.onOpenSettings ?? () => showDeviceSettingsPopup(
        context,
        isDark: isDark,
        mac: widget.mac,
        displayName: widget.backendName ?? 'Quạt thông minh',
        rawDeviceData: widget.rawDeviceData,
        provider: widget.provider,
        fanEndpoint: widget.endpoint,
        onRename: widget.onRename,
      ),
      onDeviceTimer: widget.onDeviceTimer,
      onDeviceHistory: widget.onDeviceHistory,
      onDeviceAutomation: widget.onDeviceAutomation,
      onDeviceShare: widget.onDeviceShare,
      onRename: widget.onRename,
      isHidden: widget.isHidden,
      hideLabel: widget.isHidden ? t.text('show_device_again') : t.text('hide_from_dashboard'),
      hideSubtitle: t.text('hide_from_dashboard_desc'),
      onToggleHide: widget.onToggleHide,
      onAssignRoom: widget.onAssignRoom, // [PHÒNG] tự render "Chuyển/Thêm vào phòng"
      onAssignHome: widget.onAssignHome, // tự render "Chuyển nhà" nếu != null (SUPER_USER)
      onDelete: widget.onDelete,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool offline = widget.isOffline;
    bool isOnline = speed > 0 && !offline, isSwingActive = swing && isOnline;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A), textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final t = AppTranslations.of(context);
    // [ĐỢT 13 — FIX TÀNG HÌNH] Dùng cho nút "Xoay" bên dưới — cùng lý do _buildBtn.
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;

    return Container(
      width: double.infinity, constraints: const BoxConstraints(maxWidth: 450),
      // [ĐỢT 18 — FIX SHADOW BỊ CẮT] AppContainer từ Đợt 9 đã TỰ có clipBehavior: Clip.antiAlias
      // + border/shadow vẽ đúng NGOÀI phần tự clip của chính nó — ClipRRect bọc ngoài trước đây
      // (comment "FIX BO GÓC" cũ) nay THỪA và có HẠI: nó cắt mất luôn boxShadow của AppContainer
      // (shadow vẽ tràn ra ngoài rìa hộp, ClipRRect bọc ngoài xén sạch) — đúng nguyên nhân khiến
      // thẻ Quạt trông phẳng ở Sáng Thường dù AppContainer đã có sẵn border/shadow. Bỏ hẳn lớp
      // ClipRRect thừa này — AppContainer tự lo việc bo góc/clip nội dung con y hệt trước đó.
      child: AppContainer(
        padding: const EdgeInsets.all(20),
        borderRadius: BorderRadius.circular(16),
        // Ngoại tuyến: toàn thẻ mờ xám (Greyscale); đang ẩn (xem qua bộ lọc thiết bị ẩn):
        // mờ nhẹ để phân biệt — nút menu (...) vẫn bấm được để hiện lại/xóa
        child: Opacity(
          opacity: offline ? 0.45 : (widget.isHidden ? 0.55 : 1.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: isOnline ? tkGreen.withValues(alpha: 0.15) : (isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.6)), shape: BoxShape.circle),
                    // Icon quay theo tốc độ THẬT từ mạch; offline thì đứng im + xám
                    child: SpinningWidget(isSpinning: isOnline, speedLevel: speed, child: Icon(offline ? Icons.cloud_off_rounded : Icons.all_out_rounded, color: isOnline ? tkGreen : (offline ? Colors.grey : textSub), size: 28))
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.backendName ?? 'Quạt thông minh', style: TextStyle(color: offline ? Colors.grey : textMain, fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    // [GIỮ NGUYÊN BIẾN ĐỘNG] "Số $speed" — số thứ tự tốc độ quạt, KHÔNG dịch
                    // (đúng yêu cầu); chỉ 2 từ trạng thái Đang bật/Đã tắt/Ngoại tuyến được dịch.
                    Text(offline ? t.text('offline') : (isOnline ? '${t.text('turned_on')} • Số $speed' : t.text('turned_off')), style: TextStyle(color: offline ? Colors.grey : (isOnline ? tkGreen : textSub), fontSize: 13, fontWeight: FontWeight.w600, fontStyle: offline ? FontStyle.italic : FontStyle.normal))
                  ])),
                  IconButton(icon: Icon(Icons.more_vert, color: textSub, size: 22), onPressed: () => _showDeviceOptions(context, isDark), splashRadius: 20)
                ],
              ),
              const SizedBox(height: 20),
              // Khóa cứng hàng nút điều khiển khi Ngoại tuyến
              IgnorePointer(
                ignoring: offline,
                child: Row(
                  children: [
                    _buildBtn(0, 'OFF', speed == 0 && !offline, isDark), const SizedBox(width: 8), _buildBtn(1, '1', speed == 1 && !offline, isDark), const SizedBox(width: 8), _buildBtn(2, '2', speed == 2 && !offline, isDark), const SizedBox(width: 8), _buildBtn(3, '3', speed == 3 && !offline, isDark), const SizedBox(width: 12),
                    Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.grey.shade300), const SizedBox(width: 12),
                    Material(color: isSwingActive ? tkGreen.withValues(alpha: 0.85) : (isDark ? Colors.white24 : (isGlass ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade200)), borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: _toggleSwing, child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, child: Row(children: [Icon(Icons.threesixty, color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), size: 16), const SizedBox(width: 4), Text('Xoay', style: TextStyle(color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 12, fontWeight: FontWeight.w800))]))))
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBtn(int btnSpeed, String label, bool isActive, bool isDark) {
    // [ĐỢT 13 — FIX TÀNG HÌNH] Gọi đồng bộ TỪ build() (không phải tap handler) -> context.watch()
    // an toàn ở đây. Sáng Thường: nút chưa chọn trước đây trắng@0.6 trên nền thẻ trắng gần như
    // vô hình — đổi hẳn sang xám nhạt để tách khối rõ; Kính (Sáng/Tối) và Tối Thường giữ nguyên.
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    bool isOffBtn = btnSpeed == 0;
    Color bgColor = isActive
        ? (isOffBtn ? Colors.redAccent.withValues(alpha: 0.85) : tkGreen.withValues(alpha: 0.85))
        : (isDark ? Colors.white10 : (isGlass ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade200));
    Color textColor = isActive ? Colors.white : (isDark ? Colors.white : Colors.black87);
    return Expanded(child: Material(color: bgColor, borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: () => _changeSpeed(btnSpeed), child: Container(height: 40, alignment: Alignment.center, child: Text(label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w900))))));
  }
}

// ============================================================================
// 🌡️ THẺ CẢM BIẾN MÔI TRƯỜNG (DHT11...) — HIỂN THỊ NHIỆT ĐỘ °C + ĐỘ ẨM %
// Cảm biến không có relay nên thẻ chỉ trưng số đo (realtime qua key của Wrap:
// sóng MQTT đổi nhiệt/ẩm là dashboard dựng lại thẻ với số mới ngay lập tức).
// Menu (…) dùng chung Popup Cài đặt với công tắc/quạt: đủ MAC/IP/RSSI/SSID/Firmware.
// ============================================================================
class SmartSensorCard extends StatelessWidget {
  final String mac;
  final String endpoint;       // endpoint chuẩn của cảm biến: SENS_{MAC}
  final String name;
  final String? temperature;   // °C — null khi chưa nhận được gói đo nào
  final String? humidity;      // %  — null khi chưa nhận được gói đo nào
  final bool isOffline;
  final bool isHidden;
  final DeviceProvider provider;
  final Map<String, dynamic> rawDeviceData;
  final ValueChanged<bool> onToggleHide;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onAssignHome; // [ADMIN] Chuyển nhà — non-null CHỈ khi user là SUPER_USER
  final VoidCallback? onAssignRoom; // [PHÒNG] Chuyển/Thêm vào phòng
  final VoidCallback? onOpenSettings; // [CHUẨN HÓA] Cài đặt thiết bị (null -> settings nội bộ)
  // [CHUẨN TUYA/GOOGLE HOME] bộ chức năng mở rộng (Thông tin đã gộp vào onOpenSettings)
  final VoidCallback? onDeviceTimer, onDeviceHistory, onDeviceAutomation, onDeviceShare;

  const SmartSensorCard({
    super.key,
    required this.mac, required this.endpoint, required this.name,
    this.temperature, this.humidity,
    this.isOffline = false, this.isHidden = false,
    required this.provider, this.rawDeviceData = const {},
    required this.onToggleHide, required this.onRename, required this.onDelete,
    this.onAssignHome,
    this.onAssignRoom,
    this.onOpenSettings,
    this.onDeviceTimer, this.onDeviceHistory, this.onDeviceAutomation, this.onDeviceShare,
  });

  static const Color tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final t = AppTranslations.of(context);

    Widget reading(IconData icon, String? value, String unit, Color color) => Expanded(
      child: Column(
        children: [
          Icon(icon, color: isOffline ? Colors.grey : color, size: 22),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value == null ? '--$unit' : '$value$unit',
              style: TextStyle(color: isOffline ? Colors.grey : textMain, fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity, constraints: const BoxConstraints(maxWidth: 450),
      child: AppContainer(
        padding: const EdgeInsets.all(20),
        child: Opacity(
          opacity: isOffline ? 0.45 : (isHidden ? 0.55 : 1.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: isOffline ? (isDark ? Colors.white10 : Colors.grey.shade200) : Colors.blueAccent.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(isOffline ? Icons.cloud_off_rounded : Icons.device_thermostat_rounded, color: isOffline ? Colors.grey : Colors.blueAccent, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: TextStyle(color: isOffline ? Colors.grey : textMain, fontSize: 16, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(isOffline ? t.text('offline') : 'Cảm biến môi trường', style: TextStyle(color: isOffline ? Colors.grey : tkGreen, fontSize: 13, fontWeight: FontWeight.w600, fontStyle: isOffline ? FontStyle.italic : FontStyle.normal)),
                  ])),
                  // [REFACTOR] Nút 3 chấm nay gọi DeviceMenuHelper dùng chung (đủ Cài đặt/Đổi tên/
                  // Ẩn/Chuyển nhà/Xóa) — cảm biến tự có full tính năng Admin mà không chép menu.
                  IconButton(
                    icon: Icon(Icons.more_vert, color: textSub, size: 22),
                    splashRadius: 20,
                    onPressed: () => DeviceMenuHelper.showGenericDeviceMenu(
                      context: context,
                      mac: mac,
                      currentName: name,
                      subtitle: 'Cảm biến môi trường',
                      headerIcon: Icons.device_thermostat_rounded,
                      // [CHUẨN HÓA] ưu tiên callback bơm từ Dashboard; null -> settings nội bộ
                      onOpenSettings: onOpenSettings ?? () => showDeviceSettingsPopup(context, isDark: isDark, mac: mac, displayName: name, rawDeviceData: rawDeviceData, provider: provider, onRename: onRename),
                      onDeviceTimer: onDeviceTimer,
                      onDeviceHistory: onDeviceHistory,
                      onDeviceAutomation: onDeviceAutomation,
                      onDeviceShare: onDeviceShare,
                      onRename: onRename,
                      isHidden: isHidden,
                      hideLabel: isHidden ? t.text('show_device_again') : t.text('hide_from_dashboard'),
                      hideSubtitle: t.text('hide_from_dashboard_desc'),
                      onToggleHide: onToggleHide,
                      onAssignRoom: onAssignRoom, // [PHÒNG] tự render "Chuyển/Thêm vào phòng"
                      onAssignHome: onAssignHome, // tự render "Chuyển nhà" nếu != null (SUPER_USER)
                      onDelete: onDelete,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  reading(Icons.thermostat_rounded, temperature, '°C', Colors.orange),
                  Container(width: 1, height: 44, color: isDark ? Colors.white10 : Colors.grey.shade300),
                  reading(Icons.water_drop_rounded, humidity, '%', Colors.blue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ⚙️ POPUP CÀI ĐẶT THIẾT BỊ DÙNG CHUNG
// Một giao diện duy nhất cho cả 3 lối vào: thẻ công tắc, thẻ quạt (Fan_Control/F1 Hub)
// và deeplink từ quả chuông thông báo. Hiển thị ĐẦY ĐỦ và ĐỒNG BỘ:
//   - Trạng thái Trực tuyến/Ngoại tuyến sống (LWT qua kho DPS)
//   - Cụm nút chỉnh tốc độ + đảo gió realtime (khi thiết bị là quạt)
//   - Thông số kỹ thuật thật: MAC, IP LAN, RSSI, "Mạng Wi-Fi kết nối: {SSID}", dòng firmware
//   - Vùng Firmware OTA: check thủ công / nút "Cập nhật ngay" / thanh % nạp realtime
// ============================================================================
Future<void> showDeviceSettingsPopup(
  BuildContext context, {
  required bool isDark,
  required String mac,
  required String displayName,
  required Map<String, dynamic> rawDeviceData,
  required DeviceProvider provider,
  VoidCallback? onRename,
  String? fanEndpoint,          // != null khi thiết bị là quạt -> hiện cụm nút tốc độ/đảo gió
  bool autoCheckFirmware = false, // true khi đến từ tin "có bản mới" -> tự check ngay
}) {
  // [GLASS THEME] DeviceSettingsPopup TỰ trả về nội dung thô (không còn tự bọc Dialog/
  // AppContainer bên trong build() của nó — xem class DeviceSettingsPopup) nên chỉ cần đưa
  // thẳng vào child: của showAppDialog.
  // [FIX — Chữ vỡ layout] maxWidth: 440 khớp ĐÚNG ConstrainedBox nội bộ của
  // DeviceSettingsPopup — trước đây bị showAppDialog mặc định 420 bóp nhẹ xuống dưới ý đồ gốc.
  return showAppDialog(
    context: context,
    maxWidth: 440,
    child: DeviceSettingsPopup(
      isDark: isDark,
      mac: mac,
      displayName: displayName,
      rawDeviceData: rawDeviceData,
      provider: provider,
      onRename: onRename,
      fanEndpoint: fanEndpoint,
      autoCheckFirmware: autoCheckFirmware,
    ),
  );
}

class DeviceSettingsPopup extends StatelessWidget {
  final bool isDark;
  final String mac;
  final String displayName;
  final Map<String, dynamic> rawDeviceData;
  final DeviceProvider provider;
  final VoidCallback? onRename;
  final String? fanEndpoint;
  final bool autoCheckFirmware;

  const DeviceSettingsPopup({
    super.key,
    required this.isDark, required this.mac, required this.displayName,
    required this.rawDeviceData, required this.provider,
    this.onRename, this.fanEndpoint, this.autoCheckFirmware = false,
  });

  static const Color tkGreen = Color(0xFF00A651);

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  @override
  Widget build(BuildContext context) {
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    // An toàn: build() của StatelessWidget này LÀ 1 pha build thật -> context.watch() nội bộ
    // của AppTranslations.of() hợp lệ; các closure bên dưới (kể cả trong ListenableBuilder)
    // dùng lại biến `t` này qua closure capture, không cần gọi lại .of(context) lần nữa.
    final t = AppTranslations.of(context);
    // [ĐỢT 13 — FIX TÀNG HÌNH] Dùng lại cho speedBtn bên dưới — cùng lý do _buildBtn của
    // SmartFanCard: nút tốc độ chưa chọn ở Sáng Thường cần nền xám để tách khối rõ.
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;

    // ---- BÓC GÓI SYSTEM THẬT TỪ REST (device_system:{mac} do firmware tự khai) ----
    final sysWrap = _asMap(rawDeviceData['system_data']);
    final sys = sysWrap.containsKey('system') ? _asMap(sysWrap['system']) : sysWrap;
    final network = _asMap(sys['network']);
    final metadata = _asMap(sys['metadata']);
    final String ip = (network['ip'] ?? network['local_ip'] ?? network['ip_address'] ?? '—').toString();
    final String ssid = (network['ssid'] ?? '').toString();
    final dynamic rssiRaw = network['rssi'] ?? network['wifi_signal'] ?? network['signal'];
    final String rssi = rssiRaw == null ? '—' : '$rssiRaw dBm';
    final String fwType = (rawDeviceData['fw_type'] ?? metadata['type'] ?? '').toString();
    final String fwVersion = (rawDeviceData['fw_version'] ?? metadata['fw_ver'] ?? '—').toString();
    // [DIGITAL TWIN — Đợt 23] category do Backend gắn (Schema-Driven UI) — "curtain" mở khối
    // hiệu chỉnh "Thời gian hành trình" riêng của Cửa cuốn.
    final String deviceCategory = (rawDeviceData['category'] ?? metadata['category'] ?? '').toString().toLowerCase();

    Widget specRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textSub),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: textSub, fontSize: 13)),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

    // [GLASS THEME] Dialog/AppContainer thủ công cũ ĐÃ BỎ khỏi build() của chính class này —
    // caller (showDeviceSettingsPopup) nay đưa thẳng DeviceSettingsPopup vào showAppDialog(
    // child: ...), showAppDialog tự cấp khung Dialog/kính bên ngoài. Giữ ConstrainedBox để
    // khóa đúng maxWidth 440 như cũ.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        color: Colors.transparent,
        // Nghe kho DPS: trạng thái online, tốc độ quạt, % OTA... đổi là popup vẽ lại tức thì
        child: ListenableBuilder(
              listenable: provider,
              builder: (context, _) {
                final live = provider.deviceOf(mac);
                final bool online = live?.online ??
                    ((rawDeviceData['status']?.toString().toLowerCase() ?? '') == 'online');

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------- TIÊU ĐỀ + TRẠNG THÁI SỐNG ----------
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: Icon(fanEndpoint != null ? Icons.all_out_rounded : Icons.settings_input_component_rounded, color: tkGreen, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(displayName, style: TextStyle(color: textMain, fontSize: 19, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? tkGreen : Colors.grey, shape: BoxShape.circle)),
                                  const SizedBox(width: 6),
                                  Text(online ? t.text('online') : t.text('offline'), style: TextStyle(color: online ? tkGreen : Colors.grey, fontSize: 12, fontWeight: FontWeight.w700)),
                                ]),
                              ],
                            ),
                          ),
                          IconButton(icon: Icon(Icons.close, color: textSub, size: 22), onPressed: () => Navigator.pop(context), splashRadius: 18),
                        ],
                      ),

                      // ---------- CỤM ĐIỀU KHIỂN QUẠT (đồng bộ hệt thẻ ngoài lưới) ----------
                      if (fanEndpoint != null) ...[
                        const SizedBox(height: 20),
                        Text(t.text('fan_control_header'), style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 10),
                        Builder(builder: (context) {
                          final int speed = live?.speedOf(fanEndpoint!) ?? 0;
                          final bool swing = live?.isSwinging(fanEndpoint!) ?? false;
                          final bool fanOn = speed > 0;

                          Widget speedBtn(int s, String label) {
                            final bool active = (speed == s) && online;
                            final bool isOffBtn = s == 0;
                            return Expanded(
                              child: Material(
                                color: active
                                    ? (isOffBtn ? Colors.redAccent.withValues(alpha: 0.85) : tkGreen.withValues(alpha: 0.85))
                                    : (isDark ? Colors.white10 : (isGlass ? Colors.black.withValues(alpha: 0.05) : Colors.grey.shade200)),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: online ? () => provider.setFanSpeed(mac, s, endpoint: fanEndpoint!, swing: swing) : null,
                                  child: Container(height: 40, alignment: Alignment.center, child: Text(label, style: TextStyle(color: active ? Colors.white : textMain, fontSize: 13, fontWeight: FontWeight.w900))),
                                ),
                              ),
                            );
                          }

                          final bool swingActive = swing && fanOn && online;
                          return Row(
                            children: [
                              speedBtn(0, 'OFF'), const SizedBox(width: 8),
                              speedBtn(1, '1'), const SizedBox(width: 8),
                              speedBtn(2, '2'), const SizedBox(width: 8),
                              speedBtn(3, '3'), const SizedBox(width: 12),
                              Material(
                                color: swingActive
                                    ? tkGreen.withValues(alpha: 0.85)
                                    : (isDark ? Colors.white10 : (isGlass ? Colors.black.withValues(alpha: 0.05) : Colors.grey.shade200)),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: (online && fanOn) ? () => provider.setFanSpeed(mac, speed, endpoint: fanEndpoint!, swing: !swing) : null,
                                  child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, child: Row(children: [Icon(Icons.threesixty, color: swingActive ? Colors.white : textMain, size: 16), const SizedBox(width: 4), Text('Xoay', style: TextStyle(color: swingActive ? Colors.white : textMain, fontSize: 12, fontWeight: FontWeight.w800))])),
                                ),
                              ),
                            ],
                          );
                        }),
                      ],

                      // ---------- THÔNG SỐ KỸ THUẬT THẬT (không mock) ----------
                      const SizedBox(height: 20),
                      Text(t.text('technical_specs_header'), style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      // [GIỮ NGUYÊN BIẾN ĐỘNG] mac/ip/rssi/ssid/fwType — giá trị thật từ thiết bị, chỉ nhãn dịch.
                      specRow(Icons.qr_code_2_rounded, t.text('mac_serial_label'), mac),
                      specRow(Icons.lan_rounded, t.text('lan_ip_label'), ip),
                      specRow(Icons.network_check_rounded, t.text('rssi_label'), rssi),
                      specRow(Icons.wifi_rounded, t.text('connected_wifi_label'), ssid.isEmpty ? '—' : ssid),
                      if (fwType.isNotEmpty) specRow(Icons.memory_rounded, t.text('firmware_branch_label'), fwType),

                      // ---------- TRẠNG THÁI KHI CÓ ĐIỆN (chỉ thiết bị có relay) ----------
                      // Cảm biến không có relay, Hub điều khiển thiết bị RF (tự nhớ qua LittleFS)
                      // -> hai dòng đó không hiện mục này
                      if (!fwType.contains('SENSOR') && !fwType.contains('HUB')) ...[
                        const SizedBox(height: 14),
                        Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                        PowerBehaviorSection(
                          mac: mac,
                          initialMode: int.tryParse(_asMap(rawDeviceData['settings'])['power_behavior']?.toString() ?? '') ?? 1,
                          isDark: isDark,
                        ),
                      ],

                      // ---------- [DIGITAL TWIN] THỜI GIAN HÀNH TRÌNH (chỉ Cửa cuốn) ----------
                      if (deviceCategory == 'curtain') ...[
                        const SizedBox(height: 14),
                        Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                        TravelTimeSection(
                          mac: mac,
                          initialSeconds: int.tryParse(_asMap(rawDeviceData['settings'])['travel_time_sec']?.toString() ?? '') ?? 0,
                          isDark: isDark,
                        ),
                      ],

                      // ---------- VÙNG FIRMWARE OTA ----------
                      const SizedBox(height: 14),
                      Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
                      DeviceFirmwareSection(
                        mac: mac,
                        fwType: fwType,
                        currentVersion: fwVersion,
                        provider: provider,
                        isDark: isDark,
                        autoCheck: autoCheckFirmware,
                      ),

                      // ---------- HÀNG NÚT DƯỚI ----------
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (onRename != null)
                            TextButton.icon(
                              onPressed: () { Navigator.pop(context); onRename!(); },
                              icon: Icon(Icons.edit_rounded, size: 18, color: textSub),
                              label: Text(t.text('rename_short_btn'), style: TextStyle(color: textSub, fontWeight: FontWeight.w600)),
                            ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: tkGreen, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            onPressed: () => Navigator.pop(context),
                            child: Text(t.text('close'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
    );
  }
}

// ============================================================================
// 🔌 KHỐI CÀI ĐẶT "TRẠNG THÁI KHI CÓ ĐIỆN" (nhúng trong Popup Cài đặt thiết bị)
// Chỉ hiện với thiết bị có relay (công tắc, quạt). Chọn 1 trong 3 chế độ:
//   0 = Nhớ trạng thái cũ | 1 = Luôn Tắt (mặc định xuất xưởng) | 2 = Luôn Bật
// Chọn xong -> PUT /api/devices/{mac}/power-behavior -> Backend lưu Redis + đẩy
// cấu hình xuống mạch qua MQTT (mạch ghi vào EEPROM, áp dụng từ lần có điện kế tiếp).
// ============================================================================
class PowerBehaviorSection extends StatefulWidget {
  final String mac;
  final int initialMode; // giá trị đã lưu trên server (settings.power_behavior)
  final bool isDark;

  const PowerBehaviorSection({super.key, required this.mac, required this.initialMode, required this.isDark});

  @override
  State<PowerBehaviorSection> createState() => _PowerBehaviorSectionState();
}

class _PowerBehaviorSectionState extends State<PowerBehaviorSection> {
  final Color tkGreen = const Color(0xFF00A651);
  late int _mode;
  bool _saving = false;

  // [ĐA NGÔN NGỮ] Không còn const — nhãn phải tra theo ngôn ngữ hiện tại, xem _labels(t).
  Map<int, String> _labels(AppTranslations t) => {
    0: t.text('remember_state_option'),
    1: t.text('always_off_option'),
    2: t.text('always_on_option'),
  };

  @override
  void initState() {
    super.initState();
    _mode = (widget.initialMode >= 0 && widget.initialMode <= 2) ? widget.initialMode : 1;
  }

  Future<void> _change(int? newMode) async {
    if (newMode == null || newMode == _mode || _saving) return;
    // Gọi từ DropdownButton.onChanged (tap handler) -> listen: false.
    final t = AppTranslations.of(context, listen: false);
    final int oldMode = _mode;
    // Đổi giao diện trước cho mượt, nhưng LƯU THẬT qua API — thất bại thì trả về như cũ
    setState(() { _mode = newMode; _saving = true; });
    final ok = await ApiService().setPowerBehavior(widget.mac, newMode);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã lưu "Khi có điện lại: ${_labels(t)[newMode]}" — mạch áp dụng từ lần mất điện kế tiếp.'),
        backgroundColor: const Color(0xFF00A651),
      ));
    } else {
      setState(() => _mode = oldMode);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không lưu được cài đặt — kiểm tra kết nối hoặc quyền tài khoản!'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color textMain = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final t = AppTranslations.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(Icons.power_rounded, color: textSub, size: 20),
      title: Text(t.text('power_on_state_label'), style: TextStyle(color: textMain, fontSize: 14)),
      subtitle: Text(t.text('relay_state_after_loss_label'), style: TextStyle(color: textSub, fontSize: 11)),
      trailing: _saving
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
          : DropdownButton<int>(
              value: _mode,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              dropdownColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
              style: TextStyle(color: tkGreen, fontSize: 13, fontWeight: FontWeight.bold),
              items: _labels(t).entries
                  .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: _change,
            ),
    );
  }
}

// ============================================================================
// 🚪 [DIGITAL TWIN — Đợt 23] KHỐI HIỆU CHỈNH "THỜI GIAN HÀNH TRÌNH" CỬA CUỐN
// (nhúng trong Popup Cài đặt thiết bị — CHỈ hiện khi category == "curtain")
// SmartRollingDoorCard dùng giá trị này (giây) để tính số mili-giây cần kích relay khi kéo
// Slider % — hiệu chỉnh đúng bằng thời gian thật cửa cuốn đi từ 0% đến 100% thì Slider mới
// khớp vị trí thật; chưa hiệu chỉnh (0) thì Card tự dùng giá trị mặc định 15 giây.
// ============================================================================
class TravelTimeSection extends StatefulWidget {
  final String mac;
  final int initialSeconds; // 0 = chưa hiệu chỉnh — Card tự dùng mặc định 15s
  final bool isDark;

  const TravelTimeSection({super.key, required this.mac, required this.initialSeconds, required this.isDark});

  @override
  State<TravelTimeSection> createState() => _TravelTimeSectionState();
}

class _TravelTimeSectionState extends State<TravelTimeSection> {
  final Color tkGreen = const Color(0xFF00A651);
  late int _seconds;
  bool _saving = false;

  static const int _minSec = 3;
  static const int _maxSec = 120;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds > 0 ? widget.initialSeconds.clamp(_minSec, _maxSec) : 15;
  }

  Future<void> _change(int delta) async {
    if (_saving) return;
    final int newVal = (_seconds + delta).clamp(_minSec, _maxSec);
    if (newVal == _seconds) return;
    final int oldVal = _seconds;
    setState(() { _seconds = newVal; _saving = true; });
    final ok = await ApiService().setDeviceSetting(widget.mac, 'travel_time_sec', newVal.toString());
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      setState(() => _seconds = oldVal);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không lưu được Thời gian hành trình — kiểm tra kết nối hoặc quyền tài khoản!'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color textMain = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = widget.isDark ? Colors.white54 : const Color(0xFF64748B);
    final t = AppTranslations.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(Icons.timer_outlined, color: textSub, size: 20),
      title: Text(t.text('travel_time_label'), style: TextStyle(color: textMain, fontSize: 14)),
      subtitle: Text(t.text('travel_time_desc'), style: TextStyle(color: textSub, fontSize: 11)),
      trailing: _saving
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: Icon(Icons.remove_circle_outline_rounded, color: textSub, size: 20), onPressed: () => _change(-1), splashRadius: 18),
                SizedBox(
                  width: 44,
                  child: Text('${_seconds}s', textAlign: TextAlign.center, style: TextStyle(color: tkGreen, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                IconButton(icon: Icon(Icons.add_circle_outline_rounded, color: textSub, size: 20), onPressed: () => _change(1), splashRadius: 18),
              ],
            ),
    );
  }
}

// ============================================================================
// 📦 KHỐI QUẢN LÝ FIRMWARE OTA (nhúng trong Popup Cài đặt thiết bị)
// Luồng thật 3 tầng: [Kiểm tra cập nhật] -> GET /api/firmware/check (200 = có bản mới,
// 304 = mới nhất) -> [Cập nhật ngay vX] -> POST /api/devices/{mac}/ota -> Backend bắn
// MQTT xuống chip -> chip tự tải .bin + kiểm MD5/SHA256 + báo % qua ota/progress -> thanh
// tiến trình realtime (đọc từ kho DPS của DeviceProvider, không mock).
// ============================================================================

/// [DỊCH LỖI OTA HẠT NHÂN] Mã ngắn firmware gửi lên (khớp otaFail()/publishOtaProgress()
/// trong C++, namespace chuẩn hóa `ERR_*` — kiến trúc Zero-Trust OTA 2026-07) -> câu tiếng
/// Việt CHUẨN XÁC, có hướng dẫn hành động cho người dùng cuối. Khóa map ở đây là mã ĐÃ BỎ
/// tiền tố "ERR_" (otaErrorMessageVi tự chuẩn hóa trước khi tra) để dùng chung được với
/// firmware CŨ (trước bản vá này) vẫn còn gửi mã KHÔNG có tiền tố "ERR_" trong lúc chờ
/// người dùng OTA lên bản mới nhất. Không đủ trong bảng (vd firmware bản mới thêm mã lạ)
/// -> vẫn hiện được, không rơi vào im lặng hay crash — xem otaErrorMessageVi bên dưới.
const Map<String, String> kOtaErrorMessages = {
  // ===== TRỤ CỘT 1 — Zero-Trust / toàn vẹn file =====
  'SIGNATURE_MISMATCH':
      'Chữ ký số của firmware không khớp — file có thể đã bị can thiệp trên đường truyền. '
      'Thiết bị đã TỪ CHỐI cài đặt và vẫn chạy bản cũ an toàn. Vui lòng thử tải lại từ máy chủ chính thức.',
  'SHA256_MISMATCH': 'File tải về không khớp mã xác thực — có thể bị hỏng hoặc bị can thiệp giữa đường. '
      'Thiết bị đã hủy cài đặt, vẫn chạy bản cũ an toàn.',
  'NO_INTEGRITY_HASH': 'Máy chủ không gửi mã xác thực (chữ ký/MD5/SHA256) — thiết bị từ chối nạp để an toàn.',
  'MD5_INVALID': 'Mã xác thực (MD5) máy chủ gửi không đúng định dạng.',
  // ===== TRỤ CỘT 2 — Anti-Brick / Self-Healing =====
  'ROLLBACK_ACTIVATED':
      'Thiết bị vừa cập nhật firmware nhưng không ổn định (không kết nối lại được WiFi/máy chủ) '
      'nên đã TỰ ĐỘNG lùi về bản chạy trước đó để tránh treo cứng. Vui lòng kiểm tra lại mật khẩu WiFi '
      'hoặc liên hệ hỗ trợ trước khi thử cập nhật lại.',
  'PARTITION_FULL': 'File firmware lớn hơn dung lượng bộ nhớ còn trống của thiết bị.',
  // ===== TRỤ CỘT 3 — Mạng / tải file =====
  'LOW_MEMORY_TLS': 'Thiết bị đang thiếu bộ nhớ trống để mở kết nối bảo mật (TLS) — vui lòng thử lại sau ít phút '
      'hoặc khởi động lại thiết bị.',
  'NETWORK_TIMEOUT': 'Mất kết nối mạng giữa chừng khi đang tải firmware — có thể do WiFi nhà bạn yếu hoặc chập chờn. '
      'Thiết bị vẫn giữ bản cũ an toàn, hãy thử lại khi mạng ổn định.',
  'HTTP_BEGIN_FAILED': 'Không dựng được kết nối tới máy chủ tải firmware — kiểm tra đường link tải.',
  'HTTP_CONNECT_FAILED': 'Không kết nối được máy chủ — có thể do mạng nhà bạn hoặc máy chủ đang gặp sự cố.',
  'SIZE_UNKNOWN': 'Máy chủ không trả về kích thước file hợp lệ.',
  'INSUFFICIENT_SPACE': 'File firmware lớn hơn dung lượng bộ nhớ còn trống của thiết bị.',
  'DOWNLOAD_INCOMPLETE': 'Mất kết nối giữa chừng khi đang tải — thiết bị vẫn giữ bản cũ an toàn.',
  // ===== Flash / kích hoạt =====
  'UPDATE_BEGIN_FAILED': 'Thiết bị không cấp phát được vùng nhớ để chuẩn bị nạp.',
  'UPDATE_WRITE_FAILED': 'Lỗi ghi dữ liệu vào bộ nhớ flash trong lúc nạp.',
  'UPDATE_END_FAILED': 'Xác thực cuối cùng thất bại (thường do sai mã MD5) — thiết bị giữ nguyên bản cũ.',
};

/// [null-safe, không crash] code null/lạ vẫn trả về câu hiển thị được. Tự chuẩn hóa cả mã
/// mới (tiền tố "ERR_", vd "ERR_SIGNATURE_MISMATCH") lẫn mã cũ (không tiền tố, vd
/// "SIGNATURE_MISMATCH") về cùng một khóa tra cứu — tương thích cả firmware trước/sau khi
/// vá Zero-Trust OTA.
String otaErrorMessageVi(String? code, String? detail) {
  String base;
  if (code == null || code.isEmpty) {
    base = 'Nạp thất bại không rõ nguyên nhân — thiết bị vẫn chạy bản cũ an toàn.';
  } else {
    final String bare = code.startsWith('ERR_') ? code.substring(4) : code;
    if (kOtaErrorMessages.containsKey(bare)) {
      base = kOtaErrorMessages[bare]!;
    } else if (bare.startsWith('HTTP_STATUS_')) {
      base = 'Máy chủ trả lỗi HTTP ${bare.substring('HTTP_STATUS_'.length)} khi tải file firmware.';
    } else {
      base = 'Lỗi không xác định ($code) — thiết bị vẫn chạy bản cũ an toàn.';
    }
  }
  return (detail != null && detail.isNotEmpty) ? '$base\n($detail)' : base;
}

class DeviceFirmwareSection extends StatefulWidget {
  final String mac;
  final String fwType;         // dòng firmware học từ heartbeat (SMART_SWITCH, SMART_FAN_CTRL...)
  final String currentVersion; // phiên bản đang chạy, đọc từ gói system thật
  final DeviceProvider provider;
  final bool isDark;
  final bool autoCheck;        // true khi mở từ deeplink chuông thông báo -> tự check ngay

  const DeviceFirmwareSection({super.key, required this.mac, required this.fwType, required this.currentVersion, required this.provider, required this.isDark, this.autoCheck = false});

  @override
  State<DeviceFirmwareSection> createState() => _DeviceFirmwareSectionState();
}

class _DeviceFirmwareSectionState extends State<DeviceFirmwareSection> {
  final Color tkGreen = const Color(0xFF00A651);
  bool _checking = false;
  bool _updating = false;
  String? _newVersion;   // != null khi kho có bản mới hơn
  String? _statusNote;   // thông báo ngắn dưới nút

  @override
  void initState() {
    super.initState();
    // Người dùng đến từ tin "Có bản cập nhật Firmware": check luôn để nút
    // "Cập nhật ngay (vX)" hiện ra ngay, khỏi phải bấm thêm một lần
    if (widget.autoCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _checkUpdate(); });
    }
  }

  Future<void> _checkUpdate() async {
    if (widget.fwType.isEmpty) {
      setState(() => _statusNote = 'Chưa nhận diện dòng firmware (chờ heartbeat)');
      return;
    }
    setState(() { _checking = true; _statusNote = null; });
    final meta = await ApiService().checkFirmwareUpdate(widget.fwType, widget.currentVersion);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (meta != null && (meta['version'] ?? '').toString().isNotEmpty) {
        _newVersion = meta['version'].toString();
        _statusNote = null;
      } else {
        _newVersion = null;
        _statusNote = 'Đang ở phiên bản mới nhất';
      }
    });
  }

  Future<void> _startUpdate() async {
    setState(() { _updating = true; _statusNote = null; });
    final ok = await ApiService().triggerOtaUpdate(widget.mac);
    if (!mounted) return;
    if (!ok) setState(() { _updating = false; _statusNote = 'Không ra lệnh được — thiết bị Ngoại tuyến?'; });
  }

  @override
  Widget build(BuildContext context) {
    final Color textMain = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = widget.isDark ? Colors.white54 : const Color(0xFF64748B);

    // Nghe kho DPS realtime: thiết bị báo % nạp qua smarthub/{home}/{mac}/ota/progress
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final t = AppTranslations.of(context);
        final device = widget.provider.deviceOf(widget.mac);
        final int? progress = device?.otaProgress;
        final bool inProgress = _updating && progress != null && progress >= 0 && progress < 100;
        final bool done = progress == 100;
        final bool failed = progress == -1;
        // [DỊCH LỖI OTA] App KHÔNG tự đoán trạng thái — chỉ dịch đúng mã/câu thiết bị
        // đã gửi qua {mac}/ota/progress (error_code/error), null-safe khi thiếu dữ liệu.
        final String? otaErrorText =
            failed ? otaErrorMessageVi(device?.otaErrorCode, device?.otaErrorDetail) : null;

        Widget trailing;
        if (done) {
          trailing = Text('Hoàn tất ✓', style: TextStyle(color: tkGreen, fontSize: 13, fontWeight: FontWeight.bold));
        } else if (_updating && !failed) {
          trailing = Text('${progress ?? 0}%', style: TextStyle(color: tkGreen, fontSize: 13, fontWeight: FontWeight.bold));
        } else if (_checking) {
          trailing = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen));
        } else if (_newVersion != null) {
          trailing = TextButton(
            onPressed: _startUpdate,
            style: TextButton.styleFrom(backgroundColor: tkGreen.withValues(alpha: 0.15), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            // [GIỮ NGUYÊN BIẾN ĐỘNG] v$_newVersion — số phiên bản thật từ server, chỉ nhãn dịch.
            child: Text('${t.text('update_now')} (v$_newVersion)', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 13)),
          );
        } else {
          trailing = TextButton(
            onPressed: _checkUpdate,
            style: TextButton.styleFrom(backgroundColor: tkGreen.withValues(alpha: 0.15), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            child: Text(t.text('check_update_btn'), style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 13)),
          );
        }

        return Column(
          children: [
            ListTile(
              leading: Icon(Icons.system_update_alt, color: textSub, size: 20),
              title: Text('Firmware v${widget.currentVersion}', style: TextStyle(color: textMain, fontSize: 14)),
              subtitle: failed
                  ? Text(otaErrorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 11))
                  : (_statusNote != null ? Text(_statusNote!, style: TextStyle(color: textSub, fontSize: 11)) : null),
              trailing: trailing,
            ),
            if (inProgress)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress / 100.0,
                    minHeight: 6,
                    color: tkGreen,
                    backgroundColor: widget.isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
