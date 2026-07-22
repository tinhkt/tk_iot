import 'package:flutter/material.dart';

import '../../models/imou_camera_model.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [XEM LẠI — CHỈ DANH SÁCH METADATA] Đã tra cứu kỹ (tài liệu công khai + đọc thẳng mã nguồn thư
/// viện tham chiếu github.com/user2684/imouapi, nền tích hợp Home Assistant CHÍNH THỨC của
/// Imou) — XÁC NHẬN: API `queryLocalRecords`/`queryCloudRecords` chỉ trả metadata (thời gian/
/// kích thước/ảnh nhỏ), KHÔNG có URL phát được. Danh sách năng lực thiết bị của Imou liệt kê
/// "PBSV1: Playback stream supports private protocol to pull stream" — phát lại cần giao thức
/// riêng (SDK gốc), khác Live View (có lối tắt HTTP/HLS qua getLiveStreamInfo). Thư viện tham
/// chiếu (44 hàm API, dùng thật trong sản phẩm) CŨNG không implement phát lại — cùng kết luận.
///
/// Màn này CỐ Ý chỉ hiện danh sách (hữu ích thật — biết có ghi hình hay không, lúc nào) — bấm
/// vào 1 mục hiện rõ "chưa hỗ trợ phát qua API công khai", KHÔNG giả vờ mở được video.
class ImouCameraRecordsScreen extends StatefulWidget {
  final String homeId;
  final ImouCameraModel camera;
  const ImouCameraRecordsScreen({super.key, required this.homeId, required this.camera});

  @override
  State<ImouCameraRecordsScreen> createState() => _ImouCameraRecordsScreenState();
}

class _ImouCameraRecordsScreenState extends State<ImouCameraRecordsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime _selectedDay = DateTime.now();
  bool _loading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _errorMessage = null; });
    final begin = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 0, 0, 0);
    final end = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, 23, 59, 59);
    final source = _tabController.index == 0 ? 'local' : 'cloud';

    final result = await ApiService().getImouCameraRecords(widget.homeId, widget.camera.id, source: source, begin: begin, end: end);
    if (!mounted) return;
    if (result == null) {
      setState(() { _loading = false; _errorMessage = source == 'cloud' ? 'Không lấy được danh sách — có thể chưa kích hoạt gói Cloud Storage' : 'Không lấy được danh sách đoạn ghi'; });
      return;
    }
    setState(() { _loading = false; _records = result; });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _selectedDay = picked);
    _load();
  }

  void _tapRecord(Map<String, dynamic> record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chưa hỗ trợ phát lại'),
        content: const Text(
          'Đoạn ghi này chỉ đọc được thông tin (thời gian/kích thước) qua API công khai của Imou — '
          'phát lại video cần giao thức riêng (SDK gốc) mà tài khoản Developer cơ bản chưa dùng được. '
          'Bạn vẫn có thể xem lại đoạn này trực tiếp trong App Imou Life.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: Text('Xem lại · ${widget.camera.name}'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: _tkGreen,
          unselectedLabelColor: textSub,
          indicatorColor: _tkGreen,
          tabs: const [Tab(text: 'Thẻ nhớ SD'), Tab(text: 'Cloud Storage')],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today_rounded), tooltip: 'Chọn ngày', onPressed: _pickDay),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(Icons.event_rounded, size: 16, color: textSub),
                const SizedBox(width: 6),
                Text('${_selectedDay.day}/${_selectedDay.month}/${_selectedDay.year}', style: TextStyle(color: textSub, fontSize: 13)),
              ]),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _tkGreen))
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded, color: textSub, size: 32),
                                const SizedBox(height: 8),
                                Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: textSub)),
                              ],
                            ),
                          ),
                        )
                      : _records.isEmpty
                          ? Center(child: Text('Không có đoạn ghi nào trong ngày này', style: TextStyle(color: textSub)))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _records.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final r = _records[index];
                                final String thumb = (r['thumb_url'] ?? '').toString();
                                return InkWell(
                                  onTap: () => _tapRecord(r),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: isDark ? const Color(0xFF1E293B) : Colors.white, borderRadius: BorderRadius.circular(12)),
                                    child: Row(children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: thumb.isNotEmpty
                                            ? Image.network(thumb, width: 64, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => _thumbPlaceholder())
                                            : _thumbPlaceholder(),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${r['begin_time'] ?? ''}', style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600)),
                                            Text('đến ${r['end_time'] ?? ''}', style: TextStyle(color: textSub, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.play_circle_outline_rounded, color: textSub),
                                    ]),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
        width: 64,
        height: 48,
        color: Colors.black26,
        child: const Icon(Icons.videocam_rounded, color: Colors.white54, size: 20),
      );
}
