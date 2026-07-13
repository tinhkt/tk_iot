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
            // Logo thương hiệu — Hero để sẵn hiệu ứng chuyển cảnh về sau (tag dùng chung
            // nếu màn Đăng nhập đặt cùng tag 'app_logo'); ClipRRect bo góc mềm.
            Hero(
              tag: 'app_logo',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                  // Lưới an toàn: thiếu/hỏng asset thì hiện icon nhà thay vì ô vỡ đỏ
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: _tkGreen.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.home_rounded, color: _tkGreen, size: 64),
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