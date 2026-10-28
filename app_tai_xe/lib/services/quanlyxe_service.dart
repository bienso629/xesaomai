import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/quanlyxe_model.dart';
import 'auth_service.dart';

class QuanLyXeService {
  static const String apiKey = '7GDc6Vk0KdTGBx6yRKYZGM6eQKHThzA4';
  static const String baseUrl = 'https://client-api.quanlyxe.vn/v3/tracking';

  /// Lấy danh sách các xe trên Vietmap (quanlyxe.vn)
  static Future<List<QuanLyXeInfo>> fetchVehicles() async {
    try {
      final url = Uri.parse('$baseUrl/getvehicles?apikey=$apiKey');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final list = decoded['Data'] as List<dynamic>? ?? [];
        return list.map((item) => QuanLyXeInfo.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('QuanLyXeService fetchVehicles error: $e');
    }
    return [];
  }

  /// Lấy trạng thái GPS, tốc độ, vị trí thực tế của 1 xe theo biển số
  static Future<QuanLyXeStatus?> fetchVehicleStatus(String plate) async {
    try {
      final url = Uri.parse('$baseUrl/GetVehicleStatus?plate=${Uri.encodeComponent(plate)}&apikey=$apiKey');
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final list = decoded['Data'] as List<dynamic>? ?? [];
        if (list.isNotEmpty) {
          return QuanLyXeStatus.fromJson(list.first as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('QuanLyXeService fetchVehicleStatus error: $e');
    }
    return null;
  }

  /// Lấy trạng thái GPS toàn đội xe gộp chính xác từ 2 dịch vụ Vietmap và Bình Anh qua Backend API
  static Future<Map<String, QuanLyXeStatus>> fetchFleetGpsStatusFromServer({bool refresh = false}) async {
    final Map<String, QuanLyXeStatus> results = {};
    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse('${ApiConfig.apiV1}/fleet/gps-status${refresh ? '?refresh=true' : ''}');
      final headers = <String, String>{
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 18));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final list = decoded['Data'] as List<dynamic>? ?? [];
        for (final raw in list) {
          if (raw is Map<String, dynamic>) {
            final status = QuanLyXeStatus.fromJson(raw);
            if (status.plate.isNotEmpty) {
              results[status.plate] = status;
            }
          }
        }
        return results;
      } else if (response.statusCode == 401) {
        // Phiên đăng nhập hết hạn: đăng xuất bắt buộc và dừng ngay,
        // không chạy fallback vì các request sau cũng sẽ dính 401.
        debugPrint('fetchFleetGpsStatusFromServer HTTP 401: phiên hết hạn');
        await AuthService.handleUnauthorizedResponse();
        return results;
      } else {
        debugPrint('fetchFleetGpsStatusFromServer HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('QuanLyXeService fetchFleetGpsStatusFromServer error: $e');
    }
    // Server cũ chưa có endpoint hợp nhất hoặc có lỗi: gộp Vietmap trực tiếp + Bình Anh riêng lẻ
    if (results.isEmpty) {
      return _fetchMergedFallback();
    }
    return results;
  }

  /// Định dạng biển số Bình Anh: 50H16627 -> 50H-166.27 (khớp kiểu biển trong Đội xe)
  static String _formatBinhanhPlate(String plate) {
    final p = plate.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final match = RegExp(r'^(\d{2})([A-Z])(\d{5})$').firstMatch(p);
    if (match != null) {
      final digits = match.group(3)!;
      return '${match.group(1)}${match.group(2)}-${digits.substring(0, 3)}.${digits.substring(3)}';
    }
    return p;
  }

  /// Lấy trạng thái GPS của xe Bình Anh qua endpoint riêng lẻ trên Backend
  /// (dùng khi server chưa có endpoint hợp nhất /fleet/gps-status).
  static Future<Map<String, QuanLyXeStatus>> fetchBinhanhStatusesFromServer() async {
    final Map<String, QuanLyXeStatus> results = {};
    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse('${ApiConfig.apiV1}/binhanh/tracking');
      final headers = <String, String>{
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 18));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final list = decoded['vehicles'] as List<dynamic>? ?? [];
        for (final raw in list) {
          if (raw is! Map<String, dynamic>) continue;
          final status = _binhanhVehicleToStatus(raw);
          if (status != null && status.plate.isNotEmpty) {
            results[status.plate] = status;
          }
        }
      } else if (response.statusCode == 401) {
        // Phiên đăng nhập hết hạn: đăng xuất bắt buộc về màn hình Đăng nhập
        debugPrint('fetchBinhanhStatusesFromServer HTTP 401: phiên hết hạn');
        await AuthService.handleUnauthorizedResponse();
      } else {
        debugPrint('fetchBinhanhStatusesFromServer HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('QuanLyXeService fetchBinhanhStatusesFromServer error: $e');
    }
    return results;
  }

  /// Chuyển dữ liệu xe Bình Anh (format /binhanh/tracking) sang QuanLyXeStatus.
  static QuanLyXeStatus? _binhanhVehicleToStatus(Map<String, dynamic> raw) {
    final String providerPlate = (raw['provider_plate'] ?? '').toString().trim();
    String plate = (raw['fleet_plate'] ?? '').toString().trim();
    if (plate.isEmpty) {
      plate = _formatBinhanhPlate(providerPlate);
    }
    final double lat = (raw['latitude'] as num?)?.toDouble() ?? 0.0;
    final double lng = (raw['longitude'] as num?)?.toDouble() ?? 0.0;
    if (plate.isEmpty || (lat == 0.0 && lng == 0.0)) {
      return null;
    }
    final int state = (raw['state'] as num?)?.toInt() ?? 0;
    final double spd = (raw['speed'] as num?)?.toDouble() ?? 0.0;
    final double direction = (raw['direction'] as num?)?.toDouble() ?? 0.0;
    final double heading = (direction >= 0 && direction <= 8) ? direction * 45.0 : direction;
    DateTime? gpsTime;
    final String utcTime = (raw['utc_time'] ?? '').toString().trim();
    final String localTime = (raw['local_time'] ?? '').toString().trim();
    String? timeStr;
    if (utcTime.isNotEmpty) {
      timeStr = (utcTime.endsWith('Z') || utcTime.contains('+')) ? utcTime : '${utcTime}Z';
    } else if (localTime.isNotEmpty) {
      timeStr = localTime;
    }
    if (timeStr != null) {
      gpsTime = DateTime.tryParse(timeStr);
    }
    final String driver = (raw['driver_name'] ?? '').toString().trim();
    final int odo = (raw['total_km_today'] as num?)?.toInt() ?? 0;
    return QuanLyXeStatus(
      id: (raw['vehicle_id'] as num?)?.toInt() ?? 0,
      plate: plate,
      latitude: lat,
      longitude: lng,
      speed: spd,
      driverName: driver.isNotEmpty ? driver : 'Chưa gắn thẻ',
      address: (raw['address'] ?? '').toString(),
      isAccOn: state == 1 || state == 2 || state == 4 || spd > 0,
      odoKm: odo,
      gpsTime: gpsTime,
      heading: heading,
      status: state,
      satellite: 0,
      gpsProvider: 'binhanh',
      stateLabel: (raw['state_label'] ?? '').toString(),
    );
  }

  /// Gộp dữ liệu khi server cũ chưa có endpoint hợp nhất:
  /// Vietmap gọi trực tiếp + Bình Anh qua endpoint riêng lẻ của Backend.
  static Future<Map<String, QuanLyXeStatus>> _fetchMergedFallback() async {
    final Map<String, QuanLyXeStatus> merged = {};
    // 1. Vietmap gọi trực tiếp
    try {
      final vmVehicles = await fetchVehicles();
      final futures = vmVehicles.map((v) async {
        final status = await fetchVehicleStatus(v.plate);
        if (status != null) {
          merged[v.plate] = status;
        }
      });
      await Future.wait(futures);
    } catch (e) {
      debugPrint('QuanLyXeService _fetchMergedFallback vietmap error: $e');
    }
    // 2. Bình Anh qua Backend (không ghi đè xe đã có của Vietmap)
    // Bỏ qua nếu không còn token (đã bị đăng xuất do phiên hết hạn)
    final baToken = await AuthService.getToken();
    if (baToken == null || baToken.isEmpty) {
      return merged;
    }
    try {
      final baStatuses = await fetchBinhanhStatusesFromServer();
      baStatuses.forEach((plate, status) {
        if (!merged.containsKey(plate)) {
          merged[plate] = status;
        }
      });
    } catch (e) {
      debugPrint('QuanLyXeService _fetchMergedFallback binhanh error: $e');
    }
    return merged;
  }

  /// Lấy trạng thái GPS của toàn bộ đội xe (Vietmap + Bình Anh)
  static Future<Map<String, QuanLyXeStatus>> fetchAllVehiclesStatus({
    List<String>? targetPlates,
    bool forceRefresh = false,
  }) async {
    // Ưu tiên lấy dữ liệu chuẩn hợp nhất Vietmap + Bình Anh từ Backend
    if (targetPlates == null) {
      final serverResults = await fetchFleetGpsStatusFromServer(refresh: forceRefresh);
      if (serverResults.isNotEmpty) {
        return serverResults;
      }
      // Server cũ chưa có endpoint hợp nhất: gộp Vietmap trực tiếp + Bình Anh riêng lẻ
      final mergedResults = await _fetchMergedFallback();
      if (mergedResults.isNotEmpty) {
        return mergedResults;
      }
    }

    // Fallback trực tiếp Vietmap nếu không kết nối được Backend
    List<String> platesToFetch = targetPlates ?? [];
    if (platesToFetch.isEmpty) {
      final vmVehicles = await fetchVehicles();
      platesToFetch = vmVehicles.map((v) => v.plate).where((p) => p.isNotEmpty).toList();
    }
    final Map<String, QuanLyXeStatus> results = {};
    final futures = platesToFetch.map((plate) async {
      final status = await fetchVehicleStatus(plate);
      if (status != null) {
        results[plate] = status;
      }
    });
    await Future.wait(futures);
    return results;
  }
}
