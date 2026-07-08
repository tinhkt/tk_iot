import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';

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
      _selectedImage = null; // Reset ảnh tạm
    });
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
      String? uploadedUrl = await _authService.uploadAvatar(_selectedImage!);
      
      setState(() { _isUploading = false; });

      if (uploadedUrl != null) {
        setState(() { _avatarUrl = uploadedUrl; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tải ảnh lên thành công! Bấm Cập Nhật để lưu.'), backgroundColor: Color(0xFF00A651)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tải ảnh thất bại! Vui lòng thử lại.'), backgroundColor: Colors.redAccent));
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
    final Color textMain = isDark ? Colors.white : const Color(0xFF0F172A);
    final Color textSub = isDark ? Colors.white54 : const Color(0xFF64748B);
    final bool isSuperUser = widget.currentRole == 'SUPER_USER';

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
                  _editingEmail == widget.currentEmail ? 'Hồ sơ của tôi' : 'Chỉnh sửa tài khoản hệ thống',
                  style: TextStyle(color: textMain, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text('Cập nhật đầy đủ thông tin hành chính và phương thức liên hệ.', style: TextStyle(color: textSub, fontSize: 13)),
                const SizedBox(height: 32),
                
                // KHU VỰC THAY ĐỔI AVATAR
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 54,
                        backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                        // Hiển thị ưu tiên: Ảnh vừa chọn Local -> Ảnh từ Server -> Icon mặc định
                        backgroundImage: _selectedImage != null 
                            ? FileImage(_selectedImage!) as ImageProvider
                            : (_avatarUrl.isNotEmpty ? NetworkImage('${_authService.baseUrl.replaceAll('/api', '')}$_avatarUrl') : null),
                        child: (_selectedImage == null && _avatarUrl.isEmpty)
                            ? Icon(Icons.business_center_rounded, size: 48, color: tkGreen.withValues(alpha: 0.5))
                            : null,
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
                _buildField('Tài khoản Email (Cố định)', TextEditingController(text: _editingEmail), Icons.email_outlined, enabled: false, isDark: isDark, textMain: textMain, textSub: textSub),
                const SizedBox(height: 16),
                _buildField('Họ tên / Tên Công ty', _nameCtrl, Icons.business_rounded, hint: 'Nhập tên thực thể vận hành', isDark: isDark, textMain: textMain, textSub: textSub),
                const SizedBox(height: 16),
                _buildField('Số điện thoại liên hệ', _phoneCtrl, Icons.phone_android_rounded, hint: 'Số hotline hoặc sđt cá nhân', isDark: isDark, textMain: textMain, textSub: textSub),
                const SizedBox(height: 16),
                _buildField('Địa chỉ văn phòng / Nhà ở', _addressCtrl, Icons.location_on_outlined, hint: 'Nhập địa chỉ chi tiết', isDark: isDark, textMain: textMain, textSub: textSub),
                
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: tkGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _isSaving ? null : _saveProfile,
                    child: _isSaving 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('CẬP NHẬT THÔNG TIN HỒ SƠ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                // Nút quay về sửa chính mình
                if (_editingEmail != widget.currentEmail) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: textSub),
                    onPressed: _loadInitialData,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Quay lại sửa hồ sơ cá nhân của tôi'),
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
                  Text('Hồ sơ toàn hệ thống', style: TextStyle(color: textMain, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Bấm vào một tài khoản để sửa đổi thông tin của họ.', style: TextStyle(color: textSub, fontSize: 12)),
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
                          title: Text(u['email'], style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Quyền: ${u['role'] ?? 'USER'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

  Widget _buildField(String label, TextEditingController ctrl, IconData icon, {String? hint, bool enabled = true, required bool isDark, required Color textMain, required Color textSub}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          enabled: enabled,
          style: TextStyle(color: enabled ? textMain : textSub, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: textSub, size: 18),
            filled: true,
            fillColor: enabled ? (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white) : (isDark ? Colors.black26 : Colors.grey.shade100),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade300)),
          ),
        ),
      ],
    );
  }
}