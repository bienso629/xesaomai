import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationHelper {
  static bool _hasRequested = false;

  /// Yêu cầu cấp quyền hiển thị thông báo khi mở ứng dụng trên thiết bị
  static Future<void> requestNotificationPermission() async {
    if (kIsWeb) return;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.notification.status;
        if (!status.isGranted) {
          await Permission.notification.request();
        }
      }
      _hasRequested = true;
    } catch (e) {
      debugPrint('Lỗi khi xin quyền thông báo: $e');
    }
  }

  /// Trạng thái đã xin quyền trong phiên chạy này
  static bool get hasRequested => _hasRequested;
}
