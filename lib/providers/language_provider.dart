import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LanguageProvider — "động cơ" đa ngôn ngữ, dựng CÙNG khuôn với ThemeProvider: quản lý
/// Locale hiện tại (mặc định 'vi'), tự lưu/khôi phục qua SharedPreferences, notifyListeners()
/// để mọi widget đang đọc AppTranslations.of(context) tự vẽ lại NGAY khi đổi ngôn ngữ —
/// real-time, không cần khởi động lại App (cùng triết lý setGlassThemeEnabled()).
class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('vi'); // Mặc định Tiếng Việt

  Locale get locale => _locale;

  static const List<String> supportedLanguageCodes = ['vi', 'en'];

  LanguageProvider() {
    _loadLanguage();
  }

  /// Đổi ngôn ngữ — chỉ nhận 'vi'/'en' (supportedLanguageCodes); mã lạ hoặc trùng ngôn ngữ
  /// hiện tại thì bỏ qua, không notifyListeners() vô ích.
  void changeLanguage(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode) || languageCode == _locale.languageCode) return;
    _locale = Locale(languageCode);
    notifyListeners(); // Kích hoạt đổi ngôn ngữ toàn App ngay lập tức (mọi nơi dùng AppTranslations.of())

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('language_code', languageCode);
  }

  void _loadLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString('language_code');
    if (code != null && supportedLanguageCodes.contains(code)) {
      _locale = Locale(code);
      notifyListeners();
    }
  }
}
