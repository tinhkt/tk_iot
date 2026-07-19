import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/app_ui_wrappers.dart';
import '../../localization/app_translations.dart';

class ProfileManagementView extends StatefulWidget {
  final String currentRole;
  final String currentEmail;

  const ProfileManagementView({super.key, required this.currentRole, required this.currentEmail});

  @override
  State<ProfileManagementView> createState() => _ProfileManagementViewState();
}

class _ProfileManagementViewState extends State<ProfileManagementView> {
  final AuthService _authService = AuthService();
  
  // --- CONTROLLER CHO FORM CHỈNH SỬA ---
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _editingEmail = '';
  String _avatarUrl = '';
  // [FIX GIAI ĐOẠN 96 — CACHE BUST] Server đặt tên file theo "avatar_{email}_{filename gốc}" —
  // nếu ảnh mới upload trùng tên file gốc với ảnh cũ (rất hay gặp, image_picker nhiều máy trả
  // tên file cố định/lặp lại), URL không đổi -> NetworkImage cache theo URL vẫn hiện ảnh CŨ dù
  // server đã lưu ảnh MỚI đè lên. Đổi giá trị này mỗi lần _avatarUrl cập nhật (upload thành công
  // HOẶC nạp lại hồ sơ) để buộc Flutter luôn tải lại, không dùng cache stale.
  int _avatarCacheBuster = 0;

  // Trạng thái file ảnh chọn từ máy để review trước khi upload
  File? _selectedImage;

  List<dynamic> _allUsers = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isUploading = false;
  final Color tkGreen = const Color(0xFF00A651);

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // Tải dữ liệu ban đầu từ Backend
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    // Mặc định nạp hồ sơ của chính mình trước
    _editingEmail = widget.currentEmail;
    
    // GỌI API LẤY DỮ LIỆU THẬT CỦA BẢN THÂN
    final myProfile = await _authService.getMyProfile();
    if (myProfile != null) {
      _nameCtrl.text = myProfile['full_name'] ?? '';
      _phoneCtrl.text = myProfile['phone'] ?? '';
      _addressCtrl.text = myProfile['address'] ?? '';
      _avatarUrl = myProfile['avatar_url'] ?? '';
      _avatarCacheBuster = DateTime.now().millisecondsSinceEpoch;
    }

    // Nếu là SUPER_USER, lấy thêm danh sách tất cả các user hệ thống
    if (widget.currentRole == 'SUPER_USER') {
      final users = await _authService.getHomeUsers();
      if (users != null) {
        _allUsers = users;
      }
    }
    
