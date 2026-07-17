import 'package:flutter/material.dart';
import '../../services/secure_storage_service.dart';
import '../../widgets/app_ui_wrappers.dart';
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

    // MINIMALIST: chỉ icon launcher + vòng xoay. Nền LẤY THEO scaffoldBackgroundColor
    // của theme -> tự đồng bộ Sáng/Tối.
    return AppScaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon ĐẠI DIỆN của App (launcher icon): Container đổ bóng nhẹ (nổi 3D) ->
            // ClipRRect bo góc 22 mô phỏng icon iOS/Android -> ảnh vuông 100x100.
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                    blurRadius: 22,
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
            const SizedBox(height: 48),
            // Vòng xoay lấy màu chủ đạo hệ thống qua primaryColor
            SizedBox(
              width: 30, height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}