import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:file_picker/file_picker.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../localization/app_translations.dart';

/// AdminSystemScreen — Bảng điều khiển Quản trị Hệ thống (chỉ SUPER_USER).
/// Tab 1: Cấp phép thiết bị (Whitelist) + công tắc Chế độ nghiêm ngặt.
/// Tab 2: Quản lý kho Firmware OTA (upload .bin + danh sách + xóa).
class AdminSystemScreen extends StatelessWidget {
  /// [embedded]=true khi NHÚNG làm tab body của Dashboard (giữ sidebar/header, KHÔNG AppBar).
  /// [embedded]=false (mặc định) khi Navigator.push riêng trên Mobile: PHẢI bọc Scaffold +
  /// AppBar (nút Back) + SafeArea — trước đây push widget trần (không Scaffold) làm vỡ layout.
  final bool embedded;
  const AdminSystemScreen({super.key, this.embedded = false});

  // Danh mục loại thiết bị dùng chung cho cả Whitelist lẫn Upload firmware.
  // label hiển thị cho người, value là fw_type khớp firmware của thiết bị.
  static const List<Map<String, String>> deviceTypes = [
    {'label': 'Hub trung tâm', 'value': 'SMART_HUB_V38'},
    {'label': 'Công tắc', 'value': 'SMART_SWITCH'},
    {'label': 'Công tắc 4 kênh', 'value': 'SMART_SWITCH_4CH'},
    {'label': 'Quạt', 'value': 'SMART_FAN_CTRL'},
    {'label': 'Cảm biến', 'value': 'SMART_SENSOR'},
  ];

  static const Color tkGreen = Color(0xFF00A651);

  @override
  Widget build(BuildContext context) {
    // [NHÚNG VÀO DASHBOARD] Đã GỠ Scaffold + AppBar (nút Back) — màn này nay là một "tab body"
    // bên trong DashboardScreen (đổi qua _selectedIndex), không còn đè lên sidebar/header.
    // Thay AppBar bằng một hàng tiêu đề đơn giản + TabBar; TabBarView bọc Expanded để co giãn
    // đầy chiều cao trên cả PC lẫn Mobile. (Material ancestor do Scaffold của Dashboard cung cấp.)
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0B1120);
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final tr = AppTranslations.of(context);