    setState(() => _isLoading = false);
  }

  // Chuyển đổi đối tượng chỉnh sửa dành riêng cho Developer
  void _selectUserToEdit(Map<String, dynamic> user) {
    setState(() {
      _editingEmail = user['email'];
      _nameCtrl.text = user['full_name'] ?? '';
      _phoneCtrl.text = user['phone'] ?? '';
      _addressCtrl.text = user['address'] ?? '';
      _avatarUrl = user['avatar_url'] ?? '';
      _avatarCacheBuster = DateTime.now().millisecondsSinceEpoch;
      _selectedImage = null; // Reset ảnh tạm
    });
  }

  // [FIX GIAI ĐOẠN 103 — DÙNG Uri CHUẨN, KHÔNG TỰ GHÉP CHUỖI] Bản trước (Giai đoạn 102) tự cắt
  // hậu tố "/api" bằng substring thủ công — ĐÃ ĐÚNG và đã tự chạy verify bằng Dart CLI, nhưng vẫn
  // là ghép chuỗi tay, dễ sai lại nếu baseUrl đổi hình dạng sau này. Đổi hẳn sang Uri.replace(path:)
  // — ĐÃ TỰ CHẠY THẬT bằng Dart CLI để xác nhận hành vi (không suy đoán):
  //   Uri.parse('https://api.iot-smart.vn/api').replace(path: '/uploads/avatar_test.jpg').toString()
  //   -> "https://api.iot-smart.vn/uploads/avatar_test.jpg"
  // replace(path:) THAY THẾ TOÀN BỘ path cũ (kể cả "/api") bằng path mới — KHÔNG cần tự cắt hậu tố
  // "/api" nữa (Uri tự lo), VÀ tự thêm dấu "/" đầu nếu thiếu (đã verify: path truyền vào không có
  // "/" đầu vẫn ra kết quả đúng) — loại bỏ hoàn toàn lớp cắt-ghép chuỗi thủ công trước đây.
  // queryParameters cũng qua Uri (không tự nối "?v=..." bằng chuỗi) — không bao giờ ra "??" hay
  // thiếu "?" nếu sau này path đã có sẵn query string.
  String? _resolveAvatarDisplayUrl() {
    if (_avatarUrl.isEmpty) return null;
    // Nếu Server đã trả URL TUYỆT ĐỐI (dữ liệu cũ/hành vi khác sau này) thì giữ nguyên gốc, chỉ
    // gắn thêm cache-buster qua Uri.replace — không parse lại domain, không nối chồng domain.
    final bool isAbsolute = _avatarUrl.startsWith('http://') || _avatarUrl.startsWith('https://');
    final Uri baseUri = isAbsolute ? Uri.parse(_avatarUrl) : Uri.parse(_authService.baseUrl);
    final Uri finalUri = isAbsolute
        ? baseUri.replace(queryParameters: {'v': '$_avatarCacheBuster'})
        : baseUri.replace(path: _avatarUrl, queryParameters: {'v': '$_avatarCacheBuster'});
    final String finalUrl = finalUri.toString();
    if (kDebugMode) print('🖼️ [AVATAR] URL đang tải: $finalUrl');
    return finalUrl;
  }

  // Widget ảnh đại diện lấy từ Server — tách riêng để CHỈ resolve URL (và in log) ĐÚNG MỘT LẦN
  // mỗi lượt build, tránh gọi _resolveAvatarDisplayUrl() lặp lại ở nhiều nhánh.
  Widget _buildAvatarImage() {
    final String? url = _resolveAvatarDisplayUrl();
    if (url == null) {
      return Icon(Icons.business_center_rounded, size: 48, color: tkGreen.withValues(alpha: 0.5));
    }
    return Image.network(
      url,
      width: 108,
      height: 108,
      fit: BoxFit.cover,
      // [FIX GIAI ĐOẠN 98] Icon lỗi màu ĐỎ RÕ RÀNG — phân biệt hẳn với icon mặc định "chưa có
      // ảnh" (màu xanh nhạt) để người dùng biết CHẮC CHẮN là URL bị chết (404/mất mạng/CORS...),
      // không nhầm lẫn với trạng thái "chưa từng đặt ảnh đại diện".
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) print('❌ [AVATAR] Lỗi tải ảnh từ $url: $error');
        return const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent);
      },
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Center(child: CircularProgressIndicator(strokeWidth: 2, color: tkGreen.withValues(alpha: 0.5))),
    );
  }

  // --- LOGIC GỌI CAMERA / BỘ SƯU TẬP ẢNH ---
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    // Khởi tạo cửa sổ chọn ảnh (hỗ trợ cả Mobile và Desktop)
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
        _isUploading = true;
      });

      // Gọi API Upload ảnh thật lên server Golang
      // [FIX GIAI ĐOẠN 94] uploadAvatar giờ trả record (url, error) — hiện ĐÚNG lỗi Server trả
      // (hoặc lỗi mạng) thay vì câu chung chung "Tải ảnh thất bại" không rõ nguyên nhân.
      final result = await _authService.uploadAvatar(_selectedImage!);

      if (!mounted) return; // màn hình đã đóng trong lúc chờ upload
      setState(() { _isUploading = false; });

      if (result.url != null) {
        setState(() { _avatarUrl = result.url!; _avatarCacheBuster = DateTime.now().millisecondsSinceEpoch; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tải ảnh lên thành công! Bấm Cập Nhật để lưu.'), backgroundColor: Color(0xFF00A651)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error ?? 'Tải ảnh thất bại! Vui lòng thử lại.'), backgroundColor: Colors.redAccent));
      }
    }
  }

  // Tiến hành lưu dữ liệu
  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    
    // Nếu đang sửa chính mình thì không cần truyền targetEmail
    String? target = (_editingEmail == widget.currentEmail) ? null : _editingEmail;

    String? error = await _authService.updateProfile(
      targetEmail: target,
      fullName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      avatarUrl: _avatarUrl.isNotEmpty ? _avatarUrl : null,
    );

    if (!mounted) return; // màn hình đã đóng trong lúc chờ API
    setState(() => _isSaving = false);

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã cập nhật thông tin cho $_editingEmail thành công!'), backgroundColor: tkGreen)
      );
      if (widget.currentRole == 'SUPER_USER') _fetchLatestUsersSilently();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _fetchLatestUsersSilently() async {
    final users = await _authService.getHomeUsers();
    if (users != null) {
      setState(() { _allUsers = users; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 900;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // [FIX — Low Contrast trên nền Kính] textMain/textSub trước đây chỉ theo isDark hệ thống,
    // không biết view này đang nằm trong popup Cài đặt kính (showAppDialog) hay không — đồng bộ
    // quy ước glass-aware của AppTextField/AppDropdown: BẬT kính -> luôn trắng/trắng70.
    final bool isGlass = context.watch<ThemeProvider>().isGlassThemeEnabled;
    final Color textMain = isGlass ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A));
    final Color textSub = isGlass ? Colors.white70 : (isDark ? Colors.white54 : const Color(0xFF64748B));
    final List<Shadow>? sh = isGlass ? kGlassTextShadow : null;
    final bool isSuperUser = widget.currentRole == 'SUPER_USER';
    final t = AppTranslations.of(context);

    if (_isLoading) return Center(child: CircularProgressIndicator(color: tkGreen));

    return Row(
      children: [
        // CỘT TRÁI: FORM CHỈNH SỬA THÔNG TIN CHI TIẾT
        Expanded(
          flex: 6,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editingEmail == widget.currentEmail ? t.text('my_profile') : t.text('edit_system_account'),
                  style: TextStyle(color: textMain, fontSize: 26, fontWeight: FontWeight.bold, shadows: sh),
                ),
                Text(t.text('profile_desc'), style: TextStyle(color: textSub, fontSize: 13, fontWeight: FontWeight.w500, shadows: sh)),
                const SizedBox(height: 32),
                
                // KHU VỰC THAY ĐỔI AVATAR
                Center(
                  child: Stack(
                    children: [
                      // [FIX GIAI ĐOẠN 96/98] Đổi từ CircleAvatar.backgroundImage (KHÔNG có
                      // errorBuilder — lỗi tải chỉ gọi onBackgroundImageError, không tự động rơi
                      // về icon mặc định được) sang CircleAvatar bọc ClipOval + _buildAvatarImage()
                      // (Image.network có đủ errorBuilder/loadingBuilder — xem hàm bên dưới).
                      CircleAvatar(
                        radius: 54,
                        backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                        child: ClipOval(
                          child: SizedBox(
                            width: 108,
                            height: 108,
                            // Hiển thị ưu tiên: Ảnh vừa chọn Local -> Ảnh từ Server -> Icon mặc định
                            child: _selectedImage != null
                                ? Image.file(_selectedImage!, width: 108, height: 108, fit: BoxFit.cover)
                                : _buildAvatarImage(),
                          ),
                        ),
                      ),
                      if (_isUploading)
                        const Positioned.fill(child: CircularProgressIndicator(color: Color(0xFF00A651), strokeWidth: 3)),
                      Positioned(
                        bottom: 0, right: 0,
                        child: CircleAvatar(
                          radius: 18, backgroundColor: tkGreen,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
                            onPressed: _isUploading ? null : _pickImage, // MỞ HỘP THOẠI CHỌN ẢNH
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // CÁC TRƯỜNG NHẬP LIỆU CHI TIẾT
                _buildField(t.text('email_fixed'), TextEditingController(text: _editingEmail), Icons.email_outlined, enabled: false, isGlass: isGlass, textMain: textMain, textSub: textSub, sh: sh),
                const SizedBox(height: 16),
                _buildField(t.text('full_name_company'), _nameCtrl, Icons.business_rounded, hint: t.text('full_name_hint'), isGlass: isGlass, textMain: textMain, textSub: textSub, sh: sh),
                const SizedBox(height: 16),
                _buildField(t.text('phone_number'), _phoneCtrl, Icons.phone_android_rounded, hint: t.text('phone_hint'), isGlass: isGlass, textMain: textMain, textSub: textSub, sh: sh),
                const SizedBox(height: 16),
                _buildField(t.text('address'), _addressCtrl, Icons.location_on_outlined, hint: t.text('address_hint'), isGlass: isGlass, textMain: textMain, textSub: textSub, sh: sh),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(t.text('update_profile_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),

                // Nút quay về sửa chính mình
                if (_editingEmail != widget.currentEmail) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: textSub),
                    onPressed: _loadInitialData,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: Text(t.text('back_to_my_profile')),
                  )
                ]
              ],
            ),
          ),
        ),
        
        // CỘT PHẢI: DANH SÁCH USER TOÀN HỆ THỐNG (CHỈ SUPER_USER MỚI CÓ)
        if (isSuperUser && !isMobile) ...[
          VerticalDivider(width: 1, color: isDark ? Colors.white10 : Colors.black12),
          Expanded(
            flex: 4,
            child: Container(
              color: isDark ? Colors.black12 : Colors.grey.withValues(alpha: 0.02),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.text('system_wide_profiles'), style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold, shadows: sh)),
                  Text(t.text('tap_to_edit_account'), style: TextStyle(color: textSub, fontSize: 12, fontWeight: FontWeight.w500, shadows: sh)),
                  const SizedBox(height: 20),
                  Expanded(
                    child: ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: _allUsers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final u = _allUsers[index];
                        bool isTarget = _editingEmail == u['email'];
                        return ListTile(
                          selected: isTarget,
                          selectedTileColor: tkGreen.withValues(alpha: 0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: CircleAvatar(
                            backgroundColor: isTarget ? tkGreen : Colors.blue.withValues(alpha: 0.1),
                            child: Icon(Icons.person, color: isTarget ? Colors.white : Colors.blue, size: 18),
                          ),
                          title: Text(u['email'], style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold, shadows: sh), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${t.text('role_label')}: ${u['role'] ?? 'USER'}', style: TextStyle(fontSize: 11, color: textSub, fontWeight: FontWeight.w500, shadows: sh)),
                          trailing: const Icon(Icons.edit_note_rounded, size: 18),
                          onTap: () => _selectUserToEdit(u),
                        );
                      },
                    ),
                  )
                ],
              ),
            ),
          )
        ]
      ],
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon, {String? hint, bool enabled = true, required bool isGlass, required Color textMain, required Color textSub, required List<Shadow>? sh}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold, shadows: sh)),
        const SizedBox(height: 8),
        // [FIX — Input mờ trên nền kính] TextField trần tự chế fillColor/border (từng dùng
        // fillColor alpha 0.02 ở chế độ tối — gần như trong suốt, chìm hẳn vào lớp kính phía
        // sau) ĐÃ THAY bằng AppTextField — khối kính "chìm" trung tâm của cả hệ thống.
        // prefixIcon truyền màu textSub tường minh (đồng bộ admin_system_screen.dart) — Icon()
        // không tự kế thừa DefaultTextStyle/hintColor như Text.
        AppTextField(
          controller: ctrl,
          enabled: enabled,
          hintText: hint,
          prefixIcon: Icon(icon, color: textSub, size: 18),
        ),
      ],
    );
  }
}