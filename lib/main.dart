import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/splash_screen.dart'; // 1. NHẬP NGƯỜI GÁC CỔNG VÀO
import 'providers/notification_provider.dart';
import 'providers/room_group_provider.dart';
import 'providers/automation_provider.dart';
import 'providers/home_provider.dart';

// KHAI BÁO KHÓA ĐIỀU HƯỚNG TOÀN CỤC CHỐNG CRASH / TREO KHI HẾT HẠN TOKEN
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================================
// 🔐 GỠ RÀO SSL (HandshakeException khi ra mạng ngoài qua Nginx Proxy Manager)
// ============================================================================
// Server sau NPM có thể gửi chuỗi chứng chỉ THIẾU intermediate (fullchain): Android/iOS
// kiểm chain of trust nghiêm nên từ chối bắt tay -> "Connection terminated during
// handshake" trên 4G, còn WiFi/Windows tự tìm được intermediate nên vẫn chạy.
//
// [BYPASS TOÀN CỤC — TẠM THỜI] badCertificateCallback trả `true` VÔ ĐIỀU KIỆN cho MỌI
// host, để chắc chắn REST API (qua NPM) không bao giờ bị chặn dù allowlist theo host
// trước đó không khớp (redirect/subdomain/CDN...).
//
// ⚠️ CẢNH BÁO BẢO MẬT: chấp nhận mọi chứng chỉ = App tin cả cert giả -> lộ cửa cho tấn
// công Man-in-the-Middle (đọc lén JWT/mật khẩu trên WiFi công cộng). Đây là giải pháp
// TẠM để hệ thống chạy; FIX GỐC là cài đúng Intermediate Certificate (fullchain) trên
// NPM cho api.iot-smart.vn, sau đó siết lại thành allowlist theo host.
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  // [SSL BYPASS] Cài override NGAY đầu main(), TRƯỚC mọi request HTTPS (API/MQTT).
  // Chỉ áp dụng nền tảng có dart:io (Android/iOS/Desktop) — Web dùng SSL trình duyệt.
  if (!kIsWeb) {
    HttpOverrides.global = MyHttpOverrides();
  }

  // Bắt buộc khi main() là async và thao tác với UI hệ thống
  WidgetsFlutterBinding.ensureInitialized();

  // --- THIẾT LẬP CỬA SỔ TRÀN VIỀN CHO DESKTOP ---
  // Chỉ chạy khối lệnh này nếu không phải là Web và đang chạy trên Windows/macOS/Linux
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 800), // Kích thước mặc định khi mở
      minimumSize: Size(360, 640), // Đã thu nhỏ giới hạn xuống bằng điện thoại
      center: true, 
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, 
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => RoomGroupProvider()), // Phòng + Nhóm (mock)
        ChangeNotifierProvider(create: (_) => AutomationProvider()), // Ngữ cảnh (mock)
        ChangeNotifierProvider(create: (_) => HomeProvider()), // Quản lý Nhà + Sổ thành viên (dữ liệu thật)
      ],
      child: const TkIotApp(),
    ),
  );
}

class TkIotApp extends StatelessWidget {
  const TkIotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          // GẮN KHÓA ĐIỀU HƯỚNG TOÀN CỤC VÀO ĐÂY ĐỂ ĐÁ TÀI KHOẢN KHI LỖI 401
          navigatorKey: navigatorKey,
          
          title: 'TK_IOT CloudPlatform',
          debugShowCheckedModeBanner: false,
          
          // CẤU HÌNH GIAO DIỆN SÁNG
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F6F9),
            primaryColor: const Color(0xFF00A651),
            fontFamily: 'Roboto',
          ),

          // CẤU HÌNH GIAO DIỆN TỐI (Đã chỉnh sang Deep Slate để hợp Glassmorphism)
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0B1120),
            primaryColor: const Color(0xFF00A651),
            fontFamily: 'Roboto',
          ),

          themeMode: themeProvider.themeMode, 
          
          // 2. THIẾT LẬP MÀN HÌNH KHỞI ĐỘNG LÀ SPLASHSCREEN
          home: const SplashScreen(), 
        );
      },
    );
  }
}