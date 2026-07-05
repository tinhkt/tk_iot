import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // Mặc định là Tự động theo thiết bị

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  void setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners(); // Kích hoạt đổi màu toàn App ngay lập tức
    
    // Lưu vào bộ nhớ máy để mở app lần sau không bị mất
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt('theme_mode', mode.index);
  }

  void _loadTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? modeIndex = prefs.getInt('theme_mode');
    if (modeIndex != null) {
      _themeMode = ThemeMode.values[modeIndex];
      notifyListeners();
    }
  }
}