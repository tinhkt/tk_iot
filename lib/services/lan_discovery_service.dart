import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;

/// Một thiết bị TK_IOT tìm thấy qua quét UDP LAN.
class LanDevice {
  final String mac;        // MAC đã chuẩn hóa (bỏ ":", HOA) — khóa khử trùng
  final String ip;         // IP LAN của thiết bị
  final String name;       // tên gợi ý của thiết bị
  final String deviceType; // dòng thiết bị (device_type / fw_type / category do firmware khai)

  const LanDevice({required this.mac, required this.ip, required this.name, required this.deviceType});
}

/// Service quét tìm thiết bị trong mạng LAN bằng UDP Broadcast (dart:io thuần,
/// KHÔNG cần package ngoài). Vòng đời:
///   1. start()  -> mở socket, phát {"cmd":"discovery"} tới 255.255.255.255:port,
///                  lắng nghe phản hồi, phát lại mỗi giây (UDP dễ rớt gói).
///   2. devices  -> Stream danh sách thiết bị (đã khử trùng theo MAC), phát mỗi khi có tin mới.
///   3. sau `timeout` (mặc định 5s) tự dừng (đóng socket) và phát danh sách cuối.
///   4. stop()/dispose() -> đóng socket + hủy mọi timer (gọi khi tắt màn hình quét).
///
/// MỌI thao tác socket được bọc try-catch để một gói rác/lỗi mạng không làm sập luồng,
/// và socket LUÔN được đóng (kể cả khi lỗi) — không rò tài nguyên.
class LanDiscoveryService {
  /// Cổng UDP mà firmware ESP lắng nghe — KHỚP DISCOVERY_UDP_PORT bên firmware.
  static const int discoveryPort = 8266;

  RawDatagramSocket? _socket;
  Timer? _retryTimer;
  Timer? _timeoutTimer;
  bool _scanning = false;

  final Map<String, LanDevice> _found = {};
  final StreamController<List<LanDevice>> _controller = StreamController<List<LanDevice>>.broadcast();

  /// Luồng danh sách thiết bị (đã khử trùng) — UI lắng nghe để vẽ lại.
  Stream<List<LanDevice>> get devices => _controller.stream;

  /// Đang quét hay đã dừng (UI dựa vào để hiện spinner / nút "Thử lại").
  bool get isScanning => _scanning;

  /// Ảnh chụp danh sách hiện tại (dùng cho lần dựng UI đầu tiên trước khi stream phát).
  List<LanDevice> get currentDevices => _found.values.toList();

  /// Bắt đầu một lượt quét mới. An toàn để gọi lại (tự dọn lượt cũ trước).
  Future<void> start({Duration timeout = const Duration(seconds: 5)}) async {
    await stop();          // dọn sạch socket/timer của lượt trước (nếu có)
    _found.clear();
    _scanning = true;
    _emit();               // phát danh sách rỗng + trạng thái đang quét cho UI

    try {
      // Bind cổng bất kỳ (0) trên mọi IPv4 để vừa gửi vừa nhận trên cùng socket
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true; // BẮT BUỘC mới gửi được tới địa chỉ broadcast
      _socket = socket;

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = socket.receive();
          if (dg != null) _handleReply(dg);
        }
      }, onError: (e) {
        if (kDebugMode) print('❌ [LAN SCAN] Lỗi socket: $e');
      });

      final List<int> payload = utf8.encode(jsonEncode({'cmd': 'discovery'}));
      final InternetAddress broadcast = InternetAddress('255.255.255.255');

      // Phát ngay, rồi nhắc lại mỗi giây trong suốt cửa sổ quét (UDP không đảm bảo tới nơi)
      _safeSend(payload, broadcast);
      _retryTimer = Timer.periodic(const Duration(seconds: 1), (_) => _safeSend(payload, broadcast));

      // Hết thời gian -> dừng, giữ nguyên kết quả đã có
      _timeoutTimer = Timer(timeout, stop);
    } catch (e) {
      if (kDebugMode) print('❌ [LAN SCAN] Không mở được UDP socket: $e');
      await stop(); // lỗi mở socket -> đóng gọn, phát trạng thái đã dừng
    }
  }

  void _safeSend(List<int> payload, InternetAddress broadcast) {
    try {
      _socket?.send(payload, broadcast, discoveryPort);
    } catch (e) {
      if (kDebugMode) print('⚠️ [LAN SCAN] Lỗi gửi broadcast: $e');
    }
  }

  void _handleReply(Datagram dg) {
    try {
      final decoded = jsonDecode(utf8.decode(dg.data));
      if (decoded is! Map) return;

      final String mac = (decoded['mac'] ?? '').toString().replaceAll(':', '').toUpperCase();
      if (mac.isEmpty) return; // gói không phải phản hồi thiết bị (vd chính gói broadcast của ta)

      // KHỬ TRÙNG theo MAC: thiết bị trả lời nhiều lần vẫn chỉ 1 mục
      _found[mac] = LanDevice(
        mac: mac,
        ip: (decoded['ip'] ?? dg.address.address).toString(),
        name: (decoded['name'] ?? 'Thiết bị $mac').toString(),
        // firmware TK_IOT khai fw_type/category; chấp nhận cả device_type để tương thích chuẩn chung
        deviceType: (decoded['device_type'] ?? decoded['fw_type'] ?? decoded['category'] ?? '').toString(),
      );
      _emit();
    } catch (_) {
      // Gói rác / không phải JSON -> bỏ qua, không làm sập luồng quét
    }
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_found.values.toList());
  }

  /// Dừng quét: đóng socket + hủy timer. Idempotent (gọi nhiều lần vô hại).
  Future<void> stop() async {
    _retryTimer?.cancel();
    _timeoutTimer?.cancel();
    _retryTimer = null;
    _timeoutTimer = null;
    _socket?.close();
    _socket = null;
    if (_scanning) {
      _scanning = false;
      _emit(); // báo UI đã dừng (kèm danh sách cuối cùng)
    }
  }

  /// Giải phóng hoàn toàn — gọi trong dispose() của màn hình quét.
  Future<void> dispose() async {
    await stop();
    if (!_controller.isClosed) await _controller.close();
  }
}
