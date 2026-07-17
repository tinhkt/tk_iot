import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system; // Mặc định là Tự động theo thiết bị

  ThemeMode get themeMode => _themeMode;

  // [GLASS THEME — TÙY CHỌN SONG SONG] Không thay thế themeMode (sáng/tối/hệ thống) — đây
  // là một trục ĐỘC LẬP: bật/tắt lớp "vỏ" Ultra-Glassmorphism (nền Aurora + thẻ kính 3D) mà
  // vẫn tôn trọng sáng/tối bên dưới. app_ui_wrappers.dart đọc cờ này để rẽ nhánh render —
  // KHÔNG có nơi nào khác trong app được phép tự ý bật/tắt hiệu ứng kính ngoài field này.
  bool _isGlassThemeEnabled = false;
  bool get isGlassThemeEnabled => _isGlassThemeEnabled;

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

  /// Bật/tắt Glass Theme — mọi AppScaffold/AppCard/AppDialog... (app_ui_wrappers.dart) tự
  /// vẽ lại NGAY qua notifyListeners(), không cần khởi động lại App.
  void setGlassThemeEnabled(bool enabled) async {
    _isGlassThemeEnabled = enabled;
    notifyListeners();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool('glass_theme_enabled', enabled);
  }

  void _loadTheme() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int? modeIndex = prefs.getInt('theme_mode');
    bool? glassEnabled = prefs.getBool('glass_theme_enabled');
    if (modeIndex != null) _themeMode = ThemeMode.values[modeIndex];
    if (glassEnabled != null) _isGlassThemeEnabled = glassEnabled;
    if (modeIndex != null || glassEnabled != null) notifyListeners();
  }
}