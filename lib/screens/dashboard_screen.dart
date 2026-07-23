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
import '../services/push_notification_service.dart';
import 'settings/notification_settings_screen.dart';
import 'tuya/tuya_link_screen.dart';
import 'cameras/camera_dashboard_section.dart';
import '../models/imou_camera_model.dart';
import '../models/camera_model.dart';
import 'auth/login_screen.dart';
import 'admin/role_management_view.dart';
import 'admin/admin_system_screen.dart';
import 'admin/device_management_screen.dart';
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
import 'package:reorderables/reorderables.dart'; // [GIAI ĐOẠN 75 — ReorderableWrap: thẻ khác kích thước]
import 'dart:math' show Random;
import 'automation/automation_screen.dart';
import 'automation/create_automation_screen.dart';
import 'devices/device_timer_screen.dart';
import 'devices/device_history_screen.dart';
import '../widgets/share_device_dialog.dart';
import '../widgets/ownership_conflict_dialog.dart'; // [LUỒNG CHUYỂN GIAO] Dialog 409 dùng chung
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:lottie/lottie.dart';
// [GỠ flutter_staggered_grid_view] Bin-packing của StaggeredGrid phá vỡ thứ tự kéo-thả — đã
// thay bằng Wrap thuần (xem _buildAvatarStaggeredGrid) để tôn trọng tuyệt đối thứ tự mảng.
import '../models/device_avatar_definition.dart';
import '../models/device_avatars_repo.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'energy/full_energy_dashboard_screen.dart';

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
  // [ĐẨY THÔNG BÁO OS — DEEPLINK] Mang dữ liệu từ PushNotificationService khi user mở App
  // bằng cách bấm vào 1 thông báo hệ thống (cả 2 trường hợp: App đang nền, và App đã bị
  // kill hẳn — lúc đó DashboardScreen còn chưa hề tồn tại nên KHÔNG thể gọi thẳng các hàm
  // deeplink private _openDeviceSettingsByMac/_showUpdateDialog từ bên ngoài, phải đi qua
  // constructor rồi tự trigger trong _bootstrapSync() SAU KHI _currentHomeDevices đã nạp
  // xong). null = mở App bình thường, không có gì để deeplink.
  final String? initialDeeplinkMac;
  final String? initialDeeplinkType;
  final String? initialDeeplinkVersion;
  final String? initialDeeplinkChangelog;

  const DashboardScreen({
    super.key,
    this.initialDeeplinkMac,
    this.initialDeeplinkType,
    this.initialDeeplinkVersion,
    this.initialDeeplinkChangelog,
  });
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
  int _selectedIndex = 0;
  bool _isLoadingDevices = true;
  // [CAMERA IP — PHẦN 3] Danh sách camera của nhà đang mở, nạp qua ApiService().getCameras()
  // trong _bootstrapSync() (cùng lúc với khởi tạo khác) — xem _loadCameras().
  List<CameraModel> _cameras = [];
  // [CAMERA P2P — IMOU] Danh sách camera Imou của nhà đang mở, nạp song song _cameras trong
  // _loadCameras() — chế độ lưới/player thật nay nằm trong
  // cameras/camera_dashboard_section.dart (đã gộp chung 1 lưới với RTSP).
  List<ImouCameraModel> _imouCameras = [];
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

  // [BƯỚC 5 — DEVICE AVATAR BLUEPRINT] deviceKey (mac_endpoint) -> DeviceAvatarDefinition.id đã
  // gán qua popup "Thay đổi giao diện (Avatar)". Không có entry = dùng card mặc định (SmartXCard).
  // Chỉ đổi GIAO DIỆN hiển thị — KHÔNG đụng logic điều khiển/dữ liệu thiết bị thật.
  final Map<String, String> _deviceAvatarId = {};

  // [GIAI ĐOẠN 125 — GỘP/TÁCH CÔNG TẮC ĐA KÊNH DO NGƯỜI DÙNG TỰ CHỌN] mac (KHÔNG phải hideKey —
  // đây là lựa chọn CẤP THIẾT BỊ, áp dụng chung cho mọi kênh) -> true = hiển thị GỘP thành 1 khối
  // mặt công tắc (PhysicalSwitchBlockCard qua popup, xem Giai đoạn 115-123); false/vắng mặt =
  // BUNG LẺ từng kênh thành thẻ SmartSwitchCard rời (hành vi mặc định TỪ TRƯỚC Giai đoạn 115, xem
  // yêu cầu tường minh — is_grouped vắng mặt = false). Đồng bộ máy khác qua avatar_map CÙNG kênh
  // device_settings:{MAC} (key riêng "is_grouped", xem allowedDeviceSettingKeys phía Backend).
  final Map<String, bool> _deviceGrouped = {};

  /// [LAN SCAN] Tập MAC đã sở hữu trong nhà đang mở (đã chuẩn hóa HOA + bỏ ":") —
  /// truyền vào AddDeviceDialog để ẩn nút "Thêm ngay" với thiết bị đã có.
  Set<String> get _ownedMacs => _currentHomeDevices
      .map((d) => (d['mac_address'] ?? d['mac'] ?? '').toString().replaceAll(':', '').toUpperCase())
      .where((m) => m.isNotEmpty)
      .toSet();
  Map<String, dynamic>? _selectedHomeForSuperUser;
  final Color tkGreen = const Color(0xFF00A651);
  // [FIX NỔI BẬT MỤC ĐANG CHỌN — Sidebar/Drawer Kính] tkGreen gốc (0xFF00A651) làm chữ/icon
  // MỤC ĐANG CHỌN hơi trầm khi đặt trên nền kính tối — dùng riêng bản sáng hơn (neon) chỉ cho
  // chữ/icon Active State, KHÔNG đổi nền tint/viền (giữ nguyên tkGreen.withValues(alpha: ...)
  // ở decoration như thiết kế cũ).
  final Color tkGreenNeon = const Color(0xFF3DF2A0);

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
    _loadDeviceAvatars();
    _loadDeviceGrouped();
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

    // [ĐẨY THÔNG BÁO OS] Chỉ Android/iOS thật có FCM — Desktop/Web bỏ qua hẳn.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      PushNotificationService.registerWithBackend();
    }

    // [PUSH — DEEPLINK KHỞI ĐỘNG LẠNH] App vừa mở do user bấm vào 1 thông báo hệ thống khi
    // App đang bị kill hẳn — widget.initialDeeplinkMac mang theo từ constructor (xem
    // PushNotificationService._handleTapData). PHẢI chạy SAU _initializeHome() phía trên vì
    // _openDeviceSettingsByMac() tra cứu trong _currentHomeDevices vừa nạp xong.
    final String? deeplinkMac = widget.initialDeeplinkMac;
    if (deeplinkMac != null && deeplinkMac.isNotEmpty) {
      if (widget.initialDeeplinkType == 'OTA_UPDATE') {
        _showUpdateDialog(deeplinkMac, widget.initialDeeplinkVersion ?? '', widget.initialDeeplinkChangelog ?? '');
      } else {
        _openDeviceSettingsByMac(deeplinkMac);
      }
    }

    // [CAMERA IP — PHẦN 3] currentHomeId đã có giá trị thật sau _initializeHome() phía trên.
    _loadCameras();
  }

  /// [CAMERA IP — PHẦN 3] Nạp danh sách camera của nhà đang mở. Lỗi mạng/HTTP -> giữ nguyên
  /// danh sách CŨ trên màn hình thay vì xóa trắng (getCameras trả null phân biệt với [] rỗng
  /// thật — cùng quy ước getGridLayout đã có trong ApiService).
  Future<void> _loadCameras() async {
    if (currentHomeId.isEmpty) return;
    // [FIX — camera "biến mất"/lạc nhà, CÙNG HỌ BUG với Tuya "ALL_SYSTEM"] currentHomeId là
    // placeholder JWT ("ALL_SYSTEM") với tài khoản SUPER_USER — PHẢI dùng _provisioningTargetHomeId
    // (đúng công thức nhà đích đã áp cho Tuya/AP Mode) để camera gắn đúng nhà SUPER_USER đang xem.
    final String targetHomeId = _provisioningTargetHomeId;
    final result = await ApiService().getCameras(targetHomeId);
    if (mounted && result != null) setState(() => _cameras = result);
    final imouResult = await ApiService().getImouCameras(targetHomeId);
    if (mounted && imouResult != null) setState(() => _imouCameras = imouResult);
  }

  /// [CHUYỂN NHÀ] HomeProvider.activeHomeId đổi (HomeCard gọi setActiveHome() khi user bấm
  /// "Vào điều khiển" ở màn Quản lý Nhà) -> nhảy về tab Bảng điều khiển NGAY LẬP TỨC + refetch
  /// thiết bị của nhà mới. HomeCard KHÔNG tự điều hướng — chỉ đổi data, Dashboard tự phản ứng.
  void _onActiveHomeChanged() {
    final newId = _homeProviderRef?.activeHomeId;
    if (newId == null || newId == _lastKnownActiveHomeId || !mounted) return;
    _lastKnownActiveHomeId = newId;
    setState(() { _selectedIndex = 0; _cameras = []; _imouCameras = []; });
    _initializeHome();
    _loadCameras();
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

  /// [BƯỚC 5] Nạp lại bảng gán Avatar (deviceKey -> avatarId) — SharedPreferences không hỗ trợ
  /// Map trực tiếp nên lưu dưới dạng 1 chuỗi JSON (cùng kỹ thuật dart:convert đã import sẵn cho
  /// luồng giải mã JWT phía trên, không cần thêm import mới).
  Future<void> _loadDeviceAvatars() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('device_avatar_map');
    if (raw == null || raw.isEmpty) return;
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      if (mounted) setState(() => _deviceAvatarId.addAll(decoded.map((k, v) => MapEntry(k, v.toString()))));
    } catch (e) {
      if (kDebugMode) print('⚠️ [AVATAR] Lỗi đọc device_avatar_map đã lưu: $e — bỏ qua, dùng card mặc định.');
    }
  }

  /// Ghi bảng gán Avatar xuống Local Storage ngay khi có thay đổi (chọn mới/trả về mặc định).
  void _persistDeviceAvatars() {
    SharedPreferences.getInstance().then((p) => p.setString('device_avatar_map', jsonEncode(_deviceAvatarId)));
  }

  /// [GIAI ĐOẠN 125] Nạp lại lựa chọn Gộp/Tách (mac -> bool) — cùng kỹ thuật JSON string với
  /// _loadDeviceAvatars ở trên (SharedPreferences không hỗ trợ Map trực tiếp).
  Future<void> _loadDeviceGrouped() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('device_grouped_map');
    if (raw == null || raw.isEmpty) return;
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      if (mounted) setState(() => _deviceGrouped.addAll(decoded.map((k, v) => MapEntry(k, v == true))));
    } catch (e) {
      if (kDebugMode) print('⚠️ [GỘP/TÁCH] Lỗi đọc device_grouped_map đã lưu: $e — bỏ qua, mặc định bung lẻ.');
    }
  }

  /// Ghi lựa chọn Gộp/Tách xuống Local Storage ngay khi có thay đổi.
  void _persistDeviceGrouped() {
    SharedPreferences.getInstance().then((p) => p.setString('device_grouped_map', jsonEncode(_deviceGrouped)));
  }

  /// [GIAI ĐOẠN 125] Đổi lựa chọn Gộp/Tách cho MỘT thiết bị đa kênh — cập nhật State NGAY (vẽ lại
  /// lưới tức thì) + lưu cục bộ + đồng bộ Server qua kênh device_settings chung (giống avatar_map).
  void _setDeviceGrouped(String mac, bool grouped) {
    setState(() => _deviceGrouped[mac] = grouped);
    _persistDeviceGrouped();
    ApiService().setDeviceSetting(mac, 'is_grouped', grouped.toString());
  }

  // ==========================================================================
  // 🔗 [FIX ĐỨT GÃY LUỒNG DỮ LIỆU] Thứ tự kéo-thả — CACHE CỤC BỘ là nguồn sự thật cho HIỂN THỊ
  // ==========================================================================
  // [TẠI SAO THÊM LỚP NÀY] Trước bản vá này, `_currentHomeDevices = devices;` (trong
  // _fetchDevicesForHome) gán THẲNG danh sách REST vào state — KHÔNG hề sắp lại theo thứ tự đã
  // lưu. Toàn bộ "trí nhớ" về thứ tự kéo-thả phụ thuộc 100% vào việc Backend (applyDeviceOrder(),
  // code Go — KHÔNG nằm trong repo Flutter này, không kiểm chứng được từ đây) có thật sự sắp lại
  // đúng trước khi trả REST hay không. Nếu Backend trả sai thứ tự (bug/cache/quên áp) — kể cả khi
  // request Lưu trước đó đã 200 OK — _handleRefresh() gọi NGAY sau khi Lưu (để đối chiếu nền) sẽ
  // ÂM THẦM GHI ĐÈ thứ tự vừa kéo-thả bằng thứ tự sai đó, đúng cảm giác "kéo thả không hoạt động"
  // dù code Flutter/luồng gọi API hoàn toàn đúng. Nay lưu thêm 1 bản CỤC BỘ (SharedPreferences,
  // theo từng home) và ÁP LẠI bản này lên MỌI danh sách thiết bị vừa nạp — tại ĐÚNG MỘT nơi
  // (_fetchDevicesForHome, nơi duy nhất gán _currentHomeDevices từ REST) — nên dù Backend có trả
  // đúng hay sai, máy NÀY luôn hiển thị đúng thứ tự người dùng đã kéo gần nhất. Gọi API Backend
  // vẫn giữ nguyên (đồng bộ nền cho phiên đăng nhập khác/thiết bị khác), chỉ không còn là ĐIỀU
  // KIỆN DUY NHẤT để thứ tự "dính" trên chính máy này nữa.
  Future<List<String>> _loadLocalDeviceOrder(String homeId) async {
    if (homeId.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('device_order_$homeId') ?? [];
  }

  void _persistLocalDeviceOrder(String homeId, List<String> orderedMacs) {
    if (homeId.isEmpty) return;
    SharedPreferences.getInstance().then((p) => p.setStringList('device_order_$homeId', orderedMacs));
  }

  // ==========================================================================
  // 🧩 [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Bố cục lưới — SONG SONG với
  // device_order_$homeId ở trên, KHÔNG thay thế. Rỗng ([]) = người dùng CHƯA từng dùng tính năng
  // "khoảng trống" -> mọi nơi đọc _gridLayoutSlots phải tự rơi về hành vi cũ (macOrderRank/Wrap
  // tetris-fill sẵn có, xem _buildDevicesGridBody) — cùng triết lý "local-first, đồng bộ nền" đã
  // áp dụng cho device_order (_loadLocalDeviceOrder/_persistLocalDeviceOrder ở trên).
  // ==========================================================================
  Future<List<String>> _loadLocalGridLayout(String homeId) async {
    if (homeId.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('grid_layout_$homeId') ?? [];
  }

  void _persistLocalGridLayout(String homeId, List<String> slots) {
    if (homeId.isEmpty) return;
    SharedPreferences.getInstance().then((p) => p.setStringList('grid_layout_$homeId', slots));
  }

  /// Sắp [devices] TẠI CHỖ theo [orderedMacs] (rank theo vị trí xuất hiện; MAC lạ/chưa từng kéo
  /// rơi xuống cuối, giữ nguyên thứ tự tự nhiên giữa chúng) — dùng CHUNG cho mọi điểm nạp danh
  /// sách thiết bị để đảm bảo nhất quán 1 công thức sắp xếp duy nhất trong toàn bộ luồng.
  void _applyLocalDeviceOrder(List<dynamic> devices, List<String> orderedMacs) {
    if (orderedMacs.isEmpty) return;
    String macOf(dynamic d) => (d['mac_address'] ?? d['mac'] ?? '').toString().replaceAll(':', '').toUpperCase();
    devices.sort((a, b) {
      final int ra = orderedMacs.indexOf(macOf(a));
      final int rb = orderedMacs.indexOf(macOf(b));
      final int rankA = ra == -1 ? orderedMacs.length : ra;
      final int rankB = rb == -1 ? orderedMacs.length : rb;
      return rankA.compareTo(rankB);
    });
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

           // [ĐỒNG BỘ AVATAR LÊN SERVER — ĐỌC] device['settings']['avatar_map'] là JSON phẳng
           // {endpoint: avatarId} Backend trả về nguyên văn từ Redis hash device_settings:{MAC}
           // (xem DeviceListItem.Settings ở dashboard_handler.go — ĐÃ có sẵn, không cần API mới).
           // Chỉ hydrate khi field NÀY TỒN TẠI (khác null) — MAC chưa từng đồng bộ (avatar cũ chỉ
           // gán cục bộ trước khi tính năng này ra đời) thì ĐỂ NGUYÊN _deviceAvatarId đã nạp từ
           // SharedPreferences lúc initState, không ghi đè mất lựa chọn cũ của chính máy này.
           final String devMacNorm = devMac.replaceAll(':', '').toUpperCase();
           final dynamic rawAvatarMap = (device['settings'] as Map?)?['avatar_map'];
           if (devMacNorm.isNotEmpty && rawAvatarMap is String) {
             // Field tồn tại (kể cả rỗng/"{}" = đã gỡ hết) -> Server giờ là NGUỒN SỰ THẬT cho MAC
             // này, XÓA SẠCH entry cũ của MAC trước khi nạp lại — đồng bộ đúng cả trường hợp GỠ
             // avatar từ một máy/người dùng khác trong cùng nhà.
             _deviceAvatarId.removeWhere((k, _) => k.startsWith('${devMacNorm}_'));
             if (rawAvatarMap.isNotEmpty) {
               try {
                 final Map<String, dynamic> decoded = jsonDecode(rawAvatarMap);
                 decoded.forEach((endpoint, avatarId) {
                   if (avatarId is String && avatarId.isNotEmpty) {
                     _deviceAvatarId['${devMacNorm}_$endpoint'] = avatarId;
                   }
                 });
               } catch (e) {
                 if (kDebugMode) print('⚠️ [AVATAR SYNC] Lỗi giải mã avatar_map của $devMacNorm: $e');
               }
             }
           }

           // [GIAI ĐOẠN 125 — GỘP/TÁCH — ĐỌC] device['settings']['is_grouped'] ("true"/"false",
           // vắng mặt = mặc định false/bung lẻ theo đúng yêu cầu). Cùng triết lý với avatar_map:
           // CHỈ ghi đè khi field THẬT SỰ có mặt trong response — máy chưa từng đồng bộ (hoặc mất
           // mạng) giữ nguyên lựa chọn cục bộ đã nạp từ SharedPreferences, không bị reset về false.
           final dynamic rawIsGrouped = (device['settings'] as Map?)?['is_grouped'];
           if (devMacNorm.isNotEmpty && rawIsGrouped != null) {
             _deviceGrouped[devMacNorm] = rawIsGrouped.toString() == 'true';
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

        // [FIX ĐỨT GÃY LUỒNG DỮ LIỆU — BƯỚC 1 "ĐỌC"] ÁP LẠI thứ tự kéo-thả đã lưu cục bộ TRƯỚC
        // khi gán vào state — đây là MỘT nơi DUY NHẤT mọi lượt nạp thiết bị (khởi động app, pull-
        // to-refresh, silent refresh sau khi Lưu kéo-thả) đều đi qua, nên vá đúng ở đây đảm bảo
        // nhất quán tuyệt đối bất kể Backend có tự sắp đúng hay không (xem giải thích đầy đủ ở
        // _loadLocalDeviceOrder).
        final List<String> localOrder = await _loadLocalDeviceOrder(homeId);
        _applyLocalDeviceOrder(devices, localOrder);

        // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Nạp cục bộ TRƯỚC (đồng bộ, không chờ
        // mạng) — cùng triết lý "local-first" đã áp cho device_order ở trên. Đồng bộ NỀN với
        // Server ngay sau (KHÔNG await — 1 field tuỳ chọn không được phép chặn hiển thị dashboard
        // chính), tự vá lại _gridLayoutSlots nếu Server có bản mới hơn (vd vừa đổi từ máy khác).
        final List<String> localGridLayout = await _loadLocalGridLayout(homeId);
        if (localGridLayout.isNotEmpty) _gridLayoutSlots = localGridLayout;
        ApiService().getGridLayout(homeId).then((serverSlots) {
          if (!mounted || serverSlots == null) return;
          // Đã chuyển sang nhà khác trong lúc chờ mạng -> bỏ, tránh gán nhầm bố cục nhà khác.
          if (_provisioningTargetHomeId != homeId) return;
          _persistLocalGridLayout(homeId, serverSlots);
          setState(() => _gridLayoutSlots = serverSlots);
        });

        // [ĐỒNG BỘ AVATAR LÊN SERVER] _deviceAvatarId vừa được vá lại (có thể) ở vòng lặp trên —
        // ghi luôn xuống SharedPreferences để lần mở App kế tiếp (kể cả OFFLINE, chưa kịp fetch)
        // vẫn thấy đúng avatar mới nhất đã đồng bộ, không phải đợi round-trip mạng lần nữa.
        _persistDeviceAvatars();
        // [GIAI ĐOẠN 125] Cùng lý do — _deviceGrouped vừa được vá lại ở vòng lặp trên.
        _persistDeviceGrouped();

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

  // [ĐỢT 25 — DIRECT MAC BINDING] Nhà đích để truyền vào AddDeviceDialog.homeId — CÙNG công
  // thức "Nhà đích" mà _linkScannedDevice bên dưới đã dùng cho luồng QR/Nhập tay/Quét LAN,
  // tách thành getter riêng để AddDeviceDialog (luồng AP Mode) dùng được TRƯỚC khi user chọn
  // xong MAC (dialog cần homeId ngay lúc khởi tạo, không đợi tới lúc trả kết quả).
  String get _provisioningTargetHomeId => (userRole == 'SUPER_USER' && _selectedHomeForSuperUser != null)
      ? _selectedHomeForSuperUser!['home_id'].toString()
      : currentHomeId;

  // ==========================================================================
  // ↕️ [GIAI ĐOẠN 75 — REWRITE #2] KÉO-THẢ TẠI CHỖ DÙNG ĐÚNG THẺ GỐC (không tráo icon nữa)
  // ==========================================================================
  // [TẠI SAO ĐỔI TIẾP TỪ BẢN LƯỚI ICON ĐỒNG NHẤT] Bản trước (Giai đoạn 72 rewrite) mô phỏng iOS
  // Jiggle bằng cách hiện Ô icon+tên tĩnh khi sửa — đúng cơ chế iOS thật nhưng người dùng từ chối:
  // yêu cầu rõ ràng là giữ NGUYÊN hình dáng/kích thước THẬT của từng thẻ (SmartFanCard/
  // SmartRollingDoorCard/SmartSwitchCard...), chỉ thêm rung + khóa chạm. Bản này đáp ứng đúng.
  //
  // [KIẾN TRÚC — TẠI SAO KHÔNG SỬA THẲNG return Column(...) CỦA _buildDevicesGridBody]
  // Khối render bình thường (~300 dòng, nhiều vòng lặp dịch DPS phức tạp đã tinh chỉnh lâu dài)
  // RỦI RO CAO nếu tái cấu trúc tại chỗ. Thay vào đó: nhánh edit-mode là một hàm HOÀN TOÀN CỘNG
  // THÊM (_buildInPlaceEditWrap) — nhận CHÍNH các danh sách visibleFans/visibleSensors/...  đã
  // tính sẵn (không đụng logic tính chúng), tự dựng lại ĐÚNG các Widget thẻ gốc (cùng constructor
  // y hệt khối render bình thường) rồi xếp vào MỘT ReorderableWrap chung (gói "reorderables" —
  // hỗ trợ trẻ kích thước KHÁC NHAU, không như GridView lưới đều). Khối Column bình thường ở
  // dưới KHÔNG bị đụng một dòng nào -> zero rủi ro hồi quy khi Kính TẮT bật lại chế độ thường.
  //
  // [ĐƠN VỊ KÉO-THẢ LÀ THẺ (key = mac_endpoint), KHÔNG PHẢI MAC] Công tắc nhiều kênh render N
  // thẻ/1 MAC — người dùng đòi kéo TỪNG thẻ riêng lẻ (kể cả xen giữa các loại khác), nên
  // _editOrderDraft lưu theo key thẻ (giống hideKey dùng cho Ẩn/Hiện toàn hệ thống), KHÔNG theo
  // MAC. Khi Lưu, dedupe về mảng MAC (giữ đúng model Backend Giai đoạn 72 — chỉ xếp hạng theo
  // MAC): thẻ đầu tiên xuất hiện của một MAC trong thứ tự cuối cùng quyết định hạng MAC đó; các
  // kênh khác cùng MAC không có hạng riêng (giới hạn THẬT của model Backend hiện có, không phải
  // lỗi — nâng cấp Backend lên hạng theo từng kênh nằm ngoài phạm vi yêu cầu lần này).
  bool _isEditingOrder = false;
  bool _savingOrder = false;
  List<({String key, String mac})> _editOrderDraft = [];
  // Thứ tự thẻ NHÌN THẤY gần nhất (key+mac, KHÔNG chứa Widget) — cập nhật ở CUỐI mỗi lượt
  // _buildDevicesGridBody chạy (kể cả ngoài edit mode, rẻ vì chỉ đọc field có sẵn) để làm hạt
  // giống khi bật chế độ Sửa, tránh phải dựng lại toàn bộ danh sách riêng.
  List<({String key, String mac})> _lastVisualCardOrder = [];
  // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] gridSpanX của lần build gần nhất, theo key —
  // cập nhật CÙNG LÚC với _lastVisualCardOrder (xem _buildDevicesGridBody). Chỉ _saveDeviceOrder()
  // đọc, để biết cần chèn bao nhiêu "SKIP" sau mỗi thẻ lớn khi dựng mảng gửi setGridLayout() —
  // _editOrderDraft tự thân KHÔNG mang theo gridSpanX (chỉ có key+mac).
  Map<String, int> _lastEntrySpanByKey = {};
  // [FIX GIAI ĐOẠN 109 — KÉO-THẢ THEO TỪNG PHÒNG] null = đang Sửa thứ tự CẢ NHÀ (mở từ tab "Tất
  // cả", hành vi gốc không đổi). Non-null = đang Sửa CHỈ trong phạm vi 1 phòng (mở khi đang xem
  // tab phòng đó) — chụp lại NGAY LÚC bấm cây bút, không đọc lại roomProv.selectedRoomId về sau vì
  // chuyển tab trong lúc đang Sửa không có ý nghĩa (UI hiện tại không cho đổi phòng giữa chừng).
  // Backend CHỈ có MỘT key Redis "device_order:{homeID}" cho CẢ NHÀ (không có khái niệm "thứ tự
  // riêng từng phòng") — nên "kéo-thả theo phòng" ở đây nghĩa là: lọc màn hình xuống đúng phòng đó
  // để kéo, rồi khi Lưu, GHÉP thứ tự mới của phòng vào ĐÚNG các "khe" (slot) mà MAC phòng đó đang
  // chiếm trong thứ tự CẢ NHÀ hiện có — không đụng vị trí tương đối của bất kỳ thiết bị phòng khác
  // nào (xem _saveDeviceOrder). Không cần thêm bảng/endpoint Backend nào mới.
  String? _editingScopedRoomId;

  // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Token đặc biệt (KHÔNG phải MAC/hideKey thật
  // — không thiết bị nào trùng được) đại diện "ô trống người dùng cố ý để lại" trong
  // _editOrderDraft/_gridLayoutSlots. "SKIP" (khác EMPTY) chỉ sinh ra lúc LƯU (xem _saveDeviceOrder)
  // để đánh dấu ô bị "nuốt" bởi span của thẻ lớn đứng trước — không bao giờ xuất hiện trong
  // _editOrderDraft (người dùng không tự tạo/kéo được ô SKIP, nó là hệ quả tự động của span).
  static const String _kEmptySlotMac = '__EMPTY__';
  static const String _kSkipToken = 'SKIP';
  static const String _kEmptyToken = 'EMPTY';

  // Bố cục lưới đã tải (hideKey / "EMPTY" / "SKIP", ĐÚNG thứ tự đã lưu) — [] = người dùng CHƯA
  // từng dùng tính năng khoảng trống, mọi nơi đọc biến này PHẢI tự rơi về hành vi cũ (macOrderRank).
  List<String> _gridLayoutSlots = [];

  void _toggleEditOrder() {
    if (_isEditingOrder) {
      _saveDeviceOrder();
      return;
    }
    final roomProv = Provider.of<RoomGroupProvider>(context, listen: false);
    setState(() {
      _isEditingOrder = true;
      _editingScopedRoomId = roomProv.selectedRoomId;
      _editOrderDraft = List<({String key, String mac})>.from(_lastVisualCardOrder);
    });
  }

  // [FIX GIAI ĐOẠN 99 — TRUY VẾT NÚT LƯU] Log rõ TỪNG bước: hàm này có thực sự chạy không, mảng
  // gửi lên là gì, gọi API thành công/thất bại ra sao — để lần test tới biết CHẮC CHẮN sự cố nằm
  // ở đâu (nút không bắn sự kiện / mảng rỗng-sai / API lỗi / build cũ chưa deploy) thay vì đoán.
  Future<void> _saveDeviceOrder() async {
    if (kDebugMode) print('💾 [SAVE ORDER] Bắt đầu lưu thứ tự...');
    final homeId = _provisioningTargetHomeId;
    // Dedupe theo MAC — GIỮ vị trí xuất hiện ĐẦU TIÊN của MAC đó trong thứ tự thẻ cuối cùng
    // (xem giải thích ở comment lớp trên).
    final List<String> draftMacs = [];
    final Set<String> seenMacs = {};
    for (final entry in _editOrderDraft) {
      // [GIAI ĐOẠN 113] "__EMPTY__" (ô trống) KHÔNG phải MAC thật — loại khỏi mảng device-order
      // cũ (mảng đó chỉ hiểu MAC thật, xem _saveDeviceOrder/applyDeviceOrder phía Backend); ô
      // trống chỉ sống trong gridTokensToSave bên dưới.
      if (entry.mac.isNotEmpty && entry.mac != _kEmptySlotMac && seenMacs.add(entry.mac)) draftMacs.add(entry.mac);
    }

    // [FIX GIAI ĐOẠN 109 — KÉO-THẢ THEO TỪNG PHÒNG] _editingScopedRoomId != null nghĩa là vừa Sửa
    // trong phạm vi 1 phòng -> draftMacs CHỈ chứa MAC của phòng đó (đúng theo bộ lọc selRoom đã áp
    // xuyên suốt lúc Sửa). Backend chỉ có DUY NHẤT 1 key thứ tự cho CẢ NHÀ — gửi thẳng draftMacs
    // (danh sách con) lên sẽ bị applyDeviceOrder() Backend hiểu là "các MAC này lên ĐẦU, mọi MAC
    // khác (phòng khác) rơi xuống SAU" (xem rank map ở dashboard_handler.go) — TỨC LÀ vô tình kéo
    // luôn cả các phòng khác lên/xuống theo, không phải ý định "chỉ sắp trong phòng này". Nay GHÉP
    // draftMacs vào ĐÚNG các "khe" mà MAC phòng này đang chiếm trong thứ tự CẢ NHÀ hiện có (nguồn:
    // _currentHomeDevices, đã phản ánh đúng lần lưu gần nhất) — duyệt thứ tự cả nhà, gặp khe nào
    // thuộc phòng đang sửa thì thay bằng phần tử TIẾP THEO của draftMacs (đúng thứ tự mới vừa kéo),
    // khe không thuộc phòng giữ NGUYÊN — không đụng vị trí tương đối của bất kỳ thiết bị phòng khác.
    final List<String> orderedMacs;
    if (_editingScopedRoomId != null) {
      final String scopedRoomId = _editingScopedRoomId!;
      final List<String> currentFullOrder = [
        for (final d in _currentHomeDevices)
          (d['mac_address'] ?? d['mac'] ?? '').toString().replaceAll(':', '').toUpperCase(),
      ];
      final roomProvForMerge = Provider.of<RoomGroupProvider>(context, listen: false);
      final Set<String> roomMacsInFullOrder = currentFullOrder.where((m) => roomProvForMerge.roomOf(m) == scopedRoomId).toSet();
      final List<String> merged = [];
      int roomIdx = 0;
      for (final mac in currentFullOrder) {
        if (roomMacsInFullOrder.contains(mac)) {
          if (roomIdx < draftMacs.length) merged.add(draftMacs[roomIdx++]);
        } else {
          merged.add(mac);
        }
      }
      // An toàn: MAC thuộc phòng nhưng chưa từng có khe trong thứ tự cả nhà (thiết bị vừa gán vào
      // phòng, chưa qua lần Lưu cả nhà nào) -> nối vào cuối, không mất.
      while (roomIdx < draftMacs.length) { merged.add(draftMacs[roomIdx++]); }
      orderedMacs = merged;
      if (kDebugMode) print('💾 [SAVE ORDER] Chế độ theo PHÒNG ($scopedRoomId) — ghép ${draftMacs.length} MAC phòng vào ${currentFullOrder.length} MAC cả nhà -> ${orderedMacs.length} MAC.');
    } else {
      orderedMacs = draftMacs;
    }

    if (kDebugMode) print('💾 [SAVE ORDER] home_id=$homeId — danh sách gửi lên (${orderedMacs.length} MAC): $orderedMacs');
    if (homeId.isEmpty || orderedMacs.isEmpty) {
      if (kDebugMode) print('⚠️ [SAVE ORDER] Bỏ qua gọi API: home_id rỗng hoặc danh sách rỗng — thoát chế độ Sửa không lưu gì.');
      setState(() { _isEditingOrder = false; _editingScopedRoomId = null; });
      return;
    }

    // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Ghi KÉP song song với device_order ở
    // dưới (KHÔNG thay thế) — CHỈ khi Sửa CẢ NHÀ (_editingScopedRoomId == null): grid-layout là
    // MỘT chuỗi token PHẲNG duy nhất cho cả nhà, không có công thức "ghép theo khe của 1 phòng"
    // như device_order (xem khối _editingScopedRoomId ở trên) — ghép chuỗi token PARTIAL của 1
    // phòng vào chuỗi ĐẦY ĐỦ sẽ làm lệch toàn bộ vị trí SKIP/EMPTY của các phòng khác, phức tạp
    // hơn hẳn lợi ích mang lại nên KHÔNG làm (nút "Thêm khoảng trống" cũng đã tự ẩn khi Sửa theo
    // phòng — xem _buildDevicesGridBody — nên usesGridLayout dưới đây luôn false trong trường
    // hợp đó, không cần thêm gate riêng).
    final bool usesGridLayout = _editingScopedRoomId == null && _editOrderDraft.any((e) => e.mac == _kEmptySlotMac);
    List<String>? gridTokensToSave;
    if (usesGridLayout) {
      final List<String> tokens = [];
      for (final entry in _editOrderDraft) {
        if (entry.mac == _kEmptySlotMac) {
          tokens.add(_kEmptyToken);
          continue;
        }
        tokens.add(entry.key);
        // "SKIP" theo ĐÚNG span của thẻ (Công tắc=1 -> 0 SKIP, Cửa Gara=2 -> 1 SKIP, Quạt/Nhiệt
        // độ=3 -> 2 SKIP...) — span lấy từ _lastEntrySpanByKey (chụp ở lần build hiển thị gần
        // nhất, xem _buildDevicesGridBody); mặc định 1 (không SKIP) nếu vì lý do gì đó chưa có.
        final int span = _lastEntrySpanByKey[entry.key] ?? 1;
        for (int i = 1; i < span; i++) { tokens.add(_kSkipToken); }
      }
      gridTokensToSave = tokens;
    } else if (_gridLayoutSlots.isNotEmpty && _editingScopedRoomId == null) {
      // Đã từng có bố cục ô lưới nhưng lượt Sửa này người dùng xoá HẾT ô trống -> "tắt" tính năng,
      // dọn sạch để lần hiển thị sau tự rơi về macOrderRank (mảng rỗng = _applyGridLayout không
      // còn được gọi, xem _buildDevicesGridBody).
      gridTokensToSave = [];
    }
    if (gridTokensToSave != null) {
      _gridLayoutSlots = gridTokensToSave;
      _persistLocalGridLayout(homeId, gridTokensToSave);
      if (kDebugMode) print('💾 [SAVE ORDER] Ô lưới (${gridTokensToSave.length} token): $gridTokensToSave');
      // Fire-and-forget — tính năng TÙY CHỌN, lỗi mạng ở đây không được phép chặn/làm hỏng luồng
      // Lưu thứ tự MAC chính bên dưới.
      ApiService().setGridLayout(homeId, gridTokensToSave);
    }

    // [FIX ĐỨT GÃY LUỒNG DỮ LIỆU — BƯỚC 3 "LƯU"] Ghi CỤC BỘ NGAY LẬP TỨC, KHÔNG chờ kết quả gọi
    // API — đây là nguồn sự thật cho hiển thị trên CHÍNH máy này (xem _loadLocalDeviceOrder).
    // Trước đây việc "thứ tự có dính hay không" phụ thuộc HOÀN TOÀN vào Backend trả 200 OK; nếu
    // Backend lỗi/mất mạng, người dùng mất trắng công sức kéo-thả dù đã bấm Lưu.
    _persistLocalDeviceOrder(homeId, orderedMacs);
    if (kDebugMode) print('💾 [SAVE ORDER] Đã ghi cục bộ (device_order_$homeId) — ${orderedMacs.length} MAC.');

    setState(() => _savingOrder = true);
    bool ok = false;
    try {
      if (kDebugMode) print('💾 [SAVE ORDER] Đang gọi ApiService.setDeviceOrder()...');
      ok = await ApiService().setDeviceOrder(homeId, orderedMacs);
      if (kDebugMode) print('💾 [SAVE ORDER] Kết quả API: ${ok ? "THÀNH CÔNG" : "THẤT BẠI"}');
    } catch (e) {
      // [CẤM NUỐT LỖI] Mọi try-catch trong luồng này BẮT BUỘC phải print — dù setDeviceOrder() đã
      // tự bắt lỗi mạng nội bộ (trả false, không throw), vẫn giữ lớp chặn này phòng lỗi bất ngờ
      // khác (vd lỗi logic ngoài dự kiến) không lọt qua trong im lặng.
      if (kDebugMode) print('❌ [SAVE ORDER] Lỗi Save Order: $e');
      ok = false;
    }
    if (!mounted) return;
    // [FIX GIAI ĐOẠN 103 — "UI GIỮ NGUYÊN THỨ TỰ CŨ"] _isEditingOrder=false chuyển màn NGAY LẬP
    // TỨC (đồng bộ) từ ReorderableWrap (edit mode) về _buildUnifiedDeviceWrap (bình thường) —
    // nhưng màn bình thường đọc _currentHomeDevices, một biến TÁCH BIỆT HOÀN TOÀN, trước đây CHỈ
    // được cập nhật SAU khi _handleRefresh() hoàn tất round-trip mạng (bất đồng bộ). Khoảng hở
    // giữa "thoát Edit Mode" (ngay lập tức) và "_currentHomeDevices có thứ tự mới" (chờ mạng) là
    // ĐÚNG nguyên nhân UI "bảo thủ" giữ thứ tự cũ trong lúc chờ. Nay sắp lại _currentHomeDevices
    // TẠI CHỖ, TRONG CÙNG setState thoát Edit Mode, dùng ĐÚNG orderedMacs vừa kéo-thả (dữ liệu
    // local, không cần chờ Server trả về) — UI đổi ĐÚNG thứ tự mới NGAY, không còn độ trễ.
    //
    // [FIX ĐỨT GÃY LUỒNG DỮ LIỆU] KHÔNG còn gate `if (ok)` ở đây — trước đây nếu Backend trả lỗi,
    // thứ tự vừa kéo-thả bị BỎ QUA hoàn toàn dù người dùng đã thao tác đúng. Local đã lưu ở trên
    // rồi (_persistLocalDeviceOrder) BẤT KỂ ok hay không -> luôn cập nhật hiển thị NGAY tương ứng.
    setState(() {
      _savingOrder = false;
      _isEditingOrder = false;
      _editingScopedRoomId = null;
      _applyLocalDeviceOrder(_currentHomeDevices, orderedMacs);
    });
    if (kDebugMode) print('💾 [SAVE ORDER] Đã cập nhật local state ngay lập tức — đang đối chiếu nền với Server...');
    // [FIX ĐỨT GÃY LUỒNG DỮ LIỆU] _handleRefresh() vẫn luôn gọi (không chỉ khi ok) để đối chiếu
    // nền với Backend — an toàn tuyệt đối ngay cả khi Backend trả SAI thứ tự, vì _fetchDevicesForHome
    // giờ TỰ áp lại device_order_$homeId cục bộ lên MỌI danh sách vừa nạp (xem đó) — không còn
    // rủi ro "kéo-thả xong, refresh nền lại âm thầm ghi đè về thứ tự cũ" như trước.
    _handleRefresh();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu thứ tự trên máy này — đồng bộ lên máy chủ thất bại (thiết bị khác có thể chưa thấy thay đổi).'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ==========================================================================
  // 🖼️ [BƯỚC 5 — DEVICE AVATAR BLUEPRINT] Cầu nối avatarLibrary <-> dữ liệu/API THẬT
  // ==========================================================================
  /// Quy trạng thái THẬT của 1 thiết bị (item raw của ĐÚNG category nó thuộc — 7 loại item raw
  /// khác nhau, xem 7 vòng lặp visibleFans/.../visibleSwitches ở dưới) về DeviceAvatarState
  /// chuẩn hoá (xem models/device_avatar_definition.dart). Category không có trục nào đó ->
  /// để null, avatar tự bỏ qua theo đúng hợp đồng Bước 1.
  DeviceAvatarState _avatarStateFromRaw(String category, Map<String, dynamic> e) {
    switch (category) {
      case 'fan':
        final int speed = (e['speed'] as num?)?.toInt() ?? 0;
        return (isOn: speed > 0, speed: speed, value: null, metric: null, metricHistory: null, isOffline: e['online'] != true);
      case 'sensor':
        // Cảm biến không có khái niệm on/off thật — coi là LUÔN "đang đo" để avatar không xám đi
        // như thiết bị tắt. value=nhiệt độ, metric=độ ẩm (2 số đọc phổ biến nhất của category này).
        return (isOn: true, speed: null, value: (e['temp'] as num?)?.toDouble(), metric: (e['hum'] as num?)?.toDouble(), metricHistory: null, isOffline: e['online'] != true);
      case 'rollingDoor':
        return (isOn: true, speed: null, value: (e['positionPct'] as num?)?.toDouble(), metric: null, metricHistory: null, isOffline: e['online'] != true);
      case 'dimmer':
        return (isOn: e['state'] == 'ON', speed: null, value: (e['brightness'] as num?)?.toDouble(), metric: null, metricHistory: null, isOffline: e['online'] != true);
      case 'pump':
      case 'generic':
      case 'switch':
      default:
        return (isOn: e['state'] == 'ON', speed: null, value: null, metric: null, metricHistory: null, isOffline: e['online'] != true);
    }
  }

  /// Bó callbacks THẬT cho Avatar — dựng trên method THẬT đã có sẵn ở DeviceProvider/ApiService
  /// (KHÔNG bịa API mới). CHỈ 4 category dưới đây có đường điều khiển firmware thật đã biết
  /// trong dự án này (Quạt/Dimmer/Cửa cuốn/Relay-Switch — đúng những gì SmartFanCard/
  /// SmartDimmerCard/SmartRollingDoorCard/SmartSwitchCard vẫn dùng, xem digital_twin_cards.dart).
  /// MỌI avatar khác (RGB/HVAC/Thang máy/nhóm Công nghiệp/Cảm biến các Bước 2-4...) CHƯA có
  /// firmware tương ứng trong dự án — onToggle vẫn gọi setSwitchState() THẬT (publish ON/OFF
  /// đúng mac/endpoint qua MQTT, vô hại nếu không có mạch nào lắng nghe đúng endpoint đó), còn
  /// onChange không khớp category nào rơi về ApiService.setDeviceSetting() — LƯU THẬT xuống
  /// Backend (không phải no-op giả) làm mức tối thiểu "không mất input người dùng chỉnh", firmware
  /// nào đọc đúng key `avatar_` + tên field sau này tự nhận được giá trị mà không cần sửa avatar.
  DeviceAvatarCallbacks _avatarCallbacksFor(DeviceProvider provider, String category, Map<String, dynamic> raw) {
    final String mac = (raw['mac'] ?? '') as String;
    final String endpoint = (raw['endpoint'] ?? raw['upEp'] ?? '') as String;
    return (
      onToggle: (bool newOn) => provider.setSwitchState(mac, endpoint, newOn),
      onChange: (String field, num value) {
        switch (category) {
          case 'fan':
            if (field == 'speed') { provider.setFanSpeed(mac, value.toInt(), endpoint: endpoint); return; }
            break;
          case 'dimmer':
            if (field == 'value') { provider.setDimmerBrightness(mac, endpoint, value.round()); return; }
            break;
          case 'rollingDoor':
            if (field == 'value') {
              // CÙNG công thức delta% -> mili-giây kích relay mà SmartRollingDoorCard đã dùng
              // (_onSliderChangeEnd trong digital_twin_cards.dart) — Thời gian hành trình mặc
              // định 15s khi thiết bị chưa hiệu chỉnh (travelSec <= 0).
              final double targetPct = value.toDouble().clamp(0, 100);
              final double? currentPct = (raw['positionPct'] as num?)?.toDouble();
              final double delta = targetPct - (currentPct ?? targetPct);
              if (delta == 0) return;
              final int travelSec = (raw['travelSec'] as int?) ?? 0;
              final int effectiveTravelSec = travelSec > 0 ? travelSec : 15;
              final int durationMs = ((delta.abs() / 100) * effectiveTravelSec * 1000).round().clamp(100, 30000);
              final String dirEp = (delta > 0 ? raw['upEp'] : raw['downEp']) as String? ?? endpoint;
              provider.pulseDoorRelay(mac, dirEp, durationMs);
              return;
            }
            break;
        }
        ApiService().setDeviceSetting(mac, 'avatar_$field', value.toString());
      },
    );
  }

  /// Tra avatarLibrary theo id. null nếu id đã gán trước đó không còn tồn tại (vd đổi phiên bản
  /// app) -> nơi gọi tự rơi về card mặc định, KHÔNG throw, KHÔNG mất thiết bị khỏi lưới.
  DeviceAvatarDefinition? _findAvatarDef(String avatarId) {
    for (final d in avatarLibrary) {
      if (d.id == avatarId) return d;
    }
    return null;
  }

  /// [FIX #3] Mở ĐÚNG menu dùng chung (Đổi tên/Ẩn/Chuyển phòng/Xoá/... + "Thay đổi giao diện")
  /// cho một thiết bị ĐÃ GÁN AVATAR — avatar (Bước 2-4) tự thân không có menu riêng (chỉ vẽ UI),
  /// nên nhấn giữ ở đây phải tự dựng `cb` qua `_stdCallbacks` rồi gọi thẳng
  /// `DeviceMenuHelper.showGenericDeviceMenu` giống hệt cấu trúc mọi card mặc định đang dùng.
  void _openAvatarDeviceMenu(String mac, String hideKey, String name, String endpoint) {
    final cb = _stdCallbacks(mac, hideKey, name, endpoint: endpoint);
    DeviceMenuHelper.showGenericDeviceMenu(
      context: context,
      mac: mac,
      currentName: name,
      headerIcon: Icons.dashboard_customize_rounded,
      onRename: cb.rename,
      onChangeAvatar: cb.changeAvatar,
      onAssignHome: cb.assignHome,
      onAssignRoom: cb.assignRoom,
      onDeviceTimer: cb.timer,
      onDeviceHistory: cb.history,
      onDeviceAutomation: cb.automation,
      onDeviceShare: cb.share,
      isHidden: _hiddenDevices.contains(hideKey),
      onToggleHide: (hide) => setState(() {
        hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
        _persistHiddenDevices();
      }),
      onDelete: cb.delete,
    );
  }

  // ==========================================================================
  // 🧱 [GIAI ĐOẠN 115, MỞ RỘNG GIAI ĐOẠN 117] MENU 2 CẤP CHO KHỐI MẶT CÔNG TẮC VẬT LÝ
  // ==========================================================================
  /// Menu khi nhấn giữ MỘT NÚT (ô con/endpoint) trong khối — mọi việc THẬT SỰ thuộc về riêng
  /// kênh đó: Sửa tên nút, Thay đổi giao diện avatar riêng kênh, Ẩn riêng kênh này (KHÔNG ảnh
  /// hưởng các nút khác cùng khối — đúng data model hideKey per-endpoint, xem Giai đoạn 116),
  /// và lối vào "Chọn nhiều" có TỰ CHỌN SẴN đúng kênh này (để user chọn thêm kênh/khối khác rồi
  /// dùng thanh công cụ bên dưới tạo Nhóm ảo/Cầu thang — _bulkCreateGroup). KHÔNG có Xóa/Chuyển
  /// phòng/Chuyển nhà ở đây — những việc đó thuộc về CẢ khối, xem _openFaceplateDeviceMenu (nhấn
  /// giữ tiêu đề).
  void _openGangMenu(String mac, String hideKey, String name, String endpoint) {
    final cb = _stdCallbacks(mac, hideKey, name, endpoint: endpoint);
    final t = AppTranslations.of(context, listen: false);
    DeviceMenuHelper.showGenericDeviceMenu(
      context: context,
      mac: mac,
      currentName: name,
      subtitle: 'Endpoint: $endpoint',
      headerIcon: Icons.power_settings_new_rounded,
      onRename: cb.rename,
      onChangeAvatar: cb.changeAvatar,
      isHidden: _hiddenDevices.contains(hideKey),
      onToggleHide: (hide) => setState(() {
        hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
        _persistHiddenDevices();
      }),
      extraItems: [
        DeviceMenuItem(
          icon: Icons.checklist_rtl_rounded,
          title: t.text('select_multiple_devices'),
          onTap: () => setState(() { _isSelectionMode = true; _selectedDevices.add(hideKey); }),
        ),
      ],
    );
  }

  /// Menu ĐẦY ĐỦ cấp thiết bị khi nhấn giữ vùng TIÊU ĐỀ của khối (tên khối, phía trên các nút) —
  /// Cài đặt/Hẹn giờ/Lịch sử/Ngữ cảnh/Chia sẻ/Ẩn CẢ KHỐI/Chuyển phòng/Chuyển nhà/Xóa CẢ THIẾT BỊ.
  /// [KHÔNG có onRename/onChangeAvatar ở đây — CỐ Ý] Backend chỉ hỗ trợ đổi tên/avatar THEO TỪNG
  /// ENDPOINT (RenameDeviceEndpointHandler yêu cầu endpoint khớp regex khác rỗng; avatar_map cũng
  /// theo endpoint) — không có khái niệm "tên/avatar cấp thiết bị" tách biệt để gán ở đây, 2 việc
  /// đó CHỈ làm được qua _openGangMenu (nhấn giữ đúng 1 nút). [endpoint đại diện] Hẹn giờ/Lịch sử/
  /// Ngữ cảnh dùng endpoint của KÊNH ĐẦU TIÊN làm đại diện (không có khái niệm "cả khối" cho các
  /// tính năng này ở Backend).
  void _openFaceplateDeviceMenu(String mac, String groupKey, String deviceName, List<Map<String, dynamic>> channels) {
    final String repEndpoint = channels.isNotEmpty ? channels.first['endpoint'] as String : '';
    final cb = _stdCallbacks(mac, groupKey, deviceName, endpoint: repEndpoint);
    // Gọi từ chuỗi tap-handler (onLongPress) -> listen: false, tránh "liệt nút".
    final t = AppTranslations.of(context, listen: false);
    DeviceMenuHelper.showGenericDeviceMenu(
      context: context,
      mac: mac,
      currentName: deviceName,
      subtitle: '${channels.length} nút bấm',
      headerIcon: Icons.grid_view_rounded,
      onDeviceTimer: cb.timer,
      onDeviceHistory: cb.history,
      onDeviceAutomation: cb.automation,
      onDeviceShare: cb.share,
      onAssignHome: cb.assignHome,
      onAssignRoom: cb.assignRoom,
      // [FIX GIAI ĐOẠN 116] "Ẩn cả khối" là hành động TIỆN ÍCH lặp qua TỪNG hideKey thật (không có
      // khoá ẩn cấp khối nào tồn tại) — isHidden hiển thị true chỉ khi TẤT CẢ kênh đang ẩn (đúng
      // logic allHidden đã tính ở _buildFaceplateEntry, tính lại tương đương ở đây vì hàm này độc
      // lập với entries).
      isHidden: channels.every((c) => _hiddenDevices.contains("${mac}_${c['endpoint']}")),
      onToggleHide: (hide) => setState(() {
        for (final c in channels) {
          final String ck = "${mac}_${c['endpoint']}";
          hide ? _hiddenDevices.add(ck) : _hiddenDevices.remove(ck);
        }
        _persistHiddenDevices();
      }),
      onDelete: cb.delete,
      // [FIX — LỐI VÀO "CHỌN NHIỀU" CHO NHÀ CHỈ TOÀN CÔNG TẮC ĐA KÊNH] SmartSwitchCard đơn (1-gang)
      // có sẵn mục này trong extraItems riêng — khối mặt công tắc (>=2 gang) trước đây KHÔNG có,
      // nếu một nhà chỉ toàn thiết bị đa kênh sẽ không còn cách nào bật chế độ Chọn nhiều.
      // [FIX GIAI ĐOẠN 116] CHỈ bật chế độ Chọn nhiều — KHÔNG tự chọn sẵn gì (groupKey/mac trần
      // không còn là 1 phần tử hợp lệ của _selectedDevices, tập này nay LUÔN là hideKey per-nút).
      // Người dùng tự tick từng nút muốn chọn sau khi menu đóng.
      extraItems: [
        DeviceMenuItem(
          icon: Icons.checklist_rtl_rounded,
          title: t.text('select_multiple_devices'),
          onTap: () => setState(() => _isSelectionMode = true),
        ),
        // [GIAI ĐOẠN 125 — GỘP/TÁCH] Chiều ngược lại của mục trong SmartSwitchCard:
        // thẻ này đang Ở DẠNG GỘP (mở được _openFaceplateDeviceMenu nghĩa là channels.length > 1
        // và _deviceGrouped[mac] == true) -> cho phép tách trở lại thành N thẻ rời.
        DeviceMenuItem(
          icon: Icons.call_split_rounded,
          title: 'Tách thành từng nút riêng',
          onTap: () => _setDeviceGrouped(mac, false),
        ),
      ],
    );
  }

  // [FIX GIAI ĐOẠN 123 — DIALOG CĂN GIỮA + STATE SỐNG] 2 lỗi user báo: (1) showAppBottomSheet
  // trước đây trượt lên từ ĐÁY màn hình, KHÔNG bao giờ căn giữa (đúng nguyên nhân "lệch tâm") ->
  // đổi hẳn sang showAppDialog() (Dialog CĂN GIỮA tuyệt đối, bo góc, cùng khung dùng chung với
  // MỌI dialog khác trong app — không tự dựng showDialog/Dialog() thô để giữ nhất quán theming
  // Sáng/Tối/Kính đã có sẵn, xem app_ui_wrappers.dart); bọc thêm ConstrainedBox(maxHeight: 70%
  // màn hình) làm lưới an toàn cho thiết bị nhiều kênh bất thường (vd 16-gang tương lai). (2) Bấm
  // nút trong popup KHÔNG đổi màu vì [cells] trước đây là ẢNH TĨNH build 1 lần lúc mở — nay bọc
  // Consumer<DeviceProvider> NGAY TRONG popup, tự dựng lại cells SỐNG từ liveProvider mỗi khi có
  // gói MQTT mới cho MAC này (xem _buildFaceplateCellsLive).
  // [FIX GIAI ĐOẠN 127 — CHECKMARK CHỌN NHIỀU KHÔNG CẬP NHẬT] Root cause: Dialog (showAppDialog)
  // đẩy [child] vào một ROUTE/OVERLAY RIÊNG, TÁCH HẲN khỏi cây widget chính của DashboardScreen —
  // setState() gọi trên _DashboardScreenState (bên trong _buildFaceplateCellsLive khi bấm chọn)
  // CHỈ rebuild cây MÀN HÌNH CHÍNH (đúng lý do "Đã chọn N" ở FAB cập nhật ĐÚNG), KHÔNG rebuild
  // được route Dialog đang nổi bên trên — Consumer<DeviceProvider> trong popup CHỈ tự rebuild khi
  // DeviceProvider.notifyListeners() (gói MQTT mới), một nguồn dữ liệu HOÀN TOÀN KHÁC với
  // _selectedDevices/_isSelectionMode. Bọc thêm StatefulBuilder NGAY TRONG Dialog, lấy StateSetter
  // riêng (setStateDialog) — gọi nó NGAY SAU setState() ngoài mỗi khi chọn/bỏ chọn để ép ĐÚNG cây
  // con của Dialog vẽ lại tức thì, độc lập với vòng đời DeviceProvider.
  void _showFaceplateExpanded({
    required String mac,
    required String groupKey,
    required String deviceName,
    required List<Map<String, dynamic>> channels,
    required Map<String, dynamic>? masterItem,
    required bool isHidden,
  }) {
    // [FIX GIAI ĐOẠN 129 — YÊU CẦU #3.1 — THU NHỎ POPUP] maxWidth của showAppDialog() ĐÃ LÀ ĐÚNG
    // cơ chế bọc ConstrainedBox(maxWidth) quanh nội dung Dialog (xem app_ui_wrappers.dart) — thêm
    // MỘT ConstrainedBox(maxWidth:360) LỒNG THÊM bên trong [child] như đề xuất literal sẽ chỉ tạo
    // 2 lớp ConstrainedBox trùng chức năng (vô hại nhưng thừa) — đơn giản hơn: đổi thẳng giá trị
    // tham số maxWidth có sẵn từ 400 xuống 360, đạt ĐÚNG hiệu quả mong muốn mà không lồng thêm lớp.
    showAppDialog(
      context: context,
      maxWidth: 360,
      // [FIX GIAI ĐOẠN 128 — PADDING DIALOG QUÁ LỚN] Mặc định showAppDialog() là EdgeInsets.all(24)
      // (dành cho popup xác nhận/form THÔNG THƯỜNG, chữ ít) — với 1 GridView nhiều ô như popup
      // này, 24px mỗi cạnh (48px tổng theo bề ngang) ăn vào đúng phần nên dành cho các ô, khiến
      // Dialog trông "phình" quá mức cần thiết dù maxWidth đã khoá 400. Giảm còn 16.
      contentPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        // [FIX GIAI ĐOẠN 129 — YÊU CẦU #2 — OVERFLOW ĐÁY 1.6px] PhysicalSwitchBlockCard bên dưới
        // dùng Column(mainAxisSize.min) + GridView(shrinkWrap:true) — tổng chiều cao THẬT (header +
        // Divider + lưới N kênh) đôi khi lệch vài phần thập phân pixel so với ConstrainedBox(maxHeight)
        // ở trên (làm tròn childAspectRatio 1.0 của Giai đoạn 128 × số hàng lẻ) — trước đây KHÔNG có
        // đường thoát nào cho phần dư đó ngoài ném RenderFlex overflow. Bọc SingleChildScrollView ở
        // ĐÚNG ranh giới này: cấp height UNBOUNDED cho nội dung bên trong (Column tự cao theo đúng
        // nhu cầu, không còn bị ép cắt) trong khi viewport NGOÀI vẫn bị khoá bởi ConstrainedBox —
        // phần dư (nếu có) biến thành cuộn được thay vì tràn vỡ khung hình.
        child: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setStateDialog) => Consumer<DeviceProvider>(
              builder: (context, liveProvider, _) {
                final DeviceModel? live = liveProvider.devices[mac];
                final bool anyOnline = live?.online ?? channels.any((c) => c['online'] == true);
                final bool anyOn = channels.any((c) => live?.isOn(c['endpoint'] as String) ?? false);
                return PhysicalSwitchBlockCard(
                  deviceName: deviceName,
                  cells: _buildFaceplateCellsLive(mac, channels, liveProvider, setStateDialog),
                  isOffline: !anyOnline,
                  isHidden: isHidden,
                  isSelectionMode: _isSelectionMode,
                  onOpenDeviceMenu: () => _openFaceplateDeviceMenu(mac, groupKey, deviceName, channels),
                  onToggleAll: masterItem != null ? () => liveProvider.toggleDevice(mac, 'all', anyOn) : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// [GIAI ĐOẠN 123] Dựng lại TOÀN BỘ nút con của khối mặt công tắc, đọc trạng thái BẬT/TẮT +
  /// Ngoại tuyến TRỰC TIẾP từ [liveProvider] (không phải bản snapshot [channels] đóng băng lúc mở
  /// popup) — gọi TỪ BÊN TRONG `Consumer<DeviceProvider>.builder` nên chạy lại MỖI LẦN provider
  /// notify, đảm bảo popup luôn phản ánh đúng trạng thái sống. [channels] chỉ còn dùng cho phần
  /// KHÔNG đổi theo thời gian thực (danh sách endpoint tồn tại + tên mặc định).
  /// [GIAI ĐOẠN 127] [setStateDialog] = StateSetter riêng của StatefulBuilder bọc Dialog (xem
  /// _showFaceplateExpanded) — gọi ngay sau khi đổi _selectedDevices/_isSelectionMode để ép Dialog
  /// (route riêng, KHÔNG tự rebuild theo setState() của _DashboardScreenState) vẽ lại tức thì.
  List<Widget> _buildFaceplateCellsLive(String mac, List<Map<String, dynamic>> channels, DeviceProvider liveProvider, StateSetter setStateDialog) {
    final DeviceModel? live = liveProvider.devices[mac];
    final List<Widget> cells = [];
    for (final rawItem in channels) {
      final String ep = rawItem['endpoint'] as String;
      final String hideKey = "${mac}_$ep";
      // Đè trạng thái SỐNG lên bản snapshot — live == null (chưa từng có gói MQTT nào cho MAC
      // này kể từ lúc mở App) thì rơi về đúng giá trị REST ban đầu trong rawItem, không đoán mò.
      final Map<String, dynamic> item = {
        ...rawItem,
        if (live != null) 'state': live.isOn(ep) ? 'ON' : 'OFF',
        if (live != null) 'online': live.online,
      };
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'switch', item, liveProvider);
      if (avatarEntry != null) {
        cells.add(KeyedSubtree(key: ValueKey('gang_live_$hideKey'), child: avatarEntry.widget));
        continue;
      }
      final bool isOn = item['state'] == 'ON';
      final bool isOffline = item['online'] != true;
      final String name = (item['name'] as String?)?.isNotEmpty == true ? item['name'] as String : ep;
      cells.add(KeyedSubtree(
        key: ValueKey('gang_live_$hideKey'),
        child: _SwitchGangButton(
          name: name,
          isOn: isOn,
          isOffline: isOffline,
          isSelectionMode: _isSelectionMode,
          isSelected: _selectedDevices.contains(hideKey),
          onTap: () {
            if (_isSelectionMode) {
              setState(() {
                _selectedDevices.contains(hideKey) ? _selectedDevices.remove(hideKey) : _selectedDevices.add(hideKey);
                if (_selectedDevices.isEmpty) _isSelectionMode = false;
              });
              // [GIAI ĐOẠN 127] setState() ở trên CHỈ rebuild màn hình chính (đúng lý do "Đã chọn
              // N" cập nhật đúng) — Dialog là route riêng, PHẢI tự ép vẽ lại qua setStateDialog để
              // checkmark nảy lên ngay lập tức thay vì đợi gói MQTT kế tiếp kích Consumer rebuild.
              setStateDialog(() {});
            } else {
              liveProvider.toggleDevice(mac, ep, isOn);
            }
          },
          onLongPress: () => _openGangMenu(mac, hideKey, name, ep),
        ),
      ));
    }
    return cells;
  }

  /// Nếu [hideKey] đã được gán Avatar còn hợp lệ -> trả về Widget Avatar (bọc long-press mở
  /// ĐÚNG menu dùng chung, có "Thay đổi giao diện") + kích thước lưới ĐÚNG blueprint. null nếu
  /// chưa gán/avatar đã gỡ khỏi thư viện -> nơi gọi tự dựng card mặc định (SmartXCard) như trước.
  ({Widget widget, int gridSpanX, int gridSpanY})? _tryBuildAvatarEntry(
    String hideKey,
    String category,
    Map<String, dynamic> raw,
    DeviceProvider provider,
  ) {
    final String? avatarId = _deviceAvatarId[hideKey];
    if (avatarId == null) return null;
    final DeviceAvatarDefinition? def = _findAvatarDef(avatarId);
    if (def == null) return null;
    final DeviceAvatarState state = _avatarStateFromRaw(category, raw);
    final DeviceAvatarCallbacks callbacks = _avatarCallbacksFor(provider, category, raw);
    final String mac = (raw['mac'] ?? '') as String;
    final String endpoint = (raw['endpoint'] ?? raw['upEp'] ?? '') as String;
    final String name = (raw['name'] as String?)?.isNotEmpty == true ? raw['name'] as String : def.name;
    return (
      widget: GestureDetector(
        onLongPress: () => _openAvatarDeviceMenu(mac, hideKey, name, endpoint),
        child: Builder(builder: (ctx) => def.buildWidget(ctx, state, callbacks)),
      ),
      gridSpanX: def.gridSpanX,
      gridSpanY: def.gridSpanY,
    );
  }

  /// [ĐỒNG BỘ AVATAR LÊN SERVER] Gom mọi avatar ĐANG gán cho các kênh của [mac] (từ
  /// _deviceAvatarId, khoá dạng "{mac}_{endpoint}") thành JSON phẳng {endpoint: avatarId} — khớp
  /// đúng field `avatar_map` phía Backend (xem allowedDeviceSettingKeys trong device_handler.go).
  Map<String, String> _avatarMapForMac(String mac) {
    final Map<String, String> m = {};
    final String prefix = '${mac}_';
    _deviceAvatarId.forEach((k, v) {
      if (k.startsWith(prefix)) m[k.substring(prefix.length)] = v;
    });
    return m;
  }

  /// Popup "Thay đổi giao diện (Avatar)" — chọn từ TOÀN BỘ avatarLibrary, KHÔNG lọc theo category
  /// backend của thiết bị (đổi Avatar chỉ đổi GIAO DIỆN hiển thị, người dùng có thể chọn bất kỳ
  /// hình dáng nào họ thấy hợp — vd gán "Đèn RGB" cho một công tắc thường vẫn hợp lệ). Mỗi ô
  /// preview render bằng ĐÚNG buildWidget() của blueprint với dữ liệu MẪU cố định (không phải
  /// trạng thái thật) chỉ để xem trước hình dáng — callbacks preview là no-op (không điều khiển
  /// thiết bị thật khi đang chọn).
  void _showAvatarPicker(String hideKey, String mac) {
    final String? currentId = _deviceAvatarId[hideKey];
    final Size screenSize = MediaQuery.of(context).size;
    showAppDialog(
      context: context,
      // [FIX — KHÔNG CÒN NỞ VÔ HẠN TRÊN PC] Trước đây dùng screenSize.width*0.8 — trên màn hình
      // rộng (PC/Web), 80% bề ngang vẫn RẤT lớn, kéo giãn cả Dialog lẫn số cột cứng theo tỉ lệ đó
      // ra tô hô. Cố định trần 800px: showAppDialog()/Dialog() bên trong đã TỰ giao (intersect)
      // với bề ngang màn hình thật nên vẫn an toàn trên điện thoại hẹp (trần 800 chỉ có tác dụng
      // khi màn hình ĐỦ RỘNG để chạm tới, không bao giờ ép Dialog vượt quá màn hình thật).
      maxWidth: 800,
      child: Builder(
        builder: (ctx) => _AvatarPickerDialogBody(
          currentId: currentId,
          maxHeight: screenSize.height * 0.75,
          onSelect: (avatarId) {
            setState(() {
              if (avatarId == null) {
                _deviceAvatarId.remove(hideKey);
              } else {
                _deviceAvatarId[hideKey] = avatarId;
              }
            });
            _persistDeviceAvatars();
            // [ĐỒNG BỘ AVATAR LÊN SERVER] Trước đây CHỈ lưu SharedPreferences cục bộ — đổi điện
            // thoại/người nhà dùng máy khác không thấy avatar vừa gán. Bắn NGAY lên Backend qua
            // kênh device_settings tổng quát đã có sẵn (setDeviceSetting, xem
            // allowedDeviceSettingKeys.avatar_map ở Go) — fire-and-forget, không chặn UI/không
            // rollback nếu lỗi mạng (đã có bản cục bộ ngay phía trên làm nguồn sự thật tối thiểu
            // trên CHÍNH máy này, cùng triết lý với _saveDeviceOrder).
            ApiService().setDeviceSetting(mac, 'avatar_map', jsonEncode(_avatarMapForMac(mac)));
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }


  // [BƯỚC 5 — DEVICE AVATAR BLUEPRINT] Dựng danh sách entries kèm gridSpanX (hệ số bề rộng — 1 =
  // thẻ nhỏ, 2 = thẻ lớn, xem _buildAvatarStaggeredGrid) cho TOÀN BỘ thiết bị "thẻ lớn" (Quạt/Cảm
  // biến/Cửa cuốn/Bơm/Đèn/Generic). Mỗi thiết bị: nếu đã gán Avatar (qua popup "Thay đổi giao
  // diện") -> dùng ĐÚNG UI + gridSpanX của blueprint (_tryBuildAvatarEntry); chưa gán -> giữ
  // NGUYÊN card mặc định gốc (SmartFanCard/SmartSensorCard/... gridSpanX=2, SmartSwitchCard=1) —
  // "Thay đổi giao diện (Avatar)" nằm trong CHÍNH menu nhấn-giữ có sẵn của từng card
  // (cb.changeAvatar, xem _stdCallbacks) — KHÔNG còn huy hiệu góc ngoài riêng.
  // _buildDevicesGridBody() nối chung danh sách này với _buildSwitchCardEntries() rồi vẽ MỘT
  // Wrap duy nhất (xem _buildAvatarStaggeredGrid) — chảy đúng thứ tự mảng, không bin-packing.
  List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> _buildAllDeviceCardEntries(
    List<Map<String, dynamic>> visibleFans,
    List<Map<String, dynamic>> visibleSensors,
    List<Map<String, dynamic>> visibleRollingDoors,
    List<Map<String, dynamic>> visiblePumps,
    List<Map<String, dynamic>> visibleDimmers,
    List<Map<String, dynamic>> visibleGenericPrimary,
    DeviceProvider provider,
    bool isDark,
  ) {
    final List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> entries = [];

    for (final e in visibleFans) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'fan', e, provider);
      if (avatarEntry != null) {
        entries.add((key: hideKey, mac: e['mac'] as String, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false));
        continue;
      }
      final String status = "${e['speed']}_${e['swing']}_${e['online']}";
      final String renameEndpoint = (e['endpoint'] as String).startsWith('S_') || RegExp(r'^[Ff]\d+$').hasMatch(e['endpoint'])
          ? e['endpoint'] : 'S_${e['mac']}';
      final cb = _stdCallbacks(e['mac'], "${e['mac']}_$renameEndpoint", e['name'], endpoint: renameEndpoint);
      // [FIX GIAI ĐOẠN 113] Quạt: span 3 theo quy hoạch cột mới (Công tắc=1, Cửa Gara=2, Quạt/
      // Nhiệt độ=3) — trước đây dùng chung span 2 với mọi thẻ lớn khác.
      entries.add((key: hideKey, mac: e['mac'] as String, gridSpanX: 3, gridSpanY: 1, autoHeight: true, widget: SmartFanCard(
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
        onToggleHide: (hide) => setState(() {
          hide ? _hiddenDevices.add(hideKey) : _hiddenDevices.remove(hideKey);
          _persistHiddenDevices();
        }),
        onDelete: cb.delete,
        onRename: cb.rename,
        onChangeAvatar: cb.changeAvatar,
        onAssignHome: cb.assignHome,
        onAssignRoom: cb.assignRoom,
        onDeviceTimer: cb.timer,
        onDeviceHistory: cb.history,
        onDeviceAutomation: cb.automation,
        onDeviceShare: cb.share,
      )));
    }

    for (final e in visibleSensors) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'sensor', e, provider);
      if (avatarEntry != null) {
        entries.add((key: hideKey, mac: e['mac'] as String, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false));
        continue;
      }
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      // [FIX GIAI ĐOẠN 113] Cảm biến (Nhiệt độ): span 3 — cùng nhóm với Quạt theo yêu cầu.
      entries.add((key: hideKey, mac: e['mac'] as String, gridSpanX: 3, gridSpanY: 1, autoHeight: true, widget: SmartSensorCard(
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
        onRename: cb.rename,
        onDelete: cb.delete,
        onChangeAvatar: cb.changeAvatar,
        onAssignHome: cb.assignHome,
        onAssignRoom: cb.assignRoom,
        onDeviceTimer: cb.timer,
        onDeviceHistory: cb.history,
        onDeviceAutomation: cb.automation,
        onDeviceShare: cb.share,
      )));
    }

    for (final e in visibleRollingDoors) {
      final String hideKey = "${e['mac']}_${e['upEp']}";
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'rollingDoor', e, provider);
      if (avatarEntry != null) {
        entries.add((key: hideKey, mac: e['mac'] as String, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false));
        continue;
      }
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['upEp']);
      entries.add((key: hideKey, mac: e['mac'] as String, gridSpanX: 2, gridSpanY: 1, autoHeight: true, widget: SmartRollingDoorCard(
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
      )));
    }

    for (final e in visiblePumps) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'pump', e, provider);
      if (avatarEntry != null) {
        entries.add((key: hideKey, mac: e['mac'] as String, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false));
        continue;
      }
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      entries.add((key: hideKey, mac: e['mac'] as String, gridSpanX: 2, gridSpanY: 1, autoHeight: true, widget: SmartPumpCard(
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
      )));
    }

    for (final e in visibleDimmers) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'dimmer', e, provider);
      if (avatarEntry != null) {
        entries.add((key: hideKey, mac: e['mac'] as String, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false));
        continue;
      }
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      entries.add((key: hideKey, mac: e['mac'] as String, gridSpanX: 2, gridSpanY: 1, autoHeight: true, widget: SmartDimmerCard(
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
      )));
    }

    for (final e in visibleGenericPrimary) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final avatarEntry = _tryBuildAvatarEntry(hideKey, 'generic', e, provider);
      if (avatarEntry != null) {
        entries.add((key: hideKey, mac: e['mac'] as String, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false));
        continue;
      }
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      entries.add((key: hideKey, mac: e['mac'] as String, gridSpanX: 2, gridSpanY: 1, autoHeight: true, widget: GenericDeviceCard(
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
      )));
    }

    return entries;
  }

  // [FIX GIAI ĐOẠN 113 — TỶ LỆ CỘT THEO MỐC TƯỜNG MINH] Trước đây MỖI nơi (Công tắc/thẻ lớn) tự
  // suy công thức riêng từ 1 target-px khác nhau (140px/130px, clamp khác nhau) — tuy đều đạt
  // mục tiêu "3 cột trên Mobile" nhưng số cột Tablet/PC không khớp nhau tuyệt đối và không theo
  // đúng mốc breakpoint người dùng yêu cầu tường minh. Nay dùng ĐÚNG MỘT hàm _gridColumns() cho
  // TẤT CẢ (Công tắc lẫn thẻ lớn, chế độ thường lẫn chế độ Sửa — vẫn giữ nguyên tắc "không nhảy
  // cỡ giữa 2 chế độ" từ Giai đoạn 90/104).
  //
  // [FIX GIAI ĐOẠN 114 — THẺ CÔNG TẮC PHÌNH TO TRÊN TABLET] Mốc cũ (>1000=10, >600=6) để trống
  // một dải rộng 601-1000px chỉ có 6 cột — trên Tablet ngang/cửa sổ desktop thu nhỏ (~900-1200px)
  // 6 cột vẫn cho thẻ Công tắc 1x1 khá to, không "gọn như Desktop". Thêm MỘT mốc trung gian
  // 900px (8 cột) — dải 601-900 (Tablet dọc) giữ 6 cột như cũ. Mốc Mobile (<=600 -> 3 cột) GIỮ
  // NGUYÊN TUYỆT ĐỐI theo yêu cầu, không đụng.
  int _gridColumns(double maxWidth) {
    if (maxWidth > 1200) return 10; // Desktop lớn — thẻ rất gọn
    if (maxWidth > 900) return 8; // Tablet ngang / Desktop thu nhỏ — 4 Công tắc = nửa màn hình
    if (maxWidth > 600) return 6; // Tablet dọc
    return 3; // Mobile — KHÔNG ĐỔI
  }

  int _switchCrossAxisCount(double maxWidth) => _gridColumns(maxWidth);
  double _switchCellWidth(double maxWidth) {
    final int n = _switchCrossAxisCount(maxWidth);
    return (maxWidth - (n - 1) * 16) / n;
  }

  // [BƯỚC 5, ĐẠI TU GIAI ĐOẠN 115] Dựng entries CHO thiết bị Công tắc. [KIẾN TRÚC "SERVER MÙ" —
  // xem khối comment đầy đủ tại PhysicalSwitchBlockCard] Backend/thứ tự KHÔNG đổi gì — quyết định
  // duy nhất ở ĐÂY: thiết bị 1 kênh (đa số) đi ĐÚNG đường cũ (SmartSwitchCard đơn, xem
  // _buildSingleSwitchEntry — tuyệt đối không đổi hình dáng), thiết bị >=2 kênh CÙNG MAC gộp
  // thành MỘT entry duy nhất (khối mặt công tắc vật lý, xem _buildFaceplateEntry) — 1 entry = 1
  // đơn vị kéo-thả/lưu thứ tự (ReorderableWrap thao tác theo entries -> tự động "kéo cả khối,
  // không kéo rời từng nút" mà KHÔNG cần Draggable/DragTarget riêng nào).
  List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> _buildSwitchCardEntries(
    List<Map<String, dynamic>> visibleSwitches,
    DeviceProvider provider,
    bool isDark,
  ) {
    final List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> entries = [];

    // Gom KÊNH THẬT theo MAC (loại nút "Tất cả" ảo — endpoint='all', KHÔNG phải nút vật lý trên
    // mặt công tắc thật). visibleSwitches đã sắp sẵn: nút "Tất cả" (nếu có) LUÔN đứng TRƯỚC các
    // kênh cùng MAC (allSwitches.sort() ở _buildDevicesGridBody, rank(a)=-1 cho nút tổng) — giữ
    // nguyên thứ tự này khi gom vào channelsByMac.
    final Map<String, List<Map<String, dynamic>>> channelsByMac = {};
    final Map<String, Map<String, dynamic>> masterByMac = {};
    for (final item in visibleSwitches) {
      final String mac = item['mac'] as String;
      if (item['isMaster'] == true) { masterByMac[mac] = item; continue; }
      channelsByMac.putIfAbsent(mac, () => []).add(item);
    }

    final Set<String> emittedMacs = {};
    for (final item in visibleSwitches) {
      if (item['isMaster'] == true) continue;
      final String mac = item['mac'] as String;
      if (!emittedMacs.add(mac)) continue; // MAC này đã emit entry rồi (kênh thứ 2+ của cùng MAC)
      final channels = channelsByMac[mac]!;

      if (channels.length == 1) {
        // 1 kênh duy nhất -> KHÔNG có khái niệm Gộp/Tách (chỉ có ý nghĩa khi >=2 kênh).
        entries.add(_buildSingleSwitchEntry(channels.first, provider, isPartOfMultiChannel: false));
      } else if (_deviceGrouped[mac] ?? false) {
        // [GIAI ĐOẠN 125] Người dùng CHỌN Gộp cho MAC này -> khối mặt công tắc như cũ.
        entries.add(_buildFaceplateEntry(mac, channels, masterByMac[mac], provider));
      } else {
        // [GIAI ĐOẠN 125 — MẶC ĐỊNH] Chưa từng chọn hoặc đã chọn Tách -> flat-map thành N thẻ đơn
        // rời rạc (ĐÚNG hành vi mặc định từ trước Giai đoạn 115) — mỗi thẻ tự biết mình thuộc 1
        // MAC đa kênh (isPartOfMultiChannel: true) để hiện lối vào "Gộp thành 1 thẻ" trong menu.
        // [GIAI ĐOẠN 126 — TRẢ LẠI CÔNG TẮC TỔNG] masterByMac[mac] LUÔN tồn tại cho mọi MAC đa
        // kênh (được dựng sẵn ở _buildDevicesGridBody, endpoint 'all', xem [MASTER SWITCH]) —
        // trước đây nhánh bung-lẻ này KHÔNG emit nó (chỉ dùng cho nhánh Gộp qua
        // _buildFaceplateEntry), khiến công tắc Tổng biến mất khi Tách. Emit nó làm THẺ ĐẦU TIÊN
        // qua ĐÚNG _buildSingleSwitchEntry — SmartSwitchCard đã tự vẽ icon riêng (settings_power_
        // rounded) khi isMaster=true (xem widget ở dưới), không cần thẻ/icon mới.
        final master = masterByMac[mac];
        if (master != null) {
          entries.add(_buildSingleSwitchEntry(master, provider, isPartOfMultiChannel: true));
        }
        for (final ch in channels) {
          entries.add(_buildSingleSwitchEntry(ch, provider, isPartOfMultiChannel: true));
        }
      }
    }
    return entries;
  }

  /// [GIAI ĐOẠN 115] Thiết bị Công tắc CHỈ 1 kênh — trích Y NGUYÊN logic entry gốc (trước khi có
  /// khối mặt công tắc), KHÔNG đổi 1 dòng hành vi/hình dáng cho đa số thiết bị (1-gang) đang có.
  /// [GIAI ĐOẠN 125] Nay TÁI DÙNG luôn cho từng kênh của thiết bị đa kênh đang ở chế độ BUNG LẺ
  /// (isPartOfMultiChannel: true) — thêm lối vào "Gộp thành 1 thẻ" trong menu qua onToggleGrouping.
  ({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight}) _buildSingleSwitchEntry(
    Map<String, dynamic> item,
    DeviceProvider provider, {
    required bool isPartOfMultiChannel,
  }) {
    final String mac = item['mac'];
    final String ep = item['endpoint'];
    final String deviceKey = "${mac}_$ep";
    final avatarEntry = _tryBuildAvatarEntry(deviceKey, 'switch', item, provider);
    if (avatarEntry != null) {
      // [GIỚI HẠN ĐÃ BIẾT] Thẻ Avatar tự có UI/menu RIÊNG (_openAvatarDeviceMenu, không đi qua
      // SmartSwitchCard._showDeviceOptions) — KHÔNG có điểm chèn onToggleGrouping. Nếu kênh này
      // đang gán Avatar riêng, người dùng cần Gộp lại qua 1 kênh KHÁC cùng MAC chưa gán Avatar
      // (hoặc qua chính khối đã Gộp nếu trước đó từng Gộp) — chấp nhận được, trường hợp hiếm.
      return (key: deviceKey, mac: mac, widget: avatarEntry.widget, gridSpanX: avatarEntry.gridSpanX, gridSpanY: avatarEntry.gridSpanY, autoHeight: false);
    }
    final bool isDevOnline = item['online'] == true;
    final String status = "${item['state']}_$isDevOnline";
    final bool isOn = item['state'] == 'ON';
    final cb = _stdCallbacks(mac, deviceKey, item['name'], endpoint: ep);
    return (key: deviceKey, mac: mac, gridSpanX: 1, gridSpanY: 1, autoHeight: false, widget: SmartSwitchCard(
      key: ValueKey("${mac}_${ep}_$status"),
      mac: mac,
      endpointKey: ep,
      backendName: item['name'],
      initialStatus: isOn,
      isOffline: !isDevOnline,
      isMaster: item['isMaster'] == true,
      provider: provider,
      onRefresh: _handleRefresh,
      rawDeviceData: item['rawDevice'],
      isHidden: _hiddenDevices.contains(deviceKey),
      isSelectionMode: _isSelectionMode,
      // [GIAI ĐOẠN 125] Chỉ hiện lối vào "Gộp thành 1 thẻ" khi kênh này THẬT SỰ thuộc 1 MAC đa
      // kênh (>=2 kênh) — thiết bị 1-gang thật sự không có gì để gộp, null tự ẩn mục menu.
      onToggleGrouping: isPartOfMultiChannel ? () => _setDeviceGrouped(mac, true) : null,
      isSelected: _selectedDevices.contains(deviceKey),
      hasHiddenDevices: _hiddenDevices.isNotEmpty,
      isShowingHidden: _showHiddenFilter,
      onToggleShowHidden: () => setState(() => _showHiddenFilter = !_showHiddenFilter),
      onEnterSelectionMode: () => setState(() { _isSelectionMode = true; _selectedDevices.add(deviceKey); }),
      onToggleSelect: () => setState(() { _selectedDevices.contains(deviceKey) ? _selectedDevices.remove(deviceKey) : _selectedDevices.add(deviceKey); if (_selectedDevices.isEmpty) _isSelectionMode = false; }),
      onToggleHide: (hide) => setState(() { hide ? _hiddenDevices.add(deviceKey) : _hiddenDevices.remove(deviceKey); _persistHiddenDevices(); }),
      onDelete: cb.delete,
      onRename: cb.rename,
      onChangeAvatar: cb.changeAvatar,
      onAssignHome: cb.assignHome,
      onAssignRoom: cb.assignRoom,
      onDeviceTimer: cb.timer,
      onDeviceHistory: cb.history,
      onDeviceAutomation: cb.automation,
      onDeviceShare: cb.share,
    ));
  }

  /// [GIAI ĐOẠN 115] Thiết bị Công tắc >=2 kênh CÙNG MAC — MỘT entry duy nhất (khối mặt công tắc
  /// vật lý). key/mac của entry = MAC trần (KHÔNG còn mac_endpoint) — Ẩn/Chọn nhiều/kéo-thả áp
  /// dụng cho CẢ KHỐI; mỗi nút con vẫn đọc avatar_map/tên RIÊNG theo endpoint của chính nó (xem
  /// vòng lặp cells bên dưới, dùng lại NGUYÊN _tryBuildAvatarEntry như thẻ đơn).
  ({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight}) _buildFaceplateEntry(
    String mac,
    List<Map<String, dynamic>> channels,
    Map<String, dynamic>? masterItem,
    DeviceProvider provider,
  ) {
    final bool anyOnline = channels.any((c) => c['online'] == true);
    // Tên khối mặc định: ưu tiên tên nút "Tất cả (N kênh)" đã có sẵn (masterItem, xem
    // allSwitches ở _buildDevicesGridBody) — nếu vì lý do gì đó không có (không nên xảy ra khi
    // channels.length>=2, nhưng phòng thủ), rơi về "sw-{4 cuối MAC}" đúng quy tắc đặt tên chung.
    final String deviceName = (masterItem?['name'] as String?) ??
        'sw-${(mac.length >= 4 ? mac.substring(mac.length - 4) : mac).toLowerCase()}';

    // [FIX GIAI ĐOẠN 123 — POPUP GIỜ TỰ DỰNG CELLS SỐNG] Trước đây dựng SẴN 1 mảng `cells` tĩnh ở
    // đây rồi truyền nguyên vào popup — ảnh snapshot ĐÓNG BĂNG tại thời điểm build entries, bấm
    // nút trong popup không đổi màu ngay vì popup KHÔNG nằm trong chu trình rebuild của
    // Consumer<DeviceProvider> bọc _buildDevicesGridBody. Nay popup tự dựng cells NGAY BÊN TRONG
    // Consumer<DeviceProvider> riêng của nó (xem _buildFaceplateCellsLive/_showFaceplateExpanded)
    // — hàm này chỉ còn cần truyền [channels] (cấu trúc kênh: endpoint/tên, ổn định) sang, không
    // cần dựng cells nữa.

    // [FIX GIAI ĐOẠN 116] "Ẩn cả khối" (menu tiêu đề) hiển thị ĐANG ẨN chỉ khi TẤT CẢ kênh đều bị
    // ẩn — dùng để quyết định overlay xám của khối; việc ẩn/hiện thật vẫn ghi từng hideKey riêng
    // (xem _openFaceplateDeviceMenu), không có khái niệm "khoá ẩn cấp khối" nào tồn tại.
    final bool allHidden = channels.every((c) => _hiddenDevices.contains("${mac}_${c['endpoint']}"));
    final bool isOffline = !anyOnline;

    // [GIAI ĐOẠN 120 — Ô THU GỌN 1x1] TỐI ĐA 4 nút mini hiện trực tiếp trên lưới chính (đủ cho
    // 2/3/4-gang); >4 kênh (vd 8-gang) hiện 3 nút đầu + 1 ô "+N" — cả 2 đều mở popup phóng to khi
    // chạm (xem _FaceplateMoreButton/_showFaceplateExpanded). Dùng LẠI chính callback onTap/
    // onLongPress đã gắn cho từng kênh trong [cells] (không xây lại logic toggle/menu lần 2).
    final List<Widget> miniCells = [];
    final int miniShown = channels.length > 4 ? 3 : channels.length;
    for (int i = 0; i < miniShown; i++) {
      final item = channels[i];
      final String ep = item['endpoint'] as String;
      final String hideKey = "${mac}_$ep";
      final bool isOn = item['state'] == 'ON';
      final bool chOffline = item['online'] != true;
      miniCells.add(KeyedSubtree(
        key: ValueKey('mini_$hideKey'),
        child: _FaceplateMiniButton(
          isOn: isOn,
          isOffline: chOffline,
          onTap: () {
            if (_isSelectionMode) {
              setState(() {
                _selectedDevices.contains(hideKey) ? _selectedDevices.remove(hideKey) : _selectedDevices.add(hideKey);
                if (_selectedDevices.isEmpty) _isSelectionMode = false;
              });
            } else {
              provider.toggleDevice(mac, ep, isOn);
            }
          },
          onLongPress: () => _openGangMenu(mac, hideKey, (item['name'] as String?)?.isNotEmpty == true ? item['name'] as String : ep, ep),
        ),
      ));
    }
    final String groupKey = mac; // vẫn dùng làm entry.key/entry.mac cho kéo-thả/grid-layout — KHÔNG liên quan gì đến Ẩn/Chọn nhiều
    void expand() => _showFaceplateExpanded(
          mac: mac,
          groupKey: groupKey,
          deviceName: deviceName,
          channels: channels,
          masterItem: masterItem,
          isHidden: allHidden,
        );
    if (channels.length > 4) {
      miniCells.add(_FaceplateMoreButton(remaining: channels.length - 3, onTap: expand));
    }

    // [FIX GIAI ĐOẠN 120 — SỬA ĐÚNG "2-4 CỘT LÀM NÁT BỐ CỤC"] TẤT CẢ khối đa kênh giờ span=1
    // (vuông, bằng đúng công tắc đơn) — trước đây 3-4 gang span=2 bị luật "full-width thẻ lớn
    // Mobile" (Giai đoạn 107) đẩy lên chiếm TRỌN bề ngang, phá nhịp lưới đều của các ô 1x1 xung
    // quanh. Nội dung chi tiết chuyển hẳn vào popup (_showFaceplateExpanded) thay vì cố nhét vừa
    // trong 1 ô lưới bình thường.
    return (
      key: groupKey,
      mac: mac,
      gridSpanX: 1,
      gridSpanY: 1,
      autoHeight: false,
      widget: _FaceplateCompactCard(
        channelCount: channels.length,
        miniCells: miniCells,
        isOffline: isOffline,
        isHidden: allHidden,
        onExpand: expand,
      ),
    );
  }

  // [FIX — GỠ STAGGEREDGRID, DÙNG Wrap ĐỂ TÔN TRỌNG TUYỆT ĐỐI THỨ TỰ ĐÃ KÉO-THẢ] StaggeredGrid
  // (gói flutter_staggered_grid_view) dùng thuật toán "shelf best-fit" — mỗi thẻ được đặt vào
  // CỘT nào đang trống thấp nhất tại thời điểm xét (_findBestCandidate trong source gói), KHÔNG
  // phải cứ theo đúng thứ tự mảng trái-sang-phải-trên-xuống-dưới. Hệ quả: một thẻ NHỎ nằm SAU
  // trong mảng entries có thể được "hút" lên hiển thị TRƯỚC một thẻ LỚN đứng trước nó trong mảng
  // (nếu thẻ lớn chưa tìm được chỗ vừa mà thẻ nhỏ thì có) — phá vỡ đúng thứ tự device_order người
  // dùng vừa kéo-thả lưu, dù dữ liệu/logic lưu thứ tự (đọc ở _fetchDevicesForHome, ghi ở
  // _saveDeviceOrder) hoàn toàn đúng. Đây là lỗi CHỌN SAI THUẬT TOÁN LƯỚI cho use-case này —
  // bin-packing hợp với feed kiểu Pinterest (thứ tự không quan trọng), KHÔNG hợp với dashboard có
  // kéo-thả sắp xếp (thứ tự LÀ yêu cầu cứng).
  //
  // Đổi sang Wrap: chảy TUẦN TỰ đúng thứ tự mảng, hết chỗ ngang thì tự xuống dòng mới — thẻ lớn
  // không vừa nốt hàng hiện tại thì rớt hẳn xuống dòng dưới (để lại khoảng trống ở hàng trên,
  // CHẤP NHẬN ĐƯỢC — đổi lấy đúng thứ tự tuyệt đối, đúng ưu tiên người dùng chọn). gridSpanX (đã
  // có sẵn từ Bước 5) giờ dùng làm HỆ SỐ BỀ RỘNG thay vì số ô lưới: 1 = thẻ nhỏ (Công tắc/hầu hết
  // Avatar), 2 = thẻ lớn (Quạt/Cửa cuốn/Cảm biến mặc định + Avatar 2 cột như AC/HVAC/Thang máy).
  //
  // [gridSpanY/autoHeight KHÔNG còn dùng ở đây] Wrap tự đo chiều cao THẬT của từng con theo
  // chiều rộng được cấp — không còn khái niệm "ép chiều cao cứng" từng gây tràn đáy
  // (StaggeredGridTile.count) nên KHÔNG cần phân biệt autoHeight=true/false nữa; giữ nguyên 2
  // field này trong record/lúc gọi entries.add() (không rủi ro khi thừa, chỉ đơn giản không đọc
  // tới) để tránh phải sửa lại ~14 chỗ dựng entries chỉ để xoá 2 field không còn ý nghĩa.
  // [FIX GIAI ĐOẠN 113] Dùng chung _gridColumns() — xem giải thích đầy đủ ở _switchCrossAxisCount.
  double _smallCardWidth(double availableWidth) {
    const double spacing = 16;
    final int columns = _gridColumns(availableWidth);
    return (availableWidth - spacing * (columns - 1)) / columns;
  }

  // [GIAI ĐOẠN 108, TÁCH RA THÀNH HÀM RIÊNG Ở GIAI ĐOẠN 113] Hợp nhất [entries] (2 khối "thẻ
  // lớn"+"Công tắc" nối thẳng, xem nơi gọi) theo ĐÚNG macOrderRank — sort ỔN ĐỊNH (tiebreak bằng
  // chỉ số gốc, vì List.sort của Dart KHÔNG đảm bảo stable) để giữ nguyên thứ tự kênh nội bộ của
  // từng MAC đa kênh. Đây là đường mặc định khi người dùng CHƯA từng dùng tính năng "khoảng
  // trống" (Giai đoạn 113, xem _applyGridLayout) — 2 đường merge SONG SONG tồn tại, KHÔNG đường
  // nào thay thế đường kia.
  List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> _mergeEntriesByMacOrderRank(
    List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> entries,
    Map<String, int> macOrderRank,
  ) {
    final List<int> mergeOrder = List<int>.generate(entries.length, (i) => i)
      ..sort((ia, ib) {
        final int ra = macOrderRank[entries[ia].mac] ?? 999999;
        final int rb = macOrderRank[entries[ib].mac] ?? 999999;
        if (ra != rb) return ra.compareTo(rb);
        return ia.compareTo(ib);
      });
    return [for (final i in mergeOrder) entries[i]];
  }

  // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Hợp nhất [entries] (dựng từ thiết bị SỐNG)
  // với _gridLayoutSlots (đã lưu — hideKey thật xen "EMPTY"/"SKIP") thành thứ tự HIỂN THỊ cuối
  // cùng. CHỈ gọi khi _gridLayoutSlots.isNotEmpty (nơi gọi tự kiểm tra) — người dùng CHƯA từng
  // dùng tính năng khoảng trống thì KHÔNG đụng tới hàm này, vẫn đi đường _mergeEntriesByMacOrderRank cũ.
  List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> _applyGridLayout(
    List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> entries,
  ) {
    final Map<String, ({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> byKey = {
      for (final e in entries) e.key: e,
    };
    final List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> result = [];
    int emptyCounter = 0;
    for (final token in _gridLayoutSlots) {
      // "SKIP" = ô bị "nuốt" bởi span của thẻ lớn đứng ngay trước — Wrap tự tính width theo
      // gridSpanX của thẻ đó (xem _buildAvatarStaggeredGrid), KHÔNG cần vẽ ô riêng cho SKIP.
      if (token == _kSkipToken) continue;
      if (token == _kEmptyToken) {
        result.add((key: 'empty_${emptyCounter++}', mac: _kEmptySlotMac, gridSpanX: 1, gridSpanY: 1, autoHeight: false, widget: const SizedBox.shrink()));
        continue;
      }
      // token trỏ tới thiết bị đã bị xoá/không còn hiển thị (ẩn/mất kết nối vĩnh viễn) kể từ lần
      // lưu trước -> TỰ BỎ QUA (self-heal, giống hệt triết lý "MAC lạ rơi cuối" của device_order,
      // chỉ khác chiều: ở đây token lạ bị loại thay vì được giữ).
      final entry = byKey.remove(token);
      if (entry != null) result.add(entry);
    }
    // Thiết bị MỚI (chưa từng có trong layout đã lưu, vd vừa thêm) -> rơi CUỐI, giữ nguyên thứ tự
    // tương đối gốc — cùng triết lý "rank map, unknown-appends-at-end" dùng xuyên suốt hệ thống.
    result.addAll(byKey.values);
    return result;
  }

  Widget _buildAvatarStaggeredGrid(List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> entries, bool isDark) {
    if (entries.isEmpty) {
      return _buildEmptyState(isDark, isDark ? Colors.white54 : const Color(0xFF64748B), "Khu vực này chưa kết nối với thiết bị/Hub nào.");
    }
    return LayoutBuilder(builder: (context, constraints) {
      final double smallWidth = _smallCardWidth(constraints.maxWidth);
      // [FIX GIAI ĐOẠN 107] Mobile (<600px) — ranh giới ĐÃ DÙNG SẴN cho _switchCrossAxisCount/
      // _buildEmptyState ở trên, tái dùng đúng mốc này thay vì bịa số mới.
      final bool isMobile = constraints.maxWidth < 600;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final en in entries)
            SizedBox(
              // [FIX #2 — THẺ LỚN TRÀN FULL BỀ RỘNG TRÊN MOBILE] Trước đây MỌI thẻ (kể cả span 2 —
              // Quạt/Cảm biến/Cửa cuốn...) đều tính theo công thức cột "smallWidth*N + gap*(N-1)" —
              // trên Mobile (Wrap chỉ có 3 cột nhỏ) một thẻ span-2 chỉ chiếm ĐÚNG 2/3 bề ngang, để
              // lại khoảng trống 1/3 bên phải rất khó chịu (đúng report của người dùng). Nay: Mobile
              // + thẻ lớn (gridSpanX > 1) -> ép width = TRỌN bề ngang khả dụng (constraints.maxWidth,
              // đã là bề rộng NỘI DUNG thật sau mọi lề ngoài — LayoutBuilder này nằm trong Column đã
              // được đặt trong Padding của màn hình). Tablet/PC hoặc thẻ nhỏ (span 1) giữ NGUYÊN công
              // thức cột cũ.
              width: (isMobile && en.gridSpanX > 1)
                  ? constraints.maxWidth
                  : smallWidth * en.gridSpanX + 16 * (en.gridSpanX - 1),
              // [FIX #1 — THẺ NHỎ BẮT BUỘC VUÔNG 1:1] Trước đây SizedBox chỉ khoá width, height thả
              // tự do theo nội dung bên trong (SmartSwitchCard không có AspectRatio/height cố định)
              // -> thẻ Công tắc bị "dẹt" thành chữ nhật thay vì vuông chuẩn (khác hẳn chế độ Sửa,
              // nơi _buildInPlaceEditWrap ép cứng SizedBox(width:switchCellWidth, height:switchCellWidth)
              // — đúng nguyên nhân "thẻ nhảy cỡ giữa 2 chế độ"). Nay ép height = ĐÚNG width của 1 ô
              // lưới (smallWidth) cho mọi thẻ span 1 (Công tắc mặc định lẫn Avatar 1 ô) — vuông tuyệt
              // đối, khớp luôn công thức chế độ Sửa. Thẻ lớn (span > 1) giữ height tự nhiên (null) —
              // các thẻ này (SmartFanCard...) đã tự thiết kế nội dung riêng, không nên ép vuông.
              height: en.gridSpanX == 1 ? smallWidth : null,
              child: KeyedSubtree(key: ValueKey(en.key), child: en.widget),
            ),
        ],
      );
    });
  }

  // [GIAI ĐOẠN 75] Lưới edit-mode CỘNG THÊM — dựng lại ĐÚNG các Widget thẻ gốc (không phải icon
  // giả), bọc AbsorbPointer (khóa chạm bên trong, chỉ còn kéo-thả) rồi bọc tiếp _JiggleTile (rung
  // lắc iOS). visibleFans...visibleSwitches truyền vào ĐÃ tính sẵn từ _buildDevicesGridBody —
  // hàm này CHỈ đọc, không tính lại DPS.
  Widget _buildInPlaceEditWrap(
    List<Map<String, dynamic>> visibleFans,
    List<Map<String, dynamic>> visibleSensors,
    List<Map<String, dynamic>> visibleRollingDoors,
    List<Map<String, dynamic>> visiblePumps,
    List<Map<String, dynamic>> visibleDimmers,
    List<Map<String, dynamic>> visibleGenericPrimary,
    List<Map<String, dynamic>> visibleSwitches,
    DeviceProvider provider,
    bool isDark,
  ) {
    // [GIAI ĐOẠN 104] Bọc LayoutBuilder NGOÀI CÙNG để lấy constraints.maxWidth THẬT — thẻ Công
    // tắc trong chế độ Sửa dùng CHUNG công thức _switchCellWidth() với lưới chế độ thường
    // (_buildSwitchGrid), thay cho 130px cố định trước đây (nguyên nhân lệch cột trên màn hình
    // hẹp — xem giải thích đầy đủ ở _buildAllDeviceCardEntries).
    return LayoutBuilder(builder: (context, constraints) {
    final double switchCellWidth = _switchCellWidth(constraints.maxWidth);
    final Map<String, String> macByKey = {};
    final Map<String, Widget> widgetByKey = {};

    // [FIX GIAI ĐOẠN 107] categoryByKey (Giai đoạn 90) chỉ tồn tại để phục vụ việc tách 2 nhóm
    // kéo-thả của Giai đoạn 104 — nay đã bỏ hẳn khái niệm nhóm (xem đoạn ReorderableWrap hợp nhất
    // bên dưới) nên tham số [category] giữ nguyên chữ ký cho 7 lời gọi addEntry() khỏi phải sửa,
    // nhưng không còn được lưu/đọc ở đâu nữa.
    void addEntry(String key, String mac, String category, Widget rawCard) {
      macByKey[key] = mac;
      // AbsorbPointer chặn TOÀN BỘ tap/swipe vào nội dung thẻ gốc (nút bật/tắt quạt, slider cửa
      // cuốn...) — thẻ chỉ còn dùng để cầm-kéo. _JiggleTile bọc NGOÀI CÙNG để cả khối rung lắc.
      widgetByKey[key] = _JiggleTile(
        key: ValueKey('jiggle_$key'),
        child: AbsorbPointer(child: rawCard),
      );
    }

    // [FIX GIAI ĐOẠN 105 — "THẺ MA" KẸT Ở OVERLAY KHI KÉO-THẢ] Toàn bộ 7 vòng lặp bên dưới TRƯỚC
    // ĐÂY gắn Key cho thẻ gốc (SmartFanCard/SmartSensorCard/...) kèm DỮ LIỆU SỐNG (speed/swing/
    // temp/hum/state/online...) — vd 'edit_${hideKey}_$status'. Đây là chỗ nguy hiểm THẬT SỰ:
    // _buildInPlaceEditWrap chạy TRONG Consumer<DeviceProvider>, mỗi gói MQTT cập nhật tốc độ
    // Quạt/độ ẩm Cảm biến... đều kích build() lại NGAY LẬP TỨC, kể cả khi người dùng đang GIỮ TAY
    // kéo thẻ đó. Key đổi giá trị -> Flutter coi widget con là MỘT PHẦN TỬ HOÀN TOÀN MỚI (unmount
    // + remount) NGAY GIỮA cử chỉ kéo — trong khi gói "reorderables" (ReorderableWrap) đã chụp lại
    // tham chiếu RenderBox/kích thước của phần tử CŨ lúc bắt đầu kéo (_draggingFeedbackSize,
    // _dragStartIndex...) để dựng khung overlay (drag feedback/ghost). Phần tử cũ bị hủy đột ngột
    // giữa chừng khiến overlay đó KHÔNG còn gắn với bất kỳ Element sống nào để tự dọn dẹp khi thả
    // tay — kẹt lại, rung mãi, dữ liệu không cập nhật (đúng triệu chứng người dùng chụp lại: thẻ
    // Quạt dễ trúng nhất vì tốc độ/đảo gió đổi liên tục qua MQTT). Nay ĐỔI Key mọi thẻ trong chế
    // độ Sửa về CHỈ hideKey (định danh thiết bị ỔN ĐỊNH, không đổi theo trạng thái) — khớp đúng
    // key CHA (_JiggleTile) vốn đã ổn định sẵn. Card vẫn nhận dữ liệu MỚI qua props/didUpdateWidget
    // bình thường — KHÔNG cần remount để cập nhật hiển thị; card gốc bị AbsorbPointer khóa chạm
    // hoàn toàn trong chế độ Sửa nên không cần đồng bộ tức thời tuyệt đối trong lúc đang kéo.

    for (final e in visibleFans) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final String renameEndpoint = (e['endpoint'] as String).startsWith('S_') || RegExp(r'^[Ff]\d+$').hasMatch(e['endpoint'])
          ? e['endpoint'] : 'S_${e['mac']}';
      final cb = _stdCallbacks(e['mac'], "${e['mac']}_$renameEndpoint", e['name'], endpoint: renameEndpoint);
      addEntry(hideKey, e['mac'] as String, 'fan', SmartFanCard(
        key: ValueKey('edit_$hideKey'),
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
        onToggleHide: (_) {},
        onDelete: cb.delete,
        onRename: cb.rename,
        onAssignHome: cb.assignHome,
        onAssignRoom: cb.assignRoom,
        onDeviceTimer: cb.timer,
        onDeviceHistory: cb.history,
        onDeviceAutomation: cb.automation,
        onDeviceShare: cb.share,
      ));
    }

    for (final e in visibleSensors) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      addEntry(hideKey, e['mac'] as String, 'sensor', SmartSensorCard(
        key: ValueKey('edit_$hideKey'),
        mac: e['mac'],
        endpoint: e['endpoint'],
        name: e['name'],
        temperature: e['temp'],
        humidity: e['hum'],
        isOffline: e['online'] != true,
        isHidden: _hiddenDevices.contains(hideKey),
        provider: provider,
        rawDeviceData: Map<String, dynamic>.from(e['rawDevice'] ?? {}),
        onToggleHide: (_) {},
        onRename: cb.rename,
        onDelete: cb.delete,
        onAssignHome: cb.assignHome,
        onAssignRoom: cb.assignRoom,
        onDeviceTimer: cb.timer,
        onDeviceHistory: cb.history,
        onDeviceAutomation: cb.automation,
        onDeviceShare: cb.share,
      ));
    }

    for (final e in visibleRollingDoors) {
      final String hideKey = "${e['mac']}_${e['upEp']}";
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['upEp']);
      addEntry(hideKey, e['mac'] as String, 'rollingDoor', SmartRollingDoorCard(
        key: ValueKey('edit_$hideKey'),
        mac: e['mac'],
        upEndpoint: e['upEp'], downEndpoint: e['downEp'], stopEndpoint: e['stopEp'],
        backendName: e['name'],
        isOffline: e['online'] != true,
        travelTimeSec: e['travelSec'] ?? 0,
        initialPositionPct: e['positionPct'] ?? 0,
        provider: provider,
        isHidden: _hiddenDevices.contains(hideKey),
        onToggleHide: (_) {},
        onOpenSettings: () {},
        callbacks: cb,
      ));
    }

    for (final e in visiblePumps) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      addEntry(hideKey, e['mac'] as String, 'pump', SmartPumpCard(
        key: ValueKey('edit_$hideKey'),
        mac: e['mac'],
        endpoint: e['endpoint'],
        isOn: e['state'] == 'ON',
        isOffline: e['online'] != true,
        backendName: e['name'],
        provider: provider,
        isHidden: _hiddenDevices.contains(hideKey),
        onToggleHide: (_) {},
        onOpenSettings: () {},
        callbacks: cb,
      ));
    }

    for (final e in visibleDimmers) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      addEntry(hideKey, e['mac'] as String, 'dimmer', SmartDimmerCard(
        key: ValueKey('edit_$hideKey'),
        mac: e['mac'],
        endpoint: e['endpoint'],
        isOn: e['state'] == 'ON',
        brightness: e['brightness'] ?? 0,
        isOffline: e['online'] != true,
        backendName: e['name'],
        provider: provider,
        isHidden: _hiddenDevices.contains(hideKey),
        onToggleHide: (_) {},
        onOpenSettings: () {},
        callbacks: cb,
      ));
    }

    for (final e in visibleGenericPrimary) {
      final String hideKey = "${e['mac']}_${e['endpoint']}";
      final cb = _stdCallbacks(e['mac'], hideKey, e['name'], endpoint: e['endpoint']);
      addEntry(hideKey, e['mac'] as String, 'generic', GenericDeviceCard(
        key: ValueKey('edit_$hideKey'),
        mac: e['mac'],
        endpoint: e['endpoint'],
        category: e['category'] ?? '',
        isOn: e['state'] == 'ON',
        isOffline: e['online'] != true,
        backendName: e['name'],
        provider: provider,
        isHidden: _hiddenDevices.contains(hideKey),
        onToggleHide: (_) {},
        onOpenSettings: () {},
        callbacks: cb,
      ));
    }

    // [GIAI ĐOẠN 115] Gom theo MAC — ĐÚNG cùng quy tắc với _buildSwitchCardEntries (chế độ
    // thường): 1-gang giữ nguyên SmartSwitchCard đơn, >=2-gang gộp thành PhysicalSwitchBlockCard.
    // Không đổi thì chế độ Sửa/thường sẽ "nhảy hình dạng" khác nhau — phá đúng nguyên tắc đã giữ
    // xuyên suốt từ Giai đoạn 90/104.
    final Map<String, List<Map<String, dynamic>>> editChannelsByMac = {};
    final Map<String, Map<String, dynamic>> editMasterByMac = {};
    for (final item in visibleSwitches) {
      final String mac = item['mac'] as String;
      if (item['isMaster'] == true) { editMasterByMac[mac] = item; continue; }
      editChannelsByMac.putIfAbsent(mac, () => []).add(item);
    }
    // [GIAI ĐOẠN 125 — GỘP/TÁCH, CHẾ ĐỘ SỬA] Tách phần dựng 1 thẻ SmartSwitchCard đơn ra hàm dùng
    // chung — vừa phục vụ nhánh 1-gang thật (channels.length == 1) vừa phục vụ nhánh BUNG LẺ (>=2
    // kênh nhưng _deviceGrouped[mac] != true) bên dưới, tránh lặp y hệt 40 dòng.
    void addSingleSwitchEntry(Map<String, dynamic> single, String mac) {
      final String ep = single['endpoint'] as String;
      final String deviceKey = "${mac}_$ep";
      final bool isDevOnline = single['online'] == true;
      final bool isOn = single['state'] == 'ON';
      final cb = _stdCallbacks(mac, deviceKey, single['name'], endpoint: ep);
      // [BOUNDED SIZE] SmartSwitchCard bình thường CHỈ sống trong GridView (kích thước ép bởi
      // childAspectRatio) — Wrap cấp constraint KHÔNG giới hạn cho từng con, phải tự bọc SizedBox
      // vuông. [GIAI ĐOẠN 104] Cỡ ô nay dùng switchCellWidth (co giãn theo constraints.maxWidth
      // thật, CHUNG công thức với lưới chế độ thường) thay vì 130px cố định — đảm bảo LUÔN đúng
      // số cột kể cả màn hình hẹp, và khớp cỡ 1:1 với chế độ thường (không "nhảy" cỡ).
      addEntry(deviceKey, mac, 'switch', SizedBox(
        width: switchCellWidth,
        height: switchCellWidth,
        child: SmartSwitchCard(
          key: ValueKey('edit_${mac}_$ep'),
          mac: mac,
          endpointKey: ep,
          backendName: single['name'],
          initialStatus: isOn,
          isOffline: !isDevOnline,
          isMaster: single['isMaster'] == true,
          provider: provider,
          onRefresh: _handleRefresh,
          rawDeviceData: single['rawDevice'],
          isHidden: _hiddenDevices.contains(deviceKey),
          isSelectionMode: false,
          isSelected: false,
          hasHiddenDevices: false,
          isShowingHidden: false,
          onToggleShowHidden: () {},
          onEnterSelectionMode: () {},
          onToggleSelect: () {},
          onToggleHide: (_) {},
          onDelete: cb.delete,
          onRename: cb.rename,
          onAssignHome: cb.assignHome,
          onAssignRoom: cb.assignRoom,
          onDeviceTimer: cb.timer,
          onDeviceHistory: cb.history,
          onDeviceAutomation: cb.automation,
          onDeviceShare: cb.share,
        ),
      ));
    }

    final Set<String> editEmittedMacs = {};
    for (final item in visibleSwitches) {
      if (item['isMaster'] == true) continue;
      final String mac = item['mac'] as String;
      if (!editEmittedMacs.add(mac)) continue;
      final channels = editChannelsByMac[mac]!;

      if (channels.length == 1) {
        addSingleSwitchEntry(channels.first, mac);
      } else if (_deviceGrouped[mac] ?? false) {
        // [KHỐI MẶT CÔNG TẮC — CHẾ ĐỘ SỬA] Callback bên trong đều NO-OP: addEntry() bọc
        // AbsorbPointer ngoài cùng đã chặn hết tương tác (chỉ còn dùng để cầm-kéo), giống hệt
        // nguyên tắc mọi thẻ khác trong chế độ Sửa (xem addEntry ở trên).
        // [FIX GIAI ĐOẠN 120] Dùng ĐÚNG _FaceplateCompactCard (span=1, vuông switchCellWidth) —
        // KHÔNG còn PhysicalSwitchBlockCard cỡ lớn ở đây nữa, khớp với hình dạng THẬT sẽ hiện ở
        // chế độ thường (nguyên tắc "không nhảy cỡ giữa 2 chế độ", Giai đoạn 90/104/107).
        final bool anyOnline = channels.any((c) => c['online'] == true);
        final int miniShown = channels.length > 4 ? 3 : channels.length;
        final List<Widget> miniCells = [
          for (int i = 0; i < miniShown; i++)
            _FaceplateMiniButton(
              isOn: channels[i]['state'] == 'ON',
              isOffline: channels[i]['online'] != true,
              onTap: () {},
              onLongPress: () {},
            ),
        ];
        if (channels.length > 4) miniCells.add(_FaceplateMoreButton(remaining: channels.length - 3, onTap: () {}));
        addEntry(mac, mac, 'switch', SizedBox(
          width: switchCellWidth,
          height: switchCellWidth,
          child: _FaceplateCompactCard(
            channelCount: channels.length,
            miniCells: miniCells,
            isOffline: !anyOnline,
            // [FIX GIAI ĐOẠN 116] Ẩn per-endpoint như bản chính — hiển thị "đã ẩn" chỉ khi TẤT CẢ
            // kênh trong khối đều bị ẩn (không có khoá ẩn cấp khối).
            isHidden: channels.every((c) => _hiddenDevices.contains("${mac}_${c['endpoint']}")),
            onExpand: () {},
          ),
        ));
      } else {
        // [GIAI ĐOẠN 125 — GỘP/TÁCH, CHẾ ĐỘ SỬA] _deviceGrouped[mac] == false (mặc định) -> khớp
        // ĐÚNG nhánh "bung lẻ" của _buildSwitchCardEntries (chế độ thường): vẽ N thẻ SmartSwitchCard
        // rời thay vì 1 khối _FaceplateCompactCard — giữ nguyên tắc "không nhảy hình dạng giữa 2
        // chế độ" cho đúng lựa chọn Gộp/Tách người dùng đã chọn, không phải luôn luôn gộp như cũ.
        // [GIAI ĐOẠN 126] Khớp đúng thẻ Tổng vừa trả lại ở _buildSwitchCardEntries — chế độ Sửa
        // KHÔNG được lệch hình dạng với chế độ thường.
        final master = editMasterByMac[mac];
        if (master != null) addSingleSwitchEntry(master, mac);
        for (final single in channels) {
          addSingleSwitchEntry(single, mac);
        }
      }
    }

    // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Dựng thêm entry cho MỌI "ô trống" người
    // dùng đã thêm — nguồn DUY NHẤT là _editOrderDraft (không có "thiết bị sống" nào đại diện cho
    // khái niệm ô trống). Đăng ký vào macByKey/widgetByKey CÙNG CƠ CHẾ với thẻ thật để commitReorder()
    // và ReorderableWrap bên dưới xử lý đồng nhất, không cần nhánh riêng.
    for (final d in _editOrderDraft) {
      if (d.mac != _kEmptySlotMac) continue;
      macByKey[d.key] = _kEmptySlotMac;
      widgetByKey[d.key] = _EmptySlotEditTile(
        size: switchCellWidth,
        onDelete: () => setState(() {
          _editOrderDraft = _editOrderDraft.where((x) => x.key != d.key).toList();
        }),
      );
    }

    if (widgetByKey.isEmpty) {
      return _buildEmptyState(isDark, isDark ? Colors.white54 : const Color(0xFF64748B), "Chưa có thiết bị nào để sắp xếp.");
    }

    // Sắp theo _editOrderDraft đã lưu; thẻ MỚI (chưa từng thấy trong draft, vd vừa thêm thiết
    // bị) rơi xuống CUỐI, giữ nguyên thứ tự tự nhiên giữa chúng — cùng kỹ thuật rank map với
    // applyDeviceOrder() phía Backend.
    final Set<String> knownKeys = widgetByKey.keys.toSet();
    final List<String> orderedKeys = [
      for (final d in _editOrderDraft) if (knownKeys.contains(d.key)) d.key,
      for (final k in widgetByKey.keys) if (!_editOrderDraft.any((d) => d.key == k)) k,
    ];

    // [FIX GIAI ĐOẠN 107 — THAY THẾ HẲN BẢN TÁCH 2 NHÓM CỦA GIAI ĐOẠN 104] Bản 104 tách cứng
    // thành 2 ReorderableWrap độc lập (nhóm "thẻ lớn" LUÔN trước, nhóm "Công tắc" LUÔN sau) vì
    // lúc đó _buildDevicesGridBody (chế độ thường) đúng là vẽ theo 2 khối cố định như vậy. NHƯNG
    // Giai đoạn 100 (rewrite Wrap Tetris-fill) đã ĐỔI chế độ thường sang MỘT Wrap liên tục duy
    // nhất, chảy tuần tự theo ĐÚNG một mảng entries hợp nhất — không còn ranh giới cứng "khối lớn/
    // khối Công tắc" nữa (thẻ Công tắc có thể "leo" lên chen vào cuối hàng còn trống của khối lớn
    // do hiệu ứng tetris-fill của Wrap). Bản 104 KHÔNG được cập nhật theo, nên vẫn khoá cứng người
    // dùng chỉ được kéo Công tắc lẫn Công tắc / thẻ lớn lẫn thẻ lớn — bất kỳ ý định kéo xuyên nhóm
    // nào (điều Wrap hiển thị PHÍA TRÊN vẫn có thể trông như cho phép do tetris-fill) đều bị ép
    // quay về đúng nhóm cũ ngay khi lưu, đúng triệu chứng "kéo thả xong bấm Xong thì thiết bị hoàn
    // về vị trí cũ" người dùng báo. Nay bỏ HẲN khái niệm 2 nhóm — dùng ĐÚNG MỘT ReorderableWrap
    // cho TOÀN BỘ orderedKeys (khớp 1-1 với cách _buildDevicesGridBody nối
    // [..._buildAllDeviceCardEntries, ..._buildSwitchCardEntries] thành MỘT mảng entries) — kéo
    // thẻ bất kỳ tới vị trí bất kỳ trong TOÀN danh sách, lưu xong hiển thị lại ĐÚNG y hệt vị trí đã
    // kéo, không còn rào chắn nhóm giả tạo nào.
    void commitReorder(List<String> newKeys) {
      setState(() {
        _editOrderDraft = [for (final k in newKeys) (key: k, mac: macByKey[k]!)];
      });
    }

    return ReorderableWrap(
      spacing: 16,
      runSpacing: 16,
      // [GIỮ CUỘN TRANG] Mặc định gói (true) = phải giữ (long-press) mới bắt đầu kéo — một
      // chạm-kéo NGẮN vẫn cuộn trang bình thường (đúng hành vi iOS Jiggle thật: icon rung nhưng
      // trang vẫn cuộn được). AbsorbPointer đã chặn hết tap/swipe vào thẻ gốc nên giữ lâu ở đây
      // an toàn tuyệt đối, không lo "lỡ tay bật/tắt" — không cần ép kéo tức thì.
      needsLongPressDraggable: true,
      onReorder: (oldIndex, newIndex) {
        final newKeys = List<String>.from(orderedKeys)
          ..removeAt(oldIndex)
          ..insert(newIndex, orderedKeys[oldIndex]);
        commitReorder(newKeys);
      },
      children: [for (final k in orderedKeys) widgetByKey[k]!],
    );
    }); // đóng LayoutBuilder (constraints.maxWidth -> switchCellWidth)
  }

  // ==========================================================================
  // ➕ LIÊN KẾT THIẾT BỊ VỪA QUÉT/NHẬP VÀO NHÀ (POST /api/homes/:id/devices)
  // ==========================================================================
  /// AddDeviceDialog chỉ trả về mã MAC (String) — hàm này mới là nơi GỌI API THẬT.
  /// [FIX] Trước đây dashboard bỏ quên kết quả dialog: quét QR xong không link gì cả.
  /// [FIX TIẾP — lỗ hổng 409 thật] Trước đây hàm này TỰ gọi http.post() thô rồi hiện SnackBar đỏ
  /// chung chung cho MỌI lỗi kể cả 409 — luồng QR/Nhập tay/Quét LAN không hề có Dialog "Thiết bị
  /// đã có chủ" như luồng AP Mode (add_device_dialog.dart), lệch hẳn trải nghiệm giữa 2 lối vào
  /// cùng một tính năng. Nay dùng CHUNG ApiService.addDevice() (đã có type AddDeviceResult) +
  /// showOwnershipConflictDialog() dùng chung — 409 luôn ra đúng 1 Dialog dù đi lối nào.
  ///   - Thành công        -> SnackBar xanh + làm mới danh sách
  ///   - 409 đã có chủ     -> Dialog chuyên biệt + email chủ cũ đã che + nút "Gửi yêu cầu gỡ"
  ///   - Server chê khác   -> SnackBar đỏ kèm ĐÚNG thông báo lỗi server trả về
  ///   - Rớt mạng          -> SnackBar đỏ báo lỗi kết nối
  Future<void> _linkScannedDevice(dynamic dialogResult) async {
    // Dialog đóng không quét gì (null) hoặc luồng AP Mode trả bool -> không link
    if (dialogResult is! String || dialogResult.trim().isEmpty) return;
    final String mac = dialogResult.trim().toUpperCase();

    // Nhà đích: user thường = nhà trong token; SUPER_USER = nhà đang mở trên màn hình
    final String homeId = _provisioningTargetHomeId;
    if (homeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Chưa xác định được ngôi nhà — hãy mở một nhà cụ thể rồi thêm thiết bị.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    if (kDebugMode) print('🤝 [LINK] Gửi yêu cầu link $mac vào nhà $homeId...');
    final AddDeviceResult result = await ApiService().addDevice(homeId, mac);
    if (!mounted) return;

    switch (result.status) {
      case AddDeviceStatus.success:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Đã thêm thiết bị $mac vào nhà thành công!'),
          backgroundColor: const Color(0xFF00A651),
        ));
        // [FIX GIẬT LAG SAU "THÊM THIẾT BỊ"] Trước đây gọi _handleRefresh() — LUÔN set
        // isSilent:false (spinner toàn màn hình xóa sạch UI hiện có rồi vẽ lại từ đầu) + delay
        // 500ms cho hiệu ứng pull-to-refresh. Ở đây KHÔNG phải người dùng chủ động kéo-làm-mới —
        // chỉ cần danh sách thiết bị cập nhật ÊM, không xóa UI hiện có trước. isSilent:true vẫn
        // gọi ĐÚNG pipeline sync thật (DashboardSyncService().fetch()), chỉ khác ở chỗ KHÔNG bật
        // cờ loading toàn màn hình — dữ liệu mới về thì UI tự cập nhật êm, không "chớp" trắng.
        _initializeHome(isSilent: true);
        break;
      case AddDeviceStatus.ownershipConflict:
        // [LUỒNG CHUYỂN GIAO] KHÔNG hiện SnackBar chung chung nữa — bung đúng Dialog chuyên biệt
        // kèm email chủ cũ đã che + nút "Gửi yêu cầu gỡ" (dùng chung với luồng AP Mode).
        await showOwnershipConflictDialog(context, mac: mac, maskedOwnerEmail: result.maskedOwnerEmail);
        break;
      case AddDeviceStatus.networkError:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ Không thể kết nối máy chủ — kiểm tra mạng rồi thử lại.'),
          backgroundColor: Colors.redAccent,
        ));
        break;
      case AddDeviceStatus.notOnlineYet:
      case AddDeviceStatus.forbidden:
      case AddDeviceStatus.otherError:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ ${result.message ?? 'Lỗi máy chủ không xác định'}'),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ));
        break;
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
  void _showSettingsMenu({int initialTab = 0}) { showAppDialog(context: context, maxWidth: 1000, child: WindowsSettingsDialog(currentRole: userRole, currentEmail: userEmail, initialTab: initialTab, homeId: _provisioningTargetHomeId)); }

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

  // [PHÒNG] Chuyển HÀNG LOẠT thiết bị/kênh đã chọn vào 1 phòng (API thật qua RoomGroupProvider).
  // [FIX GOM CHÙM] _selectedDevices lưu theo TỪNG KÊNH ("MAC_endpoint" — xem hideKey/deviceKey ở
  // các nơi setState thêm/bớt selection), nhưng bản cũ gọi _selectedMacs() rút gọn về MAC rồi gán
  // NGUYÊN KHỐI qua assignDevicesToRoom — chọn riêng lẻ 1-2 kênh của công tắc đa nút để "Chuyển
  // phòng" hàng loạt vẫn kéo theo mọi kênh khác cùng MAC. Nay gom theo MAC rồi tự quyết định:
  // user đã tick ĐỦ mọi kênh điều khiển được của 1 MAC (hoặc chọn đúng nút "Tất cả") -> gán cả
  // thiết bị (tương đương, gọn 1 lời gọi); chỉ tick MỘT PHẦN kênh -> gán RIÊNG từng kênh đó qua
  // assignEndpointsToRoom, không đụng các kênh chưa được chọn.
  Future<void> _bulkAssignRoom() async {
    if (_selectedDevices.isEmpty) return;
    final roomProvider = Provider.of<RoomGroupProvider>(context, listen: false);
    final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
    final room = await showRoomSelectionDialog(context, roomProvider);
    if (room == null || !mounted) return;

    final Map<String, Set<String>> selectedEpsByMac = {};
    for (final key in _selectedDevices) {
      final idx = key.indexOf('_');
      if (idx <= 0) continue;
      selectedEpsByMac.putIfAbsent(key.substring(0, idx), () => {}).add(key.substring(idx + 1));
    }

    final List<String> wholeMacs = [];
    final List<({String mac, String endpoint})> partialItems = [];
    selectedEpsByMac.forEach((mac, selectedEps) {
      final device = deviceProvider.deviceOf(mac);
      final allChannels = device == null
          ? <String>{}
          : device.endpointIds.where((ep) => device.typeOf(ep) != 'sensor' && device.typeOf(ep) != 'fan').toSet();
      final bool selectedWhole = selectedEps.contains('all') ||
          allChannels.isEmpty ||
          allChannels.difference(selectedEps).isEmpty;
      if (selectedWhole) {
        wholeMacs.add(mac);
      } else {
        for (final ep in selectedEps) {
          if (ep != 'all') partialItems.add((mac: mac, endpoint: ep));
        }
      }
    });

    showDialog(context: context, barrierDismissible: false, builder: (_) => Center(child: CircularProgressIndicator(color: tkGreen)));
    String? err;
    if (wholeMacs.isNotEmpty) err = await roomProvider.assignDevicesToRoom(wholeMacs, room.id);
    if (err == null && partialItems.isNotEmpty) err = await roomProvider.assignEndpointsToRoom(partialItems, room.id);
    if (!mounted) return;
    Navigator.pop(context); // đóng loading
    final int total = wholeMacs.length + partialItems.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Đã chuyển $total thiết bị/kênh vào "${room.name}"'),
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
    VoidCallback changeAvatar, // [BƯỚC 5] mở popup "Thay đổi giao diện (Avatar)" từ menu nhấn-giữ
  }) _stdCallbacks(String mac, String key, String name, {String endpoint = ''}) => (
        rename: () => _showRenameDialog(key, name),
        delete: () => _deleteDevice(mac),
        // [FIX GOM CHÙM] endpoint của ĐÚNG thẻ vừa mở menu — cho _assignSingleRoom biết cần gán
        // riêng 1 kênh hay cả thiết bị (xem doc-comment tại đó).
        assignRoom: () => _assignSingleRoom(mac, endpoint),
        assignHome: _isSuperUser ? () => _showAssignHomeDialog(mac) : null,
        changeAvatar: () => _showAvatarPicker(key, mac),
        // [RESPONSIVE NAV] Mobile: push toàn màn hình; PC: cửa sổ dialog lớn nổi trên
        // Dashboard — Sidebar/Topbar phía sau GIỮ NGUYÊN, không bị route đè mất
        // [FIX MULTI-RELAY] endpoint truyền xuống DeviceTimerScreen -> Hẹn giờ/Đếm ngược chỉ
        // nhắm ĐÚNG kênh của thẻ vừa mở menu, không còn mù kênh (bắn cả cụm SSW04 4 relay).
        timer: () => openAdaptiveScreen(context, DeviceTimerScreen(mac: mac, endpoint: endpoint, deviceName: name)),
        history: () => openAdaptiveScreen(context, DeviceHistoryScreen(mac: mac, deviceName: name)),
        automation: () => openAdaptiveScreen(context, const CreateAutomationScreen()),
        share: () => showShareDeviceDialog(context, mac: mac, deviceName: name),
      );

  // [PHÒNG] Gán 1 thiết bị (hoặc đúng 1 kênh) vào phòng (từ menu ngữ cảnh của thẻ).
  // [FIX GOM CHÙM] Trước đây LUÔN gọi assignDevicesToRoom(mac) — gán NGUYÊN KHỐI cả thiết bị,
  // nên mở menu "Chuyển phòng" từ MỘT kênh của công tắc đa nút (SSW04...) vẫn kéo theo TẤT CẢ
  // kênh còn lại cùng MAC vào chung 1 phòng. Nay: [endpoint] rỗng/'all', hoặc thiết bị chỉ có
  // đúng 1 kênh điều khiển được -> giữ hành vi cũ (gán cả thiết bị, coi như tương đương). Thiết
  // bị ĐA KÊNH mở đúng từ 1 thẻ kênh cụ thể -> CHỈ gán riêng kênh đó qua assignEndpointsToRoom
  // (API tách kênh đã có sẵn ở Backend — cùng API mà RoomDetailScreen._pickChannels dùng).
  Future<void> _assignSingleRoom(String mac, [String endpoint = '']) async {
    final provider = Provider.of<RoomGroupProvider>(context, listen: false);
    final room = await showRoomSelectionDialog(context, provider);
    if (room == null || !mounted) return;

    final device = Provider.of<DeviceProvider>(context, listen: false).deviceOf(mac);
    final int channelCount = device == null
        ? 0
        : device.endpointIds.where((ep) => device.typeOf(ep) != 'sensor' && device.typeOf(ep) != 'fan').length;
    final bool wholeDevice = endpoint.isEmpty || endpoint == 'all' || channelCount <= 1;

    final err = wholeDevice
        ? await provider.assignDevicesToRoom([mac], room.id)
        : await provider.assignEndpointsToRoom([(mac: mac, endpoint: endpoint)], room.id);
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
                                  // [FIX — RenderFlex overflow trên màn hẹp] Tiêu đề + nút "Đọc tất
                                  // cả" cộng lại rộng hơn panel trên mobile (width - 32) -> Expanded
                                  // + ellipsis để tiêu đề co lại nhường chỗ cho nút, thay vì tràn ra
                                  // ngoài (không dùng Expanded thì Row tính kích thước tự nhiên của
                                  // cả 2 con, tràn phải khi tổng > panel).
                                  Expanded(
                                    child: Text(t.text('notifications_title'), style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                  const SizedBox(width: 8),
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
                // [FIX OVERFLOW] Giảm padding ngang 24 -> 16: nhường thêm không gian cho header
                // trên màn hẹp — vertical giữ nguyên 24 (không phải nguồn gây tràn).
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Row(
                  children: [
                    // [FIX OVERFLOW] Bọc Flexible + ellipsis đề phòng chuỗi dịch dài (locale khác)
                    // — trước đây ĐÃ Expanded nhưng thiếu maxLines, giữ nguyên tinh thần cũ.
                    Flexible(
                      child: Text(
                        t.text('notifications_full_title'),
                        style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // [FIX OVERFLOW — THỦ PHẠM CHÍNH] Trước đây cụm "Đánh dấu tất cả đã đọc" +
                    // "Đẩy (Push)" + Switch nằm chung 1 Row(mainAxisSize.min) KHÔNG co giãn được
                    // — màn hẹp không đủ chỗ là tràn ngay (sọc vàng-đen). Nay bọc Expanded cho
                    // nút Đánh dấu (chiếm hết chỗ trống, tự co lại) — tự build TextButton +
                    // Row(mainAxisSize.min) + Flexible(Text ellipsis) THAY VÌ TextButton.icon:
                    // constructor .icon KHÔNG tự bọc Flexible cho label bên trong, bản thân nó
                    // vẫn có thể tràn nội bộ khi bị ép quá chặt — tự build đảm bảo an toàn tuyệt
                    // đối ở mọi kích thước màn hình, đúng phương án dự phòng người dùng đề xuất.
                    if (notifProvider.unreadCount > 0)
                      Expanded(
                        child: TextButton(
                          onPressed: () => notifProvider.markAllRead(),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.centerLeft),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.done_all_rounded, size: 18, color: tkGreen),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  t.text('mark_all_read'),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(color: tkGreen, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 4),
                    // [FIX OVERFLOW] Cụm "Đẩy (Push)" + Switch bọc FittedBox — không bao giờ tràn
                    // dù bị ép chặt tới đâu (tự thu nhỏ thay vì tràn cứng ra ngoài).
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.text('push_short'), style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w600)),
                          Switch(value: _isPushEnabled, activeThumbColor: tkGreen, onChanged: (val) => setState(() => _isPushEnabled = val)),
                        ],
                      ),
                    ),
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
    // [ĐÍNH CHÍNH] Bản trước ép LUÔN chữ trắng khi Kính bật (kể cả Sáng+Kính) — SAI theo đúng
    // ảnh chụp thật người dùng gửi lại: Sáng+Kính phải giữ chữ TỐI (mặt kính ở đây được phủ
    // TRẮNG đục 60-70%, không phải tối), chỉ Tối+Kính mới cần chữ trắng. Quay về thuần isDark ở
    // cấp biến dùng chung này (AppBar/tiêu đề/bottom-nav — không nằm trên mặt kính riêng, sống
    // trực tiếp trên nền trang đã tự tính đúng sáng/tối); tương phản cho các mặt kính CỤ THỂ
    // (Drawer/Sidebar) tự xử lý riêng ngay tại nơi dùng — xem _buildMenuItem bên dưới.
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: bgLight,
      appBar: isMobile
          ? AppBar(
              backgroundColor: isGlass ? Colors.transparent : (isDark ? surfaceLight : bgLight), elevation: 0, iconTheme: IconThemeData(color: tkGreen),
              title: Text(_selectedIndex == 3 ? 'THÔNG BÁO' : _selectedIndex == 4 ? 'CÀI ĐẶT' : 'MY HOME', style: TextStyle(color: textMain, fontWeight: FontWeight.w900, letterSpacing: 1.2)), centerTitle: true,
              actions: _selectedIndex == 4 ? [] : [
                // [VÁ LỖ HỔNG "THIẾT BỊ MA"] Trước đây nút + hiện ở MỌI tab (trừ Cài đặt) — kể cả
                // khi đang ở Quản trị Hệ thống(7)/Quản trị Thiết bị(8)/Vai trò(6)/Quản lý Nhà(5),
                // nơi KHÔNG có ngữ cảnh 1 Ngôi nhà cụ thể. SUPER_USER bấm nhầm ở các tab đó tạo ra
                // AddDeviceDialog với homeId RỖNG -> thiết bị lơ lửng ngoài không gian. Nay CHỈ
                // hiện khi đang ở tab "MY HOME" (index 0) VÀ đã có ngữ cảnh nhà hợp lệ — cùng điều
                // kiện với nút + bản Desktop (xem "all_devices" section bên dưới).
                if (_selectedIndex == 0 && (userRole != 'SUPER_USER' || _selectedHomeForSuperUser != null)) ...[
                  // [GIAI ĐOẠN 72 — REWRITE] Cây bút -> chuyển isEditing tại chỗ, KHÔNG điều
                  // hướng màn hình nào. Đang sửa -> đổi thành nút "Xong" xanh, ẩn nút "+" (tránh
                  // thêm thiết bị giữa lúc đang kéo-thả làm lệch draft thứ tự).
                  _isEditingOrder
                      ? TextButton.icon(
                          // [FIX GIAI ĐOẠN 102 — TRUY VẾT NÚT LƯU] In NGAY dòng đầu tiên bên
                          // trong onPressed (KHÔNG phải bên trong _saveDeviceOrder() nữa) — nếu
                          // dòng này còn không hiện trong log khi bấm, chứng tỏ sự kiện chạm
                          // không tới được đây (bị Widget khác đè/che khuất), không phải lỗi
                          // logic bên trong hàm lưu.
                          onPressed: _savingOrder ? null : () {
                            if (kDebugMode) print('DEBUG: Nút Lưu đã được nhấn! (Mobile)');
                            _toggleEditOrder();
                          },
                          icon: _savingOrder
                              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
                              : Icon(Icons.check_circle_rounded, color: tkGreen, size: 20),
                          label: Text('Xong', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold)),
                        )
                      : IconButton(
                          icon: Icon(Icons.edit_note_rounded, color: textMain),
                          tooltip: 'Sắp xếp thiết bị',
                          onPressed: _toggleEditOrder,
                        ),
                  if (!_isEditingOrder)
                    IconButton(
                      icon: Icon(Icons.add_circle_outline_rounded, color: textMain),
                      onPressed: () async {
                        // [FIX] Bắt lấy mã MAC dialog trả về rồi GỌI API LINK THẬT
                        // (kèm SnackBar báo thành công/lỗi chi tiết) — trước đây kết quả bị vứt bỏ
                        // [FIX GIẬT LAG] KHÔNG gọi thêm _handleRefresh() ở đây nữa — _linkScannedDevice()
                        // đã tự làm mới (êm, không spinner) khi thành công. Gọi thêm lần 2 ở đây từng
                        // khiến toàn Dashboard chớp trắng LIÊN TIẾP HAI LẦN mỗi lần thêm thiết bị.
                        final result = await showAppDialog(context: context, contentPadding: const EdgeInsets.all(8), child: AddDeviceDialog(ownedMacs: _ownedMacs, homeId: _provisioningTargetHomeId));
                        await _linkScannedDevice(result);
                      },
                    ),
                ],
                _buildNotificationBell(textMain, textSub), const SizedBox(width: 8),
              ]
            )
          : null,
      // [ĐÓNG BĂNG RENDER] RepaintBoundary — Drawer chỉ hiện khi user vuốt mở nên ít khi là điểm
      // nóng, nhưng bọc luôn cho đồng bộ với Sidebar Desktop bên dưới, chống layer cha (nếu có
      // rebuild ngoài ý muốn) kéo theo vẽ lại nội dung Drawer.
      drawer: isMobile ? RepaintBoundary(child: _buildMobileDrawer(isDark, surfaceLight, textMain, textSub)) : null,

      body: Column(
        children: [
          // [ĐÓNG BĂNG RENDER] Header/title bar Desktop là vùng TĨNH (chỉ đổi khi bấm phóng to/
          // thu nhỏ/đóng cửa sổ) — RepaintBoundary chống nó bị kéo vẽ lại theo body bên dưới.
          if (!kIsWeb && !isMobile && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) RepaintBoundary(child: _buildCustomTitleBar(isDark)),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [ĐÓNG BĂNG RENDER] Sidebar Desktop là vùng TĨNH (menu điều hướng) — bọc
                // RepaintBoundary để lớp vẽ (paint layer) của nó độc lập với phần body bên cạnh
                // (nơi lưới thiết bị nhấp nháy liên tục theo MQTT); Flutter không cần vẽ lại
                // Sidebar mỗi khi layer body thay đổi.
                if (!isMobile) RepaintBoundary(child: _buildDesktopFloatingSidebar(isDark, textMain, textSub)),
                Expanded(
                  child: SafeArea(
                    // [ADMIN] index 7 = Quản trị hệ thống, nhúng thẳng vào body (giữ sidebar + header)
                    child: _selectedIndex == 7 ? const AdminSystemScreen(embedded: true)
                         // [ADMIN] index 8 = Quản trị Thiết bị toàn cục, cùng khuôn mẫu nhúng
                         : _selectedIndex == 8 ? const DeviceManagementScreen(embedded: true)
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

      bottomNavigationBar: isMobile ? _buildBottomNav(surfaceLight, textSub, isDark, isGlass) : null,
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
          // [ĐẨY THÔNG BÁO OS] Mở màn Cài đặt loại thông báo muốn nhận đẩy — xem
          // lib/screens/settings/notification_settings_screen.dart.
          buildSettingGroup([ListTile(leading: Icon(Icons.notifications_active_outlined, color: textMain), title: Text(t.text('notification_settings'), style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Icon(Icons.chevron_right, color: textSub), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationSettingsScreen())))]),
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text('Tích hợp', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          // [TUYA CLOUD-TO-CLOUD] Mở màn Liên kết tài khoản Tuya/Smart Life — xem
          // lib/screens/tuya/tuya_link_screen.dart. Điều khiển/hiển thị thiết bị Tuya sau khi
          // đồng bộ KHÔNG cần code riêng (tự vào chung Dashboard qua pipeline có sẵn).
          buildSettingGroup([ListTile(leading: Icon(Icons.cloud_queue_rounded, color: textMain), title: const Text('Đồng bộ Tuya / Smart Life', style: TextStyle(fontWeight: FontWeight.w600)), trailing: Icon(Icons.chevron_right, color: textSub), onTap: () async {
            // [FIX — thiết bị Tuya "biến mất" sau khi đồng bộ] currentHomeId là "ALL_SYSTEM" (placeholder
            // JWT) với tài khoản SUPER_USER — PHẢI dùng _provisioningTargetHomeId (cùng công thức nhà đích
            // AddDeviceDialog/AP Mode đang dùng) để đồng bộ đúng vào nhà SUPER_USER đang xem. Đồng thời
            // await + _handleRefresh() sau khi đóng màn — các luồng "thêm thiết bị" khác đều làm vậy,
            // thiếu bước này Dashboard không tự fetch lại danh sách thiết bị mới.
            await Navigator.push(context, MaterialPageRoute(builder: (context) => TuyaLinkScreen(homeId: _provisioningTargetHomeId)));
            if (mounted) _handleRefresh();
          })]),
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
          // [FIX LAYOUT] Trước đây bọc trong buildSettingGroup (AppContainer full-width +
          // ListTile căn trái) nên nhìn như MỘT mục menu bình thường thay vì một nút hành động
          // độc lập. Nay tách khỏi buildSettingGroup, bọc Center + OutlinedButton.icon
          // (mainAxisSize.min mặc định của Button -> ôm sát nội dung) — dạng viên thuốc, nền/
          // viền đỏ mờ TỰ THÂN không phụ thuộc isDark/isGlass nên tự động đúng trên MỌI theme,
          // không cần rẽ nhánh riêng cho Tối/Sáng/Kính.
          const SizedBox(height: 8),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _performLogout(context),
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
              label: Text(t.text('logout_device'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                side: const BorderSide(color: Colors.redAccent, width: 1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
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
                  // [ADMIN] Nút Quản trị Thiết bị toàn cục — cùng điều kiện SUPER_USER
                  if (_isSuperUser) _buildDeviceAdminMenuItem(txtMain, txtSub),
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
        // [ĐÍNH CHÍNH — Frost theo ĐÚNG theme] Frost mặc định (kGlassFrostFill = trắng 5%) quá
        // trong suốt — nền thật sự là bất kỳ thứ gì bị blur phía sau, không kiểm soát được độ
        // tối/sáng. Sáng+Kính: phủ TRẮNG đục 65% (giữa khoảng 0.6-0.7 người dùng yêu cầu) làm
        // bệ sáng vững chắc cho chữ ĐEN — đây chính là lỗi thật (trước đây lỡ phủ đen, khiến
        // chữ tối "chìm" trên nền tối như ảnh chụp gốc). Tối+Kính: giữ phủ đen 40% (không đổi,
        // không thuộc phạm vi đính chính lần này) làm bệ tối cho chữ trắng.
        glassTint: !isGlass ? null : (isDark ? Colors.black.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.65)),
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
                  // [ADMIN] Nút Quản trị Thiết bị toàn cục — cùng điều kiện SUPER_USER
                  if (_isSuperUser) _buildDeviceAdminMenuItem(txtMain, txtSub, isFromDrawer: true),
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [ĐÍNH CHÍNH — Sáng+Kính] txtMain/txtSub truyền vào giờ thuần isDark (đã quay lại ở cấp
    // build() phía trên) nên KHÔNG còn tự đúng cho riêng mặt kính Sáng của Drawer/Sidebar — mặt
    // kính này được phủ TRẮNG đục (glassTint, xem _buildMobileDrawer) nên chữ phải TỐI hẳn
    // (black87/black54) mới đủ nét, không phải màu navy nhạt txtMain gốc.
    final bool lightGlass = isGlass && !isDark;
    final Color unselectedText = lightGlass ? Colors.black87 : txtMain;
    final Color unselectedIcon = lightGlass ? Colors.black54 : txtSub;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // [ĐÍNH CHÍNH — Mục đang chọn trên Sáng+Kính] Nền tkGreen ĐẶC (không phải tint 15% cũ) +
        // đổ bóng mờ xanh nhẹ để "nổi bật tuyệt đối" đúng yêu cầu — Tối+Kính/tắt Kính giữ
        // nguyên kiểu tint mỏng cũ, không thuộc phạm vi đính chính lần này.
        color: isSelected ? (lightGlass ? tkGreen : tkGreen.withValues(alpha: 0.15)) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? tkGreen.withValues(alpha: lightGlass ? 1.0 : 0.3) : Colors.transparent),
        boxShadow: (isSelected && lightGlass) ? [BoxShadow(color: tkGreen.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))] : null,
      ),

      // SỬA LỖI CẢNH BÁO LIST TILE BẰNG THẺ MATERIAL NÀY
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(icon, color: isSelected ? (lightGlass ? Colors.white : tkGreenNeon) : unselectedIcon, size: 22, shadows: sh),
          title: Text(title, style: TextStyle(color: isSelected ? (lightGlass ? Colors.white : tkGreenNeon) : unselectedText, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, shadows: sh)),
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [ĐÍNH CHÍNH — Sáng+Kính] xem giải thích đầy đủ ở _buildMenuItem phía trên.
    final bool lightGlass = isGlass && !isDark;
    final Color unselectedText = lightGlass ? Colors.black87 : txtMain;
    final Color unselectedIcon = lightGlass ? Colors.black54 : txtSub;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    final t = AppTranslations.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? (lightGlass ? tkGreen : tkGreen.withValues(alpha: 0.15)) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? tkGreen.withValues(alpha: lightGlass ? 1.0 : 0.3) : Colors.transparent),
        boxShadow: (isSelected && lightGlass) ? [BoxShadow(color: tkGreen.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(Icons.admin_panel_settings, color: isSelected ? (lightGlass ? Colors.white : tkGreenNeon) : unselectedIcon, size: 22, shadows: sh),
          title: Text(t.text('system_admin'),
              style: TextStyle(color: isSelected ? (lightGlass ? Colors.white : tkGreenNeon) : unselectedText, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, shadows: sh)),
          onTap: () {
            if (isFromDrawer) Navigator.of(context).pop(); // đóng Drawer trượt (Mobile) trước khi đổi tab
            setState(() => _selectedIndex = kAdminIndex);
          },
        ),
      ),
    );
  }

  // Index dành riêng cho màn Quản trị Thiết bị toàn cục (nhúng trong body qua _selectedIndex).
  static const int kDeviceAdminIndex = 8;

  // [ADMIN] Nút Sidebar "Quản trị Thiết bị" — CHỈ SUPER_USER thấy (gate ở nơi gọi, không lặp lại
  // ở đây), cùng khuôn mẫu _buildAdminMenuItem ở trên, nhúng qua _selectedIndex.
  Widget _buildDeviceAdminMenuItem(Color txtMain, Color txtSub, {bool isFromDrawer = false}) {
    final bool isSelected = _selectedIndex == kDeviceAdminIndex;
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [ĐÍNH CHÍNH — Sáng+Kính] xem giải thích đầy đủ ở _buildMenuItem phía trên.
    final bool lightGlass = isGlass && !isDark;
    final Color unselectedText = lightGlass ? Colors.black87 : txtMain;
    final Color unselectedIcon = lightGlass ? Colors.black54 : txtSub;
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    final t = AppTranslations.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? (lightGlass ? tkGreen : tkGreen.withValues(alpha: 0.15)) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? tkGreen.withValues(alpha: lightGlass ? 1.0 : 0.3) : Colors.transparent),
        boxShadow: (isSelected && lightGlass) ? [BoxShadow(color: tkGreen.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(Icons.dns_rounded, color: isSelected ? (lightGlass ? Colors.white : tkGreenNeon) : unselectedIcon, size: 22, shadows: sh),
          title: Text(t.text('device_admin_title'),
              style: TextStyle(color: isSelected ? (lightGlass ? Colors.white : tkGreenNeon) : unselectedText, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, shadows: sh)),
          onTap: () {
            if (isFromDrawer) Navigator.of(context).pop();
            setState(() => _selectedIndex = kDeviceAdminIndex);
          },
        ),
      ),
    );
  }

  Widget _buildBottomNav(Color surface, Color txtSub, bool isDark, bool isGlass) {
    final t = AppTranslations.of(context);
    // [GIAI ĐOẠN 76 — KÍNH 3D BOTTOM NAV] Trước đây bật Kính chỉ đổi backgroundColor sang
    // Colors.transparent — KHÔNG hề có BackdropFilter/blur nào, nên thanh chỉ là 1 dải trong
    // suốt phẳng đè lên nền trang + vẫn giữ elevation mặc định (8, đổ bóng Material nặng nề) ->
    // đúng cảm giác "tối, đục, nặng nề" không khớp mặt kính của các thẻ phía trên. Bản này: tắt
    // hẳn elevation/backgroundColor mặc định, tự dựng lớp kính riêng (ClipRRect+BackdropFilter+
    // Container phủ màu+viền trên) CHỈ khi Kính bật; tắt Kính giữ nguyên thanh đặc màu cũ.
    final Color unselectedColor = isGlass
        ? (isDark ? Colors.white60 : Colors.grey[600]!)
        : txtSub;
    final bar = BottomNavigationBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      selectedItemColor: tkGreen,
      unselectedItemColor: unselectedColor,
      type: BottomNavigationBarType.fixed,
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

    if (!isGlass) {
      // Tắt Kính -> giữ nguyên hành vi cũ: thanh đặc màu surface, không đụng gì thêm.
      return Material(color: surface, elevation: 8, child: bar);
    }

    // [KÍNH 3D] Sáng+Kính: phủ trắng đục 55% + viền trên trắng 80% (đúng yêu cầu). Tối+Kính:
    // phủ đen mờ tương ứng — theo ĐÚNG nguyên tắc đã chốt ở Drawer (Sáng dùng tông sáng, Tối
    // dùng tông tối), không lặp lại lỗi "luôn phủ 1 màu bất kể theme" của lần trước.
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.8),
                width: 1.0,
              ),
            ),
          ),
          child: bar,
        ),
      ),
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
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // [GIAI ĐOẠN 72 — REWRITE] Cây bút -> chuyển isEditing tại chỗ,
                                // KHÔNG điều hướng màn hình nào (xem comment đầy đủ tại _toggleEditOrder).
                                _isEditingOrder
                                    ? TextButton.icon(
                                        // [FIX GIAI ĐOẠN 102 — TRUY VẾT NÚT LƯU] Cùng lý do bản Mobile.
                                        onPressed: _savingOrder ? null : () {
                                          if (kDebugMode) print('DEBUG: Nút Lưu đã được nhấn! (Desktop)');
                                          _toggleEditOrder();
                                        },
                                        icon: _savingOrder
                                            ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
                                            : Icon(Icons.check_circle_rounded, color: tkGreen, size: 20),
                                        label: Text('Xong', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold)),
                                      )
                                    : IconButton(
                                        icon: Icon(Icons.edit_note_rounded, color: textMain),
                                        tooltip: 'Sắp xếp thiết bị',
                                        onPressed: _toggleEditOrder,
                                      ),
                                if (!_isEditingOrder) ...[
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen.withValues(alpha: 0.15), foregroundColor: tkGreen, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                    icon: const Icon(Icons.add, size: 20), label: Text(t.text('add_device'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    onPressed: () async {
                                      // [FIX] Bắt lấy mã MAC dialog trả về rồi GỌI API LINK THẬT
                                      // (kèm SnackBar báo thành công/lỗi chi tiết) — trước đây kết quả bị vứt bỏ
                                      // [FIX GIẬT LAG] KHÔNG gọi thêm _handleRefresh() ở đây — _linkScannedDevice()
                                      // đã tự làm mới êm khi thành công (xem comment ở đó); gọi thêm lần 2 từng
                                      // khiến Dashboard chớp trắng liên tiếp hai lần mỗi lần thêm thiết bị.
                                      final result = await showAppDialog(context: context, contentPadding: const EdgeInsets.all(8), child: AddDeviceDialog(ownedMacs: _ownedMacs, homeId: _provisioningTargetHomeId));
                                      await _linkScannedDevice(result);
                                    },
                                  ),
                                ],
                              ],
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
                              // [PHÒNG] Thanh chọn phòng ngang — đồng bộ PC/Tablet như Mobile.
                              // [ĐÓNG BĂNG RENDER] RepaintBoundary — danh sách phòng gần như tĩnh
                              // (chỉ đổi khi user thêm/xóa/đổi tên phòng), không cần vẽ lại mỗi
                              // khi lưới thiết bị bên dưới nhấp nháy theo MQTT.
                              RepaintBoundary(child: _buildRoomTabs()),
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
          // [ĐÓNG BĂNG RENDER] RepaintBoundary — cùng lý do bản Mobile phía trên.
          RepaintBoundary(child: _buildRoomTabs()),
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
  // [FIX GIAI ĐOẠN 89] AppContainer.width=cardWidth CHỈ ép khung NGOÀI CÙNG — khi Kính bật, nội
  // dung đi qua _GlassSurface dựng bằng Stack (Padding đặt trong Stack, xem app_ui_wrappers.dart)
  // và Stack mặc định cấp constraint LỎNG (loose) cho con không-Positioned, nên Column dù đã
  // crossAxisAlignment.center vẫn tự co khít theo chữ (Column không tự giãn theo constraint
  // lỏng) -> "center" hóa vô nghĩa vì hộp của chính nó đã bằng đúng bề rộng nội dung. Bọc thêm
  // SizedBox(width: double.infinity) ép Column LUÔN chiếm trọn bề ngang thật sự được cấp thì
  // center mới có "chỗ" để phát huy tác dụng — đúng nguyên nhân người dùng đã chỉ ra.
  Widget _buildMiniStatusMobile(IconData icon, String title, String value, Color color, Color txtMain, Color txtSub, double cardWidth) {
    return AppContainer(
      width: cardWidth,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
      child: SizedBox(
        width: double.infinity,
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
          ],
        ),
      ),
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
          // [FIX CĂN LỀ] Bọc Expanded để mỗi thẻ chiếm ĐÚNG 1/3 bề ngang thực tế còn lại (trừ 2
          // vạch chia) — trước đây 3 Column con chỉ co khít theo nội dung (shrink-wrap) nên
          // CrossAxisAlignment.center bên trong _buildMiniStatusDesktop không có "chỗ" để căn
          // giữa, nhìn như bám lề trái dù thuộc tính center vẫn luôn đúng.
          Expanded(child: _buildMiniStatusDesktop(Icons.water_drop, t.text('humidity'), '${_weatherData['humidity'] ?? '--'}%', Colors.blue, txtMain, txtSub)), Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          Expanded(child: _buildMiniStatusDesktop(Icons.bolt, t.text('power_load'), '2.1 kW', tkGreen, txtMain, txtSub)), Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          Expanded(child: _buildMiniStatusDesktop(Icons.security, t.text('security'), t.text('on_state'), Colors.redAccent, txtMain, txtSub)),
        ],
      ),
    );
  }

  // [GIAI ĐOẠN 131] Trước đây thẻ này 1 trang tĩnh duy nhất — nay giao lại cho _EnergySliderCard
  // (StatefulWidget riêng, TỰ giữ PageController — tách khỏi _DashboardScreenState vốn đã rất
  // lớn, tránh phải nhớ thêm 1 field/dispose() giữa hàng trăm field khác của State khổng lồ này).
  Widget _buildEnergyWidget(bool isDark, Color textMain, Color textSub) {
    return const _EnergySliderCard();
  }

  // [ĐẬP BỎ UI CAMERA — QUY HOẠCH LẠI NVR] Toàn bộ khối cũ (2 lưới rời RTSP/Imou, "cấp 2" Phóng to
  // giữa Dashboard, overlay luôn hiện...) đã ĐẬP BỎ theo yêu cầu, thay bằng 1 widget tự trị DUY
  // NHẤT — xem lib/screens/cameras/camera_dashboard_section.dart (gộp 2 loại camera vào chung 1
  // lưới động 1x1/2x2/3x3/1+4, tự phân trang, overlay chạm-hiện-tự-ẩn, trang Fullscreen riêng).
  Widget _buildCameraWidget(bool isDark, Color textMain, Color textSub) {
    // [TÊN NHÀ CHO MÀN CHI TIẾT CAMERA] SUPER_USER đang xem nhà cụ thể -> lấy từ
    // _selectedHomeForSuperUser (giống các tiêu đề khác trong file này); user thường -> HomeProvider.
    final String homeName = (userRole == 'SUPER_USER' && _selectedHomeForSuperUser != null)
        ? (_selectedHomeForSuperUser!['home_name'] ?? '').toString()
        : (Provider.of<HomeProvider>(context, listen: false).activeHome?['home_name'] ?? '').toString();
    return CameraDashboardSection(
      cameras: _cameras,
      imouCameras: _imouCameras,
      homeId: _provisioningTargetHomeId,
      homeName: homeName,
      onCamerasChanged: (rtsp, imou) => setState(() { _cameras = rtsp; _imouCameras = imou; }),
    );
  }

  // [FIX CĂN LỀ] Icon/Tiêu đề/Giá trị giờ nằm thẳng hàng CHÍNH GIỮA thẻ (không còn bám lề trái):
  // SizedBox(width: double.infinity) đảm bảo Column trải hết bề ngang thật của phần Expanded cha
  // đã cấp; crossAxisAlignment.center + Row con cũng center + textAlign.center trên cả 2 Text
  // đề phòng chữ dài rớt dòng vẫn giữ giữa.
  Widget _buildMiniStatusDesktop(IconData icon, String label, String val, Color color, Color txtMain, Color txtSub) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, textAlign: TextAlign.center, style: TextStyle(color: txtSub, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Text(val, textAlign: TextAlign.center, style: TextStyle(color: txtMain, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
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
    // [FIX CÙNG HỌ BUG ĐẾM THIẾT BỊ] devicesInRoom() CHỈ trả thiết bị gán NGUYÊN KHỐI — bỏ sót
    // kênh gán riêng qua đường tách relay mới (endpointsInRoom). Trước đây Công tắc tổng phòng
    // lặng lẽ KHÔNG bật/tắt các kênh này dù hiển thị trong phòng — mỗi kênh chỉ toggle ĐÚNG
    // endpoint của nó (không dùng 'all', vì chỉ 1 kênh của thiết bị thuộc phòng này).
    for (final ep in roomProv.endpointsInRoom(roomId)) {
      deviceProv.toggleDevice(ep.mac, ep.endpoint, !turnOn);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(turnOn ? 'Đã bật tất cả thiết bị trong phòng' : 'Đã tắt tất cả thiết bị trong phòng'), backgroundColor: tkGreen));
  }

  // [CÁCH LY REBUILD — chống quá tải Accessibility Tree] Trước đây gọi thẳng
  // Provider.of<DeviceProvider>(context) [listen:true] BẰNG context của _DashboardScreenState —
  // vì _buildDevicesGrid() chỉ là MỘT PHƯƠNG THỨC (không phải Widget/Element riêng) được gọi
  // TRONG build() của State, dependency đó bị đăng ký lên chính Element của DashboardScreen. Kết
  // quả: MỖI notifyListeners() từ DeviceProvider (kể cả 1 gói MQTT của đúng 1 cảm biến) kích hoạt
  // build() lại TOÀN BỘ màn hình — sidebar, header, danh sách phòng, TẤT CẢ — gây "Failed to
  // update ui::AXTree, Nodes left pending" trên Desktop khi dữ liệu MQTT đổ về dồn dập.
  // Fix: bọc lưới trong Consumer<DeviceProvider> NGAY TẠI 2 nơi gọi (Mobile/Desktop, xem bên
  // dưới) — Consumer tạo MỘT Element RIÊNG, dependency đăng ký lên Element đó thay vì lên
  // DashboardScreen, nên khi DeviceProvider đổi CHỈ đúng lưới thiết bị vẽ lại, sidebar/header/
  // rooms giữ nguyên không rebuild. _buildDevicesGrid giờ nhận [provider] qua tham số thay vì tự
  // tra bằng context của State.
  // [FIX — RÀ SOÁT HIỆU NĂNG Trụ cột 3 (God Widget), lỗ hổng cách ly còn sót] Comment gốc ngay
  // dưới đây giải thích ĐÚNG lý do bọc Consumer<DeviceProvider> — NHƯNG _buildDevicesGridBody bên
  // dưới lại tự gọi THÊM `context.watch<RoomGroupProvider>()` VÀ `context.watch<ThemeProvider>()`
  // bằng `context` của CHÍNH _DashboardScreenState (vì đây là 1 PHƯƠNG THỨC của State, không phải
  // build() của 1 Widget/Element riêng) — 2 dependency đó vẫn đăng ký lên Element của
  // DashboardScreen y hệt lỗi ban đầu, chỉ khác Provider. Đổi phòng (RoomGroupProvider) hoặc đổi
  // theme Kính (ThemeProvider) vẫn kéo theo rebuild TOÀN BỘ Dashboard dù Consumer<DeviceProvider>
  // đã chặn đúng phần DeviceProvider. Fix: lồng thêm 2 Consumer NGAY TẠI ĐÂY (nơi duy nhất tạo
  // Widget/Element mới), roomProv/isGlass nhận qua THAM SỐ thay vì tự watch bằng context của
  // State — dependency giờ đăng ký đúng lên Element Consumer trong cùng, không lan lên Dashboard.
  Widget _buildDevicesGrid(bool isDark, Color textMain, Color textSub) {
    return Consumer<DeviceProvider>(
      builder: (_, provider, _) => Consumer<RoomGroupProvider>(
        builder: (_, roomProv, _) => Consumer<ThemeProvider>(
          builder: (_, themeProv, _) => _buildDevicesGridBody(provider, roomProv, themeProv.isGlassThemeEnabled, isDark, textMain, textSub),
        ),
      ),
    );
  }

  Widget _buildDevicesGridBody(DeviceProvider provider, RoomGroupProvider roomProv, bool isGlass, bool isDark, Color textMain, Color textSub) {
    if (_isLoadingDevices) return Center(child: Padding(padding: const EdgeInsets.all(40), child: CircularProgressIndicator(color: tkGreen)));

    // [PHÒNG] Phòng đang chọn (null = Tất cả) — dùng để LỌC thiết bị + chèn Công tắc tổng.
    // [FIX GIAI ĐOẠN 109 — THAY THẾ CÁCH LÀM CỦA GIAI ĐOẠN 75] Trước đây đang Sửa thứ tự LUÔN ép
    // về "Tất cả" (bỏ qua bộ lọc phòng) vì lúc lưu gửi thẳng draft làm thứ tự CẢ NHÀ — lọc theo 1
    // phòng sẽ làm mất các MAC phòng khác. Nay dùng _editingScopedRoomId (chụp SẴN lúc bấm cây bút
    // — xem _toggleEditOrder) thay vì luôn ép null: mở Sửa từ tab "Tất cả" -> vẫn null, hành vi
    // CŨ giữ nguyên 100%; mở Sửa từ tab 1 phòng cụ thể -> lọc ĐÚNG phòng đó xuyên suốt lúc Sửa,
    // cho kéo-thả CHỈ trong phạm vi phòng. _saveDeviceOrder() chịu trách nhiệm GHÉP đúng thứ tự
    // con đó vào thứ tự CẢ NHÀ trước khi gửi lên Backend — không còn nguy cơ mất MAC phòng khác.
    final String? selRoom = _isEditingOrder ? _editingScopedRoomId : roomProv.selectedRoomId;

    // VIEW 1: SUPER USER (HIỂN THỊ THẺ NHÀ) - Giữ nguyên của bác
    // [ĐỢT 21] Thẻ Nhà nằm trong ClipRRect+BackdropFilter riêng (như SmartSwitchCard) nên border/
    // shadow mới PHẢI ở một Container bọc NGOÀI ClipRRect — đặt trực tiếp vào AnimatedContainer sẽ
    // bị chính ClipRRect của nó cắt mất, xem bài học "Shadow phải nằm ngoài ClipRRect".
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
                          // [FIX — Camera "Chưa có camera nào" sau khi SUPER_USER chọn nhà] Nhánh
                          // chọn nhà của SUPER_USER trước đây CHỈ gọi _initializeHome() (nạp lại
                          // thiết bị MQTT/DPS) — KHÔNG gọi _loadCameras(), nên _cameras/_imouCameras
                          // kẹt nguyên giá trị từ lúc bootstrap (fetch cho "ALL_SYSTEM" -> rỗng).
                          // Khác _onActiveHomeChanged() (đường chuyển nhà của user thường) đã gọi
                          // đúng cả 2 hàm — nhánh SUPER_USER này bị bỏ sót, không phải do UI camera
                          // filter sai device_type.
                          onTap: () { setState(() => _selectedHomeForSuperUser = home); _initializeHome(); _loadCameras(); },
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

    // [FIX ĐỒNG BỘ PHÒNG] roomOf(mac) chỉ phản ánh gán NGUYÊN KHỐI (_deviceRoom) — thiết bị
    // gán qua picker "Thêm thiết bị" của RoomDetailScreen (TÁCH RELAY, đi qua
    // assignEndpointsToRoom -> _endpointRoom) trước đây KHÔNG được lọc filter này nhìn thấy,
    // nên tab phòng trên Dashboard "quên" mất thiết bị vừa thêm dù RoomManagementScreen/
    // RoomDetailScreen đã đếm/hiển thị đúng (2 màn đó gộp CẢ HAI nguồn từ lâu). Gộp thêm tập
    // MAC có ít nhất 1 kênh thuộc đúng phòng đang chọn để 2 nguồn khớp nhau.
    final Set<String> selRoomEndpointMacs =
        selRoom == null ? const {} : {for (final e in roomProv.endpointsInRoom(selRoom)) e.mac};

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
      // [PHÒNG] Đang xem 1 phòng cụ thể -> chỉ giữ thiết bị thuộc phòng đó (nguyên khối HOẶC
      // có ít nhất 1 kênh đã tách gán riêng vào phòng này).
      if (selRoom != null && roomProv.roomOf(mac) != selRoom && !selRoomEndpointMacs.contains(mac)) continue;
      String deviceName = device['name'] ?? device['home_name'] ?? 'Thiết bị $mac';

      // [FIX GOM CHÙM — LỌC TỪNG KÊNH] Điều kiện ở trên chỉ xác định "thiết bị CÓ mặt trong
      // phòng" (nguyên khối HOẶC có ít nhất 1 kênh) — KHÔNG có nghĩa MỌI kênh cùng MAC đều thuộc
      // phòng đang xem. "Phòng hiệu lực" của một kênh = phòng đã tách gán riêng cho ĐÚNG kênh đó
      // (endpointRoomOf) nếu có, rơi về phòng nguyên khối của cả thiết bị (roomOf) nếu kênh đó
      // chưa từng tách riêng — cùng quy tắc "effectiveRoom" mà RoomDetailScreen._pickChannels đã
      // dùng. Trước đây Dashboard không lọc theo kênh nên gán 1 kênh vào phòng kéo theo hiển thị
      // TẤT CẢ kênh còn lại của công tắc đa nút trong đúng tab phòng đó.
      bool channelInSelectedRoom(String ep) =>
          selRoom == null || (roomProv.endpointRoomOf(mac, ep) ?? roomProv.roomOf(mac)) == selRoom;

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

      // [FIX FACTORY BUILDER — chống thẻ đôi Fan+Switch] Cờ đánh dấu thiết bị ĐÃ được dựng thành
      // thẻ Quạt ở khối này (bất kể qua nhánh endpoint chuẩn hay nhánh đoán legacy bên dưới) —
      // dùng để CHẶN CỨNG việc rơi tiếp xuống các nhánh category khác ngay sau khối này.
      bool isFanDevice = false;
      if (fanEndpoints.isNotEmpty) {
        // Mỗi endpoint dạng quạt -> đúng MỘT thẻ SmartFanCard tích hợp (icon cánh quạt
        // quay theo tốc độ thật); speed/swing đã được đè lớp sống từ dps ở trên.
        for (final f in fanEndpoints) {
          // [FIX GOM CHÙM] Hub nhiều kênh quạt (F1/F2...) — mỗi kênh tự kiểm tra phòng hiệu lực
          // riêng, không "ăn theo" kênh khác cùng MAC.
          if (!channelInSelectedRoom(f)) continue;
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
        isFanDevice = true;
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
          isFanDevice = true;
        }
      }
      // [FIX FACTORY BUILDER — GỐC RỄ THẬT của bug "1 quạt ra 2 thẻ"] TRƯỚC ĐÂY không có
      // continue ở đây — category "fan" lại NẰM SẴN trong primaryDeviceCategories (dòng 139) nên
      // thiết bị vừa được dựng thẻ Quạt xong vẫn tiếp tục CHẢY XUỐNG khối exclude-list bên dưới
      // (dòng ~3120), bị dựng THÊM một GenericDeviceCard/Switch chỉ 1 nút nguồn cho ĐÚNG MAC đó.
      // Thoát vòng lặp NGAY khi đã xác định là quạt — tuyệt đối không rơi xuống bất kỳ nhánh
      // category nào khác nữa.
      if (isFanDevice) continue;

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

        // [FIX GOM CHÙM] Đang xem 1 phòng cụ thể -> mỗi kênh của công tắc đa nút (SSW04...) chỉ
        // hiện trong đúng tab phòng nó thật sự được gán riêng (hoặc phòng nguyên khối nếu kênh đó
        // chưa từng tách riêng) — KHÔNG còn cảnh gán 1 kênh vào phòng kéo theo cả cụm hiện ra.
        final List<String> roomChildKeys = childKeys.where(channelInSelectedRoom).toList();

        for (final key in roomChildKeys) {
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
        // [LƯU Ý GIỚI HẠN FIRMWARE] Nút này vẫn gửi lệnh "all" xuống CẢ thiết bị vật lý (không
        // chỉ các kênh đang hiển thị trong phòng) — nếu 1 thiết bị bị chia kênh cho nhiều phòng
        // khác nhau, bấm "Tất cả" ở phòng này vẫn bật/tắt luôn kênh thuộc phòng khác. Đây là giới
        // hạn của lệnh "all" phía firmware, không phải phạm vi sửa của bug hiển thị lần này.
        if (roomChildKeys.length > 1) {
          final bool anyOn = roomChildKeys.any((k) => endpointStates[k] == 'ON');
          allSwitches.add({
            'mac': mac,
            'endpoint': 'all',
            'state': anyOn ? 'ON' : 'OFF',
            'name': 'Tất cả (${roomChildKeys.length} kênh)',
            'online': deviceOnline,
            'rawDevice': device,
            'isMaster': true,
          });
        }
      }
    }

    // [FIX GIAI ĐOẠN 91] Trước đây khóa CHÍNH của sort là so sánh chuỗi MAC (a-z) — ghi đè HOÀN
    // TOÀN thứ tự tùy chỉnh người dùng vừa kéo-thả lưu (device_order:{homeID}, đã phản ánh đúng
    // trong thứ tự _currentHomeDevices do Backend applyDeviceOrder() sắp sẵn) mỗi lần trang tải
    // lại — kéo-thả xong bấm Lưu, thẻ Công tắc "nhảy về" đúng thứ tự alphabet cũ, giống hệt
    // triệu chứng "chưa lưu được" dù Backend đã lưu đúng. Nay dùng RANK THEO VỊ TRÍ THẬT trong
    // _currentHomeDevices làm khóa chính (giữ đúng thứ tự liên-thiết-bị người dùng đã sắp), CHỈ
    // dùng "nút tổng trước, kênh theo số" làm khóa PHỤ để ổn định thứ tự các kênh NỘI BỘ MỘT
    // thiết bị đa kênh — đúng mục đích BAN ĐẦU của đoạn sort này (không đổi gì khác).
    final Map<String, int> macOrderRank = {
      for (int i = 0; i < _currentHomeDevices.length; i++)
        (_currentHomeDevices[i]['mac_address'] ?? _currentHomeDevices[i]['mac'] ?? '').toString().replaceAll(':', '').toUpperCase(): i,
    };
    allSwitches.sort((a, b) {
      final ra = macOrderRank[a['mac']] ?? 999999;
      final rb = macOrderRank[b['mac']] ?? 999999;
      if (ra != rb) return ra.compareTo(rb);
      int rank(Map<String, dynamic> it) => isMasterKey(it['endpoint']) ? -1 : (channelOf(it['endpoint']) ?? 999);
      return rank(a).compareTo(rank(b));
    });

    // [FIX GIAI ĐOẠN 116 — REVERT GIAI ĐOẠN 115] "Ẩn cả khối" (menu tiêu đề PhysicalSwitchBlockCard,
    // xem _openFaceplateDeviceMenu) nay lặp ghi TỪNG hideKey per-kênh thay vì 1 khoá mac trần — bộ
    // lọc CHỈ cần kiểm tra ĐÚNG hideKey per-endpoint như nguyên gốc trước Giai đoạn 115, không cần
    // nhánh mac trần nào nữa (khỏi phải giữ 2 dạng khoá song song).
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

    // [FIX GIAI ĐOẠN 113 — _lastVisualCardOrder PHẢI KHỚP ĐÚNG THỨ TỰ HIỂN THỊ THẬT] Trước đây
    // gộp theo khối cố định [fans,sensors,rollingDoors,pumps,dimmers,genericPrimary,switches] —
    // ĐÃ LỆCH với thứ tự HIỂN THỊ THẬT kể từ Giai đoạn 108 (màn thường merge theo macOrderRank,
    // có thể xen kẽ Công tắc giữa các thẻ lớn): bấm Sửa, _editOrderDraft (seed từ biến này) khởi
    // đầu KHÔNG khớp những gì mắt vừa thấy. Nay build entries + áp ĐÚNG MỘT đường merge (grid
    // layout nếu người dùng đã dùng tính năng khoảng trống, không thì macOrderRank cũ) NGAY TẠI
    // ĐÂY — dùng lại y hệt cho Builder hiển thị bên dưới (không tính 2 lần).
    final List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> displayEntries = [
      ..._buildAllDeviceCardEntries(visibleFans, visibleSensors, visibleRollingDoors, visiblePumps, visibleDimmers, visibleGenericPrimary, provider, isDark),
      ..._buildSwitchCardEntries(visibleSwitches, provider, isDark),
    ];
    final List<({String key, String mac, Widget widget, int gridSpanX, int gridSpanY, bool autoHeight})> mergedDisplayEntries = _gridLayoutSlots.isNotEmpty
        ? _applyGridLayout(displayEntries)
        : _mergeEntriesByMacOrderRank(displayEntries, macOrderRank);

    // [GIAI ĐOẠN 75] Ghi lại thứ tự thẻ NHÌN THẤY hiện tại (key+mac, KHÔNG dựng Widget) — làm hạt
    // giống cho _editOrderDraft khi người dùng bấm Cây bút bật chế độ Sửa (xem _toggleEditOrder).
    // Bỏ qua entry "ô trống" (_kEmptySlotMac) — chế độ Sửa dựng lại ô trống từ CHÍNH _gridLayoutSlots
    // (xem _buildInPlaceEditWrap), không cần _lastVisualCardOrder mang theo.
    _lastVisualCardOrder = [
      for (final e in mergedDisplayEntries)
        if (e.mac != _kEmptySlotMac) (key: e.key, mac: e.mac),
    ];
    // [GIAI ĐOẠN 113] Ghi kèm gridSpanX theo key — xem giải thích tại khai báo _lastEntrySpanByKey.
    _lastEntrySpanByKey = {
      for (final e in mergedDisplayEntries)
        if (e.mac != _kEmptySlotMac) e.key: e.gridSpanX,
    };

    // [GIAI ĐOẠN 75] Chế độ Sửa -> nhánh CỘNG THÊM riêng (_buildInPlaceEditWrap), KHÔNG đụng
    // khối Column bình thường bên dưới. Vẫn giữ dải cảnh báo mất kết nối + Công tắc tổng phòng ở
    // trên để giao diện tổng thể không "giật cục" khi bật/tắt chế độ Sửa.
    if (_isEditingOrder) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(children: [
              Icon(Icons.open_with_rounded, color: tkGreen, size: 18),
              const SizedBox(width: 8),
              // [GIAI ĐOẠN 109] Báo rõ đang Sửa trong PHẠM VI PHÒNG nào (nếu mở từ 1 tab phòng cụ
              // thể) — tránh người dùng tưởng nhầm đang sắp xếp toàn bộ thiết bị cả nhà.
              Expanded(child: Text(
                _editingScopedRoomId != null
                    ? 'Giữ và kéo để sắp xếp thứ tự thiết bị TRONG PHÒNG "${roomProv.roomName(_editingScopedRoomId!)}"'
                    : 'Giữ và kéo để sắp xếp lại vị trí thẻ thiết bị',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
              )),
              // [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Nút TẠO ô trống mới — CHỈ hiện
              // khi Sửa CẢ NHÀ (_editingScopedRoomId == null). Grid-layout là 1 chuỗi token PHẲNG
              // cho CẢ NHÀ, không có công thức ghép-theo-phòng như device_order (xem
              // _saveDeviceOrder) — ẩn nút này khi Sửa theo phòng để không tạo trạng thái mù mờ
              // (ô trống thêm vào lúc Sửa theo phòng sẽ không có chỗ nào để lưu).
              if (_editingScopedRoomId == null)
              TextButton.icon(
                onPressed: () => setState(() {
                  _editOrderDraft = [
                    ..._editOrderDraft,
                    (key: 'empty_${DateTime.now().microsecondsSinceEpoch}', mac: _kEmptySlotMac),
                  ];
                }),
                icon: Icon(Icons.add_box_outlined, size: 16, color: tkGreen),
                label: Text('Thêm khoảng trống', style: TextStyle(color: tkGreen, fontSize: 12, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ]),
          ),
          _buildInPlaceEditWrap(visibleFans, visibleSensors, visibleRollingDoors, visiblePumps, visibleDimmers, visibleGenericPrimary, visibleSwitches, provider, isDark),
        ],
      );
    }

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
        // [FIX — Wrap THAY StaggeredGrid, TÔN TRỌNG TUYỆT ĐỐI THỨ TỰ ĐÃ KÉO-THẢ] StaggeredGrid
        // (bin-packing "shelf best-fit") tự chọn cột trống thấp nhất cho từng thẻ — có thể hiện
        // một thẻ NHỎ đứng sau trong mảng entries TRƯỚC một thẻ LỚN đứng trước nó, phá vỡ đúng
        // thứ tự device_order (Giai đoạn 72) người dùng vừa kéo-thả lưu. Wrap chảy tuần tự ĐÚNG
        // thứ tự mảng — thẻ lớn không vừa hết hàng thì tự xuống dòng mới (chấp nhận khoảng trống
        // cuối hàng, đổi lấy đúng thứ tự tuyệt đối). Vẫn gộp 1 danh sách duy nhất (đúng thứ tự đã
        // lưu qua Giai đoạn 72) — xem _buildAvatarStaggeredGrid.
        //
        // [FIX GIAI ĐOẠN 108 — NGUYÊN NHÂN THẬT CỦA "KÉO XONG BẤM XONG BỊ RESET"] Bản trên chỉ nối
        // ĐÚNG thứ tự NỘI BỘ từng khối ([...cards lớn], [...Công tắc]) nhưng vẫn CHỐT CỨNG khối lớn
        // LUÔN đứng TRƯỚC khối Công tắc — bất kể _currentHomeDevices (nguồn sự thật, đã áp
        // device_order cục bộ ở _fetchDevicesForHome) có xen kẽ MAC Công tắc giữa các MAC thẻ lớn
        // hay không. Giai đoạn 107 vừa hợp nhất chế độ SỬA thành 1 ReorderableWrap tự do (cho phép
        // kéo thẻ Công tắc chen vào giữa thẻ lớn) — nhưng màn hình THƯỜNG (ở đây) chưa từng theo
        // kịp: vẫn vẽ [khối lớn][khối Công tắc] tách rời, nên bất kỳ thứ tự chen kẽ nào vừa kéo đều
        // KHÔNG THỂ hiển thị lại đúng — nó luôn "rơi" về đúng khối mặc định, đúng cảm giác "lưu
        // xong lại về vị trí cũ" người dùng báo (không phải do MQTT/Server ghi đè — _currentHomeDevices
        // và local order hoàn toàn đúng, chỉ là bước DỰNG ENTRIES không đọc đúng thứ tự đó). Nay
        // MERGE 2 khối lại theo ĐÚNG macOrderRank (đã tính sẵn ở trên cho allSwitches.sort()) —
        // sort ỔN ĐỊNH (tiebreak bằng chỉ số gốc, vì List.sort của Dart KHÔNG đảm bảo stable) để
        // giữ nguyên thứ tự kênh nội bộ của từng MAC đa kênh.
        //
        // [FIX GIAI ĐOẠN 113] entries + merge (macOrderRank HOẶC grid layout nếu có khoảng trống)
        // giờ tính MỘT LẦN DUY NHẤT phía trên (biến mergedDisplayEntries, dùng chung với
        // _lastVisualCardOrder) — KHÔNG còn dựng lại toàn bộ Widget thẻ thiết bị lần thứ 2 ở đây.
        // ====================================================================
        _buildAvatarStaggeredGrid(mergedDisplayEntries, isDark),

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
  final String currentRole; final String currentEmail; final int initialTab; final String homeId;
  const WindowsSettingsDialog({super.key, required this.currentRole, required this.currentEmail, this.initialTab = 0, required this.homeId});
  @override
  State<WindowsSettingsDialog> createState() => _WindowsSettingsDialogState();
}

