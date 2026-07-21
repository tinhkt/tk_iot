/// [CAMERA P2P — IMOU] Khớp ĐÚNG hình dạng `imouCameraResponse` phía Backend Go
/// (internal/api/imou_camera_handler.go). Khác [CameraModel] (RTSP) — KHÔNG có URL/địa chỉ
/// mạng nào cả, chỉ có [deviceSerial]+[channel] — App tự lấy access-token+PSK NGẮN HẠN qua
/// ApiService.getImouLiveToken() mỗi lần mở xem, không lưu URL cố định như camera RTSP.
class ImouCameraModel {
  final int id;
  final String name;
  final String deviceSerial;
  final int channel;

  const ImouCameraModel({
    required this.id,
    required this.name,
    required this.deviceSerial,
    this.channel = 0,
  });

  factory ImouCameraModel.fromJson(Map<String, dynamic> json) {
    return ImouCameraModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      deviceSerial: (json['device_serial'] ?? '').toString(),
      channel: (json['channel'] as num?)?.toInt() ?? 0,
    );
  }
}
