import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui'; 
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:window_manager/window_manager.dart'; 
import 'package:provider/provider.dart';

import '../providers/device_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import 'auth/login_screen.dart';
import 'admin/role_management_view.dart';
import 'devices/add_device_dialog.dart';
import 'admin/profile_management_view.dart';
import '../providers/notification_provider.dart';

// ============================================================================
// WIDGET HỖ TRỢ: HIỆU ỨNG KÍNH MỜ
// ============================================================================
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;

  const GlassContainer({super.key, required this.child, this.padding, this.width, this.height, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.95),
            borderRadius: radius,
            border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15), width: 1.5),
            boxShadow: [
              if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8))
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String targetMac = ''; 
  int _selectedIndex = 0;
  
  String userEmail = 'Đang tải...';
  String userRole = 'USER';

  // --- TRẠNG THÁI CỦA WIDGET CAMERA ---
  int _cameraViewMode = 1; 

  final Color tkGreen = const Color(0xFF00A651); 

  @override
  void initState() {
    super.initState();
    _initializeHome(); 
  }

  Future<void> _initializeHome() async {
    final token = await AuthService().getToken();
    if (token != null) {
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payloadStr = base64Url.normalize(parts[1]);
          final decoded = utf8.decode(base64Url.decode(payloadStr));
          final Map<String, dynamic> payload = jsonDecode(decoded);

          String role = payload['role'] ?? 'USER';
          String homeId = payload['home_id'] ?? '';
          String email = payload['email'] ?? 'Chưa xác định';

          if (role == 'SUPER_USER') {
            homeId = 'ECE334468B64'; 
          }

          setState(() {
            targetMac = homeId;
            userEmail = email;
            userRole = role;
          });

          if (targetMac.isNotEmpty && mounted) {
            Provider.of<DeviceProvider>(context, listen: false).fetchDeviceState(targetMac);
            Provider.of<NotificationProvider>(context, listen: false).fetchHistory();
            Provider.of<NotificationProvider>(context, listen: false).initMQTTListener(userEmail);
          }
        }
      } catch (e) {
        print("Lỗi giải mã token: $e");
      }
    }
  }

  // ==========================================================================
  // HỆ THỐNG XỬ LÝ TÀI KHOẢN
  // ==========================================================================
  
  void _performLogout(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    bool confirm = await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: GlassContainer(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.logout_rounded, size: 36, color: Colors.redAccent),
                ),
                const SizedBox(height: 24),
                Text('Đăng xuất', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(
                  'Bạn có chắc chắn muốn thoát khỏi hệ thống?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: textSub, fontSize: 14),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => Navigator.pop(context, false), 
                        child: const Text('Hủy', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Đăng xuất', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) ?? false;

    if (confirm) {
      await AuthService().logout();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
      }
    }
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isDialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
        final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassContainer(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_reset_rounded, color: tkGreen, size: 28),
                          const SizedBox(width: 12),
                          Text('Đổi mật khẩu', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextField(controller: oldPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu hiện tại', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 16),
                      TextField(controller: newPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 16),
                      TextField(controller: confirmPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Xác nhận mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isDialogLoading ? null : () => Navigator.pop(context),
                            child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: tkGreen, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: isDialogLoading ? null : () async {
                              final oldPass = oldPassCtrl.text.trim();
                              final newPass = newPassCtrl.text.trim();
                              final confirmPass = confirmPassCtrl.text.trim();

                              if (oldPass.isEmpty || newPass.isEmpty) return;
                              if (newPass != confirmPass) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu xác nhận không khớp!'), backgroundColor: Colors.redAccent));
                                return;
                              }

                              setDialogState(() => isDialogLoading = true);
                              String? error = await AuthService().changePassword(oldPass, newPass);
                              setDialogState(() => isDialogLoading = false);

                              if (error == null) {
                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công!'), backgroundColor: Color(0xFF00A651)));
                              } else {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
                              }
                            },
                            child: isDialogLoading 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Lưu thay đổi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }
    );
  }

  void _showAccountInfoDialog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    
    String friendlyRole = 'Thành viên (User)';
    IconData roleIcon = Icons.verified_user;
    Color roleColor = Colors.blue;

    switch (userRole) {
      case 'SUPER_USER':
        friendlyRole = 'Nhà phát triển (Super User)';
        roleIcon = Icons.developer_board;
        roleColor = Colors.purple;
        break;
      case 'HOME_OWNER':
        friendlyRole = 'Chủ nhà (Owner)';
        roleIcon = Icons.home_work_rounded;
        roleColor = Colors.orange;
        break;
      case 'ADMIN':
        friendlyRole = 'Quản trị viên (Admin)';
        roleIcon = Icons.admin_panel_settings;
        roleColor = Colors.teal;
        break;
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: GlassContainer(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Thông tin tài khoản', style: TextStyle(color: tkGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                CircleAvatar(radius: 46, backgroundColor: tkGreen.withValues(alpha: 0.15), child: Icon(Icons.person, size: 46, color: tkGreen)),
                const SizedBox(height: 20),
                Text(userEmail, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textMain), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: Icon(roleIcon, color: roleColor, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cấp quyền hệ thống', style: TextStyle(fontSize: 11, color: textSub)),
                            const SizedBox(height: 4),
                            Text(friendlyRole, style: TextStyle(fontWeight: FontWeight.bold, color: textMain, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.pop(context), 
                    child: const Text('Đóng', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- HÀM MỞ SETTINGS/PROFILE TỪ AVATAR MENU ---
  void _openProfileOrSettings(int tabIndex) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    if (isMobile) {
      setState(() => _selectedIndex = 4); 
    } else {
      _showSettingsMenu(initialTab: tabIndex);
    }
  }

  Widget _buildUserAvatarMenu(Color textMain) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuButton<int>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      tooltip: 'Tài khoản của tôi',
      child: const CircleAvatar(radius: 20, backgroundColor: Color(0xFF00A651), child: Icon(Icons.person, color: Colors.white)),
      onSelected: (value) {
        switch (value) {
          case 0: _openProfileOrSettings(0); break; // Tab 0: Hồ sơ
          case 1: _openProfileOrSettings(2); break; // Tab 2: Bảo mật
          case 2: _onMenuTapped(3); break; // Phân quyền
          case 3: _performLogout(context); break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.account_circle_outlined, color: textMain), const SizedBox(width: 12), Text('Hồ sơ tài khoản', style: TextStyle(color: textMain))])),
        PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.lock_reset, color: textMain), const SizedBox(width: 12), Text('Đổi mật khẩu', style: TextStyle(color: textMain))])),
        PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.security, color: textMain), const SizedBox(width: 12), Text('Quản lý phân quyền', style: TextStyle(color: textMain))])),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.logout, color: Colors.redAccent), SizedBox(width: 12), Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])),
      ],
    );
  }

  void _showSettingsMenu({int initialTab = 0}) {
    showDialog(
      context: context,
      barrierDismissible: true, 
      barrierColor: Colors.black.withValues(alpha: 0.5), 
      builder: (context) => WindowsSettingsDialog(
        currentRole: userRole,
        currentEmail: userEmail,
        initialTab: initialTab,
      ),
    );
  }

  void _showThemeDialog() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color surface = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        final themeProvider = Provider.of<ThemeProvider>(context);
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Giao diện', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: tkGreen)),
                  IconButton(icon: Icon(Icons.close, color: textMain), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 8),
              RadioListTile<ThemeMode>(title: Text('Chế độ Sáng', style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: ThemeMode.light, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
              RadioListTile<ThemeMode>(title: Text('Chế độ Tối', style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), value: ThemeMode.dark, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
              RadioListTile<ThemeMode>(title: Text('Tự động theo thiết bị', style: TextStyle(fontWeight: FontWeight.w600, color: textMain)), subtitle: const Text('Đổi màu theo ban ngày/ban đêm'), value: ThemeMode.system, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
            ],
          ),
        );
      }
    );
  }

  void _onMenuTapped(int index, {bool isFromDrawer = false}) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    
    if (isFromDrawer && isMobile) {
      Navigator.pop(context); 
    }
    
    // Nếu là Desktop và ấn vào Cài đặt -> Mở Popup Settings (Tab 0 mặc định)
    if (index == 4 && !isMobile) { 
      _showSettingsMenu(initialTab: 0);
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  // ==========================================================================
  // HỆ THỐNG THÔNG BÁO (NOTIFICATION)
  // ==========================================================================
  void _showNotificationPanel(Color textMain, Color textSub) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    Provider.of<NotificationProvider>(context, listen: false).clearNewBadge();

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (context) {
        return Align(
          alignment: Alignment.topRight,
          child: Container(
            margin: const EdgeInsets.only(top: 70, right: 80), 
            width: 380,
            child: Material(
              color: Colors.transparent,
              child: GlassContainer(
                padding: EdgeInsets.zero,
                borderRadius: BorderRadius.circular(16),
                child: Consumer<NotificationProvider>( 
                  builder: (context, notifProvider, child) {
                    final listNotif = notifProvider.list;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Thông báo hệ thống', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                              Text('Tổng số: ${listNotif.length}', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
                        
                        if (listNotif.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Center(child: Text('Không có thông báo nào gần đây.', style: TextStyle(color: textSub, fontSize: 13))),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 400),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: const BouncingScrollPhysics(),
                              itemCount: listNotif.length,
                              separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: isDark ? Colors.white10 : Colors.grey.shade100),
                              itemBuilder: (context, index) {
                                final notif = listNotif[index];
                                IconData icon;
                                if (notif.type == 'ALERT') {
                                  icon = Icons.warning_amber_rounded;
                                } else if (notif.type == 'SYSTEM') icon = Icons.system_security_update_good_rounded;
                                else if (notif.type == 'DEVICE') icon = Icons.power_off_outlined;
                                else icon = Icons.info_outline_rounded;
                                Color notifColor = Color(int.parse(notif.color));

                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  hoverColor: isDark ? Colors.white10 : Colors.grey.shade50,
                                  leading: CircleAvatar(backgroundColor: notifColor.withValues(alpha: 0.12), child: Icon(icon, color: notifColor, size: 20)),
                                  title: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(notif.title, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                      Text(notif.time, style: TextStyle(color: textSub, fontSize: 11)),
                                    ],
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(notif.message, style: TextStyle(color: textSub, height: 1.4, fontSize: 13)),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildNotificationBell(Color textMain, Color textSub) {
    return Consumer<NotificationProvider>(
      builder: (context, notifProvider, child) {
        return Stack(
          children: [
            IconButton(
              icon: Icon(Icons.notifications_none_rounded, color: textMain),
              onPressed: () => _showNotificationPanel(textMain, textSub),
            ),
            if (notifProvider.hasNewNotification) 
              Positioned(top: 12, right: 12, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)))
          ],
        );
      },
    );
  }

  // ==========================================================================
  // KHUNG GIAO DIỆN PREMIUM CHÍNH
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color bgLight = isDark ? const Color(0xFF0B1120) : const Color(0xFFF4F7FC); 
    final Color surfaceLight = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgLight,
      appBar: isMobile
          ? AppBar(
              backgroundColor: isDark ? surfaceLight : bgLight,
              elevation: 0,
              iconTheme: IconThemeData(color: tkGreen),
              title: Text(
                _selectedIndex == 3 ? 'PHÂN QUYỀN' :
                _selectedIndex == 4 ? 'CÀI ĐẶT' : 'MY HOME', 
                style: TextStyle(color: textMain, fontWeight: FontWeight.w900, letterSpacing: 1.2)
              ),
              centerTitle: true,
              actions: _selectedIndex == 4 ? [] : [
                _buildNotificationBell(textMain, textSub),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: _buildUserAvatarMenu(textMain),
                ),
              ],
            )
          : null,
      
      drawer: isMobile ? _buildMobileDrawer(isDark, surfaceLight, textMain, textSub) : null,
      
      body: Column(
        children: [
          if (!kIsWeb && !isMobile && (Platform.isWindows || Platform.isMacOS || Platform.isLinux))
            _buildCustomTitleBar(isDark),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) _buildDesktopFloatingSidebar(isDark, textMain, textSub),
                Expanded(
                  child: SafeArea(
                    child: _selectedIndex == 3 
                        ? const RoleManagementView()
                        : _selectedIndex == 4 && isMobile
                            ? _buildMobileSettingsView(isDark, textMain, textSub) 
                            : isMobile 
                                ? _buildMobileContent(isDark, surfaceLight, textMain, textSub) 
                                : Padding(
                                    padding: const EdgeInsets.fromLTRB(32.0, 16.0, 32.0, 24.0),
                                    child: _buildBentoDashboard(isDark, textMain, textSub),
                                  ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile ? _buildBottomNav(surfaceLight, textSub) : null,
    );
  }

  Widget _buildMobileSettingsView(bool isDark, Color textMain, Color textSub) {
    Widget buildSettingGroup(List<Widget> children) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: GlassContainer(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSettingGroup([
            ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(radius: 30, backgroundColor: tkGreen.withValues(alpha: 0.2), child: Icon(Icons.person, color: tkGreen, size: 32)),
              title: Text(userEmail, style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text('Quyền: $userRole', style: TextStyle(color: textSub, fontWeight: FontWeight.w600)),
              ),
              trailing: Icon(Icons.edit_outlined, color: textSub),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => Scaffold(
                    appBar: AppBar(title: const Text('Hồ sơ tài khoản'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0),
                    backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF4F7FC),
                    body: SafeArea(child: ProfileManagementView(currentRole: userRole, currentEmail: userEmail)),
                  )
                ));
              },
            ),
          ]),

          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text('CHUNG', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          buildSettingGroup([
            ListTile(
              leading: Icon(Icons.palette_outlined, color: textMain),
              title: Text('Giao diện màu sắc', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right, color: textSub),
              onTap: () => _showThemeDialog(),
            ),
          ]),

          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text('BẢO MẬT', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          buildSettingGroup([
            ListTile(
              leading: Icon(Icons.lock_outline, color: textMain),
              title: Text('Đổi mật khẩu', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right, color: textSub),
              onTap: () => _showChangePasswordDialog(),
            ),
          ]),

          Padding(
            padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
            child: Text('HỆ THỐNG', style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
          buildSettingGroup([
            ListTile(
              leading: Icon(Icons.dns_outlined, color: textMain),
              title: Text('Máy chủ', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
              trailing: Text('Armbian OS', style: TextStyle(color: textSub)),
            ),
            Divider(height: 1, indent: 16, endIndent: 16, color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.2)),
            ListTile(
              leading: Icon(Icons.info_outline, color: textMain),
              title: Text('Phiên bản phần mềm', style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
              trailing: Text('3.0.1 (Stable)', style: TextStyle(color: textSub)),
            ),
          ]),

          buildSettingGroup([
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Đăng xuất khỏi thiết bị', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () => _performLogout(context),
            ),
          ]),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCustomTitleBar(bool isDark) {
    return DragToMoveArea(
      child: Container(
        height: 36,
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(Icons.minimize, size: 16, color: isDark ? Colors.white54 : Colors.black54),
              onPressed: () => windowManager.minimize(),
              splashRadius: 20,
            ),
            IconButton(
              icon: Icon(Icons.crop_square, size: 16, color: isDark ? Colors.white54 : Colors.black54),
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  windowManager.unmaximize();
                } else {
                  windowManager.maximize();
                }
              },
              splashRadius: 20,
            ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: isDark ? Colors.white54 : Colors.black54),
              hoverColor: Colors.redAccent,
              onPressed: () => windowManager.close(),
              splashRadius: 20,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopFloatingSidebar(bool isDark, Color txtMain, Color txtSub) {
    return Container(
      width: 260,
      margin: const EdgeInsets.only(left: 24, bottom: 24, top: 16),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 40),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.home_rounded, color: tkGreen, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TUAN KIET', style: TextStyle(color: tkGreen, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)),
                      Text('CloudPlatform', style: TextStyle(color: txtSub, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildMenuItem(0, Icons.dashboard_rounded, 'Bảng điều khiển', txtMain, txtSub),
                  _buildMenuItem(1, Icons.maps_home_work_rounded, 'Phòng ban', txtMain, txtSub),
                  _buildMenuItem(2, Icons.auto_awesome_rounded, 'Ngữ cảnh', txtMain, txtSub),
                  _buildMenuItem(3, Icons.security_rounded, 'Phân quyền', txtMain, txtSub),
                  _buildMenuItem(4, Icons.settings_rounded, 'Cài đặt', txtMain, txtSub),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileDrawer(bool isDark, Color surface, Color txtMain, Color txtSub) {
    return Container(
      width: 260,
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(top: 60, bottom: 24, left: 24),
            child: Row(
              children: [
                Icon(Icons.home_rounded, color: tkGreen, size: 36),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('TUAN KIET', style: TextStyle(color: tkGreen, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
                    Text('CloudPlatform', style: TextStyle(color: txtSub, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  ],
                ),
              ],
            ),
          ),
          Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                _buildMenuItem(0, Icons.dashboard_rounded, 'Điều khiển', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(1, Icons.maps_home_work_rounded, 'Phòng ban', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(2, Icons.auto_awesome_rounded, 'Ngữ cảnh', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(3, Icons.security_rounded, 'Phân quyền', txtMain, txtSub, isFromDrawer: true),
                _buildMenuItem(4, Icons.settings_rounded, 'Cài đặt', txtMain, txtSub, isFromDrawer: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String title, Color txtMain, Color txtSub, {bool isFromDrawer = false}) {
    bool isSelected = _selectedIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? tkGreen.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? tkGreen.withValues(alpha: 0.3) : Colors.transparent),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: isSelected ? tkGreen : txtSub, size: 22),
        title: Text(title, style: TextStyle(color: isSelected ? tkGreen : txtMain, fontSize: 14, fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
        onTap: () => _onMenuTapped(index, isFromDrawer: isFromDrawer),
      ),
    );
  }

  Widget _buildBottomNav(Color surface, Color txtSub) {
    return BottomNavigationBar(
      backgroundColor: surface,
      selectedItemColor: tkGreen,
      unselectedItemColor: txtSub,
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex, 
      onTap: (index) => _onMenuTapped(index), 
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Điều khiển'),
        BottomNavigationBarItem(icon: Icon(Icons.maps_home_work_rounded), label: 'Phòng'),
        BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Ngữ cảnh'),
        BottomNavigationBarItem(icon: Icon(Icons.security_rounded), label: 'Phân quyền'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Cài đặt'),
      ],
    );
  }

  // ==========================================================================
  // [BẢN CẬP NHẬT] DESKTOP DASHBOARD (CHỐNG TRÀN VÀ CHỐNG KÉO GIÃN VÔ HẠN)
  // ==========================================================================
  Widget _buildBentoDashboard(bool isDark, Color textMain, Color textSub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Xin chào!', style: TextStyle(color: textSub, fontSize: 16)),
                Text('Tổng quan Ngôi nhà', style: TextStyle(color: textMain, fontSize: 28, fontWeight: FontWeight.w900)),
              ],
            ),
            Row(
              children: [
                _buildNotificationBell(textMain, textSub),
                const SizedBox(width: 16),
                _buildUserAvatarMenu(textMain),
              ],
            )
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(flex: 4, child: _buildWeatherBento(isDark, textMain, textSub)),
            const SizedBox(width: 24),
            Expanded(flex: 6, child: _buildSensorsBento(isDark, textMain, textSub)),
          ],
        ),
        const SizedBox(height: 24),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CỘT TRÁI: THIẾT BỊ (Cuộn độc lập)
              Expanded(
                flex: 7,
                child: GlassContainer(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Thiết bị thông minh', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (userRole == 'SUPER_USER' || userRole == 'HOME_OWNER')
                                IconButton(
                                  icon: Icon(Icons.add_circle_outline_rounded, color: tkGreen, size: 24),
                                  tooltip: 'Thêm thiết bị mới',
                                  onPressed: () async {
                                    final result = await showDialog(
                                      context: context,
                                      barrierColor: Colors.black.withValues(alpha: 0.6),
                                      builder: (context) => const AddDeviceDialog(),
                                    );
                                    if (result == true) _initializeHome();
                                  },
                                ),
                              IconButton(
                                icon: Icon(Icons.refresh, color: textSub), 
                                onPressed: () {
                                  if (targetMac.isNotEmpty) Provider.of<DeviceProvider>(context, listen: false).fetchDeviceState(targetMac);
                                }
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildDevicesGrid(isDark, textMain, textSub),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              
              // CỘT PHẢI: WIDGET ĐIỆN & CAMERA (Cuộn dọc, giữ nguyên form dáng)
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildEnergyWidget(isDark, textMain, textSub),
                      const SizedBox(height: 24),
                      _buildCameraWidget(isDark, textMain, textSub),
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnergyWidget(bool isDark, Color textMain, Color textSub) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, color: tkGreen, size: 22),
                  const SizedBox(width: 8),
                  Text('Điện năng', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: Icon(Icons.open_in_new_rounded, color: textSub, size: 20),
                tooltip: 'Xem chi tiết',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng Thống kê chi tiết đang được phát triển.')));
                },
              )
            ],
          ),
          const SizedBox(height: 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Hôm nay', style: TextStyle(color: textSub, fontSize: 13)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('14.5', style: TextStyle(color: textMain, fontSize: 40, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 4),
                  Text('kWh', style: TextStyle(color: tkGreen, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.white10 : Colors.black12, height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text('Đang tiêu thụ', style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, child: Text('2,104 W', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 8)),
                  Expanded(
                    child: Column(
                      children: [
                        Text('Tháng này', style: TextStyle(color: textSub, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        FittedBox(fit: BoxFit.scaleDown, child: Text('124 kWh', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCameraWidget(bool isDark, Color textMain, Color textSub) {
    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // Bo gọn nội dung bên trong
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_rounded, color: Colors.blueAccent, size: 22),
                  const SizedBox(width: 8),
                  Text('Camera', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 28,
                    decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _cameraViewMode = 1),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: _cameraViewMode == 1 ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(6)), child: Center(child: Icon(Icons.crop_din_rounded, size: 16, color: _cameraViewMode == 1 ? Colors.white : textSub))),
                        ),
                        InkWell(
                          onTap: () => setState(() => _cameraViewMode = 4),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: _cameraViewMode == 4 ? Colors.blueAccent : Colors.transparent, borderRadius: BorderRadius.circular(6)), child: Center(child: Icon(Icons.grid_view_rounded, size: 16, color: _cameraViewMode == 4 ? Colors.white : textSub))),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.open_in_new_rounded, color: textSub, size: 20),
                    tooltip: 'Mở trình quản lý Camera',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trình xem phát lại và quản lý luồng Camera đang được phát triển.')));
                    },
                  )
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          
          // SỬ DỤNG TỶ LỆ KHUNG HÌNH (ASPECT RATIO) THAY VÌ CHIỀU CAO TĨNH
          _cameraViewMode == 1 
            ? AspectRatio(
                aspectRatio: 16 / 9, // Tỷ lệ chuẩn của 1 Camera
                child: Container(
                  decoration: BoxDecoration(color: isDark ? Colors.black45 : Colors.grey.shade300, borderRadius: BorderRadius.circular(12)), 
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min, 
                      children: [
                        Icon(Icons.videocam_off_rounded, color: textSub, size: 32), 
                        const SizedBox(height: 8), 
                        Text('Ngoại tuyến', style: TextStyle(color: textSub, fontSize: 12))
                      ]
                    )
                  )
                ),
              )
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(), // Tắt cuộn lưới vì đã có cuộn ngoài
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,      // Chia 2 cột
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 4 / 3, // Ép tỷ lệ 4:3 để cam không bị kéo dài thòng lọng
                ),
                itemCount: 4,
                itemBuilder: (context, index) {
                  return Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black45 : Colors.grey.shade300, 
                      borderRadius: BorderRadius.circular(8)
                    ), 
                    child: Center(child: Icon(Icons.videocam_off_rounded, color: textSub)),
                  );
                },
              )
        ],
      ),
    );
  }

  Widget _buildMobileContent(bool isDark, Color surfaceLight, Color textMain, Color textSub) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeatherBento(isDark, textMain, textSub),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              children: [
                _buildMiniStatusMobile(Icons.thermostat, 'Nhiệt độ', '31.0°C', Colors.orange, textMain, textSub),
                const SizedBox(width: 12),
                _buildMiniStatusMobile(Icons.water_drop, 'Độ ẩm', '66%', Colors.blue, textMain, textSub),
                const SizedBox(width: 12),
                _buildMiniStatusMobile(Icons.bolt, 'Tiêu thụ', '2.1 kW', tkGreen, textMain, textSub),
                const SizedBox(width: 12),
                _buildMiniStatusMobile(Icons.security, 'An ninh', 'BẬT', Colors.redAccent, textMain, textSub),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Thiết bị yêu thích', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (userRole == 'SUPER_USER' || userRole == 'HOME_OWNER')
                    IconButton(
                      icon: Icon(Icons.add_circle_outline_rounded, color: tkGreen, size: 24),
                      tooltip: 'Thêm thiết bị mới',
                      onPressed: () async {
                        final result = await showDialog(
                          context: context,
                          barrierColor: Colors.black.withValues(alpha: 0.6),
                          builder: (context) => const AddDeviceDialog(),
                        );
                        if (result == true) _initializeHome();
                      },
                    ),
                  IconButton(icon: Icon(Icons.refresh, color: textSub), onPressed: () {
                    if (targetMac.isNotEmpty) Provider.of<DeviceProvider>(context, listen: false).fetchDeviceState(targetMac);
                  }),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDevicesGrid(isDark, textMain, textSub),
          const SizedBox(height: 24),
          
          // XÓA SIZEDBOX ÉP CHIỀU CAO - ĐỂ NÓ TỰ DO
          _buildEnergyWidget(isDark, textMain, textSub),
          const SizedBox(height: 16),
          
          // XÓA SIZEDBOX ÉP CHIỀU CAO - ĐỂ NÓ TỰ DO
          _buildCameraWidget(isDark, textMain, textSub),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildWeatherBento(bool isDark, Color txtMain, Color txtSub) {
    return GlassContainer(
      child: Row(
        children: [
          Container(width: 70, height: 70, decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle), child: Icon(Icons.cloud_queue_rounded, color: tkGreen, size: 36)),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text('Hà Nội, VN', style: TextStyle(color: txtSub, fontSize: 13, fontWeight: FontWeight.w600)), Text('31.0°C', style: TextStyle(color: txtMain, fontSize: 28, fontWeight: FontWeight.w900))]))
        ],
      ),
    );
  }

  Widget _buildSensorsBento(bool isDark, Color txtMain, Color txtSub) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildMiniStatusDesktop(Icons.water_drop, 'Độ ẩm', '66%', Colors.blue, txtMain, txtSub),
          Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          _buildMiniStatusDesktop(Icons.bolt, 'Tiêu thụ', '2.1 kW', tkGreen, txtMain, txtSub),
          Container(width: 1, height: 40, color: isDark ? Colors.white10 : Colors.grey.shade300),
          _buildMiniStatusDesktop(Icons.security, 'An ninh', 'BẬT', Colors.redAccent, txtMain, txtSub),
        ],
      ),
    );
  }

  Widget _buildMiniStatusDesktop(IconData icon, String label, String val, Color color, Color txtMain, Color txtSub) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(color: txtSub, fontSize: 13))]), const SizedBox(height: 8), Text(val, style: TextStyle(color: txtMain, fontSize: 18, fontWeight: FontWeight.bold))]);
  }

  Widget _buildMiniStatusMobile(IconData icon, String title, String value, Color color, Color txtMain, Color txtSub) {
    return GlassContainer(width: 140, padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 24), const SizedBox(height: 8), Text(title, style: TextStyle(color: txtSub, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text(value, style: TextStyle(color: txtMain, fontSize: 20, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)]));
  }

  Widget _buildDevicesGrid(bool isDark, Color textMain, Color textSub) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, child) {
        if (targetMac.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('Đang thiết lập kết nối...', style: TextStyle(color: textSub))));
        if (provider.isLoading) return Center(child: Padding(padding: const EdgeInsets.all(40), child: CircularProgressIndicator(color: tkGreen)));
        if (provider.deviceState == null || provider.deviceState!.endpoints.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Icon(Icons.devices_other_rounded, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('Chưa có thiết bị nào', style: TextStyle(color: textSub, fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
                  onPressed: () async {
                    final result = await showDialog(context: context, barrierColor: Colors.black.withValues(alpha: 0.6), builder: (context) => const AddDeviceDialog());
                    if (result == true) _initializeHome();
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text('Thêm thiết bị', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        }

        final endpoints = provider.deviceState!.endpoints;
        final fans = endpoints.entries.where((e) => e.key.startsWith('F_')).toList();
        final switches = endpoints.entries.where((e) => !e.key.startsWith('F_')).toList();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fans.isNotEmpty) Wrap(spacing: 16, runSpacing: 16, children: fans.map((e) => SmartFanCard(mac: targetMac, endpoint: e.key, initialSpeed: e.value.speed ?? 0, initialSwing: e.value.swing == true, provider: provider)).toList()),
            const SizedBox(height: 24),
            if (switches.isNotEmpty) GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: switches.length, gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.0), itemBuilder: (context, index) { String key = switches[index].key; String? backendName = switches[index].value.name; bool isOnline = switches[index].value.state == 'ON'; return SmartSwitchCard(mac: targetMac, endpointKey: key, backendName: backendName, initialStatus: isOnline, provider: provider); }),
          ],
        );
      },
    );
  }
}

