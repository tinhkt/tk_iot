import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../widgets/app_ui_wrappers.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController(); 
  
  final AuthService _authService = AuthService();
  
  bool _isLoading = false;
  bool _isOTPSent = false; 

  final Color tkGreen = const Color(0xFF00A651);

  // BƯỚC 1: Xử lý Gửi mã OTP về Email
  void _handleSendOTP() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      _showError('Vui lòng điền đầy đủ thông tin để đăng ký');
      return;
    }
    if (pass.length < 6) {
      _showError('Mật khẩu phải có tối thiểu 6 ký tự');
      return;
    }
    if (pass != confirm) {
      _showError('Mật khẩu xác nhận không khớp');
      return;
    }

    setState(() => _isLoading = true);
    
    // Yêu cầu Backend gửi thư OTP
    String? errorMsg = await _authService.sendRegisterOTP(email);

    setState(() => _isLoading = false);

    if (errorMsg == null) {
      // Gửi mail thành công, chuyển sang màn hình nhập OTP
      setState(() => _isOTPSent = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mã xác thực đã được gửi tới Email của bạn!'), backgroundColor: Color(0xFF00A651)),
      );
    } else {
      _showError(errorMsg);
    }
  }

  // BƯỚC 2: Xử lý Xác nhận Đăng ký (Có kèm OTP)
  void _handleFinalRegister() async {
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();
    final otp = _otpController.text.trim();

    if (otp.isEmpty || otp.length < 6) {
      _showError('Vui lòng nhập đúng 6 số mã xác nhận OTP');
      return;
    }

    setState(() => _isLoading = true);
    
    // Gọi API sang Golang, truyền cả email, pass và OTP
    String? errorMsg = await _authService.register(email, pass, otp);

    setState(() => _isLoading = false);

    if (errorMsg == null) {
      // Đăng ký thành công
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tạo tài khoản thành công! Vui lòng đăng nhập.'), backgroundColor: Color(0xFF00A651)),
      );
      Navigator.pop(context); // Quay lại màn hình Login
    } else {
      _showError(errorMsg);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
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
                Icon(
                  _isOTPSent ? Icons.mark_email_read_rounded : Icons.person_add_alt_1_rounded, 
                  size: 80, 
                  color: tkGreen
                ),
                const SizedBox(height: 20),
                
                Text(
                  _isOTPSent ? "XÁC NHẬN EMAIL" : "TẠO TÀI KHOẢN MỚI", 
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textMain)
                ),
                const SizedBox(height: 10),
                
                if (_isOTPSent)
                  Text(
                    "Mã xác thực đã được gửi tới:\n${_emailController.text}", 
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: textSub, height: 1.5)
                  ),

                const SizedBox(height: 30),
                
                // --- FORM NHẬP THÔNG TIN ---
                if (!_isOTPSent) ...[
                  // [FORM SWEEP] 3× TextField -> AppTextField (không validator/textAlign đặc
                  // biệt nên chuyển an toàn 100%).
                  AppTextField(
                    controller: _emailController,
                    hintText: 'Nhập email',
                  ),
                  const SizedBox(height: 16),

                  AppTextField(
                    controller: _passwordController,
                    obscureText: true,
                    hintText: 'Mật khẩu (tối thiểu 6 ký tự)',
                  ),
                  const SizedBox(height: 16),

                  AppTextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    hintText: 'Xác nhận lại mật khẩu',
                  ),
                ],

                // --- FORM NHẬP OTP (CHỈ HIỆN KHI ĐÃ GỬI EMAIL) ---
                if (_isOTPSent) ...[
                  // [FORM SWEEP — GIỮ NGUYÊN TextField] Cần textAlign/style tùy biến/
                  // counterText mà AppTextField chưa hỗ trợ — ép chuyển sẽ mất UX ô OTP căn
                  // giữa/giãn chữ/ẩn bộ đếm, để nguyên (cùng lý do login_screen.dart).
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textMain, fontSize: 18, letterSpacing: 4.0),
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: 'Nhập mã OTP 6 số', 
                      hintStyle: TextStyle(color: textSub, letterSpacing: 0),
                      filled: true, 
                      fillColor: surfaceColor, 
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      counterText: "", 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
                    ),
                  ),
                ],

                const SizedBox(height: 25),
                
                // --- NÚT BẤM (ĐỒNG BỘ KÍCH THƯỚC VỚI LOGIN) ---
                SizedBox(
                  width: double.infinity, 
                  height: 52, // Đã nâng lên 52 giống LoginScreen
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tkGreen,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                      elevation: 4, 
                      shadowColor: tkGreen.withValues(alpha: 0.5),
                    ),
                    onPressed: _isLoading 
                        ? null 
                        : (_isOTPSent ? _handleFinalRegister : _handleSendOTP),
                    child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : Text(
                          _isOTPSent ? "HOÀN TẤT ĐĂNG KÝ" : "TIẾP TỤC", 
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)
                        ),
                  ),
                ),

                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text("Đã có tài khoản? ", style: TextStyle(color: textSub), overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text("Đăng nhập", style: TextStyle(color: tkGreen, fontWeight: FontWeight.bold)),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}