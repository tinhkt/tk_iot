import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
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
  // [FIX HANDSHAKE 4G] URL nối an toàn: bỏ '/' thừa cuối baseUrl -> không bao giờ '//dashboard'
  static final String _syncUrl = '${ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '')}/dashboard/sync';
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxAttempts = 3;

  /// [FIX HANDSHAKE 4G] MỘT http.Client DÙNG CHUNG, sống suốt vòng đời App: giữ kết nối
  /// keep-alive để TÁI DÙNG phiên TLS đã bắt tay -> các lần gọi sau KHÔNG mở handshake mới.
  /// Nguyên nhân "Connection terminated during handshake" chỉ riêng sync: lúc mở App bắn
  /// đồng loạt login+sync+notifications+homes+weather+MQTT -> nhiều TLS handshake đua nhau
  /// qua NPM/4G, một cái thua cuộc bị rớt (thường là sync). Dùng client chung + retry để
  /// gom về ít kết nối và tự nối lại khi rớt tạm. (KHÔNG close client — dùng lại toàn app.)
  static final http.Client _client = http.Client();

  /// Gọi sync có retry (tối đa 3 lần, backoff tăng dần) chịu lỗi handshake/rớt 4G tạm thời.
  /// HTTP non-200 (401/500...) KHÔNG retry (lỗi thật, retry vô ích).
  Future<DashboardSyncResult> fetch() async {
    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        // [AUTH] Cùng cơ chế token với mọi API khác (SecureStorageService)
        final token = await SecureStorageService.getToken();
        if (token == null || token.isEmpty) {
          debugPrint('SYNC_ERROR: token rỗng (chưa đăng nhập?) — bỏ qua sync');
          return const DashboardSyncResult([], 'Chưa đăng nhập');
        }

        final res = await _client
            .get(
              Uri.parse(_syncUrl),
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
            )
            .timeout(_timeout);

        debugPrint('SYNC_HTTP: status=${res.statusCode}, bytes=${res.bodyBytes.length} (lần $attempt)');

        if (res.statusCode != 200) {
          final preview = res.body.length > 300 ? res.body.substring(0, 300) : res.body;
          debugPrint('SYNC_ERROR: HTTP ${res.statusCode} — body: $preview');
          return DashboardSyncResult(const [], 'Máy chủ báo lỗi (HTTP ${res.statusCode})');
        }

        // utf8.decode(bodyBytes): giải mã đúng charset tên tiếng Việt
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          debugPrint('SYNC_ERROR: body 200 nhưng KHÔNG phải JSON object (${decoded.runtimeType})');
          return const DashboardSyncResult([], 'Dữ liệu máy chủ không hợp lệ');
        }
        final homes = (decoded['homes'] as List?) ?? const [];
        debugPrint('SYNC_OK: nhận ${homes.length} nhà (lần $attempt)');
        return DashboardSyncResult(homes, null);
      } on TimeoutException catch (e) {
        debugPrint('SYNC_ERROR: TIMEOUT sau ${_timeout.inSeconds}s (lần $attempt): $e');
        if (attempt >= _maxAttempts) return const DashboardSyncResult([], 'Mạng chậm, vui lòng thử lại');
      } on FormatException catch (e) {
        debugPrint('SYNC_ERROR: FormatException (JSON hỏng/cụt) (lần $attempt): $e');
        if (attempt >= _maxAttempts) return const DashboardSyncResult([], 'Dữ liệu máy chủ bị lỗi, thử lại');
      } catch (e) {
        // HandshakeException / Connection reset -> lỗi tầng TLS/mạng, retry với kết nối mới
        debugPrint('SYNC_ERROR: ${e.runtimeType} (lần $attempt): $e');
        if (attempt >= _maxAttempts) return const DashboardSyncResult([], 'Không kết nối được máy chủ');
      }
      // Backoff tăng dần (400ms, 800ms) cho radio 4G kịp ổn định trước lần thử sau
      await Future.delayed(Duration(milliseconds: 400 * attempt));
    }
    return const DashboardSyncResult([], 'Không kết nối được máy chủ');
  }
}