// ============================================================================
// WIDGET POPUP CÀI ĐẶT DÀNH CHO DESKTOP
// ============================================================================
class WindowsSettingsDialog extends StatefulWidget {
  final String currentRole;
  final String currentEmail;
  final int initialTab;

  const WindowsSettingsDialog({
    super.key, 
    required this.currentRole, 
    required this.currentEmail,
    this.initialTab = 0,
  });

  @override
  State<WindowsSettingsDialog> createState() => _WindowsSettingsDialogState();
}

class _WindowsSettingsDialogState extends State<WindowsSettingsDialog> {
  late int _selectedTab;
  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color sidebarColor = isDark ? Colors.white.withValues(alpha: 0.02) : Colors.grey.withValues(alpha: 0.05);

    return Dialog(
      backgroundColor: Colors.transparent, 
      insetPadding: const EdgeInsets.all(24), 
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 650),
        child: GlassContainer(
          padding: EdgeInsets.zero, 
          borderRadius: BorderRadius.circular(20),
          child: Row(
            children: [
              Container(
                width: 240,
                decoration: BoxDecoration(
                  color: sidebarColor,
                  border: Border(right: BorderSide(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.2))),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 16.0),
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(color: isDark ? Colors.black26 : Colors.white70, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.3))),
                        child: Row(children: [const SizedBox(width: 8), Icon(Icons.search, size: 16, color: textSub), const SizedBox(width: 8), Text('Tìm kiếm', style: TextStyle(color: textSub, fontSize: 13))]),
                      ),
                    ),
                    _buildTabButton(0, Icons.person_outline, 'Hồ sơ tài khoản', textMain),
                    _buildTabButton(1, Icons.palette_outlined, 'Giao diện', textMain),
                    _buildTabButton(2, Icons.shield_outlined, 'Bảo mật & Mật khẩu', textMain),
                    _buildTabButton(3, Icons.info_outline, 'Thông tin hệ thống', textMain),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: InkWell(
                        onTap: () async {
                          Navigator.pop(context); 
                          await AuthService().logout();
                          if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10), alignment: Alignment.center,
                          decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: const Text('Đăng xuất', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    )
                  ],
                ),
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0, right: 12.0),
                          child: IconButton(icon: Icon(Icons.close, size: 24, color: textSub), hoverColor: Colors.redAccent.withValues(alpha: 0.1), onPressed: () => Navigator.pop(context), splashRadius: 20),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32.0, 0, 32.0, 32.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedTab != 0) ...[
                              Text(
                                _selectedTab == 1 ? 'Giao diện (Appearance)' : 
                                _selectedTab == 2 ? 'Bảo mật & Mật khẩu' : 'Thông tin hệ thống',
                                style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 32),
                            ],
                            Expanded(
                              child: _selectedTab == 0 ? ProfileManagementView(currentRole: widget.currentRole, currentEmail: widget.currentEmail) :
                                     _selectedTab == 1 ? _buildAppearanceTab(textMain, textSub) :
                                     _selectedTab == 2 ? _buildSecurityTab(textMain, textSub) :
                                     _buildInfoTab(textMain, textSub),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String title, Color txtMain) {
    bool isSelected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: isSelected ? tkGreen : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : txtMain),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(color: isSelected ? Colors.white : txtMain, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppearanceTab(Color textMain, Color textSub) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color boxColor = isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chủ đề màu sắc', style: TextStyle(color: textSub, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              RadioListTile<ThemeMode>(title: Text('Chế độ Sáng (Light)', style: TextStyle(color: textMain, fontWeight: FontWeight.w500)), value: ThemeMode.light, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
              RadioListTile<ThemeMode>(title: Text('Chế độ Tối (Dark)', style: TextStyle(color: textMain, fontWeight: FontWeight.w500)), value: ThemeMode.dark, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black12, indent: 50),
              RadioListTile<ThemeMode>(title: Text('Tự động theo hệ thống', style: TextStyle(color: textMain, fontWeight: FontWeight.w500)), value: ThemeMode.system, groupValue: themeProvider.themeMode, activeColor: tkGreen, onChanged: (val) => themeProvider.setThemeMode(val!)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildSecurityTab(Color textMain, Color textSub) {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Thay đổi mật khẩu tài khoản hiện tại', style: TextStyle(color: textSub, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: oldPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu cũ', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),
          TextField(controller: newPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 16),
          TextField(controller: confirmPassCtrl, obscureText: true, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Xác nhận lại mật khẩu mới', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 45,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                final oldPass = oldPassCtrl.text.trim();
                final newPass = newPassCtrl.text.trim();
                if (oldPass.isEmpty || newPass.isEmpty) return;
                if (newPass != confirmPassCtrl.text.trim()) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu xác nhận không khớp!'), backgroundColor: Colors.redAccent));
                  return;
                }
                String? error = await AuthService().changePassword(oldPass, newPass);
                if (error == null) {
                  if (!context.mounted) return;
                  oldPassCtrl.clear(); newPassCtrl.clear(); confirmPassCtrl.clear();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công!'), backgroundColor: Color(0xFF00A651)));
                } else {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
                }
              },
              child: const Text('Cập nhật mật khẩu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoTab(Color textMain, Color textSub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: Icon(Icons.home_rounded, color: tkGreen, size: 48),
              ),
              const SizedBox(height: 16),
              Text('TK_IOT CloudPlatform', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.w900)),
              Text('Phiên bản 3.0.1 (Stable)', style: TextStyle(color: textSub, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 40),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.dns, color: textSub),
          title: Text('Máy chủ', style: TextStyle(color: textSub, fontSize: 13)),
          subtitle: Text('MQTT Core Golang (Armbian)', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.copyright, color: textSub),
          title: Text('Bản quyền', style: TextStyle(color: textSub, fontSize: 13)),
          subtitle: Text('© 2026 Tuan Kiet Solutions.', style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ============================================================================
// 💡 CÔNG TẮC ĐÈN
// ============================================================================
class SmartSwitchCard extends StatefulWidget {
  final String mac;
  final String endpointKey;
  final String? backendName;
  final bool initialStatus;
  final DeviceProvider provider;

  const SmartSwitchCard({super.key, required this.mac, required this.endpointKey, this.backendName, required this.initialStatus, required this.provider});

  @override
  State<SmartSwitchCard> createState() => _SmartSwitchCardState();
}

class _SmartSwitchCardState extends State<SmartSwitchCard> {
  late bool isOnline;
  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    isOnline = widget.initialStatus;
  }

  @override
  void didUpdateWidget(SmartSwitchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus) isOnline = widget.initialStatus;
  }

  void _toggleSwitch() {
    bool oldState = isOnline;
    setState(() => isOnline = !isOnline); 
    widget.provider.toggleDevice(widget.mac, widget.endpointKey, oldState);
  }

  String _formatName() {
    if (widget.backendName != null && widget.backendName!.isNotEmpty) return widget.backendName!;
    if (widget.endpointKey.startsWith('S_')) {
      String shortHex = widget.endpointKey.substring(2);
      if (shortHex.length > 4) shortHex = shortHex.substring(0, 4);
      return 'Công tắc $shortHex';
    }
    return widget.endpointKey;
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isOnline ? tkGreen.withValues(alpha: isDark ? 0.8 : 0.95) : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.95));
    final Color iconColor = isOnline ? Colors.white : (isDark ? Colors.white38 : Colors.black45);
    final Color textColor = isOnline ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final Color powerIconColor = isOnline ? Colors.white : (isDark ? Colors.white24 : Colors.grey.shade400);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isOnline ? tkGreen : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2)), width: 1.5),
            boxShadow: [if (!isDark && !isOnline) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleSwitch,
              child: Stack(
                children: [
                  Positioned(top: 14, left: 14, child: Icon(Icons.lightbulb_outline, color: isOnline ? Colors.white : tkGreen, size: 22)),
                  Positioned(top: 14, right: 14, child: Icon(Icons.more_horiz, color: iconColor, size: 18)),
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12.0, top: 10.0),
                      child: Icon(Icons.power_settings_new_rounded, color: powerIconColor, size: 54),
                    ),
                  ),
                  Positioned(
                    bottom: 14, left: 8, right: 8,
                    child: Text(_formatName(), textAlign: TextAlign.center, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 🌀 QUẠT THÔNG MINH
// ============================================================================
class SmartFanCard extends StatefulWidget {
  final String mac;
  final String endpoint;
  final int initialSpeed;
  final bool initialSwing;
  final DeviceProvider provider;

  const SmartFanCard({super.key, required this.mac, required this.endpoint, required this.initialSpeed, required this.initialSwing, required this.provider});

  @override
  State<SmartFanCard> createState() => _SmartFanCardState();
}

class _SmartFanCardState extends State<SmartFanCard> {
  late int speed; 
  late bool swing;
  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    speed = widget.initialSpeed;
    swing = widget.initialSwing;
  }

  @override
  void didUpdateWidget(SmartFanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSwing != widget.initialSwing) swing = widget.initialSwing;
    if (oldWidget.initialSpeed != widget.initialSpeed) speed = widget.initialSpeed;
  }

  void _changeSpeed(int newSpeed) {
    setState(() => speed = newSpeed);
    widget.provider.setFanSpeed(widget.mac, widget.endpoint, speed, swing);
  }

  void _toggleSwing() {
    if (speed == 0) return; 
    setState(() => swing = !swing); 
    widget.provider.setFanSpeed(widget.mac, widget.endpoint, speed, swing);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isOnline = speed > 0;
    bool isSwingActive = swing && isOnline;

    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 450), 
      child: GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: isOnline ? tkGreen.withValues(alpha: 0.15) : (isDark ? Colors.white10 : Colors.grey.shade100), shape: BoxShape.circle),
                  child: Icon(Icons.mode_fan_off, color: isOnline ? tkGreen : textSub, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quạt thông minh', style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(isOnline ? 'Đang bật • Số $speed' : 'Đã tắt', style: TextStyle(color: isOnline ? tkGreen : textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildBtn(0, 'OFF', speed == 0, isDark),
                _buildBtn(1, '1', speed == 1, isDark),
                _buildBtn(2, '2', speed == 2, isDark),
                _buildBtn(3, '3', speed == 3, isDark),
                Container(width: 1, height: 30, color: isDark ? Colors.white10 : Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 4)),
                
                Material(
                  color: isSwingActive ? tkGreen : (isDark ? Colors.white24 : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _toggleSwing,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.threesixty, color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), size: 18),
                          const SizedBox(width: 6),
                          Text('Xoay', style: TextStyle(color: isSwingActive ? Colors.white : (isDark ? Colors.white : Colors.black87), fontSize: 13, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBtn(int btnSpeed, String label, bool isActive, bool isDark) {
    bool isOffBtn = btnSpeed == 0;
    Color bgColor = isActive ? (isOffBtn ? Colors.redAccent : tkGreen) : (isDark ? Colors.white10 : Colors.grey.shade200);
    Color textColor = isActive ? Colors.white : (isDark ? Colors.white : Colors.black87);

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _changeSpeed(btnSpeed),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}