import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:ui';
import 'dart:io' show Platform, Process; 
import 'dart:async';
import 'dart:convert'; 
import 'package:http/http.dart' as http; 
import '../../services/auth_service.dart';

// ============================================================================
// WIDGET HỖ TRỢ: KÍNH MỜ CHO POPUP
// ============================================================================
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;
  final VoidCallback? onTap;

  const GlassCard({super.key, required this.child, this.padding, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: padding ?? const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15), width: 1.5),
                boxShadow: [
                  if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4))
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// POPUP CHÍNH: THÊM THIẾT BỊ (ĐÃ CHUẨN HÓA DANH XƯNG TOÀN CỤC)
// ============================================================================
class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key});

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final MobileScannerController _cameraController = MobileScannerController();
  final TextEditingController _macController = TextEditingController();
  final AuthService _authService = AuthService();
  
  final Color tkGreen = const Color(0xFF00A651);

  // 0: Menu, 1: Quét QR, 2: Nhập tay, 3: Chế độ AP Tự động
  int _currentView = 0; 
  bool _isProcessing = false;
  
  // Vòng lặp quét tìm thiết bị phát Wi-Fi AP ngầm
  Timer? _apDetectionTimer;
  String _apStatusMessage = "Đang chờ bạn kết nối vào Wi-Fi của thiết bị...";

  @override
  void dispose() {
    _cameraController.dispose();
    _macController.dispose();
    _stopAPDetection();
    super.dispose();
  }

  // --- HÀM ĐIỀU HƯỚNG MỞ CÀI ĐẶT WI-FI HỆ THỐNG ---
  void _openWifiSettings() async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', 'ms-settings:network-wifi']);
      } else if (Platform.isAndroid || Platform.isIOS) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng mở mục Cài đặt Wi-Fi trên điện thoại của bạn.'))
        );
      }
    } catch (e) {
      print("Lỗi mở cài đặt mạng: $e");
    }
  }

  // --- VÒNG LẶP PING TỰ ĐỘNG PHÁT HIỆN THIẾT BỊ QUA GATEWAY AP (192.168.4.1) ---
  void _startAPDetection() {
    _stopAPDetection();
    setState(() {
      _apStatusMessage = "Đang quét ngầm hệ thống để tìm kiếm thiết bị...";
    });

    _apDetectionTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isProcessing) return;
      try {
        final response = await http.get(Uri.parse('http://192.168.4.1/info')).timeout(const Duration(seconds: 1));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String? hubMac = data['mac'] ?? data['mac_address'];
          
          if (hubMac != null && hubMac.isNotEmpty) {
            _stopAPDetection();
            setState(() {
              _apStatusMessage = "Đã tìm thấy thiết bị! Đang tự động tiến hành liên kết Cloud...";
            });
            _processLinkDevice(hubMac);
          }
        }
      } catch (_) {
        // Bỏ qua lỗi kết nối khi chưa cấu hình Wi-Fi xong
      }
    });
  }

  void _stopAPDetection() {
    _apDetectionTimer?.cancel();
    _apDetectionTimer = null;
  }

  // --- [ĐÃ SỬA LỖI ĐỒNG BỘ BACKEND] HÀM XỬ LÝ GỬI MÃ ĐỊA CHỈ THIẾT BỊ LÊN SERVER CLOUD ---
  Future<void> _processLinkDevice(String rawMac) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    String cleanMac = rawMac.replaceAll('MAC:', '').replaceAll('SN:', '').replaceAll(':', '').trim();

    if (cleanMac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mã định danh thiết bị không hợp lệ!'), backgroundColor: Colors.redAccent));
      setState(() => _isProcessing = false);
      return;
    }

    if (_currentView == 1) _cameraController.stop();

    // Gọi API Backend (Hàm này đã được nâng cấp trên Server Go để tự tạo bộ nhớ đệm nếu thiết bị mới tinh)
    String? error = await _authService.linkHub(cleanMac);
    
    if (!mounted) return;

    if (error == null) {
      // Thành công: Thông báo màu xanh lá và đóng hộp thoại, trả về kết quả true để Dashboard load lại dữ liệu
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Liên kết thiết bị $cleanMac thành công!'), backgroundColor: tkGreen)
      );
      Navigator.pop(context, true); 
    } else {
      // Thất bại: Hiển thị lỗi đỏ
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
      if (_currentView == 1) _cameraController.start();
      setState(() => _isProcessing = false);
      if (_currentView == 3) _startAPDetection(); 
    }
  }

  // --- WIDGET HEADER (Tiêu đề Popup gọn gàng) ---
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

  // --- VIEW 0: MENU LỰA CHỌN PHƯƠNG THỨC ---
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
              _startAPDetection();
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

  // --- VIEW 3: LUỒNG AP MODE TỰ ĐỘNG HOÀN TOÀN ---
  Widget _buildAPModeView(bool isDark, Color textMain, Color textSub) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader('Kết nối Wi-Fi AP Tự động', textMain, textSub),
          const SizedBox(height: 20),
          
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? Colors.black12 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200)
            ),
            child: Column(
              children: [
                if (!_isProcessing)
                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.orange))
                else
                  Icon(Icons.cloud_upload_rounded, color: tkGreen, size: 32),
                const SizedBox(height: 16),
                Text(
                  _apStatusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: tkGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              onPressed: _openWifiSettings,
              icon: const Icon(Icons.wifi_rounded, color: Colors.white, size: 20),
              label: const Text('BƯỚC 1: MỞ CÀI ĐẶT WI-FI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Sau khi nhấn, hãy kết nối vào Wi-Fi do thiết bị phát ra (Ví dụ: TK_DEVICE_...). Hệ thống sẽ tự động bắt tay và cấu hình Cloud ngay lập tức.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textSub, fontSize: 11, height: 1.4),
          )
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
                          : _buildAPModeView(isDark, textMain, textSub),
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