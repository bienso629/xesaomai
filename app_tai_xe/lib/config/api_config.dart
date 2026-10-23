/// Cấu hình địa chỉ máy chủ backend dùng chung cho toàn app.
///
/// Mặc định trỏ tới server thật. Muốn thử với backend chạy ở máy (local):
///   flutter run --dart-define=API_HOST=http://localhost:1133
class ApiConfig {
  ApiConfig._();

  /// Gốc máy chủ, không có dấu `/` ở cuối (dùng để ghép đường dẫn ảnh /uploads/...).
  static const String host = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://saomai-api.type.vn',
  );

  /// Gốc API phiên bản 1.
  static const String apiV1 = '$host/api/v1';

  /// Đang chạy với backend local hay không.
  static const bool isLocal = host != 'https://saomai-api.type.vn';
}
