import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/camera_entry.dart';
import '../../services/api_service.dart';
import 'imou_ptz_pad.dart';

const Color _tkGreen = Color(0xFF00A651);

/// [THIẾT KẾ LẠI TOÀN BỘ — theo mẫu chuẩn NVR user tham khảo] Thay hẳn trang toàn màn hình đen
/// ép xoay ngang trước đây — giờ là 1 trang CHI TIẾT CAMERA bình thường (AppBar + nội dung cuộn +
/// BottomNavigationBar 3 tab), giống cấu trúc app NVR thật (Hikvision/Imou Life...): Appbar (Back
/// + tên camera/nhà + Playlist + Cài đặt) -> Video 16:9 -> Thao tác nhanh -> Chức năng nâng cao
/// (chỉ ở tab Trực tiếp) HOẶC danh sách Xem lại/Sự kiện (2 tab còn lại).
///
/// [XEM LẠI — GIỚI HẠN THẬT ĐÃ TỰ KIỂM CHỨNG, KHÔNG PHẢI GIẢ ĐỊNH] Đã tra 3 nguồn độc lập (tài
/// liệu chính thức Imou cho cả local+cloud record, mã nguồn thư viện tham chiếu mã nguồn mở
/// imouapi, cộng đồng dev thực tế đang gặp đúng vấn đề) — Imou Open API công khai KHÔNG có endpoint
/// HTTP nào trả URL phát được (HLS/m3u8) cho video ĐÃ GHI (khác Live View có getLiveStreamInfo).
/// Đã tự chạy thử SDK gốc (LCOpenSDK, giao thức riêng) với dữ liệu ghi hình THẬT — bắt tay HTTP/PSK
/// thành công (200 OK) nhưng onPlayBegin KHÔNG BAO GIỜ bắn ra (chỉ onPlayFinished sau 46s, nghi vấn
/// SELinux chặn ioctl UDP-socket trên máy test MIUI) — CHƯA chạy ổn định. Tab Xem lại vì vậy hiện
/// ĐÚNG danh sách bản ghi thật (metadata có sẵn), bấm vào 1 mục hiện rõ giới hạn ngay trong khung
/// video thay vì giả vờ phát được.
Future<void> openCameraSingleFullscreen(
  BuildContext context, {
  required CameraEntry entry,
  required VoidCallback onOpenSettings,
}) {
  return Navigator.push(context, MaterialPageRoute(builder: (_) => _CameraDetailScreen(entry: entry, onOpenSettings: onOpenSettings)));
}

enum _DetailTab { live, playback, events }

class _CameraDetailScreen extends StatefulWidget {
  final CameraEntry entry;
  final VoidCallback onOpenSettings;
  const _CameraDetailScreen({required this.entry, required this.onOpenSettings});

  @override
  State<_CameraDetailScreen> createState() => _CameraDetailScreenState();
}

class _CameraDetailScreenState extends State<_CameraDetailScreen> {
  late final Player _player;
  late final VideoController _controller;
  // [FIX — RÀ SOÁT HIỆU NĂNG Trụ cột 2, Thấp — cùng họ với camera_tile.dart] Lưu tường minh thay
  // vì gọi .listen() rồi bỏ, để cancel() rõ ràng trong dispose().
  StreamSubscription<String>? _errorSub;
  _DetailTab _tab = _DetailTab.live;
  bool _isFullscreen = false;
  bool _ptzPanelOpen = false;

  // ---- Thao tác nhanh đè lên video (chỉ Mobile) — auto-hide ----
  bool _quickActionsVisible = false;
  Timer? _quickActionsTimer;

  // ---- Trực tiếp ----
  bool _liveLoading = true;
  String? _liveError;
  ({String hd, String sd})? _liveUrls;
  bool _useHd = true;

  // ---- Xem lại ----
  DateTime _playbackDay = DateTime.now();
  String _playbackSource = 'local'; // 'local' | 'cloud'
  bool _recordsLoading = false;
  String? _recordsError;
  List<Map<String, dynamic>> _records = [];
  Map<String, dynamic>? _selectedRecord;

