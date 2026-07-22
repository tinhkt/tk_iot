/// [CAMERA IP — RTSP] Khớp ĐÚNG hình dạng `cameraResponse` phía Backend Go
/// (internal/api/camera_handler.go) — KHÔNG có field mật khẩu nào cả, chỉ có [rtspUrl] đã
/// ghép sẵn (Backend tự giải mã + dựng chuỗi, App không bao giờ thấy mật khẩu thô).
class CameraModel {
  final int id;
  final String name;
  final String ipAddress;
  final int port;
  final String username;
  final String streamPath;
  final String rtspUrl;
  // [HIỆU NĂNG UX — PHẦN 3] Luồng PHỤ (mờ, nhẹ) cho khung xem trước Dashboard — RỖNG nếu
  // camera không cấu hình. Dùng [previewUrl] bên dưới thay vì đọc field này trực tiếp để luôn
  // có fallback đúng đắn về luồng chính.
  final String subRtspUrl;

  const CameraModel({
    required this.id,
    required this.name,
    required this.ipAddress,
    required this.port,
    required this.username,
    required this.streamPath,
    required this.rtspUrl,
    this.subRtspUrl = '',
  });

  /// URL dùng cho khung xem trước Dashboard — luồng phụ nếu có cấu hình, rơi về luồng chính
  /// nếu camera chưa cấu hình luồng phụ (KHÔNG được để trống hẳn, thà nét còn hơn không có gì).
  String get previewUrl => subRtspUrl.isNotEmpty ? subRtspUrl : rtspUrl;

  factory CameraModel.fromJson(Map<String, dynamic> json) {
    return CameraModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      ipAddress: (json['ip_address'] ?? '').toString(),
      port: (json['port'] as num?)?.toInt() ?? 554,
      username: (json['username'] ?? '').toString(),
      streamPath: (json['stream_path'] ?? '').toString(),
      rtspUrl: (json['rtsp_url'] ?? '').toString(),
      subRtspUrl: (json['sub_rtsp_url'] ?? '').toString(),
    );
  }
}

/// [QUÉT LAN ONVIF] Khớp ĐÚNG `onvif.DiscoveredCamera` phía Backend Go
/// (internal/onvif/discovery.go) — chỉ dữ liệu THÔ tìm được qua WS-Discovery + tra thêm best-
/// effort, KHÔNG phải camera đã lưu (không có id/rtsp_url — form Thêm Camera tự điền IP/Tên rồi
/// người dùng hoàn tất Stream Path/tài khoản như luồng nhập tay).
class DiscoveredCameraModel {
  final String ipAddress;
  final String name;
  final String macAddress;
  final String manufacturer;
  final String model;
  final String serialNumber;

  const DiscoveredCameraModel({
    required this.ipAddress,
    required this.name,
    required this.macAddress,
    this.manufacturer = '',
    this.model = '',
    this.serialNumber = '',
  });

  factory DiscoveredCameraModel.fromJson(Map<String, dynamic> json) {
    return DiscoveredCameraModel(
      ipAddress: (json['ip_address'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      macAddress: (json['mac_address'] ?? '').toString(),
      manufacturer: (json['manufacturer'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      serialNumber: (json['serial_number'] ?? '').toString(),
    );
  }
}