    final Widget content = DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tiêu đề trong body CHỈ khi nhúng (đứng riêng đã có AppBar, tránh double tiêu đề)
          if (embedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.admin_panel_settings, color: tkGreen, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr.text('system_admin'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          TabBar(
            indicatorColor: tkGreen,
            labelColor: tkGreen,
            unselectedLabelColor: textSub,
            tabs: [
              Tab(icon: const Icon(Icons.verified_user_outlined), text: tr.text('provision_device_tab')),
              Tab(icon: const Icon(Icons.system_update_alt), text: tr.text('ota_update_tab')),
            ],
          ),
          // Expanded -> TabBarView chiếm trọn chiều cao còn lại (không tràn/không co rúm)
          const Expanded(
            child: TabBarView(
              children: [
                _WhitelistTab(),
                _FirmwareTab(),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return content;

    // Đứng riêng (Mobile push): Scaffold + AppBar Back + SafeArea đầy đủ
    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: Text(tr.text('system_admin')),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: SafeArea(child: content),
    );
  }
}

// ============================================================================
// TAB 1: WHITELIST + STRICT MODE
// ============================================================================
class _WhitelistTab extends StatefulWidget {
  const _WhitelistTab();

  @override
  State<_WhitelistTab> createState() => _WhitelistTabState();
}

class _WhitelistTabState extends State<_WhitelistTab> {
  final AdminService _api = AdminService();
  final TextEditingController _snCtrl = TextEditingController();
  // [DYNAMIC INPUT] Đồng nhất với tab OTA: chọn gợi ý HAY gõ tay tự do, giá trị đọc từ controller.
  final TextEditingController _deviceTypeCtrl = TextEditingController();
  List<String> _deviceTypes = [];

  bool _strictMode = false;
  bool _loading = true;
  bool _adding = false;
  List<Map<String, dynamic>> _list = [];

  static const Color tkGreen = Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadDeviceTypes();
  }

  @override
  void dispose() {
    _snCtrl.dispose();
    _deviceTypeCtrl.dispose();
    super.dispose();
  }

  // Nạp danh sách loại thiết bị gợi ý (động) từ Backend; điền sẵn phần tử đầu cho tiện.
  Future<void> _loadDeviceTypes() async {
    final types = await _api.getDeviceTypes();
    if (!mounted) return;
    setState(() {
      _deviceTypes = types;
      if (_deviceTypeCtrl.text.isEmpty && types.isNotEmpty) {
        _deviceTypeCtrl.text = types.first;
      }
    });
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final strict = await _api.getStrictMode();
    final list = await _api.getWhitelist();
    if (!mounted) return;
    setState(() {
      _strictMode = strict;
      _list = list;
      _loading = false;
    });
  }

  Future<void> _toggleStrict(bool val) async {
    setState(() => _strictMode = val); // optimistic
    final ok = await _api.setStrictMode(val);
    if (!mounted) return;
    if (!ok) {
      setState(() => _strictMode = !val); // revert khi lỗi
      _snack('Không thể cập nhật chế độ bảo mật', isError: true);
    }
  }

  Future<void> _add() async {
    final sn = _snCtrl.text.trim().toUpperCase().replaceAll(':', '');
    if (sn.isEmpty) {
      _snack('Vui lòng nhập SN/MAC', isError: true);
      return;
    }
    // [DYNAMIC INPUT] Loại thiết bị lấy từ controller — chọn gợi ý HAY gõ tay đều được.
    final deviceType = _deviceTypeCtrl.text.trim();
    if (deviceType.isEmpty) {
      // Gọi từ nút Thêm (tap handler) -> listen: false, tránh "liệt nút".
      _snack(AppTranslations.of(context, listen: false).text('pick_device_type_error'), isError: true);
      return;
    }
    setState(() => _adding = true);
    final err = await _api.addWhitelist(sn, deviceType);
    if (!mounted) return;
    setState(() => _adding = false);
    if (err == null) {
      _snCtrl.clear();
      _snack('Đã cấp phép thiết bị $sn');
      _loadAll();
    } else {
      _snack(err, isError: true);
    }
  }

  Future<void> _delete(String sn) async {
    // [SỬA LỖI LIỆT NÚT] Ghi chú cũ ở đây SAI: "gọi trước await là an toàn" — thực ra
    // context.watch() bị assert bằng cờ TOÀN CỤC context.owner!.debugBuilding, cờ này LUÔN
    // false khi hàm này chạy (được gọi từ tap handler), bất kể có await hay chưa. Phải
    // listen: false — không liên quan gì đến vị trí trước/sau await.
    final failedText = AppTranslations.of(context, listen: false).text('delete_failed');
    final ok = await _api.deleteWhitelist(sn);
    if (!mounted) return;
    if (ok) {
      _snack('Đã thu hồi cấp phép $sn');
      _loadAll();
    } else {
      _snack(failedText, isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : tkGreen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0B1120);
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final tr = AppTranslations.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator(color: tkGreen));

    return RefreshIndicator(
      color: tkGreen,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Công tắc Strict Mode ---
          Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(_strictMode ? Icons.shield : Icons.shield_outlined,
                    color: _strictMode ? tkGreen : textSub, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr.text('strict_mode_title'),
                          style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(tr.text('strict_mode_desc'),
                          style: TextStyle(color: textSub, fontSize: 12)),
                    ],
                  ),
                ),
                Switch(value: _strictMode, activeThumbColor: tkGreen, onChanged: _toggleStrict),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Form thêm ---
          Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('add_whitelist_device_title'),
                    style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                // [FORM SWEEP — GIỮ NGUYÊN TextField] Cần textCapitalization.characters (tự
                // viết HOA khi gõ MAC) — AppTextField chưa hỗ trợ tham số này, ép chuyển sẽ
                // mất tính năng tự-viết-hoa. Để nguyên.
                TextField(
                  controller: _snCtrl,
                  style: TextStyle(color: textMain),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: tr.text('sn_mac_label'),
                    labelStyle: TextStyle(color: textSub),
                    prefixIcon: Icon(Icons.qr_code_2, color: textSub),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                // [DYNAMIC INPUT] Đồng nhất tab OTA: chọn loại đã có (động từ API) HOẶC gõ tay tự do.
                DropdownMenu<String>(
                  controller: _deviceTypeCtrl,
                  requestFocusOnTap: true,
                  enableFilter: true,
                  expandedInsets: EdgeInsets.zero,
                  menuHeight: 260,
                  label: Text(tr.text('device_type_label')),
                  textStyle: TextStyle(color: textMain),
                  dropdownMenuEntries: _deviceTypes
                      .map((t) => DropdownMenuEntry<String>(value: t, label: t))
                      .toList(),
                  onSelected: (v) {
                    if (v != null) _deviceTypeCtrl.text = v;
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tkGreen, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _adding
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.add),
                    label: Text(_adding ? tr.text('adding_ellipsis') : tr.text('add_to_list')),
                    onPressed: _adding ? null : _add,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Danh sách ---
          // [FIX iOS] Ép cứng fontSize + height: không để Text kế thừa DefaultTextStyle khổng lồ.
          Text('${tr.text('provisioned_count_prefix')}${_list.length})',
              style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 16, height: 1.3, letterSpacing: 1)),
          const SizedBox(height: 8),
          if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(tr.text('no_whitelist_devices'), style: TextStyle(color: textSub))),
            )
          else
            ..._list.map((e) {
              final sn = (e['sn_mac'] ?? '').toString();
              final type = (e['device_type'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.15),
                      child: const Icon(Icons.memory, color: tkGreen)),
                  title: Text(sn, style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
                  subtitle: Text(type, style: TextStyle(color: textSub, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _delete(sn),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 2: FIRMWARE OTA
// ============================================================================
class _FirmwareTab extends StatefulWidget {
  const _FirmwareTab();

  @override
  State<_FirmwareTab> createState() => _FirmwareTabState();
}

class _FirmwareTabState extends State<_FirmwareTab> {
  final AdminService _api = AdminService();
  final TextEditingController _versionCtrl = TextEditingController();
  final TextEditingController _changelogCtrl = TextEditingController();
  // [DYNAMIC INPUT] controller giữ giá trị loại thiết bị — dù CHỌN từ gợi ý hay GÕ tay tự do,
  // giá trị cuối cùng đều đọc từ controller này rồi truyền vào API upload.
  final TextEditingController _deviceTypeCtrl = TextEditingController();
  List<String> _deviceTypes = []; // danh sách gợi ý lấy động từ Backend

  PlatformFile? _pickedFile;
  bool _loading = true;
  bool _uploading = false;
  List<Map<String, dynamic>> _list = [];

  static const Color tkGreen = Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    _loadList();
    _loadDeviceTypes();
  }

  @override
  void dispose() {
    _versionCtrl.dispose();
    _changelogCtrl.dispose();
    _deviceTypeCtrl.dispose();
    super.dispose();
  }

  // Nạp danh sách loại thiết bị gợi ý (động) từ Backend; mặc định điền sẵn phần tử đầu.
  Future<void> _loadDeviceTypes() async {
    final types = await _api.getDeviceTypes();
    if (!mounted) return;
    setState(() {
      _deviceTypes = types;
      if (_deviceTypeCtrl.text.isEmpty && types.isNotEmpty) {
        _deviceTypeCtrl.text = types.first;
      }
    });
  }

  Future<void> _loadList() async {
    setState(() => _loading = true);
    final list = await _api.getFirmwareList();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
        withData: true, // lấy bytes cho nền web/không có đường dẫn
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFile = result.files.single);
      }
    } catch (e) {
      _snack('Không chọn được file: $e', isError: true);
    }
  }

  Future<void> _upload() async {
    // [SỬA LỖI LIỆT NÚT] Gọi từ tap handler -> listen: false (xem giải thích ở
    // _WhitelistTabState._delete()).
    final tr = AppTranslations.of(context, listen: false);
    if (_pickedFile == null) {
      _snack(tr.text('pick_bin_file_error'), isError: true);
      return;
    }
    final version = _versionCtrl.text.trim();
    if (version.isEmpty) {
      _snack(tr.text('enter_version_error'), isError: true);
      return;
    }
    // [DYNAMIC INPUT] Giá trị cuối cùng lấy từ controller — chọn gợi ý HAY gõ tay đều được.
    final deviceType = _deviceTypeCtrl.text.trim();
    if (deviceType.isEmpty) {
      _snack(tr.text('pick_device_type_error'), isError: true);
      return;
    }
    final uploadSuccessText = tr.text('upload_success');
    setState(() => _uploading = true);
    final err = await _api.uploadFirmware(
      deviceType: deviceType,
      version: version,
      changelog: _changelogCtrl.text.trim(),
      filePath: _pickedFile!.path,
      fileBytes: _pickedFile!.bytes,
      fileName: _pickedFile!.name,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err == null) {
      _snack(uploadSuccessText);
      _versionCtrl.clear();
      _changelogCtrl.clear();
      setState(() => _pickedFile = null);
      _loadList();
    } else {
      _snack(err, isError: true);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> fw) async {
    // [SỬA LỖI LIỆT NÚT] Gọi từ tap handler -> listen: false (xem giải thích ở
    // _WhitelistTabState._delete()).
    final tr = AppTranslations.of(context, listen: false);
    final failedText = tr.text('delete_failed');
    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog().
    final confirm = await showAppDialog<bool>(
      context: context,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr.text('confirm_delete_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // [GIỮ NGUYÊN BIẾN ĐỘNG] device_type/version/file_name đọc từ API — chỉ câu hỏi đầu dịch.
            Text('${tr.text('confirm_delete_file_prefix')}${fw['device_type']} v${fw['version']}\n${fw['file_name'] ?? ''}'),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr.text('delete'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    final ok = await _api.deleteFirmware((fw['id'] ?? '').toString());
    if (!mounted) return;
    if (ok) {
      _snack('Đã xóa file khỏi server');
      _loadList();
    } else {
      _snack(failedText, isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : tkGreen,
    ));
  }

  // [OTA ZERO-TRUST] Private Key KHÔNG BAO GIỜ rời Server — chỉ Public Key (không phải bí
  // mật) mới lấy ra được, để dán vào mảng OTA_PUBLIC_KEY[65] (PROGMEM) trong C++.
  bool _fetchingKey = false;

  Future<void> _showPublicKeyDialog() async {
    // [SỬA LỖI LIỆT NÚT] Gọi từ tap handler -> listen: false (xem giải thích ở
    // _WhitelistTabState._delete()).
    final cantGetKeyText = AppTranslations.of(context, listen: false).text('cant_get_pubkey_error');
    setState(() => _fetchingKey = true);
    final (hexKey, err) = await _api.getOtaPublicKey();
    if (!mounted) return;
    setState(() => _fetchingKey = false);

    if (err != null || hexKey == null) {
      _snack(err ?? cantGetKeyText, isError: true);
      return;
    }

    if (!mounted) return;
    // [GLASS THEME] AlertDialog (title/content/actions) ĐÃ THAY bằng showAppDialog() — giữ
    // Builder để context bên trong VẪN LÀ context riêng của dialog (có await Clipboard rồi
    // kiểm ctx.mounted để biết dialog đã tự đóng chưa).
    await showAppDialog<void>(
      context: context,
      child: Builder(
        builder: (ctx) {
          final bool isDark = Theme.of(ctx).brightness == Brightness.dark;
          final Color textMain = isDark ? Colors.white : const Color(0xFF0B1120);
          final Color textSub = isDark ? Colors.white70 : Colors.black54;
          final tr = AppTranslations.of(ctx);
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('public_key_dialog_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    hexKey,
                    style: TextStyle(color: textMain, fontFamily: 'monospace', fontSize: 12.5, height: 1.4),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: textSub),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tr.text('public_key_help_text'),
                        style: TextStyle(color: textSub, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.text('close'))),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: tkGreen, foregroundColor: Colors.white),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(tr.text('copy_clipboard_btn')),
                      onPressed: () async {
                        // [AN TOÀN PROVIDER] Dịch TRƯỚC await Clipboard — xem giải thích ở
                        // _WhitelistTabState._delete().
                        final copiedText = tr.text('copied_clipboard');
                        await Clipboard.setData(ClipboardData(text: hexKey));
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        _snack(copiedText);
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtSize(dynamic bytes) {
    final n = (bytes is num) ? bytes.toDouble() : double.tryParse('$bytes') ?? 0;
    if (n <= 0) return '';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0B1120);
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final tr = AppTranslations.of(context);

    return RefreshIndicator(
      color: tkGreen,
      onRefresh: _loadList,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Form upload ---
          Container(
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr.text('upload_new_firmware_title'),
                          style: TextStyle(color: textMain, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                    // [OTA ZERO-TRUST] Public Key không phải bí mật -> lấy tự do để nhúng vào
                    // C++ firmware. Private Key KHÔNG có đường nào lấy ra qua UI.
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: tkGreen, padding: const EdgeInsets.symmetric(horizontal: 8)),
                      icon: _fetchingKey
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen))
                          : const Icon(Icons.vpn_key_outlined, size: 16),
                      label: Text(tr.text('get_public_key_btn'), style: const TextStyle(fontSize: 12)),
                      onPressed: _fetchingKey ? null : _showPublicKeyDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // [DYNAMIC INPUT] DropdownMenu MỞ: bấm mũi tên chọn loại đã có (lấy động từ API)
                // HOẶC gõ tay tự do loại mới (smart_fan, curtain_v2...). Giá trị dùng = text controller.
                DropdownMenu<String>(
                  controller: _deviceTypeCtrl,
                  requestFocusOnTap: true,               // cho phép gõ tay
                  enableFilter: true,                    // gõ tới đâu lọc gợi ý tới đó
                  expandedInsets: EdgeInsets.zero,       // giãn full chiều rộng cột
                  menuHeight: 260,
                  label: Text(tr.text('device_type_label')),
                  textStyle: TextStyle(color: textMain),
                  dropdownMenuEntries: _deviceTypes
                      .map((t) => DropdownMenuEntry<String>(value: t, label: t))
                      .toList(),
                  onSelected: (v) {
                    if (v != null) _deviceTypeCtrl.text = v; // đồng bộ khi chọn từ gợi ý
                  },
                ),
                const SizedBox(height: 12),
                // [FORM SWEEP] 2× TextField -> AppTextField.
                AppTextField(
                  controller: _versionCtrl,
                  labelText: tr.text('version_hint'),
                  prefixIcon: Icon(Icons.tag, color: textSub),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _changelogCtrl,
                  maxLines: 3,
                  labelText: tr.text('changelog_hint'),
                ),
                const SizedBox(height: 12),
                // Nút chọn file
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tkGreen,
                    side: const BorderSide(color: tkGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.attach_file),
                  label: Text(_pickedFile == null ? tr.text('pick_bin_file_btn') : _pickedFile!.name),
                  onPressed: _uploading ? null : _pickFile,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tkGreen, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _uploading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload_outlined),
                    label: Text(_uploading ? tr.text('uploading_ellipsis') : tr.text('upload_to_server_btn')),
                    onPressed: _uploading ? null : _upload,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // --- Danh sách firmware ---
          // [FIX iOS] Ép cứng fontSize + height: không để Text kế thừa DefaultTextStyle khổng lồ.
          Text(tr.text('firmware_on_server'),
              style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 16, height: 1.3, letterSpacing: 1)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: tkGreen)))
          else if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(tr.text('firmware_repo_empty'), style: TextStyle(color: textSub))),
            )
          else
            ..._list.map((fw) {
              final changelog = (fw['changelog'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: tkGreen.withValues(alpha: 0.15),
                      child: const Icon(Icons.developer_board, color: tkGreen)),
                  title: Text('${fw['device_type']}  ·  v${fw['version']}',
                      style: TextStyle(color: textMain, fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (changelog.isNotEmpty)
                        Text(changelog, style: TextStyle(color: textSub, fontSize: 12)),
                      Text('${_fmtSize(fw['size_bytes'])}  ·  ${(fw['upload_date'] ?? '').toString().split('T').first}',
                          style: TextStyle(color: textSub, fontSize: 11)),
                    ],
                  ),
                  isThreeLine: changelog.isNotEmpty,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: () => _confirmDelete(fw),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
