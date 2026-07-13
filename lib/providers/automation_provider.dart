import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../services/secure_storage_service.dart';

/// Loại ngữ cảnh: chạm-để-chạy (thủ công) hoặc tự động (IF/THEN theo điều kiện).
/// Tên enum TRÙNG KHỚP giá trị scene_type bên Backend ('tapToRun' | 'automation').
enum SceneType { tapToRun, automation }

/// Bộ icon ngữ cảnh cho user chọn — CONST để tra ngược từ codePoint (xem [sceneIconFor]).
const List<IconData> kSceneIcons = [
  Icons.auto_awesome, Icons.movie_creation_outlined, Icons.nightlight_round,
  Icons.wb_sunny_outlined, Icons.home_rounded, Icons.umbrella,
  Icons.local_cafe_outlined, Icons.directions_run,
];

/// Bộ icon các BƯỚC điều kiện/hành động — CONST để dựng lại SceneStep từ JSON server
/// mà không phải tạo `IconData(codePoint)` động (giữ icon tree-shaking + analyze sạch).
const List<IconData> kSceneStepIcons = [
  Icons.access_time, Icons.toggle_on, Icons.cloud, Icons.settings_remote,
  Icons.notifications_active_outlined, Icons.timelapse, Icons.lightbulb_outline,
  Icons.tv, Icons.power_settings_new, Icons.blinds_closed, Icons.flash_on,
  Icons.thermostat, // điều kiện thời tiết theo ngưỡng nhiệt độ
];

/// Tra IconData từ codePoint qua bảng CONST thay vì dựng `IconData(codePoint,...)` động
/// (giữ icon tree-shaking khi build release + analyze sạch). Icon lạ -> auto_awesome.
IconData sceneIconFor(int codePoint) =>
    kSceneIcons.firstWhere((i) => i.codePoint == codePoint, orElse: () => Icons.auto_awesome);

/// Tra icon bước điều kiện/hành động từ codePoint. Icon lạ -> flash_on.
IconData sceneStepIconFor(int codePoint) =>
    kSceneStepIcons.firstWhere((i) => i.codePoint == codePoint, orElse: () => Icons.flash_on);

/// Một "dòng" điều kiện/hành động trong ngữ cảnh. [params] là gói dữ liệu tự do
/// (mac/endpoint/command/time...) — Backend không ép khuôn, dùng cho Fan-out MQTT sau.
class SceneStep {
  final IconData icon;
  final String label;
  final Map<String, dynamic>? params;
  const SceneStep(this.icon, this.label, {this.params});

  /// Khuôn JSON hai chiều với Backend: {"icon_code":..., "label":..., "params":{...}}
  Map<String, dynamic> toJson() => {
        'icon_code': icon.codePoint,
        'label': label,
        if (params != null) 'params': params,
      };

  factory SceneStep.fromJson(Map<String, dynamic> json) => SceneStep(
        sceneStepIconFor((json['icon_code'] as num?)?.toInt() ?? 0),
        (json['label'] ?? '').toString(),
        params: json['params'] is Map ? Map<String, dynamic>.from(json['params'] as Map) : null,
      );
}

/// Ngữ cảnh (Scene/Automation) — bản chiếu của bảng SQL `automation_scenes`.
class SceneItem {
  final String id;
  String name;
  int iconCodePoint;
  bool enabled; // dùng cho tab Tự động (bật/tắt automation)
  SceneType type;
  List<SceneStep> conditions; // "NẾU..."
  List<SceneStep> actions;    // "THÌ..."

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

  IconData get icon => sceneIconFor(iconCodePoint);

  factory SceneItem.fromJson(Map<String, dynamic> json) {
    List<SceneStep> steps(dynamic raw) => raw is List
        ? raw.whereType<Map>().map((e) => SceneStep.fromJson(Map<String, dynamic>.from(e))).toList()
        : <SceneStep>[];
    return SceneItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      iconCodePoint: (json['icon_code'] as num?)?.toInt() ?? 0,
      enabled: json['is_enabled'] != false,
      type: json['scene_type'] == 'tapToRun' ? SceneType.tapToRun : SceneType.automation,
      conditions: steps(json['conditions']),
      actions: steps(json['actions']),
    );
  }
}

