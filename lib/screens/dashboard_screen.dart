import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui'; 
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:window_manager/window_manager.dart'; 
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http; 

import '../providers/device_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';
import 'admin/role_management_view.dart';
import 'devices/add_device_dialog.dart';
import 'admin/profile_management_view.dart';
import '../providers/notification_provider.dart';
import 'home/home_management_screen.dart';
import '../widgets/glass_container.dart';
import 'dart:async';

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
  int _selectedIndex = 0, _cameraViewMode = 1; 
  bool _isLoadingDevices = true; 
  bool _isPushEnabled = true;
  Map<String, dynamic> _weatherData = {'temp': '--', 'condition': 'Đang tải...'};
  Timer? _debounceSync;
  bool _isSelectionMode = false;
  Set<String> _selectedDevices = {}; 
  Set<String> _hiddenDevices = {}; // Chứa ID (MAC_Endpoint) của các công tắc bị ẩn
  bool _showHiddenFilter = false; // Bật cờ này lên để xem các thiết bị đang bị ẩn
  List<dynamic> _currentHomeDevices = [], _allHomesForSuperUser = [];
  Map<String, dynamic>? _selectedHomeForSuperUser; 
  final Color tkGreen = const Color(0xFF00A651); 

  @override
  void initState() { super.initState(); _initializeHome(); _fetchWeather(); WidgetsBinding.instance.addPostFrameCallback((_) { Provider.of<NotificationProvider>(context, listen: false).initMQTTListener(userEmail); _setupRealtimeSync();}); }

  @override
  void dispose() { _debounceSync?.cancel(); super.dispose(); }

  Future<void> _handleRefresh() async { await _initializeHome(isSilent: false); await Future.delayed(const Duration(milliseconds: 500)); }

  Future<void> _initializeHome({bool isSilent = false}) async {
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
          setState(() { currentHomeId = homeId; userEmail = email; userRole = role; });

          if (role == 'SUPER_USER') {
            final resHomes = await http.get(Uri.parse('$baseUrl/homes'), headers: {'Authorization': 'Bearer $token'});
            if (resHomes.statusCode == 200) {
              List<dynamic> homes = jsonDecode(resHomes.body);
              // Gọi API lấy thiết bị của tất cả các nhà SONG SONG thay vì chờ tuần tự từng nhà
              await Future.wait(homes.map((home) async {
                final hId = home['home_id'];
                final dRes = await http.get(Uri.parse('$baseUrl/homes/${Uri.encodeComponent(hId.toString())}/devices'), headers: {'Authorization': 'Bearer $token'});
                if (dRes.statusCode == 200) {
                  List<dynamic> devs = jsonDecode(dRes.body);
                  int onCount = 0, offCount = 0, totalEndpoints = 0;
                  
                  for (var d in devs) {
                    var rawState = d['state'] ?? d['state_data'] ?? d['properties'] ?? {}; 
                    Map<String, dynamic> stateMap = rawState is String ? (jsonDecode(rawState) ?? {}) : Map<String, dynamic>.from(rawState ?? {});
                    bool hasEp = false;

                    // HÀM ĐỆ QUY CẬP NHẬT TÍNH TOÁN (LỌC BỎ IP, MAC, WIFI...)
                    void countRecursive(String key, dynamic val) {
                      final kLow = key.toLowerCase();
                      final ignored = ['ip', 'mac', 'rssi', 'signal', 'wifi', 'serial', 'version', 'fw', 'firmware', 'update', 'reset', 'restart', 'online', 'timestamp', 'time', 'led', 'config', 'status', 'ping'];
                      for (var ig in ignored) { if (kLow == ig || kLow.contains(ig)) return; } // Gặp rác là bỏ qua ngay

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
                      if (s == 'ON' || s == 'TRUE' || s == '1') {
                        hasEp = true; totalEndpoints++; onCount++;
                      } else if (s == 'OFF' || s == 'FALSE' || s == '0') {
                        hasEp = true; totalEndpoints++; offCount++;
                      }
                    }

                    if (stateMap.isNotEmpty) stateMap.forEach((k, v) => countRecursive(k, v));
                    if (!hasEp) { totalEndpoints++; offCount++; }
                  }
                  
                  home['on_count'] = onCount; home['off_count'] = offCount; home['total_endpoints'] = totalEndpoints; home['raw_devices'] = devs;
                }
              }));
              if (mounted) setState(() => _allHomesForSuperUser = homes);
            }
            if (_selectedHomeForSuperUser != null) { await _fetchDevicesForHome(_selectedHomeForSuperUser!['home_id'], token); }
          } else {
            if (homeId.isNotEmpty) { await _fetchDevicesForHome(homeId, token); }
          }
          if (mounted) { Provider.of<NotificationProvider>(context, listen: false).fetchHistory(); }
        }
      } catch (e) { if (kDebugMode) print("Lỗi giải mã token: $e"); }
    }
    if (mounted && !isSilent) setState(() => _isLoadingDevices = false);
  }

  Future<void> _fetchDevicesForHome(String homeId, String token) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}/devices'), headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        List<dynamic> devices = jsonDecode(response.body);
        
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

           // THUẬT TOÁN ÉP PHẲNG JSON ĐỂ ĐẾM SỐ NÚT KHÔNG BAO GIỜ SÓT
           Map<String, dynamic> flatMap = {};
           void flatten(Map m) {
             m.forEach((k, v) { if (v is Map) flatten(v); else flatMap[k] = v; });
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
                 if (['ON', 'TRUE', '1'].contains(s)) onCount++; else offCount++;
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

  // --- HÀM GỌI API XÓA THIẾT BỊ ---
  Future<void> _deleteDevice(String mac) async {
    try {
      final token = await AuthService().getToken();
      
      // LƯU Ý: Giả định endpoint xóa thiết bị của backend Golang là: DELETE /api/devices/:mac
      // Nếu route backend của bác là kiểu khác (VD: /api/homes/$currentHomeId/devices/$mac), bác sửa lại URL dưới đây nhé.
      final response = await http.delete(
        Uri.parse('$baseUrl/devices/${Uri.encodeComponent(mac)}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa thiết bị thành công!'), backgroundColor: Color(0xFF00A651)),
        );
        // Xóa xong thì bắt buộc phải gọi làm mới danh sách
        _handleRefresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa thiết bị trên Server: Mã ${response.statusCode}'), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể kết nối đến máy chủ!'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _setupRealtimeSync() {
    final provider = Provider.of<DeviceProvider>(context, listen: false);

    // Kích hoạt (lại) kết nối MQTT bằng credentials động của user vừa đăng nhập
    provider.connectMqtt();

    provider.setGlobalMqttListener((topic, message) {
      if (!mounted) return;
      
      if (_debounceSync?.isActive ?? false) _debounceSync!.cancel();
      
      _debounceSync = Timer(const Duration(milliseconds: 800), () {
         if (mounted) {
           _initializeHome(isSilent: true); 
         }
      });
    });
  }

  Future<void> _fetchWeather() async {
    try {
      final token = await AuthService().getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/weather/current'), 
        headers: {'Authorization': 'Bearer $token'},
      );

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
            };
          });
        }
      }
    } catch (e) {
      if (kDebugMode) print("☁️ Lỗi API thời tiết: $e");
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
    bool confirm = await showDialog(
      context: context, barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, elevation: 0, insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassContainer(
            padding: const EdgeInsets.all(32),
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
        ),
      ),
    ) ?? false;
    if (confirm) { await AuthService().logout(); if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false); }
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController(), newPassCtrl = TextEditingController(), confirmPassCtrl = TextEditingController();
    bool isDialogLoading = false;
    showDialog(
      context: context, barrierDismissible: false, barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A), textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent, elevation: 0, insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassContainer(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [Icon(Icons.lock_reset_rounded, color: tkGreen, size: 28), const SizedBox(width: 12), Text('Đổi mật khẩu', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold))]), const SizedBox(height: 24),
                      TextField(controller: oldPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu hiện tại', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))), const SizedBox(height: 16),
                      TextField(controller: newPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))), const SizedBox(height: 16),
                      TextField(controller: confirmPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Xác nhận mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))), const SizedBox(height: 32),
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
                ),
              ),
            );
          },
        );
      }
    );
  }

  void _openProfileOrSettings(int tabIndex) {
    if (MediaQuery.of(context).size.width < 900) { setState(() => _selectedIndex = 4); } else { _showSettingsMenu(initialTab: tabIndex); }
  }

  Widget _buildUserAvatarMenu(Color textMain) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<int>(
      offset: const Offset(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: isDark ? const Color(0xFF1E293B) : Colors.white, tooltip: 'Tài khoản của tôi',
      child: const CircleAvatar(radius: 20, backgroundColor: Color(0xFF00A651), child: Icon(Icons.person, color: Colors.white)),
      onSelected: (value) { switch (value) { case 0: _openProfileOrSettings(0); break; case 1: _openProfileOrSettings(2); break; case 2: _onMenuTapped(6); break; case 3: _performLogout(context); break; } },
      itemBuilder: (context) => [
        PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.account_circle_outlined, color: textMain), const SizedBox(width: 12), Text('Hồ sơ tài khoản', style: TextStyle(color: textMain))])),
        PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.lock_reset, color: textMain), const SizedBox(width: 12), Text('Đổi mật khẩu', style: TextStyle(color: textMain))])),
        PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.security, color: textMain), const SizedBox(width: 12), Text('Quản lý phân quyền', style: TextStyle(color: textMain))])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.logout, color: Colors.redAccent), SizedBox(width: 12), Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])),
      ],
    );
  }

  void _showSettingsMenu({int initialTab = 0}) { showDialog(context: context, barrierDismissible: true, barrierColor: Colors.black.withValues(alpha: 0.5), builder: (context) => WindowsSettingsDialog(currentRole: userRole, currentEmail: userEmail, initialTab: initialTab)); }

  void _showThemeDialog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color surface = isDark ? const Color(0xFF1E293B) : Colors.white, textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    showModalBottomSheet(
      context: context, backgroundColor: surface, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Giao diện', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tkGreen)), IconButton(icon: Icon(Icons.close, color: textMain), onPressed: () => Navigator.pop(context))]),
              const SizedBox(height: 8),
              RadioListTile<ThemeMode>(title: Text('Chế độ Sáng', style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: ThemeMode.light, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
              RadioListTile<ThemeMode>(title: Text('Chế độ Tối', style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: ThemeMode.dark, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
              RadioListTile<ThemeMode>(title: Text('Tự động theo thiết bị', style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), subtitle: const Text('Đổi màu theo ban ngày/ban đêm'), value: ThemeMode.system, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
            ],
          ),
        );
      }
    );
  }

  void _onMenuTapped(int index, {bool isFromDrawer = false}) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);

    if (isFromDrawer && isMobile) Navigator.pop(context); 

    if (index == 5 && isMobile) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text('Quản lý hệ sinh thái'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: SafeArea(child: HomeManagementScreen(userRole: userRole))))).then((value) => _initializeHome());
      return; 
    }

    if (index == 6 && isMobile) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text('Phân quyền'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: const SafeArea(child: RoleManagementView()))));
      return; 
    }

    if (index == 4 && !isMobile) { _showSettingsMenu(initialTab: 0); } else { setState(() => _selectedIndex = index); }
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
                  child: GlassContainer(
                    padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(16),
                    child: Consumer<NotificationProvider>( 
                      builder: (context, notifProvider, child) {
                        final listNotif = notifProvider.list;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Thông báo hệ thống', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text('Tổng số: ${listNotif.length}', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Nhận thông báo đẩy (Push)', style: TextStyle(color: textMain, fontSize: 13)),
                                  Switch(
                                    value: _isPushEnabled, activeThumbColor: tkGreen,
                                    onChanged: (val) { setState(() => _isPushEnabled = val); setDialogState(() => _isPushEnabled = val); },
                                  )
                                ]
                              )
                            ),
                            Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                            if (listNotif.isEmpty)
                              Padding(padding: const EdgeInsets.all(32.0), child: Center(child: Text('Không có thông báo nào gần đây.', style: TextStyle(color: textSub, fontSize: 13))))
                            else
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 400),
                                child: ListView.separated(
                                  shrinkWrap: true, physics: const BouncingScrollPhysics(), itemCount: listNotif.length,
                                  separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: isDark ? Colors.white10 : Colors.grey.shade100),
                                  itemBuilder: (context, index) {
                                    final notif = listNotif[index];
                                    IconData icon = Icons.info_outline_rounded;
                                    if (notif.type == 'ALERT') {
                                      icon = Icons.warning_amber_rounded;
                                    } else if (notif.type == 'SYSTEM') icon = Icons.system_security_update_good_rounded; else if (notif.type == 'DEVICE') icon = Icons.power_off_outlined;
                                    Color notifColor = Color(int.parse(notif.color));
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), hoverColor: isDark ? Colors.white10 : Colors.grey.shade50,
                                      leading: CircleAvatar(backgroundColor: notifColor.withValues(alpha: 0.12), child: Icon(icon, color: notifColor, size: 20)),
                                      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(notif.title, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)), Text(notif.time, style: TextStyle(color: textSub, fontSize: 11))]),
                                      subtitle: Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(notif.message, style: TextStyle(color: textSub, height: 1.4, fontSize: 13))),
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

  Widget _buildNotificationBell(Color textMain, Color textSub) {
    return Consumer<NotificationProvider>(
      builder: (context, notifProvider, child) {
        int count = notifProvider.list.length; 
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(icon: Icon(Icons.notifications_none_rounded, color: textMain), onPressed: () => _showNotificationPanel(textMain, textSub)),
            if (notifProvider.hasNewNotification || count > 0) 
              Positioned(
                top: 8, right: 8, 
                child: Container(
                  padding: const EdgeInsets.all(5), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  child: Text(count > 9 ? '9+' : '$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, height: 1))
                )
              )
          ],
        );
      },
    );
  }

  Widget _buildFullNotificationView(bool isDark, Color textMain, Color textSub) {
    return GlassContainer(
      padding: const EdgeInsets.all(0),
      child: Consumer<NotificationProvider>(
        builder: (context, notifProvider, child) {
          final listNotif = notifProvider.list;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('Tất cả thông báo', style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Đẩy (Push)', style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.w600)),
                        Switch(value: _isPushEnabled, activeThumbColor: tkGreen, onChanged: (val) => setState(() => _isPushEnabled = val)),
                      ],
                    )
                  ],
                ),
              ),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
              Expanded(
                child: listNotif.isEmpty
                    ? Center(child: Text('Không có thông báo nào.', style: TextStyle(color: textSub)))
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(16), itemCount: listNotif.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: isDark ? Colors.white10 : Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final notif = listNotif[index];
                          IconData icon = Icons.info_outline_rounded;
                          if (notif.type == 'ALERT') {
                            icon = Icons.warning_amber_rounded;
                          } else if (notif.type == 'SYSTEM') icon = Icons.system_security_update_good_rounded; else if (notif.type == 'DEVICE') icon = Icons.power_off_outlined;
                          Color notifColor = Color(int.parse(notif.color));
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), leading: CircleAvatar(backgroundColor: notifColor.withValues(alpha: 0.12), child: Icon(icon, color: notifColor, size: 20)),
                            title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(notif.title, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)), Text(notif.time, style: TextStyle(color: textSub, fontSize: 11))]),
                            subtitle: Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(notif.message, style: TextStyle(color: textSub, height: 1.4, fontSize: 13))),
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
            Text('Đã chọn ${_selectedDevices.length}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00A651))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Đổi tên hàng loạt',
                  icon: const Icon(Icons.edit_rounded, color: Colors.blueAccent),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng đổi tên hàng loạt đang phát triển')));
                    setState(() { _isSelectionMode = false; _selectedDevices.clear(); });
                  }
                ),
                IconButton(
                  tooltip: 'Ẩn / Hiện hàng loạt',
                  icon: Icon(_showHiddenFilter ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.orange), 
                  onPressed: () {
                    setState(() { 
                      if (_showHiddenFilter) _hiddenDevices.removeAll(_selectedDevices); 
                      else _hiddenDevices.addAll(_selectedDevices); 
                      _isSelectionMode = false; _selectedDevices.clear(); 
                    });
                  }
                ),
                IconButton(
                  tooltip: 'Xóa hàng loạt',
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
    final Color bgLight = isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2); 
    final Color surfaceLight = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgLight,
      appBar: isMobile
          ? AppBar(
              backgroundColor: isDark ? surfaceLight : bgLight, elevation: 0, iconTheme: IconThemeData(color: tkGreen), 
              title: Text(_selectedIndex == 3 ? 'THÔNG BÁO' : _selectedIndex == 4 ? 'CÀI ĐẶT' : 'MY HOME', style: TextStyle(color: textMain, fontWeight: FontWeight.w900, letterSpacing: 1.2)), centerTitle: true, 
              actions: _selectedIndex == 4 ? [] : [
                IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded, color: textMain),
                  onPressed: () async {
                    // ĐÃ SỬA: Ép buộc làm mới ngay sau khi đóng Dialog
                    await showDialog(context: context, barrierColor: Colors.black.withValues(alpha: 0.6), builder: (context) => const AddDeviceDialog());
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
                    child: _selectedIndex == 6 ? const RoleManagementView()
                         : _selectedIndex == 3 ? Padding(padding: const EdgeInsets.all(16.0), child: _buildFullNotificationView(isDark, textMain, textSub))
                         : _selectedIndex == 5 ? HomeManagementScreen(userRole: userRole) 
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

      bottomNavigationBar: isMobile ? _buildBottomNav(surfaceLight, textSub) : null,
    );
  }

  Widget _buildMobileSettingsView(bool isDark, Color textMain, Color textSub) {
    Widget buildSettingGroup(List<Widget> children) => Padding(padding: const EdgeInsets.only(bottom: 24.0), child: GlassContainer(padding: EdgeInsets.zero, child: Column(children: children)));
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingGroup([
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(radius: 30, backgroundColor: tkGreen.withValues(alpha: 0.2), child: Icon(Icons.person, color: tkGreen, size: 32)),
              title: Text(userEmail, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 4.0), child: Text('Quyền: $userRole', style: TextStyle(color: textSub, fontWeight: FontWeight.w600))),
              trailing: PopupMenuButton<int>(
                icon: Icon(Icons.edit_outlined, color: textSub), offset: const Offset(0, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), color: isDark ? const Color(0xFF1E293B) : Colors.white,
                onSelected: (value) {
                  switch (value) {
                    case 0: Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text('Hồ sơ tài khoản'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: SafeArea(child: ProfileManagementView(currentRole: userRole, currentEmail: userEmail))))); break;
                    case 1: _showChangePasswordDialog(); break;
                    case 2: Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text('Phân quyền'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: const SafeArea(child: RoleManagementView())))); break;
                    case 3: _performLogout(context); break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.account_circle_outlined, color: textMain), const SizedBox(width: 12), Text('Hồ sơ tài khoản', style: TextStyle(color: textMain))])),
                  PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.lock_reset, color: textMain), const SizedBox(width: 12), Text('Đổi mật khẩu', style: TextStyle(color: textMain))])),
                  PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.security, color: textMain), const SizedBox(width: 12), Text('Quản lý phân quyền', style: TextStyle(color: textMain))])),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.logout, color: Colors.redAccent), const SizedBox(width: 12), Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])),
                ],
              ),
              onTap: () { Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(appBar: AppBar(title: const Text('Hồ sơ tài khoản'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0), backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2), body: SafeArea(child: ProfileManagementView(currentRole: userRole, currentEmail: userEmail))))); }
            ),
          ]),
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text('CHUNG', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          buildSettingGroup([ListTile(leading: Icon(Icons.palette_outlined, color: textMain), title: Text('Giao diện màu sắc', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Icon(Icons.chevron_right, color: textSub), onTap: () => _showThemeDialog())]),
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text('BẢO MẬT', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          buildSettingGroup([ListTile(leading: Icon(Icons.lock_outline, color: textMain), title: Text('Đổi mật khẩu', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Icon(Icons.chevron_right, color: textSub), onTap: () => _showChangePasswordDialog())]),
          Padding(padding: const EdgeInsets.only(left: 8.0, bottom: 8.0), child: Text('HỆ THỐNG', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
          buildSettingGroup([
            ListTile(leading: Icon(Icons.dns_outlined, color: textMain), title: Text('Máy chủ', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Text('Armbian OS', style: TextStyle(color: textSub))),
            Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.2)),
            ListTile(leading: Icon(Icons.info_outline, color: textMain), title: Text('Phiên bản phần mềm', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)), trailing: Text('3.0.1 (Stable)', style: TextStyle(color: textSub))),
          ]),
          buildSettingGroup([ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text('Đăng xuất khỏi thiết bị', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), onTap: () => _performLogout(context))]),
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
    return Container(
      width: 260, margin: const EdgeInsets.only(left: 24, bottom: 24, top: 16),
      child: GlassContainer(
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
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('TUAN KIET', style: TextStyle(color: tkGreen, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)), Text('CloudPlatform', style: TextStyle(color: txtSub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2))]),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildMenuItem(0, Icons.dashboard_rounded, 'Bảng điều khiển', txtMain, txtSub),
                  _buildMenuItem(5, Icons.maps_home_work_rounded, 'Quản lý Nhà', txtMain, txtSub), 
                  _buildMenuItem(1, Icons.meeting_room_rounded, 'Phòng ban', txtMain, txtSub),
                  _buildMenuItem(2, Icons.auto_awesome_rounded, 'Ngữ cảnh', txtMain, txtSub),
                  _buildMenuItem(3, Icons.notifications_active_rounded, 'Thông báo', txtMain, txtSub), 
                  _buildMenuItem(6, Icons.security_rounded, 'Phân quyền', txtMain, txtSub), 
                  _buildMenuItem(4, Icons.settings_rounded, 'Cài đặt', txtMain, txtSub),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer(bool isDark, Color surface, Color txtMain, Color txtSub) {
    return Container(
      width: 260, color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(top: 60, bottom: 24, left: 24),
            child: Row(
              children: [
                Icon(Icons.home_rounded, color: tkGreen, size: 36),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text('TUAN KIET', style: TextStyle(color: tkGreen, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)), Text('CloudPlatform', style: TextStyle(color: txtSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2))]),
              ],
            ),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                _buildMenuItem(0, Icons.dashboard_rounded, 'Điều khiển', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(5, Icons.maps_home_work_rounded, 'Quản lý Nhà', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(1, Icons.meeting_room_rounded, 'Phòng ban', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(2, Icons.auto_awesome_rounded, 'Ngữ cảnh', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(6, Icons.security_rounded, 'Phân quyền', txtMain, txtSub, isFromDrawer: true), 
                _buildMenuItem(4, Icons.settings_rounded, 'Cài đặt', txtMain, txtSub, isFromDrawer: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String title, Color txtMain, Color txtSub, {bool isFromDrawer = false}) {
    bool isSelected = _selectedIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: isSelected ? tkGreen.withValues(alpha: 0.15) : Colors.transparent, borderRadius: BorderRadius.circular(16), border: Border.all(color: isSelected ? tkGreen.withValues(alpha: 0.3) : Colors.transparent)),
      
      // SỬA LỖI CẢNH BÁO LIST TILE BẰNG THẺ MATERIAL NÀY
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(icon, color: isSelected ? tkGreen : txtSub, size: 22),
          title: Text(title, style: TextStyle(color: isSelected ? tkGreen : txtMain, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
          onTap: () => _onMenuTapped(index, isFromDrawer: isFromDrawer),
        ),
      ),
    );
  }

  Widget _buildBottomNav(Color surface, Color txtSub) {
    return BottomNavigationBar(
      backgroundColor: surface, selectedItemColor: tkGreen, unselectedItemColor: txtSub, type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex, onTap: (index) => _onMenuTapped(index), 
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Điều khiển'),
        BottomNavigationBarItem(icon: Icon(Icons.meeting_room_rounded), label: 'Phòng'),
        BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Ngữ cảnh'),
        BottomNavigationBarItem(icon: Icon(Icons.notifications_active_rounded), label: 'Thông báo'), 
        BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Cài đặt'),
      ],
    );
  }

  Widget _buildBentoDashboard(bool isDark, Color textMain, Color textSub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Text('Xin chào, ', style: TextStyle(color: textSub, fontSize: 16)), Text(userEmail.split('@')[0], style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold))]),
                Text('Tổng quan Hệ thống', style: TextStyle(color: textMain, fontSize: 28, fontWeight: FontWeight.w900)),
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
                child: GlassContainer(
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
                                  Expanded(child: Text('Tất cả thiết bị - ${_selectedHomeForSuperUser!['home_name']}', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                            )
                          else
                            Text('Tất cả thiết bị', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
                          
                          if (userRole != 'SUPER_USER' || _selectedHomeForSuperUser != null) 
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: tkGreen.withValues(alpha: 0.15), foregroundColor: tkGreen, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                              icon: const Icon(Icons.add, size: 20), label: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              onPressed: () async {
                                // ĐÃ SỬA: Bỏ if (result != null), ép buộc gọi _handleRefresh()
                                await showDialog(context: context, barrierColor: Colors.black.withValues(alpha: 0.6), builder: (context) => const AddDeviceDialog());
                                _handleRefresh();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: _buildDevicesGrid(isDark, textMain, textSub)),
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
                    // Gắn biến thời tiết thực tế và truyền itemWidth vào từng thẻ
                    _buildMiniStatusMobile(Icons.thermostat, 'Nhiệt độ', '${_weatherData['temp'] ?? '--'}°C', Colors.orange, textMain, textSub, itemWidth), 
                    const SizedBox(width: 12),
                    _buildMiniStatusMobile(Icons.water_drop, 'Độ ẩm', '${_weatherData['humidity'] ?? '--'}%', Colors.blue, textMain, textSub, itemWidth), 
                    const SizedBox(width: 12),
                    _buildMiniStatusMobile(Icons.bolt, 'Tiêu thụ', '2.1 kW', tkGreen, textMain, textSub, itemWidth), 
                    const SizedBox(width: 12),
                    _buildMiniStatusMobile(Icons.security, 'An ninh', 'BẬT', Colors.redAccent, textMain, textSub, itemWidth),
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
                Text('Tất cả thiết bị', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
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
    return GlassContainer(
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

  Widget _buildWeatherBento(bool isDark, Color txtMain, Color txtSub) {
  // Lấy dữ liệu từ Map, nếu chưa có thì hiển thị giá trị mặc định
  final String temp = _weatherData['temp']?.toString() ?? '--';
  final String condition = _weatherData['condition']?.toString() ?? 'Đang cập nhật...';

    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 70, 
            height: 70, 
            decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle), 
            child: Icon(Icons.cloud_queue_rounded, color: tkGreen, size: 36)
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              mainAxisAlignment: MainAxisAlignment.center, 
              children: [
                Text(
                  condition, // Hiển thị mây đen, nắng, mưa... từ API
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
    );
  }

  Widget _buildSensorsBento(bool isDark, Color txtMain, Color txtSub) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildMiniStatusDesktop(Icons.water_drop, 'Độ ẩm', '${_weatherData['humidity'] ?? '--'}%', Colors.blue, txtMain, txtSub), Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          _buildMiniStatusDesktop(Icons.bolt, 'Tiêu thụ', '2.1 kW', tkGreen, txtMain, txtSub), Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          _buildMiniStatusDesktop(Icons.security, 'An ninh', 'BẬT', Colors.redAccent, txtMain, txtSub),
        ],
      ),
    );
  }

  Widget _buildEnergyWidget(bool isDark, Color textMain, Color textSub) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [Icon(Icons.bolt_rounded, color: tkGreen, size: 22), const SizedBox(width: 8), Text('Điện năng', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))]),
              IconButton(icon: Icon(Icons.open_in_new_rounded, color: textSub, size: 20), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: () {})
            ],
          ),
          const SizedBox(height: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Hôm nay', style: TextStyle(color: textSub, fontSize: 13)), const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [Text('14.5', style: TextStyle(color: textMain, fontSize: 40, fontWeight: FontWeight.w900)), const SizedBox(width: 4), Text('kWh', style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 16), Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1), const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(child: Column(children: [Text('Đang tiêu thụ', style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), FittedBox(fit: BoxFit.scaleDown, child: Text('2,104 W', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)))])),
                  Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  Expanded(child: Column(children: [Text('Tháng này', style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), FittedBox(fit: BoxFit.scaleDown, child: Text('124 kWh', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)))])),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCameraWidget(bool isDark, Color textMain, Color textSub) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8,
            children: [
              Row(children: [const Icon(Icons.videocam_rounded, color: Colors.blueAccent, size: 22), const SizedBox(width: 8), Text('Camera', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))]),
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
            ? AspectRatio(aspectRatio: 16 / 9, child: Container(decoration: BoxDecoration(color: isDark ? Colors.black45 : Colors.grey.shade300, borderRadius: BorderRadius.circular(12)), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.videocam_off_rounded, color: textSub, size: 32), const SizedBox(height: 8), Text('Ngoại tuyến', style: TextStyle(color: textSub, fontSize: 12))]))))
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
  Widget _buildDevicesGrid(bool isDark, Color textMain, Color textSub) {
    if (_isLoadingDevices) return Center(child: Padding(padding: const EdgeInsets.all(40), child: CircularProgressIndicator(color: tkGreen)));

    final provider = Provider.of<DeviceProvider>(context, listen: false);

    // VIEW 1: SUPER USER (HIỂN THỊ THẺ NHÀ) - Giữ nguyên của bác
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
              
              return ClipRRect(
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
              );
            },
          );
        }
      );
    }

    // VIEW 2: TẤT CẢ THIẾT BỊ 
    if (_currentHomeDevices.isEmpty) return _buildEmptyState(isDark, textSub, "Khu vực này chưa kết nối với thiết bị/Hub nào.");

    List<Map<String, dynamic>> allFans = [];
    List<Map<String, dynamic>> allSwitches = [];

    // TỪ ĐIỂN DỊCH TÊN CHUẨN HASS
    String translateName(String key) {
      String k = key.toLowerCase();
      if (k == 'all') return 'Bật/Tắt Tất Cả';
      if (k.startsWith('relay')) return 'Relay ${k.replaceAll(RegExp(r'[^0-9]'), '')}';
      if (k.startsWith('power') && k != 'power') return 'Relay ${k.replaceAll(RegExp(r'[^0-9]'), '')}';
      if (k.startsWith('swa') || k.startsWith('s_')) return 'Công tắc ${k.replaceAll(RegExp(r'[^0-9]'), '')}';
      return 'Công tắc ${key.toUpperCase()}';
    }

    final ignoredKeys = ['ip', 'mac', 'rssi', 'signal', 'wifi', 'serial', 'version', 'fw', 'firmware', 'update', 'reset', 'restart', 'online', 'timestamp', 'time', 'led', 'config', 'status', 'ping', 'type', 'id'];

    // BÓC TÁCH THÔNG MINH
    for (var device in _currentHomeDevices) {
      String mac = device['mac_address'] ?? device['mac'] ?? 'UNKNOWN';
      String deviceName = device['name'] ?? device['home_name'] ?? 'Thiết bị $mac';
      
      var rawState = device['state'] ?? device['state_data'] ?? device['properties']; 
      Map<String, dynamic> stateMap = {};
      if (rawState is String) {
        String s = rawState.trim();
        if (s.startsWith('{')) { try { stateMap = Map<String, dynamic>.from(jsonDecode(s)); } catch(_) {} }
        else { stateMap = {'state': s}; }
      } else if (rawState is Map) {
        stateMap = Map<String, dynamic>.from(rawState);
      }

      // TRẢI PHẲNG JSON: Dù mạch gửi dạng {"switch":{"power1": "ON"}} hay gộp chung thì đều moi ra được hết!
      Map<String, String> flatEndpoints = {};
      void flatten(Map m) {
        m.forEach((k, v) {
          if (v is Map) {
             if (v.containsKey('state') || v.containsKey('value')) {
                String s = (v['state'] ?? v['value']).toString().toUpperCase();
                if (['ON', 'OFF', 'TRUE', 'FALSE', '1', '0'].contains(s)) flatEndpoints[k] = ['ON', 'TRUE', '1'].contains(s) ? 'ON' : 'OFF';
             } else { flatten(v); }
          } else {
             String s = v.toString().toUpperCase();
             if (['ON', 'OFF', 'TRUE', 'FALSE', '1', '0'].contains(s)) flatEndpoints[k] = ['ON', 'TRUE', '1'].contains(s) ? 'ON' : 'OFF';
          }
        });
      }
      flatten(stateMap);

      // Nhận diện Quạt
      List<String> eps = flatEndpoints.keys.map((e) => e.toLowerCase()).toList();
      bool isFan = deviceName.toLowerCase().contains('quạt') || deviceName.toLowerCase().contains('fan') ||
                   eps.contains('sw') || eps.contains('swing') || eps.contains('tupnang') ||
                   eps.any((e) => e.contains('speed')) || 
                   (eps.contains('1') && eps.contains('2') && eps.contains('3'));

      // --- NẾU LÀ QUẠT ---
      if (isFan) {
        int speed = 0; bool swing = false;
        bool checkOn(String t) => flatEndpoints.entries.any((entry) => entry.key.toLowerCase() == t && entry.value == 'ON');

        if (checkOn('3') || checkOn('speed3')) speed = 3;
        else if (checkOn('2') || checkOn('speed2')) speed = 2;
        else if (checkOn('1') || checkOn('speed1')) speed = 1;
        else if (checkOn('power') || checkOn('power0') || checkOn('fan_power') || checkOn('state')) speed = 1;

        if (checkOn('sw') || checkOn('swing') || checkOn('tupnang')) swing = true;

        allFans.add({
          'mac': mac, 'endpoint': 'fan', 'data': {'speed': speed, 'swing': swing, 'name': deviceName}, 'rawDevice': device
        });
        continue; 
      }

      // --- NẾU LÀ CÔNG TẮC ĐA KÊNH ---
      if (flatEndpoints.isEmpty) {
        String dLow = deviceName.toLowerCase();
        if (dLow.contains('4b') || dLow.contains('4ch') || dLow.contains('4 nút') || dLow.contains('công tắc 4')) {
          ['power1', 'power2', 'power3', 'power4'].forEach((ep) => allSwitches.add({'mac': mac, 'endpoint': ep, 'data': {'state': 'OFF', 'name': 'Relay ${ep.replaceAll("power", "")}'}, 'rawDevice': device}));
        } else {
          allSwitches.add({'mac': mac, 'endpoint': 'power1', 'data': {'state': 'OFF', 'name': deviceName}, 'rawDevice': device});
        }
      } else {
        flatEndpoints.forEach((key, state) {
          if (!ignoredKeys.contains(key.toLowerCase())) {
             allSwitches.add({'mac': mac, 'endpoint': key, 'data': {'state': state, 'name': translateName(key)}, 'rawDevice': device});
          }
        });
      }
    }

    List<Map<String, dynamic>> visibleSwitches = allSwitches.where((item) => !_hiddenDevices.contains("${item['mac']}_${item['endpoint']}") || _showHiddenFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. VẼ THẺ QUẠT LỚN NẰM TRÊN CÙNG
        if (allFans.isNotEmpty) Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Wrap(
            spacing: 16, runSpacing: 16, 
            children: allFans.map((e) => SmartFanCard(
              key: ValueKey("${e['mac']}_fan_${e['data']['speed']}_${e['data']['swing']}"), 
              mac: e['mac'], endpoint: e['endpoint'], initialSpeed: e['data']['speed'] ?? 0, 
              initialSwing: e['data']['swing'] == true, provider: provider, onRefresh: _handleRefresh,
              
              // KÍCH HOẠT HÀM XÓA CHO QUẠT
              onDelete: () => _deleteDevice(e['mac']),
            )).toList()
          ),
        ),

        // 2. VẼ LƯỚI CÔNG TẮC Ở BÊN DƯỚI
        if (visibleSwitches.isNotEmpty) LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount; double ratio;
              if (constraints.maxWidth < 500) { crossAxisCount = 3; ratio = 1.0; } 
              else { crossAxisCount = (constraints.maxWidth / 120).floor(); if (crossAxisCount < 4) crossAxisCount = 4; ratio = 1.0; }
              
              return GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: visibleSwitches.length, 
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: ratio), 
                itemBuilder: (context, index) { 
                  var item = visibleSwitches[index]; 
                  String mac = item['mac']; String ep = item['endpoint']; String deviceKey = "${mac}_$ep";
                  bool isOnline = item['data']['state'] == 'ON'; 
                  
                  return SmartSwitchCard(
                    key: ValueKey("${deviceKey}_$isOnline"), 
                    mac: mac, endpointKey: ep, backendName: item['data']['name'], 
                    initialStatus: isOnline, provider: provider, onRefresh: _handleRefresh,
                    rawDeviceData: item['rawDevice'], 
                    isHidden: _hiddenDevices.contains(deviceKey), isSelectionMode: _isSelectionMode, isSelected: _selectedDevices.contains(deviceKey),
                    hasHiddenDevices: _hiddenDevices.isNotEmpty, isShowingHidden: _showHiddenFilter,
                    onToggleShowHidden: () => setState(() => _showHiddenFilter = !_showHiddenFilter),
                    onEnterSelectionMode: () => setState(() { _isSelectionMode = true; _selectedDevices.add(deviceKey); }),
                    onToggleSelect: () => setState(() { _selectedDevices.contains(deviceKey) ? _selectedDevices.remove(deviceKey) : _selectedDevices.add(deviceKey); if (_selectedDevices.isEmpty) _isSelectionMode = false; }),
                    onToggleHide: (hide) => setState(() { hide ? _hiddenDevices.add(deviceKey) : _hiddenDevices.remove(deviceKey); }),
                    
                    // KÍCH HOẠT HÀM XÓA CHO CÔNG TẮC
                    onDelete: () => _deleteDevice(mac),
                    
                    onRename: () => _showRenameDialog(deviceKey, item['data']['name']),
                  ); 
                }
              );
            }
          ),
      ],
    );
  }

  void _showRenameDialog(String deviceKey, String currentName) {
    TextEditingController controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên thiết bị', style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nhập tên mới...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00A651)),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã lưu tên mới: ${controller.text}')));
            },
            child: const Text('Lưu thay đổi', style: TextStyle(color: Colors.white)),
          )
        ],
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
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A), textSub = isDark ? Colors.white54 : const Color(0xFF64748B), sidebarColor = isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey.withValues(alpha: 0.05);

    return Dialog(
      backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(24), 
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 650),
        child: GlassContainer(
          padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              Container(
                width: 240, decoration: BoxDecoration(color: sidebarColor, border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.2)))),
                child: Column(
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0), child: Container(height: 32, decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.white70, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.3))), child: Row(children: [const SizedBox(width: 8), Icon(Icons.search, size: 16, color: textSub), const SizedBox(width: 8), Text('Tìm kiếm', style: TextStyle(color: textSub, fontSize: 13))]))),
                    _buildTabButton(0, Icons.person_outline, 'Hồ sơ tài khoản', textMain), _buildTabButton(1, Icons.palette_outlined, 'Giao diện', textMain), _buildTabButton(2, Icons.shield_outlined, 'Bảo mật & Mật khẩu', textMain), _buildTabButton(3, Icons.info_outline, 'Thông tin hệ thống', textMain), const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: InkWell(
                        onTap: () async { Navigator.pop(context); await AuthService().logout(); if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false); },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center, decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: const Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
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
                            if (_selectedTab != 0) ...[Text(_selectedTab == 1 ? 'Giao diện (Appearance)' : _selectedTab == 2 ? 'Bảo mật & Mật khẩu' : 'Thông tin hệ thống', style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold)), const SizedBox(height: 32)],
                            Expanded(child: _selectedTab == 0 ? ProfileManagementView(currentRole: widget.currentRole, currentEmail: widget.currentEmail) : _selectedTab == 1 ? _buildAppearanceTab(textMain, textSub) : _selectedTab == 2 ? _buildSecurityTab(textMain, textSub) : _buildInfoTab(textMain, textSub)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String title, Color txtMain) {
    bool isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index), borderRadius: BorderRadius.circular(8),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: isSelected ? tkGreen : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(icon, size: 20, color: isSelected ? Colors.white : txtMain), const SizedBox(width: 12), Text(title, style: TextStyle(color: isSelected ? Colors.white : txtMain, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14))])),
      ),
    );
  }

  Widget _buildAppearanceTab(Color textMain, Color textSub) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color boxColor = isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chủ đề màu sắc', style: TextStyle(color: textSub, fontWeight: FontWeight.bold)), const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            RadioListTile<ThemeMode>(title: Text('Chế độ Sáng (Light)', style: TextStyle(color: textMain, fontWeight: FontWeight.w500)), value: ThemeMode.light, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)), Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
            RadioListTile<ThemeMode>(title: Text('Chế độ Tối (Dark)', style: TextStyle(color: textMain, fontWeight: FontWeight.w500)), value: ThemeMode.dark, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)), Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
            RadioListTile<ThemeMode>(title: Text('Tự động theo hệ thống', style: TextStyle(color: textMain, fontWeight: FontWeight.w500)), value: ThemeMode.system, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
          ]),
        )
      ],
    );
  }

  Widget _buildSecurityTab(Color textMain, Color textSub) {
    final oldPassCtrl = TextEditingController(), newPassCtrl = TextEditingController(), confirmPassCtrl = TextEditingController();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Thay đổi mật khẩu tài khoản hiện tại', style: TextStyle(color: textSub, fontWeight: FontWeight.bold)), const SizedBox(height: 16),
          TextField(controller: oldPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu cũ', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 16),
          TextField(controller: newPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 16),
          TextField(controller: confirmPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Xác nhận lại mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))), const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, height: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                final oldPass = oldPassCtrl.text.trim(), newPass = newPassCtrl.text.trim();
                if (oldPass.isEmpty || newPass.isEmpty) return;
                if (newPass != confirmPassCtrl.text.trim()) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu xác nhận không khớp!'), backgroundColor: Colors.redAccent)); return; }
                String? error = await AuthService().changePassword(oldPass, newPass);
                if (error == null) {
                  if (!context.mounted) return; oldPassCtrl.clear(); newPassCtrl.clear(); confirmPassCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công!'), backgroundColor: Color(0xFF00A651)));
                } else { if (!context.mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent)); }
              },
              child: const Text('Cập nhật mật khẩu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoTab(Color textMain, Color textSub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Column(children: [Container(width: 80, height: 80, decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)), child: Icon(Icons.home_rounded, color: tkGreen, size: 48)), const SizedBox(height: 16), Text('TK_IOT CloudPlatform', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.w900)), Text('Phiên bản 3.0.1 (Stable)', style: TextStyle(color: textSub, fontSize: 14))])),
        const SizedBox(height: 40),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.dns, color: textSub), title: Text('Máy chủ', style: TextStyle(color: textSub, fontSize: 13)), subtitle: Text('MQTT Core Golang (Armbian)', style: TextStyle(color: textMain, fontWeight: FontWeight.bold))),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.copyright, color: textSub), title: Text('Bản quyền', style: TextStyle(color: textSub, fontSize: 13)), subtitle: Text('© 2026 Tuan Kiet Solutions.', style: TextStyle(color: textMain, fontWeight: FontWeight.bold))),
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
  final DeviceProvider provider;
  final Function onRefresh;
  final String? backendName;
  final Map<String, dynamic> rawDeviceData; // <--- CHỨA CẢM BIẾN & CHẨN ĐOÁN

  final bool isSelectionMode;
  final bool isSelected;
  final bool isHidden;
  final VoidCallback onToggleSelect;
  final VoidCallback onEnterSelectionMode;
  final Function(bool) onToggleHide; 
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final bool hasHiddenDevices;
  final bool isShowingHidden;
  final VoidCallback? onToggleShowHidden;

  const SmartSwitchCard({
    Key? key,
    required this.mac, required this.endpointKey, required this.initialStatus,
    required this.provider, required this.onRefresh, this.backendName,
    required this.rawDeviceData,
    this.isSelectionMode = false, this.isSelected = false, this.isHidden = false,
    required this.onToggleSelect, required this.onEnterSelectionMode,
    required this.onToggleHide, required this.onDelete, required this.onRename,
    this.hasHiddenDevices = false, this.isShowingHidden = false, this.onToggleShowHidden,
  }) : super(key: key);

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
    if (widget.isSelectionMode) widget.onToggleSelect(); 
    else {
      bool oldState = isOnline;
      setState(() => isOnline = !isOnline); 
      widget.provider.toggleDevice(widget.mac, widget.endpointKey, oldState);
    }
  }

  String _formatName() {
    if (widget.backendName != null && widget.backendName!.isNotEmpty) return widget.backendName!;
    return widget.endpointKey;
  }

  // --- MÀN HÌNH CÀI ĐẶT CHI TIẾT (POPUP GIỮA MÀN HÌNH - KÍNH MỜ CHUẨN) ---
  void _showDeviceSettingsDialog(BuildContext context, bool isDark) {
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    // BÓC TÁCH CẢM BIẾN (DIAGNOSTICS) CỰC KỲ CHI TIẾT
    Map<String, dynamic> raw = widget.rawDeviceData;
    var stateData = raw['state'] ?? raw['state_data'] ?? raw['properties'] ?? {};
    if (stateData is String) stateData = jsonDecode(stateData) ?? {};
    
    // Hàm Helper thông minh: Lục lọi các key có thể chứa dữ liệu
    String findValue(List<String> keys, String fallback) {
      for (var k in keys) {
        if (raw.containsKey(k) && raw[k] != null && raw[k].toString().isNotEmpty) return raw[k].toString();
        if (stateData.containsKey(k) && stateData[k] != null && stateData[k].toString().isNotEmpty) return stateData[k].toString();
      }
      return fallback;
    }

    // Quét lấy các thông số thật từ thiết bị
    String ipStr = findValue(['ip', 'ip_address', 'ipAddress', 'wifi_ip'], 'Không xác định');
    String rssiStr = findValue(['rssi', 'wifi_signal', 'signal', 'wifi'], '-');
    String serialStr = findValue(['serial', 'mac', 'mac_address', 'macAddress'], widget.mac);
    String fwStr = findValue(['fw', 'version', 'firmware', 'sw_version'], '1.0.0');

    showDialog(
      context: context, 
      barrierColor: Colors.black.withValues(alpha: 0.5), // Nền làm mờ tối lại
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, // Bắt buộc transparent để hiện hiệu ứng kính mờ
        elevation: 0, 
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420), // Khung giới hạn vừa vặn ở giữa màn hình
          child: GlassContainer(
            padding: const EdgeInsets.all(0), 
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- HEADER ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.tune_rounded, color: tkGreen, size: 28),
                            const SizedBox(width: 12),
                            Text('Cài đặt thiết bị', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(icon: Icon(Icons.close, color: textSub), onPressed: () => Navigator.pop(ctx), padding: EdgeInsets.zero, constraints: const BoxConstraints())
                      ],
                    ),
                  ),
                  Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12),
                  
                  // --- NỘI DUNG CHI TIẾT ---
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // BLOCK 1: THÔNG TIN CHUNG
                          Text('THÔNG TIN CHUNG', style: TextStyle(color: tkGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                ListTile(title: Text('Tên thiết bị', style: TextStyle(color: textMain, fontSize: 14)), trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(_formatName(), style: TextStyle(color: textSub, fontSize: 14)), const SizedBox(width: 8), Icon(Icons.edit, color: tkGreen, size: 18)]), onTap: () { Navigator.pop(ctx); widget.onRename(); }),
                                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                                ListTile(title: Text('Nhà sản xuất', style: TextStyle(color: textMain, fontSize: 14)), trailing: Text('Tuan Kiet Smart Home', style: TextStyle(color: textSub, fontSize: 14))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // BLOCK 2: CẤU HÌNH
                          Text('CẤU HÌNH', style: TextStyle(color: tkGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                ListTile(leading: Icon(Icons.system_update_alt, color: textSub, size: 20), title: Text('Cập nhật Firmware', style: TextStyle(color: textMain, fontSize: 14)), trailing: Text('Mới nhất', style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.bold))),
                                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                                ListTile(leading: Icon(Icons.wifi_password, color: textSub, size: 20), title: Text('Reset Factory WiFi', style: TextStyle(color: textMain, fontSize: 14)), trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)), child: Text('Nhấn', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 13)))),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // BLOCK 3: CHẨN ĐOÁN HỆ THỐNG
                          Text('CHẨN ĐOÁN HỆ THỐNG', style: TextStyle(color: tkGreen, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                ListTile(leading: Icon(Icons.lan_outlined, color: textSub, size: 20), title: Text('IP Address', style: TextStyle(color: textMain, fontSize: 14)), trailing: Text(ipStr, style: TextStyle(color: textSub, fontFamily: 'monospace', fontSize: 13))),
                                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                                ListTile(leading: Icon(Icons.qr_code_2, color: textSub, size: 20), title: Text('Số Serial (MAC)', style: TextStyle(color: textMain, fontSize: 14)), trailing: Text(serialStr, style: TextStyle(color: textSub, fontFamily: 'monospace', fontSize: 13))),
                                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                                ListTile(leading: Icon(Icons.wifi, color: textSub, size: 20), title: Text('Cường độ WiFi (RSSI)', style: TextStyle(color: textMain, fontSize: 14)), trailing: Text(rssiStr != '-' ? '$rssiStr dBm' : rssiStr, style: TextStyle(color: textSub, fontSize: 13))),
                                Divider(height: 1, indent: 16, color: isDark ? Colors.white10 : Colors.black12),
                                ListTile(leading: Icon(Icons.memory, color: textSub, size: 20), title: Text('Phiên bản lõi', style: TextStyle(color: textMain, fontSize: 14)), trailing: Text(fwStr, style: TextStyle(color: textSub, fontSize: 13))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
    );
  }

  void _showDeviceOptions(BuildContext context, bool isDark) {
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    showDialog(
      context: context, barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, elevation: 0, insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.settings_input_component_rounded, color: tkGreen, size: 30), const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_formatName(), style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6), Text('MAC: ${widget.mac}', style: TextStyle(color: textSub, fontSize: 12)),
                            const SizedBox(height: 2), Text('Endpoint: ${widget.endpointKey}', style: TextStyle(color: textSub, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // GỌI MENU CÀI ĐẶT (CHẨN ĐOÁN) Ở ĐÂY
                  _buildMenuItem(Icons.settings_rounded, 'Cài đặt thiết bị', textMain, () { Navigator.pop(ctx); _showDeviceSettingsDialog(context, isDark); }),
                  _buildMenuItem(Icons.edit_rounded, 'Sửa tên thiết bị', textMain, () { Navigator.pop(ctx); widget.onRename(); }),
                  _buildMenuItem(widget.isHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, widget.isHidden ? 'Hiển thị lại công tắc này' : 'Ẩn khỏi Bảng điều khiển', textMain, () { Navigator.pop(ctx); widget.onToggleHide(!widget.isHidden); }, subtitle: widget.isHidden ? null : 'Vẫn hiển thị trong danh sách thiết bị'),
                  _buildMenuItem(Icons.checklist_rtl_rounded, 'Chọn nhiều thiết bị', textMain, () { Navigator.pop(ctx); widget.onEnterSelectionMode(); }),
                  if (widget.hasHiddenDevices) _buildMenuItem(widget.isShowingHidden ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded, widget.isShowingHidden ? 'Đóng chế độ xem thiết bị ẩn' : 'Hiển thị các thiết bị đã ẩn', Colors.orange, () { Navigator.pop(ctx); if (widget.onToggleShowHidden != null) widget.onToggleShowHidden!(); }),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1, thickness: 1)),
                  _buildMenuItem(Icons.delete_outline_rounded, 'Xóa thiết bị', Colors.redAccent, () { Navigator.pop(ctx); _confirmDeleteDevice(context, isDark, textMain, textSub); }, isDestructive: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, Color color, VoidCallback onTap, {String? subtitle, bool isDestructive = false}) {
    return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), hoverColor: isDestructive ? Colors.redAccent.withValues(alpha: 0.1) : Colors.white10, leading: Icon(icon, color: color, size: 24), title: Text(title, style: TextStyle(color: color, fontSize: 15, fontWeight: isDestructive ? FontWeight.bold : FontWeight.w600)), subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, height: 1.2)) : null, onTap: onTap);
  }

  void _confirmDeleteDevice(BuildContext context, bool isDark, Color textMain, Color textSub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Xóa ${_formatName()}?', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn gỡ thiết bị này khỏi hệ thống không?', style: TextStyle(color: textSub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { Navigator.pop(ctx); widget.onDelete(); }, child: const Text('Xóa ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isOnline ? tkGreen : (isDark ? const Color(0xFF1E293B) : Colors.white.withValues(alpha: 0.6));
    final Color textColor = isOnline ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final Color powerIconColor = isOnline ? Colors.white : (isDark ? Colors.white24 : Colors.grey.shade400);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16), 
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          foregroundDecoration: widget.isHidden ? BoxDecoration(color: isDark ? Colors.black.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.7)) : null,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.isSelected ? tkGreen : (isOnline ? tkGreen : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white)), width: widget.isSelected ? 3.0 : 1.5), boxShadow: [if (!isDark && !isOnline) BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))]),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleTap, onLongPress: () { if (!widget.isSelectionMode) _showDeviceOptions(context, isDark); }, 
              child: Stack(
                children: [
                  Positioned(top: 10, left: 10, child: Icon(Icons.lightbulb_outline, color: isOnline ? Colors.white : tkGreen, size: 18)),
                  if (widget.isSelected) Positioned(top: 8, right: 8, child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: tkGreen, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const Icon(Icons.check, color: Colors.white, size: 14))),
                  Align(alignment: Alignment.center, child: Padding(padding: const EdgeInsets.only(bottom: 14.0, top: 10.0), child: Icon(Icons.power_settings_new_rounded, color: powerIconColor, size: 36))),
                  Positioned(bottom: 8, left: 6, right: 6, child: Text(_formatName(), textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
// 🌀 QUẠT THÔNG MINH 
// ============================================================================
class SmartFanCard extends StatefulWidget {
  final String mac, endpoint; final int initialSpeed; final bool initialSwing; final DeviceProvider provider;
  final VoidCallback onRefresh;
  final VoidCallback onDelete;

  const SmartFanCard({super.key, required this.mac, required this.endpoint, required this.initialSpeed, required this.initialSwing, required this.provider, required this.onRefresh, required this.onDelete});
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

  void _changeSpeed(int newSpeed) { setState(() => speed = newSpeed); widget.provider.setFanSpeed(widget.mac, widget.endpoint, speed, swing); }
  void _toggleSwing() { if (speed == 0) return; setState(() => swing = !swing); widget.provider.setFanSpeed(widget.mac, widget.endpoint, speed, swing); }

  void _showDeviceOptions(BuildContext context, bool isDark) {
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent, elevation: 0, insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassContainer(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.all_out_rounded, color: tkGreen, size: 28),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Quạt thông minh', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('MAC: ${widget.mac}', style: TextStyle(color: textSub, fontSize: 12)),
                const SizedBox(height: 24),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(Icons.settings_rounded, color: textMain),
                  title: Text('Cài đặt', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(ctx); },
                ),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(Icons.visibility_off_rounded, color: textMain),
                  title: Text('Ẩn khỏi Bảng điều khiển', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(ctx); },
                ),
                Divider(color: isDark ? Colors.white10 : Colors.black12),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                  title: const Text('Xóa thiết bị', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  onTap: () { Navigator.pop(ctx); _confirmDeleteFan(context, isDark, textMain, textSub); },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteFan(BuildContext context, bool isDark, Color textMain, Color textSub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text('Xóa Quạt thông minh?', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn gỡ thiết bị này khỏi hệ thống không?', style: TextStyle(color: textSub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () { Navigator.pop(ctx); widget.onDelete(); }, child: const Text('Xóa ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isOnline = speed > 0, isSwingActive = swing && isOnline;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A), textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Container(
      width: double.infinity, constraints: const BoxConstraints(maxWidth: 450), 
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12), 
                  decoration: BoxDecoration(color: isOnline ? tkGreen.withValues(alpha: 0.15) : (isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.6)), shape: BoxShape.circle), 
                  // Sử dụng icon all_out_rounded ở đây
                  child: SpinningWidget(isSpinning: isOnline, speedLevel: speed, child: Icon(Icons.all_out_rounded, color: isOnline ? tkGreen : textSub, size: 28))
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Quạt thông minh', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(isOnline ? 'Đang bật • Số $speed' : 'Đã tắt', style: TextStyle(color: isOnline ? tkGreen : textSub, fontSize: 13, fontWeight: FontWeight.w600))])),
                IconButton(icon: Icon(Icons.more_vert, color: textSub, size: 22), onPressed: () => _showDeviceOptions(context, isDark), splashRadius: 20)
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildBtn(0, 'OFF', speed == 0, isDark), const SizedBox(width: 8), _buildBtn(1, '1', speed == 1, isDark), const SizedBox(width: 8), _buildBtn(2, '2', speed == 2, isDark), const SizedBox(width: 8), _buildBtn(3, '3', speed == 3, isDark), const SizedBox(width: 12),
                Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.grey.shade300), const SizedBox(width: 12),
                Material(color: isSwingActive ? tkGreen.withValues(alpha: 0.85) : (isDark ? Colors.white24 : Colors.white.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: _toggleSwing, child: Container(height: 40, padding: const EdgeInsets.symmetric(horizontal: 14), alignment: Alignment.center, child: Row(children: [Icon(Icons.threesixty, color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), size: 16), const SizedBox(width: 4), Text('Xoay', style: TextStyle(color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 12, fontWeight: FontWeight.w800))]))))
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBtn(int btnSpeed, String label, bool isActive, bool isDark) {
    bool isOffBtn = btnSpeed == 0;
    Color bgColor = isActive ? (isOffBtn ? Colors.redAccent.withValues(alpha: 0.85) : tkGreen.withValues(alpha: 0.85)) : (isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.6));
    Color textColor = isActive ? Colors.white : (isDark ? Colors.white : Colors.black87);
    return Expanded(child: Material(color: bgColor, borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: () => _changeSpeed(btnSpeed), child: Container(height: 40, alignment: Alignment.center, child: Text(label, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w900))))));
  }
}