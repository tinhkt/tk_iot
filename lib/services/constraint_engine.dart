/// ============================================================================
/// ⚖️ UNIVERSAL VALIDATION ENGINE — METADATA-DRIVEN CONSTRAINTS
/// ============================================================================
/// Engine xử lý BẤT KỲ bài toán lựa chọn nào (relay vào nhóm, action vào ngữ cảnh,
/// lịch hẹn theo giờ...) dựa trên BỘ THUỘC TÍNH KHAI BÁO (Capabilities) — không một
/// dòng if-else nào theo tên loại thiết bị/đối tượng.
///
/// Kiến trúc:
///   SelectionItem  : một "mục" trung tính — chỉ có key (định danh) + scopeKey (phạm vi).
///                    Relay -> key "MAC|endpoint", scope "MAC". Action -> scope "mac|ep".
///                    Lịch hẹn -> scope "HH:MM". Engine KHÔNG biết mục là gì.
///   Capabilities   : bộ quy tắc khai báo (multi_selection / exclusive_group /
///                    allow_multi_endpoint / max_per_scope / extraRules).
///   ValidationEngine.validate(caps, current, attempt)
///                  -> ValidationResult {allowed, operations[uncheck...], reason}.
///   CapabilityRegistry : bảng entityType -> Capabilities. THÊM KỊCH BẢN MỚI = thêm
///                    một entry (hoặc register() lúc runtime) — KHÔNG sửa engine/UI.
///
/// Bản chiếu 1:1 của engine này nằm bên Backend Go (internal/api/constraint_engine.go)
/// — server cưỡng chế lại lần cuối nên client lách cũng không ghi bậy được.
library;

/// Một mục trong bộ chọn — trung tính với nghiệp vụ.
class SelectionItem {
  /// Định danh DUY NHẤT của mục trong phiên chọn (trùng key = trùng mục).
  final String key;

  /// Phạm vi xét quy tắc: các mục cùng scopeKey bị ràng buộc với nhau
  /// (MAC thiết bị, endpoint đích của action, giờ HH:MM của lịch...).
  final String scopeKey;
  const SelectionItem({required this.key, required this.scopeKey});
}

/// Hành động dọn dẹp engine RA LỆNH thực hiện khi cho phép chọn.
class SelectionOp {
  static const String uncheck = 'uncheck';
  final String op;
  final String targetKey; // key của mục phải xử lý
  const SelectionOp(this.op, this.targetKey);
}

/// Phán quyết của engine.
class ValidationResult {
  final bool allowed;
  final List<SelectionOp> operations; // dọn dẹp bắt buộc trước khi thêm (vd uncheck)
  final String? reason; // câu báo lỗi khi từ chối
  const ValidationResult.allowedWith([this.operations = const []])
      : allowed = true,
        reason = null;
  const ValidationResult.denied(this.reason)
      : allowed = false,
        operations = const [];
}

/// Luật tùy biến: trả null = bỏ qua (cho luật sau xét tiếp), khác null = phán quyết.
/// Cho phép nhét quy tắc đặc thù vào Registry mà KHÔNG sửa engine.
typedef ConstraintRule = ValidationResult? Function(
    List<SelectionItem> current, SelectionItem attempt);

/// Bộ thuộc tính quy tắc của một loại đối tượng.
class Capabilities {
  /// false = toàn bộ phiên chọn chỉ được đúng 1 mục (vd Scene chọn 1 mode).
  final bool multiSelection;

  /// false = mỗi scope (thiết bị/endpoint/giờ...) tối đa 1 mục.
  final bool allowMultiEndpoint;

  /// Trần số mục mỗi scope (0 = không giới hạn; chỉ xét khi allowMultiEndpoint=true).
  final int maxPerScope;

  /// true = vi phạm trần thì 'uncheck' mục cũ (mục mới thắng) thay vì từ chối.
  final bool exclusiveGroup;

  /// Câu báo lỗi khi từ chối (engine có câu mặc định nếu bỏ trống).
  final String? denyReason;

  /// Luật tùy biến chạy TRƯỚC các luật chuẩn — mở rộng không đụng engine.
  final List<ConstraintRule> extraRules;

  const Capabilities({
    this.multiSelection = true,
    this.allowMultiEndpoint = true,
    this.maxPerScope = 0,
    this.exclusiveGroup = false,
    this.denyReason,
    this.extraRules = const [],
  });
}

/// [LUẬT NHÓM] "CẢ THIẾT BỊ" vs "KÊNH LẺ" loại trừ nhau trong CÙNG một MAC.
/// Quy ước key của member nhóm: 'MAC|endpoint' — endpoint rỗng (key kết thúc '|')
/// = member đại diện CẢ THIẾT BỊ. Nếu để chúng song song, toggle nhóm sẽ bắn
/// 'all' + từng kênh -> SSW04 bật cả 4 relay dù chỉ chọn 2 (điểm mù đa kênh).
/// Luật: chọn KÊNH LẺ -> tự đá member cả-thiết-bị; chọn CẢ THIẾT BỊ -> tự đá
/// mọi kênh lẻ của MAC đó. Trả null khi không có xung đột (luật sau xét tiếp).
ValidationResult? ruleWholeDeviceVsChannel(List<SelectionItem> current, SelectionItem attempt) {
  bool isWhole(SelectionItem i) => i.key.endsWith('|');
  final conflicts = current
      .where((i) => i.scopeKey == attempt.scopeKey && isWhole(i) != isWhole(attempt))
      .toList();
  if (conflicts.isEmpty) return null;
  return ValidationResult.allowedWith(
      [for (final i in conflicts) SelectionOp(SelectionOp.uncheck, i.key)]);
}

