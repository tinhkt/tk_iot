import 'camera_model.dart';
import 'imou_camera_model.dart';
import '../services/api_service.dart';

/// [ĐẬP BỎ UI CAMERA — GỘP RTSP + IMOU] Nguồn camera (RTSP LAN vs Imou P2P Cloud) — mọi widget
/// lưới/tile/fullscreen thao tác qua [CameraEntry] chung, KHÔNG cần biết loại cụ thể.
enum CameraProviderType { rtsp, imou }

/// CameraEntry — khuôn DUY NHẤT đại diện 1 camera (bất kể RTSP hay Imou) cho toàn bộ lớp UI mới
/// (CameraTile/CameraGridPageView/CameraDashboardSection/CameraFullscreenGridScreen). Cách lấy
/// URL phát là ĐIỂM KHÁC BIỆT DUY NHẤT giữa 2 loại — gói gọn trong [resolvePreviewUrl]/
/// [resolveFullUrl], phần còn lại (render/overlay/lưới/phân trang) dùng chung 100%.
class CameraEntry {
  final CameraProviderType provider;
  final String homeId;
  final CameraModel? rtspCamera;
  final ImouCameraModel? imouCamera;

  const CameraEntry.rtsp({required this.homeId, required this.rtspCamera}) : provider = CameraProviderType.rtsp, imouCamera = null;
  const CameraEntry.imou({required this.homeId, required this.imouCamera}) : provider = CameraProviderType.imou, rtspCamera = null;

  /// id DUY NHẤT xuyên suốt 2 danh sách gộp lại — tiền tố theo provider vì id (int) của
  /// CameraModel/ImouCameraModel là 2 chuỗi khóa chính RIÊNG BIỆT (Postgres 2 bảng khác nhau,
  /// camera RTSP #3 và camera Imou #3 hoàn toàn không liên quan) — thiếu tiền tố sẽ đụng ID giả.
  String get id => provider == CameraProviderType.rtsp ? 'rtsp_${rtspCamera!.id}' : 'imou_${imouCamera!.id}';

  String get name => provider == CameraProviderType.rtsp ? rtspCamera!.name : imouCamera!.name;

  bool get hasSettings => true; // cả 2 loại đều có (RTSP: sheet Xóa camera; Imou: ImouCameraSettingsScreen)
  bool get hasRecords => provider == CameraProviderType.imou; // RTSP hệ thống chưa có tính năng ghi hình
  bool get hasTalk => false; // đàm thoại 2 chiều CHƯA tồn tại ở cả 2 loại trong toàn hệ thống

  /// URL luồng PHỤ (nhẹ) cho khung xem trước lưới — RTSP có sẵn tức thì (đã ghép sẵn phía
  /// Backend), Imou phải gọi API mỗi lần mở xem (không cache lâu dài, xem getImouLiveURL).
  Future<String> resolvePreviewUrl() async {
    if (provider == CameraProviderType.rtsp) return rtspCamera!.previewUrl;
    final result = await ApiService().getImouLiveURL(homeId, imouCamera!.id);
    if (result == null) return '';
    return result.subHlsUrl.isNotEmpty ? result.subHlsUrl : result.hlsUrl;
  }

  /// URL luồng CHÍNH (nét) cho trang Fullscreen.
  Future<String> resolveFullUrl() async {
    if (provider == CameraProviderType.rtsp) return rtspCamera!.rtspUrl;
    final result = await ApiService().getImouLiveURL(homeId, imouCamera!.id);
    return result?.hlsUrl ?? '';
  }
}
