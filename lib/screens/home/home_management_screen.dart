import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/permission_manager.dart';
import '../../services/auth_service.dart';
import '../../providers/home_provider.dart';
import '../../widgets/glass_container.dart';
import 'device_list_screen.dart';
import 'member_list_screen.dart';

// ============================================================================
// MÀN HÌNH QUẢN LÝ NHÀ CHÍNH
// ============================================================================
class HomeManagementScreen extends StatefulWidget {
  final String userRole; // Quyền TOÀN CỤC (SUPER_USER, USER...)
  final String userEmail; // Email người đang đăng nhập — cần để tự "Rời khỏi nhà" (self-leave)

  const HomeManagementScreen({super.key, required this.userRole, required this.userEmail});

  @override
  State<HomeManagementScreen> createState() => _HomeManagementScreenState();
}

class _HomeManagementScreenState extends State<HomeManagementScreen> {
  final Color tkGreen = const Color(0xFF00A651);

  final String baseUrl = "https://api.iot-smart.vn/api";

  @override
  void initState() {
    super.initState();
    // Nạp sau frame đầu — context.read cần cây widget (Provider) đã build xong.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchHomesFromAPI());
  }

  // =======================================================================
  // 1. GỌI API LẤY DANH SÁCH NHÀ — qua HomeProvider (NGUỒN SỰ THẬT DUY NHẤT, dùng
  // chung với MemberListScreen). Trước đây màn hình này tự fetch + giữ state riêng
  // (_realHomes cục bộ) trong khi MemberListScreen tự fetch/mock riêng — 2 nguồn dữ
  // liệu tách biệt chính là gốc rễ lệch số lượng "T.viên" khi bấm Back. Nay CẢ HAI
  // màn hình cùng đọc/ghi một HomeProvider -> Provider.notifyListeners() sau
  // addMember/removeMember tự động vẽ lại Card này, không cần code gì thêm ở đây.
  // =======================================================================
  Future<void> _fetchHomesFromAPI() async {
    try {
      await context.read<HomeProvider>().fetchHomes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải dữ liệu: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  // [NHÚNG, KHÔNG PUSH] Xem thành viên của 1 nhà TRƯỚC đây dùng Navigator.push
  // (MemberListScreen cũ) -> route mới đè LÊN TRÊN toàn app, che mất Sidebar/Header của
  // Dashboard. Nay chỉ hoán đổi state cục bộ: home != null -> build() trả thẳng
  // MemberListScreen làm nội dung, KHÔNG tạo route nào — HomeManagementScreen vẫn đang nằm
  // nguyên trong ô Content Area của Dashboard (_selectedIndex == 5), Sidebar không hề động.
  Map<String, dynamic>? _viewingMembersOfHome;

  /// [NHÚNG, KHÔNG PUSH] Cùng nguyên tắc — xem thiết bị của 1 nhà chỉ hoán đổi state cục
  /// bộ, KHÔNG Navigator.push (DeviceListScreen thay cho HomeDevicesScreen cũ đã push route).
  Map<String, dynamic>? _viewingDevicesOfHome;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final homeProvider = context.watch<HomeProvider>();
    final bool isLoading = homeProvider.isLoadingHomes && homeProvider.homes.isEmpty;
    final homes = homeProvider.homes;

    if (_viewingMembersOfHome != null) {
      return MemberListScreen(
        homeData: _viewingMembersOfHome!,
        onBack: () => setState(() => _viewingMembersOfHome = null),
      );
    }
    if (_viewingDevicesOfHome != null) {
      return DeviceListScreen(
        homeData: _viewingDevicesOfHome!,
        onBack: () => setState(() => _viewingDevicesOfHome = null),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent, 
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              // ĐÃ SỬA LỖI CÚ PHÁP Ở ĐÂY: Đặt Expanded vào trong children, bọc Text lại
              children: [
                Expanded(
                  child: Text(
                    widget.userRole == PermissionManager.superAdmin ? 'Toàn bộ hệ thống' : 'Danh sách Nhà của tôi', 
                    style: TextStyle(color: textMain, fontSize: 28, fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis, // Cắt chữ thành ... nếu quá dài
                  ),
                ),
                const SizedBox(width: 8),
                if (PermissionManager.canManageHouses(widget.userRole))
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tkGreen.withValues(alpha: 0.15),
                      foregroundColor: tkGreen,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.add_home_work_rounded, size: 20),
                    label: const Text('Thêm nhà mới', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    onPressed: () => _showAddOrEditHomeDialog(context, isDark, textMain, textSub),
                  ),
              ],
            ),
            const SizedBox(height: 32),

            if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF00A651))))
            else
              Expanded(child: _buildHomeList(homes, isDark, textMain, textSub)),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeList(List<Map<String, dynamic>> homes, bool isDark, Color textMain, Color textSub) {
    if (homes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.house_siding_rounded, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
            const SizedBox(height: 16),
            Text("Chưa có ngôi nhà nào trên hệ thống.", style: TextStyle(color: textSub, fontSize: 16)),
          ],
        )
      );
    }

    // [ÉP CHIỀU CAO] Bỏ SliverGridDelegateWithFixedCrossAxisCount + childAspectRatio (đoán tỉ
    // lệ, dễ dư khoảng trắng khi nội dung thẻ đã cố định/gọn) -> MaxCrossAxisExtent +
    // mainAxisExtent CỐ ĐỊNH bằng px thật: thẻ cao ĐÚNG NGẦN ẤY, không co giãn theo phần còn
    // trống của ô grid. 400 giữ nguyên ngưỡng responsive cũ (dưới ~600-800px tự về 1 cột).
    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: homes.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        // [SAFETY MARGIN] 168 -> 180: chừa dư ~12px "thở" cho hàng Role Badge + ID không còn
        // rớt dòng (đã ép Row 1 dòng + ellipsis phía dưới) nhưng vẫn khác biệt font/hệ điều
        // hành (line-height Android/iOS/Web lệch nhau vài px) có thể khiến "vừa khít" trước
        // đây bị tràn 1-3px — dư khoảng này tránh tái diễn "Bottom overflowed" mà không tạo
        // khoảng trắng rõ rệt (Column đã dùng SizedBox cố định, không Spacer co giãn).
        mainAxisExtent: 180,
      ),
      itemBuilder: (context, index) {
        final home = homes[index];
        return _buildHomeCard(home, index, isDark, textMain, textSub);
      },
    );
  }

  // =======================================================================
  // THẺ NHÀ VÀ PHÂN QUYỀN CỤC BỘ — [COMPACT] padding/font đã thu gọn so với bản trước
  // =======================================================================
  Widget _buildHomeCard(Map<String, dynamic> home, int index, bool isDark, Color textMain, Color textSub) {
    bool isPending = home['status'] == 'PENDING';

    final String myRole = (home['my_role'] ?? '').toString();
    final bool isSuperAdminGlobal = widget.userRole == PermissionManager.superAdmin;
    bool isLocalOwner = isSuperAdminGlobal || myRole == 'OWNER';
    bool isLocalOwnerOrAdmin = isLocalOwner || myRole == 'ADMIN';
    // [RỜI KHỎI NHÀ] Nhà chia sẻ (ADMIN/USER) hiện menu để có lối "Rời khỏi nhà" — trước
    // đây USER thường KHÔNG có popup nào cả nên không có cách tự rời nhà chung.
    final bool showCardMenu = isLocalOwnerOrAdmin || myRole == 'USER';

    String displayRole = myRole == 'OWNER' ? 'Chủ nhà' : (myRole == 'ADMIN' ? 'Quản trị' : 'Thành viên');
    if (isSuperAdminGlobal) displayRole = 'Super Admin';

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: isPending
        ? _buildPendingOverlay(home, index, textMain, textSub, isDark)
        : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded( // Bọc Expanded chống tràn cho cả cụm icon + chữ
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(Icons.maps_home_work_rounded, color: tkGreen, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded( // Bọc Expanded chống tràn cho tên nhà
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              home['home_name'],
                              style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis, // Tên nhà quá dài sẽ thành ...
                            ),
                            const SizedBox(height: 3),
                            // [FIX OVERFLOW] Wrap cũ tự rớt dòng khi home_id dài -> tăng chiều
                            // cao nội dung vượt mainAxisExtent cố định của Grid -> "Bottom
                            // overflowed". Đổi sang Row CHỈ 1 DÒNG DUY NHẤT: badge vai trò giữ
                            // nguyên kích thước, phần ID co giãn trong Flexible + tự cắt "..."
                            // thay vì rớt dòng khi không đủ chỗ.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(color: isLocalOwner ? Colors.orange.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                  child: Text(displayRole, style: TextStyle(color: isLocalOwner ? Colors.orange : Colors.blue, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'ID: ${home['home_id']}',
                                    style: TextStyle(color: textSub, fontSize: 10, fontFamily: 'monospace'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (showCardMenu)
                  PopupMenuButton<int>(
                    icon: Icon(Icons.more_vert, color: textSub, size: 20),
                    padding: EdgeInsets.zero,
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) {
                      if (value == 1) _showAddOrEditHomeDialog(context, isDark, textMain, textSub, homeToEdit: home);
                      if (value == 2) _deleteHome(home['home_id'], home['home_name']);
                      if (value == 3) _confirmLeaveHome(home);
                    },
                    itemBuilder: (context) => _buildHomeMenuItems(isLocalOwner, isLocalOwnerOrAdmin, textMain),
                  ),
              ],
            ),
            // [ÉP CHIỀU CAO] Spacer() cũ ép Column giãn hết phần trống của ô Grid (fixed
            // mainAxisExtent) -> khoảng trắng khổng lồ giữa header và hàng stat. Đổi hẳn
            // sang khoảng cách CỐ ĐỊNH — thẻ chỉ cao đúng bằng tổng nội dung thật.
            const SizedBox(height: 10),
            Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _buildActionableStat(
                    Icons.devices_other, '${home['devices_count']} TB', textMain, textSub,
                    () => setState(() => _viewingDevicesOfHome = home)
                  ),
                ),
                Container(width: 1, height: 16, color: isDark ? Colors.white10 : Colors.grey.shade300),

                Expanded(
                  child: Opacity(
                    opacity: isLocalOwnerOrAdmin ? 1.0 : 0.4,
                    child: _buildActionableStat(
                      Icons.group, '${home['members_count']} TV', textMain, textSub,
                      () {
                        if (isLocalOwnerOrAdmin) setState(() => _viewingMembersOfHome = home);
                      }
                    ),
                  ),
                ),
                Container(width: 1, height: 16, color: isDark ? Colors.white10 : Colors.grey.shade300),

                Expanded(
                  child: _buildActionableStat(
                    Icons.security_rounded, home['owner_email'].toString().split('@')[0], textMain, textSub,
                    () => _showOwnerInfoDialog(context, home, isDark, textMain, textSub)
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // [CHUYỂN NHÀ] Nút "Vào điều khiển" tường minh, mỏng nhẹ (OutlinedButton) — KHÔNG
            // gắn onTap lên toàn bộ thân thẻ vì thẻ đã có 3 vùng bấm riêng (Thiết bị/T.viên/
            // Chủ nhà) + menu 3 chấm; một GestureDetector bao trùm sẽ tranh chấp cử chỉ. Bấm ->
            // HomeProvider.setActiveHome() -> notifyListeners() -> DashboardScreen (đã
            // addListener) tự nhảy về tab Bảng điều khiển + refetch thiết bị nhà này.
            SizedBox(
              width: double.infinity,
              height: 32,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: tkGreen,
                  side: BorderSide(color: tkGreen.withValues(alpha: 0.5)),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.dashboard_customize_rounded, size: 15),
                label: const Text('Vào điều khiển', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _enterHomeDashboard(home),
              ),
            ),
          ],
        ),
    );
  }

  /// [RỜI KHỎI NHÀ] Danh sách item PopupMenu theo vai trò: Owner luôn có "Cập nhật thông
  /// tin" + "Xóa nhà này" (đỏ); Admin/User có "Rời khỏi nhà" (cam) thay cho xóa — Admin còn
  /// giữ "Cập nhật thông tin", User (chỉ xem) thì không.
  List<PopupMenuEntry<int>> _buildHomeMenuItems(bool isLocalOwner, bool isLocalOwnerOrAdmin, Color textMain) {
    final items = <PopupMenuEntry<int>>[];
    if (isLocalOwnerOrAdmin) {
      items.add(PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.edit_note_rounded, color: textMain, size: 20), const SizedBox(width: 12), Text('Cập nhật thông tin', style: TextStyle(color: textMain))])));
    }
    if (isLocalOwner) {
      items.add(const PopupMenuDivider());
      items.add(const PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), SizedBox(width: 12), Text('Xóa nhà này', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])));
    } else {
      if (items.isNotEmpty) items.add(const PopupMenuDivider());
      items.add(const PopupMenuItem(value: 3, child: Row(children: [Icon(Icons.logout_rounded, color: Colors.orange, size: 20), SizedBox(width: 12), Text('Rời khỏi nhà', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))])));
    }
    return items;
  }

  /// [RỜI KHỎI NHÀ] Confirm rồi gọi removeMember(homeId, CHÍNH email của mình) — KHÔNG BAO
  /// GIỜ gọi API xóa cả nhà. Backend (RemoveMemberHandler) đã cho phép self-leave bất kể
  /// role (chỉ chặn nếu target là owner_email — owner phải transfer-ownership trước).
  Future<void> _confirmLeaveHome(Map<String, dynamic> home) async {
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Rời khỏi nhà'),
            content: const Text('Bạn có chắc chắn muốn rời khỏi ngôi nhà này? Bạn sẽ mất toàn quyền truy cập và điều khiển.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Rời khỏi nhà', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm || !mounted) return;

    try {
      await context.read<HomeProvider>().removeMember(home['home_id'].toString(), widget.userEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã rời khỏi nhà "${home['home_name']}"'), backgroundColor: tkGreen),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  /// [CHUYỂN NHÀ] Đặt nhà này làm "active" toàn cục — Dashboard tự lắng nghe và điều hướng,
  /// xem HomeProvider.setActiveHome() + DashboardScreen._onActiveHomeChanged().
  void _enterHomeDashboard(Map<String, dynamic> home) {
    final homeId = home['home_id'].toString();
    context.read<HomeProvider>().setActiveHome(homeId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đang chuyển sang "${home['home_name']}"...'), backgroundColor: tkGreen),
    );
  }

  /// [KHIÊN CHỦ NHÀ] Popup thông tin Chủ nhà — Tên (suy ra từ email, không phải hồ sơ thật
  /// nên gắn nhãn rõ "suy ra từ email" để không hiểu nhầm là tên đã xác thực), Email đầy đủ,
  /// Vai trò.
  void _showOwnerInfoDialog(BuildContext context, Map<String, dynamic> home, bool isDark, Color textMain, Color textSub) {
    final String ownerEmail = (home['owner_email'] ?? '').toString();
    final String displayName = ownerEmail.contains('@') ? ownerEmail.split('@')[0] : ownerEmail;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 22, backgroundColor: Colors.orange.withValues(alpha: 0.2), child: const Icon(Icons.security_rounded, color: Colors.orange)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text('Thông tin Chủ nhà', style: TextStyle(color: textMain, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ownerInfoRow('Tên hiển thị (suy ra từ email)', displayName, textMain, textSub),
                const SizedBox(height: 12),
                _ownerInfoRow('Email đầy đủ', ownerEmail, textMain, textSub),
                const SizedBox(height: 12),
                _ownerInfoRow('Vai trò', 'Chủ nhà', textMain, textSub),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ownerInfoRow(String label, String value, Color textMain, Color textSub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textSub, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPendingOverlay(Map<String, dynamic> home, int index, Color textMain, Color textSub, bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.mark_email_unread_rounded, color: Colors.blueAccent, size: 36),
        const SizedBox(height: 12),
        Text('Lời mời tham gia hệ thống', style: TextStyle(color: textSub, fontSize: 12)),
        Text(home['home_name'], style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () async {
                _fetchHomesFromAPI();
              },
              child: const Text('Từ chối', style: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () async {
                _fetchHomesFromAPI(); 
              },
              child: const Text('Chấp nhận', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        )
      ],
    );
  }

  Widget _buildActionableStat(IconData icon, String text, Color textMain, Color textSub, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        hoverColor: tkGreen.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: textSub),
              const SizedBox(width: 4),
              Expanded(
                child: Text(text, style: TextStyle(color: textMain, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =======================================================================
  // 2. GỌI API THÊM HOẶC CẬP NHẬT NHÀ
  // =======================================================================
  void _showAddOrEditHomeDialog(BuildContext context, bool isDark, Color textMain, Color textSub, {Map<String, dynamic>? homeToEdit}) {
    final nameCtrl = TextEditingController(text: homeToEdit?['home_name'] ?? '');
    final addressCtrl = TextEditingController(text: homeToEdit?['address'] ?? '');
    final isEdit = homeToEdit != null;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: GlassCard(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isEdit ? 'Cập nhật thông tin Nhà' : 'Thêm Nhà mới', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    TextField(controller: nameCtrl, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Tên ngôi nhà', hintText: 'Để trống sẽ lấy ID làm tên', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 16),
                    TextField(controller: addressCtrl, style: TextStyle(color: textMain), decoration: InputDecoration(labelText: 'Địa chỉ cụ thể', labelStyle: TextStyle(color: textSub), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: () async {
                            if (nameCtrl.text.isEmpty && addressCtrl.text.isEmpty) return;
                            Navigator.pop(context);
                            
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Đang cập nhật...' : 'Đang tạo nhà mới...'), backgroundColor: tkGreen));
                            
                            try {
                              final token = await AuthService().getToken();
                              final uri = isEdit ? Uri.parse('$baseUrl/homes/${homeToEdit['home_id']}') : Uri.parse('$baseUrl/homes');
                              final method = isEdit ? http.put : http.post;
                              
                              final response = await method(
                                uri,
                                headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
                                body: jsonEncode({
                                  "name": nameCtrl.text,
                                  "address": addressCtrl.text,
                                })
                              );

                              if (!context.mounted) return; // dialog đã đóng trong lúc chờ API
                              if (response.statusCode == 200 || response.statusCode == 201) {
                                _fetchHomesFromAPI();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: ${response.body}'), backgroundColor: Colors.redAccent));
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent));
                            }
                          },
                          child: Text(isEdit ? 'Lưu thay đổi' : 'Tạo mới', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      }
    );
  }

  // =======================================================================
  // 3. GỌI API XÓA NHÀ
  // =======================================================================
  void _deleteHome(String homeId, String homeName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa hệ thống "$homeName"? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text('Xóa', style: TextStyle(color: Colors.white))
          ),
        ],
      )
    ) ?? false;

    if (!confirm || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang xóa hệ thống: $homeName'), backgroundColor: Colors.orange));

    try {
      final token = await AuthService().getToken();
      final response = await http.delete(
        Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}'),
        headers: {'Authorization': 'Bearer $token'}
      );

      if (!mounted) return; // màn hình đã đóng trong lúc chờ API
      if (response.statusCode == 200) {
        _fetchHomesFromAPI();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa nhà: ${response.body}'), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent));
    }
  }
}