/// AutomationProvider — NGỮ CẢNH NỐI API THẬT (cụm /api/scenes bên Backend Golang).
/// Giữ nguyên chữ ký các hàm UI đang gọi (tapToRun/automations/addScene/updateScene/
/// toggleEnabled...); hàm ghi trả về `Future<String?>`: null = thành công, chuỗi = lỗi.
class AutomationProvider extends ChangeNotifier {
  // ===================== HTTP HELPER (cùng khuôn RoomGroupProvider) =====================
  static const String _apiBase = ApiService.baseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorageService.getToken();
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  String _errorFrom(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {}
    return '$fallback (HTTP ${res.statusCode})';
  }

  // ===================== STATE =====================
  List<SceneItem> _scenes = [];
  String _homeId = ''; // nhà đang hoạt động — fetchScenes ghi nhớ để addScene dùng lại

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<SceneItem> get all => List.unmodifiable(_scenes);
  List<SceneItem> get tapToRun => _scenes.where((s) => s.type == SceneType.tapToRun).toList();
  List<SceneItem> get automations => _scenes.where((s) => s.type == SceneType.automation).toList();

  /// GET /api/scenes?home_id=... — nạp toàn bộ ngữ cảnh của nhà. UI tự chia 2 tab
  /// theo type (getter tapToRun/automations lọc tại chỗ).
  Future<String?> fetchScenes(String homeId) async {
    if (homeId.isEmpty) return 'Thiếu home_id';
    _homeId = homeId;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await http.get(
        Uri.parse('$_apiBase/scenes?home_id=${Uri.encodeComponent(homeId)}'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return _errorFrom(res, 'Không tải được danh sách ngữ cảnh');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _scenes = (body['scenes'] as List? ?? [])
          .whereType<Map>()
          .map((e) => SceneItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [SCENES] Lỗi tải ngữ cảnh: $e');
      return 'Lỗi kết nối máy chủ';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// POST /api/scenes — LÕI UPSERT dùng chung cho cả tạo mới lẫn cập nhật.
  /// QUAN TRỌNG: conditions/actions map thành List<Map> RỒI MỚI jsonEncode cả body
  /// MỘT LẦN — tuyệt đối không encode riêng từng cục (double-encode làm Backend
  /// nhận chuỗi thay vì mảng JSON và trả 400).
  Future<String?> _saveScene({
    required String id, // '' = tạo mới (server tự sinh id)
    required String name,
    required int iconCodePoint,
    required SceneType type,
    required List<SceneStep> conditions,
    required List<SceneStep> actions,
    bool? enabled,
  }) async {
    if (_homeId.isEmpty) return 'Chưa xác định được nhà hiện tại';
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/scenes'),
        headers: await _authHeaders(),
        body: jsonEncode({
          'id': id,
          'home_id': _homeId,
          'name': name.trim().isEmpty ? 'Ngữ cảnh mới' : name.trim(),
          'icon_code': iconCodePoint,
          'scene_type': type.name, // 'tapToRun' | 'automation' — trùng tên enum
          'is_enabled': ?enabled, // null-aware: bỏ key khi enabled == null (server tự default)
          'conditions': conditions.map((s) => s.toJson()).toList(),
          'actions': actions.map((s) => s.toJson()).toList(),
        }),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        return _errorFrom(res, 'Không lưu được ngữ cảnh');
      }

      // Đắp bản server trả về (id thật, dữ liệu chuẩn hóa) vào list cục bộ
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final saved = SceneItem.fromJson(Map<String, dynamic>.from(body['scene'] ?? {}));
      final idx = _scenes.indexWhere((s) => s.id == saved.id);
      if (idx == -1) {
        _scenes.insert(0, saved); // mới tạo -> lên đầu (khớp sort created_at DESC)
      } else {
        _scenes[idx] = saved;
      }
      notifyListeners();
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [SCENES] Lỗi lưu ngữ cảnh: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// Thêm ngữ cảnh mới — CreateAutomationScreen gọi (giữ chữ ký cũ, nay trả lỗi).
  Future<String?> addScene({
    required String name,
    required int iconCodePoint,
    required SceneType type,
    List<SceneStep>? conditions,
    List<SceneStep>? actions,
  }) =>
      _saveScene(id: '', name: name, iconCodePoint: iconCodePoint, type: type, conditions: conditions ?? [], actions: actions ?? []);

  /// Cập nhật ngữ cảnh sẵn có — màn Sửa gọi (giữ chữ ký cũ, nay trả lỗi).
  Future<String?> updateScene(
    String id, {
    required String name,
    required int iconCodePoint,
    required SceneType type,
    List<SceneStep>? conditions,
    List<SceneStep>? actions,
  }) {
    // Giữ nguyên trạng thái bật/tắt hiện có khi sửa nội dung
    final idx = _scenes.indexWhere((s) => s.id == id);
    final bool? enabled = idx == -1 ? null : _scenes[idx].enabled;
    return _saveScene(id: id, name: name, iconCodePoint: iconCodePoint, type: type, conditions: conditions ?? [], actions: actions ?? [], enabled: enabled);
  }

  /// PUT /api/scenes/:id/toggle — Optimistic UI: gạt ngay, lỗi thì giật hoàn tác.
  Future<String?> toggleEnabled(String id, bool value) async {
    final idx = _scenes.indexWhere((s) => s.id == id);
    if (idx == -1) return 'Ngữ cảnh không tồn tại';
    final bool old = _scenes[idx].enabled;
    _scenes[idx].enabled = value;
    notifyListeners();
    try {
      final res = await http.put(
        Uri.parse('$_apiBase/scenes/${Uri.encodeComponent(id)}/toggle'),
        headers: await _authHeaders(),
        body: jsonEncode({'is_enabled': value}),
      );
      if (res.statusCode != 200) {
        _scenes[idx].enabled = old; // hoàn tác
        notifyListeners();
        return _errorFrom(res, 'Không cập nhật được trạng thái');
      }
      return null;
    } catch (e) {
      _scenes[idx].enabled = old;
      notifyListeners();
      if (kDebugMode) print('❌ [SCENES] Lỗi toggle: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// DELETE /api/scenes/:id — Optimistic: gỡ ngay, lỗi thì fetch lại khôi phục.
  Future<String?> deleteScene(String id) async {
    final idx = _scenes.indexWhere((s) => s.id == id);
    if (idx == -1) return null;
    final removed = _scenes.removeAt(idx);
    notifyListeners();
    try {
      final res = await http.delete(
        Uri.parse('$_apiBase/scenes/${Uri.encodeComponent(id)}'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) {
        _scenes.insert(idx, removed); // hoàn tác tại đúng vị trí cũ
        notifyListeners();
        return _errorFrom(res, 'Không xóa được ngữ cảnh');
      }
      return null;
    } catch (e) {
      _scenes.insert(idx, removed);
      notifyListeners();
      if (kDebugMode) print('❌ [SCENES] Lỗi xóa: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }

  /// POST /api/scenes/:id/execute — chạy thủ công (nút "Chạy" tab Chạm-để-chạy).
  /// null = lệnh đã được server nhận và đẩy đi; chuỗi = câu lỗi cho SnackBar.
  Future<String?> executeScene(String id) async {
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/scenes/${Uri.encodeComponent(id)}/execute'),
        headers: await _authHeaders(),
      );
      if (res.statusCode != 200) return _errorFrom(res, 'Không chạy được ngữ cảnh');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ [SCENES] Lỗi execute: $e');
      return 'Lỗi kết nối máy chủ';
    }
  }
}
