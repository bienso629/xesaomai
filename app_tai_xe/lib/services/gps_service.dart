import 'package:geolocator/geolocator.dart';

/// Một lần lấy tọa độ GPS gắn với một tấm ảnh.
class GpsFix {
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime capturedAt;

  const GpsFix({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.capturedAt,
  });

  String get display =>
      "${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)} (±${accuracy.toStringAsFixed(0)}m)";

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'captured_at': capturedAt.toIso8601String(),
      };
}

/// Lỗi lấy GPS kèm thông báo tiếng Việt để hiện cho tài xế.
class GpsException implements Exception {
  final String message;

  /// true khi người dùng đã chặn vĩnh viễn, cần mở Cài đặt để cấp lại quyền.
  final bool needsAppSettings;

  /// true khi dịch vụ định vị của máy đang tắt.
  final bool needsLocationSettings;

  const GpsException(
    this.message, {
    this.needsAppSettings = false,
    this.needsLocationSettings = false,
  });

  @override
  String toString() => message;
}

/// Lấy tọa độ thực tế của thiết bị. Mọi hình chụp của tài xế bắt buộc phải có GPS,
/// nên hàm này ném [GpsException] thay vì trả về tọa độ giả khi thất bại.
class GpsService {
  static Future<GpsFix> getCurrentFix({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const GpsException(
        "Định vị (GPS) của máy đang tắt. Vui lòng bật Vị trí rồi thử lại.",
        needsLocationSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const GpsException(
        "Ứng dụng chưa được cấp quyền Vị trí. Ảnh bắt buộc phải có GPS mới gửi được.",
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const GpsException(
        "Quyền Vị trí đã bị chặn. Vui lòng mở Cài đặt ứng dụng và cho phép Vị trí.",
        needsAppSettings: true,
      );
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return GpsFix(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        capturedAt: DateTime.now(),
      );
    } catch (_) {
      throw const GpsException(
        "Không lấy được tọa độ GPS. Vui lòng ra chỗ thoáng, chờ vài giây rồi thử lại.",
      );
    }
  }

  static Future<void> openSettingsFor(GpsException e) async {
    if (e.needsLocationSettings) {
      await Geolocator.openLocationSettings();
    } else if (e.needsAppSettings) {
      await Geolocator.openAppSettings();
    }
  }
}
