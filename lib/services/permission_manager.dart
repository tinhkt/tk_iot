class PermissionManager {
  static const String superAdmin = 'SUPER_USER';
  static const String owner = 'HOME_OWNER';
  static const String admin = 'ADMIN';
  static const String user = 'USER';

  // SuperAdmin và Owner được thêm/xóa nhà
  static bool canManageHouses(String role) => role == superAdmin || role == owner;

  // Quyền quản lý thành viên (thêm/xóa Admin/User)
  static bool canManageMembers(String role) => role == superAdmin || role == owner || role == admin;
}