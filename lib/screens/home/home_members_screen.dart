import 'package:flutter/material.dart';

class HomeMembersScreen extends StatefulWidget {
  final Map<String, dynamic> homeData;
  const HomeMembersScreen({super.key, required this.homeData});

  @override
  State<HomeMembersScreen> createState() => _HomeMembersScreenState();
}

class _HomeMembersScreenState extends State<HomeMembersScreen> {
  final Color tkGreen = const Color(0xFF00A651);
  List<Map<String, String>> _members = []; 

  @override
  void initState() {
    super.initState();
    // Giả lập Fetch Data từ API
    _members = [
      {"email": widget.homeData['owner_email'] ?? 'admin@tuankiet.vn', "role": "HOME_OWNER"},
      {"email": "nguoithan@gmail.com", "role": "USER"},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF4F7FC),
      appBar: AppBar(
        title: Text('Thành viên: ${widget.homeData['home_name']}', style: const TextStyle(fontSize: 16)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.person_add_alt_1_rounded, color: tkGreen),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Tính năng thêm thành viên đang chờ API'), backgroundColor: tkGreen));
            },
          )
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _members.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final mem = _members[index];
          return ListTile(
            leading: CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.2), child: Icon(Icons.person, color: tkGreen)),
            title: Text(mem['email']!),
            subtitle: Text('Vai trò: ${mem['role']}'),
            trailing: mem['role'] != 'HOME_OWNER' 
              ? PopupMenuButton<String>(
                  onSelected: (val) { /* Đổi quyền hoặc xóa user */ },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'admin', child: Text('Cấp quyền Admin')),
                    const PopupMenuItem(value: 'remove', child: Text('Xóa khỏi nhà', style: TextStyle(color: Colors.red))),
                  ],
                )
              : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}