class _WindowsSettingsDialogState extends State<WindowsSettingsDialog> {
  late int _selectedTab;
  final Color tkGreen = const Color(0xFF00A651);
  bool _tuyaSyncing = false;
  bool _tuyaUnsyncing = false;

  @override
  void initState() { super.initState(); _selectedTab = widget.initialTab; }

  // [TUYA CLOUD-TO-CLOUD — PC] CÙNG API syncTuyaDevices() mà TuyaLinkScreen (Mobile,
  // lib/screens/tuya/tuya_link_screen.dart) đang dùng — không viết logic riêng cho PC. homeId
  // truyền từ _showSettingsMenu() (_provisioningTargetHomeId, ĐÚNG công thức nhà đích cho
  // SUPER_USER đã sửa ở nút Mobile — tránh lặp lại bug đồng bộ "biến mất" vì home_id
  // "ALL_SYSTEM").
  Future<void> _syncTuya() async {
    if (_tuyaSyncing) return;
    setState(() => _tuyaSyncing = true);
    final result = await ApiService().syncTuyaDevices(widget.homeId);
    if (!mounted) return;
    setState(() => _tuyaSyncing = false);
    if (result.count != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã đồng bộ ${result.count} thiết bị Tuya'), backgroundColor: tkGreen));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Đồng bộ Tuya thất bại'), backgroundColor: Colors.redAccent));
    }
  }

  // [TÍNH NĂNG MỚI — PC, theo yêu cầu user] Cùng API unsyncTuyaDevices() mà TuyaLinkScreen
  // (Mobile) dùng — không viết logic riêng cho PC, đúng tiền lệ _syncTuya() ở trên.
  Future<void> _unsyncTuya() async {
    if (_tuyaUnsyncing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy đồng bộ Tuya?'),
        content: const Text('Toàn bộ thiết bị Tuya đã đồng bộ sẽ bị gỡ khỏi nhà này (không đụng thiết bị vật lý). Đồng bộ lại bất cứ lúc nào để kéo về y hệt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xác nhận', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _tuyaUnsyncing = true);
    final result = await ApiService().unsyncTuyaDevices(widget.homeId);
    if (!mounted) return;
    setState(() => _tuyaUnsyncing = false);
    if (result.count != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã gỡ ${result.count} thiết bị Tuya khỏi nhà này'), backgroundColor: Colors.redAccent));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Hủy đồng bộ Tuya thất bại'), backgroundColor: Colors.redAccent));
    }
  }

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
        const SizedBox(height: 24),
        Divider(height: 1, color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.cloud_queue_rounded, color: tkGreen),
          title: Text('Đồng bộ thiết bị Tuya', style: TextStyle(color: textMain, fontWeight: FontWeight.w600, shadows: sh)),
          subtitle: Text('Kéo toàn bộ thiết bị từ tài khoản Tuya/Smart Life về nhà đang xem', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w500, shadows: sh)),
          trailing: _tuyaSyncing
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
              : Icon(Icons.sync_rounded, color: textSub),
          onTap: _tuyaSyncing ? null : _syncTuya,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.link_off_rounded, color: Colors.redAccent),
          title: Text('Hủy đồng bộ Tuya', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, shadows: sh)),
          subtitle: Text('Gỡ toàn bộ thiết bị Tuya khỏi nhà đang xem (không đụng thiết bị vật lý)', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w500, shadows: sh)),
          trailing: _tuyaUnsyncing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
              : const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
          onTap: _tuyaUnsyncing ? null : _unsyncTuya,
        ),
      ],
    );
  }
}

