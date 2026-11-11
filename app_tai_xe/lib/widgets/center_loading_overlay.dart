import 'package:flutter/material.dart';

/// Khung hiển thị trạng thái Loading chuẩn ở chính giữa vùng hiển thị hoặc toàn màn hình.
/// Tuân thủ QUY_TAC_STYLE_APP.md: bo góc 4px (rounded-sm), chữ rõ ràng, đồng bộ toàn ứng dụng.
class CenterLoadingBox extends StatelessWidget {
  final String message;
  final String? subMessage;

  const CenterLoadingBox({
    super.key,
    this.message = 'Đang tải dữ liệu...',
    this.subMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 380),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 24,
              offset: Offset(0, 8),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.blue.shade800,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
            if (subMessage != null && subMessage!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bọc một cây giao diện và phủ lớp Loading ở chính giữa màn hình khi [isLoading] = true.
class CenterLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final String message;
  final String? subMessage;
  final Widget child;
  final Color barrierColor;

  const CenterLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Đang xử lý...',
    this.subMessage,
    this.barrierColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: ColoredBox(
                color: barrierColor,
                child: CenterLoadingBox(
                  message: message,
                  subMessage: subMessage,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
