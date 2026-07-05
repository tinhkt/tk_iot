import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/device_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Trỏ chính xác vào IP Box Armbian của bạn
  static const String baseUrl = 'https://api.iot-smart.vn/api';

  // --- HÀM LẤY TRẠNG THÁI THIẾT BỊ (ĐÃ ĐƯỢC LỒNG GHÉP AUTH) ---
  Future<DeviceState?> getDeviceState(String mac) async {
    try {
      // THAY ĐỔI Ở ĐÂY: Dùng authorizedGet thay vì http.get trực tiếp
      final response = await authorizedGet('$baseUrl/devices/$mac/state');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        // Lưu ý: Nếu server trả về dạng {"success": true, "data": {...}}
        // Bạn có thể cần truy cập data['data'] tùy vào cấu trúc model của bạn.
        // Ở đây tôi giữ nguyên logic cũ theo file bạn gửi:
        return DeviceState.fromJson(data);
      } else {
        print('⚠️ Server Golang báo lỗi (Status ${response.statusCode}): ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Không thể kết nối tới Box Armbian: $e');
      return null;
    }
  }

  // --- HÀM TRỢ GIÚP GẮN TOKEN VÀO HEADER ---
  Future<http.Response> authorizedGet(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    // Debug: Kiểm tra token trước khi gửi
    print("ApiService: Đang gửi Token: $token");

    return await http.get(
      Uri.parse(url),
      headers: {
        // Đảm bảo đúng định dạng: "Bearer <token>" (có dấu cách)
        'Authorization': 'Bearer $token', 
        'Content-Type': 'application/json',
      },
    );
  }
}