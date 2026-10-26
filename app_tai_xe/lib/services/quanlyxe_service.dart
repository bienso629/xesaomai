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
      } else {
        debugPrint('fetchFleetGpsStatusFromServer HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('QuanLyXeService fetchFleetGpsStatusFromServer error: $e');
    }
    return results;
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
