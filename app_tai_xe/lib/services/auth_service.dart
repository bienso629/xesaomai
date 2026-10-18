import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  // Đường dẫn Backend API thực tế
  static const String baseUrl = 'https://saomai-api.type.vn/api/v1/auth';
  static const String apiV1Url = 'https://saomai-api.type.vn/api/v1';

  /// Khởi tạo hoặc lấy Device Token cố định của thiết bị hiện tại
  static Future<Map<String, String>> getOrCreateDeviceMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceToken = prefs.getString('device_push_token');
    String platform = 'android';
    String deviceName = 'Mobile Device';

    if (!kIsWeb) {
      if (Platform.isAndroid) {
        platform = 'android';
        deviceName = 'Android (${Platform.localHostname})';
      } else if (Platform.isIOS) {
        platform = 'ios';
        deviceName = 'iOS (${Platform.localHostname})';
      } else if (Platform.isLinux) {
        platform = 'linux';
        deviceName = 'Linux Desktop (${Platform.localHostname})';
      } else if (Platform.isWindows) {
        platform = 'windows';
        deviceName = 'Windows Desktop (${Platform.localHostname})';
      }
    }

    if (deviceToken == null || deviceToken.isEmpty) {
      final rawUuid = const Uuid().v4().replaceAll('-', '').substring(0, 16);
      deviceToken = 'fcm_${platform}_$rawUuid';
      await prefs.setString('device_push_token', deviceToken);
    }

    return {
      'device_token': deviceToken,
      'platform': platform,
      'device_name': deviceName,
      'app_version': '1.0.0',
    };
  }

  /// Đồng bộ Device Token lên máy chủ cho các phiên đăng nhập đã lưu sẵn
  static Future<void> syncDeviceToken() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;

      final meta = await getOrCreateDeviceMetadata();
      final url = Uri.parse('$apiV1Url/devices/register');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(meta),
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('Lỗi đồng bộ device_token: $e');
    }
  }

  /// Gửi yêu cầu đăng nhập thực tế tới FastAPI kèm Device Token và nhận JWT Bearer Token
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final meta = await getOrCreateDeviceMetadata();
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
          'device_token': meta['device_token'],
          'platform': meta['platform'],
          'device_name': meta['device_name'],
          'app_version': meta['app_version'],
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
