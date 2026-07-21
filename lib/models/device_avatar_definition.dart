import 'package:flutter/widgets.dart';

/// Trạng thái runtime của MỘT thiết bị truyền vào [DeviceAvatarDefinition.buildWidget] — tách
/// biệt hoàn toàn khỏi cấu trúc dữ liệu Backend thật (xem DeviceState/SubDevice ở
/// device_state.dart). Avatar chỉ cần biết vài trục phổ biến nhất; category nào không dùng trục
/// nào thì cứ để null (vd công tắc không có speed/value).
/// [Bước 2 bổ sung `metric`] Một số avatar (Ổ cắm thông minh) cần hiển thị một SỐ ĐỌC CHỈ-ĐỌC
/// không phải do người dùng chỉnh (vd công suất tiêu thụ W) — khác bản chất với `value` (người
/// dùng CHỈNH được qua onChange). Đặt tên chung "metric" (không riêng "watt") để tái dùng được
/// cho category tương lai khác (nhiệt độ cảm biến, độ ẩm...) mà không cần thêm field mới.
/// [Bước 3 bổ sung `metricHistory`] HVAC cần vẽ biểu đồ nhiệt/độ ẩm mini — khác bản chất với
/// `metric` (một điểm CHỈ-ĐỌC tại thời điểm hiện tại): đây là CHUỖI các điểm CHỈ-ĐỌC gần nhất.
/// null nếu Dashboard CHƯA nối dữ liệu lịch sử thật — avatar phải tự vẽ placeholder trung tính
/// (đường đứt nét phẳng), TUYỆT ĐỐI không bịa số liệu giả trông như dữ liệu thật (đánh lừa người
/// vận hành BMS).
typedef DeviceAvatarState = ({
  bool isOn,
  int? speed, // vd tốc độ quạt theo nấc (1-3), tầng hiện tại của thang máy
  double? value, // vd % độ mở cửa cuốn/rèm, % độ sáng đèn, góc màu (hue 0-360), nhiệt độ đặt (°C), tầng đang gọi
  double? metric, // số đọc CHỈ-ĐỌC tại 1 thời điểm, vd công suất tiêu thụ (W), độ ẩm (%RH) — không có onChange tương ứng
  List<double>? metricHistory, // chuỗi số đọc CHỈ-ĐỌC gần nhất để vẽ sparkline mini, vd 12 điểm nhiệt độ gần nhất
  bool isOffline,
});

/// Bó sự kiện avatar bắn ngược lên tầng gọi (Dashboard) — buildWidget KHÔNG tự gọi API/MQTT,
/// chỉ vẽ UI + báo sự kiện qua đây, giữ đúng nguyên tắc tách Data khỏi UI.
typedef DeviceAvatarCallbacks = ({
  ValueChanged<bool> onToggle, // bật/tắt
  void Function(String field, num value) onChange, // đổi speed/value/... theo tên field
});

typedef DeviceAvatarBuilder = Widget Function(
  BuildContext context,
  DeviceAvatarState state,
  DeviceAvatarCallbacks callbacks,
);

/// Định nghĩa "hình dáng" (blueprint) của một loại thiết bị trong kho avatarLibrary — thuần dữ
/// liệu (id/name/category/kích thước lưới) cộng một hàm dựng UI, không tự giữ trạng thái/gọi API.
class DeviceAvatarDefinition {
  final String id;
  final String name;
  final String category;
  final int gridSpanX; // số cột chiếm trên grid
  final int gridSpanY; // số hàng chiếm trên grid
  final DeviceAvatarBuilder buildWidget;

  const DeviceAvatarDefinition({
    required this.id,
    required this.name,
    required this.category,
    this.gridSpanX = 1,
    this.gridSpanY = 1,
    required this.buildWidget,
  });
}
