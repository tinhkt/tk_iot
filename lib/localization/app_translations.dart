import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language_provider.dart';

/// AppTranslations — cơ chế dịch thuật PROOF-OF-CONCEPT cho màn Cài đặt (WindowsSettingsDialog
/// + popup "Giao diện" trên Mobile). CHƯA quét/dịch toàn app — chỉ chứa các khóa liên quan
/// trực tiếp tới 2 khu vực trên, theo đúng mô hình "Xây động cơ - Tích hợp UI - Dịch thử
/// nghiệm" đã thống nhất.
///
/// [KIẾN TRÚC] Cố tình KHÔNG dùng Flutter Localizations.of()/flutter_localizations chuẩn (đòi
/// hỏi khai báo localizationsDelegates + supportedLocales trong MaterialApp — đụng vào cấu hình
/// gốc ảnh hưởng TOÀN app, rủi ro không cần thiết cho một bản proof-of-concept). Đi theo ĐÚNG
/// kiến trúc Provider sẵn có của dự án (như ThemeProvider): đọc locale từ LanguageProvider qua
/// context.watch() — đổi ngôn ngữ tự vẽ lại NGAY (real-time), không cần rebuild delegate/App.
class AppTranslations {
  final String languageCode;
  const AppTranslations(this.languageCode);

  /// [listen] mặc định true = context.watch() — BẮT BUỘC để widget tự rebuild real-time khi
  /// LanguageProvider.changeLanguage() gọi notifyListeners(). CHỈ dùng mặc định này khi gọi
  /// TRỰC TIẾP trong build() hoặc trong 1 builder: đang chạy giữa pha build thật (Builder/
  /// Consumer/StatefulBuilder/ListView.itemBuilder/GridView.itemBuilder).
  ///
  /// [BUG THẬT ĐÃ VỠ NÚT — listen:false BẮT BUỘC ở mọi nơi khác] context.watch() nội bộ gọi
  /// dependOnInheritedWidgetOfExactType(), được Provider tự assert bằng cờ TOÀN CỤC
  /// `context.owner!.debugBuilding` — cờ này chỉ true trong lúc Flutter đang thực sự chạy
  /// buildScope() của MỘT khung hình, KHÔNG hề true khi đang xử lý sự kiện chạm (onPressed/
  /// onTap) hay trong PopupMenuButton.itemBuilder/onSelected (những callback này chạy TỪ tap
  /// handler, không phải từ build pass, dù tên nghe giống builder). Gọi context.watch() ở
  /// những chỗ đó ném assertion "Tried to listen... from outside of the widget tree" — vì đây
  /// là hàm async/callback (không phải Widget.build), exception KHÔNG hiện đỏ màn hình mà rơi
  /// thành 1 Future lỗi không ai bắt -> nút bấm im lặng không phản ứng gì (triệu chứng "liệt
  /// nút" đã gặp thật ở Đợt 5). Mọi lời gọi trong onPressed/onTap/hàm async được gọi từ đó/
  /// PopupMenuButton.itemBuilder+onSelected PHẢI truyền listen: false (dùng context.read() —
  /// không cần rebuild real-time cho 1 dialog/menu chỉ mở đúng 1 lần tại thời điểm bấm).
  static AppTranslations of(BuildContext context, {bool listen = true}) {
    final code = listen
        ? context.watch<LanguageProvider>().locale.languageCode
        : context.read<LanguageProvider>().locale.languageCode;
    return AppTranslations(code);
  }

  /// Tra từ theo khóa — không có bản dịch cho ngôn ngữ hiện tại thì rơi về tiếng Việt, không
  /// có cả tiếng Việt thì trả nguyên văn khóa (dễ phát hiện khóa thiếu khi dịch mở rộng sau này).
  String text(String key) {
    final dict = _values[languageCode] ?? _values['vi']!;
    return dict[key] ?? _values['vi']![key] ?? key;
  }

