import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:io' show Platform, Process;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:app_settings/app_settings.dart'; // Thư viện mở WiFi Settings
import '../../widgets/glass_container.dart';

// ============================================================================
// POPUP CHÍNH: THÊM THIẾT BỊ
// ============================================================================
class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> with SingleTickerProviderStateMixin {
  final MobileScannerController _cameraController = MobileScannerController();
  final TextEditingController _macController = TextEditingController();
  
  final Color tkGreen = const Color(0xFF00A651);

  // 0: Menu, 1: Quét QR, 2: Nhập tay, 3: Chế độ AP Tự động
  int _currentView = 0; 
  bool _isProcessing = false;
  
  // Trạng thái cho luồng quét AP Mode
  Timer? _apDetectionTimer;
  late AnimationController _pulseController;
  bool isConnectedToHub = false;

  @override
  void initState() {
    super.initState();
    // Tạo hiệu ứng sóng Radar chớp tắt
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _macController.dispose();
    _stopAPDetection();
    _pulseController.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mã định danh thiết bị không hợp lệ!'), backgroundColor: Colors.redAccent));
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
  Widget _buildSelectionMenu(bool isDark, Color textMain, Color textSub) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader('Thêm thiết bị mới', textMain, textSub),
          const SizedBox(height: 16),
          Text('Chọn một phương thức cấu hình thuận tiện nhất để liên kết thiết bị thông minh vào hệ thống.', style: TextStyle(color: textSub, fontSize: 13, height: 1.4)),
          const SizedBox(height: 20),

          // 1. Quét QR
          GlassCard(
            padding: const EdgeInsets.all(12),
            onTap: () {
              setState(() => _currentView = 1);
              _cameraController.start();
            },
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.qr_code_scanner_rounded, color: tkGreen, size: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quét mã QR Code', style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('Tự động nhận diện nhanh qua camera', style: TextStyle(color: textSub, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 2. Chế độ Wi-Fi AP Tự động 
          GlassCard(
            padding: const EdgeInsets.all(12),
            onTap: () {
              setState(() => _currentView = 3);
              _startAPDetection(); // Gọi hàm quét ngầm và phát radar
            },
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.wifi_tethering_rounded, color: Colors.orange, size: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kết nối Wi-Fi (AP Mode tự động)', style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('Bắt mạng của thiết bị để cấu hình tự động', style: TextStyle(color: textSub, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3. Nhập tay
          GlassCard(
            padding: const EdgeInsets.all(12),
            onTap: () => setState(() => _currentView = 2),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.keyboard_alt_outlined, color: Colors.blue, size: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nhập thủ công (SN/MAC)', style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('Điền thông tin sê-ri mã phía sau vỏ máy', style: TextStyle(color: textSub, fontSize: 11)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: textSub, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- VIEW 1: CAMERA SCANNER ---
  Widget _buildScannerView(Color textMain, Color textSub) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: _buildHeader('Quét mã QR thiết bị', textMain, textSub),
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
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Đưa mã QR trên tem thiết bị vào trung tâm camera', style: TextStyle(color: Colors.grey, fontSize: 12)),
        )
      ],
    );
  }

  // --- VIEW 2: NHẬP THỦ CÔNG ---
  Widget _buildManualEntryView(bool isDark, Color textMain, Color textSub) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader('Nhập thủ công mã MAC', textMain, textSub),
          const SizedBox(height: 20),
          TextField(
            controller: _macController,
            style: TextStyle(color: textMain, fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.bold),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'Mã MAC hoặc SN của thiết bị',
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
                  : const Text('XÁC NHẬN KẾT NỐI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  // --- VIEW 3: LUỒNG AP MODE TỰ ĐỘNG ---
  Widget _buildAPModeView(bool isDark, Color textMain, Color textSub) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader('Kết nối Wi-Fi AP Tự động', textMain, textSub),
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
            isConnectedToHub ? 'Đã kết nối với Smart Hub!' : 'Đang tìm kiếm mạng thiết bị...',
            style: TextStyle(color: isConnectedToHub ? tkGreen : textMain, fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            isConnectedToHub 
              ? 'Chuẩn bị mở màn hình Cài đặt kết nối...' 
              : 'Vui lòng nhấn nút bên dưới để mở cài đặt Wi-Fi. Kết nối với mạng có tên "Smart_Hub_..." sau đó quay lại App.',
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
                label: const Text('MỞ CÀI ĐẶT WI-FI ĐIỆN THOẠI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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

    return Dialog(
      backgroundColor: Colors.transparent, 
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlassCard(
          padding: EdgeInsets.zero, 
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _currentView == 0 
                  ? _buildSelectionMenu(isDark, textMain, textSub)
                  : _currentView == 1 
                      ? _buildScannerView(textMain, textSub)
                      : _currentView == 2
                          ? _buildManualEntryView(isDark, textMain, textSub)
                          : _buildAPModeView(isDark, textMain, textSub), // Render View 3
            ),
          ),
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