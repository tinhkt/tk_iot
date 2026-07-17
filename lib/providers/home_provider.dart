import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

/// Lỗi API "thép" — KHÔNG BAO GIỜ bị nuốt câm. Provider ném đúng câu tiếng Việt mà
/// Backend Go đã trả về trong field "error" (403/404/409...); UI chỉ việc bắt và hiển
/// thị lên SnackBar đỏ, không tự chế lại thông báo.
class HomeApiException implements Exception {
  final int? statusCode;
  final String message;
  HomeApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// Một thành viên trong nhà — bản chiếu mỏng của home_members:{homeId} bên Backend
/// (Redis hash email -> role: OWNER/ADMIN/USER).
class HomeMember {
  final String email;
  final String role;
  const HomeMember({required this.email, required this.role});

  factory HomeMember.fromJson(Map<String, dynamic> json) => HomeMember(
        email: (json['email'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
      );
}

/// HomeProvider — nguồn sự thật DUY NHẤT cho danh sách nhà + sổ thành viên của App.
/// Thay thế state cục bộ trước đây trong HomeManagementScreen (fetch riêng, không ai
/// biết ai) — nay HomeManagementScreen VÀ MemberListScreen cùng đọc từ đây, nên số
/// "T.viên" trên Home Card và danh sách chi tiết LUÔN khớp nhau (cùng 1 nguồn dữ liệu).
class HomeProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _homes = [];
  List<Map<String, dynamic>> get homes => _homes;

  bool _isLoadingHomes = false;
  bool get isLoadingHomes => _isLoadingHomes;

  final Map<String, List<HomeMember>> _membersByHome = {};
  final Map<String, bool> _loadingMembers = {};

  List<HomeMember> membersOf(String homeId) => _membersByHome[homeId] ?? const [];
  bool isLoadingMembers(String homeId) => _loadingMembers[homeId] ?? false;

  // ==========================================================================
  // ACTIVE HOME — "Nhà đang được chọn" TOÀN CỤC. Trước đây user quản lý nhiều nhà
  // KHÔNG có cách chuyển nhà: Dashboard fix cứng vào home_id nằm trong JWT lúc đăng nhập.
  // Nay HomeCard gọi setActiveHome() -> notifyListeners() -> DashboardScreen (đã
  // addListener vào provider này) TỰ refetch thiết bị của nhà mới + chuyển tab về Bảng
  // điều khiển. HomeCard KHÔNG tự điều hướng — tách bạch "chọn nhà nào" (data) khỏi
  // "hiển thị màn nào" (UI), Dashboard là nơi duy nhất biết về _selectedIndex của chính nó.
  // ==========================================================================
  static const String _activeHomePrefsKey = 'active_home_id';

  String? _activeHomeId;
  String? get activeHomeId => _activeHomeId;

  /// Object nhà đang active (tra trong [homes] đã fetch) — null nếu chưa xác định hoặc
  /// homes chưa tải xong.
  Map<String, dynamic>? get activeHome {
    if (_activeHomeId == null) return null;
    for (final h in _homes) {
      if (h['home_id'] == _activeHomeId) return h;
    }
    return null;
  }

  /// Đặt "Nhà đang active" — gọi từ HomeCard khi user bấm "Vào điều khiển". Ghi kèm
  /// SharedPreferences để sống qua restart app.
  Future<void> setActiveHome(String homeId) async {
    if (_activeHomeId == homeId) return;
    _activeHomeId = homeId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeHomePrefsKey, homeId);
    } catch (_) {
      // Lỗi ghi local storage không nên chặn tính năng chuyển nhà — bỏ qua an toàn.
    }
  }

