import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/automation_provider.dart';
import 'create_automation_screen.dart';

/// AutomationScreen — Ngữ cảnh: 2 tab 'Chạm để chạy' + 'Tự động'. [embedded]=true khi nhúng
/// làm tab body của Dashboard (bỏ AppBar để tránh double). FAB thêm ngữ cảnh mới.
class AutomationScreen extends StatelessWidget {
  final bool embedded;
  const AutomationScreen({super.key, this.embedded = false});

  static const Color tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
        appBar: embedded
            ? null
            : AppBar(title: const Text('Ngữ cảnh'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: tkGreen,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Thêm ngữ cảnh'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAutomationScreen())),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (embedded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome, color: tkGreen, size: 26),
                    const SizedBox(width: 12),
                    Text('Ngữ cảnh', style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]),
                ),
              TabBar(
                indicatorColor: tkGreen,
                labelColor: tkGreen,
                unselectedLabelColor: textSub,
                tabs: const [
                  Tab(icon: Icon(Icons.touch_app), text: 'Chạm để chạy'),
                  Tab(icon: Icon(Icons.bolt), text: 'Tự động'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _SceneList(type: SceneType.tapToRun),
                    _SceneList(type: SceneType.automation),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Danh sách ngữ cảnh theo loại — tab tapToRun có nút "Chạy", tab automation có Switch bật/tắt.
class _SceneList extends StatelessWidget {
  final SceneType type;
  const _SceneList({required this.type});

  static const Color tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Consumer<AutomationProvider>(
      builder: (context, provider, _) {
        final scenes = type == SceneType.tapToRun ? provider.tapToRun : provider.automations;
        if (scenes.isEmpty) {
          return Center(child: Text('Chưa có ngữ cảnh nào.\nBấm "Thêm ngữ cảnh" để tạo.', textAlign: TextAlign.center, style: TextStyle(color: textSub)));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: scenes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final s = scenes[index];
            // Tóm tắt điều kiện/hành động cho subtitle
            final String summary = type == SceneType.automation && s.conditions.isNotEmpty
                ? '${s.conditions.first.label} → ${s.actions.length} hành động'
                : '${s.actions.length} hành động';
            return Container(
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(radius: 24, backgroundColor: tkGreen.withValues(alpha: 0.15), child: Icon(s.icon, color: tkGreen, size: 26)),
                title: Text(s.name, style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(summary, style: TextStyle(color: textSub, fontSize: 12))),
                trailing: type == SceneType.tapToRun
                    // Chạm để chạy -> nút "Chạy"
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Chạy'),
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang chạy ngữ cảnh "${s.name}"'), backgroundColor: tkGreen)),
                      )
                    // Tự động -> Switch bật/tắt
                    : Switch(value: s.enabled, activeThumbColor: tkGreen, onChanged: (v) => provider.toggleEnabled(s.id, v)),
              ),
            );
          },
        );
      },
    );
  }
}