/// BẢNG ĐĂNG KÝ QUY TẮC — nguồn sự thật duy nhất phía App.
class CapabilityRegistry {
  static final Map<String, Capabilities> _registry = {
    // ---- NHÓM CÔNG TẮC ----
    // additive: chọn thoải mái nhiều relay/thiết bị — nhưng cả-thiết-bị vs kênh lẻ
    // của cùng MAC loại trừ nhau (ruleWholeDeviceVsChannel)
    'group.normal': const Capabilities(extraRules: [ruleWholeDeviceVsChannel]),
    'group.staircase': const Capabilities(extraRules: [ruleWholeDeviceVsChannel]),
    'group.fan': const Capabilities(
      allowMultiEndpoint: false, // mỗi thiết bị đúng 1 kênh
      exclusiveGroup: true, // chọn kênh mới tự đá kênh cũ cùng thiết bị
      extraRules: [ruleWholeDeviceVsChannel],
    ),

    // ---- NGỮ CẢNH: hành động (THÌ...) ----
    // 1 endpoint chỉ mang 1 hành động trong 1 ngữ cảnh — thêm hành động mới cho cùng
    // endpoint sẽ THAY hành động cũ (tránh "bật rồi tắt cùng kênh" vô nghĩa/xung đột).
    'scene.actions': const Capabilities(
      allowMultiEndpoint: false,
      exclusiveGroup: true,
    ),

    // ---- HẸN GIỜ: lịch trong ngày của một thiết bị ----
    // Mỗi mốc giờ chỉ 1 lịch (2 lịch cùng giờ = xung đột ON/OFF không xác định) —
    // không exclusive: bắt user sửa lịch cũ thay vì lặng lẽ đè.
    'schedule.times': const Capabilities(
      allowMultiEndpoint: false,
      denyReason: 'Đã có lịch trình vào đúng giờ này — hãy sửa hoặc xóa lịch cũ trước',
    ),
  };

  /// Đăng ký/ghi đè quy tắc lúc runtime (phục vụ loại đối tượng mới, test...).
  static void register(String entityType, Capabilities caps) => _registry[entityType] = caps;

  /// Không đăng ký = không ràng buộc (Capabilities mặc định cho phép tất).
  static Capabilities of(String entityType) => _registry[entityType] ?? const Capabilities();
}

/// Engine THUẦN TÚY — không state, không UI, không biết nghiệp vụ.
class ValidationEngine {
  static ValidationResult validate({
    required Capabilities caps,
    required List<SelectionItem> current,
    required SelectionItem attempt,
  }) {
    // 0. Trùng định danh tuyệt đối -> không có gì để làm
    if (current.any((i) => i.key == attempt.key)) {
      return const ValidationResult.denied('Mục này đã được chọn');
    }

    // 1. Luật tùy biến (đặc thù nghiệp vụ) — thắng mọi luật chuẩn
    for (final rule in caps.extraRules) {
      final r = rule(current, attempt);
      if (r != null) return r;
    }

    // 2. Chọn đơn toàn cục: mục mới thay tất cả (exclusive) hoặc từ chối
    if (!caps.multiSelection && current.isNotEmpty) {
      if (caps.exclusiveGroup) {
        return ValidationResult.allowedWith(
            [for (final i in current) SelectionOp(SelectionOp.uncheck, i.key)]);
      }
      return ValidationResult.denied(caps.denyReason ?? 'Chỉ được chọn một mục');
    }

    // 3. Trần mục trong cùng scope
    final sameScope = current.where((i) => i.scopeKey == attempt.scopeKey).toList();
    final int limit =
        !caps.allowMultiEndpoint ? 1 : (caps.maxPerScope > 0 ? caps.maxPerScope : 0);
    if (limit == 0 || sameScope.length < limit) return const ValidationResult.allowedWith();

    if (caps.exclusiveGroup) {
      // Đá đủ số mục CŨ NHẤT để vừa trần sau khi thêm mục mới
      final removeCount = sameScope.length - limit + 1;
      return ValidationResult.allowedWith([
        for (final i in sameScope.take(removeCount)) SelectionOp(SelectionOp.uncheck, i.key)
      ]);
    }
    return ValidationResult.denied(
        caps.denyReason ?? 'Vượt giới hạn $limit mục cho mỗi phạm vi — hãy bỏ bớt trước');
  }

  /// Tiện ích: validate theo tên loại đối tượng trong Registry.
  static ValidationResult validateFor(String entityType,
          {required List<SelectionItem> current, required SelectionItem attempt}) =>
      validate(caps: CapabilityRegistry.of(entityType), current: current, attempt: attempt);
}