  /// Khôi phục "Nhà active" đã lưu lần trước — gọi ĐÚNG 1 LẦN lúc DashboardScreen khởi
  /// tạo. [fallback] dùng khi CHƯA từng chọn (cài mới/lần đầu đăng nhập) — thường là
  /// home_id nằm trong JWT.
  Future<void> restoreActiveHome({String? fallback}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activeHomeId = prefs.getString(_activeHomePrefsKey) ?? fallback;
    } catch (_) {
      _activeHomeId = fallback;
    }
    notifyListeners();
  }

  // ==========================================================================
  // DANH SÁCH NHÀ — nguồn cho Home Card (devices_count/members_count/my_role...)
  // ==========================================================================
  Future<void> fetchHomes() async {
    _isLoadingHomes = true;
    notifyListeners();
    try {
      final response = await _api.authorizedGet('${ApiService.baseUrl}/homes');
      if (response.statusCode != 200) {
        throw HomeApiException(_extractError(response, 'Không tải được danh sách nhà'), response.statusCode);
      }
      final decoded = jsonDecode(response.body);
      List<dynamic> data = [];
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map && decoded['data'] != null) {
        data = decoded['data'] as List<dynamic>;
      }
      _homes = data.map((item) {
        final m = item as Map<String, dynamic>;
        final id = (m['id'] ?? m['home_id'] ?? 'UNKNOWN_ID').toString();
        final rawName = (m['name'] ?? m['home_name'] ?? '').toString();
        return {
          'home_id': id,
          'home_name': rawName.trim().isEmpty ? 'Nhà $id' : rawName,
          'address': m['address'] ?? 'Chưa cập nhật địa chỉ',
          'owner_email': m['owner_email'] ?? m['owner'] ?? 'Chưa xác định',
          'devices_count': m['devices_count'] ?? 0,
          // [SỐ CÔNG TẮC] switches_count do GetHomesHandler (server.go) tính động — tổng
          // endpoint thật (S_{mac}, S_{mac}_N...) của mọi thiết bị trong nhà, KHÔNG phải số MAC.
          'switches_count': m['switches_count'] ?? 0,
          'members_count': m['members_count'] ?? 1,
          'my_role': m['my_role'] ?? 'OWNER',
          'status': m['status'] ?? 'ACCEPTED',
        };
      }).toList();
    } catch (e) {
      if (kDebugMode) print('❌ [HomeProvider] fetchHomes lỗi: $e');
      rethrow;
    } finally {
      _isLoadingHomes = false;
      notifyListeners();
    }
  }

  /// Cập nhật tức thời members_count của MỘT nhà trong bộ nhớ (phản hồi UI nhanh trong
  /// lúc fetchHomes() mạng chậm chạy nền) — KHÔNG thay thế fetchHomes(), chỉ là lớp
  /// "optimistic" tạm thời, fetchHomes() ngay sau đó mới là nguồn sự thật cuối cùng.
  void _bumpMembersCountLocally(String homeId, int delta) {
    final idx = _homes.indexWhere((h) => h['home_id'] == homeId);
    if (idx == -1) return;
    final current = (_homes[idx]['members_count'] as num?)?.toInt() ?? 0;
    _homes[idx] = {..._homes[idx], 'members_count': (current + delta).clamp(0, 1 << 30)};
    notifyListeners();
  }

  // ==========================================================================
  // SỔ THÀNH VIÊN CỦA MỘT NHÀ
  // ==========================================================================
  Future<void> fetchMembers(String homeId) async {
    _loadingMembers[homeId] = true;
    notifyListeners();
    try {
      final response = await _api.authorizedGet('${ApiService.baseUrl}/homes/${Uri.encodeComponent(homeId)}/members');
      if (response.statusCode != 200) {
        throw HomeApiException(_extractError(response, 'Không tải được danh sách thành viên'), response.statusCode);
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawMembers = (decoded['members'] as List<dynamic>? ?? []);
      _membersByHome[homeId] = rawMembers.map((e) => HomeMember.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => _roleRank(b.role).compareTo(_roleRank(a.role)));
    } catch (e) {
      if (kDebugMode) print('❌ [HomeProvider] fetchMembers($homeId) lỗi: $e');
      rethrow;
    } finally {
      _loadingMembers[homeId] = false;
      notifyListeners();
    }
  }

  int _roleRank(String role) {
    switch (role) {
      case 'OWNER':
        return 3;
      case 'ADMIN':
        return 2;
      default:
        return 1;
    }
  }

  /// Thêm thành viên — POST /api/homes/{id}/members {email, role}.
  /// Thành công: refetch sổ thành viên CỦA nhà đó + fetchHomes() để members_count trên
  /// Home Card đồng bộ tuyệt đối (yêu cầu BẮT BUỘC, không chỉ optimistic local).
  /// Thất bại (400/403/404...): ném HomeApiException với ĐÚNG câu Backend trả — UI tự
  /// bắt và hiển thị SnackBar đỏ, KHÔNG có nhánh nào nuốt câm lỗi ở đây.
  Future<void> addMember(String homeId, String email, String role) async {
    final response = await _api.authorizedPost(
      '${ApiService.baseUrl}/homes/${Uri.encodeComponent(homeId)}/members',
      {'email': email.trim(), 'role': role},
    );
    if (response.statusCode != 200) {
      throw HomeApiException(_extractError(response, 'Thêm thành viên thất bại'), response.statusCode);
    }
    _bumpMembersCountLocally(homeId, 1); // phản hồi UI tức thì trong lúc 2 lệnh dưới đang chạy nền
    await Future.wait([
      fetchMembers(homeId),
      fetchHomes(),
    ]);
  }

  /// Gỡ thành viên — DELETE /api/homes/{id}/members?email=...
  /// Cùng nguyên tắc đồng bộ + fail-loud như addMember().
  Future<void> removeMember(String homeId, String email) async {
    final response = await _api.authorizedDelete(
      '${ApiService.baseUrl}/homes/${Uri.encodeComponent(homeId)}/members?email=${Uri.encodeComponent(email)}',
    );
    if (response.statusCode != 200) {
      throw HomeApiException(_extractError(response, 'Xóa thành viên thất bại'), response.statusCode);
    }
    _bumpMembersCountLocally(homeId, -1);
    await Future.wait([
      fetchMembers(homeId),
      fetchHomes(),
    ]);
  }

  /// Đọc field "error" (tiếng Việt, do Go trả) từ body JSON — rơi về [fallback] khi body
  /// không phải JSON hợp lệ (vd lỗi hạ tầng NPM/Cloudflare trả HTML) để KHÔNG BAO GIỜ hiện
  /// chuỗi rác cho người dùng cuối.
  String _extractError(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is String && (decoded['error'] as String).isNotEmpty) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // body không phải JSON — dùng fallback bên dưới
    }
    return '$fallback (HTTP ${response.statusCode})';
  }
}
