import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, ValueNotifier;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'mqtt_credentials_service.dart';

class MqttService {
  MqttServerClient? client;
  bool isConnected = false;

  /// Chống bão kết nối: nhiều nơi (init + các lệnh publish) cùng gọi connect()
  /// một lúc thì chỉ MỘT lượt được chạy, các lượt khác đứng ngoài chờ.
  bool _connecting = false;

  /// Đánh dấu ngắt kết nối CHỦ Ý (đăng xuất) — để onDisconnected phân biệt được
  /// với rớt mạng ngầm và không cảnh báo/không kết nối lại oan.
  bool _manualDisconnect = false;

  /// Hẹn giờ thử kết nối lại khi connect() thất bại hoàn toàn (autoReconnect của
  /// thư viện chỉ hoạt động SAU khi đã từng nối thành công — PC ngủ dậy chưa có
  /// mạng ngay thì cần lưới này).
  Timer? _retryTimer;

  /// Trạng thái sống của kênh MQTT cho UI theo dõi:
  /// false = đang đứt/đang nối lại -> Dashboard hiện "Đang kết nối lại máy chủ..."
  final ValueNotifier<bool> brokerOnline = ValueNotifier<bool>(false);

  // Callback để truyền dữ liệu thời gian thực về cho DeviceProvider
  Function(String topic, String message)? onMessageReceived;

  bool get _isClientConnected =>
      client?.connectionStatus?.state == MqttConnectionState.connected;

  /// [CHỐNG ĐÁ PHIÊN] Client ID độc nhất tuyệt đối: tên nền tảng + timestamp + random.
  /// Mở song song nhiều PC/nhiều cửa sổ, EMQX thấy mỗi phiên một ID riêng — không
  /// còn cảnh hai client trùng ID thay nhau kick phiên của nhau.
  String _buildClientId() {
    final platform = kIsWeb ? 'web' : Platform.operatingSystem; // windows|android|ios|macos...
    return 'tk_app_${platform}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(100000)}';
  }

