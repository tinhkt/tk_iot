import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io' show Platform, Process;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:app_settings/app_settings.dart'; // Thư viện mở WiFi Settings
import 'package:permission_handler/permission_handler.dart'; // Xin quyền Camera trước khi quét QR
import '../../services/lan_discovery_service.dart'; // Quét thiết bị LAN qua UDP Broadcast
import '../../localization/app_translations.dart';

// ============================================================================
// POPUP CHÍNH: THÊM THIẾT BỊ
// ============================================================================
class AddDeviceDialog extends StatefulWidget {
  /// [LAN SCAN] "Sổ hộ khẩu" — tập MAC đã sở hữu (đã chuẩn hóa HOA + bỏ ":") do màn hình
  /// chính truyền vào, dùng để ẩn nút "Thêm ngay" cho thiết bị đã có trong hệ thống.
  final Set<String> ownedMacs;
  const AddDeviceDialog({super.key, this.ownedMacs = const {}});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> with SingleTickerProviderStateMixin {
  final MobileScannerController _cameraController = MobileScannerController();
  final TextEditingController _macController = TextEditingController();
  
  final Color tkGreen = const Color(0xFF00A651);

  // 0: Menu, 1: Quét QR, 2: Nhập tay, 3: Chế độ AP Tự động, 4: Quét mạng LAN
  int _currentView = 0;
  bool _isProcessing = false;

  // Trạng thái cho luồng quét AP Mode
  Timer? _apDetectionTimer;
  late AnimationController _pulseController;
  bool isConnectedToHub = false;

  // --- Trạng thái cho luồng QUÉT MẠNG LAN (dùng LanDiscoveryService) ---
  final LanDiscoveryService _lanService = LanDiscoveryService();
  StreamSubscription<List<LanDevice>>? _lanSub;
  List<LanDevice> _lanDevices = [];
  bool _isScanning = false;

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
    super.dispose();
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
          // Bắt được mạch ESP32!
          _stopAPDetection();
          if (mounted) {
            setState(() {
              isConnectedToHub = true;
            });
            _pulseController.stop();
            
            // Đợi 1.5s cho người dùng nhìn thấy dấu Check Xanh rồi chuyển bước
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) {
                // Tạm thời trả về "true" (Thành công). 
                // Bác có thể thay dòng pop này bằng Navigator.push sang một màn hình WebView 
                // trỏ tới "http://192.168.4.1" để cấu hình WiFi nhà nhé.
                Navigator.pop(context, true); 
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
              onTap: () {
                setState(() => _currentView = 3);
                _startAPDetection(); // Gọi hàm quét ngầm và phát radar
              },
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
                              : _buildLanScanView(isDark, textMain, textSub, t), // View 4: Quét LAN
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