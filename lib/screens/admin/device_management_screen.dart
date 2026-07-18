import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../localization/app_translations.dart';

/// DeviceManagementScreen — "Quản trị Thiết bị" toàn cục (chỉ SUPER_USER).
/// PaginatedDataTable tải TỪNG TRANG từ Backend (GET /api/admin/devices?search=&page=&page_size=)
/// thay vì kéo hết về máy rồi lọc tay — đúng yêu cầu "tải mượt mà hàng vạn thiết bị". Thanh tìm
/// kiếm là Universal Search: Backend tự đối chiếu CẢ 4 trường (tên thiết bị/tên nhà/email chủ/MAC)
/// trong CÙNG MỘT query, không cần dropdown chọn field.
class DeviceManagementScreen extends StatefulWidget {
  /// [embedded]=true khi nhúng làm tab body của Dashboard (giữ sidebar/header, KHÔNG AppBar).
  /// [embedded]=false khi Navigator.push riêng trên Mobile — cùng quy ước với AdminSystemScreen.
  final bool embedded;
  const DeviceManagementScreen({super.key, this.embedded = false});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  static const Color tkGreen = Color(0xFF00A651);
  static const int _pageSize = 15;

  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  String _pendingSearch = '';

  late _AdminDeviceDataSource _dataSource;
  final GlobalKey<PaginatedDataTableState> _tableKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _dataSource = _buildDataSource('');
  }

  _AdminDeviceDataSource _buildDataSource(String search) {
    return _AdminDeviceDataSource(
      api: _api,
      search: search,
      pageSize: _pageSize,
      onError: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppTranslations.of(context, listen: false).text('device_admin_load_error')),
          backgroundColor: Colors.redAccent,
        ));
      },
      onForceUnbind: _confirmForceUnbind,
    )..fetchInitial();
  }

  void _runSearch() {
    final String q = _pendingSearch.trim();
    setState(() {
      _dataSource.dispose();
      _dataSource = _buildDataSource(q);
      // Đưa PaginatedDataTable về trang đầu — kết quả tìm kiếm mới không liên quan gì tới trang
      // đang xem dở của bộ lọc cũ.
      _tableKey.currentState?.pageTo(0);
    });
  }

  Future<void> _confirmForceUnbind(AdminDeviceRow row) async {
    final t = AppTranslations.of(context);
    // Cùng lưới an toàn chuỗi rỗng như bảng danh sách — String không nullable nên không thể
    // "null crash", nhưng vẫn tránh hiện dòng trống trơn khó hiểu trong Dialog xác nhận.
    final String displayName = row.name.trim().isEmpty ? '⚠️ Chưa đặt tên' : row.name;
    final String displayOwner = row.ownerEmail.trim().isEmpty ? '⚠️ TÀNG HÌNH — không xác định được chủ' : row.ownerEmail;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.text('force_unbind_confirm_title')),
        content: Text('${t.text('force_unbind_confirm_body')}\n\n$displayName (${row.mac})\n${t.text('device_admin_col_owner')}: $displayOwner'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(t.text('cancel'))),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(t.text('force_unbind_action'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final bool success = await _api.forceUnbindDevice(row.mac);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? t.text('force_unbind_success') : t.text('force_unbind_error')),
      backgroundColor: success ? tkGreen : Colors.redAccent,
    ));
    if (success) {
      setState(() {
        _dataSource.dispose();
        _dataSource = _buildDataSource(_pendingSearch.trim());
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dataSource.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0B1120);
    final Color textSub = isDark ? Colors.white70 : Colors.black54;
    final t = AppTranslations.of(context);

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.dns_rounded, color: tkGreen, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t.text('device_admin_title'),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textMain, fontSize: 22, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: AppTextField(
            controller: _searchController,
            hintText: t.text('device_admin_search_hint'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _runSearch),
            onChanged: (v) => _pendingSearch = v,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: PaginatedDataTable(
              key: _tableKey,
              header: Text(t.text('device_admin_table_header'), style: TextStyle(color: textMain, fontSize: 16, fontWeight: FontWeight.w600)),
              headingRowColor: WidgetStateProperty.all(isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03)),
              columnSpacing: 20,
              rowsPerPage: _pageSize,
              showFirstLastButtons: true,
              columns: [
                DataColumn(label: Text(t.text('device_admin_col_name'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text(t.text('device_admin_col_mac'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text(t.text('device_admin_col_home'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text(t.text('device_admin_col_owner'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text(t.text('device_admin_col_status'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 12))),
                DataColumn(label: Text(t.text('device_admin_col_action'), style: TextStyle(color: textSub, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
              source: _dataSource,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );

    if (widget.embedded) return content;

    return AppScaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFE8EEF2),
      appBar: AppBar(
        title: Text(t.text('device_admin_title')),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: SafeArea(child: content),
    );
  }
}

/// Nguồn dữ liệu SERVER-SIDE cho PaginatedDataTable: [getRow] chỉ trả về những dòng ĐÃ CACHE
/// (từ trang vừa tải); gặp index chưa có -> tự kích hoạt tải trang chứa index đó rồi
/// notifyListeners() khi xong, PaginatedDataTable tự vẽ lại. Nhờ vậy hàng vạn thiết bị vẫn
/// mượt vì KHÔNG BAO GIỜ tải quá 1 trang (pageSize dòng) cùng lúc.
class _AdminDeviceDataSource extends DataTableSource {
  final ApiService api;
  final String search;
  final int pageSize;
  final VoidCallback onError;
  final void Function(AdminDeviceRow row) onForceUnbind;

  _AdminDeviceDataSource({
    required this.api,
    required this.search,
    required this.pageSize,
    required this.onError,
    required this.onForceUnbind,
  });

  final Map<int, AdminDeviceRow> _cache = {};
  final Set<int> _loadingPages = {};
  int _totalRows = 0;
  bool _loadedOnce = false;
  bool _disposed = false;

  void fetchInitial() => _fetchPage(1);

  Future<void> _fetchPage(int page) async {
    if (_loadingPages.contains(page)) return;
    _loadingPages.add(page);
    final result = await api.listAllDevicesAdmin(search: search, page: page, pageSize: pageSize);
    _loadingPages.remove(page);
    if (_disposed) return;
    if (result == null) {
      onError();
      return;
    }
    _totalRows = result.total;
    for (int i = 0; i < result.rows.length; i++) {
      _cache[(page - 1) * pageSize + i] = result.rows[i];
    }
    _loadedOnce = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  DataRow? getRow(int index) {
    final AdminDeviceRow? row = _cache[index];
    if (row == null) {
      // Chưa có trong cache -> âm thầm kích hoạt tải trang chứa index này, KHÔNG chặn UI —
      // notifyListeners() (trong _fetchPage) sẽ tự vẽ lại đúng dòng này khi dữ liệu về.
      final int page = (index ~/ pageSize) + 1;
      _fetchPage(page);
      return null;
    }
    // [BỊT LỖI VỠ UI — dữ liệu thiết bị ma] AdminDeviceRow.name/homeName/ownerEmail đều là String
    // KHÔNG NULLABLE (fromJson đã ?? '' sẵn) nên KHÔNG THỂ crash "Text(null)" theo đúng nghĩa
    // đen — Dart sound null-safety chặn việc này ngay lúc biên dịch, không phải lúc chạy. Vấn đề
    // THẬT có thể xảy ra là chuỗi RỖNG (không phải null) hiển thị trống trơn gây khó hiểu, HOẶC
    // chuỗi placeholder dài ("⚠️ TÀNG HÌNH — không xác định được chủ") tràn khỏi bề rộng cột hẹp
    // của DataTable gây cảnh báo RenderFlex overflow (nhìn giống "vỡ UI" dù không phải crash
    // thật). Vá cả 2: fallback rõ ràng cho chuỗi rỗng + overflow: ellipsis chống tràn cột.
    String orFallback(String v, String fallback) => v.trim().isEmpty ? fallback : v;
    Widget cellText(String value, {double maxWidth = 180}) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 1),
        );

    return DataRow.byIndex(
      index: index,
      cells: [
        DataCell(cellText(orFallback(row.name, '⚠️ Chưa đặt tên'))),
        DataCell(SelectableText(orFallback(row.mac, '⚠️ MAC lỗi'))),
        DataCell(cellText(orFallback(
          row.homeName.isEmpty ? row.homeId : row.homeName,
          '⚠️ LỖI DỮ LIỆU (home_id hỏng/rỗng)',
        ))),
        DataCell(cellText(orFallback(row.ownerEmail, '⚠️ TÀNG HÌNH — không xác định được chủ'), maxWidth: 220)),
        DataCell(Icon(
          row.online ? Icons.circle : Icons.circle_outlined,
          color: row.online ? const Color(0xFF00A651) : Colors.grey,
          size: 12,
        )),
        DataCell(IconButton(
          icon: const Icon(Icons.link_off_rounded, color: Colors.redAccent),
          tooltip: 'Force Unbind',
          onPressed: () => onForceUnbind(row),
        )),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => _loadedOnce ? _totalRows : 0;

  @override
  int get selectedRowCount => 0;
}