  // ---- Sự kiện ----
  DateTime _eventsDay = DateTime.now();
  bool _eventsLoading = false;
  String? _eventsError;
  List<Map<String, dynamic>> _events = [];
  Map<String, dynamic>? _selectedEvent;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _errorSub = _player.stream.error.listen((e) {
      if (mounted) setState(() { _liveError = e; _liveLoading = false; });
    });
    _loadLive();
  }

  @override
  void dispose() {
    // [BẮT BUỘC — quên bước này sẽ vỡ giao diện màn khác] Nếu đang ở chế độ toàn màn hình lúc rời
    // trang (back cứng/gesture), PHẢI trả về portrait + hiện lại thanh hệ thống trước khi dispose —
    // phần còn lại của app chỉ thiết kế cho Portrait.
    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    // [KHÔNG được bỏ — cùng họ lỗi leak PTZ đã vá trước đó] Timer.cancel() ở đây là lưới an toàn
    // CUỐI CÙNG — nếu thiếu, Timer đang đếm ngược khi widget bị huỷ vẫn chạy tiếp rồi gọi setState
    // trên 1 State đã dispose (dù có check `mounted` mới không crash, vẫn là 1 Timer "mồ côi" tồn
    // tại thừa trong bộ nhớ tới khi tự bắn xong).
    _quickActionsTimer?.cancel();
    _errorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // [NÚT TOÀN MÀN HÌNH/XOAY NGANG — theo yêu cầu user, thiếu hẳn trong bản thiết kế lại] Gộp 2
  // yêu cầu "xem full màn hình" + "xoay ngang" thành 1 hành động: ép landscape (giống YouTube/hầu
  // hết app camera — không phụ thuộc auto-rotate hệ thống có bật hay không) + ẩn AppBar/BottomNav,
  // video lấp đầy toàn màn hình thật. `_player`/`_controller` KHÔNG bị tạo lại — cùng 1 Player vẫn
  // đang phát, chỉ đổi cây widget bao quanh nó (Scaffold thường <-> Scaffold toàn màn hình đen).
  void _enterFullscreen() {
    setState(() => _isFullscreen = true);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitFullscreen() {
    setState(() => _isFullscreen = false);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _loadLive() async {
    setState(() { _liveLoading = true; _liveError = null; });
    final urls = await widget.entry.resolveLiveUrls();
    if (!mounted) return;
    _liveUrls = urls;
    final url = _useHd ? urls.hd : urls.sd;
    if (url.isEmpty) {
      setState(() { _liveLoading = false; _liveError = 'Không lấy được URL xem trực tiếp'; });
      return;
    }
    await _player.open(Media(url));
    if (mounted) setState(() => _liveLoading = false);
  }

  // [KHÔNG gọi lại API — Trụ cột 4 rà soát hiệu năng] resolveLiveUrls() đã lấy CẢ 2 URL (hd/sd)
  // 1 lần duy nhất lúc mở màn — chuyển chất lượng chỉ đổi Media() đang phát, không round-trip
  // getImouLiveURL lần nữa.
  Future<void> _toggleQuality() async {
    if (_liveUrls == null) return;
    final url = _useHd ? _liveUrls!.sd : _liveUrls!.hd;
    if (url.isEmpty) return;
    setState(() { _useHd = !_useHd; _liveLoading = true; });
    await _player.open(Media(url));
    if (mounted) setState(() => _liveLoading = false);
  }

  void _switchTab(_DetailTab tab) {
    if (_tab == tab) return;
    setState(() { _tab = tab; _ptzPanelOpen = false; });
    if (tab == _DetailTab.live) {
      _loadLive();
    } else {
      // Rời tab Trực tiếp -> dừng phát (đỡ tốn băng thông/CPU chạy nền không ai xem).
      _player.stop();
      if (tab == _DetailTab.playback && widget.entry.hasRecords && _records.isEmpty) _loadRecords();
      if (tab == _DetailTab.events && widget.entry.hasEvents && _events.isEmpty) _loadEvents();
    }
  }

  Future<void> _loadRecords() async {
    setState(() { _recordsLoading = true; _recordsError = null; _selectedRecord = null; });
    final begin = DateTime(_playbackDay.year, _playbackDay.month, _playbackDay.day, 0, 0, 0);
    final end = DateTime(_playbackDay.year, _playbackDay.month, _playbackDay.day, 23, 59, 59);
    final result = await ApiService().getImouCameraRecords(widget.entry.homeId, widget.entry.imouCamera!.id, source: _playbackSource, begin: begin, end: end);
    if (!mounted) return;
    if (result == null) {
      setState(() { _recordsLoading = false; _recordsError = _playbackSource == 'cloud' ? 'Không lấy được danh sách — có thể chưa kích hoạt gói Cloud Storage' : 'Không lấy được danh sách đoạn ghi'; });
      return;
    }
    setState(() { _recordsLoading = false; _records = result; });
  }

  Future<void> _loadEvents() async {
    setState(() { _eventsLoading = true; _eventsError = null; _selectedEvent = null; });
    final begin = DateTime(_eventsDay.year, _eventsDay.month, _eventsDay.day, 0, 0, 0);
    final end = DateTime(_eventsDay.year, _eventsDay.month, _eventsDay.day, 23, 59, 59);
    final result = await ApiService().getImouCameraEvents(widget.entry.homeId, widget.entry.imouCamera!.id, begin: begin, end: end);
    if (!mounted) return;
    if (result == null) {
      setState(() { _eventsLoading = false; _eventsError = 'Không lấy được danh sách sự kiện'; });
      return;
    }
    setState(() { _eventsLoading = false; _events = result; });
  }

  Future<void> _pickPlaybackDay() async {
    final picked = await showDatePicker(context: context, initialDate: _playbackDay, firstDate: DateTime.now().subtract(const Duration(days: 90)), lastDate: DateTime.now());
    if (picked == null) return;
    setState(() => _playbackDay = picked);
    _loadRecords();
  }

  Future<void> _pickEventsDay() async {
    final picked = await showDatePicker(context: context, initialDate: _eventsDay, firstDate: DateTime.now().subtract(const Duration(days: 90)), lastDate: DateTime.now());
    if (picked == null) return;
    setState(() => _eventsDay = picked);
    _loadEvents();
  }

  void _showUnsupported(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chưa hỗ trợ: $feature'), duration: const Duration(seconds: 2)));
  }

  // [THAY showModalBottomSheet — theo yêu cầu user] Trước đây PTZ mở dạng popup modal đè lên toàn
  // bộ màn hình (kể cả các icon khác trong lưới) — giờ chỉ TOGGLE 1 cờ trạng thái, panel PTZ tự
  // nằm gọn vào PHẦN TRỐNG có sẵn bên dưới lưới (xem _buildAdvancedGridWrap), không che icon nào
  // cả. Icon PTZ tự "sáng lên" khi đang mở (xem _buildAdvancedGridWrap) — không cần dialog riêng.
  void _togglePtzPanel() => setState(() => _ptzPanelOpen = !_ptzPanelOpen);

  // [AUTO-HIDE Thao tác nhanh — theo yêu cầu user, chỉ Mobile] Chạm vào video -> hiện dải nút +
  // khởi động lại đếm ngược 4s (huỷ Timer cũ nếu đang chạy dở, tránh 2 Timer chồng nhau tự ẩn
  // nhầm lúc). Hết giờ -> tự ẩn, người dùng chạm lại video để hiện tiếp — đúng hành vi auto-hide
  // chuẩn của mọi trình phát video (YouTube, VLC...).
  void _revealQuickActions() {
    _quickActionsTimer?.cancel();
    setState(() => _quickActionsVisible = true);
    _quickActionsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _quickActionsVisible = false);
    });
  }

  String _alarmTypeLabel(int type) {
    switch (type) {
      case 0:
        return 'Phát hiện người (hồng ngoại)';
      case 1:
        return 'Phát hiện chuyển động';
      default:
        return 'Sự kiện #$type';
    }
  }

  // [ĐÈ Thao tác nhanh LÊN VIDEO — theo yêu cầu user, CHỈ Mobile] `isWide` = true (PC/Tablet
  // ngang) giữ nguyên hàng Thao tác nhanh Ở SIDEBAR như cũ (không đụng, user không yêu cầu đổi) —
  // chỉ khi `isWide == false` mới bật GestureDetector chạm-hiện + dải nút bán trong suốt đè lên
  // video, nhường hẳn khoảng trống bên dưới cho lưới nâng cao/danh sách.
  Widget _videoBoxWithFullscreenButton(bool isWide) {
    final bool showOverlayQuickActions = !isWide && _tab == _DetailTab.live;
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: showOverlayQuickActions ? _revealQuickActions : null,
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildVideoArea(),
                // [NÚT TOÀN MÀN HÌNH — chỉ tab Trực tiếp] Dời lên GÓC TRÊN-PHẢI (trước đây ở
                // dưới-phải) để không đè lên dải Thao tác nhanh auto-hide mới thêm ở cạnh dưới.
                if (_tab == _DetailTab.live)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                        tooltip: 'Toàn màn hình / Xoay ngang',
                        onPressed: _enterFullscreen,
                      ),
                    ),
                  ),
                // [Thao tác nhanh — AUTO-HIDE, đè lên cạnh dưới video] Mặc định ẩn (opacity 0 +
                // IgnorePointer để chạm xuyên qua xuống GestureDetector phía dưới thay vì bị dải
                // nút vô hình chắn mất) — chạm vào video (_revealQuickActions) hiện lên mượt qua
                // AnimatedOpacity rồi tự ẩn sau 4s.
                if (showOverlayQuickActions)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: _quickActionsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_quickActionsVisible,
                        child: Container(
                          color: Colors.black45,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _buildQuickActionsRow(Colors.white, Colors.white70),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    // [CHẾ ĐỘ TOÀN MÀN HÌNH] Scaffold RIÊNG, tối giản — chỉ video lấp đầy + 1 nút thu nhỏ. `_player`/
    // `_controller` dùng CHUNG với Scaffold thường bên dưới (không tạo lại) nên video không giật/
    // load lại khi bật/tắt chế độ này. PopScope chặn back cứng thoát hẳn màn hình — back trước tiên
    // chỉ thoát toàn màn hình (đúng hành vi chuẩn của mọi app xem video).
    if (_isFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _exitFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: _buildVideoArea()),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(icon: const Icon(Icons.close_fullscreen_rounded, color: Colors.white), tooltip: 'Thu nhỏ', onPressed: _exitFullscreen),
                  ),
                ),
                // [PTZ trên toàn màn hình — theo yêu cầu user] Không còn "phần trống bên dưới" như
                // ở màn thường (video lấp đầy edge-to-edge) -> panel PTZ ở đây BẮT BUỘC phải là
                // OVERLAY đè lên video (nền bán trong suốt), khác hẳn cách xử lý "nằm gọn vào chỗ
                // trống" ở _buildAdvancedGridWrap.
                if (widget.entry.hasPTZ) ...[
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: _ptzPanelOpen ? _tkGreen.withValues(alpha: 0.85) : Colors.black45,
                      shape: const CircleBorder(),
                      child: IconButton(icon: const Icon(Icons.control_camera_rounded, color: Colors.white), tooltip: 'PTZ', onPressed: _togglePtzPanel),
                    ),
                  ),
                  if (_ptzPanelOpen)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                        child: ImouPtzPad(homeId: widget.entry.homeId, cameraId: widget.entry.imouCamera!.id),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.entry.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (widget.entry.homeName.isNotEmpty) Text(widget.entry.homeName, style: TextStyle(fontSize: 11, color: textSub)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.playlist_play_rounded), tooltip: 'Xem lại', onPressed: () => _switchTab(_DetailTab.playback)),
          IconButton(icon: const Icon(Icons.settings_rounded), tooltip: 'Cài đặt', onPressed: widget.onOpenSettings),
        ],
      ),
      // [BỐ CỤC RESPONSIVE — theo yêu cầu user] LayoutBuilder đo bề rộng THẬT của body (không phải
      // toàn màn hình vật lý — đã trừ AppBar/lề) để quyết định bố cục: PC/Tablet ngang (>800px)
      // dùng Row 2 cột (Video trái + Sidebar phải cố định), Mobile/hẹp giữ Column cũ (Video trên,
      // nội dung dưới).
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 800;
          final Widget videoBox = _videoBoxWithFullscreenButton(isWide);

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // [Center + AspectRatio bên trong Expanded — theo đúng yêu cầu user] Video được
                // PHÓNG TO HẾT CỠ vừa khít không gian khả dụng của cột trái, không tràn cột phải.
                Expanded(flex: 4, child: videoBox),
                Container(
                  width: 320,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    border: Border(left: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
                  ),
                  child: _buildSidebar(isDark, textMain, textSub),
                ),
              ],
            );
          }

          // [Mobile/hẹp — TỐI ƯU LẠI theo yêu cầu user] Thao tác nhanh đã dời ĐÈ LÊN video (xem
          // _videoBoxWithFullscreenButton) nên KHÔNG còn chiếm dòng riêng ở đây nữa — video được
          // Expanded LẤY HẾT phần trống còn lại (không cần chia sẻ với hàng nút cũ). Lưới nâng cao
          // giờ compact (icon tròn nhỏ, xem _buildAdvancedGridWrap) nên để NGUYÊN kích thước tự
          // nhiên (không Expanded) — chỉ chiếm đúng 1 dải mỏng, KHÔNG cưỡng ép giãn ra choán chỗ.
          // Playback/Sự kiện được tăng flex danh sách (4:7 thay vì 5:6 cũ) — nhường hẳn không gian
          // "bao la" cho danh sách như yêu cầu.
          return Column(
            children: [
              if (_tab == _DetailTab.live) ...[
                Expanded(child: videoBox),
                Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: _buildAdvancedGridWrap(isDark, textMain, textSub)),
              ] else if (_tab == _DetailTab.playback) ...[
                Expanded(flex: 4, child: videoBox),
                Expanded(flex: 7, child: _buildPlaybackBody(isDark, textMain, textSub)),
              ] else ...[
                Expanded(flex: 4, child: videoBox),
                Expanded(flex: 7, child: _buildEventsBody(isDark, textMain, textSub)),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab.index,
        selectedItemColor: _tkGreen,
        unselectedItemColor: textSub,
        onTap: (i) => _switchTab(_DetailTab.values[i]),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.videocam_rounded), label: 'Trực tiếp'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline_rounded), label: 'Xem lại'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_active_outlined), label: 'Sự kiện'),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_tab == _DetailTab.live) {
      if (_liveLoading) return const Center(child: CircularProgressIndicator(color: _tkGreen));
      if (_liveError != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 32),
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(_liveError!, style: const TextStyle(color: Colors.white54, fontSize: 12), textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadLive, child: const Text('Thử lại', style: TextStyle(color: _tkGreen, fontWeight: FontWeight.bold))),
          ]),
        );
      }
      return Video(controller: _controller, controls: NoVideoControls, fit: BoxFit.contain);
    }

    if (_tab == _DetailTab.playback) {
      if (_selectedRecord == null) {
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.video_library_outlined, color: Colors.white38, size: 32),
            SizedBox(height: 8),
            Text('Chọn 1 đoạn ghi bên dưới', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_clock_rounded, color: Colors.amber, size: 30),
          const SizedBox(height: 10),
          Text('${_selectedRecord!['begin_time'] ?? ''} → ${_selectedRecord!['end_time'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'Phát lại video ghi hình cần SDK gốc của Imou (đang trong quá trình tích hợp, chưa chạy ổn định). Bạn có thể xem đoạn này trực tiếp trong App Imou Life.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }

    // Sự kiện — ẢNH THẬT (khác Xem lại, không vướng giới hạn SDK gốc).
    if (_selectedEvent == null) {
      return const Center(child: Text('Chọn 1 sự kiện bên dưới để xem ảnh', style: TextStyle(color: Colors.white54, fontSize: 12)));
    }
    final pics = (_selectedEvent!['pic_urls'] as List?)?.cast<String>() ?? const [];
    final thumb = (_selectedEvent!['thumb_url'] ?? '').toString();
    final imgUrl = pics.isNotEmpty ? pics.first : thumb;
    if (imgUrl.isEmpty) return const Center(child: Text('Không có ảnh cho sự kiện này', style: TextStyle(color: Colors.white54)));
    return Image.network(imgUrl, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 32)));
  }

  // [SIDEBAR — PC/Tablet ngang, theo yêu cầu user] Cột phải cố định 320px chứa Thao tác nhanh +
  // Chức năng nâng cao (tab Trực tiếp) HOẶC danh sách Xem lại/Sự kiện — BỌC 1 LẦN DUY NHẤT trong
  // SingleChildScrollView ở NGOÀI CÙNG để tránh scrollable-lồng-scrollable (2 lớp cuộn độc lập
  // từng gây lỗi "RenderBox không đo được chiều cao" khi 1 scrollable không giới hạn nằm trong 1
  // scrollable khác) — vì vậy _buildAdvancedGridWrap() bên dưới KHÔNG tự bọc scroll riêng.
  Widget _buildSidebar(bool isDark, Color textMain, Color textSub) {
    if (_tab == _DetailTab.live) {
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(
          children: [
            _buildQuickActionsRow(textMain, textSub),
            const SizedBox(height: 16),
            Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey.shade200),
            const SizedBox(height: 16),
            _buildAdvancedGridWrap(isDark, textMain, textSub),
          ],
        ),
      );
    }
    if (_tab == _DetailTab.playback) return _buildPlaybackBody(isDark, textMain, textSub);
    return _buildEventsBody(isDark, textMain, textSub);
  }

  // [FIX — icon giãn toác ra 2 mép màn hình] Trước đây mỗi icon bọc Expanded trong 1 Row — Row
  // CHIA ĐỀU toàn bộ bề rộng khả dụng cho 4 Expanded, màn càng rộng (PC/sidebar) khoảng cách giữa
  // các icon càng giãn ra xa nhau trông rời rạc. Wrap KHÔNG chia đều theo bề rộng cha — mỗi icon
  // giữ kích thước tự nhiên/cố định rồi xếp SÁT NHAU quanh tâm (WrapAlignment.center), đúng yêu
  // cầu "gom gọn lại gần nhau ở giữa".
  Widget _buildQuickActionsRow(Color textMain, Color textSub) {
    final bool hasQuality = widget.entry.provider == CameraProviderType.imou; // RTSP chỉ 1 luồng
    Widget action(IconData icon, String label, VoidCallback onTap) => SizedBox(
          width: 72,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: textMain, size: 20),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: textSub)),
              ]),
            ),
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        action(Icons.camera_alt_outlined, 'Chụp ảnh', () => _showUnsupported('Chụp ảnh')),
        action(Icons.videocam_outlined, 'Quay video', () => _showUnsupported('Quay video')),
        action(Icons.mic_none_rounded, 'Đàm thoại', () => _showUnsupported('Đàm thoại 2 chiều')),
        action(
          hasQuality ? (_useHd ? Icons.hd_rounded : Icons.sd_rounded) : Icons.hd_rounded,
          hasQuality ? (_useHd ? 'HD' : 'SD') : 'Chất lượng',
          hasQuality ? _toggleQuality : () => _showUnsupported('Chọn chất lượng'),
        ),
      ],
    );
  }

  // [FIX — nút phình to trên màn ngang/PC] GridView.count(crossAxisCount: 3) CHIA ĐỀU chiều rộng
  // sẵn có cho đúng 3 cột — trên màn RỘNG (PC/tablet ngang), mỗi cột nghiễm nhiên giãn to theo,
  // nút vuông biến thành khối khổng lồ. Wrap KHÔNG chia cột theo tỷ lệ màn hình — mỗi nút giữ
  // ĐÚNG kích thước cố định (icon tròn 44px, khối rộng 60px) rồi tự xuống dòng khi hết chỗ, số
  // cột/hàng tự thay đổi theo bề rộng thật mà KHÔNG co giãn từng nút. KHÔNG tự bọc scroll ở đây
  // (xem _buildSidebar/call site mobile) — tránh scrollable lồng scrollable.
  // [Item thứ 4: `active` — CHỈ PTZ dùng, các nút còn lại luôn false] Nút PTZ tự sáng lên khi
  // panel đang mở (nền/viền/icon đổi màu _tkGreen) — thay cho việc phải mở dialog riêng để biết
  // trạng thái.
  Widget _buildAdvancedGridWrap(bool isDark, Color textMain, Color textSub) {
    final items = <(IconData, String, VoidCallback, bool)>[
      (Icons.control_camera_rounded, 'PTZ', widget.entry.hasPTZ ? _togglePtzPanel : () => _showUnsupported('PTZ'), _ptzPanelOpen),
      (Icons.push_pin_outlined, 'Địa điểm thường xuyên', () => _showUnsupported('Địa điểm thường xuyên'), false),
      (Icons.wb_incandescent_outlined, 'Đèn cảnh báo', () => _showUnsupported('Đèn cảnh báo'), false),
      (Icons.campaign_outlined, 'Răn đe chủ động', () => _showUnsupported('Răn đe chủ động'), false),
      (Icons.horizontal_rule_rounded, 'Cần gạt', () => _showUnsupported('Cần gạt'), false),
      (Icons.remove_red_eye_outlined, 'Mống mắt', () => _showUnsupported('Mống mắt'), false),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // [COMPACT — theo yêu cầu user] Đổi từ khối vuông bo góc 80x80 sang icon TRÒN 44px + chữ
        // 10px bên dưới — mỗi nút chỉ rộng 60px, spacing/runSpacing giảm còn 8 — cả dải chỉ còn 1
        // dải mỏng thay vì chiếm cả khối lớn như Card, nhường không gian cho video/danh sách.
        Wrap(
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 8,
          children: [
            for (final it in items)
              SizedBox(
                width: 60,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: it.$3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: it.$4 ? _tkGreen.withValues(alpha: 0.15) : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
                          border: it.$4 ? Border.all(color: _tkGreen, width: 1.5) : null,
                        ),
                        child: Icon(it.$1, color: it.$4 ? _tkGreen : textMain, size: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(it.$2, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, height: 1.1, color: it.$4 ? _tkGreen : textSub)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        // [PANEL PTZ NỘI TUYẾN — theo yêu cầu user] Nằm gọn vào PHẦN TRỐNG có sẵn ngay bên dưới
        // lưới nút, KHÔNG che icon nào — khác hẳn showModalBottomSheet cũ phủ lên toàn màn hình.
        if (_ptzPanelOpen && widget.entry.hasPTZ) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16)),
            child: Center(child: ImouPtzPad(homeId: widget.entry.homeId, cameraId: widget.entry.imouCamera!.id)),
          ),
        ],
      ],
    );
  }

  Widget _thumbPlaceholder() => Container(width: 64, height: 48, color: Colors.black26, child: const Icon(Icons.videocam_rounded, color: Colors.white54, size: 20));

  Widget _buildPlaybackBody(bool isDark, Color textMain, Color textSub) {
    if (!widget.entry.hasRecords) {
      return Center(child: Text('Camera này chưa hỗ trợ Xem lại', style: TextStyle(color: textSub)));
    }
    return Column(
      children: [
        // [FIX — RIGHT OVERFLOWED BY 39 PIXELS] Row không co giãn/rớt dòng khi 2 ChoiceChip + ngày
        // + icon lịch cộng lại rộng hơn màn hình (Spacer chỉ lấp khoảng TRỐNG còn lại, không giúp
        // gì khi tổng các phần TỬ CỐ ĐỊNH đã vượt bề ngang sẵn có). Wrap tự xuống dòng gọn gàng
        // thay vì tràn hoặc phải vuốt ngang để thấy nút chọn ngày (dễ bị bỏ sót hơn Wrap).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(label: const Text('Thẻ nhớ SD'), selected: _playbackSource == 'local', onSelected: (_) { setState(() => _playbackSource = 'local'); _loadRecords(); }),
              ChoiceChip(label: const Text('Cloud Storage'), selected: _playbackSource == 'cloud', onSelected: (_) { setState(() => _playbackSource = 'cloud'); _loadRecords(); }),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _pickPlaybackDay,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_today_rounded, size: 16, color: textSub),
                    const SizedBox(width: 6),
                    Text('${_playbackDay.day}/${_playbackDay.month}/${_playbackDay.year}', style: TextStyle(color: textSub, fontSize: 12)),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _recordsLoading
              ? const Center(child: CircularProgressIndicator(color: _tkGreen))
              : _recordsError != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_recordsError!, style: TextStyle(color: textSub), textAlign: TextAlign.center)))
                  : _records.isEmpty
                      ? Center(child: Text('Không có đoạn ghi nào trong ngày này', style: TextStyle(color: textSub)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _records.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final r = _records[index];
                            final bool selected = identical(r, _selectedRecord);
                            final String thumb = (r['thumb_url'] ?? '').toString();
                            return InkWell(
                              onTap: () => setState(() => _selectedRecord = r),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: selected ? Border.all(color: _tkGreen, width: 1.5) : null,
                                ),
                                child: Row(children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(8), child: thumb.isNotEmpty ? Image.network(thumb, width: 64, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => _thumbPlaceholder()) : _thumbPlaceholder()),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('${r['begin_time'] ?? ''}', style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text('đến ${r['end_time'] ?? ''}', style: TextStyle(color: textSub, fontSize: 11)),
                                    ]),
                                  ),
                                  Icon(Icons.play_circle_outline_rounded, color: textSub),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildEventsBody(bool isDark, Color textMain, Color textSub) {
    if (!widget.entry.hasEvents) {
      return Center(child: Text('Camera này chưa hỗ trợ Sự kiện', style: TextStyle(color: textSub)));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(Icons.event_rounded, size: 16, color: textSub),
            const SizedBox(width: 6),
            Text('${_eventsDay.day}/${_eventsDay.month}/${_eventsDay.year}', style: TextStyle(color: textSub, fontSize: 13)),
            const Spacer(),
            IconButton(icon: Icon(Icons.calendar_today_rounded, size: 18, color: textSub), onPressed: _pickEventsDay),
          ]),
        ),
        Expanded(
          child: _eventsLoading
              ? const Center(child: CircularProgressIndicator(color: _tkGreen))
              : _eventsError != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_eventsError!, style: TextStyle(color: textSub), textAlign: TextAlign.center)))
                  : _events.isEmpty
                      ? Center(child: Text('Không có sự kiện nào trong ngày này', style: TextStyle(color: textSub)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _events.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final e = _events[index];
                            final bool selected = identical(e, _selectedEvent);
                            final String thumb = (e['thumb_url'] ?? '').toString();
                            final String localDate = (e['local_date'] ?? '').toString();
                            final int type = (e['type'] as num?)?.toInt() ?? -1;
                            return InkWell(
                              onTap: () => setState(() => _selectedEvent = e),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: selected ? Border.all(color: _tkGreen, width: 1.5) : null,
                                ),
                                child: Row(children: [
                                  ClipRRect(borderRadius: BorderRadius.circular(8), child: thumb.isNotEmpty ? Image.network(thumb, width: 64, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => _thumbPlaceholder()) : _thumbPlaceholder()),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(_alarmTypeLabel(type), style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600)),
                                      Text(localDate, style: TextStyle(color: textSub, fontSize: 11)),
                                    ]),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: textSub),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
