import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Đường dẫn Backend API thực tế
  static const String baseUrl = 'https://saomai-api.type.vn/api/v1/auth';

  /// Gửi yêu cầu đăng nhập thực tế tới FastAPI và nhận JWT Bearer Token
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/login');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 8));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        final token = data['access_token'] as String?;
        if (token != null) {
          await prefs.setString('jwt_token', token);
          await prefs.setString('user_id', data['user_id']?.toString() ?? '');
          await prefs.setString('username', data['username'] ?? '');
          await prefs.setString('full_name', data['full_name'] ?? '');
          if (data['roles'] != null) {
            await prefs.setStringList('roles', List<String>.from(data['roles']));
          }
        }
        return {
          'success': true,
          'data': data,
        };
      } else {
        return {
          'success': false,
          'message': data['detail'] ?? 'Tên đăng nhập hoặc mật khẩu không đúng.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Không thể kết nối đến máy chủ API: $e',
      };
    }
  }

  /// Lấy thông tin phiên đăng nhập đã lưu trong SharedPreferences
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  /// Lấy toàn bộ thông tin phiên đã lưu trong bộ nhớ máy
  static Future<Map<String, dynamic>?> getSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token == null || token.isEmpty) return null;

    final userIdStr = prefs.getString('user_id');
    final username = prefs.getString('username');
    final fullName = prefs.getString('full_name');
    final roles = prefs.getStringList('roles') ?? [];

    return {
      'access_token': token,
      'user_id': int.tryParse(userIdStr ?? '') ?? 0,
      'username': username ?? '',
      'full_name': fullName ?? '',
      'roles': roles,
    };
  }

  /// Đăng xuất và xóa phiên đăng nhập
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_id');
    await prefs.remove('username');
    await prefs.remove('full_name');
    await prefs.remove('roles');
  }
}
