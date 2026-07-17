import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/automation_provider.dart';
import '../../services/constraint_engine.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../widgets/glass_popup.dart';
import '../../widgets/scene_step_pickers.dart';
import '../../localization/app_translations.dart';

/// CreateAutomationScreen — Tạo/Sửa Ngữ cảnh theo chuẩn IFTTT (NẾU... THÌ...).
/// [editScene] != null -> CHẾ ĐỘ SỬA: form đổ sẵn tên/icon/loại/điều kiện/hành động
/// của ngữ cảnh đó, nút Lưu gọi AutomationProvider.updateScene (giữ nguyên id).
/// [embedded]=true khi nhúng làm 1 tab trong AddSceneOrScheduleScreen (bỏ Scaffold/AppBar
/// riêng — tránh 2 AppBar lồng nhau; nút Lưu chuyển xuống cuối form thay vì nằm trong AppBar).
class CreateAutomationScreen extends StatefulWidget {
  final SceneType initialType;
  final SceneItem? editScene;
  final bool embedded;
  const CreateAutomationScreen({super.key, this.initialType = SceneType.automation, this.editScene, this.embedded = false});

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
    final t = AppTranslations.of(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [KÍNH MỜ] Màn này sống TRONG _GlassShell của openAdaptiveScreen — nền/AppBar phải
    // TRONG SUỐT, chữ contrast chuẩn kính (white / black87), thẻ nội dung dùng dải alpha
    // (không màu đặc) để giữ độ xuyên thấu của lớp blur phía sau.
    final Color textMain = isDark ? Colors.white : Colors.black87;
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final Color cardColor = Colors.white.withValues(alpha: isDark ? 0.08 : 0.55);

    final Widget form = Center(
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
                        decoration: InputDecoration(hintText: t.text('scene_name_hint'), hintStyle: TextStyle(color: textSub), border: InputBorder.none),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  // Chọn loại: chạm-để-chạy vs tự động
                  SegmentedButton<SceneType>(
                    segments: [
                      ButtonSegment(value: SceneType.tapToRun, icon: const Icon(Icons.touch_app), label: Text(t.text('tap_to_run_tab'))),
                      ButtonSegment(value: SceneType.automation, icon: const Icon(Icons.bolt), label: Text(t.text('auto_tab'))),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ]),
                const SizedBox(height: 16),

                // --- NẾU... (điều kiện) — ẩn với "Chạm để chạy" (kích hoạt thủ công) ---
                if (_type == SceneType.automation) ...[
                  _ifThenHeader(t.text('if_label'), Icons.help_outline, textMain),
                  const SizedBox(height: 8),
                  ..._conditions.asMap().entries.map((e) => _stepTile(cardColor, textMain, textSub, e.value, () => setState(() => _conditions.removeAt(e.key)))),
                  _addButton(t.text('add_condition'), _pickCondition),
                  const SizedBox(height: 16),
                ],

                // --- THÌ... (hành động) ---
                _ifThenHeader(t.text('then_label'), Icons.play_circle_outline, textMain),
                const SizedBox(height: 8),
                ..._actions.asMap().entries.map((e) => _stepTile(cardColor, textMain, textSub, e.value, () => setState(() => _actions.removeAt(e.key)))),
                _addButton(t.text('add_action'), _pickAction),

                // [embedded] Không còn AppBar để đặt nút Lưu -> chuyển xuống cuối form.
                if (widget.embedded) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_isEditing ? t.text('save_changes') : t.text('create_scene_title')),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    // "form" ở trên chỉ là Center(child: ConstrainedBox(child: ListView(...))) — KHÔNG còn
    // Scaffold/SafeArea lồng trong biến này; 2 nhánh dưới tự quyết định có cần bọc thêm
    // Scaffold/AppBar riêng hay không tùy [embedded].

    // [embedded] Chủ (AddSceneOrScheduleScreen) đã tự lo Scaffold/AppBar/TabBar chung —
    // trả thẳng form, KHÔNG lồng thêm Scaffold thứ 2 (2 AppBar chồng nhau).
    if (widget.embedded) return SafeArea(child: form);

    return AppScaffold(
      backgroundColor: Colors.transparent, // vỏ kính bên ngoài lo phần nền
      appBar: AppBar(
        title: Text(_isEditing ? t.text('edit_scene_title') : t.text('create_scene_title')),
        backgroundColor: Colors.transparent,
        foregroundColor: textMain,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                // Loading mượt ngay trên nút Lưu trong lúc chờ server
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
                : Text(t.text('save'), style: const TextStyle(color: tkGreen, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(child: form),
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
  //
  // [CONSTRAINT ENGINE] Quy tắc 'scene.actions' (CapabilityRegistry): MỖI ENDPOINT
  // CHỈ MANG 1 HÀNH ĐỘNG trong một ngữ cảnh — thêm hành động mới cho cùng endpoint
  // là engine ra lệnh THAY hành động cũ (hết cảnh "bật rồi tắt cùng kênh" xung đột).
  // Bước không nhắm endpoint (Gửi thông báo, Chờ...) không bị ràng buộc.
  Future<void> _pickAction() async {
    final step = await showActionPicker(context);
    if (step == null || !mounted) return;

    final String? mac = step.params?['mac']?.toString();
    final String? ep = step.params?['endpoint']?.toString();
    if (mac != null && ep != null) {
      // Dịch các action hiện có sang SelectionItem (key = vị trí, scope = mac|endpoint)
      final current = <SelectionItem>[];
      final stepByKey = <String, SceneStep>{};
      for (int i = 0; i < _actions.length; i++) {
        final m = _actions[i].params?['mac']?.toString();
        final e = _actions[i].params?['endpoint']?.toString();
        if (m == null || e == null) continue; // thông báo/delay: ngoài phạm vi quy tắc
        final item = SelectionItem(key: 'a$i', scopeKey: '$m|$e');
        current.add(item);
        stepByKey[item.key] = _actions[i];
      }
      final res = ValidationEngine.validateFor('scene.actions',
          current: current, attempt: SelectionItem(key: 'new', scopeKey: '$mac|$ep'));
      if (!res.allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res.reason ?? 'Vi phạm quy tắc ngữ cảnh'), backgroundColor: Colors.redAccent));
        return;
      }
      if (res.operations.isNotEmpty) {
        final doomed = {for (final op in res.operations) stepByKey[op.targetKey]};
        setState(() => _actions.removeWhere(doomed.contains));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Kênh này đã có hành động — đã thay bằng hành động mới'),
            backgroundColor: Colors.orange));
      }
    }
    setState(() => _actions.add(step));
  }

