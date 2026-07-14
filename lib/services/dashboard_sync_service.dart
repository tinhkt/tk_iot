import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

import 'api_service.dart';
import 'secure_storage_service.dart';

/// Kết quả gọi single-fetch: [homes] là mảng nhà (mỗi nhà có rooms + devices lồng sẵn),
/// [error] != null là câu báo lỗi thân thiện (timeout/mạng) để UI hiện SnackBar, KHÔNG sập.
class DashboardSyncResult {
  final List<dynamic> homes;
  final String? error;
  const DashboardSyncResult(this.homes, this.error);
}

/// DashboardSyncService — SINGLE FETCH chống N+1: gọi DUY NHẤT GET /api/dashboard/sync
/// thay cho chuỗi "lấy Homes -> loop lấy Devices từng nhà". Có timeout 10s: mạng yếu thì
/// trả lỗi "Mạng chậm" chứ không treo App vô tận.
class DashboardSyncService {
  static const String _apiBase = ApiService.baseUrl;
  static const Duration _timeout = Duration(seconds: 10);

  Future<DashboardSyncResult> fetch() async {
    try {
      final token = await SecureStorageService.getToken();
      final res = await http
          .get(
            Uri.parse('$_apiBase/dashboard/sync'),
            headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          )
          .timeout(_timeout); // treo quá 10s -> ném TimeoutException, bắt bên dưới

      if (res.statusCode != 200) {
        return DashboardSyncResult(const [], 'Máy chủ báo lỗi (HTTP ${res.statusCode})');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return DashboardSyncResult((body['homes'] as List?) ?? const [], null);
    } on TimeoutException {
      if (kDebugMode) print('⏳ [SYNC] Quá hạn 10s — mạng chậm');
      return const DashboardSyncResult([], 'Mạng chậm, vui lòng thử lại');
    } catch (e) {
      if (kDebugMode) print('❌ [SYNC] Lỗi tải dashboard: $e');
      return const DashboardSyncResult([], 'Không kết nối được máy chủ');
    }
  }
}
