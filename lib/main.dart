import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'providers/device_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/splash_screen.dart'; // 1. NHẬP NGƯỜI GÁC CỔNG VÀO
import 'providers/notification_provider.dart';

// KHAI BÁO KHÓA ĐIỀU HƯỚNG TOÀN CỤC CHỐNG CRASH / TREO KHI HẾT HẠN TOKEN
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Bắt buộc phải có dòng này khi hàm main() là async và thao tác với UI hệ thống
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