import 'device_avatar_definition.dart';
import '../widgets/avatars/switch_avatars.dart';
import '../widgets/avatars/lighting_avatars.dart';
import '../widgets/avatars/lighting_extra_avatars.dart';
import '../widgets/avatars/climate_avatars.dart';
import '../widgets/avatars/climate_extra_avatars.dart';
import '../widgets/avatars/security_avatars.dart';
import '../widgets/avatars/access_control_avatars.dart';
import '../widgets/avatars/hvac_avatars.dart';
import '../widgets/avatars/elevator_avatars.dart';
import '../widgets/avatars/building_sensor_avatars.dart';
import '../widgets/avatars/industrial_pump_avatars.dart';
import '../widgets/avatars/industrial_fan_avatars.dart';
import '../widgets/avatars/electrical_panel_avatars.dart';
import '../widgets/avatars/spot_welder_avatars.dart';
import '../widgets/avatars/appliance_avatars.dart';
import '../widgets/avatars/it_equipment_avatars.dart';

/// Kho blueprint avatar khả dụng cho toàn app — Dashboard tra theo id/category để chọn UI vẽ
/// cho một thiết bị. Bước 2 nạp nhóm Smart Home (Công tắc/Chiếu sáng/Không khí/An ninh-Cửa);
/// Bước 3 nạp nhóm Office/BMS (Cửa từ/HVAC/Thang máy/Cảm biến tòa nhà); Bước 4 nạp nhóm Công
/// nghiệp (Trạm bơm/Quạt công nghiệp/Tủ điện-Tải nặng/Máy hàn điểm); Bước 5 mở rộng thêm Công tắc
/// nút nguồn glow, Chiếu sáng (Đèn ngủ/chùm/Downlight/tuýp), Không khí (Quạt hơi nước/Đèn sưởi/
/// Quạt hút mùi/thông gió), Điện gia dụng (Tủ lạnh/Tivi/Máy giặt/Robot hút bụi/Ấm siêu tốc/Bình
/// nóng lạnh/Bếp từ), IT & Bơm chuyên dụng (PC/Server/Bơm tăng áp/cứu hỏa/bể lớn) — mỗi nhóm UI
/// thật nằm ở file riêng dưới lib/widgets/avatars/, file này chỉ GOM danh sách.
final List<DeviceAvatarDefinition> avatarLibrary = [
  ...switchAvatars,
  ...lightingAvatars,
  ...lightingExtraAvatars,
  ...climateAvatars,
  ...climateExtraAvatars,
  ...securityAvatars,
  ...accessControlAvatars,
  ...hvacAvatars,
  ...elevatorAvatars,
  ...buildingSensorAvatars,
  ...industrialPumpAvatars,
  ...industrialFanAvatars,
  ...electricalPanelAvatars,
  ...spotWelderAvatars,
  ...applianceAvatars,
  ...itEquipmentAvatars,
];
