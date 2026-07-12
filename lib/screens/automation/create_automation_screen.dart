import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/automation_provider.dart';

/// CreateAutomationScreen — Tạo/Sửa Ngữ cảnh theo chuẩn IFTTT (NẾU... THÌ...).
class CreateAutomationScreen extends StatefulWidget {
  final SceneType initialType;
  const CreateAutomationScreen({super.key, this.initialType = SceneType.automation});

  @override
  State<CreateAutomationScreen> createState() => _CreateAutomationScreenState();
}

class _CreateAutomationScreenState extends State<CreateAutomationScreen> {
  static const Color tkGreen = Color(0xFF00A651);

  final TextEditingController _nameCtrl = TextEditingController();
  int _iconCodePoint = Icons.auto_awesome.codePoint;
  late SceneType _type;
  final List<SceneStep> _conditions = [];
  final List<SceneStep> _actions = [];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: const Text('Tạo ngữ cảnh'),
        backgroundColor: cardColor,
        foregroundColor: textMain,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Lưu', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640), // responsive: không kéo dài trên PC
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- Tên + Icon + Loại ---
                _sectionCard(cardColor, [
                  Row(children: [
                    InkWell(
                      onTap: _pickIcon,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                        child: Icon(IconData(_iconCodePoint, fontFamily: 'MaterialIcons'), color: tkGreen, size: 28),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 16),
                        decoration: InputDecoration(hintText: 'Tên ngữ cảnh (vd: Về nhà)', hintStyle: TextStyle(color: textSub), border: InputBorder.none),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  // Chọn loại: chạm-để-chạy vs tự động
                  SegmentedButton<SceneType>(
                    segments: const [
                      ButtonSegment(value: SceneType.tapToRun, icon: Icon(Icons.touch_app), label: Text('Chạm để chạy')),
                      ButtonSegment(value: SceneType.automation, icon: Icon(Icons.bolt), label: Text('Tự động')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ]),
                const SizedBox(height: 16),

                // --- NẾU... (điều kiện) — ẩn với "Chạm để chạy" (kích hoạt thủ công) ---
                if (_type == SceneType.automation) ...[
                  _ifThenHeader('NẾU...', Icons.help_outline, textMain),
                  const SizedBox(height: 8),
                  ..._conditions.asMap().entries.map((e) => _stepTile(cardColor, textMain, textSub, e.value, () => setState(() => _conditions.removeAt(e.key)))),
                  _addButton('Thêm điều kiện', _pickCondition),
                  const SizedBox(height: 16),
                ],

                // --- THÌ... (hành động) ---
                _ifThenHeader('THÌ...', Icons.play_circle_outline, textMain),
                const SizedBox(height: 8),
                ..._actions.asMap().entries.map((e) => _stepTile(cardColor, textMain, textSub, e.value, () => setState(() => _actions.removeAt(e.key)))),
                _addButton('Thêm hành động', _pickAction),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Widgets phụ ----------
  Widget _sectionCard(Color cardColor, List<Widget> children) => Container(
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _ifThenHeader(String title, IconData icon, Color textMain) => Row(children: [
        Icon(icon, color: tkGreen, size: 20),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: textMain, fontSize: 16, height: 1.2, fontWeight: FontWeight.w900, letterSpacing: 1)),
      ]);

  Widget _stepTile(Color cardColor, Color textMain, Color textSub, SceneStep step, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.15), child: Icon(step.icon, color: tkGreen, size: 20)),
          title: Text(step.label, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
          trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent), onPressed: onRemove),
        ),
      );

  Widget _addButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: tkGreen, side: const BorderSide(color: tkGreen), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          icon: const Icon(Icons.add),
          label: Text(label),
          onPressed: onTap,
        ),
      );

  // ---------- Bottom sheets chọn điều kiện / hành động ----------
  void _pickCondition() {
    _showPicker('Chọn điều kiện (NẾU)', const [
      SceneStep(Icons.access_time, 'Hẹn giờ (Thời gian)'),
      SceneStep(Icons.toggle_on, 'Thiết bị thay đổi trạng thái'),
      SceneStep(Icons.cloud, 'Thời tiết thay đổi'),
    ], (step) => setState(() => _conditions.add(step)));
  }

  void _pickAction() {
    _showPicker('Chọn hành động (THÌ)', const [
      SceneStep(Icons.settings_remote, 'Điều khiển thiết bị'),
      SceneStep(Icons.notifications_active_outlined, 'Gửi thông báo'),
      SceneStep(Icons.timelapse, 'Chờ (Delay)'),
    ], (step) => setState(() => _actions.add(step)));
  }

  void _showPicker(String title, List<SceneStep> options, ValueChanged<SceneStep> onPick) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(title, style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold))),
            ...options.map((o) => ListTile(
                  leading: Icon(o.icon, color: tkGreen),
                  title: Text(o.label, style: TextStyle(color: textMain, fontWeight: FontWeight.w600)),
                  onTap: () { onPick(o); Navigator.pop(ctx); },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _pickIcon() {
    const icons = [Icons.auto_awesome, Icons.movie_creation_outlined, Icons.nightlight_round, Icons.wb_sunny_outlined, Icons.home_rounded, Icons.umbrella, Icons.local_cafe_outlined, Icons.directions_run];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 14, runSpacing: 14,
            children: icons.map((ic) => InkWell(
                  onTap: () { setState(() => _iconCodePoint = ic.codePoint); Navigator.pop(ctx); },
                  child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(ic, color: tkGreen, size: 26)),
                )).toList(),
          ),
        ),
      ),
    );
  }

  void _save() {
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy thêm ít nhất 1 hành động (THÌ...)'), backgroundColor: Colors.redAccent));
      return;
    }
    Provider.of<AutomationProvider>(context, listen: false).addScene(
      name: _nameCtrl.text,
      iconCodePoint: _iconCodePoint,
      type: _type,
      conditions: List.of(_conditions),
      actions: List.of(_actions),
    );
    Navigator.pop(context);
  }
}