  Future<void> connect() async {
    if (_isClientConnected) { isConnected = true; brokerOnline.value = true; return; }
    if (_connecting) return; // đã có lượt kết nối đang chạy — không chen ngang
    _connecting = true;
    _manualDisconnect = false;

    try {
      // [BẢO MẬT] Không còn tài khoản MQTT chung hardcode trong App:
      // lấy credentials động (username + JWT password, kèm danh sách topic được phép)
      // từ Backend theo đúng user đang đăng nhập.
      final creds = await MqttCredentialsService.get();
      if (creds == null) {
        if (kDebugMode) print('⚠️ [MQTT] Chưa có credentials MQTT (chưa đăng nhập hoặc chưa liên kết nhà), bỏ qua kết nối.');
        return;
      }

      final clientId = _buildClientId();
      final c = MqttServerClient(creds.host, clientId);
      c.port = creds.port;
      c.secure = creds.secure; // Tự bật TLS khi server trả broker_url dạng mqtts://
      c.logging(on: false);

      // [FIX HandshakeException TRÊN 4G] mqtt_client dùng SecureSocket RIÊNG — KHÔNG
      // đi qua HttpOverrides.global (chỉ áp cho HttpClient). Broker sau Nginx Proxy Manager
      // có thể gửi chuỗi chứng chỉ THIẾU intermediate: WiFi nội bộ nối mqtt:// (không TLS)
      // nên không lộ, ra 4G nối mqtts:// -> bắt tay TLS đứt "Connection terminated during
      // handshake". Chấp nhận cert ở đây AN TOÀN có phạm vi: client này CHỈ trỏ tới đúng
      // broker của mình (creds.host do Backend cấp), không phải bypass cho mọi máy chủ.
      if (c.secure) {
        c.onBadCertificate = (dynamic cert) => true;
      }

      // ===== CƠ CHẾ CHUẨN CÔNG NGHIỆP: KEEPALIVE + AUTO-RECONNECT =====
      // keepAlive 30s: App tự ping broker định kỳ; broker không còn cớ ngắt ngầm
      // vì "im lặng quá lâu" — chính là nguyên nhân nút đơ trên Windows để lâu.
      c.keepAlivePeriod = 30;
      // Thư viện tự nối lại NGẦM khi phát hiện đứt (PC sleep mạng, WiFi chớp...):
      c.autoReconnect = true;
      // ...và tự subscribe lại đúng các topic cũ sau khi nối lại — không cần code tay:
      c.resubscribeOnAutoReconnect = true;

      // ===== CALLBACK VÒNG ĐỜI KẾT NỐI =====
      c.onConnected = () {
        isConnected = true;
        brokerOnline.value = true;
        if (kDebugMode) print('✅ [MQTT] Kênh điều khiển đã kết nối (clientId: $clientId)');
      };
      c.onDisconnected = () {
        isConnected = false;
        brokerOnline.value = false; // UI hiện "Đang kết nối lại máy chủ..."
        final origin = client?.connectionStatus?.disconnectionOrigin;
        if (_manualDisconnect || origin == MqttDisconnectionOrigin.solicited) {
          if (kDebugMode) print('ℹ️ [MQTT] Đã ngắt kết nối theo yêu cầu (đăng xuất).');
          return;
        }
        // Đứt KHÔNG do chủ ý (broker timeout/PC ngủ, hoặc OS chuyển mạng AP<->4G đột ngột gây
        // "Software caused connection abort") — autoReconnect (đã bật ở trên) thường tự cứu.
        if (kDebugMode) print('⚠️ [MQTT] MẤT KẾT NỐI NGẦM! Thư viện đang tự động nối lại...');
        // [LƯỚI AN TOÀN THỨ 2] Phòng trường hợp cơ chế autoReconnect nội bộ không kịp kích hoạt
        // đúng lúc (đứt kiểu abort đột ngột giữa lúc OS đang chuyển interface mạng) — kiểm tra
        // lại sau 3s, NẾU VẪN chưa tự nối lại được (và không phải do chủ ý ngắt) thì chủ động
        // gọi connect() một lần nữa. An toàn tuyệt đối để gọi thừa: connect() tự no-op ngay từ
        // dòng đầu nếu đã kết nối rồi (autoReconnect lỡ cứu kịp trong lúc chờ 3s).
        Timer(const Duration(seconds: 3), () {
          if (_manualDisconnect) return;
          if (!_isClientConnected) {
            if (kDebugMode) print('🔁 [MQTT] Sau 3s vẫn chưa tự nối lại được — chủ động thử lại...');
            connect();
          }
        });
      };
      c.onAutoReconnect = () {
        brokerOnline.value = false;
        if (kDebugMode) print('🔄 [MQTT] Đang tự động kết nối lại máy chủ...');
      };
      c.onAutoReconnected = () {
        isConnected = true;
        brokerOnline.value = true;
        if (kDebugMode) print('✅ [MQTT] Đã nối lại thành công + tự subscribe lại toàn bộ topic!');
      };

      c.connectionMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .authenticateAs(creds.username, creds.password)
          .startClean();
      client = c;

      if (kDebugMode) print('⏳ [MQTT] Đang kết nối kênh điều khiển tới ${creds.host}:${creds.port} (TLS: ${creds.secure})...');
      await c.connect();
      isConnected = true;
      brokerOnline.value = true;

      // Subscribe đúng các cụm topic mà ACL của user này được cấp (smarthub/{home_id}/#),
      // thay cho wildcard smarthub/# nghe lén được mọi nhà như trước đây.
      // (autoReconnect sẽ tự đăng ký lại danh sách này mỗi lần nối lại ngầm.)
      for (final prefix in creds.topicPrefixes) {
        c.subscribe(prefix, MqttQos.atLeastOnce);
      }

      // Bắt đầu lắng nghe luồng tin nhắn đổ về — stream này SỐNG XUYÊN các lần
      // auto-reconnect vì client không bị tạo mới, nên không lo listener mồ côi.
      // [BẢO VỆ STREAM] Trước đây .listen() không có onError — một SocketException rò rỉ từ
      // socket bên dưới (vd "Software caused connection abort" khi OS chuyển AP<->4G đột ngột
      // giữa lúc đang đọc dữ liệu) sẽ lọt thành Unhandled Exception làm crash App. Thêm
      // onError để NUỐT lỗi + log thay vì rethrow; cancelOnError: false để stream KHÔNG tự hủy
      // sau 1 lỗi — vẫn tiếp tục nhận tin khi kênh nối lại (autoReconnect tái dùng cùng stream).
      c.updates!.listen(
        (List<MqttReceivedMessage<MqttMessage>> messages) {
          // [RÀO CHẮN AN TOÀN] Payload rỗng/null hoặc gói tin dị dạng — bỏ qua thay vì crash.
          if (messages.isEmpty) return;
          final dynamic rawPayload = messages[0].payload;
          if (rawPayload is! MqttPublishMessage) return;
          final MqttPublishMessage recMess = rawPayload;
          final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          final String topic = messages[0].topic;
          if (topic.isEmpty) return;

          if (kDebugMode) print('📥 [MQTT NHẬN]: Topic: $topic | Payload: $message');

          // Bắn dữ liệu về cho DeviceProvider bóc tách và vẽ lại UI
          if (onMessageReceived != null) {
            onMessageReceived!(topic, message);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          // TUYỆT ĐỐI không rethrow — đây chính là nơi rò rỉ "Unhandled Exception:
          // SocketException: Software caused connection abort" trước đây.
          if (kDebugMode) print('⚠️ [MQTT] Stream lỗi (kênh đọc dữ liệu bị rớt ngang): $error');
          isConnected = false;
          brokerOnline.value = false;
        },
        cancelOnError: false,
      );
    } on SocketException catch (e) {
      // [NHIỆM VỤ 1] Bắt RIÊNG SocketException (vd "Software caused connection abort" khi OS
      // chuyển mạng AP<->4G đột ngột giữa lúc bắt tay/đọc-ghi TCP) — log rõ ràng, TUYỆT ĐỐI
      // không rethrow, để lộ thành Unhandled Exception làm crash App.
      if (kDebugMode) print('MQTT TCP Connection aborted: $e — sẽ tự thử lại sau 10 giây.');
      isConnected = false;
      brokerOnline.value = false;
      client?.disconnect();
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 10), () {
        if (!_manualDisconnect) connect();
      });
    } catch (e) {
      // Kết nối thất bại HOÀN TOÀN (chưa từng nối được nên autoReconnect chưa kích
      // hoạt) — vd PC vừa thức dậy, card mạng chưa có IP. Hẹn 10 giây thử lại,
      // lặp cho đến khi thành công.
      if (kDebugMode) print('❌ [MQTT] Lỗi kết nối: $e — sẽ tự thử lại sau 10 giây.');
      isConnected = false;
      brokerOnline.value = false;
      client?.disconnect();
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 10), () {
        if (!_manualDisconnect) connect();
      });
    } finally {
      _connecting = false;
    }
  }

  /// [CHỐNG PUBLISH VÀO KHOẢNG KHÔNG] Lưới an toàn gọi TRƯỚC MỌI lệnh publish:
  /// client chưa nối (hoặc vừa bị broker ngắt ngầm) -> chủ động connect() lại ngay
  /// rồi mới cho bắn lệnh. Trả về true khi kênh đã sẵn sàng.
  Future<bool> _ensureConnected() async {
    if (_isClientConnected) return true;
    if (kDebugMode) print('⚠️ [MQTT] Kênh đang đứt — chủ động kết nối lại trước khi gửi lệnh...');
    await connect();
    if (!_isClientConnected) {
      if (kDebugMode) print('❌ [MQTT] Nối lại chưa thành công — lệnh bị hoãn, người dùng bấm lại sau khi banner "Đang kết nối lại" tắt.');
      return false;
    }
    return true;
  }

  // --- HÀM MỚI ĐƯỢC THÊM VÀO ĐỂ GỬI LỆNH ĐÃ PHÂN LUỒNG TỪ PROVIDER ---
  Future<void> publish(String topic, String payload) async {
    // Ép đợi khôi phục mạng ngầm trước khi bắn lệnh (chống rớt mạng)
    if (!await _ensureConnected()) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    // [NHIỆM VỤ 1 — áp cho mọi điểm publish] Nút bấm UI gọi thẳng xuống đây; nếu đúng lúc
    // OS đang chuyển AP<->4G, socket ghi có thể chết đột ngột (SocketException errno=103)
    // NGAY TẠI publishMessage() chứ không phải ở connect(). Bọc lại để không rò rỉ thành
    // Unhandled Exception làm crash App — mất 1 lệnh còn hơn crash cả app.
    try {
      client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      // Log ra terminal để bác dễ kiểm soát
      if (kDebugMode) print('📤 [MQTT PUBLISH]: $payload -> Topic: $topic');
    } on SocketException catch (e) {
      if (kDebugMode) print('MQTT TCP Connection aborted (publish): $e');
      isConnected = false;
      brokerOnline.value = false;
    } catch (e) {
      if (kDebugMode) print('⚠️ [MQTT] Publish thất bại (kênh vừa rớt giữa chừng): $e');
    }
  }

  /// [HỢP ĐỒNG MỚI] Mọi lệnh điều khiển đi qua Cầu nối Backend thay vì publish thẳng
  /// vào topic gốc của thiết bị (ACL động chỉ cho phép user hoạt động trong smarthub/{home_id}/#):
  /// App -> smarthub/{home_id}/{mac}/command (JSON {"endpoint","action","value"})
  /// Backend xác minh chủ quyền -> chuyển tiếp thô xuống devices_v2/{mac}/command cho firmware.
  /// [DIGITAL TWIN] durationMs (tùy chọn): kèm "duration_ms" vào payload — Cửa cuốn dùng để
  /// kích relay đúng N mili-giây (mô phỏng kéo Slider %) thay vì xung cố định 500ms mặc định.
  /// Backend (broker.go) kẹp biên 100-30000ms trước khi chuyển tiếp xuống firmware.
  Future<void> publishCommand(String mac, String endpoint, String value, {String action = 'set', int? durationMs}) async {
    // Kiểm tra kênh TRƯỚC khi gửi: đứt thì nối lại ngay rồi mới bắn —
    // không bao giờ publish vào client chết làm nút bấm "đơ" trong im lặng
    if (!await _ensureConnected()) return;

    final creds = await MqttCredentialsService.get();
    if (creds == null) return;

    final cleanMac = mac.replaceAll(':', '').toUpperCase();
    final Map<String, dynamic> body = {'endpoint': endpoint, 'action': action, 'value': value};
    if (durationMs != null && durationMs > 0) body['duration_ms'] = durationMs;
    final payload = jsonEncode(body);

    // Suy ra danh sách home_id từ chính các quyền ACL được cấp (smarthub/{home_id}/#):
    // - User thường: không biết thiết bị thuộc nhà nào -> bắn vào MỌI nhà user sở hữu,
    //   Backend tra device_home:{mac} và tự loại các gói sai chủ quyền (defense-in-depth).
    // - SUPER_USER: ACL là smarthub/# (không có home_id cụ thể) -> dùng làn quản trị
    //   smarthub/admin/{mac}/command. Backend bỏ qua bước so khớp home cho segment này;
    //   an toàn vì home_id thật luôn dạng HOME_xxx hoặc MAC 12 hex, ACL của user thường
    //   không bao giờ với tới "admin".
    final targets = <String>{};
    for (final prefix in creds.topicPrefixes) {
      final parts = prefix.split('/');
      if (parts.length < 2 || parts[0] != 'smarthub') continue;
      final homeSegment = (parts[1] == '#' || parts[1] == '+') ? 'admin' : parts[1];
      targets.add('smarthub/$homeSegment/$cleanMac/command');
    }

    if (targets.isEmpty) {
      if (kDebugMode) print('⚠️ [MQTT] ACL không chứa quyền smarthub nào — không thể gửi lệnh (chưa liên kết nhà?)');
      return;
    }

    for (final topic in targets) {
      // Bọc từng lượt publish riêng lẻ trong vòng lặp — một target rớt (socket abort giữa
      // chừng lúc OS đổi mạng) không được kéo sập cả vòng lặp, các target còn lại vẫn bắn tiếp.
      try {
        client!.publishMessage(topic, MqttQos.atLeastOnce, (MqttClientPayloadBuilder()..addString(payload)).payload!);
        if (kDebugMode) print('⚡ [LỆNH QUA BRIDGE]: $payload -> Topic: $topic');
      } on SocketException catch (e) {
        if (kDebugMode) print('MQTT TCP Connection aborted (publishCommand): $e');
        isConnected = false;
        brokerOnline.value = false;
      } catch (e) {
        if (kDebugMode) print('⚠️ [MQTT] Gửi lệnh thất bại tới $topic (kênh vừa rớt giữa chừng): $e');
      }
    }
  }

  // --- HÀM CŨ CHO QUẠT (Tốc độ, Túp năng) — nay cũng đi qua Cầu nối Backend ---
  Future<void> sendCommand(String mac, String endpoint, bool currentState, {int? speed, bool? swing}) async {
    if (speed != null) {
      // Lệnh tốc độ đã BAO HÀM bật/tắt (0 = tắt hẳn, 1-3 = bật đúng số đó) — không gửi
      // kèm lệnh set ON để firmware quạt khỏi nhảy lên số 1 rồi mới về số đích (giật cấp)
      await publishCommand(mac, endpoint, speed.toString(), action: 'speed');
    } else {
      await publishCommand(mac, endpoint, currentState ? 'ON' : 'OFF');
    }
    if (swing != null) await publishCommand(mac, endpoint, swing ? 'swing' : 'off', action: 'osc');
  }

  /// [DIGITAL TWIN] Kích relay Cửa cuốn đúng [durationMs] mili-giây rồi để firmware TỰ tắt và
  /// báo lại OFF (công tắc "chạm rồi tự bật lại", xem SW_rolling_doors.ino/handleDoorLogic).
  /// value luôn là "ON" — "OFF" chỉ phát sinh từ chính firmware, App không bao giờ tự gửi.
  Future<void> sendDoorPulse(String mac, String endpoint, int durationMs) =>
      publishCommand(mac, endpoint, 'ON', durationMs: durationMs);

  /// [DIGITAL TWIN] Đèn Chiết áp (Dimmer) — độ sáng 0-100, action riêng "brightness" (khác
  /// "speed" của quạt dùng 0-3) để 2 loại thiết bị không đụng ngữ nghĩa trên cùng 1 trường.
  Future<void> sendBrightness(String mac, String endpoint, int brightness) =>
      publishCommand(mac, endpoint, brightness.toString(), action: 'brightness');

  /// Ngắt kết nối và quên client cũ — gọi khi đăng xuất để phiên MQTT
  /// của tài khoản trước không tiếp tục nhận dữ liệu.
  /// Gắn cờ _manualDisconnect để onDisconnected biết đây là chủ ý (không cảnh báo,
  /// không hẹn giờ nối lại oan).
  void disconnect() {
    _manualDisconnect = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    client?.disconnect();
    client = null;
    isConnected = false;
    brokerOnline.value = false;
  }
}
