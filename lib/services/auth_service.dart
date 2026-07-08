import 'dart:convert';
import 'dart:io'; // <-- [BẢN CẬP NHẬT MỚI]: Yêu cầu để sử dụng đối tượng File tải ảnh
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart'; // Yêu cầu để sử dụng ScaffoldMessenger và MaterialPageRoute
import 'package:http/http.dart' as http;

import '../../main.dart'; // Import để truy cập navigatorKey toàn cục
import '../screens/auth/login_screen.dart'; // Import màn hình Đăng nhập
import 'secure_storage_service.dart';

class AuthService {
  final String baseUrl = "https://api.iot-smart.vn/api";

  // ============================================================================
  // HÀM HỖ TRỢ CHUNG: TỰ ĐỘNG VĂNG RA KHI TOKEN HẾT HẠN (LỖI 401)
  // ============================================================================
  
  // Chúng ta để public (bỏ dấu _ ở đầu) để các Provider khác (như DeviceProvider)
  // cũng có thể mượn hàm này để kích hoạt luồng văng ra ngoài khi cần thiết.
  void handleUnauthorized() async {
    // 1. Dọn dẹp sạch sẽ token cũ trong máy
    await logout();
    
    // 2. Dùng navigatorKey lấy Context hiện tại mà không cần truyền biến lằng nhằng
    final context = navigatorKey.currentContext;
    if (context != null) {
      // 3. Hiển thị thông báo (Popup nhỏ phía dưới)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại!'), 
          backgroundColor: Colors.orange
        )
      );
      
