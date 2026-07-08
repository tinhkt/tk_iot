import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/glass_container.dart';

// ============================================================================
// GIAO DIỆN CHÍNH: QUẢN LÝ PHÂN QUYỀN TRONG VẬN HÀNH THỰC TẾ
// ============================================================================
class RoleManagementView extends StatefulWidget {
  const RoleManagementView({super.key});

  @override
  State<RoleManagementView> createState() => _RoleManagementViewState();
}

class _RoleManagementViewState extends State<RoleManagementView> {
  final AuthService _authService = AuthService();
  List<dynamic> _allUsers = [];
  List<dynamic> _filteredUsers = [];
  bool _isLoading = true;
  String? _errorMessage;

  // --- BỘ ĐIỀU KHIỂN TÌM KIẾM & LỌC HÀNG LOẠT ---
  final TextEditingController _searchController = TextEditingController();
  String _selectedRoleFilter = 'ALL';
  final List<String> _selectedEmails = []; // Lưu danh sách các user được chọn hàng loạt

  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    setState(() { _isLoading = true; _errorMessage = null; _selectedEmails.clear(); });
    final data = await _authService.getHomeUsers();
    
    if (data != null) {
      if (mounted) {
        setState(() { 
          _allUsers = data; 
          _filteredUsers = data;
          _isLoading = false; 
        });
        _applyFilterAndSearch();
      }
    } else {
      if (mounted) {
        setState(() { 
          _isLoading = false; 
          _errorMessage = "Bạn không có quyền truy cập, hoặc máy chủ đang gặp sự cố."; 
        });
      }
    }
  }

  // --- LOGIC XỬ LÝ LỌC & TÌM KIẾM REAL-TIME TỐI ƯU HIỆU NĂNG ---
  void _applyFilterAndSearch() {
    String query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredUsers = _allUsers.where((user) {
        bool matchesSearch = user['email'].toString().toLowerCase().contains(query);
        bool matchesRole = _selectedRoleFilter == 'ALL' || user['role'] == _selectedRoleFilter;
        return matchesSearch && matchesRole;
      }).toList();
    });
  }

  // --- THỐNG KÊ NHANH CHỈ SỐ ---
  Map<String, int> _getMetrics() {
    int total = _allUsers.length;
    int owners = _allUsers.where((u) => u['role'] == 'HOME_OWNER').length;
    int admins = _allUsers.where((u) => u['role'] == 'ADMIN').length;
    int restricted = _allUsers.where((u) => u['role'] == 'USER' || u['role'] == '').length;
    return {'TOTAL': total, 'OWNER': owners, 'ADMIN': admins, 'USER': restricted};
  }

  // --- HÀM THAY ĐỔI QUYỀN ĐƠN LẺ ---
  void _showEditDialog(Map<String, dynamic> user) {
    String selectedRole = user['role'] == 'SUPER_USER' ? 'ADMIN' : user['role']; 
    if (!['ADMIN', 'HOME_OWNER', 'USER'].contains(selectedRole)) selectedRole = 'USER';

    final endpointCtrl = TextEditingController();
    if (user['accessible_endpoints'] != null) {
      endpointCtrl.text = (user['accessible_endpoints'] as List).join(', ');
    }

    bool isUpdating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
        final Color textSub = isDark ? Colors.white70 : Colors.black54;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cấp quyền thành viên', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 12),
                    Text(user['email'], style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 20),
                    Text('Cấp độ tương tác:', style: TextStyle(fontSize: 13, color: textSub, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade50,
                        border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200), 
                        borderRadius: BorderRadius.circular(12)
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedRole,
                          dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                          style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.w600),
                          items: const [
                            DropdownMenuItem(value: 'HOME_OWNER', child: Text('CHỦ NHÀ (Toàn quyền hệ thống)')),
                            DropdownMenuItem(value: 'ADMIN', child: Text('ADMIN (Quản trị viên thiết bị)')),
                            DropdownMenuItem(value: 'USER', child: Text('USER (Giới hạn thiết bị)')),
                          ],
                          onChanged: (val) => setDialogState(() => selectedRole = val!),
                        ),
                      ),
                    ),
                    if (selectedRole == 'USER') ...[
                      const SizedBox(height: 20),
                      TextField(
                        controller: endpointCtrl,
                        style: TextStyle(color: textMain),
                        decoration: InputDecoration(
                          labelText: 'Thiết bị được phép điều khiển',
                          labelStyle: TextStyle(color: textSub, fontSize: 13),
                          hintText: 'Ví dụ: S_1706, S_6456',
                          filled: true,
                          fillColor: isDark ? Colors.black26 : Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      )
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: isUpdating ? null : () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          onPressed: isUpdating ? null : () async {
                            setDialogState(() => isUpdating = true);
                            List<String> endpoints = [];
                            if (selectedRole == 'USER' && endpointCtrl.text.isNotEmpty) {
                              endpoints = endpointCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            }
                            String? error = await _authService.updateUserConfig(user['email'], selectedRole, endpoints);
                            if (error == null) {
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              _fetchUsers();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật thành công!'), backgroundColor: Color(0xFF00A651)));
                            } else {
                              setDialogState(() => isUpdating = false);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
                            }
                          },
                          child: isUpdating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Lưu thay đổi', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  // --- HÀM THU HỒI TRUY CẬP (XÓA 1 HOẶC NHIỀU) ---
  void _confirmDeleteBatch(List<String> emails) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thu hồi quyền truy cập', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn loại bỏ ${emails.length} tài khoản được chọn khỏi hệ thống ngôi nhà này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa truy cập', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);
      for (String email in emails) {
        await _authService.deleteUser(email);
      }
      _fetchUsers();
    }
  }

  // ==========================================================================
  // PHẦN DỰNG GIAO DIỆN CHUYÊN NGHIỆP TRỰC QUAN
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    if (_isLoading) return Center(child: CircularProgressIndicator(color: tkGreen));

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security_rounded, size: 80, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: textMain, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: tkGreen), onPressed: _fetchUsers, child: const Text('Thử lại')),
          ],
        ),
      );
    }

    final metrics = _getMetrics();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- TIÊU ĐỀ CHÍNH ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hệ thống bảo mật vận hành', style: TextStyle(color: textSub, fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('Quản lý Phân quyền', style: TextStyle(color: textMain, fontSize: isMobile ? 22 : 26, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  IconButton(icon: Icon(Icons.sync_rounded, color: tkGreen), onPressed: _fetchUsers)
                ],
              ),
              const SizedBox(height: 20),

              // --- THÀNH PHẦN 1: BẢNG CHỈ SỐ TỐM TẮT (ANALYTICS BENTO) ---
              if (!isMobile)
                Row(
                  children: [
                    _buildMetricCard('TỔNG THÀNH VIÊN', metrics['TOTAL'].toString(), Colors.blue, isDark),
                    const SizedBox(width: 16),
                    _buildMetricCard('CHỦ NHÀ (OWNER)', metrics['BODY'] == null ? metrics['OWNER'].toString() : '0', Colors.orange, isDark),
                    const SizedBox(width: 16),
                    _buildMetricCard('QUẢN TRỊ VIÊN (ADMIN)', metrics['ADMIN'].toString(), Colors.teal, isDark),
                    const SizedBox(width: 16),
                    _buildMetricCard('GIỚI HẠN (USER)', metrics['USER'].toString(), Colors.purple, isDark),
                  ],
                ),
              const SizedBox(height: 20),

              // --- THÀNH PHẦN 2: THANH TÌM KIẾM VÀ LỌC DỮ LIỆU TẬP TRUNG ---
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: isMobile 
                // TRÊN MOBILE: Xếp dọc từ trên xuống dưới
                ? Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => _applyFilterAndSearch(),
                        style: TextStyle(color: textMain, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Tìm kiếm tài khoản email...',
                          hintStyle: TextStyle(color: textSub.withValues(alpha: 0.5)),
                          prefixIcon: Icon(Icons.search_rounded, color: textSub, size: 20),
                          border: InputBorder.none,
                        ),
                      ),
                      Divider(height: 16, color: isDark ? Colors.white10 : Colors.black12),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true, // Ép Dropdown tự dãn full màn hình
                          value: _selectedRoleFilter,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 13),
                          icon: Icon(Icons.filter_list_rounded, color: tkGreen, size: 20),
                          items: const [
                            DropdownMenuItem(value: 'ALL', child: Text('Tất cả cấp quyền')),
                            DropdownMenuItem(value: 'HOME_OWNER', child: Text('Cấp: Chủ nhà')),
                            DropdownMenuItem(value: 'ADMIN', child: Text('Cấp: Admin')),
                            DropdownMenuItem(value: 'USER', child: Text('Cấp: Thành viên')),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedRoleFilter = val!);
                            _applyFilterAndSearch();
                          },
                        ),
                      ),
                    ],
                  )
                // TRÊN DESKTOP: Xếp ngang như cũ
                : Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => _applyFilterAndSearch(),
                          style: TextStyle(color: textMain, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Tìm kiếm nhanh theo tài khoản email...',
                            hintStyle: TextStyle(color: textSub.withValues(alpha: 0.5)),
                            prefixIcon: Icon(Icons.search_rounded, color: textSub, size: 20),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      Container(width: 1, height: 24, color: isDark ? Colors.white10 : Colors.black12, margin: const EdgeInsets.symmetric(horizontal: 16)),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedRoleFilter,
                            dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                            style: TextStyle(color: textMain, fontWeight: FontWeight.w600, fontSize: 13),
                            icon: Icon(Icons.filter_list_rounded, color: tkGreen, size: 20),
                            items: const [
                              DropdownMenuItem(value: 'ALL', child: Text('Tất cả cấp quyền')),
                              DropdownMenuItem(value: 'HOME_OWNER', child: Text('Cấp: Chủ nhà')),
                              DropdownMenuItem(value: 'ADMIN', child: Text('Cấp: Admin')),
                              DropdownMenuItem(value: 'USER', child: Text('Cấp: Thành viên')),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedRoleFilter = val!);
                              _applyFilterAndSearch();
                            },
                          ),
                        ),
                      )
                    ],
                  ),
              ),
              
              // --- THANH ĐIỀU KHIỂN SỬ LÝ HÀNG LOẠT ---
              if (_selectedEmails.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Đang chọn xử lý hàng loạt: ${_selectedEmails.length} tài khoản', style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          onPressed: () => _confirmDeleteBatch(_selectedEmails),
                          icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 18),
                          label: const Text('THU HỒI TẤT CẢ QUYỀN', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              // --- THÀNH PHẦN 3: KHO KHÔNG GIAN CUỘN ĐỘC LẬP DANH SÁCH USER VIRTUAL ---
              Expanded(
                child: _filteredUsers.isEmpty
                    ? Center(child: Text('Không tìm thấy tài khoản người dùng nào khớp điều kiện.', style: TextStyle(color: textSub)))
                    : (isMobile 
                        ? ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            itemCount: _filteredUsers.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, idx) => _buildRowUser(_filteredUsers[idx], isDark, textMain, textSub),
                          )
                        : GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              mainAxisExtent: 104,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _filteredUsers.length,
                            itemBuilder: (context, idx) => _buildRowUser(_filteredUsers[idx], isDark, textMain, textSub),
                          )),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- HÀM VẼ TẤT CẢ CÁC LOẠI USER THẺ CHUẨN KHOA HỌC ---
  Widget _buildRowUser(Map<String, dynamic> user, bool isDark, Color textMain, Color textSub) {
    final bool isHardcoded = user['is_hardcoded'] == true;
    final bool isSelected = _selectedEmails.contains(user['email']);

    String friendlyRole = 'Thành viên';
    IconData roleIcon = Icons.person_rounded;
    Color roleColor = Colors.blue;

    switch (user['role']) {
      case 'SUPER_USER': friendlyRole = 'Phát triển'; roleIcon = Icons.developer_board_rounded; roleColor = Colors.purple; break;
      case 'HOME_OWNER': friendlyRole = 'Chủ nhà'; roleIcon = Icons.home_work_rounded; roleColor = Colors.orange; break;
      case 'ADMIN': friendlyRole = 'Quản trị viên'; roleIcon = Icons.admin_panel_settings_rounded; roleColor = Colors.teal; break;
      default: friendlyRole = 'Giới hạn'; roleIcon = Icons.person_rounded; roleColor = Colors.blue; break;
    }

    return GestureDetector(
      onLongPress: isHardcoded ? null : () {
        setState(() {
          if (isSelected) {
            _selectedEmails.remove(user['email']);
          } else {
            _selectedEmails.add(user['email']);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected 
              ? Colors.redAccent.withValues(alpha: 0.05) 
              : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
                ? Colors.redAccent.withValues(alpha: 0.5) 
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.2)),
            width: isSelected ? 2.0 : 1.0
          ),
        ),
        child: Row(
          children: [
            // Checkbox chọn hàng loạt
            if (_selectedEmails.isNotEmpty && !isHardcoded)
              Checkbox(
                activeColor: Colors.redAccent,
                value: isSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) { _selectedEmails.add(user['email']); } 
                    else { _selectedEmails.remove(user['email']); }
                  });
                },
              ),
            CircleAvatar(radius: 20, backgroundColor: roleColor.withValues(alpha: 0.12), child: Icon(roleIcon, color: roleColor, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(user['email'], style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(friendlyRole, style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                      if (user['role'] == 'USER' && user['accessible_endpoints'] != null) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Khu vực: ${(user['accessible_endpoints'] as List).join(', ')}', 
                            style: TextStyle(color: textSub, fontSize: 11),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        )
                      ]
                    ],
                  )
                ],
              ),
            ),
            if (isHardcoded)
              Icon(Icons.lock_clock_outlined, color: textSub.withValues(alpha: 0.3), size: 18)
            else
              PopupMenuButton<int>(
                icon: Icon(Icons.more_vert_rounded, color: textSub, size: 20),
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 0) _showEditDialog(user);
                  if (val == 1) _confirmDeleteBatch([user['email']]);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 0, child: Row(children: [Icon(Icons.shield_outlined, color: textMain, size: 18), const SizedBox(width: 10), Text('Sửa cấp quyền', style: TextStyle(color: textMain, fontSize: 13))])),
                  const PopupMenuDivider(),
                  PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18), const SizedBox(width: 10), Text('Thu hồi quyền', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13))])),
                ],
              )
          ],
        ),
      ),
    );
  }

  // --- KHỐI NHỎ CHỈ SỐ METRIC CARD ---
  Widget _buildMetricCard(String title, String value, Color accent, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: accent, fontSize: 24, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}