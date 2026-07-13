import 'package:flutter/material.dart';
import '../../services/secure_storage_service.dart';
import '../dashboard_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final token = await SecureStorageService.getToken();

    // Đợi 1 chút để màn hình Splash hiện ra (giúp trải nghiệm mượt hơn)
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return; // widget đã bị gỡ trong lúc chờ -> không điều hướng nữa
    if (token != null && token.isNotEmpty) {
      // Nếu có token, vào thẳng Dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      // Nếu không có, bắt đăng nhập
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  static const Color _tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    // Nền LẤY THEO scaffoldBackgroundColor của theme -> tự đồng bộ Sáng/Tối
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon ĐẠI DIỆN của App (launcher icon) — bo góc 22 mô phỏng hình dáng icon
            // iOS/Android + đổ bóng nhẹ cho nổi khối. Hero sẵn cho hiệu ứng chuyển cảnh
            // (dùng chung tag 'app_logo' nếu màn Đăng nhập đặt cùng tag).
            Hero(
              tag: 'app_logo',
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/images/icon_app.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    // Lưới an toàn: thiếu/hỏng asset thì hiện icon nhà thay vì ô vỡ đỏ
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 100, height: 100,
                      color: _tkGreen.withValues(alpha: 0.15),
                      child: const Icon(Icons.home_rounded, color: _tkGreen, size: 56),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'TK_IOT CloudPlatform',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(color: _tkGreen, strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text('Đang khởi động...', style: TextStyle(color: textSub, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}