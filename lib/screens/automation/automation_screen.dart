import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/automation_provider.dart';
import '../../providers/device_provider.dart';
import '../../services/schedule_service.dart';
import '../../widgets/adaptive_navigation.dart';
import 'add_scene_or_schedule_screen.dart';
import 'create_automation_screen.dart';

/// AutomationScreen — Ngữ cảnh: 3 tab 'Chạm để chạy' + 'Tự động' + 'Lịch trình' (tổng hợp
/// mọi hẹn giờ/lịch trình của các thiết bị trong nhà, trước đây phân tán mỗi thiết bị một
/// nơi trong DeviceTimerScreen — nay xem tập trung tại đây). [embedded]=true khi nhúng làm
/// tab body của Dashboard (bỏ AppBar để tránh double). FAB mở popup 2 tab (Ngữ cảnh/Lịch
/// trình) — xem AddSceneOrScheduleScreen.
class AutomationScreen extends StatefulWidget {
  final bool embedded;
  const AutomationScreen({super.key, this.embedded = false});

  static const Color tkGreen = Color(0xFF00A651);

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  static const Color tkGreen = AutomationScreen.tkGreen;

  // [ÉP LÀM MỚI] _ScheduleAggregateList không có provider trung gian (chỉ là State cục bộ) —
  // đổi Key này ép Flutter HỦY + TẠO LẠI toàn bộ subtree đó (initState chạy lại -> fetch lại)
  // ngay sau khi popup Thêm/Sửa lịch trình đóng lại với kết quả "đã lưu".
  Key _scheduleListKey = UniqueKey();

  Future<void> _openAddPopup() async {
    final result = await openAdaptiveScreen(context, const AddSceneOrScheduleScreen());
    // true = tab "Lịch trình" của popup vừa lưu 1 lịch/đếm ngược -> làm mới danh sách gộp.
    // Ngữ cảnh (Scene) KHÔNG cần xử lý ở đây — AutomationProvider tự notifyListeners().
    if (result == true && mounted) {
      setState(() => _scheduleListKey = UniqueKey());
    }
  }

  Future<void> _editSchedule(ScheduleItem s) async {
    final result = await openAdaptiveScreen(context, AddSceneOrScheduleScreen(editingSchedule: s));
    if (result == true && mounted) {
      setState(() => _scheduleListKey = UniqueKey());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
        appBar: widget.embedded
            ? null
            : AppBar(title: const Text('Ngữ cảnh'), backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white, foregroundColor: textMain, elevation: 0),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: tkGreen,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: const Text('Thêm mới'),
          // [RESPONSIVE NAV] PC: dialog lớn giữ nguyên Sidebar; Mobile: push như cũ
          onPressed: _openAddPopup,
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (widget.embedded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome, color: tkGreen, size: 26),
                    const SizedBox(width: 12),
                    Text('Ngữ cảnh', style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]),
                ),
              // [isScrollable] 3 tab dàn hàng ngang đủ chỗ trên PC; trên Mobile (màn hẹp) chữ
              // KHÔNG bị ép nhỏ/overflow — TabBar tự co theo nội dung + vuốt ngang để thấy
              // "Lịch trình" ở bên phải, thay vì Flutter chia đều 3 cột cứng nhắc.
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: tkGreen,
                labelColor: tkGreen,
                unselectedLabelColor: textSub,
                tabs: const [
                  Tab(icon: Icon(Icons.touch_app), text: 'Chạm để chạy'),
                  Tab(icon: Icon(Icons.bolt), text: 'Tự động'),
                  Tab(icon: Icon(Icons.event_repeat), text: 'Lịch trình'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    const _SceneList(type: SceneType.tapToRun),
                    const _SceneList(type: SceneType.automation),
                    _ScheduleAggregateList(key: _scheduleListKey, onEdit: _editSchedule),
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

/// Tab "Lịch trình" — TỔNG HỢP mọi hẹn giờ của mọi thiết bị trong nhà đang mở, một lần gọi
/// GET /api/homes/:id/schedules (chống N+1, xem GetHomeSchedules bên Go).
///   * Chạm cả thẻ  -> [onEdit] (mở lại popup Thêm/Sửa, đã đổ sẵn dữ liệu, Lưu = UPDATE/PUT).
///   * Nhấn giữ thẻ -> xác nhận rồi DELETE + gỡ khỏi danh sách tại chỗ.
///   * Switch       -> bật/tắt nhanh, optimistic.
class _ScheduleAggregateList extends StatefulWidget {
  final ValueChanged<ScheduleItem> onEdit;
  const _ScheduleAggregateList({super.key, required this.onEdit});

  @override
  State<_ScheduleAggregateList> createState() => _ScheduleAggregateListState();
}

class _ScheduleAggregateListState extends State<_ScheduleAggregateList> {
  static const Color tkGreen = Color(0xFF00A651);
  final ScheduleService _api = ScheduleService();
  List<ScheduleItem> _schedules = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final homeId = context.read<AutomationProvider>().homeId;
    if (homeId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Chưa xác định được nhà hiện tại — mở lại màn hình Ngữ cảnh';
      });
      return;
    }
    setState(() => _loading = true);
    final (list, err) = await _api.fetchHomeSchedules(homeId);
    if (!mounted) return;
    setState(() {
      _schedules = list;
      _loading = false;
      _error = err;
    });
  }

