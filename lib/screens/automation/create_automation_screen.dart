import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/automation_provider.dart';
import '../../widgets/glass_popup.dart';
import '../../widgets/scene_step_pickers.dart';

/// CreateAutomationScreen — Tạo/Sửa Ngữ cảnh theo chuẩn IFTTT (NẾU... THÌ...).
/// [editScene] != null -> CHẾ ĐỘ SỬA: form đổ sẵn tên/icon/loại/điều kiện/hành động
/// của ngữ cảnh đó, nút Lưu gọi AutomationProvider.updateScene (giữ nguyên id).
class CreateAutomationScreen extends StatefulWidget {
  final SceneType initialType;
  final SceneItem? editScene;
  const CreateAutomationScreen({super.key, this.initialType = SceneType.automation, this.editScene});

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
  bool _saving = false; // đang chờ API lưu — khóa nút + hiện spinner

  bool get _isEditing => widget.editScene != null;

  @override
  void initState() {
    super.initState();
    final scene = widget.editScene;
    if (scene != null) {
      // Chế độ SỬA: đổ sẵn toàn bộ nội dung ngữ cảnh vào form
      _nameCtrl.text = scene.name;
      _iconCodePoint = scene.iconCodePoint;
      _type = scene.type;
      _conditions.addAll(scene.conditions);
      _actions.addAll(scene.actions);
    } else {
      _type = widget.initialType;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [KÍNH MỜ] Màn này sống TRONG _GlassShell của openAdaptiveScreen — nền/AppBar phải
    // TRONG SUỐT, chữ contrast chuẩn kính (white / black87), thẻ nội dung dùng dải alpha
    // (không màu đặc) để giữ độ xuyên thấu của lớp blur phía sau.
    final Color textMain = isDark ? Colors.white : Colors.black87;
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final Color cardColor = Colors.white.withValues(alpha: isDark ? 0.08 : 0.55);

    return Scaffold(
      backgroundColor: Colors.transparent, // vỏ kính bên ngoài lo phần nền
      appBar: AppBar(
        title: Text(_isEditing ? 'Sửa ngữ cảnh' : 'Tạo ngữ cảnh'),
        backgroundColor: Colors.transparent,
        foregroundColor: textMain,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                // Loading mượt ngay trên nút Lưu trong lúc chờ server
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
                : const Text('Lưu', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // [RESPONSIVE PC] Form ghim giữa màn hình, trần 800px — không phóng to
            // tràn hết chiều ngang trên desktop/web
            constraints: const BoxConstraints(maxWidth: 800),
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
                        child: Icon(sceneIconFor(_iconCodePoint), color: tkGreen, size: 28),
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

  // ---------- Bộ picker THẬT (scene_step_pickers.dart) ----------
  // Điều kiện: Theo thời gian -> TimePicker + ngày lặp -> params {"time","repeat"}.
  Future<void> _pickCondition() async {
    final step = await showConditionPicker(context);
    if (step != null && mounted) setState(() => _conditions.add(step));
  }

  // Hành động: thiết bị THẬT từ kho DPS -> endpoint -> BẬT/TẮT
  // -> params {"mac","endpoint","command"} đúng khuôn Backend Fan-out MQTT.
  Future<void> _pickAction() async {
    final step = await showActionPicker(context);
    if (step != null && mounted) setState(() => _actions.add(step));
  }

  void _pickIcon() {
    // Dùng chung bảng icon CONST với provider (kSceneIcons) — codePoint lưu ra luôn tra ngược được.
    // [KÍNH MỜ ĐỒNG BỘ] Qua showGlassPopup: PC = dialog giữa màn hình, Mobile = sheet.
    const icons = kSceneIcons;
    showGlassPopup(
      context,
      title: 'Chọn biểu tượng',
      body: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Wrap(
          spacing: 14, runSpacing: 14,
          children: icons.map((ic) => InkWell(
                onTap: () { setState(() => _iconCodePoint = ic.codePoint); Navigator.pop(ctx); },
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: tkGreen.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)), child: Icon(ic, color: tkGreen, size: 26)),
              )).toList(),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy thêm ít nhất 1 hành động (THÌ...)'), backgroundColor: Colors.redAccent));
      return;
    }
    final provider = Provider.of<AutomationProvider>(context, listen: false);
    setState(() => _saving = true);

    // API thật (upsert): sửa -> giữ id cũ; tạo mới -> server tự sinh id.
    // null = thành công, chuỗi = câu báo lỗi tiếng Việt từ Backend.
    final String? err = _isEditing
        ? await provider.updateScene(
            widget.editScene!.id,
            name: _nameCtrl.text,
            iconCodePoint: _iconCodePoint,
            type: _type,
            conditions: List.of(_conditions),
            actions: List.of(_actions),
          )
        : await provider.addScene(
            name: _nameCtrl.text,
            iconCodePoint: _iconCodePoint,
            type: _type,
            conditions: List.of(_conditions),
            actions: List.of(_actions),
          );

    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
      return; // giữ nguyên form cho user sửa/thử lại — không mất dữ liệu đã nhập
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEditing ? 'Đã lưu thay đổi ngữ cảnh' : 'Đã tạo ngữ cảnh mới'),
        backgroundColor: tkGreen));
    Navigator.pop(context);
  }
}
