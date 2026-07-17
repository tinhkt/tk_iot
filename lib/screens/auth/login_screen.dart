import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  /// Khóa SharedPreferences ghi nhớ Username/Email của phiên đăng nhập gần nhất.
  /// Chỉ lưu ĐỊNH DANH (không bao giờ lưu mật khẩu) — token phiên vẫn nằm riêng
  /// trong SecureStorage; đăng xuất xóa token nhưng giữ lại định danh này.
  static const String _kLastIdentifierKey = 'last_login_identifier';

  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    _restoreLastIdentifier();
  }

  /// Tự điền Username/Email của phiên trước vào ô đăng nhập —
  /// người dùng mở lại app chỉ cần gõ mật khẩu.
  Future<void> _restoreLastIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kLastIdentifierKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _emailController.text = saved);
    }
  }

  void _handleLogin() async {
    setState(() => _isLoading = true);

    final identifier = _emailController.text.trim();
    bool success = await _authService.login(
      identifier,
      _passwordController.text.trim()
    );

    setState(() => _isLoading = false);

    if (success) {
      // Chỉ ghi nhớ định danh khi đăng nhập THÀNH CÔNG (không lưu chuỗi gõ sai)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastIdentifierKey, identifier);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sai tài khoản hoặc mật khẩu!'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showForgotPasswordDialog() {
    String step = 'email'; 
    final emailCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool isDialogLoading = false;

    // [GLASS THEME] Dialog/ConstrainedBox/GlassContainer thủ công cũ ĐÃ THAY bằng
    // showAppDialog() — showAppDialog tự cấp khung Dialog/kính, bỏ GlassContainer lồng
    // trong đây (tránh 2 lớp BackdropFilter chồng nhau); giữ nguyên StatefulBuilder (state
    // cục bộ isDialogLoading/step) + ConstrainedBox maxWidth 400.
    showAppDialog(
      context: context,
      barrierDismissible: false,
      child: Builder(
        builder: (context) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
        final Color textSub = isDark ? Colors.white70 : Colors.black54;
        final Color inputBg = isDark ? Colors.black26 : Colors.grey.shade100;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(step == 'email' ? Icons.mark_email_read_outlined : Icons.lock_reset, size: 48, color: tkGreen),
                      const SizedBox(height: 16),
                      Text(
                        step == 'email' ? 'Quên mật khẩu' : 'Đặt lại mật khẩu', 
                        style: TextStyle(color: textMain, fontSize: 20, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(height: 12),
                      
                      if (step == 'email') ...[
                        Text(
                          'Vui lòng nhập Email của bạn. Hệ thống sẽ gửi mã OTP gồm 6 chữ số để khôi phục tài khoản.', 
                          style: TextStyle(fontSize: 13, color: textSub, height: 1.5), 
                          textAlign: TextAlign.center
                        ),
                        const SizedBox(height: 20),
                        // [FORM SWEEP] TextField -> AppTextField.
                        AppTextField(
                          controller: emailCtrl,
                          hintText: 'Nhập email đã đăng ký',
                        ),
                      ] else ...[
                        Text(
                          'Mã OTP đã được gửi đến:\n${emailCtrl.text}', 
                          style: TextStyle(fontSize: 13, color: textSub, height: 1.5), 
                          textAlign: TextAlign.center
                        ),
                        const SizedBox(height: 20),
                        // [FORM SWEEP — GIỮ NGUYÊN TextField] AppTextField chưa hỗ trợ textAlign/
                        // style tùy biến (fontSize/letterSpacing riêng)/counterText — cần cả 3 để
                        // giữ đúng UX ô nhập OTP căn giữa, giãn chữ, ẩn bộ đếm ký tự. Ép chuyển sẽ
                        // làm MẤT các đặc điểm này (vi phạm "không rớt một ký tự nào của logic
                        // cũ") — để nguyên, chờ mở rộng AppTextField ở lượt sau nếu cần.
                        TextField(
                          controller: otpCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: textMain, fontSize: 18, letterSpacing: 4.0),
                          decoration: InputDecoration(
                            hintText: 'Mã OTP (6 số)',
                            hintStyle: TextStyle(color: textSub, letterSpacing: 0),
                            counterText: "",
                            filled: true,
                            fillColor: inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
                          ),
                        ),
                        const SizedBox(height: 12),
                        // [FORM SWEEP] TextField -> AppTextField.
                        AppTextField(
                          controller: newPassCtrl,
                          obscureText: true,
                          hintText: 'Mật khẩu mới (Tối thiểu 6 ký tự)',
                        ),
                      ],
                      const SizedBox(height: 24),
                      
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: isDialogLoading ? null : () => Navigator.pop(context),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: Text('Hủy', style: TextStyle(color: textSub, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tkGreen,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                              ),
                              onPressed: isDialogLoading ? null : () async {
                                if (step == 'email') {
                                  final email = emailCtrl.text.trim();
                                  if (email.isEmpty) return;

                                  setDialogState(() => isDialogLoading = true);
                                  String? error = await _authService.forgotPassword(email);
                                  setDialogState(() => isDialogLoading = false);

                                  if (error == null) {
                                    setDialogState(() => step = 'otp'); 
                                  } else {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
                                  }
                                } else {
                                  final email = emailCtrl.text.trim();
                                  final otp = otpCtrl.text.trim();
                                  final newPass = newPassCtrl.text.trim();
                                  
                                  if (otp.isEmpty || newPass.isEmpty) return;
                                  if (newPass.length < 6) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mật khẩu mới phải có tối thiểu 6 ký tự'), backgroundColor: Colors.redAccent));
                                    return;
                                  }

                                  setDialogState(() => isDialogLoading = true);
                                  String? error = await _authService.resetPassword(email, otp, newPass);
                                  setDialogState(() => isDialogLoading = false);

                                  if (error == null) {
                                    if (!context.mounted) return;
                                    Navigator.pop(context); 
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi mật khẩu thành công! Hãy đăng nhập lại.'), backgroundColor: Color(0xFF00A651)));
                                  } else {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
                                  }
                                }
                              },
                              child: isDialogLoading 
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : Text(step == 'email' ? 'Nhận mã OTP' : 'Xác nhận', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
            );
          },
        );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final Color bgColor = isDark ? const Color(0xFF0B1120) : const Color(0xFFF4F7FC); 
    final Color surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white70 : Colors.black54;

    return AppScaffold(
      backgroundColor: bgColor,
      body: Center(
        child: SingleChildScrollView( 
          child: SizedBox(
            width: 350,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 80, color: tkGreen),
                const SizedBox(height: 20),
                
                Text("ĐĂNG NHẬP HỆ THỐNG", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textMain)),
                const SizedBox(height: 30),
                
                TextField(
                  controller: _emailController,
                  style: TextStyle(color: textMain), 
                  decoration: InputDecoration(
                    // Backend chấp nhận cả username admin lẫn email thường
                    hintText: 'Username hoặc Email',
                    hintStyle: TextStyle(color: textSub),
                    filled: true, 
                    fillColor: surfaceColor, 
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), 
                  ),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: TextStyle(color: textMain), 
                  decoration: InputDecoration(
                    // Đã sửa thành hintText và thêm contentPadding
                    hintText: 'Nhập mật khẩu', 
                    hintStyle: TextStyle(color: textSub),
                    filled: true, 
                    fillColor: surfaceColor, 
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: Text('Quên mật khẩu?', style: TextStyle(color: tkGreen, fontWeight: FontWeight.w600)),
                  ),
                ),
                
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tkGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                      elevation: 4, 
                      shadowColor: tkGreen.withValues(alpha: 0.5),
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text("XÁC THỰC TRUY CẬP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                  ),
                ),
                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text('Chưa có tài khoản?', style: TextStyle(color: textSub), overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterScreen()),
                        );
                      },
                      child: Text('Đăng ký ngay', style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}