  void _pickIcon() {
    // Dùng chung bảng icon CONST với provider (kSceneIcons) — codePoint lưu ra luôn tra ngược được.
    // [KÍNH MỜ ĐỒNG BỘ] Qua showGlassPopup: PC = dialog giữa màn hình, Mobile = sheet.
    // Gọi từ InkWell onTap (tap handler, KHÔNG phải build pass dù chạy đồng bộ trước await
    // nào) -> listen: false, nếu không context.watch() ném assertion khiến bấm icon vô tác dụng.
    final t = AppTranslations.of(context, listen: false);
    const icons = kSceneIcons;
    showGlassPopup(
      context,
      title: t.text('pick_icon_title'),
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
    // [SỬA LỖI LIỆT NÚT] Ghi chú cũ ở đây từng cho rằng "gọi trước await trong tap handler là
    // an toàn" — SAI: context.watch() được Provider assert bằng cờ TOÀN CỤC
    // context.owner!.debugBuilding (chỉ true khi Flutter đang thực sự chạy buildScope() của 1
    // khung hình), cờ này LUÔN false khi đang xử lý sự kiện chạm — bất kể có await hay chưa.
    // Gọi ở đây từng khiến nút "Lưu"/"Tạo ngữ cảnh" bấm không phản ứng gì (exception rơi vào
    // Future lỗi không ai bắt, không hiện đỏ màn hình). BẮT BUỘC listen: false.
    final t = AppTranslations.of(context, listen: false);
    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.text('need_one_action')), backgroundColor: Colors.redAccent));
      return;
    }
    final String savedMsg = _isEditing ? t.text('scene_updated') : t.text('scene_created');
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
        content: Text(savedMsg),
        backgroundColor: tkGreen));
    Navigator.pop(context);
  }
}
