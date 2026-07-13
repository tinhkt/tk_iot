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

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF00A651)), // Vòng xoay loading thương hiệu
      ),
    );
  }
}