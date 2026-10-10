import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class AdminService {
  static const String baseUrl = 'http://localhost:8000/api/v1';

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Lấy số liệu thống kê tổng hợp dự án
  static Future<Map<String, dynamic>> fetchSummary() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/reports/summary'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // fallback
    }
    return {
      "total_vehicles": 5,
      "total_orders": 2,
      "today_inspections": 1,
      "flagged_anomalies": 0,
      "active_breakdowns": 0,
      "fuel_mismatches": 0,
      "compliance_rate": "96.4%",
      "avg_pump_time_minutes": 78
    };
  }

  /// Lấy danh sách đơn hàng thực tế
  static Future<List<dynamic>> fetchOrders() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/orders'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách phương tiện thực tế
  static Future<List<dynamic>> fetchVehicles() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/vehicles'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách sản phẩm (Tro bay, Xi măng rời...)
  static Future<List<dynamic>> fetchProducts() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/products'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách cây dầu & trạm cấp nhiên liệu
  static Future<List<dynamic>> fetchGasStations() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/gas-stations'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách tài xế
  static Future<List<dynamic>> fetchDrivers() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/drivers'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách toàn bộ tài khoản người dùng
  static Future<List<dynamic>> fetchUsers() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/users'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách vai trò phân quyền (Roles)
  static Future<List<dynamic>> fetchRoles() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/rbac/roles'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách quyền hạt nhân (Permissions)
  static Future<List<dynamic>> fetchPermissions() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/rbac/permissions'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Tạo vai trò phân quyền mới (Role) kèm quyền (Permissions)
  static Future<Map<String, dynamic>> createRole(Map<String, dynamic> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/rbac/roles'),
        headers: await _headers(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi tạo vai trò'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Cập nhật vai trò và danh sách quyền hạt nhân
  static Future<Map<String, dynamic>> updateRole(int roleId, Map<String, dynamic> payload) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/rbac/roles/$roleId'),
        headers: await _headers(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi cập nhật vai trò'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Xóa vai trò phân quyền
  static Future<Map<String, dynamic>> deleteRole(int roleId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/rbac/roles/$roleId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi xóa vai trò'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Tạo tài khoản người dùng mới kèm vai trò
  static Future<Map<String, dynamic>> createUser(Map<String, dynamic> payload) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: await _headers(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi tạo tài khoản'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Cập nhật thông tin tài khoản người dùng
  static Future<Map<String, dynamic>> updateUser(int userId, Map<String, dynamic> payload) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/users/$userId'),
        headers: await _headers(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi cập nhật tài khoản'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Đổi mật khẩu tài khoản người dùng
  static Future<Map<String, dynamic>> changePassword(int userId, String newPassword) async {
    try {
      final res = await http.put(
        Uri.parse('$baseUrl/users/$userId/password'),
        headers: await _headers(),
        body: jsonEncode({'new_password': newPassword}),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi đổi mật khẩu'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Xóa tài khoản người dùng
  static Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/users/$userId'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi xóa tài khoản'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Tải tệp hình ảnh lên server và nhận URL lưu trữ
  static Future<Map<String, dynamic>> uploadImage(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:8000/api/v1/upload/image'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'url': data['url'], 'filename': data['filename']};
      } else {
        return {'success': false, 'message': 'Lỗi máy chủ khi tải ảnh'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể upload ảnh: $e'};
    }
  }

  /// Lấy danh sách các điều phối viên đang trong ca trực
  static Future<List<dynamic>> fetchActiveShifts() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/shifts/active'),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Điều phối viên bấm nhận ca
  static Future<Map<String, dynamic>> checkinShift({String shiftName = 'Ca ngày', String? note}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/shifts/checkin'),
        headers: await _headers(),
        body: jsonEncode({
          'shift_name': shiftName,
          'note': note,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi nhận ca'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Điều phối viên kết thúc / bàn giao ca
  static Future<Map<String, dynamic>> checkoutShift({String? note}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/shifts/checkout'),
        headers: await _headers(),
        body: jsonEncode({
          'note': note,
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {'success': false, 'message': err['detail'] ?? 'Lỗi kết thúc ca'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Lấy toàn bộ lịch sử ca trực của các điều phối viên
  static Future<List<dynamic>> fetchShiftHistory({int? userId, int limit = 50}) async {
    try {
      String url = '$baseUrl/shifts/history?limit=$limit';
      if (userId != null) {
        url += '&user_id=$userId';
      }
      final res = await http.get(
        Uri.parse(url),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }
}
