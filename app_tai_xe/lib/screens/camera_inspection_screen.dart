import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/inspection_model.dart';
import '../services/app_state.dart';
import '../widgets/camera_overlay_painter.dart';
import 'breakdown_dialog.dart';

class CameraInspectionScreen extends StatefulWidget {
  const CameraInspectionScreen({super.key});

  @override
  State<CameraInspectionScreen> createState() => _CameraInspectionScreenState();
}

class _CameraInspectionScreenState extends State<CameraInspectionScreen> {
  int _currentStepIndex = 0;
  bool _flashOn = true; // Mặc định bật cho 2 bước đầu (gầm trước, gầm sau)
  final List<PhotoMetadata> _capturedPhotos = [];

  // Giả lập GPS máy
  final double _mockLat = 10.762622;
  final double _mockLng = 106.660172;
  final double _mockAccuracy = 4.2;

  final TextEditingController _kmController = TextEditingController();
  final double _mockOcrKm = 124580.0;
  final double _previousDayGpsKm = 124550.0; // Chênh lệch 30 km (> 20 km -> Gắn cờ)

  final List<Map<String, dynamic>> _stepsConfig = [
    {
      'step': InspectionStep.frontUndercarriage,
      'title': "1. Gầm trước",
      'guide': "Căn chỉnh cản trước, trục lái và 2 bánh xe trước vào khung viền vàng.",
      'flashDefault': true,
    },
    {
      'step': InspectionStep.rearUndercarriage,
      'title': "2. Gầm sau",
      'guide': "Căn bầu vi sai và cụm nhíp cầu sau vào giữa tâm khung.",
      'flashDefault': true,
    },
    {
      'step': InspectionStep.leftFlank,
      'title': "3. Hông trái",
      'guide': "Chụp dọc toàn bộ sườn bên trái xe bao gồm dàn lốp và thân bồn.",
      'flashDefault': false,
    },
    {
      'step': InspectionStep.rightFlank,
      'title': "4. Hông phải",
      'guide': "Chụp dọc toàn bộ sườn bên phải xe bao gồm dàn lốp và bình nhiên liệu.",
      'flashDefault': false,
    },
    {
      'step': InspectionStep.dashboard,
      'title': "5. Táp lô (Đồng hồ ODO)",
      'guide': "Căn rõ ràng dãy số hiển thị km hành trình trên đồng hồ vào khung.",
      'flashDefault': false,
    },
  ];

  @override
  void initState() {
    super.initState();
    _flashOn = _stepsConfig[_currentStepIndex]['flashDefault'];
    _kmController.text = _mockOcrKm.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _kmController.dispose();
    super.dispose();
  }