  Future<void> _toggle(ScheduleItem s, bool v) async {
    setState(() => s.isEnabled = v);
    final err = await _api.toggleSchedule(s.id, v);
    if (err != null && mounted) {
      setState(() => s.isEnabled = !v);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
    }
  }

  /// [YÊU CẦU 4 — NHẤN GIỮ ĐỂ XÓA] Xác nhận rồi DELETE + gỡ khỏi danh sách tại chỗ (không
  /// cần fetch lại cả danh sách — 1 dòng vừa bị xóa ta đã biết chắc chắn).
  Future<void> _confirmDelete(ScheduleItem s, String friendlyName) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa lịch trình'),
        content: Text('Bạn có chắc chắn muốn xóa lịch trình "$friendlyName — ${s.time}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng ý xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final err = await _api.deleteSchedule(s.id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
      return; // xóa thất bại -> GIỮ NGUYÊN dòng trong danh sách, không lỡ tay mất hiển thị
    }
    setState(() => _schedules.removeWhere((x) => x.id == s.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã xóa lịch trình "$friendlyName — ${s.time}"'), backgroundColor: tkGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    // [YÊU CẦU 1 — TÊN THÂN THIỆN] context.watch: DPS đổi tên realtime (user vào Cài đặt
    // thiết bị đổi tên) -> danh sách này tự vẽ lại NGAY, không cần đóng/mở lại tab.
    final deviceProvider = context.watch<DeviceProvider>();

    if (_loading) return const Center(child: CircularProgressIndicator(color: tkGreen));
    if (_error != null && _schedules.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent))));
    }
    if (_schedules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Chưa có lịch trình nào.\nBấm "Thêm mới" > tab "Lịch trình" để tạo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: textSub),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: tkGreen,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _schedules.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final s = _schedules[index];
          final bool on = s.isOn;
          // [YÊU CẦU 1] Tên ĐÚNG endpoint (không phải tên chung của cả thiết bị — máy nhiều
          // relay mỗi kênh một tên khác nhau) — ưu tiên DPS sống, rơi về tên Backend gửi kèm.
          final String friendlyName = deviceProvider.displayNameOfEndpoint(s.deviceMac, s.endpoint, fallback: s.deviceName);
          return Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              // [YÊU CẦU 3] Chạm -> mở lại Form Thêm/Sửa, đã điền sẵn -> Lưu gọi UPDATE (PUT).
              onTap: () => widget.onEdit(s),
              // [YÊU CẦU 4] Nhấn giữ -> xác nhận -> DELETE + gỡ khỏi UI.
              onLongPress: () => _confirmDelete(s, friendlyName),
              leading: CircleAvatar(
                backgroundColor: (on ? tkGreen : Colors.redAccent).withValues(alpha: 0.15),
                child: Icon(on ? Icons.power_settings_new : Icons.power_off, color: on ? tkGreen : Colors.redAccent),
              ),
              title: Text(
                '$friendlyName — ${s.time}',
                style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${s.repeatDays} • ${on ? 'Bật' : 'Tắt'} thiết bị • Chạm để sửa, giữ để xóa', style: TextStyle(color: textSub, fontSize: 12)),
              trailing: Switch(value: s.isEnabled, activeThumbColor: tkGreen, onChanged: (v) => _toggle(s, v)),
            ),
          );
        },
      ),
    );
  }
}

