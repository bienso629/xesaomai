import 'package:flutter/material.dart';
import '../models/inspection_model.dart';

class CameraOverlayPainter extends CustomPainter {
  final InspectionStep step;
  final VehicleType vehicleType;

  CameraOverlayPainter({required this.step, required this.vehicleType});

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.55)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Vùng chụp trung tâm (Target box)
    final targetRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.88,
      height: size.height * 0.55,
    );

    // Vẽ nền mờ xung quanh ngoài targetRect
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(targetRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, backgroundPaint);

    // Vẽ viền targetRect
    canvas.drawRRect(
      RRect.fromRectAndRadius(targetRect, const Radius.circular(16)),
      borderPaint,
    );

    // Vẽ khung mẫu mô phỏng xe theo từng bước & chủng loại xe
    switch (step) {
      case InspectionStep.frontUndercarriage:
        _drawFrontUndercarriageGuideline(canvas, targetRect);
        break;
      case InspectionStep.rearUndercarriage:
        _drawRearUndercarriageGuideline(canvas, targetRect);
        break;
      case InspectionStep.leftFlank:
      case InspectionStep.rightFlank:
        _drawFlankGuideline(canvas, targetRect);
        break;
      case InspectionStep.dashboard:
        _drawDashboardGuideline(canvas, targetRect);
        break;
    }
  }

  void _drawFrontUndercarriageGuideline(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.yellowAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Khung mô phỏng cản trước & vị trí trục/bánh xe
    final axleY = rect.bottom - rect.height * 0.35;
    canvas.drawLine(
      Offset(rect.left + 30, axleY),
      Offset(rect.right - 30, axleY),
      paint,
    );

    // Khung bánh trái & bánh phải
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 20, axleY - 40, 50, 90),
        const Radius.circular(8),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.right - 70, axleY - 40, 50, 90),
        const Radius.circular(8),
      ),
      paint,
    );
  }

  void _drawRearUndercarriageGuideline(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Cụm cầu sau & nhíp
    final centerAxle = rect.center;
    canvas.drawCircle(centerAxle, 30, paint); // Bầu vi sai cầu sau
    canvas.drawLine(
      Offset(rect.left + 20, centerAxle.dy),
      Offset(rect.right - 20, centerAxle.dy),
      paint,
    );
  }

  void _drawFlankGuideline(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Dáng bồn / thùng và bánh xe đôi
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 30, rect.top + 20, rect.width - 60, rect.height * 0.5),
        const Radius.circular(20),
      ),
      paint,
    );

    // 2 Bánh xe hông
    canvas.drawCircle(Offset(rect.left + 80, rect.bottom - 45), 35, paint);
    canvas.drawCircle(Offset(rect.right - 80, rect.bottom - 45), 35, paint);
  }

  void _drawDashboardGuideline(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Khung đồng hồ ODO hiển thị số km
    final odoRect = Rect.fromCenter(
      center: rect.center,
      width: rect.width * 0.65,
      height: rect.height * 0.35,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(odoRect, const Radius.circular(10)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