  void _onStepCaptured() {
    final state = context.read<AppState>();
    final currentConfig = _stepsConfig[_currentStepIndex];

    // Giả lập kiểm tra chất lượng ảnh (độ sáng, độ nét, bánh xe)
    final randomQualityCheck = Random().nextDouble();
    if (randomQualityCheck < 0.05) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text("Ảnh quá tối hoặc không thấy bánh xe trong khung! Vui lòng chụp lại."),
        ),
      );
      return;
    }

    // Tạo metadata cho ảnh
    bool hasAnomaly = false;
    String? reason;
    if (_currentStepIndex == 0) {
      hasAnomaly = true;
      reason = "Phát hiện vệt ướt nghi rò rỉ dầu dưới gầm trước (so với hôm qua)";
    }

    final metadata = PhotoMetadata(
      stepName: currentConfig['title'],
      imagePath: "storage/inspection/${state.selectedPlate}_step_${_currentStepIndex + 1}.jpg",
      timestamp: DateTime.now(),
      latitude: _mockLat,
      longitude: _mockLng,
      accuracy: _mockAccuracy,
      vehiclePlate: state.selectedPlate,
      driverId: state.currentDriverId,
      deviceId: "DEV-VIVO-Y21-9982",
      hasFlash: _flashOn,
      flagAnomaly: hasAnomaly,
      anomalyReason: reason,
    );

    _capturedPhotos.add(metadata);

    if (_currentStepIndex < 4) {
      setState(() {
        _currentStepIndex++;
        _flashOn = _stepsConfig[_currentStepIndex]['flashDefault'];
      });
    } else {
      _showOcrConfirmationDialog();
    }
  }

  void _showOcrConfirmationDialog() {
    final state = context.read<AppState>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final double confirmedVal = double.tryParse(_kmController.text) ?? _mockOcrKm;
            final double diff = (confirmedVal - _previousDayGpsKm).abs();
            final bool isFlagged = diff > 20.0;

            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.speed, color: Colors.blueAccent),
                  SizedBox(width: 8),
                  Text("Xác nhận số km táp lô", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("OCR tự động nhận diện từ ảnh táp lô:"),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Số km đọc được:", style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            "${_mockOcrKm.toStringAsFixed(0)} km",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text("Tài xế xác nhận / sửa đổi:", style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _kmController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixText: "km",
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isFlagged ? Colors.amber.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isFlagged ? Colors.amber : Colors.green),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Km GPS chốt ngày trước: ${_previousDayGpsKm.toStringAsFixed(0)} km",
                              style: const TextStyle(fontSize: 12)),
                          Text("Độ lệch: ${diff.toStringAsFixed(1)} km",
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isFlagged ? Colors.red : Colors.green)),
                          if (isFlagged)
                            const Padding(
                              padding: EdgeInsets.only(top: 4.0),
                              child: Text(
                                "Lệch > 20 km! Hệ thống sẽ gắn CỜ BẤT THƯỜNG chuyển Điều phối/Kỹ thuật xem xét.",
                                style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () {
                    final confirmed = double.tryParse(_kmController.text) ?? _mockOcrKm;
                    state.completeDailyInspection(
                      photos: _capturedPhotos,
                      ocrKm: _mockOcrKm,
                      confirmedKm: confirmed,
                      isKmFlagged: (confirmed - _previousDayGpsKm).abs() > 20.0,
                    );
                    Navigator.of(ctx).pop(); // Đóng dialog
                    Navigator.of(context).pop(); // Đóng camera screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.green,
                        content: Text("Hoàn thành kiểm tra đầu ngày! Xe đủ điều kiện nhận chuyến."),
                      ),
                    );
                  },
                  child: const Text("Hoàn tất kiểm tra", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentConfig = _stepsConfig[_currentStepIndex];
    final step = currentConfig['step'] as InspectionStep;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentConfig['title'], style: const TextStyle(fontSize: 17, color: Colors.white)),
            Text(
              "Xe: ${state.selectedPlate} (${state.selectedVehicleType.name.toUpperCase()})",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "Bật/Tắt Flash",
            icon: Icon(
              _flashOn ? Icons.flash_on : Icons.flash_off,
              color: _flashOn ? Colors.yellowAccent : Colors.white,
            ),
            onPressed: () {
              setState(() => _flashOn = !_flashOn);
            },
          ),
          IconButton(
            tooltip: "Báo hỏng khẩn cấp",
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrangeAccent),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => const BreakdownDialog(),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Khung nhìn camera giả lập (mô phỏng ống kính)
          Positioned.fill(
            child: Container(
              color: Colors.blueGrey.shade900,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_car_filled, size: 90, color: Colors.white.withOpacity(0.12)),
                    const SizedBox(height: 12),
                    Text(
                      "[ Ống kính Camera nội bộ App ]\n(Chặn chọn ảnh từ thư viện máy)",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Custom Overlay theo từng bước & loại xe
          Positioned.fill(
            child: CustomPaint(
              painter: CameraOverlayPainter(step: step, vehicleType: state.selectedVehicleType),
            ),
          ),

          // Watermark hiển thị trực tiếp trên màn hình camera
          Positioned(
            left: 20,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Biển số: ${state.selectedPlate} | TX: ${state.currentDriverId}",
                      style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text("Giờ: ${DateTime.now().toLocal().toString().substring(0, 19)} (UTC+7)",
                      style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  Text("Tọa độ GPS: $_mockLat, $_mockLng (±${_mockAccuracy}m)",
                      style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  const Text("Thiết bị: DEV-VIVO-Y21-9982 (Watermark gốc)",
                      style: TextStyle(color: Colors.white38, fontSize: 9)),
                ],
              ),
            ),
          ),

          // Hướng dẫn góc chụp
          Positioned(
            top: 12,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amberAccent.withOpacity(0.5)),
              ),
              child: Text(
                currentConfig['guide'],
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),

          // Thanh điều khiển chụp ảnh phía dưới
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Số bước
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "${_currentStepIndex + 1}/5",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),

                // Nút chụp tròn
                GestureDetector(
                  onTap: _onStepCaptured,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: Center(
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                // Nút Báo hỏng nhanh
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => const BreakdownDialog(),
                    );
                  },
                  icon: const Icon(Icons.build, color: Colors.orangeAccent, size: 28),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
