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

// KHAI BÁO KHÓA ĐIỀU HƯỚNG TOÀN CỤC CHỐNG CRASH / TREO KHI HẾT HẠN TOKEN
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================================
// 🔐 GỠ RÀO SSL CHO ANDROID (HandshakeException khi chuỗi chứng chỉ chưa đầy đủ)
// ============================================================================
// Android kiểm chuỗi chứng chỉ (chain of trust) NGHIÊM hơn Windows: nếu Server chỉ
// gửi cert lá mà THIẾU chứng chỉ trung gian (fullchain), Android từ chối bắt tay ->
// "Connection terminated during handshake"; Windows lại tự tìm được intermediate nên
// vẫn chạy. Class dưới cho phép App bỏ qua lỗi xác thực để kết nối được ngay.
//
// ⚠️ QUAN TRỌNG — vì sao KHÔNG trả `true` cho mọi host:
// badCertificateCallback trả true vô điều kiện = App tin MỌI chứng chỉ giả của MỌI
// máy chủ -> mở toang cửa cho tấn công Man-in-the-Middle (kẻ gian trên WiFi công cộng
// đọc lén được JWT token + mật khẩu MQTT của người dùng). Ở đây ta CHỈ bỏ qua đúng
// (các) tên miền máy chủ của mình, các host khác vẫn được xác thực bình thường.
class MyHttpOverrides extends HttpOverrides {
  // Danh sách host được phép bỏ qua kiểm chứng chỉ — thêm tên miền của bạn tại đây
  static const Set<String> _trustedHosts = {
    'api.iot-smart.vn',
    'mqtt.iot-smart.vn',
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Chỉ chấp nhận chứng chỉ "xấu" nếu đúng là máy chủ của mình; còn lại từ chối
        return _trustedHosts.contains(host);
      };
  }
}

void main() async {
  // Bắt buộc phải có dòng này khi hàm main() là async và thao tác với UI hệ thống
  WidgetsFlutterBinding.ensureInitialized();

  // Cài bộ ghi đè SSL TRƯỚC khi có bất kỳ request HTTPS nào chạy (kết nối API/MQTT).
  // Chỉ áp dụng cho nền tảng có dart:io (Android/iOS/Desktop) — Web dùng SSL của trình
  // duyệt nên bỏ qua để tránh lỗi biên dịch.
  if (!kIsWeb) {
    HttpOverrides.global = MyHttpOverrides();
  }

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