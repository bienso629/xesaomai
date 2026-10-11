import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/quanlyxe_model.dart';

class QuanLyXeService {
  static const String apiKey = '7GDc6Vk0KdTGBx6yRKYZGM6eQKHThzA4';
  static const String baseUrl = 'https://client-api.quanlyxe.vn/v3/tracking';

  /// Lấy danh sách tất cả các xe đang quản lý trên Bình Anh GPS
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

  /// Lấy trạng thái GPS, tốc độ, vị trí thực tế của xe theo biển số
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

  /// Danh sách 15 xe thực tế chuẩn trong hệ thống từ Vietmap tracking API
  static const List<String> allFleetPlates = [
    "50E-477.23",
    "50E-480.24",
    "50E-889.50",
    "50H-446.76",
    "50H-449.66",
    "50H-457.21",
    "50H-538.61",
    "50H-540.41",
    "50H-882.60",
    "50H-891.21",
    "50H-919.49",
    "50H-919.51",
    "50H914.39",
    "51D-477.41",
    "51D-477.61"
  ];

  /// Lấy trạng thái GPS của tất cả các xe
  static Future<Map<String, QuanLyXeStatus>> fetchAllVehiclesStatus({List<String>? targetPlates}) async {
    final platesToFetch = targetPlates ?? allFleetPlates;
    final Map<String, QuanLyXeStatus> results = {};

    final futures = platesToFetch.map((plate) async {
      final status = await fetchVehicleStatus(plate);
      if (status != null && status.latitude > 0 && status.longitude > 0) {
        results[plate] = status;
      }
    });

    await Future.wait(futures);
    return results;
  }
}