/// Danh sách ngữ cảnh theo loại — tab tapToRun có nút "Chạy", tab automation có Switch bật/tắt.
class _SceneList extends StatelessWidget {
  final SceneType type;
  const _SceneList({required this.type});

  static const Color tkGreen = Color(0xFF00A651);

  /// Nhấn giữ thẻ ngữ cảnh -> AlertDialog xác nhận -> DELETE /api/scenes/:id.
  /// Provider xóa OPTIMISTIC: gỡ khỏi UI ngay khi bấm Đồng ý (notifyListeners ->
  /// Consumer vẽ lại tức thì); API lỗi thì tự gắn lại đúng vị trí cũ + SnackBar đỏ.
  Future<void> _confirmDeleteScene(BuildContext context, AutomationProvider provider, SceneItem s) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa ngữ cảnh'),
        content: Text('Bạn có chắc chắn muốn xóa ngữ cảnh "${s.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đồng ý xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final err = await provider.deleteScene(s.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? 'Đã xóa ngữ cảnh "${s.name}"'),
      backgroundColor: err == null ? tkGreen : Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Consumer<AutomationProvider>(
      builder: (context, provider, _) {
        final scenes = type == SceneType.tapToRun ? provider.tapToRun : provider.automations;
        // Đang tải lần đầu từ server -> spinner thay vì chớp màn trống
        if (provider.isLoading && scenes.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: tkGreen));
        }
        if (scenes.isEmpty) {
          return Center(child: Text('Chưa có ngữ cảnh nào.\nBấm "Thêm mới" để tạo.', textAlign: TextAlign.center, style: TextStyle(color: textSub)));
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                // Bấm cả thẻ (không phải Switch/nút Chạy) -> mở màn SỬA ngữ cảnh với dữ liệu đổ sẵn
                onTap: () => openAdaptiveScreen(context, CreateAutomationScreen(editScene: s)),
                // Nhấn giữ thẻ -> hỏi xác nhận rồi xóa (áp dụng cho cả 2 tab)
                onLongPress: () => _confirmDeleteScene(context, provider, s),
                leading: CircleAvatar(radius: 24, backgroundColor: tkGreen.withValues(alpha: 0.15), child: Icon(s.icon, color: tkGreen, size: 26)),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(summary, style: TextStyle(color: textSub, fontSize: 12))),
                trailing: type == SceneType.tapToRun
                    // Chạm để chạy -> nút "Chạy" gọi API execute thật
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Chạy'),
                        onPressed: () async {
                          // Giữ ref DeviceProvider TRƯỚC await — nó sống suốt vòng đời app
                          // nên gọi lại an toàn dù thẻ này đã bị dispose sau 1.5s.
                          final deviceProvider = context.read<DeviceProvider>();
                          final err = await provider.executeScene(s.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(err ?? 'Đang chạy ngữ cảnh "${s.name}"'),
                              backgroundColor: err == null ? tkGreen : Colors.redAccent));
                          // [FALLBACK ĐỒNG BỘ UI] Scene chạy OK -> phần cứng đổi trạng thái +
                          // bắn state feedback qua MQTT (UI tự cập nhật). Nhưng phòng khi sóng
                          // về trễ/rớt: sau 1.5s chủ động ép kéo lại trạng thái thật từ Server.
                          if (err == null) {
                            Future.delayed(const Duration(milliseconds: 1500), deviceProvider.requestRefresh);
                          }
                        },
                      )
                    // Tự động -> Switch bật/tắt (optimistic — provider tự hoàn tác khi lỗi)
                    : Switch(
                        value: s.enabled,
                        activeThumbColor: tkGreen,
                        onChanged: (v) async {
                          final err = await provider.toggleEnabled(s.id, v);
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.redAccent));
                          }
                        },
                      ),
              ),
            );
          },
        );
      },
    );
  }
}