// ============================================================================
// ⚡ GIAI ĐOẠN 131 — THẺ ĐIỆN NĂNG DẠNG VUỐT (PAGEVIEW SLIDER)
// ============================================================================
/// Header (dòng "Điện năng" + nút Mở rộng) CỐ ĐỊNH — chỉ phần Content bên dưới vuốt được qua 3
/// trang: (1) Tổng quan tiêu thụ — GIỮ NGUYÊN 100% nội dung/số liệu mock cũ (không đổi 1 dòng),
/// (2) Tổng quan Điện mặt trời (PV/Ắc quy), (3) Top thiết bị tiêu thụ. Nút Mở rộng điều hướng
/// sang [FullEnergyDashboardScreen] (màn hình chi tiết 3 Tab, Giai đoạn 131).
class _EnergySliderCard extends StatefulWidget {
  const _EnergySliderCard();

  @override
  State<_EnergySliderCard> createState() => _EnergySliderCardState();
}

class _EnergySliderCardState extends State<_EnergySliderCard> {
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    const Color tkGreen = Color(0xFF00A651);
    final t = AppTranslations.of(context);

    return AppContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [CẤU TRÚC TĨNH — HEADER] Row cố định, KHÔNG nằm trong PageView — luôn hiện bất kể
          // đang vuốt ở trang nào.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [Icon(Icons.bolt_rounded, color: tkGreen, size: 22), const SizedBox(width: 8), Text(t.text('energy'), style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))]),
              // [PHẦN 2 — ĐIỀU HƯỚNG] Trước đây onPressed rỗng — nay mở FullEnergyDashboardScreen.
              IconButton(
                icon: Icon(Icons.open_in_new_rounded, color: textSub, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const FullEnergyDashboardScreen())),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // [FIX GIAI ĐOẠN 132 — OVERFLOW 8px] KHÔNG bọc PageView bằng Expanded như đề xuất ban
          // đầu: Card này (AppContainer) luôn sống bên trong 1 Column đặt trực tiếp trong
          // SingleChildScrollView ở CẢ 2 nơi gọi (_buildDesktopContent dòng ~4248,
          // _buildMobileContent dòng ~4322) — SingleChildScrollView cấp height UNBOUNDED cho
          // Column con của nó. Khi Kính bật, đường đi còn xuyên qua `_GlassSurface` (đặt `child`
          // vào 1 `Stack` không set width/height, xem app_ui_wrappers.dart) — Stack không set
          // kích thước dưới constraint unbounded tiếp tục truyền unbounded xuống. Bọc Expanded ở
          // đây sẽ ném ĐÚNG lớp lỗi RenderFlex "non-zero flex nhưng constraint unbounded" (CRASH
          // cứng, không phải chỉ overflow) — cùng họ lỗi đã xác nhận ở Cửa Gara (Giai đoạn 121) và
          // đã kiểm chứng an toàn ở BarrierGateAvatar (Giai đoạn 129, nơi AvatarShell LUÔN ép
          // height cụ thể nên khác hẳn trường hợp này). SizedBox chiều cao CỐ ĐỊNH mới là lựa chọn
          // ĐÚNG — root cause overflow 8px thật sự nằm ở NỘI DUNG BÊN TRONG (Trang 1 hơi cao hơn
          // 148px cấp cho nó), khắc phục bằng cách 2 dưới đây (giảm spacing + FittedBox) + gộp
          // Page Indicator ĐÈ LÊN (Stack+Positioned, không còn SizedBox+Center RIÊNG bên ngoài
          // PageView nữa) — vừa đúng phương án "Stack" user đề xuất làm lựa chọn thay thế, vừa lấy
          // lại ~24px khoảng trống Column từng dành cho indicator, cho card gọn hẳn xuống dưới.
          SizedBox(
            height: 132,
            child: Stack(
              children: [
                PageView(
                  controller: _pageController,
                  children: [
                    _buildConsumptionPage(isDark, textMain, textSub, tkGreen, t),
                    _buildSolarPage(isDark, textMain, textSub, tkGreen),
                    _buildTopDevicesPage(isDark, textMain, textSub, tkGreen),
                  ],
                ),
                // [PAGE INDICATOR — ĐÈ LỠ LƠ LỬNG] Positioned đáy, KHÔNG chiếm thêm chiều cao vật
                // lý của Column cha — mỗi trang tự chừa khoảng trống đáy tương ứng (xem
                // _buildConsumptionPage/_buildSolarPage/_buildTopDevicesPage) để không đè lên chữ.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 2,
                  child: Center(
                    child: SmoothPageIndicator(
                      controller: _pageController,
                      count: 3,
                      effect: ExpandingDotsEffect(
                        dotHeight: 5,
                        dotWidth: 5,
                        spacing: 5,
                        activeDotColor: tkGreen,
                        dotColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                      ),
                      onDotClicked: (i) => _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Trang 1: Tổng quan tiêu thụ — nội dung/số liệu GIỮ NGUYÊN, bọc "viên đạn bạc" FittedBox
  // TOÀN TRANG (Giai đoạn 133, xem giải thích kỹ thuật đầy đủ ở build() phía trên) ---
  Widget _buildConsumptionPage(bool isDark, Color textMain, Color textSub, Color tkGreen, AppTranslations t) {
    // [GIỮ NGUYÊN BIẾN ĐỘNG] '14.5'/'kWh'/'2,104 W'/'124 kWh' là số liệu điện năng (mock chờ
    // tích hợp thật) — CHỈ nhãn (Hôm nay/Đang tiêu thụ/Tháng này) được dịch.
    return _buildScaledPageContent(
      Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(t.text('today'), style: TextStyle(color: textSub, fontSize: 13)), const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text('14.5', style: TextStyle(color: textMain, fontSize: 40, fontWeight: FontWeight.w900)), const SizedBox(width: 4), Text('kWh', style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 6), Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1), const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(child: Column(children: [Text(t.text('consuming'), style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text('2,104 W', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))])),
              Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 8)),
              Expanded(child: Column(children: [Text(t.text('this_month'), style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text('124 kWh', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))])),
            ],
          ),
        ],
      ),
    );
  }

  // [GIAI ĐOẠN 133 — "VIÊN ĐẠN BẠC" FITTEDBOX, DÙNG CHUNG CHO CẢ 3 TRANG] FittedBox cấp
  // UNCONSTRAINED (0..∞) cho [content] ở CẢ 2 TRỤC, không chỉ chiều cao — nếu để [content] (Column
  // chứa Divider/Row có Expanded) trực tiếp nhận constraint đó, Divider (tự expand theo chiều
  // rộng) VÀ mọi Row bên trong có Expanded sẽ ném "BoxConstraints forces an infinite width" —
  // MỘT LỚP CRASH KHÁC, không phải overflow, thậm chí còn dễ vỡ hơn lỗi ban đầu. Chốt chặn:
  // SizedBox(width: 260) ĐẶT TRƯỚC KHI vào Column — tái lập lại 1 chiều rộng THAM CHIẾU hữu hạn
  // (260, xấp xỉ bề ngang nội dung thật của thẻ) cho TOÀN BỘ cây con NGAY LẬP TỨC, khiến Divider/
  // Expanded phía trong an toàn tuyệt đối — FittedBox bên ngoài vẫn tự do co giãn cả khối 260 đó
  // (rộng lẫn cao) vừa khít không gian THẬT do PageView cấp, đúng tinh thần "viên đạn bạc".
  Widget _buildScaledPageContent(Widget content) {
    return Padding(
      // [CHỪA CHỖ CHO PAGE INDICATOR ĐÈ LÊN] indicator Positioned đáy (xem build()) — phần chừa
      // này nằm TRONG vùng được FittedBox co giãn cùng, tự thu nhỏ đồng bộ với chữ khi chật.
      padding: const EdgeInsets.only(bottom: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: SizedBox(width: 260, child: content),
      ),
    );
  }

  // --- Trang 2: Tổng quan Điện mặt trời (PV Generation + Trạng thái Ắc quy) ---
  // [MOCK — CHỜ TÍCH HỢP THẬT] Cùng tình trạng với Trang 1 trước Giai đoạn 131: chưa có cảm biến
  // PV/BMS ắc quy nào bắn số liệu thật lên Server — số liệu ở đây CỐ ĐỊNH, chỉ minh hoạ bố cục.
  Widget _buildSolarPage(bool isDark, Color textMain, Color textSub, Color tkGreen) {
    const Color solarYellow = Color(0xFFFFC107);
    const Color batteryBlue = Color(0xFF2196F3);
    return _buildScaledPageContent(
      Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Column(children: [
                  Icon(Icons.solar_power_rounded, color: solarYellow, size: 22),
                  const SizedBox(height: 4),
                  Text('3.2 kW', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('PV đang sinh', style: TextStyle(color: textSub, fontSize: 10)),
                ]),
              ),
              Container(width: 1, height: 44, color: isDark ? Colors.white10 : Colors.black12),
              Expanded(
                child: Column(children: [
                  Icon(Icons.battery_charging_full_rounded, color: batteryBlue, size: 22),
                  const SizedBox(height: 4),
                  Text('68%', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('Ắc quy (đang sạc)', style: TextStyle(color: textSub, fontSize: 10)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 6), Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1), const SizedBox(height: 6),
          Text('Sản lượng hôm nay: 9.6 kWh', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --- Trang 3: Top thiết bị tiêu thụ ---
  Widget _buildTopDevicesPage(bool isDark, Color textMain, Color textSub, Color tkGreen) {
    // [MOCK — CHỜ TÍCH HỢP THẬT] Xem energy_sample_data.dart cho bản đầy đủ dùng ở
    // FullEnergyDashboardScreen — ở đây chỉ trích Top-3 gọn cho vừa 1 trang thẻ thu nhỏ.
    const List<({String name, String kwh})> top = [
      (name: 'Điều hòa Phòng khách', kwh: '5.0 kWh'),
      (name: 'Công tơ tổng', kwh: '3.2 kWh'),
      (name: 'Bình nóng lạnh', kwh: '1.6 kWh'),
    ];
    return _buildScaledPageContent(
      Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final d in top)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: tkGreen),
                  const SizedBox(width: 8),
                  Expanded(child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontSize: 12.5, fontWeight: FontWeight.w600))),
                  Text(d.kwh, style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
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
  final VoidCallback? onChangeAvatar; // [BƯỚC 5] "Thay đổi giao diện (Avatar)" trong menu nhấn-giữ
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
  // [GIAI ĐOẠN 125 — GỘP/TÁCH CÔNG TẮC ĐA KÊNH] null = thẻ này KHÔNG thuộc 1 MAC đa kênh nào (1-
  // gang thật, hoặc là 1 kênh của MAC đa kênh nhưng đang hiện dạng gán Avatar riêng — không đi
  // qua đường này) -> KHÔNG hiện mục menu. Khác null = thẻ đang BUNG LẺ (1 trong N kênh cùng MAC)
  // -> hiện mục "Gộp thành 1 thẻ" trong menu nhấn giữ, gọi callback này để chuyển sang chế độ Gộp.
  final VoidCallback? onToggleGrouping;

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
    this.onChangeAvatar,
    this.hasHiddenDevices = false, this.isShowingHidden = false, this.onToggleShowHidden,
    this.onAssignHome,
    this.onAssignRoom,
    this.onOpenSettings,
    this.onDeviceTimer, this.onDeviceHistory, this.onDeviceAutomation, this.onDeviceShare,
    this.isGroup = false,
    this.onEditGroup,
    this.onGroupToggle,
    this.onToggleGrouping,
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
      onChangeAvatar: widget.onChangeAvatar,
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
        // [GIAI ĐOẠN 125 — GỘP/TÁCH] Chỉ hiện khi thẻ này thuộc 1 MAC đa kênh đang BUNG LẺ.
        if (widget.onToggleGrouping != null)
          DeviceMenuItem(
            icon: Icons.view_module_rounded,
            title: 'Gộp thành 1 thẻ',
            onTap: widget.onToggleGrouping!,
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
                  // [FIX ICON TO HƠN 30%] 36px cũ trông bé so với thẻ vuông 1x1 — tăng lên 47px
                  // (36 * 1.3 ≈ 46.8, làm tròn) để cân đối, rõ ràng hơn — cùng tinh thần đã áp
                  // cho icon nút nguồn của các Avatar Công tắc (TouchSwitchAvatar/_PowerGlowButton).
                  Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.only(bottom: 14.0, top: 10.0), child: Icon(widget.isMaster ? Icons.settings_power_rounded : Icons.power_settings_new_rounded, color: powerIconColor, size: 47))),
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
// 🧱 [GIAI ĐOẠN 115] KHỐI MẶT CÔNG TẮC VẬT LÝ (PHYSICAL FACEPLATE) — Đa kênh (2-4 gang)
// ============================================================================
// [KIẾN TRÚC "SERVER MÙ"] Backend KHÔNG đổi gì — thứ tự vẫn tính theo MAC (device_order/
// device_grid_layout, xem Giai đoạn 72/113). Đây THUẦN là quyết định RENDER phía Flutter: thay vì
// N thẻ SmartSwitchCard rời rạc (1 thẻ/1 kênh) cho các công tắc CÙNG MAC, gom lại thành MỘT khối
// duy nhất giống mặt công tắc vật lý thật — xem _buildFaceplateEntry() (nơi gọi, trong
// _buildSwitchCardEntries). [1-GANG GIỮ NGUYÊN 100%] Thiết bị chỉ có ĐÚNG 1 kênh KHÔNG đi qua
// đường này — vẫn dùng thẳng SmartSwitchCard như trước (xem _buildSingleSwitchEntry) để tuyệt
// đối không đổi hình dáng/hành vi của đa số thiết bị (1-gang) đang có trong nhà người dùng.
//
// [MENU 2 CẤP] Nhấn giữ MỘT NÚT (ô con) -> menu NHẸ chỉ gồm "Đổi tên nút"+"Thay đổi giao diện"
// (2 việc THẬT SỰ thuộc về riêng kênh đó). Nhấn giữ vùng TIÊU ĐỀ (tên thiết bị, phía trên khối)
// -> menu ĐẦY ĐỦ cấp thiết bị (Cài đặt/Hẹn giờ/Lịch sử/Ngữ cảnh/Chia sẻ/Ẩn CẢ KHỐI/Chuyển phòng/
// Chuyển nhà/Xóa CẢ THIẾT BỊ) — khớp đúng cách người dùng nghĩ về 1 mặt công tắc vật lý: đổi tên
// từng nút thì làm ngay tại nút, còn "cài đặt thiết bị"/"xóa" là việc của CẢ CÁI mặt công tắc.

/// Một Ô BẤM bên trong khối — KHÔNG tự có shell/blur riêng (khối cha PhysicalSwitchBlockCard
/// cấp NỀN KÍNH DÙNG CHUNG, xem buildGrid()) — chỉ là icon+nhãn+InkWell. Stateless: mọi prop đọc
/// trực tiếp mỗi lần build lại (không cần local state mirror như SmartSwitchCard — khối cha đã
/// rebuild toàn bộ mỗi khi DeviceProvider đổi).
///
/// [FIX GIAI ĐOẠN 116 — CHỌN NHIỀU TRẢ VỀ ĐÚNG TỪNG NÚT] Trước đây "Chọn nhiều" gộp theo CẢ
/// KHỐI (mac trần) — SAI, vì _selectedMacs()/_bulkCreateGroup (Nhóm ảo/Cầu thang) vốn hoạt động
/// độc lập theo TỪNG hideKey (mac_endpoint) từ trước giờ, không hề đổi. Nay mỗi nút tự có
/// isSelectionMode/isSelected/checkbox RIÊNG — đúng data model gốc, chỉ hình dáng (layout) đổi.
///
/// [GIAI ĐOẠN 128 — ĐỒNG BỘ DESIGN SYSTEM VỚI THẺ ĐƠN] Đập bỏ HẲN 2 phong cách riêng của Giai
/// đoạn 117 (Neumorphic 3D nổi) và 119 (Neon Glow viền-mà-không-đổ-nền) — cả 2 khiến thẻ kênh
/// TRONG popup trông "khác hệ" hoàn toàn so với SmartSwitchCard NGOÀI Dashboard. Nay sao chép Y
/// HỆT công thức màu/viền/bo góc của SmartSwitchCard (xem build() của _SmartSwitchCardState):
/// BẬT = nền ĐẶC tkGreen (Solid Background, không phải viền glow), TẮT = nền trung tính theo
/// Theme, Ngoại tuyến = xám — popup phải là "bản sao thu nhỏ" của thẻ ngoài, không phải một ngôn
/// ngữ thị giác riêng của chính nó.
class _SwitchGangButton extends StatelessWidget {
  final String name;
  final bool isOn;
  final bool isOffline;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  const _SwitchGangButton({
    required this.name,
    required this.isOn,
    required this.isOffline,
    required this.onTap,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color tkGreen = Color(0xFF00A651);
    final bool lit = isOn && !isOffline;

    // [GIAI ĐOẠN 128] Copy Y HỆT bgColor/textColor/powerIconColor/border của SmartSwitchCard —
    // chỉ đổi tên biến "isOnline" (thẻ đơn) thành "lit" (khớp tên đã dùng sẵn ở đây), cùng công
    // thức tuyệt đối, không tự sáng tạo thêm bảng màu riêng.
    final Color bgColor = isOffline
        ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade200)
        : (lit ? tkGreen : (isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.6)));
    final Color textColor = isOffline ? Colors.grey : (lit ? Colors.white : (isDark ? Colors.white : Colors.black87));
    final Color powerIconColor = isOffline ? Colors.grey.withValues(alpha: 0.4) : (lit ? Colors.white : (isDark ? Colors.white24 : Colors.grey.shade400));
    final Color typeIconColor = isOffline ? Colors.grey : (lit ? Colors.white : tkGreen);
    final Border border = Border.all(
      color: isSelected ? tkGreen : (isOffline ? Colors.grey.withValues(alpha: 0.3) : (lit ? tkGreen : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white))),
      width: isSelected ? 3.0 : 1.5,
    );

    // [YÊU CẦU #4 — BO GÓC KHỚP THẺ NGOÀI] 16, giống hệt SmartSwitchCard (trước đây 14).
    // [YÊU CẦU #3 — KHÔNG CÒN margin quanh từng ô] Khoảng cách giữa các ô nay do
    // mainAxisSpacing/crossAxisSpacing của GridView đảm nhiệm (xem buildGrid() ở
    // PhysicalSwitchBlockCard) — Container margin riêng trước đây (Giai đoạn 117) sẽ CỘNG DỒN
    // với spacing của Grid, gây khoảng trống thừa "phình" đúng như user phản ánh.
    return Container(
      decoration: BoxDecoration(color: bgColor, border: border, borderRadius: BorderRadius.circular(16)),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias, // ripple giới hạn ĐÚNG trong khối bo góc này, không lem ra ngoài
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isOffline && !isSelectionMode ? null : onTap,
          onLongPress: isSelectionMode ? null : onLongPress,
          // [YÊU CẦU #4 — KHỚP LAYOUT ICON/TEXT VỚI THẺ NGOÀI] Cùng cấu trúc Stack với
          // SmartSwitchCard: icon loại nhỏ góc trên-trái, icon Power CĂN GIỮA tuyệt đối, tên nằm
          // DƯỚI CÙNG — không còn Column-lồng-trong-Padding riêng của bản Neumorphic cũ.
          child: Stack(
            children: [
              Positioned(top: 8, left: 8, child: Icon(isOffline ? Icons.cloud_off_rounded : Icons.lightbulb_outline, size: 15, color: typeIconColor)),
              if (isSelectionMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(color: isDark ? const Color(0xFF243248) : Colors.white, shape: BoxShape.circle),
                    child: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 15,
                      color: isSelected ? tkGreen : (isDark ? Colors.white38 : Colors.grey.shade400),
                    ),
                  ),
                ),
              // [FIX GIAI ĐOẠN 129 — YÊU CẦU #3.2] size:32 -> 47 + padding(bottom:14,top:10) — COPY
              // Y HỆT giá trị thật của icon Power ở SmartSwitchCard ngoài Dashboard (dòng ~6066),
              // không bịa số mới, để 2 icon tuyệt đối bằng nhau giữa thẻ trong Popup và thẻ ngoài.
              Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14.0, top: 10.0),
                  child: Icon(Icons.power_settings_new_rounded, color: powerIconColor, size: 47),
                ),
              ),
              // [FIX GIAI ĐOẠN 129] fontSize 10.5 -> 11 + height 1.15 -> 1.2 — khớp Y HỆT Text tên
              // thiết bị của SmartSwitchCard (dòng ~6067: fontSize:11, height:1.2, maxLines:2).
              Positioned(
                bottom: 8,
                left: 6,
                right: 6,
                child: Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold, height: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Khối mặt công tắc HOÀN CHỈNH — bọc N [_SwitchGangButton] (hoặc widget Avatar per-gang, xem
/// _buildFaceplateEntry) theo layout khớp gangCount (cells.length): 2 -> Row chia đôi có
/// [VerticalDivider]; 3 -> Column chia 3 có [Divider] ngang; 4+ -> lưới 2 cột (2x2 chuẩn EU/VN,
/// dư hàng tự xuống dòng).
///
/// [FIX GIAI ĐOẠN 116 — CRASH LAYOUT KHỐI 3-4 NÚT] Khối span>=2 (3-4 gang, xem _buildFaceplateEntry)
/// được _buildAvatarStaggeredGrid cấp height=null (KHÔNG bounded — để khối tự phình theo nội
/// dung, đúng yêu cầu Giai đoạn 115). Bản trước dùng `Flexible(child: buildGrid())` bên trong một
/// Column không có chiều cao xác định — Flutter THROW RenderFlex assertion ("children have
/// non-zero flex but incoming height constraints are unbounded") vì Flexible/Expanded BẮT BUỘC
/// cha phải bounded. Lỗi render này chính là nguyên nhân "giao diện thô" (Flutter vẽ overlay lỗi
/// đỏ/vàng thay vì thẻ thật) VÀ "mất sự kiện" (subtree lỗi không nhận hit-test đúng) người dùng
/// báo — KHÔNG phải do quên gán callback. Nay dùng LayoutBuilder đọc constraints.maxHeight THẬT:
/// bounded (1-2 gang, ô vuông) -> vẫn dùng Expanded lấp đầy như cũ; unbounded (3-4 gang) -> bỏ
/// hẳn Expanded/Flexible, để Column/GridView tự cao theo nội dung (không cần ép).
class PhysicalSwitchBlockCard extends StatelessWidget {
  final String deviceName;
  final List<Widget> cells;
  final bool isOffline;
  final bool isHidden;
  final VoidCallback onOpenDeviceMenu; // menu CẤP THIẾT BỊ — nhấn giữ vùng tiêu đề
  // [GIAI ĐOẠN 115] null = thiết bị KHÔNG có nút "Tất cả" ảo (hiếm — luôn có khi >=2 kênh, xem
  // _buildFaceplateEntry) -> chạm tiêu đề không làm gì. Khác null -> chạm tiêu đề TOGGLE TẤT CẢ
  // kênh — khôi phục đúng chức năng nút "Tất cả (N kênh)" trước đây (từng là 1 thẻ ĐỘC LẬP, nay
  // gộp vào tiêu đề khối). [FIX GIAI ĐOẠN 116] Chỉ hoạt động khi KHÔNG đang Chọn nhiều (tránh bật
  // nhầm cả cụm relay khi người dùng đang thao tác chọn) — xem build().
  final VoidCallback? onToggleAll;
  final bool isSelectionMode;
  const PhysicalSwitchBlockCard({
    super.key,
    required this.deviceName,
    required this.cells,
    this.isOffline = false,
    this.isHidden = false,
    required this.onOpenDeviceMenu,
    this.onToggleAll,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final int n = cells.length;
    final Color dividerColor = isDark ? Colors.white24 : Colors.grey.withValues(alpha: 0.25);
    const Color tkGreen = Color(0xFF00A651);

    // [ĐỢT 18 — ĐÁNH NỔI KHỐI] Cùng công thức viền+bóng đổ Sáng Thường đã dùng cho SmartSwitchCard
    // (chỉ khác object riêng vì đây là widget top-level, không truy cập được field của State khác).
    final BoxDecoration outerDecoration = (!isDark && !isGlass)
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
          )
        : BoxDecoration(borderRadius: BorderRadius.circular(16));

    // [GIAI ĐOẠN 123 — ĐƠN GIẢN HÓA] Widget này giờ CHỈ còn sống bên trong popup phóng to
    // (_showFaceplateExpanded, luôn cấp chiều cao BOUNDED qua ConstrainedBox) — không còn dùng
    // trực tiếp trên lưới Dashboard nữa (đã thay bằng _FaceplateCompactCard từ Giai đoạn 120). Vì
    // vậy KHÔNG còn cần phân biệt bounded/unbounded height hay 3 kiểu layout Row/Column/GridView
    // riêng cho từng số kênh (nguồn của toàn bộ rủi ro crash Giai đoạn 116/121) — LUÔN dùng ĐÚNG 1
    // GridView.builder(shrinkWrap:true) như yêu cầu tường minh: tự thu gọn chiều cao theo đúng số
    // kênh (2 kênh -> lưới thấp, 8 kênh -> lưới cao hơn), không tràn/không thừa khoảng trống.
    // [FIX GIAI ĐOẠN 128/129 — VUÔNG + SPACING] childAspectRatio 1.3 (dẹt ngang) -> 1.0 (VUÔNG
    // chuẩn, khớp tỉ lệ SmartSwitchCard ngoài Dashboard). mainAxisSpacing/crossAxisSpacing 10 -> 16
    // (Giai đoạn 129, yêu cầu #3.1 — Popup thu hẹp còn maxWidth 360 nên mỗi ô cũng NHỎ LẠI theo, cần
    // spacing rộng hơn để không dính khít phản tác dụng với Yêu cầu #3.2 phóng to icon Power).
    Widget buildGrid() {
      if (n == 0) return const SizedBox();
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.0, mainAxisSpacing: 16, crossAxisSpacing: 16),
        itemCount: n,
        itemBuilder: (_, i) => cells[i],
      );
    }

    return Container(
      decoration: outerDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            foregroundDecoration: isHidden ? BoxDecoration(color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.7)) : null,
            decoration: BoxDecoration(
              color: isOffline ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade200) : (isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white, width: 1.5),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // [GIAI ĐOẠN 122 — CÔNG TẮC TỔNG TƯỜNG MINH] Trước đây "Tất cả" chỉ ẩn trong
                  // hành vi chạm-cả-vùng-tiêu-đề (dễ bấm nhầm/khó nhận ra) — nay tách 2 vùng RIÊNG
                  // BIỆT trong cùng hàng: vùng tên+icon (nhấn giữ = Menu đầy đủ cấp thiết bị) và 1
                  // "chip" nút BẬT/TẮT TẤT CẢ độc lập, chỉ hiện khi onToggleAll != null.
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onLongPress: isSelectionMode ? null : onOpenDeviceMenu,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                          child: Row(children: [
                            Icon(Icons.grid_view_rounded, size: 13, color: isDark ? Colors.white54 : Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Expanded(child: Text(deviceName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isDark ? Colors.white70 : Colors.black54))),
                          ]),
                        ),
                      ),
                    ),
                    if (onToggleAll != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Material(
                          color: tkGreen.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: isSelectionMode ? null : onToggleAll,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.power_settings_new_rounded, size: 14, color: tkGreen),
                                SizedBox(width: 4),
                                Text('Tất cả', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tkGreen)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ]),
                  Divider(height: 1, thickness: 1, color: dividerColor),
                  Padding(padding: const EdgeInsets.all(12), child: buildGrid()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 🔲 [GIAI ĐOẠN 120] Ô THU GỌN 1x1 CHO KHỐI MẶT CÔNG TẮC ĐA KÊNH + PHÓNG TO XEM ĐẦY ĐỦ
// ============================================================================
// [TẠI SAO CẦN LỚP NÀY] Giai đoạn 115-119 xây PhysicalSwitchBlockCard đẹp, đủ chức năng — nhưng
// span 2 (3-4 gang) trên Mobile bị luật "full-width thẻ lớn" (Giai đoạn 107) đẩy lên chiếm TRỌN
// bề ngang màn hình, phá vỡ nhịp lưới đều 1x1 của các Công tắc đơn xung quanh — đúng report "2-4
// cột làm nát bố cục". Nay ép TẤT CẢ khối đa kênh về ĐÚNG span=1 (vuông, bằng công tắc đơn) —
// bên trong chỉ hiện TỐI ĐA 4 nút thu nhỏ (đủ cho 2/3/4-gang; 5+ gang hiện 3 nút đầu + 1 ô "+N"
// gợi ý còn nhiều nút hơn) dưới dạng GridView 2 cột, CHẠM NỀN TRỐNG (không trúng nút nào) sẽ mở
// showAppBottomSheet chứa NGUYÊN VẸN PhysicalSwitchBlockCard cỡ đầy đủ để thao tác dễ hơn.
//
// [GIỚI HẠN ĐÃ BIẾT — CHƯA LÀM] Nội dung bên trong popup là ẢNH TĨNH tại thời điểm mở (không bọc
// Consumer<DeviceProvider> riêng) — nếu trạng thái đổi qua MQTT trong lúc popup đang mở, phải
// đóng/mở lại mới thấy giá trị mới nhất; bấm nút TRONG popup vẫn gửi lệnh thật (KHÔNG mất tác
// dụng), chỉ là icon không tự đổi màu ngay tại chỗ do dự án này theo triết lý "REAL-STATE, không
// optimistic UI" xuyên suốt (xem SmartSwitchCard). Chấp nhận được vì popup dùng để thao tác nhanh
// rồi đóng, không phải màn hình theo dõi trạng thái sống dài hạn.

/// Nút mini bên trong ô thu gọn — CHỈ icon (không nhãn, không viền dày/glow lớn như
/// _SwitchGangButton — sẽ vỡ hình ở kích thước ~20-30px) — vẫn giữ ngôn ngữ màu Neon Glow
/// (Giai đoạn 119: viền+icon xanh greenAccent khi BẬT) để đồng bộ thị giác với popup phóng to.
class _FaceplateMiniButton extends StatelessWidget {
  final bool isOn;
  final bool isOffline;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _FaceplateMiniButton({required this.isOn, required this.isOffline, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool lit = isOn && !isOffline;
    final Color color = isOffline ? Colors.grey.withValues(alpha: 0.4) : (lit ? Colors.greenAccent : (isDark ? Colors.white38 : Colors.grey.shade400));
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: color, width: lit ? 1.4 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isOffline ? null : onTap,
          onLongPress: onLongPress,
          child: Center(child: Icon(isOffline ? Icons.cloud_off_rounded : Icons.power_settings_new_rounded, size: 16, color: color)),
        ),
      ),
    );
  }
}

