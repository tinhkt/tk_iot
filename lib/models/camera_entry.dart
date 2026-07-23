import 'camera_model.dart';
import 'imou_camera_model.dart';
import '../services/api_service.dart';

/// [ĐẬP BỎ UI CAMERA — GỘP RTSP + IMOU] Nguồn camera (RTSP LAN vs Imou P2P Cloud) — mọi widget
/// lưới/tile/fullscreen thao tác qua [CameraEntry] chung, KHÔNG cần biết loại cụ thể.
enum CameraProviderType { rtsp, imou }

/// CameraEntry — khuôn DUY NHẤT đại diện 1 camera (bất kể RTSP hay Imou) cho toàn bộ lớp UI mới
/// (CameraTile/CameraGridPageView/CameraDashboardSection/CameraFullscreenGridScreen). Cách lấy
/// URL phát là ĐIỂM KHÁC BIỆT DUY NHẤT giữa 2 loại — gói gọn trong [resolvePreviewUrl]/
/// [resolveLiveUrls], phần còn lại (render/overlay/lưới/phân trang) dùng chung 100%.
class CameraEntry {
  final CameraProviderType provider;
  final String homeId;
  final String homeName;
  final CameraModel? rtspCamera;
  final ImouCameraModel? imouCamera;

  const CameraEntry.rtsp({required this.homeId, this.homeName = '', required this.rtspCamera}) : provider = CameraProviderType.rtsp, imouCamera = null;
  const CameraEntry.imou({required this.homeId, this.homeName = '', required this.imouCamera}) : provider = CameraProviderType.imou, rtspCamera = null;

  /// id DUY NHẤT xuyên suốt 2 danh sách gộp lại — tiền tố theo provider vì id (int) của
  /// CameraModel/ImouCameraModel là 2 chuỗi khóa chính RIÊNG BIỆT (Postgres 2 bảng khác nhau,
  /// camera RTSP #3 và camera Imou #3 hoàn toàn không liên quan) — thiếu tiền tố sẽ đụng ID giả.
  String get id => provider == CameraProviderType.rtsp ? 'rtsp_${rtspCamera!.id}' : 'imou_${imouCamera!.id}';

  String get name => provider == CameraProviderType.rtsp ? rtspCamera!.name : imouCamera!.name;

  bool get hasSettings => true; // cả 2 loại đều có (RTSP: sheet Xóa camera; Imou: ImouCameraSettingsScreen)
  bool get hasRecords => provider == CameraProviderType.imou; // RTSP hệ thống chưa có tính năng ghi hình
  bool get hasEvents => provider == CameraProviderType.imou; // getAlarmMessage — CHỈ Imou có API sự kiện thật
  bool get hasPTZ => provider == CameraProviderType.imou; // RTSP hệ thống chưa tích hợp PTZ
  bool get hasTalk => false; // đàm thoại 2 chiều CHƯA tồn tại ở cả 2 loại trong toàn hệ thống

  /// URL luồng PHỤ (nhẹ) cho khung xem trước lưới — RTSP có sẵn tức thì (đã ghép sẵn phía
  /// Backend), Imou phải gọi API mỗi lần mở xem (không cache lâu dài, xem getImouLiveURL).
  Future<String> resolvePreviewUrl() async {
    if (provider == CameraProviderType.rtsp) return rtspCamera!.previewUrl;
    final result = await ApiService().getImouLiveURL(homeId, imouCamera!.id);
    if (result == null) return '';
    return result.subHlsUrl.isNotEmpty ? result.subHlsUrl : result.hlsUrl;
  }

  /// [MÀN CHI TIẾT CAMERA — chọn chất lượng HD/SD] Lấy CẢ 2 URL (nét/nhẹ) trong 1 lần gọi API —
  /// nút chuyển đổi chất lượng chỉ đổi URL đang phát TẠI CHỖ (không gọi lại API lần 2, tránh spam
  /// getImouLiveURL — xem Trụ cột 4 rà soát hiệu năng). RTSP không có 2 luồng riêng — trả cùng 1
  /// URL cho cả `hd`/`sd`, màn hình tự ẩn nút chọn chất lượng khi 2 giá trị giống hệt nhau.
  Future<({String hd, String sd})> resolveLiveUrls() async {
    if (provider == CameraProviderType.rtsp) {
      final url = rtspCamera!.rtspUrl;
      return (hd: url, sd: url);
    }
    final result = await ApiService().getImouLiveURL(homeId, imouCamera!.id);
    if (result == null) return (hd: '', sd: '');
    final hd = result.hlsUrl;
    final sd = result.subHlsUrl.isNotEmpty ? result.subHlsUrl : result.hlsUrl;
    return (hd: hd, sd: sd);
  }
}
