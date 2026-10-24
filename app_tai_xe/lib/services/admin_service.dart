import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../config/api_config.dart';

class AdminService {
  static const String baseUrl = ApiConfig.apiV1;

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
      final res = await http
          .get(Uri.parse('$baseUrl/reports/summary'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

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
      "avg_pump_time_minutes": 78,
    };
  }

  /// Lấy danh sách đơn hàng thực tế
  static Future<List<dynamic>> fetchOrders() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/orders'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Tạo đơn hàng mới
  static Future<Map<String, dynamic>> createOrder(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/orders'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 201 || res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi tạo đơn hàng',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Cập nhật đơn hàng
  static Future<Map<String, dynamic>> updateOrder(
    int orderId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/orders/$orderId'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi cập nhật đơn hàng',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Xóa đơn hàng
  static Future<Map<String, dynamic>> deleteOrder(int orderId) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/orders/$orderId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi xóa đơn hàng',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Lấy danh sách phương tiện thực tế.
  /// [includeInactive] = true: lấy thêm xe Tạm ngừng hoạt động (không còn trên Vietmap / Bình Anh).
  static Future<List<dynamic>> fetchVehicles({bool includeInactive = false}) async {
    try {
      final uri = Uri.parse(
        includeInactive
            ? '$baseUrl/vehicles?include_inactive=true'
            : '$baseUrl/vehicles',
      );
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Nút "Tải lại danh sách" ở Đội xe: gọi ngay Vietmap + Bình Anh để đối chiếu và đồng bộ.
  /// Trả về {'success': bool, 'data': thống kê} hoặc {'success': false, 'message': ...}.
  static Future<Map<String, dynamic>> syncFleetVehicles() async {
    try {
      final res = await http
          .post(Uri.parse('$baseUrl/vehicles/sync'), headers: await _headers())
          .timeout(const Duration(seconds: 45));
      final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
      if (res.statusCode == 200 && body is Map) {
        return {'success': true, 'data': Map<String, dynamic>.from(body)};
      }
      if (res.statusCode == 404) {
        return {
          'success': false,
          'message': 'Máy chủ chưa có chức năng đồng bộ đội xe (cần cập nhật backend)',
        };
      }
      final detail = body is Map ? body['detail'] : null;
      return {
        'success': false,
        'message': (detail ?? 'Đồng bộ thất bại (HTTP ${res.statusCode})').toString(),
      };
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Cập nhật thông tin phương tiện (Loại xe, Hình thức sở hữu, Tài xế chỉ định, Đơn vị quản lý, Trạng thái)
  static Future<Map<String, dynamic>> updateVehicle(
    String plateNumber,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/vehicles/${Uri.encodeComponent(plateNumber)}'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final body = jsonDecode(res.body);
        return {
          'success': false,
          'message': body['detail'] ?? 'Cập nhật thất bại',
        };
      }
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Lấy danh sách sản phẩm (Tro bay, Xi măng rời...)
  static Future<List<dynamic>> fetchProducts() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/products'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Tạo mới sản phẩm vật liệu
  static Future<Map<String, dynamic>?> createProduct({
    required String code,
    required String name,
    required String category,
    required String unit,
    required int standardPumpTimeMinutes,
    required bool requiresAirPump,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/products'),
            headers: await _headers(),
            body: jsonEncode({
              'code': code,
              'name': name,
              'category': category,
              'unit': unit,
              'standard_pump_time_minutes': standardPumpTimeMinutes,
              'requires_air_pump': requiresAirPump,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 201 || res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Cập nhật sản phẩm vật liệu
  static Future<Map<String, dynamic>?> updateProduct(
    int id, {
    required String code,
    required String name,
    required String category,
    required String unit,
    required int standardPumpTimeMinutes,
    required bool requiresAirPump,
  }) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/products/$id'),
            headers: await _headers(),
            body: jsonEncode({
              'code': code,
              'name': name,
              'category': category,
              'unit': unit,
              'standard_pump_time_minutes': standardPumpTimeMinutes,
              'requires_air_pump': requiresAirPump,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Xóa sản phẩm vật liệu
  static Future<bool> deleteProduct(int id) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/products/$id'), headers: await _headers())
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {}
    return false;
  }

  /// Lấy danh sách khách hàng (Điều phối, Quản lý, Admin)
  static Future<List<dynamic>> fetchCustomers() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/customers'), headers: await _headers())
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Tạo mới hoặc cập nhật khách hàng.
  /// Trả về {'success': bool, 'message': String, 'data': Map?}
  static Future<Map<String, dynamic>> saveCustomer({
    int? id,
    required Map<String, dynamic> data,
  }) async {
    try {
      final uri = id == null
          ? Uri.parse('$baseUrl/customers')
          : Uri.parse('$baseUrl/customers/$id');
      final body = jsonEncode(data);
      final res = await (id == null
              ? http.post(uri, headers: await _headers(), body: body)
              : http.put(uri, headers: await _headers(), body: body))
          .timeout(const Duration(seconds: 8));
      final decoded = res.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true, 'message': 'Đã lưu khách hàng', 'data': decoded};
      }
      final detail = decoded is Map ? decoded['detail'] : null;
      return {
        'success': false,
        'message': detail?.toString() ?? 'Lỗi máy chủ (${res.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Xóa khách hàng (xóa mềm phía server)
  static Future<bool> deleteCustomer(int id) async {
    try {
      final res = await http
          .delete(Uri.parse('$baseUrl/customers/$id'), headers: await _headers())
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (_) {}
    return false;
  }

  // ---------------- ĐIỂM NHẬN / GIAO HÀNG ----------------

  /// Gọi API điểm nhận / giao, trả về {'ok': bool, 'status': int, 'data': dynamic, 'message': String}
  static Future<Map<String, dynamic>> _locationCall(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int timeoutSeconds = 10,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/$path');
      final headers = await _headers();
      final encoded = body == null ? null : jsonEncode(body);
      final Future<http.Response> req;
      switch (method) {
        case 'POST':
          req = http.post(uri, headers: headers, body: encoded ?? '{}');
          break;
        case 'PUT':
          req = http.put(uri, headers: headers, body: encoded ?? '{}');
          break;
        case 'DELETE':
          req = http.delete(uri, headers: headers);
          break;
        default:
          req = http.get(uri, headers: headers);
      }
      final res = await req.timeout(Duration(seconds: timeoutSeconds));
      final decoded = res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final detail = decoded is Map ? decoded['detail'] : null;
      return {
        'ok': ok,
        'status': res.statusCode,
        'data': decoded,
        'message': ok ? '' : (detail?.toString() ?? 'Lỗi máy chủ (${res.statusCode})'),
      };
    } catch (e) {
      return {'ok': false, 'status': 0, 'data': null, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Danh mục điểm nhận / giao hàng. [kind] = PICKUP | DELIVERY (kèm cả BOTH), để trống là lấy hết.
  static Future<List<dynamic>> fetchLocations({String? kind}) async {
    final res = await _locationCall('GET', kind == null ? 'locations' : 'locations?kind=$kind');
    return res['ok'] == true && res['data'] is List ? res['data'] as List<dynamic> : [];
  }

  /// Tạo mới hoặc cập nhật một điểm trong danh mục.
  static Future<Map<String, dynamic>> saveLocation({int? id, required Map<String, dynamic> data}) {
    return id == null
        ? _locationCall('POST', 'locations', body: data)
        : _locationCall('PUT', 'locations/$id', body: data);
  }

  /// Xóa (mềm) một điểm khỏi danh mục.
  static Future<Map<String, dynamic>> deleteLocation(int id) => _locationCall('DELETE', 'locations/$id');

  /// Bắt đầu quét lịch sử dừng đỗ của Vietmap và Bình Anh (chạy nền phía server).
  static Future<Map<String, dynamic>> startLocationScan(Map<String, dynamic> options) =>
      _locationCall('POST', 'locations/scan', body: options);

  /// Tiến độ lượt quét gần nhất.
  static Future<Map<String, dynamic>> fetchLocationScanStatus() => _locationCall('GET', 'locations/scan/status');

  /// Gợi ý điểm gom từ GPS. [status] = PENDING | IGNORED | APPROVED | ALL
  static Future<List<dynamic>> fetchLocationSuggestions({String status = 'PENDING'}) async {
    final res = await _locationCall('GET', 'location-suggestions?status_filter=$status');
    return res['ok'] == true && res['data'] is List ? res['data'] as List<dynamic> : [];
  }

  /// Duyệt gợi ý thành một điểm trong danh mục.
  static Future<Map<String, dynamic>> approveLocationSuggestion(int id, Map<String, dynamic> data) =>
      _locationCall('POST', 'location-suggestions/$id/approve', body: data);

  /// Bỏ qua gợi ý (lần quét sau không hiện lại trong hàng chờ).
  static Future<Map<String, dynamic>> ignoreLocationSuggestion(int id) =>
      _locationCall('POST', 'location-suggestions/$id/ignore');

  /// Đưa gợi ý đã bỏ qua về hàng chờ duyệt.
  static Future<Map<String, dynamic>> restoreLocationSuggestion(int id) =>
      _locationCall('POST', 'location-suggestions/$id/restore');

  /// Gọi API Zalo OA, trả về {'ok': bool, 'status': int, 'data': dynamic, 'message': String}
  static Future<Map<String, dynamic>> _zaloCall(String method, String path) async {
    try {
      final uri = Uri.parse('$baseUrl/zalo-oa/$path');
      final headers = await _headers();
      final res = await (method == 'POST'
              ? http.post(uri, headers: headers)
              : http.get(uri, headers: headers))
          .timeout(const Duration(seconds: 10));
      final decoded = res.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(res.bodyBytes));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final detail = decoded is Map ? decoded['detail'] : null;
      return {
        'ok': ok,
        'status': res.statusCode,
        'data': decoded,
        'message': ok
            ? ''
            : (res.statusCode == 404
                ? 'Máy chủ chưa có chức năng Zalo OA (cần cập nhật backend)'
                : detail?.toString() ?? 'Lỗi máy chủ (${res.statusCode})'),
      };
    } catch (e) {
      return {'ok': false, 'status': 0, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Trạng thái kết nối & tiến độ đồng bộ Zalo OA
  static Future<Map<String, dynamic>> fetchZaloOaStatus() =>
      _zaloCall('GET', 'status');

  /// Xin đường link cấp quyền Zalo OA (mở bằng trình duyệt)
  static Future<Map<String, dynamic>> requestZaloOaAuthorizeUrl() =>
      _zaloCall('POST', 'authorize-url');

  /// Bắt đầu đồng bộ toàn bộ người dùng Zalo OA vào danh sách Khách hàng
  static Future<Map<String, dynamic>> startZaloOaSync() =>
      _zaloCall('POST', 'sync');

  /// Gọi API dịch vụ GPS Bình Anh qua backend (backend giữ tài khoản Bình Anh).
  /// path: 'tracking' | 'route' | 'activity' | 'status'
  static Future<Map<String, dynamic>> binhAnhCall(
    String path, {
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/binhanh/$path')
          .replace(queryParameters: query);
      final res =
          await http.get(uri, headers: await _headers()).timeout(timeout);
      final decoded = res.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(res.bodyBytes));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      final detail = decoded is Map ? decoded['detail'] : null;
      return {
        'ok': ok,
        'status': res.statusCode,
        'data': decoded,
        'message': ok
            ? ''
            : (res.statusCode == 404
                ? 'Máy chủ chưa có dịch vụ Bình Anh (cần cập nhật backend)'
                : detail?.toString() ?? 'Lỗi máy chủ (${res.statusCode})'),
      };
    } on TimeoutException {
      return {'ok': false, 'status': 0, 'message': 'Dịch vụ Bình Anh phản hồi quá lâu, vui lòng thử lại.'};
    } catch (e) {
      return {'ok': false, 'status': 0, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Lấy danh sách cây dầu & trạm cấp nhiên liệu
  static Future<List<dynamic>> fetchGasStations() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/gas-stations'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Tạo mới cây dầu / trạm cấp nhiên liệu
  static Future<Map<String, dynamic>?> createGasStation({
    required String name,
    required String address,
    required double lat,
    required double lng,
    double allowedRadiusMeters = 500,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/gas-stations'),
            headers: await _headers(),
            body: jsonEncode({
              'name': name,
              'address': address,
              'lat': lat,
              'lng': lng,
              'allowed_radius_meters': allowedRadiusMeters,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 201 || res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Cập nhật thông tin cây dầu
  static Future<Map<String, dynamic>?> updateGasStation(
    int id, {
    required String name,
    required String address,
    required double lat,
    required double lng,
    required double allowedRadiusMeters,
  }) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/gas-stations/$id'),
            headers: await _headers(),
            body: jsonEncode({
              'name': name,
              'address': address,
              'lat': lat,
              'lng': lng,
              'allowed_radius_meters': allowedRadiusMeters,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Xóa cây dầu
  static Future<bool> deleteGasStation(int id) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/gas-stations/$id'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return true;
    } catch (_) {}
    return false;
  }

  /// Lấy danh sách tài xế
  static Future<List<dynamic>> fetchDrivers() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/drivers'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách toàn bộ tài khoản người dùng
  static Future<List<dynamic>> fetchUsers() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/users'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách vai trò phân quyền (Roles)
  static Future<List<dynamic>> fetchRoles() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/rbac/roles'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách quyền hạt nhân (Permissions)
  static Future<List<dynamic>> fetchPermissions() async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/rbac/permissions'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Tạo vai trò phân quyền mới (Role) kèm quyền (Permissions)
  static Future<Map<String, dynamic>> createRole(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/rbac/roles'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi tạo vai trò',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Cập nhật vai trò và danh sách quyền hạt nhân
  static Future<Map<String, dynamic>> updateRole(
    int roleId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/rbac/roles/$roleId'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi cập nhật vai trò',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Xóa vai trò phân quyền
  static Future<Map<String, dynamic>> deleteRole(int roleId) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/rbac/roles/$roleId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi xóa vai trò',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Tạo tài khoản người dùng mới kèm vai trò
  static Future<Map<String, dynamic>> createUser(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/users'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi tạo tài khoản',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Cập nhật thông tin tài khoản người dùng
  static Future<Map<String, dynamic>> updateUser(
    int userId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/users/$userId'),
            headers: await _headers(),
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi cập nhật tài khoản',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Đổi mật khẩu tài khoản người dùng
  static Future<Map<String, dynamic>> changePassword(
    int userId,
    String newPassword,
  ) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/users/$userId/password'),
            headers: await _headers(),
            body: jsonEncode({'new_password': newPassword}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi đổi mật khẩu',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Xóa tài khoản người dùng
  static Future<Map<String, dynamic>> deleteUser(int userId) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$baseUrl/users/$userId'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi xóa tài khoản',
        };
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
        Uri.parse('$baseUrl/upload/image'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'url': data['url'],
          'filename': data['filename'],
        };
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
      final res = await http
          .get(Uri.parse('$baseUrl/shifts/active'), headers: await _headers())
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Điều phối viên bấm nhận ca
  static Future<Map<String, dynamic>> checkinShift({
    String shiftName = 'Ca ngày',
    String? note,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/shifts/checkin'),
            headers: await _headers(),
            body: jsonEncode({'shift_name': shiftName, 'note': note}),
          )
          .timeout(const Duration(seconds: 8));

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
      final res = await http
          .post(
            Uri.parse('$baseUrl/shifts/checkout'),
            headers: await _headers(),
            body: jsonEncode({'note': note}),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi kết thúc ca',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Lấy toàn bộ lịch sử ca trực của các điều phối viên
  static Future<List<dynamic>> fetchShiftHistory({
    int? userId,
    int limit = 50,
  }) async {
    try {
      String url = '$baseUrl/shifts/history?limit=$limit';
      if (userId != null) {
        url += '&user_id=$userId';
      }
      final res = await http
          .get(Uri.parse(url), headers: await _headers())
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Lấy danh sách kiểm tra xe 5 ảnh của tài xế
  static Future<List<dynamic>> fetchInspections({
    String? date,
    String? plateNumber,
  }) async {
    try {
      String url = '$baseUrl/inspections?';
      if (date != null && date.isNotEmpty) {
        url += 'date=$date&';
      }
      if (plateNumber != null && plateNumber.isNotEmpty) {
        url += 'plate_number=${Uri.encodeComponent(plateNumber)}&';
      }
      final res = await http
          .get(Uri.parse(url), headers: await _headers())
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  /// Gửi dữ liệu kiểm tra xe 5 ảnh của tài xế lên hệ thống
  static Future<Map<String, dynamic>> submitInspection({
    required String checkDate,
    required String plateNumber,
    required String imgFront,
    required String imgRear,
    required String imgLeft,
    required String imgRight,
    required String imgDashboard,
    required double gpsLat,
    required double gpsLng,
    required double gpsAccuracy,
    required String deviceId,
    required double kmOcr,
    required double kmConfirmed,
    List<Map<String, dynamic>>? photoGps,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/inspection/submit'),
            headers: await _headers(),
            body: jsonEncode({
              'check_date': checkDate,
              'plate_number': plateNumber,
              'img_front_underbody': imgFront,
              'img_rear_underbody': imgRear,
              'img_left_side': imgLeft,
              'img_right_side': imgRight,
              'img_dashboard': imgDashboard,
              'gps_lat': gpsLat,
              'gps_lng': gpsLng,
              'gps_accuracy': gpsAccuracy,
              'device_id': deviceId,
              'km_ocr': kmOcr,
              'km_confirmed': kmConfirmed,
              if (photoGps != null) 'photo_gps': photoGps,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 201 || res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi gửi kiểm tra xe',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Điều phối viên duyệt / xử lý cờ kiểm tra xe 5 ảnh
  static Future<Map<String, dynamic>> reviewInspection(
    int inspectionId, {
    required String flagStatus,
    String? flagReason,
  }) async {
    try {
      final res = await http
          .put(
            Uri.parse('$baseUrl/inspections/$inspectionId/review'),
            headers: await _headers(),
            body: jsonEncode({
              'flag_status': flagStatus,
              'flag_reason': flagReason,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return {'success': true, 'data': jsonDecode(res.body)};
      } else {
        final err = jsonDecode(res.body);
        return {
          'success': false,
          'message': err['detail'] ?? 'Lỗi cập nhật trạng thái duyệt xe',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Không thể kết nối API: $e'};
    }
  }

  /// Gửi hình chụp chứng từ / sự cố gắn vào đơn hàng vận tải:
  /// photoType: 'pump_slip_before' | 'pump_slip' | 'weigh_slip' | 'delivery_slip' | 'breakdown' | 'repair'
  /// Mọi ảnh của tài xế đều kèm tọa độ GPS lúc chụp (gps_lat, gps_lng, gps_accuracy, gps_captured_at).
  static Future<Map<String, dynamic>?> submitOrderAttachment({
    required int orderId,
    required String photoType,
    required String photoBase64,
    String? note,
    double? tonnage,
    String? slipCode,
    String? location,
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracy,
    String? gpsCapturedAt,
    String? repairStatus,
  }) async {
    try {
      final body = <String, dynamic>{
        'photo_type': photoType,
        'photo_base64': photoBase64,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (tonnage != null) 'tonnage': tonnage,
        if (slipCode != null && slipCode.trim().isNotEmpty)
          'slip_code': slipCode.trim(),
        if (location != null && location.trim().isNotEmpty)
          'location': location.trim(),
        if (gpsLat != null) 'gps_lat': gpsLat,
        if (gpsLng != null) 'gps_lng': gpsLng,
        if (gpsAccuracy != null) 'gps_accuracy': gpsAccuracy,
        if (gpsCapturedAt != null) 'gps_captured_at': gpsCapturedAt,
        if (repairStatus != null && repairStatus.trim().isNotEmpty)
          'repair_status': repairStatus.trim(),
      };
      final res = await http
          .post(
            Uri.parse('$baseUrl/orders/$orderId/attachment'),
            headers: await _headers(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
