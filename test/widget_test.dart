// Smoke test cơ bản: đảm bảo màn hình Đăng nhập dựng được không lỗi.
//
// Không pump TkIotApp trực tiếp vì SplashScreen đọc secure storage (platform
// channel không tồn tại trong môi trường test).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tk_iot/screens/auth/login_screen.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ĐĂNG NHẬP HỆ THỐNG'), findsOneWidget);
    expect(find.text('XÁC THỰC TRUY CẬP'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
