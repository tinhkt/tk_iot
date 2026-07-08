import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/permission_manager.dart';
import '../../services/auth_service.dart';
import '../../widgets/glass_container.dart';
import 'home_devices_screen.dart';
import 'home_members_screen.dart';

// ============================================================================
// MÀN HÌNH QUẢN LÝ NHÀ CHÍNH
// ============================================================================
class HomeManagementScreen extends StatefulWidget {
  final String userRole; // Quyền TOÀN CỤC (SUPER_USER, USER...)
  
  const HomeManagementScreen({super.key, required this.userRole});

  @override
  State<HomeManagementScreen> createState() => _HomeManagementScreenState();
}

class _HomeManagementScreenState extends State<HomeManagementScreen> {
  final Color tkGreen = const Color(0xFF00A651);
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _realHomes = [];

  final String baseUrl = "https://api.iot-smart.vn/api"; 

  @override
  void initState() {
    super.initState();
    _fetchHomesFromAPI();
  }

  // =======================================================================
  // 1. GỌI API LẤY DANH SÁCH NHÀ TỪ SERVER GOLANG (DỮ LIỆU THẬT)
  // =======================================================================
  Future<void> _fetchHomesFromAPI() async {
    setState(() => _isLoading = true);
    
    try {
      final token = await AuthService().getToken();
      
      final response = await http.get(
        Uri.parse('$baseUrl/homes'), 
        headers: {
          'Content-Type': 'application/json', 
          'Authorization': 'Bearer $token'
        },
      );
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> data = [];
        
        if (decoded != null) {
          if (decoded is List) {
            data = decoded; 
          } else if (decoded is Map && decoded.containsKey('data') && decoded['data'] != null) {
            data = decoded['data']; 
          }
        }

        List<Map<String, dynamic>> realData = data.map((item) {
          String id = item['id'] ?? item['home_id'] ?? 'UNKNOWN_ID';
          String rawName = item['name'] ?? item['home_name'] ?? '';
          
          return {
            "home_id": id,
            "home_name": rawName.trim().isEmpty ? 'Nhà $id' : rawName,
            "address": item['address'] ?? 'Chưa cập nhật địa chỉ',
            "owner_email": item['owner_email'] ?? item['owner'] ?? 'Chưa xác định',
            "devices_count": item['devices_count'] ?? 0,
            "members_count": item['members_count'] ?? 1,
            "my_role": item['my_role'] ?? 'OWNER', 
            "status": item['status'] ?? 'ACCEPTED',
          };
        }).toList();

        if (mounted) {
          setState(() {
            _realHomes = realData;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải dữ liệu: Mã ${response.statusCode}'), backgroundColor: Colors.redAccent));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối tới Server: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

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

            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF00A651))))
            else
              Expanded(child: _buildHomeList(isDark, textMain, textSub)),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeList(bool isDark, Color textMain, Color textSub) {
    if (_realHomes.isEmpty) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth < 600 ? 1 : (constraints.maxWidth / 400).floor();
        return GridView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: _realHomes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 2.1, 
          ),
          itemBuilder: (context, index) {
            final home = _realHomes[index];
            return _buildHomeCard(home, index, isDark, textMain, textSub);
          },
        );
      }
    );
  }

  // =======================================================================
  // THẺ NHÀ VÀ PHÂN QUYỀN CỤC BỘ
  // =======================================================================
  Widget _buildHomeCard(Map<String, dynamic> home, int index, bool isDark, Color textMain, Color textSub) {
    bool isPending = home['status'] == 'PENDING';
    
    bool isLocalOwnerOrAdmin = widget.userRole == PermissionManager.superAdmin || home['my_role'] == 'OWNER' || home['my_role'] == 'ADMIN';
    bool isLocalOwner = widget.userRole == PermissionManager.superAdmin || home['my_role'] == 'OWNER';

    String displayRole = home['my_role'] == 'OWNER' ? 'Chủ nhà' : (home['my_role'] == 'ADMIN' ? 'Quản trị' : 'Thành viên');
    if (widget.userRole == PermissionManager.superAdmin) displayRole = 'Super Admin';

    return GlassCard(
      padding: const EdgeInsets.all(20),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: Icon(Icons.maps_home_work_rounded, color: tkGreen, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded( // Bọc Expanded chống tràn cho tên nhà
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              home['home_name'], 
                              style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold),
                              maxLines: 1, 
                              overflow: TextOverflow.ellipsis, // Tên nhà quá dài sẽ thành ...
                            ),
                            const SizedBox(height: 4),
                            Wrap( // Dùng Wrap thay vì Row để nếu dài quá nó tự rớt dòng
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: isLocalOwner ? Colors.orange.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                  child: Text(displayRole, style: TextStyle(color: isLocalOwner ? Colors.orange : Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                                Text('ID: ${home['home_id']}', style: TextStyle(color: textSub, fontSize: 11, fontFamily: 'monospace')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (isLocalOwnerOrAdmin)
                  PopupMenuButton<int>(
                    icon: Icon(Icons.more_vert, color: textSub),
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (value) {
                      if (value == 1) _showAddOrEditHomeDialog(context, isDark, textMain, textSub, homeToEdit: home);
                      if (value == 2) _deleteHome(home['home_id'], home['home_name']);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 1, child: Row(children: [Icon(Icons.edit_note_rounded, color: textMain, size: 20), const SizedBox(width: 12), Text('Cập nhật thông tin', style: TextStyle(color: textMain))])),
                      if (isLocalOwner) 
                        const PopupMenuDivider(),
                      if (isLocalOwner)
                        const PopupMenuItem(value: 2, child: Row(children: [Icon(Icons.delete_outline, color: Colors.redAccent, size: 20), SizedBox(width: 12), Text('Xóa nhà này', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])),
                    ],
                  ),
              ],
            ),
            const Spacer(),
            Divider(color: isDark ? Colors.white10 : Colors.grey.shade200, height: 1),
            const SizedBox(height: 8),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _buildActionableStat(
                    Icons.devices_other, '${home['devices_count']} Thiết bị', textMain, textSub, 
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => HomeDevicesScreen(homeData: home)))
                  ),
                ),
                Container(width: 1, height: 20, color: isDark ? Colors.white10 : Colors.grey.shade300),
                
                Expanded(
                  child: Opacity(
                    opacity: isLocalOwnerOrAdmin ? 1.0 : 0.4,
                    child: _buildActionableStat(
                      Icons.group, '${home['members_count']} T.viên', textMain, textSub, 
                      () {
                        if (isLocalOwnerOrAdmin) Navigator.push(context, MaterialPageRoute(builder: (_) => HomeMembersScreen(homeData: home)));
                      }
                    ),
                  ),
                ),
                Container(width: 1, height: 20, color: isDark ? Colors.white10 : Colors.grey.shade300),
                
                Expanded(
                  child: _buildActionableStat(
                    Icons.security_rounded, home['owner_email'].toString().split('@')[0], textMain, textSub, 
                    () {} 
                  ),
                ),
              ],
            )
          ],
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: textSub),
              const SizedBox(width: 4),
              Expanded(
                child: Text(text, style: TextStyle(color: textMain, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
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

                              if (response.statusCode == 200 || response.statusCode == 201) {
                                _fetchHomesFromAPI();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: ${response.body}'), backgroundColor: Colors.redAccent));
                              }
                            } catch (e) {
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

    if (!confirm) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang xóa hệ thống: $homeName'), backgroundColor: Colors.orange));
    
    try {
      final token = await AuthService().getToken();
      final response = await http.delete(
        Uri.parse('$baseUrl/homes/${Uri.encodeComponent(homeId)}'),
        headers: {'Authorization': 'Bearer $token'}
      );

      if (response.statusCode == 200) {
        _fetchHomesFromAPI();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa nhà: ${response.body}'), backgroundColor: Colors.redAccent));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent));
    }
  }
}