/// Ô "+N" thay cho nút mini thứ 4 khi có TRÊN 4 kênh — báo hiệu còn nút chưa hiện, gợi ý chạm để
/// xem đủ (chạm vào Ô NÀY cũng mở popup luôn, không cần chạm đúng pixel nền trống).
class _FaceplateMoreButton extends StatelessWidget {
  final int remaining;
  final VoidCallback onTap;
  const _FaceplateMoreButton({required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Center(child: Text('+$remaining', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isDark ? Colors.white70 : Colors.black54))),
        ),
      ),
    );
  }
}

/// Thẻ THU GỌN 1x1 đại diện cho khối mặt công tắc đa kênh trên lưới Dashboard chính — xem khối
/// comment ở trên. [onExpand] mở popup cỡ đầy đủ; [onOpenDeviceMenu] cũng mở qua CHẠM NỀN TRỐNG
/// (không có khái niệm "nhấn giữ nền = menu" riêng ở đây nữa — nền trống dành hẳn cho onExpand vì
/// không gian 1 ô 1x1 quá nhỏ để phân biệt tap/long-press trực quan; menu đầy đủ vẫn mở được từ
/// BÊN TRONG popup, xem PhysicalSwitchBlockCard.onOpenDeviceMenu).
// [GIAI ĐOẠN 122 — SỐ CHÌM (WATERMARK) + NHẤN GIỮ MỞ RỘNG] Thay hẳn dòng chữ "Tất cả (x kênh)"
// (khiến ô 1x1 vốn đã chật lại càng chật) bằng 1 con số CHÌM cực to ở NỀN — vừa cho biết ngay số
// kênh mà không tốn diện tích UI thật nào (số nằm DƯỚI CÙNG Stack, các nút mini đè lên trên).
// Tương tác nền đổi từ TAP sang LONG-PRESS mở popup (yêu cầu tường minh) — tap không còn tác dụng
// gì trên vùng nền trống nữa, chỉ nút mini mới phản hồi tap (bật/tắt) như trước.
class _FaceplateCompactCard extends StatelessWidget {
  final int channelCount; // TỔNG số kênh thật — KHÁC miniCells.length (có thể đã cắt còn 3 + ô "+N")
  final List<Widget> miniCells; // tối đa 4 phần tử (đã cắt + chèn _FaceplateMoreButton nếu cần)
  final bool isOffline;
  final bool isHidden;
  final VoidCallback onExpand;
  const _FaceplateCompactCard({
    required this.channelCount,
    required this.miniCells,
    required this.isOffline,
    required this.isHidden,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;

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
            foregroundDecoration: isHidden ? BoxDecoration(color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.7)) : null,
            decoration: BoxDecoration(
              color: isOffline ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade200) : (isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white, width: 1.5),
            ),
            child: Stack(
              children: [
                // [LỚP DƯỚI — SỐ CHÌM] Font cực to, alpha cực thấp — chỉ gợi ý, không cạnh tranh
                // thị giác với các nút mini vẽ đè lên trên.
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$channelCount',
                      style: TextStyle(
                        fontSize: 64,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.07 : 0.05),
                      ),
                    ),
                  ),
                ),
                // [LỚP GIỮA — NỀN TRỐNG -> NHẤN GIỮ MỞ RỘNG] Positioned.fill nằm DƯỚI lưới nút mini
                // (vẽ sau, xem bên dưới) — chỉ nhận được cử chỉ ở phần diện tích KHÔNG bị nút mini
                // che phủ. CHỈ onLongPress — tap ở vùng nền không còn tác dụng gì (yêu cầu tường minh).
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(borderRadius: BorderRadius.circular(16), onLongPress: onExpand),
                  ),
                ),
                // [LỚP TRÊN CÙNG — LƯỚI NÚT MINI] [YÊU CẦU #2] GridView.count(crossAxisCount: 2).
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 0,
                    crossAxisSpacing: 0,
                    physics: const NeverScrollableScrollPhysics(),
                    children: miniCells,
                  ),
                ),
              ],
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
  final VoidCallback? onChangeAvatar; // [BƯỚC 5] "Thay đổi giao diện (Avatar)" trong menu nhấn-giữ
  final bool isHidden;                       // đang nằm trong danh sách ẩn của Bảng điều khiển
  final ValueChanged<bool>? onToggleHide;    // callback ẩn/hiện — [FIX] trước đây nút Ẩn bị liệt vì thiếu hàm này
  final Map<String, dynamic> rawDeviceData; // gói REST đầy đủ (system_data, fw_type...) cho Popup Cài đặt
  final VoidCallback? onAssignHome; // [ADMIN] Chuyển nhà — non-null CHỈ khi user là SUPER_USER
  final VoidCallback? onAssignRoom; // [PHÒNG] Chuyển/Thêm vào phòng
  final VoidCallback? onOpenSettings; // [CHUẨN HÓA] Cài đặt thiết bị (null -> settings nội bộ)
  // [CHUẨN TUYA/GOOGLE HOME] bộ chức năng mở rộng (Thông tin đã gộp vào onOpenSettings)
  final VoidCallback? onDeviceTimer, onDeviceHistory, onDeviceAutomation, onDeviceShare;

  const SmartFanCard({super.key, required this.mac, required this.endpoint, required this.initialSpeed, required this.initialSwing, this.backendName, this.isOffline = false, required this.provider, required this.onRefresh, required this.onDelete, this.onRename, this.onChangeAvatar, this.isHidden = false, this.onToggleHide, this.rawDeviceData = const {}, this.onAssignHome, this.onAssignRoom, this.onOpenSettings, this.onDeviceTimer, this.onDeviceHistory, this.onDeviceAutomation, this.onDeviceShare});
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
      onChangeAvatar: widget.onChangeAvatar,
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

    // [FIX #3 — BƯỚC 5] onLongPress mở ĐÚNG menu dùng chung (đã có "Thay đổi giao diện") — an
    // toàn thêm mới vì thẻ Quạt TRƯỚC ĐÂY chỉ mở menu qua nút "..." (IconButton.onPressed), CHƯA
    // hề có onLongPress nào ở đây để tranh chấp gesture arena.
    return GestureDetector(
      onLongPress: () => _showDeviceOptions(context, isDark),
      child: Container(
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
                    // [FIX GIAI ĐOẠN 120] Cùng lỗi tương phản Sáng+Kính với _buildBtn ở trên — thêm viền
                    // black12 CHỈ khi Sáng+Kính+CHƯA bật (isSwingActive đã có nền tkGreen đặc, tự đủ tương phản).
                    Material(
                      color: isSwingActive ? tkGreen.withValues(alpha: 0.85) : (isDark ? Colors.white24 : (isGlass ? Colors.white.withValues(alpha: 0.6) : Colors.grey.shade200)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: (isGlass && !isDark && !isSwingActive) ? const BorderSide(color: Colors.black12, width: 1) : BorderSide.none,
                      ),
                      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: _toggleSwing, child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, child: Row(children: [Icon(Icons.threesixty, color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), size: 16), const SizedBox(width: 4), Text('Xoay', style: TextStyle(color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 12, fontWeight: FontWeight.w800))]))),
                    )
                  ],
                ),
              )
            ],
          ),
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
    // [FIX GIAI ĐOẠN 120 — TƯƠNG PHẢN NÚT SÁNG+KÍNH] Nút CHƯA CHỌN ở Sáng+Kính (bgColor trắng
    // 60% alpha) không có viền -> tiệp gần như liền mạch với nền kính của cả thẻ (cũng trắng/kính
    // mờ tương tự), mất hẳn ranh giới khối. Thêm viền mờ black12 CHỈ ở đúng trường hợp này — nút
    // ĐANG CHỌN (đã có nền đặc màu tkGreen/đỏ, tự tương phản đủ), Tối, hay Sáng-KHÔNG-Kính (đã có
    // Colors.grey.shade200 đủ đậm từ trước) đều KHÔNG cần viền, giữ nguyên như cũ.
    final bool needsGlassBorder = isGlass && !isDark && !isActive;
    // [FIX CHỮ "OFF" RỚT DÒNG] Nút này nằm trong Expanded (Row 4 nút chia đều bề ngang thẻ) —
    // khi thẻ bị ép hẹp (bin-packing StaggeredGrid trước đây, hoặc bất kỳ layout nào khác sau
    // này), Text 3 ký tự "OFF" không đủ chỗ và TỰ XUỐNG DÒNG giữa chữ (Text mặc định wrap khi
    // không vừa, không có overflow/FittedBox nào chặn). Bọc Text trong FittedBox(scaleDown): chữ
    // tự THU NHỎ CỠ FONT để vừa đúng 1 dòng thay vì gãy dòng — không đặt FittedBox ở NGOÀI
    // Expanded (Expanded cần bề ngang xác định từ Row cha; FittedBox đo con ở ràng buộc VÔ HẠN sẽ
    // làm Expanded trong đó ném lỗi "unbounded width") — đặt ĐÚNG bên trong, quanh mỗi Text riêng.
    return Expanded(child: Material(
      color: bgColor,
      // [Material.shape thay Material.borderRadius] 2 tham số này loại trừ nhau (assert) — dùng
      // shape để vừa bo góc VỪA có thể thêm viền có điều kiện, không cần nhánh code riêng.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: needsGlassBorder ? const BorderSide(color: Colors.black12, width: 1) : BorderSide.none,
      ),
      child: InkWell(borderRadius: BorderRadius.circular(10), onTap: () => _changeSpeed(btnSpeed), child: Container(height: 40, alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 2), child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w900))))),
    ));
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
  final VoidCallback? onChangeAvatar; // [BƯỚC 5] "Thay đổi giao diện (Avatar)" trong menu nhấn-giữ
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
    this.onChangeAvatar,
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

    // [FIX #3 — BƯỚC 5] Tách thành hàm cục bộ để DÙNG CHUNG cho cả nút "..." (đã có từ trước) LẪN
    // onLongPress mới thêm (thẻ Cảm biến TRƯỚC ĐÂY chưa hề có long-press nào, an toàn thêm mới).
    void openMenu() => DeviceMenuHelper.showGenericDeviceMenu(
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
          onChangeAvatar: onChangeAvatar,
          isHidden: isHidden,
          hideLabel: isHidden ? t.text('show_device_again') : t.text('hide_from_dashboard'),
          hideSubtitle: t.text('hide_from_dashboard_desc'),
          onToggleHide: onToggleHide,
          onAssignRoom: onAssignRoom, // [PHÒNG] tự render "Chuyển/Thêm vào phòng"
          onAssignHome: onAssignHome, // tự render "Chuyển nhà" nếu != null (SUPER_USER)
          onDelete: onDelete,
        );

    return GestureDetector(
      onLongPress: openMenu,
      child: Container(
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
                    onPressed: openMenu,
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
  // [FIX GIAI ĐOẠN 124 — TĂNG ĐỘ ĐỤC KÍNH SÁNG] kGlassFrostFill mặc định (showAppDialog không
  // truyền glassTint) chỉ 5% trắng — quá trong suốt trên nền Sáng+Kính, đúng nguyên nhân "chữ đen
  // tiệp vào nền" user báo. Gọi TỪ chuỗi tap-handler (mở popup) -> context.read, không watch.
  final bool isGlassNow = context.read<ThemeProvider>().isGlassThemeEnabled;
  return showAppDialog(
    context: context,
    maxWidth: 440,
    glassTint: (isGlassNow && !isDark) ? Colors.white.withValues(alpha: 0.82) : null,
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
    // [FIX GIAI ĐOẠN 124 — TƯƠNG PHẢN SÁNG+KÍNH] 0xFF64748B (slate nhạt) quá mờ trên nền kính —
    // đổi textSub (dòng phụ/chú thích) sang Colors.black54 theo yêu cầu tường minh. Tối GIỮ NGUYÊN.
    final Color textSub = isDark ? Colors.white54 : Colors.black54;
    // [FIX GIAI ĐOẠN 124] labelColor — riêng cho NHÃN (specRow label, icon đi kèm, tiêu đề mục)
    // ĐẬM HƠN textSub 1 bậc — Sáng: black87 (yêu cầu tường minh); Tối GIỮ NGUYÊN như trước (các
    // nhãn/icon này TRƯỚC ĐÂY dùng chung textSub cũ, ở Tối là white54 — không đổi gì cho Tối).
    final Color labelColor = isDark ? Colors.white54 : Colors.black87;
    // [FIX GIAI ĐOẠN 124 — TIÊU ĐỀ MỤC NỔI BẬT] "THÔNG SỐ KỸ THUẬT"/"Điều khiển Quạt" trước đây
    // dùng chung textSub (mờ, lẫn nền) — Sáng đổi sang tkGreen đậm (màu chính app, yêu cầu tường
    // minh "Primary Color tone đậm"); Tối GIỮ NGUYÊN textSub như trước.
    final Color sectionHeaderColor = isDark ? textSub : tkGreen;
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

    // [FIX GIAI ĐOẠN 124] Icon + Label dùng labelColor (ĐẬM hơn textSub) — yêu cầu tường minh
    // "Icon phải đồng bộ màu với Label", cả 2 đều là nhãn tĩnh (khác Value — dữ liệu thật, giữ
    // textMain đậm nhất + bold để phân cấp thị giác rõ ràng).
    Widget specRow(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: labelColor),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
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
                        Text(t.text('fan_control_header'), style: TextStyle(color: sectionHeaderColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                      Text(t.text('technical_specs_header'), style: TextStyle(color: sectionHeaderColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                        // ---------- [CỬA CUỐN ĐA NĂNG] LOẠI ĐỘNG CƠ (AC_220V / DC_24V) ----------
                        MotorTypeSection(
                          mac: mac,
                          initialMotorType: _asMap(rawDeviceData['settings'])['motor_type']?.toString() ?? '',
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
    // [FIX GIAI ĐOẠN 124] Sáng+Kính: 0xFF64748B quá mờ -> Colors.black54 (yêu cầu tường minh). Tối GIỮ NGUYÊN.
    final Color textSub = widget.isDark ? Colors.white54 : Colors.black54;
    // Icon "đồng bộ màu với Label" — Label hàng này dùng textMain (đã đủ đậm sẵn), Icon đi kèm
    // cũng nâng lên cùng tông thay vì mờ hơn hẳn như trước.
    final Color iconColor = textMain;
    final t = AppTranslations.of(context);

    // [FIX GIAI ĐOẠN 106 — RÀ SOÁT PHÒNG NGỪA] Cùng họ lỗi với MotorTypeSection (ListTile +
    // DropdownButton trailing không khai báo width có thể ép title/subtitle rớt dòng theo ký tự
    // khi nhãn dài/dialog hẹp) — nhãn khối này hiện đang NGẮN nên chưa vỡ, nhưng đổi luôn cấu trúc
    // Row+Expanded+Flexible để nhất quán và chống tái phát nếu nhãn dịch ngôn ngữ khác dài hơn.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.power_rounded, color: iconColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.text('power_on_state_label'), style: TextStyle(color: textMain, fontSize: 14)),
                const SizedBox(height: 2),
                Text(t.text('relay_state_after_loss_label'), style: TextStyle(color: textSub, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_saving)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
          else
            Flexible(
              child: DropdownButton<int>(
                isExpanded: true,
                isDense: true,
                value: _mode,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                dropdownColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: tkGreen, fontSize: 13, fontWeight: FontWeight.bold),
                selectedItemBuilder: (context) => _labels(t).entries.map((e) => Align(alignment: Alignment.centerRight, child: Text(e.value, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                items: _labels(t).entries
                    .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: _change,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 🔧 [CỬA CUỐN ĐA NĂNG — "SERVER MÙ"] KHỐI CHỌN "LOẠI ĐỘNG CƠ" (AC_220V / DC_24V)
// (nhúng trong Popup Cài đặt thiết bị — CHỈ hiện khi category == "curtain")
// Chọn xong -> PUT /api/devices/{mac}/motor-type -> Backend tra bảng preset pulse_ms/
// interlock_ms rồi đẩy xuống mạch qua devices_v2/{mac}/config (retained) — App KHÔNG tự tính
// timing, chỉ chọn loại cửa; Server giữ toàn bộ tri thức "loại nào cần thông số gì".
// ============================================================================
class MotorTypeSection extends StatefulWidget {
  final String mac;
  final String initialMotorType; // '' = chưa chọn (thiết bị vẫn dùng mặc định cứng của firmware)
  final bool isDark;

  const MotorTypeSection({super.key, required this.mac, required this.initialMotorType, required this.isDark});

  @override
  State<MotorTypeSection> createState() => _MotorTypeSectionState();
}

class _MotorTypeSectionState extends State<MotorTypeSection> {
  final Color tkGreen = const Color(0xFF00A651);
  static const List<String> _validTypes = ['AC_220V', 'DC_24V'];
  late String? _motorType; // null = chưa chọn, hiện placeholder
  bool _saving = false;

  Map<String, String> _labels(AppTranslations t) => {
    'AC_220V': t.text('motor_type_ac220v_option'),
    'DC_24V': t.text('motor_type_dc24v_option'),
  };

  @override
  void initState() {
    super.initState();
    _motorType = _validTypes.contains(widget.initialMotorType) ? widget.initialMotorType : null;
  }

  Future<void> _change(String? newType) async {
    if (newType == null || newType == _motorType || _saving) return;
    final t = AppTranslations.of(context, listen: false);
    final String? oldType = _motorType;
    setState(() { _motorType = newType; _saving = true; });
    final ok = await ApiService().setMotorType(widget.mac, newType);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${t.text('motor_type_saved_prefix')} "${_labels(t)[newType]}"'),
        backgroundColor: tkGreen,
      ));
    } else {
      setState(() => _motorType = oldType);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t.text('motor_type_save_error')),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color textMain = widget.isDark ? Colors.white : const Color(0xFF0F172A);
    // [FIX GIAI ĐOẠN 124] Sáng+Kính: 0xFF64748B quá mờ -> Colors.black54 (yêu cầu tường minh). Tối GIỮ NGUYÊN.
    final Color textSub = widget.isDark ? Colors.white54 : Colors.black54;
    // Icon "đồng bộ màu với Label" — Label hàng này dùng textMain, Icon đi kèm nâng cùng tông.
    final Color iconColor = textMain;
    final t = AppTranslations.of(context);

    // [FIX GIAI ĐOẠN 106 — VỠ CHỮ THẲNG ĐỨNG] ListTile TRƯỚC ĐÂY dùng title/subtitle/trailing —
    // nhãn "AC 220V (Khóa chéo nghiêm ngặt)" dài hơn hẳn 2 lựa chọn còn lại khiến DropdownButton
    // (trailing, không khai báo width, tự đòi đủ chỗ cho item DÀI NHẤT trong danh sách kể cả khi
    // đang hiện item khác) đòi bề rộng lớn — RenderListTile chia chỗ còn lại cho cột title/
    // subtitle CÓ THỂ về gần 0px trên dialog hẹp, ép Text bọc từng KÝ TỰ một dòng (đúng ảnh chụp
    // "rớt dòng theo chiều dọc"). Nay THAY ListTile bằng Row tường minh: Expanded bọc cột tiêu đề
    // (LUÔN được ưu tiên chỗ trống trước), Dropdown bọc Flexible (tự co lại + ellipsis nếu vẫn
    // không đủ chỗ) thay vì đòi trọn vẹn bề rộng tuỳ ý như cũ.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.settings_input_component_rounded, color: iconColor, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.text('motor_type_label'), style: TextStyle(color: textMain, fontSize: 14)),
                const SizedBox(height: 2),
                Text(t.text('motor_type_sublabel'), style: TextStyle(color: textSub, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_saving)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
          else
            Flexible(
              // [isExpanded:true BẮT BUỘC] Flexible/Expanded chỉ thật sự "ép co lại" được nếu
              // chính DropdownButton đồng ý nhận constraint lỏng thay vì luôn đòi đủ chỗ cho item
              // DÀI NHẤT — đây là điều kiện Flutter yêu cầu để dùng DropdownButton trong Row cùng
              // Expanded/Flexible (xem docs isExpanded). selectedItemBuilder đảm bảo NÚT ĐÃ ĐÓNG
              // (không phải menu thả xuống) cũng tự rút gọn "..." thay vì tràn ra ngoài.
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                value: _motorType,
                hint: Text(t.text('motor_type_unset_hint'), style: TextStyle(color: textSub, fontSize: 12), overflow: TextOverflow.ellipsis),
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(12),
                dropdownColor: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                style: TextStyle(color: tkGreen, fontSize: 13, fontWeight: FontWeight.bold),
                selectedItemBuilder: (context) => _labels(t).entries.map((e) => Align(alignment: Alignment.centerRight, child: Text(e.value, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                items: _labels(t).entries
                    .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: _change,
              ),
            ),
        ],
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
    // [FIX GIAI ĐOẠN 124] Sáng+Kính: 0xFF64748B quá mờ -> Colors.black54 (yêu cầu tường minh). Tối GIỮ NGUYÊN.
    final Color textSub = widget.isDark ? Colors.white54 : Colors.black54;
    // Icon "đồng bộ màu với Label" — leading + 2 nút +/- (hành động, cũng cần rõ ràng để bấm
    // trúng) đều nâng lên tông textMain thay vì mờ hơn hẳn như trước.
    final Color iconColor = textMain;
    final t = AppTranslations.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(Icons.timer_outlined, color: iconColor, size: 20),
      title: Text(t.text('travel_time_label'), style: TextStyle(color: textMain, fontSize: 14)),
      subtitle: Text(t.text('travel_time_desc'), style: TextStyle(color: textSub, fontSize: 11)),
      trailing: _saving
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: Icon(Icons.remove_circle_outline_rounded, color: iconColor, size: 20), onPressed: () => _change(-1), splashRadius: 18),
                SizedBox(
                  width: 44,
                  child: Text('${_seconds}s', textAlign: TextAlign.center, style: TextStyle(color: tkGreen, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                IconButton(icon: Icon(Icons.add_circle_outline_rounded, color: iconColor, size: 20), onPressed: () => _change(1), splashRadius: 18),
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
    // [FIX GIAI ĐOẠN 124] Sáng+Kính: 0xFF64748B quá mờ -> Colors.black54 (yêu cầu tường minh). Tối GIỮ NGUYÊN.
    final Color textSub = widget.isDark ? Colors.white54 : Colors.black54;
    // Icon "đồng bộ màu với Label" — leading nâng lên tông textMain thay vì mờ hơn hẳn như trước.
    final Color iconColor = textMain;

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
              leading: Icon(Icons.system_update_alt, color: iconColor, size: 20),
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

// [GIAI ĐOẠN 126 — CATALOG BMS THEO NHÓM] Trước đây avatarLibrary hiển thị dạng 1 LƯỚI DÀI DUY
// NHẤT (~50 mục sau khi bổ sung nhóm BMS chuyên nghiệp — Vào ra/Thang máy, Điện & Năng lượng,
// Môi trường & An toàn...) — tìm 1 avatar cụ thể phải cuộn qua toàn bộ, không phân biệt được
// "Công tắc" khác "Công nghiệp" khác "Tòa nhà". Nhóm theo field `category` SẴN CÓ trên
// DeviceAvatarDefinition (trước đây chỉ khai báo, KHÔNG dùng để hiển thị) — gộp NHIỀU category id
// kỹ thuật vào 1 NHÃN hiển thị khi chúng cùng một "mảng nghiệp vụ" theo đúng yêu cầu người dùng
// (vd access_control + elevator cùng vào "Kiểm soát Vào ra & Thang máy").
class _AvatarCategoryGroup {
  final String label;
  final IconData icon;
  final List<String> categoryIds;
  const _AvatarCategoryGroup({required this.label, required this.icon, required this.categoryIds});
}

const List<_AvatarCategoryGroup> _avatarCategoryGroups = [
  _AvatarCategoryGroup(label: 'Công tắc & Ổ cắm', icon: Icons.toggle_on_outlined, categoryIds: ['switch']),
  _AvatarCategoryGroup(label: 'Chiếu sáng', icon: Icons.lightbulb_outline, categoryIds: ['lighting']),
  _AvatarCategoryGroup(label: 'Không khí & Nhiệt độ', icon: Icons.air_rounded, categoryIds: ['climate']),
  _AvatarCategoryGroup(label: 'An ninh & Cửa', icon: Icons.security_rounded, categoryIds: ['security']),
  _AvatarCategoryGroup(label: 'Kiểm soát Vào ra & Thang máy', icon: Icons.badge_outlined, categoryIds: ['access_control', 'elevator']),
  _AvatarCategoryGroup(label: 'Điện & Năng lượng', icon: Icons.bolt_rounded, categoryIds: ['electrical_panel']),
  _AvatarCategoryGroup(label: 'Môi trường & An toàn tòa nhà', icon: Icons.health_and_safety_outlined, categoryIds: ['hvac', 'building_sensor']),
  _AvatarCategoryGroup(label: 'Công nghiệp', icon: Icons.precision_manufacturing_outlined, categoryIds: ['industrial_pump', 'industrial_fan', 'spot_welder']),
  _AvatarCategoryGroup(label: 'Thiết bị gia dụng', icon: Icons.kitchen_outlined, categoryIds: ['appliance']),
  _AvatarCategoryGroup(label: 'Thiết bị IT', icon: Icons.dns_outlined, categoryIds: ['it_equipment']),
];

// [FIX #1 — LƯỚI 3 CỘT, GIAI ĐOẠN 126 — THÊM BỘ LỌC NHÓM] Nội dung popup "Thay đổi giao diện
// (Avatar)" — tách thành widget riêng (thay vì Builder lồng sâu ngay trong _showAvatarPicker) để
// cấu trúc widget rõ ràng, dễ soát lỗi cân bằng ngoặc hơn. [onSelect] nhận null = "về mặc định",
// hoặc avatarId đã chọn. Đổi sang StatefulWidget để giữ chip Nhóm đang chọn (_selectedGroup) —
// null = "Tất cả" (hiển thị TOÀN BỘ theo từng Nhóm có tiêu đề, cùng "Mặc định" ở đầu).
class _AvatarPickerDialogBody extends StatefulWidget {
  final String? currentId;
  final double maxHeight;
  final ValueChanged<String?> onSelect;

  const _AvatarPickerDialogBody({required this.currentId, required this.maxHeight, required this.onSelect});

  @override
  State<_AvatarPickerDialogBody> createState() => _AvatarPickerDialogBodyState();
}

class _AvatarPickerDialogBodyState extends State<_AvatarPickerDialogBody> {
  _AvatarCategoryGroup? _selectedGroup; // null = "Tất cả"

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    const Color tkGreen = Color(0xFF00A651);

    Widget buildTile(DeviceAvatarDefinition def) => _AvatarPickerTile(
          label: def.name,
          selected: widget.currentId == def.id,
          isDark: isDark,
          preview: IgnorePointer(
            child: FittedBox(
              fit: BoxFit.contain,
              child: def.buildWidget(
                context,
                (isOn: true, speed: 2, value: 60, metric: 42, metricHistory: const [22, 24, 23, 26, 30, 28, 27], isOffline: false),
                (onToggle: (_) {}, onChange: (_, _) {}),
              ),
            ),
          ),
          onTap: () => widget.onSelect(def.id),
        );

    // [FIX — MAX-EXTENT THAY VÌ SỐ CỘT CỨNG] crossAxisCount cố định (dù là 3) vẫn KÉO GIÃN từng
    // ô để lấp đầy hết bề ngang Dialog — trên PC/Web (Dialog rộng tới 800px), 3 ô bị ép phình to
    // biến dạng. SliverGridDelegateWithMaxCrossAxisExtent làm NGƯỢC LẠI: ấn định TRẦN rộng một ô
    // (maxCrossAxisExtent), màn càng rộng thì tự "đẻ" thêm CỘT chứ không phình ô — ô luôn giữ
    // đúng kích thước thiết kế bất kể Dialog rộng bao nhiêu.
    Widget buildGrid(List<Widget> tiles) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            // [FIX BOTTOM OVERFLOW] 0.85 chưa đủ cao chứa nổi vùng preview 96px + khoảng
            // cách 6px + tối đa 2 dòng nhãn tên Avatar — hạ xuống 0.78 để có thêm không
            // gian chiều dọc. Xem thêm _AvatarPickerTile: vùng preview giờ dùng Expanded
            // (co giãn) thay vì SizedBox(height: 96) cố định — dù aspect ratio có tính
            // thiếu ở màn hình lạ nào đó, Text vẫn LUÔN được đảm bảo đủ chỗ, không bao giờ
            // còn tràn đáy nữa (hai lớp phòng thủ thay vì chỉ dựa vào một con số aspect ratio).
            childAspectRatio: 0.78,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, i) => tiles[i],
        );

    Widget buildSectionHeader(_AvatarCategoryGroup g) => Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 4),
          child: Row(
            children: [
              Icon(g.icon, size: 15, color: tkGreen),
              const SizedBox(width: 6),
              Text(g.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87, letterSpacing: 0.3)),
            ],
          ),
        );

    final List<Widget> content;
    if (_selectedGroup == null) {
      // "Tất cả" -> mỗi Nhóm 1 tiêu đề + lưới riêng, cuộn liền mạch; "Mặc định" đứng đầu vì
      // không thuộc Nhóm kỹ thuật nào.
      content = [
        buildGrid([
          _AvatarPickerTile(
            label: 'Mặc định',
            selected: widget.currentId == null,
            isDark: isDark,
            preview: Icon(Icons.widgets_outlined, size: 40, color: isDark ? Colors.white54 : Colors.black45),
            onTap: () => widget.onSelect(null),
          ),
        ]),
        for (final g in _avatarCategoryGroups)
          if (avatarLibrary.any((d) => g.categoryIds.contains(d.category))) ...[
            const SizedBox(height: 18),
            buildSectionHeader(g),
            buildGrid([for (final d in avatarLibrary) if (g.categoryIds.contains(d.category)) buildTile(d)]),
          ],
      ];
    } else {
      final g = _selectedGroup!;
      content = [
        buildGrid([for (final d in avatarLibrary) if (g.categoryIds.contains(d.category)) buildTile(d)]),
      ];
    }

    return ConstrainedBox(
      // [FIX — CHẶN NỞ VÔ HẠN TRÊN PC] Chặn thêm một lớp ở ĐÚNG nội dung Dialog (không chỉ ở
      // tham số maxWidth của showAppDialog phía trên) — phòng trường hợp sau này có nơi gọi khác
      // dựng lại widget này mà quên áp maxWidth ở lớp ngoài.
      constraints: const BoxConstraints(maxWidth: 800, maxHeight: double.infinity),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thay đổi giao diện (Avatar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Chỉ đổi HÌNH DÁNG hiển thị — không đổi chức năng/dữ liệu thiết bị.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 10),
            // [GIAI ĐOẠN 126] Chip lọc theo Nhóm — cuộn ngang, "Tất cả" luôn đứng đầu. Chọn 1 Nhóm
            // thu gọn lưới về ĐÚNG Nhóm đó (không còn tiêu đề, đỡ trùng lặp thông tin với chip).
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _AvatarGroupChip(label: 'Tất cả', icon: Icons.apps_rounded, selected: _selectedGroup == null, isDark: isDark, onTap: () => setState(() => _selectedGroup = null)),
                  for (final g in _avatarCategoryGroups)
                    if (avatarLibrary.any((d) => g.categoryIds.contains(d.category)))
                      _AvatarGroupChip(label: g.label, icon: g.icon, selected: _selectedGroup == g, isDark: isDark, onTap: () => setState(() => _selectedGroup = g)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: content),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// [GIAI ĐOẠN 126] Chip lọc Nhóm avatar — cùng tinh thần thị giác với _AvatarPickerTile (viền
// tkGreen khi được chọn), nhưng dạng nang thuốc ngang cho hàng cuộn phía trên lưới.
class _AvatarGroupChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _AvatarGroupChip({required this.label, required this.icon, required this.selected, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const Color tkGreen = Color(0xFF00A651);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected ? tkGreen.withValues(alpha: 0.15) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
            border: Border.all(color: selected ? tkGreen : Colors.transparent, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? tkGreen : (isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11.5, fontWeight: selected ? FontWeight.bold : FontWeight.w500, color: selected ? tkGreen : (isDark ? Colors.white70 : Colors.black87))),
            ],
          ),
        ),
      ),
    );
  }
}

// [BƯỚC 5 — DEVICE AVATAR BLUEPRINT] Ô chọn trong popup "Thay đổi giao diện (Avatar)" —
// preview + nhãn + viền nổi bật khi đang được chọn.
class _AvatarPickerTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final Widget preview;
  final VoidCallback onTap;

  const _AvatarPickerTile({required this.label, required this.selected, required this.isDark, required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const Color tkGreen = Color(0xFF00A651);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // [FIX #1] KHÔNG còn width cố định — GridView.count(crossAxisCount: 3) ở nơi gọi giờ tự
        // ép cỡ ô theo cột, Container này chỉ cần lấp đầy ô được cấp.
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          border: Border.all(color: selected ? tkGreen : Colors.transparent, width: 2),
        ),
        // [FIX BOTTOM OVERFLOW] Cột này TRƯỚC ĐÂY đòi CỐ ĐỊNH 96px cho preview + 6px + chiều cao
        // Text — nếu ô lưới thật (do childAspectRatio quyết định) cấp ÍT hơn tổng đó dù chỉ 1-2px
        // là tràn đáy ngay (đúng lỗi 1.8px đã báo). Đổi preview sang Expanded: LUÔN co giãn vừa
        // đúng phần không gian CÒN LẠI sau khi nhãn tên đã chiếm chỗ — Text không bao giờ bị đẩy
        // tràn ra ngoài nữa, bất kể ô lưới cao/thấp thế nào (không còn phụ thuộc một con số cứng).
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: Center(child: preview)),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? tkGreen : (isDark ? Colors.white70 : Colors.black87)),
            ),
          ],
        ),
      ),
    );
  }
}

