import 'package:flutter/material.dart';
import '../../services/permission_manager.dart';
import '../../ui/dashboard_screen.dart'; // Để dùng GlassContainer

class HomeManagementScreen extends StatefulWidget {
  final String userRole;
  const HomeManagementScreen({super.key, required this.userRole});

  @override
  State<HomeManagementScreen> createState() => _HomeManagementScreenState();
}

class _HomeManagementScreenState extends State<HomeManagementScreen> {
  final Color tkGreen = const Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quản lý nhà', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              if (PermissionManager.canManageHouses(widget.userRole))
                ElevatedButton.icon(
                  onPressed: () => _showAddHomeDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm nhà mới'),
                  style: ElevatedButton.styleFrom(backgroundColor: tkGreen),
                )
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: _buildHomeList()),
        ],
      ),
    );
  }

  Widget _buildHomeList() {
    // Demo danh sách nhà - Bác sẽ thay bằng API gọi từ server
    return ListView.builder(
      itemCount: 2, 
      itemBuilder: (context, index) {
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: ListTile(
            title: Text("Ngôi nhà của tôi ${index + 1}"),
            subtitle: Text("ID: ECE334468B64"),
            trailing: PermissionManager.canManageMembers(widget.userRole) 
                ? IconButton(icon: Icon(Icons.people), onPressed: () => _showMemberManagement())
                : null,
          ),
        );
      },
    );
  }

  void _showAddHomeDialog() { /* Logic thêm nhà */ }
  void _showMemberManagement() { /* Logic thêm/xóa Admin, User */ }
}