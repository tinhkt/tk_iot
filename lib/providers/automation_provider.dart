import 'package:flutter/material.dart';

/// Loại ngữ cảnh: chạm-để-chạy (thủ công) hoặc tự động (IF/THEN theo điều kiện).
enum SceneType { tapToRun, automation }

/// Một "dòng" điều kiện/hành động trong ngữ cảnh (mock — lưu icon + mô tả).
class SceneStep {
  final IconData icon;
  final String label;
  const SceneStep(this.icon, this.label);
}

/// Ngữ cảnh (Scene/Automation).
class SceneItem {
  final String id;
  String name;
  int iconCodePoint;
  bool enabled; // dùng cho tab Tự động (bật/tắt automation)
  final SceneType type;
  final List<SceneStep> conditions; // "NẾU..."
  final List<SceneStep> actions;    // "THÌ..."

  SceneItem({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    this.enabled = true,
    required this.type,
    List<SceneStep>? conditions,
    List<SceneStep>? actions,
  })  : conditions = conditions ?? [],
        actions = actions ?? [];

  IconData get icon => IconData(iconCodePoint, fontFamily: 'MaterialIcons');
}

/// AutomationProvider — quản lý danh sách ngữ cảnh (MOCK tĩnh trước khi đấu Backend).
class AutomationProvider extends ChangeNotifier {
  final List<SceneItem> _scenes = [
    SceneItem(
      id: 'scene_movie', name: 'Xem phim', iconCodePoint: Icons.movie_creation_outlined.codePoint, type: SceneType.tapToRun,
      actions: const [SceneStep(Icons.lightbulb_outline, 'Tắt đèn phòng khách'), SceneStep(Icons.tv, 'Bật TV')],
    ),
    SceneItem(
      id: 'scene_goodnight', name: 'Chúc ngủ ngon', iconCodePoint: Icons.nightlight_round.codePoint, type: SceneType.tapToRun,
      actions: const [SceneStep(Icons.power_settings_new, 'Tắt tất cả thiết bị')],
    ),
    SceneItem(
      id: 'scene_morning', name: 'Buổi sáng tự động', iconCodePoint: Icons.wb_sunny_outlined.codePoint, type: SceneType.automation, enabled: true,
      conditions: const [SceneStep(Icons.access_time, 'Lúc 06:30 hằng ngày')],
      actions: const [SceneStep(Icons.lightbulb_outline, 'Bật đèn bếp')],
    ),
    SceneItem(
      id: 'scene_rain', name: 'Trời mưa đóng rèm', iconCodePoint: Icons.umbrella.codePoint, type: SceneType.automation, enabled: false,
      conditions: const [SceneStep(Icons.cloud, 'Thời tiết: có mưa')],
      actions: const [SceneStep(Icons.blinds_closed, 'Đóng rèm cửa')],
    ),
  ];

  List<SceneItem> get all => List.unmodifiable(_scenes);
  List<SceneItem> get tapToRun => _scenes.where((s) => s.type == SceneType.tapToRun).toList();
  List<SceneItem> get automations => _scenes.where((s) => s.type == SceneType.automation).toList();

  void toggleEnabled(String id, bool value) {
    final s = _scenes.firstWhere((x) => x.id == id, orElse: () => _scenes.first);
    s.enabled = value;
    notifyListeners();
  }

  /// Thêm ngữ cảnh mới (mock). Đấu API sau: POST /scenes.
  SceneItem addScene({required String name, required int iconCodePoint, required SceneType type, List<SceneStep>? conditions, List<SceneStep>? actions}) {
    final s = SceneItem(
      id: 'scene_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Ngữ cảnh mới' : name.trim(),
      iconCodePoint: iconCodePoint,
      type: type,
      conditions: conditions,
      actions: actions,
    );
    _scenes.add(s);
    notifyListeners();
    return s;
  }

  void deleteScene(String id) {
    _scenes.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}