      // 4. Đá văng người dùng về trang Đăng nhập và chém đứt sạch lịch sử các trang trước đó
      navigatorKey.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()), 
        (route) => false
      );
    }
  }

  // ============================================================================
  // 1. ĐĂNG NHẬP & ĐĂNG XUẤT
  // ============================================================================
  
  Future<bool> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];

        await SecureStorageService.saveToken(token);
        return true;
      }
    } catch (e) {
      if (kDebugMode) print("Lỗi kết nối auth: $e");
    }
    return false;
  }

  Future<void> logout() async {
    await SecureStorageService.deleteToken();
  }

  Future<String?> getToken() => SecureStorageService.getToken();

  // ============================================================================
  // 2. ĐĂNG KÝ TÀI KHOẢN (BỔ SUNG OTP)
  // ============================================================================
  
  // Gửi OTP xác thực về Email trước khi đăng ký
  Future<String?> sendRegisterOTP(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/send-register-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return null; // Trả về null nghĩa là đã gửi mail thành công
      } else {
        return data['error'] ?? "Lỗi không xác định từ Máy chủ";
      }
    } catch (e) {
      return "Không thể kết nối đến hệ thống gửi Mail";
    }
  }

  // Thực hiện đăng ký cùng với mã OTP
  Future<String?> register(String email, String password, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email, 
          'password': password,
          'otp': otp // Bắt buộc truyền OTP lên Backend
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return null; // Thành công
      } else {
        return data['error'] ?? "Lỗi không xác định từ Server";
      }
    } catch (e) {
      return "Không thể kết nối đến Máy chủ hệ thống";
    }
  }

  // ============================================================================
  // 3. QUÊN MẬT KHẨU & ĐẶT LẠI MẬT KHẨU
  // ============================================================================
  
  Future<String?> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return null;
      } else {
        return data['error'] ?? "Lỗi không xác định từ Server";
      }
    } catch (e) {
      return "Không thể kết nối đến Máy chủ hệ thống";
    }
  }

  Future<String?> resetPassword(String email, String otp, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'new_password': newPassword
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return null;
      } else {
        return data['error'] ?? "Lỗi không xác định từ Server";
      }
    } catch (e) {
      return "Không thể kết nối đến Máy chủ hệ thống";
    }
  }

  // ============================================================================
  // 4. ĐỔI MẬT KHẨU (YÊU CẦU ĐÃ ĐĂNG NHẬP)
  // ============================================================================
  
  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      final token = await getToken();
      if (token == null) return "Bạn chưa đăng nhập hoặc phiên làm việc đã hết hạn.";

      final response = await http.post(
        Uri.parse('$baseUrl/user/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', 
        },
        body: jsonEncode({
          'old_password': oldPassword,
          'new_password': newPassword
        }),
      );

      // KIỂM TRA LỖI TOKEN HẾT HẠN NGAY TẠI ĐÂY
      if (response.statusCode == 401) {
        handleUnauthorized();
        return "Phiên làm việc hết hạn.";
      }

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return null;
      } else {
        return data['error'] ?? "Lỗi không xác định từ Server";
      }
    } catch (e) {
      return "Không thể kết nối đến Máy chủ hệ thống";
    }
  }

  // ============================================================================
  // 5. QUẢN LÝ PHÂN QUYỀN (Dành riêng cho SUPER_USER và HOME_OWNER)
  // ============================================================================

  Future<List<dynamic>?> getHomeUsers() async {
    try {
      final token = await getToken();
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: {'Authorization': 'Bearer $token'},
      );

      // KIỂM TRA LỖI TOKEN HẾT HẠN
      if (response.statusCode == 401) {
        handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['data'] ?? []; 
      }
    } catch (e) {
      if (kDebugMode) print("Lỗi getHomeUsers: $e");
    }
    return null; 
  }

  Future<String?> updateUserConfig(String email, String role, List<String> endpoints) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/admin/change-role'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'email': email,
          'role': role,
          'accessible_endpoints': endpoints
        }),
      );

      // KIỂM TRA LỖI TOKEN HẾT HẠN
      if (response.statusCode == 401) {
        handleUnauthorized();
        return "Phiên làm việc hết hạn.";
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return null; 
      return data['error'] ?? "Lỗi không xác định từ Server";
    } catch (e) {
      return "Không thể kết nối đến Máy chủ hệ thống";
    }
  }

  Future<String?> deleteUser(String email) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/admin/delete-user'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'email': email}),
      );

      // KIỂM TRA LỖI TOKEN HẾT HẠN
      if (response.statusCode == 401) {
        handleUnauthorized();
        return "Phiên làm việc hết hạn.";
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return null; 
      return data['error'] ?? "Lỗi không xác định từ Server";
    } catch (e) {
      return "Không thể kết nối đến Máy chủ hệ thống";
    }
  }

  // ============================================================================
  // 6. LIÊN KẾT HUB THIẾT BỊ (THÊM THIẾT BỊ MỚI)
  // ============================================================================

  // Liên kết Hub mới (Cập nhật MAC Address)
  Future<String?> linkHub(String macAddress) async {
    try {
      final token = await getToken();
      if (token == null) return "Lỗi xác thực.";

      final response = await http.post(
        Uri.parse('$baseUrl/devices/link-hub'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'mac_address': macAddress}),
      );

      if (response.statusCode == 401) {
        handleUnauthorized();
        return "Phiên làm việc hết hạn.";
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        // LƯU Ý QUAN TRỌNG: Lưu đè token mới (chứa mã MAC thật) do server vừa cấp
        await SecureStorageService.saveToken(data['token']);
        return null; // Thành công
      }
      return data['error'] ?? "Lỗi từ máy chủ";
    } catch (e) {
      return "Lỗi kết nối mạng";
    }
  }

  // ============================================================================
  // 7. QUẢN LÝ THÔNG TIN HỒ SƠ TÀI KHOẢN (PROFILE) VÀ AVATAR
  // ============================================================================

  // Hàm lấy thông tin tài khoản thật từ Server (My Profile)
  Future<Map<String, dynamic>?> getMyProfile() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 401) {
        handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body)['profile'];
      }
      return null;
    } catch (e) {
      if (kDebugMode) print("Lỗi getMyProfile: $e");
      return null;
    }
  }

  // Hàm đẩy ảnh Avatar lên Server (Multi-part Request)
  Future<String?> uploadAvatar(File imageFile) async {
    try {
      final token = await getToken();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      // Gắn file vật lý vào luồng Stream
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 401) {
        handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['avatar_url']; // Trả về đường dẫn ảnh tĩnh sau khi server lưu xong
      }
      return null;
    } catch (e) {
      if (kDebugMode) print("Lỗi uploadAvatar: $e");
      return null;
    }
  }

  // Hàm lưu dữ liệu Form Profile lên Server
  Future<String?> updateProfile({
    String? targetEmail,
    required String fullName,
    required String phone,
    required String address,
    String? avatarUrl,
  }) async {
    try {
      final token = await getToken();
      final response = await http.put(
        Uri.parse('$baseUrl/profile/update'), // Đã trỏ đúng theo URL mới của Backend
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({
          'target_email': ?targetEmail,
          'full_name': fullName,
          'phone': phone,
          'address': address,
          'avatar_url': ?avatarUrl,
        }),
      );

      if (response.statusCode == 401) {
        handleUnauthorized();
        return "Phiên làm việc hết hạn.";
      }

      if (response.statusCode == 200) return null; // Thành công
      
      final data = jsonDecode(response.body);
      return data['error'] ?? "Không thể cập nhật hồ sơ.";
    } catch (e) {
      return "Lỗi kết nối máy chủ";
    }
  }

  // Hàm kéo lịch sử thông báo thật từ Redis Database xuống
  Future<List<dynamic>?> getNotifications() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 401) {
        handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['data'] ?? [];
      }
    } catch (e) {
      if (kDebugMode) print("Lỗi kết nối API thông báo: $e");
    }
    return null;
  }
}