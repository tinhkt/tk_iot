import 'package:flutter/material.dart';

import 'app_ui_wrappers.dart';

/// Dialog "Thêm thành viên" — thu thập email + vai trò rồi giao lại cho [onSubmit].
///
/// [LƯU Ý KIẾN TRÚC — TRÁNH BẪY "POP TRƯỚC AWAIT"]: dialog TỰ chạy [onSubmit] và CHỈ
/// Navigator.pop() khi thành công. Lỗi (network/HTTP 400/403/404) được bắt NGAY TẠI ĐÂY
/// và hiện SnackBar đỏ bằng context CỦA CHÍNH DIALOG (vẫn còn mounted vì chưa pop) — khác
/// với cách làm cũ trong _showAddOrEditHomeDialog (pop() rồi mới await), vốn khiến lỗi sau
/// khi pop bị "nuốt câm" bởi guard `if (!context.mounted) return`. Dialog chỉ trả `true`
/// về cho màn hình cha khi CHẮC CHẮN đã thành công — màn hình cha dựa vào đó để bắn
/// SnackBar xanh, không cần đoán.
class AddMemberDialog extends StatefulWidget {
  /// Ném lỗi (vd HomeApiException) nếu Backend từ chối — dialog sẽ tự bắt và hiển thị.
  final Future<void> Function(String email, String role) onSubmit;
  const AddMemberDialog({super.key, required this.onSubmit});

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  static final Color _tkGreen = const Color(0xFF00A651);
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  String _role = 'USER';
  bool _submitting = false;

  static final RegExp _emailPattern = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_emailCtrl.text.trim(), _role);
      if (!mounted) return;
      Navigator.pop(context, true); // chỉ pop khi CHẮC CHẮN thành công
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);

    // [GLASS THEME] Dialog/ConstrainedBox/GlassCard thủ công cũ ĐÃ BỎ khỏi build() của
    // chính class này — caller (member_list_screen.dart) nay đưa thẳng AddMemberDialog vào
    // showAppDialog(child: ...), showAppDialog tự cấp khung Dialog/kính bên ngoài.
    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thêm thành viên', style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Tài khoản phải đã đăng ký trên hệ thống', style: TextStyle(color: textSub, fontSize: 12)),
                const SizedBox(height: 24),
                // [FORM SWEEP] TextFormField/DropdownButtonFormField ĐÃ THAY bằng
                // AppTextField/AppDropdown — validator/controller/onChanged nối nguyên vẹn.
                AppTextField(
                  controller: _emailCtrl,
                  enabled: !_submitting,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  labelText: 'Email thành viên',
                  hintText: 'vd: nguoithan@gmail.com',
                  prefixIcon: Icon(Icons.email_outlined, color: textSub, size: 20),
                  validator: (v) {
                    final value = (v ?? '').trim();
                    if (value.isEmpty) return 'Vui lòng nhập email';
                    if (!_emailPattern.hasMatch(value)) return 'Email không hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppDropdown<String>(
                  value: _role,
                  labelText: 'Vai trò trong nhà',
                  prefixIcon: Icon(Icons.badge_outlined, color: textSub, size: 20),
                  items: const [
                    DropdownMenuItem(value: 'USER', child: Text('Thành viên (USER) — chỉ điều khiển thiết bị')),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Quản trị (ADMIN) — được thêm/gỡ thiết bị')),
                  ],
                  onChanged: _submitting ? null : (v) => setState(() => _role = v ?? 'USER'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context, false),
                      child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _submitting ? null : _handleSubmit,
                      child: _submitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Thêm vào nhà', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }
}