// [GIAI ĐOẠN 72 — IN-PLACE REORDER] _JiggleTile — bọc rung-lắc kiểu "iOS Jiggle Mode" cho từng
// ô trong lưới edit-mode. Mỗi ô tự có AnimationController riêng (SingleTickerProviderStateMixin)
// + góc lệch pha ngẫu nhiên (+1/-1) để các ô rung LỆCH nhịp nhau (giống thật), không đồng loạt
// rung cùng lúc như 1 khối cứng.
class _JiggleTile extends StatefulWidget {
  final Widget child;
  const _JiggleTile({super.key, required this.child});

  @override
  State<_JiggleTile> createState() => _JiggleTileState();
}

class _JiggleTileState extends State<_JiggleTile> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final double _phaseSign;

  @override
  void initState() {
    super.initState();
    _phaseSign = Random().nextBool() ? 1.0 : -1.0;
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: 140 + Random().nextInt(60)))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Transform.rotate(angle: _phaseSign * 0.03 * _ctrl.value, child: child),
      child: widget.child,
    );
  }
}

// ============================================================================
// 🕳️ [GIAI ĐOẠN 113 — Ô LƯỚI TUYỆT ĐỐI + KHOẢNG TRỐNG] Ô TRỐNG trong chế độ Sửa
// ============================================================================
/// Ô vuông viền ĐỨT NÉT (không dùng package ngoài — CustomPainter tự vẽ) báo hiệu "khoảng trống
/// người dùng cố ý để lại" — kéo được như thẻ thật (ReorderableWrap không phân biệt), kèm nút "x"
/// nhỏ để XOÁ hẳn ô này (đóng khoảng trống lại). KHÔNG bọc _JiggleTile (rung lắc) — ô trống không
/// có "nội dung" cần rung để báo hiệu kéo được, giữ tĩnh cho dễ nhìn giữa các thẻ đang rung.
class _EmptySlotEditTile extends StatelessWidget {
  final double size;
  final VoidCallback onDelete;
  const _EmptySlotEditTile({required this.size, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color lineColor = isDark ? Colors.white38 : Colors.black38;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _DashedBorderPainter(color: lineColor, radius: 14)),
          ),
          const Center(child: Icon(Icons.crop_free_rounded, size: 20, color: Colors.grey)),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.85), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final Path path = Path()..addRRect(rrect);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const double dashLen = 6, gapLen = 4;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = (distance + dashLen).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