  // [PHẠM VI HIỆN TẠI — CHỈ MÀN CÀI ĐẶT] Mở rộng dần khi dịch thêm màn khác, KHÔNG cần đổi
  // kiến trúc — chỉ thêm khóa mới vào 2 map bên dưới. Đợt 2 (cuốn chiếu): phủ toàn bộ 4 tab
  // WindowsSettingsDialog (Hồ sơ/Giao diện/Bảo mật/Thông tin) + Menu Cài đặt Mobile.
  static const Map<String, Map<String, String>> _values = {
    'vi': {
      // --- Đợt 1: Giao diện ---
      'settings': 'Cài đặt',
      'appearance': 'Giao diện',
      'language': 'Ngôn ngữ',
      'vietnamese': 'Tiếng Việt',
      'english': 'Tiếng Anh',
      'dark_mode': 'Chế độ Tối',
      'light_mode': 'Chế độ Sáng',
      'system_mode': 'Tự động theo hệ thống',
      'color_theme': 'Chủ đề màu sắc',
      'interface_effect': 'Hiệu ứng giao diện',
      'glass_theme': 'Giao diện Kính (Glass Theme)',
      'glass_theme_desc': 'Kính mờ 3D — nền Aurora nhiều màu, thẻ kính bo sáng',

      // --- Đợt 2: Nhãn tab & điều hướng chung ---
      'profile': 'Hồ sơ tài khoản',
      'security_password': 'Bảo mật & Mật khẩu',
      'system_info': 'Thông tin hệ thống',
      'change_password': 'Đổi mật khẩu',
      'manage_permissions': 'Quản lý phân quyền',
      'permissions': 'Phân quyền',
      'system_admin': 'Quản trị Hệ thống',
      'system_admin_desc': 'Whitelist thiết bị & Cập nhật OTA',
      'logout': 'Đăng xuất',
      'logout_device': 'Đăng xuất khỏi thiết bị',

      // --- Đợt 2: Tab Hồ sơ tài khoản (ProfileManagementView) ---
      'my_profile': 'Hồ sơ của tôi',
      'edit_system_account': 'Chỉnh sửa tài khoản hệ thống',
      'profile_desc': 'Cập nhật đầy đủ thông tin hành chính và phương thức liên hệ.',
      'email_fixed': 'Tài khoản Email (Cố định)',
      'full_name_company': 'Họ tên / Tên Công ty',
      'full_name_hint': 'Nhập tên thực thể vận hành',
      'phone_number': 'Số điện thoại liên hệ',
      'phone_hint': 'Số hotline hoặc sđt cá nhân',
      'address': 'Địa chỉ văn phòng / Nhà ở',
      'address_hint': 'Nhập địa chỉ chi tiết',
      'update_profile_btn': 'CẬP NHẬT THÔNG TIN HỒ SƠ',
      'back_to_my_profile': 'Quay lại sửa hồ sơ cá nhân của tôi',
      'system_wide_profiles': 'Hồ sơ toàn hệ thống',
      'tap_to_edit_account': 'Bấm vào một tài khoản để sửa đổi thông tin của họ.',
      'role_label': 'Quyền',

      // --- Đợt 2: Tab Bảo mật & Mật khẩu ---
      'change_password_title': 'Thay đổi mật khẩu tài khoản hiện tại',
      'old_password': 'Mật khẩu cũ',
      'new_password': 'Mật khẩu mới',
      'confirm_new_password': 'Xác nhận lại mật khẩu mới',
      'update_password_btn': 'Cập nhật mật khẩu',
      'password_mismatch': 'Mật khẩu xác nhận không khớp!',
      'password_change_success': 'Đổi mật khẩu thành công!',

      // --- Đợt 2: Tab Thông tin hệ thống ---
      'server': 'Máy chủ',
      'copyright': 'Bản quyền',
      'app_version_label': 'Phiên bản',

      // --- Đợt 2: Riêng Menu Cài đặt Mobile ---
      'general_section': 'CHUNG',
      'security_section': 'BẢO MẬT',
      'admin_section': 'QUẢN TRỊ',
      'system_section': 'HỆ THỐNG',
      'appearance_color': 'Giao diện màu sắc',
      'software_version_label': 'Phiên bản phần mềm',

      // --- Đợt 3: Sidebar (Desktop + Mobile Drawer/BottomNav) ---
      'dashboard': 'Bảng điều khiển',
      'dashboard_short': 'Điều khiển', // biến thể ngắn cho Mobile Drawer/BottomNav (thiếu chỗ)
      'home_management': 'Quản lý Nhà',
      'rooms': 'Phòng',
      'routines': 'Ngữ cảnh',
      'notifications': 'Thông báo',

      // --- Đợt 3: Header & Tổng quan ---
      'hello': 'Xin chào',
      'system_overview': 'Tổng quan Hệ thống',
      'temperature': 'Nhiệt độ',
      'humidity': 'Độ ẩm',
      'power_load': 'Tiêu thụ',
      'security': 'An ninh',
      'on_state': 'BẬT',
      'off_state': 'TẮT',

      // --- Đợt 3: Khu vực Thiết bị ---
      'all_devices': 'Tất cả thiết bị',
      'all': 'Tất cả',

      // --- Đợt 3: Thẻ Điện năng & Camera ---
      'energy': 'Điện năng',
      'today': 'Hôm nay',
      'consuming': 'Đang tiêu thụ',
      'this_month': 'Tháng này',
      'camera': 'Camera',
      'offline': 'Ngoại tuyến',

      // --- Đợt 4: Nút Thêm, fallback, trạng thái thẻ thiết bị ---
      'add_device': 'Thêm',
      'updating': 'Đang cập nhật...',
      'online': 'Trực tuyến',
      'turned_on': 'Đang bật',
      'turned_off': 'Đã tắt',

      // ==========================================================================
      // ĐỢT 5 — QUÉT SÂU: Quản lý Nhà/Phòng/Ngữ cảnh/Phân quyền/Quản trị/Thông báo
      // ==========================================================================
      // --- Hành động chung (dùng lại xuyên suốt nhiều màn) ---
      'add': 'Thêm',
      'edit': 'Sửa',
      'delete': 'Xóa',
      'save': 'Lưu',
      'cancel': 'Hủy',
      'update': 'Cập nhật',
      'close': 'Đóng',
      'confirm': 'Đồng ý',
      'save_changes': 'Lưu thay đổi',
      'create_new': 'Tạo mới',
      'confirm_delete_title': 'Xác nhận xóa',
      'confirm_delete_action': 'Đồng ý xóa',
      'retry': 'Thử lại',

      // --- Tiêu đề trang/bảng ---
      'room_management_title': 'Quản lý phòng',
      'permissions_title': 'Quản lý Phân quyền',
      'notifications_title': 'Thông báo hệ thống',
      'notifications_full_title': 'Tất cả thông báo',

      // --- Trạng thái rỗng ---
      'no_data': 'Không có dữ liệu',
      'no_notifications': 'Không có thông báo nào.',

      // --- Tooltip/Hỗ trợ ---
      'new_notifications_tooltip': 'Thông báo mới',
      'account_tooltip': 'Tài khoản của bạn',
      'tap_for_details': 'Nhấn để xem chi tiết',
      'rename_bulk_tooltip': 'Đổi tên hàng loạt',
      'move_room_bulk_tooltip': 'Chuyển vào phòng',
      'create_group_bulk_tooltip': 'Tạo nhóm công tắc',
      'hide_show_bulk_tooltip': 'Ẩn / Hiện hàng loạt',
      'delete_bulk_tooltip': 'Xóa hàng loạt',

      // --- home_management_screen.dart ---
      'all_homes_title': 'Toàn bộ hệ thống',
      'my_homes_title': 'Danh sách Nhà của tôi',
      'add_home': 'Thêm nhà mới',
      'no_homes_yet': 'Chưa có ngôi nhà nào trên hệ thống.',
      'owner_role': 'Chủ nhà',
      'admin_role': 'Quản trị',
      'member_role': 'Thành viên',
      'super_admin_role': 'Super Admin',
      'enter_control': 'Vào điều khiển',
      'update_info': 'Cập nhật thông tin',
      'delete_this_home': 'Xóa nhà này',
      'leave_home': 'Rời khỏi nhà',
      'leave_home_confirm_msg': 'Bạn có chắc chắn muốn rời khỏi ngôi nhà này? Bạn sẽ mất toàn quyền truy cập và điều khiển.',
      'owner_info_title': 'Thông tin Chủ nhà',
      'display_name_label': 'Tên hiển thị (suy ra từ email)',
      'full_email_label': 'Email đầy đủ',
      'pending_invite_title': 'Lời mời tham gia hệ thống',
      'reject': 'Từ chối',
      'accept': 'Chấp nhận',
      'update_home_info_title': 'Cập nhật thông tin Nhà',
      'add_home_title': 'Thêm Nhà mới',
      'home_name_label': 'Tên ngôi nhà',
      'home_name_hint': 'Để trống sẽ lấy ID làm tên',
      'specific_address': 'Địa chỉ cụ thể',
      'delete_home_confirm_prefix': 'Bạn có chắc chắn muốn xóa hệ thống "',
      'delete_home_confirm_suffix': '"? Hành động này không thể hoàn tác.',
      'creating_home': 'Đang tạo nhà mới...',

      // --- room_management_screen.dart / room_detail_screen.dart ---
      'add_room': 'Thêm phòng',
      'no_rooms_yet': 'Chưa có phòng nào.\nBấm "Thêm phòng" để tạo mới.',
      'edit_room_name': 'Sửa tên phòng',
      'add_room_title': 'Thêm phòng mới',
      'room_delete_body': 'Thiết bị trong phòng KHÔNG bị xóa, chỉ gỡ khỏi phòng này.',
      'room_name_hint': 'Tên phòng',
      'delete_room_confirm_prefix': 'Xóa phòng "',
      'add_device_label': 'Thêm thiết bị',
      'no_devices_in_room': 'Phòng chưa có thiết bị nào.\nBấm "Thêm thiết bị" để gán vào phòng.',
      'remove_from_room': 'Gỡ khỏi phòng',
      'pick_devices_title': 'Chọn thiết bị thêm vào phòng',
      'no_unassigned_devices': 'Không còn thiết bị trống — tất cả đã thuộc một phòng.',
      'devices_count_suffix': ' thiết bị • Chạm để xem chi tiết',

      // --- automation_screen.dart / create_automation_screen.dart / add_scene_or_schedule_screen.dart ---
      'tap_to_run_tab': 'Chạm để chạy',
      'auto_tab': 'Tự động',
      'schedule_tab': 'Lịch trình',
      'no_home_selected_error': 'Chưa xác định được nhà hiện tại — mở lại màn hình Ngữ cảnh',
      'delete_schedule_title': 'Xóa lịch trình',
      'no_schedules_yet': 'Chưa có lịch trình nào.\nBấm "Thêm mới" > tab "Lịch trình" để tạo.',
      'delete_scene_title': 'Xóa ngữ cảnh',
      'no_scenes_yet': 'Chưa có ngữ cảnh nào.\nBấm "Thêm mới" để tạo.',
      'run_now': 'Chạy',
      'scene_name_hint': 'Tên ngữ cảnh (vd: Về nhà)',
      'if_label': 'NẾU...',
      'add_condition': 'Thêm điều kiện',
      'then_label': 'THÌ...',
      'add_action': 'Thêm hành động',
      'edit_scene_title': 'Sửa ngữ cảnh',
      'create_scene_title': 'Tạo ngữ cảnh',
      'pick_icon_title': 'Chọn biểu tượng',
      'need_one_action': 'Hãy thêm ít nhất 1 hành động (THÌ...)',
      'scene_updated': 'Đã lưu thay đổi ngữ cảnh',
      'scene_created': 'Đã tạo ngữ cảnh mới',
      'add_new_title': 'Thêm mới',
      'repeat_once': 'Một lần',
      'repeat_daily': 'Hàng ngày',
      'repeat_weekdays': 'T2 - T6',
      'repeat_weekend': 'Cuối tuần',
      'pick_device_channel_error': 'Hãy chọn thiết bị và nút/kênh cụ thể',
      'pick_custom_value_error': 'Hãy nhập Value cho hành động tùy chỉnh',
      'device_and_channel': 'Thiết bị & kênh',
      'pick_device': 'Chọn thiết bị',
      'pick_channel': 'Chọn nút / kênh',
      'no_channels_info': 'Thiết bị này chưa ghi nhận kênh điều khiển nào — lịch sẽ áp dụng cho cả thiết bị.',
      'single_channel_info_prefix': 'Thiết bị này chỉ có 1 kênh điều khiển — tự động áp dụng cho "',
      'action_label': 'Hành động',
      'toggle_segment': 'Bật/Tắt',
      'speed_segment': 'Tốc độ',
      'swing_segment': 'Đảo gió',
      'custom_segment': 'Tùy chỉnh',
      'custom_value_label': 'Value tùy chỉnh',
      'custom_value_helper': 'Giá trị thô gửi thẳng xuống thiết bị (vd: "2", "swing", "45")',
      'turn_on_segment': 'Bật',
      'turn_off_segment': 'Tắt',
      'standing_still': 'Đứng yên',
      'schedule_type_label': 'Kiểu lịch',
      'fixed_time': 'Giờ cố định',
      'countdown': 'Đếm ngược',
      'time_label': 'Thời gian',
      'repeat_label': 'Lặp lại',
      'start_countdown': 'Bắt đầu đếm ngược',
      'add_schedule': 'Thêm lịch trình',
      'trigger_label': 'Kích hoạt',
      'confirm_delete_schedule_prefix': 'Bạn có chắc chắn muốn xóa lịch trình "',
      'confirm_delete_scene_prefix': 'Bạn có chắc chắn muốn xóa ngữ cảnh "',
      'device_status_suffix': ' thiết bị • Chạm để sửa, giữ để xóa',
      'actions_count_suffix': ' hành động',

      // --- role_management_view.dart (Phân quyền) ---
      'fetch_error_role': 'Bạn không có quyền truy cập, hoặc máy chủ đang gặp sự cố.',
      'grant_member_access': 'Cấp quyền thành viên',
      'interaction_level_label': 'Cấp độ tương tác:',
      'role_owner_full': 'CHỦ NHÀ (Toàn quyền hệ thống)',
      'role_admin_full': 'ADMIN (Quản trị viên thiết bị)',
      'role_user_full': 'USER (Giới hạn thiết bị)',
      'allowed_devices_label': 'Thiết bị được phép điều khiển',
      'allowed_devices_hint': 'Ví dụ: S_1706, S_6456',
      'update_success': 'Cập nhật thành công!',
      'revoke_access_title': 'Thu hồi quyền truy cập',
      'revoke_access_btn': 'Xóa truy cập',
      'security_header_eyebrow': 'Hệ thống bảo mật vận hành',
      'total_members_metric': 'TỔNG THÀNH VIÊN',
      'owner_metric': 'CHỦ NHÀ (OWNER)',
      'admin_metric': 'QUẢN TRỊ VIÊN (ADMIN)',
      'limited_metric': 'GIỚI HẠN (USER)',
      'search_email_hint': 'Tìm kiếm tài khoản email...',
      'search_email_hint2': 'Tìm kiếm nhanh theo tài khoản email...',
      'all_roles_filter': 'Tất cả cấp quyền',
      'filter_owner': 'Cấp: Chủ nhà',
      'filter_admin': 'Cấp: Admin',
      'filter_member': 'Cấp: Thành viên',
      'revoke_all_btn': 'THU HỒI TẤT CẢ QUYỀN',
      'no_users_found': 'Không tìm thấy tài khoản người dùng nào khớp điều kiện.',
      'friendly_role_dev': 'Phát triển',
      'friendly_role_admin': 'Quản trị viên',
      'friendly_role_limited': 'Giới hạn',
      'edit_access': 'Sửa cấp quyền',
      'revoke_access_menu': 'Thu hồi quyền',
      'role': 'Vai trò',
      'grant_access': 'Cấp quyền',
      'confirm_revoke_prefix': 'Bạn có chắc chắn muốn loại bỏ ',
      'confirm_revoke_suffix': ' tài khoản được chọn khỏi hệ thống ngôi nhà này?',
      'bulk_selection_prefix': 'Đang chọn xử lý hàng loạt: ',
      'bulk_selection_suffix': ' tài khoản',
      'zone_prefix': 'Khu vực: ',

      // --- admin_system_screen.dart (Quản trị hệ thống) ---
      'provision_device_tab': 'Cấp phép thiết bị',
      'ota_update_tab': 'Cập nhật OTA',
      'strict_mode_title': 'Chế độ bảo mật nghiêm ngặt',
      'strict_mode_desc': 'Chỉ thiết bị trong danh sách mới được kết nối',
      'add_whitelist_device_title': 'Thêm thiết bị được cấp phép',
      'sn_mac_label': 'SN / MAC (12 ký tự hex)',
      'device_type_label': 'Loại thiết bị (chọn hoặc gõ mới)',
      'adding_ellipsis': 'Đang thêm...',
      'add_to_list': 'Thêm vào danh sách',
      'no_whitelist_devices': 'Chưa có thiết bị nào được cấp phép.',
      'provisioned_count_prefix': 'Đã cấp phép (',
      'confirm_delete_file_prefix': 'Bạn có chắc chắn xóa file này khỏi server không?\n\n',
      'pick_bin_file_error': 'Vui lòng chọn file .bin',
      'enter_version_error': 'Vui lòng nhập phiên bản',
      'pick_device_type_error': 'Vui lòng chọn hoặc nhập loại thiết bị',
      'upload_success': 'Tải firmware lên thành công',
      'delete_failed': 'Xóa thất bại',
      'cant_get_pubkey_error': 'Không lấy được Public Key',
      'public_key_dialog_title': 'Public Key ký OTA (P-256)',
      'public_key_help_text': 'Hãy dán chuỗi này vào biến pubkey (mảng OTA_PUBLIC_KEY[65]) trong mã nguồn C++ của thiết bị trước khi biên dịch.',
      'copy_clipboard_btn': 'Copy vào Clipboard',
      'copied_clipboard': 'Đã copy Public Key vào Clipboard',
      'upload_new_firmware_title': 'Tải lên Firmware mới',
      'get_public_key_btn': 'Lấy Khóa Công Khai',
      'version_hint': 'Phiên bản (vd: 1.0.2)',
      'changelog_hint': 'Changelog (nội dung thay đổi)',
      'pick_bin_file_btn': 'Chọn file .bin',
      'uploading_ellipsis': 'Đang tải lên...',
      'upload_to_server_btn': 'Tải lên Server',
      'firmware_on_server': 'Firmware trên server',
      'firmware_repo_empty': 'Kho firmware đang trống.',

      // --- Thông báo (dashboard_screen.dart) ---
      'mark_all_read': 'Đánh dấu tất cả đã đọc',
      'total_count_prefix': 'Tổng số: ',
      'push_notif_toggle': 'Nhận thông báo đẩy (Push)',
      'unknown_device': 'Thiết bị lạ',
      'read': 'Đã đọc',
      'unread': 'Chưa đọc',
      'push_short': 'Đẩy (Push)',

      // --- Đợt 6: Menu giữ thiết bị (device_menu_helper.dart) ---
      'device_settings_menu': 'Cài đặt thiết bị',
      'timer_schedule_menu': 'Hẹn giờ & Lịch trình',
      'activity_log_menu': 'Lịch sử hoạt động',
      'activity_log_sub': 'Nhật ký bật/tắt',
      'add_to_routine_menu': 'Thêm vào Ngữ cảnh',
      'share_device_menu': 'Chia sẻ thiết bị',
      'edit_device_name_menu': 'Sửa tên thiết bị',
      'move_to_room_menu': 'Chuyển / Thêm vào phòng',
      'transfer_home_menu': 'Chuyển sang nhà khác',
      'transfer_home_sub': 'Phân bổ thiết bị cho ngôi nhà khác (Admin)',
      'edit_group_menu': 'Chỉnh sửa nhóm',
      'edit_group_sub': 'Thêm/bớt thiết bị trong nhóm',
      'show_device_again': 'Hiển thị lại thiết bị này',
      'hide_from_dashboard_menu': 'Ẩn khỏi Bảng điều khiển',
      'delete_device_menu': 'Xóa thiết bị',
      'delete_device_confirm_prefix': 'Xóa ',
      'delete_device_confirm_body': 'Bạn có chắc chắn muốn gỡ thiết bị này khỏi hệ thống không?',
      'delete_now': 'Xóa ngay',

      // --- Đợt 6: Popup Cài đặt thiết bị — Thông số kỹ thuật (dashboard_screen.dart) ---
      'technical_specs_header': 'THÔNG SỐ KỸ THUẬT',
      'fan_control_header': 'ĐIỀU KHIỂN QUẠT',
      'mac_serial_label': 'Địa chỉ MAC / Serial',
      'lan_ip_label': 'Địa chỉ IP LAN',
      'rssi_label': 'Cường độ sóng (RSSI)',
      'connected_wifi_label': 'Mạng Wi-Fi kết nối',
      'firmware_branch_label': 'Dòng firmware',
      'power_on_state_label': 'Khi có điện lại',
      'relay_state_after_loss_label': 'Trạng thái relay sau khi mất điện',
      'remember_state_option': 'Nhớ trạng thái cũ',
      'always_off_option': 'Luôn Tắt',
      'always_on_option': 'Luôn Bật',
      'check_update_btn': 'Kiểm tra cập nhật',
      'rename_short_btn': 'Sửa tên',

      // --- Đợt 6: Popup Điều kiện Ngữ cảnh (scene_step_pickers.dart) ---
      'condition_for_prefix': 'Điều kiện cho "',
      'operator_label': 'Phép so sánh',
      'temp_attr_label': 'Nhiệt độ',
      'humidity_attr_label': 'Độ ẩm',
      'temp_threshold_label': 'Ngưỡng nhiệt độ',
      'humidity_threshold_label': 'Ngưỡng độ ẩm',
      'use_this_condition_btn': 'Dùng điều kiện này',

      // --- Đợt 6: Popup Thêm thiết bị (add_device_dialog.dart) ---
      'add_new_device_title': 'Thêm thiết bị mới',
      'add_device_intro': 'Chọn một phương thức cấu hình thuận tiện nhất để liên kết thiết bị thông minh vào hệ thống.',
      'scan_qr_title': 'Quét mã QR Code',
      'scan_qr_sub': 'Tự động nhận diện nhanh qua camera',
      'ap_mode_title': 'Kết nối Wi-Fi (AP Mode tự động)',
      'ap_mode_sub': 'Bắt mạng của thiết bị để cấu hình tự động',
      'manual_entry_title': 'Nhập thủ công (SN/MAC)',
      'manual_entry_sub': 'Điền thông tin sê-ri mã phía sau vỏ máy',
      'lan_scan_title': 'Quét mạng LAN (Tự động tìm kiếm)',
      'lan_scan_sub': 'Dò mọi thiết bị đang cùng mạng WiFi với bạn',
      'lan_scan_header': 'Quét mạng LAN',
      'lan_scanning_status': 'Đang tìm kiếm thiết bị trong mạng...',
      'lan_scan_empty': 'Không tìm thấy thiết bị nào. Đảm bảo điện thoại và thiết bị dùng chung WiFi.',
      'found_devices_prefix': 'Đã tìm thấy ',
      'found_devices_suffix': ' thiết bị.',
      'already_added_label': 'Đã thêm',
      'add_now_btn': 'Thêm ngay',
      'scan_qr_header': 'Quét mã QR thiết bị',
      'scan_qr_hint': 'Đưa mã QR trên tem thiết bị vào trung tâm camera',
      'manual_entry_header': 'Nhập thủ công mã MAC',
      'mac_sn_hint': 'Mã MAC hoặc SN của thiết bị',
      'confirm_connection_btn': 'XÁC NHẬN KẾT NỐI',
      'ap_mode_header': 'Kết nối Wi-Fi AP Tự động',
      'connected_to_hub': 'Đã kết nối với Smart Hub!',
      'searching_device_network': 'Đang tìm kiếm mạng thiết bị...',
      'preparing_open_settings': 'Chuẩn bị mở màn hình Cài đặt kết nối...',
      'wifi_ap_instructions': 'Vui lòng nhấn nút bên dưới để mở cài đặt Wi-Fi. Kết nối với mạng có tên "Smart_Hub_..." sau đó quay lại App.',
      'open_wifi_settings_btn': 'MỞ CÀI ĐẶT WI-FI ĐIỆN THOẠI',
      'camera_permission_locked': 'Quyền Camera đang bị khóa. Hãy mở Cài đặt và bật Camera cho ứng dụng để quét mã QR.',
      'camera_permission_needed': 'Bạn cần cho phép dùng Camera để quét mã QR trên tem thiết bị.',
      'open_settings_action': 'MỞ CÀI ĐẶT',
      'invalid_device_id': 'Mã định danh thiết bị không hợp lệ!',

      // --- Đợt 6: Thẻ nhà — số thiết bị/thành viên (home_management_screen.dart) ---
      'devices_stat_suffix': ' TB',
      'switches_stat_suffix': ' CT',
      'members_stat_suffix': ' TV',

      // --- Đợt 7: Màn Thành viên (member_list_screen.dart) ---
      // [LƯU Ý] 'admin_role' đã có sẵn từ Đợt 5 (giá trị 'Quản trị' — dùng cho badge gọn ở
      // Home Card, home_management_screen.dart) — KHÔNG ghi đè để tránh vỡ chỗ dùng cũ. Tiêu
      // đề khu vực dài hơn ("Quản trị viên") dùng khóa riêng 'admin_role_title'. 'member_role'
      // (đã có sẵn, giá trị 'Thành viên'/'Member') tái dùng nguyên cho badge vai trò 1 người.
      'members': 'Thành viên',
      'add_member': 'Thêm thành viên',
      'home_owner': 'Chủ nhà',
      'home_owner_desc': 'Toàn quyền sở hữu ngôi nhà này',
      'admin_role_title': 'Quản trị viên',
      'admin_badge': 'QUẢN TRỊ',
      'you_suffix': '(Bạn)',
      'no_members_yet': 'Chưa có thành viên nào',
      'no_admins_yet': 'Chưa có quản trị viên nào',
      'confirm_remove_member_prefix': 'Bạn có chắc chắn muốn xóa thành viên "',
      'confirm_remove_member_suffix': '" khỏi nhà này?',
      'remove_from_home_menu': 'Xóa khỏi nhà',
      'add_member_success': 'Đã thêm thành viên thành công',
      'removed_member_prefix': 'Đã xóa ',
      'removed_member_suffix': ' khỏi nhà',

      // --- Đợt 8: Mapping hiển thị — Lặp lại/Tốc độ quạt/Popup Điều kiện/Gỡ thiết bị ---
      'fan_speed_prefix': 'Số',
      'choose_condition_title': 'Chọn điều kiện (NẾU...)',
      'cond_time': 'Theo thời gian',
      'cond_time_desc': 'Chạy vào một giờ cố định trong ngày',
      'cond_device': 'Thiết bị thay đổi trạng thái',
      'cond_device_desc': 'Công tắc BẬT/TẮT, hoặc cảm biến vượt ngưỡng nhiệt độ/độ ẩm',
      'cond_weather': 'Thời tiết thay đổi',
      'cond_weather_desc': 'Nhiệt độ vượt ngưỡng hoặc trời mưa',
      'removed_success_1': 'Đã gỡ "',
      'removed_success_2': '" khỏi phòng ',

      // --- Đợt 10: Popup Chọn hành động (THÌ...) + nút Cập nhật OTA ---
      'choose_action_title': 'Chọn hành động (THÌ...)',
      'action_control_device': 'Điều khiển thiết bị',
      'action_control_device_desc': 'Bật/Tắt một thiết bị thật trong nhà',
      'action_send_noti': 'Gửi thông báo',
      'action_delay': 'Chờ (Delay)',
      'update_now': 'Cập nhật ngay',

      // --- Đợt 11: Xóa phòng (nhấn giữ) ---
      'delete_room_confirm': 'Bạn có chắc chắn muốn xóa phòng này không? Các thiết bị trong phòng sẽ được đưa về danh sách chung.',

      // --- Đợt 11: Tách kênh (relay) khi thêm vào phòng ---
      'channel_number_prefix': ' - Số ',
      'pick_channels_hint': 'Tick chọn từng kênh muốn thêm vào phòng này (một thiết bị nhiều nút có thể chia vào các phòng khác nhau).',

      // --- Đợt 12: Menu nhấn giữ — Ẩn khỏi Bảng điều khiển (hideLabel/hideSubtitle sót ở 3 thẻ) ---
      'hide_from_dashboard': 'Ẩn khỏi Bảng điều khiển',
      'hide_from_dashboard_desc': 'Vẫn hiển thị trong danh sách thiết bị',

      // --- Đợt 13: Dialog Tạo nhóm công tắc + thanh Đa chọn ---
      'create_group_title': 'Tạo nhóm công tắc',
      'group_name_hint': 'Tên nhóm (vd: Đèn toàn nhà)',
      'choose_icon_label': 'Chọn biểu tượng:',
      'group_type_label': 'Loại nhóm:',
      'type_normal': 'Thường',
      'type_stair': 'Cầu thang',
      'type_fan': 'Quạt',
      'btn_create_group': 'Tạo nhóm',
      'selected_count': 'Đã chọn ',

      // --- Đợt 14: Menu nhấn giữ — mục đặc thù công tắc (Chọn nhiều/Xem thiết bị ẩn) ---
      'select_multiple_devices': 'Chọn nhiều thiết bị',
      'close_hidden_view': 'Đóng chế độ xem thiết bị ẩn',
      'show_hidden_devices': 'Hiển thị các thiết bị đã ẩn',

      // --- Đợt 17: Thời tiết GPS — trạng thái ---
      // [ĐỢT 19] 'refresh_location_tooltip' đã XÓA — nút làm mới vị trí thủ công bị thay bằng
      // Text địa danh tự động (_locationName), key không còn nơi nào dùng.
      'weather_clear': 'Nắng',
      'weather_clouds': 'Nhiều mây',
      'weather_rain': 'Mưa',
      'weather_thunderstorm': 'Giông bão',
      'weather_snow': 'Tuyết',
      'weather_mist': 'Sương mù',

      // --- Đợt 22: Cài đặt WiFi App-driven (thay captive portal) — add_device_dialog.dart ---
      'wifi_setup_header': 'Cấu hình WiFi',
      'wifi_scanning_status': 'Đang quét mạng WiFi xung quanh...',
      'wifi_scan_empty_hint': 'Không tìm thấy mạng nào — nhập tên WiFi thủ công bên dưới',
      'wifi_ssid_hint': 'Tên WiFi (SSID)',
      'wifi_password_hint': 'Mật khẩu WiFi',
      'wifi_install_btn': 'CÀI ĐẶT',
      // [ĐỢT 26] Checkbox tùy chọn lưu mật khẩu WiFi cục bộ (add_device_dialog.dart)
      'save_wifi_checkbox': 'Lưu mạng WiFi này cho các lần cài đặt sau',
      'wifi_ssid_required': 'Vui lòng chọn hoặc nhập tên WiFi',
      'wifi_installing_status': 'Đang gửi thông tin tới thiết bị...',
      // [ĐỢT 30] Hết 5 lần thử vẫn không nhận được HTTP 200 thật — báo lỗi qua SnackBar, quay
      // lại màn nhập WiFi (không còn nhánh "coi Exception là thành công" nên không cần 2 khóa
      // wifi_installing_waiting_lan/wifi_installing_fail/wifi_installing_timeout cũ nữa).
      'wifi_send_failed_error': 'Không thể gửi thông tin tới thiết bị. Vui lòng kiểm tra lại kết nối WiFi nội bộ.',
      'wifi_retry_btn': 'THỬ LẠI',
      'wifi_rescan_btn': 'Quét lại',

      // --- Đợt 23: Digital Twin — Cửa cuốn/Bơm/Đèn Chiết áp/Lưới an toàn ---
      'rolling_door_default_name': 'Cửa cuốn',
      'rolling_door_open_suffix': 'mở',
      'pump_default_name': 'Máy bơm',
      'pump_running_status': 'Đang bơm...',
      'pump_idle_status': 'Đang nghỉ',
      'dimmer_default_name': 'Đèn Chiết áp',
      'generic_device_default_name': 'Thiết bị',
      'on': 'Bật',
      'off': 'Tắt',
      'travel_time_label': 'Thời gian hành trình',
      'travel_time_desc': 'Số giây cửa cuốn đi hết từ 0% đến 100% — dùng để Slider % kéo đúng vị trí',

      // --- Đợt 25: Direct MAC Binding — đăng ký trực tiếp bằng MAC (add_device_dialog.dart) ---
      'device_register_header': 'Đăng ký thiết bị',
      'device_registering_status': 'Đang đăng ký thiết bị lên hệ thống...',
      // [ĐỢT 29] Internet Liveness Check — pha chờ RIÊNG trước khi gọi Cloud
      'device_waiting_internet_status': 'Đang đợi điện thoại kết nối lại mạng Internet...',
      'device_registering_attempt_prefix': 'Đang thử lại — lần ',
      'device_owned_by_other_error': 'Thiết bị này đã được liên kết với một tài khoản khác. Vui lòng yêu cầu chủ sở hữu cũ xóa thiết bị, hoặc thực hiện Hard Reset thiết bị để tiếp tục.',
      'device_register_forbidden_error': 'Bạn không có quyền thêm thiết bị vào ngôi nhà này.',
      'device_register_timeout_error': 'Thiết bị chưa kịp kết nối vào hệ thống sau nhiều lần thử. Kiểm tra lại mật khẩu WiFi nhà rồi thử lại.',
      'device_register_network_error': 'Không thể kết nối máy chủ — kiểm tra mạng 4G/WiFi của điện thoại rồi thử lại.',
      'device_register_generic_error': 'Không thể đăng ký thiết bị — vui lòng thử lại.',
    },
    'en': {
      // --- Round 1: Appearance ---
      'settings': 'Settings',
      'appearance': 'Appearance',
      'language': 'Language',
      'vietnamese': 'Vietnamese',
      'english': 'English',
      'dark_mode': 'Dark Mode',
      'light_mode': 'Light Mode',
      'system_mode': 'System Default',
      'color_theme': 'Color Theme',
      'interface_effect': 'Interface Effect',
      'glass_theme': 'Glass Theme',
      'glass_theme_desc': '3D frosted glass — colorful Aurora background, glowing glass cards',

      // --- Round 2: Common tab/navigation labels ---
      'profile': 'Account Profile',
      'security_password': 'Security & Password',
      'system_info': 'System Information',
      'change_password': 'Change Password',
      'manage_permissions': 'Manage Permissions',
      'permissions': 'Permissions',
      'system_admin': 'System Administration',
      'system_admin_desc': 'Device whitelist & OTA updates',
      'logout': 'Logout',
      'logout_device': 'Logout from this device',

      // --- Round 2: Account Profile tab (ProfileManagementView) ---
      'my_profile': 'My Profile',
      'edit_system_account': 'Edit System Account',
      'profile_desc': 'Update your full administrative information and contact details.',
      'email_fixed': 'Email Account (Fixed)',
      'full_name_company': 'Full Name / Company Name',
      'full_name_hint': 'Enter the operating entity name',
      'phone_number': 'Contact Phone Number',
      'phone_hint': 'Hotline or personal phone number',
      'address': 'Office / Home Address',
      'address_hint': 'Enter detailed address',
      'update_profile_btn': 'UPDATE PROFILE INFO',
      'back_to_my_profile': 'Back to editing my personal profile',
      'system_wide_profiles': 'System-wide Profiles',
      'tap_to_edit_account': 'Tap an account to edit their information.',
      'role_label': 'Role',

      // --- Round 2: Security & Password tab ---
      'change_password_title': 'Change current account password',
      'old_password': 'Old Password',
      'new_password': 'New Password',
      'confirm_new_password': 'Confirm New Password',
      'update_password_btn': 'Update Password',
      'password_mismatch': 'Password confirmation does not match!',
      'password_change_success': 'Password changed successfully!',

      // --- Round 2: System Information tab ---
      'server': 'Server',
      'copyright': 'Copyright',
      'app_version_label': 'Version',

      // --- Round 2: Mobile Settings Menu only ---
      'general_section': 'GENERAL',
      'security_section': 'SECURITY',
      'admin_section': 'ADMIN',
      'system_section': 'SYSTEM',
      'appearance_color': 'Color Appearance',
      'software_version_label': 'Software Version',

      // --- Round 3: Sidebar (Desktop + Mobile Drawer/BottomNav) ---
      'dashboard': 'Dashboard',
      'dashboard_short': 'Home', // shorter variant for Mobile Drawer/BottomNav (tight space)
      'home_management': 'Home Management',
      'rooms': 'Rooms',
      'routines': 'Routines',
      'notifications': 'Notifications',

      // --- Round 3: Header & Overview ---
      'hello': 'Hello',
      'system_overview': 'System Overview',
      'temperature': 'Temperature',
      'humidity': 'Humidity',
      'power_load': 'Power Load',
      'security': 'Security',
      'on_state': 'ON',
      'off_state': 'OFF',

      // --- Round 3: Devices area ---
      'all_devices': 'All Devices',
      'all': 'All',

      // --- Round 3: Energy & Camera cards ---
      'energy': 'Energy',
      'today': 'Today',
      'consuming': 'Consuming',
      'this_month': 'This Month',
      'camera': 'Camera',
      'offline': 'Offline',

      // --- Round 4: Add button, fallback, device card status ---
      'add_device': 'Add',
      'updating': 'Updating...',
      'online': 'Online',
      'turned_on': 'ON',
      'turned_off': 'OFF',

      // ==========================================================================
      // ROUND 5 — DEEP SWEEP: Home/Room/Routine/Permissions/Admin/Notifications
      // ==========================================================================
      'add': 'Add',
      'edit': 'Edit',
      'delete': 'Delete',
      'save': 'Save',
      'cancel': 'Cancel',
      'update': 'Update',
      'close': 'Close',
      'confirm': 'Confirm',
      'save_changes': 'Save Changes',
      'create_new': 'Create New',
      'confirm_delete_title': 'Confirm Delete',
      'confirm_delete_action': 'Confirm Delete',
      'retry': 'Retry',

      'room_management_title': 'Room Management',
      'permissions_title': 'Permissions Management',
      'notifications_title': 'System Notifications',
      'notifications_full_title': 'All Notifications',

      'no_data': 'No data available',
      'no_notifications': 'No notifications.',

      'new_notifications_tooltip': 'New notifications',
      'account_tooltip': 'Your account',
      'tap_for_details': 'Click for details',
      'rename_bulk_tooltip': 'Bulk Rename',
      'move_room_bulk_tooltip': 'Move to Room',
      'create_group_bulk_tooltip': 'Create Switch Group',
      'hide_show_bulk_tooltip': 'Bulk Hide/Show',
      'delete_bulk_tooltip': 'Bulk Delete',

      // --- home_management_screen.dart ---
      'all_homes_title': 'Entire System',
      'my_homes_title': 'My Homes List',
      'add_home': 'Add New Home',
      'no_homes_yet': 'No homes in the system yet.',
      'owner_role': 'Owner',
      'admin_role': 'Admin',
      'member_role': 'Member',
      'super_admin_role': 'Super Admin',
      'enter_control': 'Enter Control',
      'update_info': 'Update Info',
      'delete_this_home': 'Delete This Home',
      'leave_home': 'Leave Home',
      'leave_home_confirm_msg': 'Are you sure you want to leave this home? You will lose all access and control.',
      'owner_info_title': 'Owner Information',
      'display_name_label': 'Display Name (inferred from email)',
      'full_email_label': 'Full Email',
      'pending_invite_title': 'System Invitation',
      'reject': 'Reject',
      'accept': 'Accept',
      'update_home_info_title': 'Update Home Info',
      'add_home_title': 'Add New Home',
      'home_name_label': 'Home Name',
      'home_name_hint': 'Leave blank to use ID as name',
      'specific_address': 'Specific Address',
      'delete_home_confirm_prefix': 'Are you sure you want to delete the home "',
      'delete_home_confirm_suffix': '"? This action cannot be undone.',
      'creating_home': 'Creating new home...',

      // --- room_management_screen.dart / room_detail_screen.dart ---
      'add_room': 'Add Room',
      'no_rooms_yet': 'No rooms yet.\nTap "Add Room" to create one.',
      'edit_room_name': 'Edit Room Name',
      'add_room_title': 'Add New Room',
      'room_delete_body': 'Devices in the room will NOT be deleted, only removed from this room.',
      'room_name_hint': 'Room Name',
      'delete_room_confirm_prefix': 'Delete room "',
      'add_device_label': 'Add Device',
      'no_devices_in_room': 'No devices in this room yet.\nTap "Add Device" to assign one.',
      'remove_from_room': 'Remove from Room',
      'pick_devices_title': 'Select Devices to Add to Room',
      'no_unassigned_devices': 'No unassigned devices left — all belong to a room.',
      'devices_count_suffix': ' devices • Tap for details',

      // --- automation_screen.dart / create_automation_screen.dart / add_scene_or_schedule_screen.dart ---
      'tap_to_run_tab': 'Tap to Run',
      'auto_tab': 'Automatic',
      'schedule_tab': 'Schedule',
      'no_home_selected_error': 'Current home not determined — reopen the Routines screen',
      'delete_schedule_title': 'Delete Schedule',
      'no_schedules_yet': 'No schedules yet.\nTap "Add New" > "Schedule" tab to create one.',
      'delete_scene_title': 'Delete Routine',
      'no_scenes_yet': 'No routines yet.\nTap "Add New" to create one.',
      'run_now': 'Run',
      'scene_name_hint': 'Routine name (e.g. Coming Home)',
      'if_label': 'IF...',
      'add_condition': 'Add Condition',
      'then_label': 'THEN...',
      'add_action': 'Add Action',
      'edit_scene_title': 'Edit Routine',
      'create_scene_title': 'Create Routine',
      'pick_icon_title': 'Select Icon',
      'need_one_action': 'Please add at least 1 action (THEN...)',
      'scene_updated': 'Routine changes saved',
      'scene_created': 'New routine created',
      'add_new_title': 'Add New',
      'repeat_once': 'Once',
      'repeat_daily': 'Daily',
      'repeat_weekdays': 'Mon - Fri',
      'repeat_weekend': 'Weekends',
      'pick_device_channel_error': 'Please select a specific device and channel',
      'pick_custom_value_error': 'Please enter a Value for the custom action',
      'device_and_channel': 'Device & Channel',
      'pick_device': 'Select Device',
      'pick_channel': 'Select Button / Channel',
      'no_channels_info': 'This device has no recorded control channels — the schedule will apply to the whole device.',
      'single_channel_info_prefix': 'This device has only 1 control channel — automatically applied to "',
      'action_label': 'Action',
      'toggle_segment': 'On/Off',
      'speed_segment': 'Speed',
      'swing_segment': 'Swing',
      'custom_segment': 'Custom',
      'custom_value_label': 'Custom Value',
      'custom_value_helper': 'Raw value sent directly to the device (e.g. "2", "swing", "45")',
      'turn_on_segment': 'On',
      'turn_off_segment': 'Off',
      'standing_still': 'Standing Still',
      'schedule_type_label': 'Schedule Type',
      'fixed_time': 'Fixed Time',
      'countdown': 'Countdown',
      'time_label': 'Time',
      'repeat_label': 'Repeat',
      'start_countdown': 'Start Countdown',
      'add_schedule': 'Add Schedule',
      'trigger_label': 'Trigger',
      'confirm_delete_schedule_prefix': 'Are you sure you want to delete this schedule "',
      'confirm_delete_scene_prefix': 'Are you sure you want to delete this routine "',
      'device_status_suffix': ' device • Tap to edit, hold to delete',
      'actions_count_suffix': ' actions',

      // --- role_management_view.dart (Permissions) ---
      'fetch_error_role': "You don't have access, or the server is experiencing issues.",
      'grant_member_access': 'Grant Member Access',
      'interaction_level_label': 'Interaction Level:',
      'role_owner_full': 'OWNER (Full system access)',
      'role_admin_full': 'ADMIN (Device administrator)',
      'role_user_full': 'USER (Limited device access)',
      'allowed_devices_label': 'Devices allowed to control',
      'allowed_devices_hint': 'Example: S_1706, S_6456',
      'update_success': 'Update successful!',
      'revoke_access_title': 'Revoke Access',
      'revoke_access_btn': 'Revoke Access',
      'security_header_eyebrow': 'Security System Operations',
      'total_members_metric': 'TOTAL MEMBERS',
      'owner_metric': 'OWNER',
      'admin_metric': 'ADMIN',
      'limited_metric': 'LIMITED (USER)',
      'search_email_hint': 'Search email account...',
      'search_email_hint2': 'Quick search by email account...',
      'all_roles_filter': 'All Access Levels',
      'filter_owner': 'Level: Owner',
      'filter_admin': 'Level: Admin',
      'filter_member': 'Level: Member',
      'revoke_all_btn': 'REVOKE ALL ACCESS',
      'no_users_found': 'No matching user accounts found.',
      'friendly_role_dev': 'Developer',
      'friendly_role_admin': 'Administrator',
      'friendly_role_limited': 'Limited',
      'edit_access': 'Edit Access',
      'revoke_access_menu': 'Revoke Access',
      'role': 'Role',
      'grant_access': 'Grant Access',
      'confirm_revoke_prefix': 'Are you sure you want to remove ',
      'confirm_revoke_suffix': ' selected accounts from this home\'s system?',
      'bulk_selection_prefix': 'Bulk selection: ',
      'bulk_selection_suffix': ' accounts',
      'zone_prefix': 'Zone: ',

      // --- admin_system_screen.dart (System Admin) ---
      'provision_device_tab': 'Provision Device',
      'ota_update_tab': 'OTA Update',
      'strict_mode_title': 'Strict Security Mode',
      'strict_mode_desc': 'Only listed devices can connect',
      'add_whitelist_device_title': 'Add Provisioned Device',
      'sn_mac_label': 'SN / MAC (12 hex characters)',
      'device_type_label': 'Device Type (select or type new)',
      'adding_ellipsis': 'Adding...',
      'add_to_list': 'Add to List',
      'no_whitelist_devices': 'No devices provisioned yet.',
      'provisioned_count_prefix': 'Provisioned (',
      'confirm_delete_file_prefix': 'Are you sure you want to delete this file from the server?\n\n',
      'pick_bin_file_error': 'Please select a .bin file',
      'enter_version_error': 'Please enter a version',
      'pick_device_type_error': 'Please select or enter a device type',
      'upload_success': 'Firmware uploaded successfully',
      'delete_failed': 'Delete failed',
      'cant_get_pubkey_error': 'Could not retrieve Public Key',
      'public_key_dialog_title': 'OTA Signing Public Key (P-256)',
      'public_key_help_text': 'Paste this string into the pubkey variable (OTA_PUBLIC_KEY[65] array) in the device C++ source before compiling.',
      'copy_clipboard_btn': 'Copy to Clipboard',
      'copied_clipboard': 'Public Key copied to Clipboard',
      'upload_new_firmware_title': 'Upload New Firmware',
      'get_public_key_btn': 'Get Public Key',
      'version_hint': 'Version (e.g. 1.0.2)',
      'changelog_hint': 'Changelog (change details)',
      'pick_bin_file_btn': 'Select .bin file',
      'uploading_ellipsis': 'Uploading...',
      'upload_to_server_btn': 'Upload to Server',
      'firmware_on_server': 'Firmware on Server',
      'firmware_repo_empty': 'Firmware repository is empty.',

      // --- Notifications (dashboard_screen.dart) ---
      'mark_all_read': 'Mark all as read',
      'total_count_prefix': 'Total: ',
      'push_notif_toggle': 'Receive Push Notifications',
      'unknown_device': 'Unknown Device',
      'read': 'Read',
      'unread': 'Unread',
      'push_short': 'Push',

      // --- Round 6: Device long-press menu (device_menu_helper.dart) ---
      'device_settings_menu': 'Device Settings',
      'timer_schedule_menu': 'Timer & Schedule',
      'activity_log_menu': 'Activity Log',
      'activity_log_sub': 'On/off log',
      'add_to_routine_menu': 'Add to Routine',
      'share_device_menu': 'Share Device',
      'edit_device_name_menu': 'Edit Device Name',
      'move_to_room_menu': 'Move / Add to Room',
      'transfer_home_menu': 'Transfer to Home',
      'transfer_home_sub': 'Assign this device to another home (Admin)',
      'edit_group_menu': 'Edit Group',
      'edit_group_sub': 'Add/remove devices in the group',
      'show_device_again': 'Show this device again',
      'hide_from_dashboard_menu': 'Hide from Dashboard',
      'delete_device_menu': 'Delete Device',
      'delete_device_confirm_prefix': 'Delete ',
      'delete_device_confirm_body': 'Are you sure you want to remove this device from the system?',
      'delete_now': 'Delete Now',

      // --- Round 6: Device Settings popup — Technical Specs (dashboard_screen.dart) ---
      'technical_specs_header': 'TECHNICAL SPECS',
      'fan_control_header': 'FAN CONTROL',
      'mac_serial_label': 'MAC / Serial Address',
      'lan_ip_label': 'LAN IP Address',
      'rssi_label': 'Signal Strength (RSSI)',
      'connected_wifi_label': 'Connected Wi-Fi',
      'firmware_branch_label': 'Firmware Branch',
      'power_on_state_label': 'Power-on State',
      'relay_state_after_loss_label': 'Relay state after power loss',
      'remember_state_option': 'Remember Previous State',
      'always_off_option': 'Always Off',
      'always_on_option': 'Always On',
      'check_update_btn': 'Check for Update',
      'rename_short_btn': 'Rename',

      // --- Round 6: Routine Condition popup (scene_step_pickers.dart) ---
      'condition_for_prefix': 'Condition for "',
      'operator_label': 'Operator',
      'temp_attr_label': 'Temperature',
      'humidity_attr_label': 'Humidity',
      'temp_threshold_label': 'Temperature Threshold',
      'humidity_threshold_label': 'Humidity Threshold',
      'use_this_condition_btn': 'Use this condition',

      // --- Round 6: Add Device popup (add_device_dialog.dart) ---
      'add_new_device_title': 'Add New Device',
      'add_device_intro': 'Choose the most convenient setup method to link a smart device to the system.',
      'scan_qr_title': 'Scan QR Code',
      'scan_qr_sub': 'Quick auto-detection via camera',
      'ap_mode_title': 'Wi-Fi Connection (Auto AP Mode)',
      'ap_mode_sub': 'Catch the device network for automatic setup',
      'manual_entry_title': 'Manual Entry (SN/MAC)',
      'manual_entry_sub': 'Enter the serial code printed on the device case',
      'lan_scan_title': 'LAN Scan (Auto Discovery)',
      'lan_scan_sub': 'Discover every device on the same Wi-Fi network as you',
      'lan_scan_header': 'LAN Scan',
      'lan_scanning_status': 'Searching for devices on the network...',
      'lan_scan_empty': 'No devices found. Make sure your phone and the device share the same Wi-Fi.',
      'found_devices_prefix': 'Found ',
      'found_devices_suffix': ' devices.',
      'already_added_label': 'Added',
      'add_now_btn': 'Add Now',
      'scan_qr_header': 'Scan Device QR Code',
      'scan_qr_hint': 'Center the device\'s QR label in the camera view',
      'manual_entry_header': 'Enter MAC Manually',
      'mac_sn_hint': 'Device MAC or SN code',
      'confirm_connection_btn': 'CONFIRM CONNECTION',
      'ap_mode_header': 'Automatic Wi-Fi AP Connection',
      'connected_to_hub': 'Connected to Smart Hub!',
      'searching_device_network': 'Searching for device network...',
      'preparing_open_settings': 'Preparing to open connection settings...',
      'wifi_ap_instructions': 'Please tap the button below to open Wi-Fi settings. Connect to the network named "Smart_Hub_..." then return to the App.',
      'open_wifi_settings_btn': 'OPEN PHONE WI-FI SETTINGS',
      'camera_permission_locked': 'Camera permission is locked. Please open Settings and enable Camera for this app to scan QR codes.',
      'camera_permission_needed': 'You need to allow Camera access to scan the QR code on the device label.',
      'open_settings_action': 'OPEN SETTINGS',
      'invalid_device_id': 'Invalid device ID!',

      // --- Round 6: Home card — device/member counts (home_management_screen.dart) ---
      'devices_stat_suffix': ' Devices',
      'switches_stat_suffix': ' Switches',
      'members_stat_suffix': ' Members',

      // --- Round 7: Members screen (member_list_screen.dart) ---
      'members': 'Members',
      'add_member': 'Add Member',
      'home_owner': 'Owner',
      'home_owner_desc': 'Full ownership of this home',
      'admin_role_title': 'Administrator',
      'admin_badge': 'ADMIN',
      'you_suffix': '(You)',
      'no_members_yet': 'No members yet',
      'no_admins_yet': 'No administrators yet',
      'confirm_remove_member_prefix': 'Are you sure you want to remove the member "',
      'confirm_remove_member_suffix': '" from this home?',
      'remove_from_home_menu': 'Remove from Home',
      'add_member_success': 'Member added successfully',
      'removed_member_prefix': 'Removed ',
      'removed_member_suffix': ' from home',

      // --- Round 8: Display Mapping — Repeat/Fan Speed/Condition Popup/Remove Device ---
      'fan_speed_prefix': 'Speed',
      'choose_condition_title': 'Choose Condition (IF...)',
      'cond_time': 'Time-based',
      'cond_time_desc': 'Run at a specific time',
      'cond_device': 'Device State Changed',
      'cond_device_desc': 'Switch ON/OFF, or sensor threshold exceeded',
      'cond_weather': 'Weather Changed',
      'cond_weather_desc': 'Temperature threshold or raining',
      'removed_success_1': 'Removed "',
      'removed_success_2': '" from room ',

      // --- Round 10: Choose Action (THEN...) popup + OTA Update button ---
      'choose_action_title': 'Choose Action (THEN...)',
      'action_control_device': 'Control Device',
      'action_control_device_desc': 'Turn ON/OFF a physical device',
      'action_send_noti': 'Send Notification',
      'action_delay': 'Delay',
      'update_now': 'Update Now',

      // --- Round 11: Delete Room (long-press) ---
      'delete_room_confirm': 'Are you sure you want to delete this room? Devices in the room will be moved back to the general list.',

      // --- Round 11: Split Channels (relay) when adding to room ---
      'channel_number_prefix': ' - Channel ',
      'pick_channels_hint': 'Tick each channel you want to add to this room (a multi-relay device can be split across different rooms).',

      // --- Round 12: Long-press menu — Hide from Dashboard (hideLabel/hideSubtitle missed on 3 cards) ---
      'hide_from_dashboard': 'Hide from Dashboard',
      'hide_from_dashboard_desc': 'Still visible in the device list',

      // --- Round 13: Create Switch Group dialog + Multi-select bar ---
      'create_group_title': 'Create Switch Group',
      'group_name_hint': 'Group name (e.g., Whole house lights)',
      'choose_icon_label': 'Choose icon:',
      'group_type_label': 'Group type:',
      'type_normal': 'Normal',
      'type_stair': 'Staircase',
      'type_fan': 'Fan',
      'btn_create_group': 'Create Group',
      'selected_count': 'Selected ',

      // --- Round 14: Long-press menu — switch-specific items (Select multiple/Show hidden) ---
      'select_multiple_devices': 'Select Multiple Devices',
      'close_hidden_view': 'Close Hidden Devices View',
      'show_hidden_devices': 'Show Hidden Devices',

      // --- Round 17: GPS Weather — condition labels ---
      'weather_clear': 'Clear',
      'weather_clouds': 'Cloudy',
      'weather_rain': 'Rain',
      'weather_thunderstorm': 'Thunderstorm',
      'weather_snow': 'Snow',
      'weather_mist': 'Misty',

      // --- Round 22: App-driven WiFi setup (replaces captive portal) — add_device_dialog.dart ---
      'wifi_setup_header': 'WiFi Setup',
      'wifi_scanning_status': 'Scanning nearby WiFi networks...',
      'wifi_scan_empty_hint': 'No networks found — enter the WiFi name manually below',
      'wifi_ssid_hint': 'WiFi name (SSID)',
      'wifi_password_hint': 'WiFi password',
      'wifi_install_btn': 'INSTALL',
      // [Round 26] Optional checkbox to save WiFi password locally (add_device_dialog.dart)
      'save_wifi_checkbox': 'Save this Wi-Fi network for future setups',
      'wifi_ssid_required': 'Please choose or enter a WiFi name',
      'wifi_installing_status': 'Sending WiFi info to the device...',
      'wifi_send_failed_error': 'Could not send information to the device. Please check your local WiFi connection.',
      'wifi_retry_btn': 'RETRY',
      'wifi_rescan_btn': 'Rescan',

      // --- Round 23: Digital Twin — Rolling Door/Pump/Dimmer/Generic fallback ---
      'rolling_door_default_name': 'Rolling Door',
      'rolling_door_open_suffix': 'open',
      'pump_default_name': 'Water Pump',
      'pump_running_status': 'Running...',
      'pump_idle_status': 'Idle',
      'dimmer_default_name': 'Dimmer Light',
      'generic_device_default_name': 'Device',
      'on': 'On',
      'off': 'Off',
      'travel_time_label': 'Travel Time',
      'travel_time_desc': 'Seconds for the door to travel from 0% to 100% — used so the % Slider matches the real position',

      // --- Round 25: Direct MAC Binding — register straight by MAC (add_device_dialog.dart) ---
      'device_register_header': 'Registering Device',
      'device_registering_status': 'Registering device to the system...',
      // [Round 29] Internet Liveness Check — separate waiting phase before hitting the Cloud
      'device_waiting_internet_status': 'Waiting for your phone to reconnect to the Internet...',
      'device_registering_attempt_prefix': 'Retrying — attempt ',
      'device_owned_by_other_error': 'This device is already linked to another account. Please ask the previous owner to remove it, or perform a Hard Reset on the device to continue.',
      'device_register_forbidden_error': 'You do not have permission to add a device to this home.',
      'device_register_timeout_error': 'The device did not connect to the system after several attempts. Check the home WiFi password and try again.',
      'device_register_network_error': 'Could not reach the server — check your phone\'s mobile data/WiFi and try again.',
      'device_register_generic_error': 'Could not register the device — please try again.',
    },
  };
}
