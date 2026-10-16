import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/inspection_model.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';
import '../widgets/camera_overlay_painter.dart';
import 'breakdown_dialog.dart';

class CameraInspectionScreen extends StatefulWidget {
  const CameraInspectionScreen({super.key});

  @override
  State<CameraInspectionScreen> createState() => _CameraInspectionScreenState();
}

class _CameraInspectionScreenState extends State<CameraInspectionScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  // 'checking' | 'granted' | 'denied' | 'permanentlyDenied' | 'noCamera' | 'error'
  String _permissionState = 'checking';
  int _currentStepIndex = 0;
  bool _flashOn = true; // Mặc định bật cho 2 bước đầu (gầm trước, gầm sau)
  // Cờ ghi nhớ người dùng đã tự bật/tắt flash: khi đã tự chọn thì giữ nguyên
  // lựa chọn ở các bước tiếp theo, không áp lại mặc định của từng bước nữa.
  bool _userFlashOverride = false;
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
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndInitCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _kmController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Giải phóng camera khi app vào nền, mở lại khi quay về (kể cả sau khi cấp quyền trong Cài đặt)
    if (lifecycle == AppLifecycleState.inactive || lifecycle == AppLifecycleState.paused) {
      final c = _cameraController;
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
      c?.dispose();
    } else if (lifecycle == AppLifecycleState.resumed && _cameraController == null) {
      _requestPermissionAndInitCamera();
    }
  }

  Future<void> _requestPermissionAndInitCamera() async {
    if (mounted) setState(() => _permissionState = 'checking');
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied || status.isRestricted) {
      setState(() => _permissionState = 'permanentlyDenied');
      return;
    }
    if (!status.isGranted && !status.isLimited) {
      setState(() => _permissionState = 'denied');
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _permissionState = 'noCamera');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      await _applyFlash(controller);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
        _permissionState = 'granted';
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _permissionState = e.code == 'CameraAccessDenied' ? 'denied' : 'error');
    }
  }

  Future<void> _applyFlash([CameraController? c]) async {
    final controller = c ?? _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(_flashOn ? FlashMode.always : FlashMode.off);
    } catch (_) {}
  }

  Future<void> _takePicture() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      // Ép áp dụng lại chế độ đèn flash NGAY TRƯỚC khi bấm máy. Một số thiết bị
      // Android (Vivo, Oppo, Xiaomi...) tự đặt lại flash mode sau mỗi lần chụp
      // khiến lệnh tắt flash bị bỏ qua, nên phải gọi lại trước mỗi lần chụp.
      await _applyFlash(controller);
      final file = await controller.takePicture();
      // Áp dụng lại sau khi chụp để đèn preview khớp với chế độ đã chọn.
      await _applyFlash(controller);
      _onStepCaptured(file.path);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade700, content: Text("Chụp ảnh thất bại: ${e.description ?? e.code}")),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _onStepCaptured(String capturedPath) {
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
      imagePath: capturedPath,
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
        // Chỉ áp flash mặc định của bước mới khi người dùng chưa tự chọn.
        if (!_userFlashOverride) {
          _flashOn = _stepsConfig[_currentStepIndex]['flashDefault'];
        }
      });
      _applyFlash();
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
                  Text("Xác nhận số km táp lô", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("OCR tự động nhận diện từ ảnh táp lô:", style: TextStyle(fontSize: 15)),
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
                    const Text("Tài xế xác nhận / sửa đổi:", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                              style: const TextStyle(fontSize: 13.5)),
                          Text("Độ lệch: ${diff.toStringAsFixed(1)} km",
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: isFlagged ? Colors.red : Colors.green)),
                          if (isFlagged)
                            const Padding(
                              padding: EdgeInsets.only(top: 4.0),
                              child: Text(
                                "Lệch > 20 km! Hệ thống sẽ gắn CỜ BẤT THƯỜNG chuyển Điều phối/Kỹ thuật xem xét.",
                                style: TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.w600),
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
                  onPressed: () async {
                    final confirmed = double.tryParse(_kmController.text) ?? _mockOcrKm;
                    state.completeDailyInspection(
                      photos: _capturedPhotos,
                      ocrKm: _mockOcrKm,
                      confirmedKm: confirmed,
                      isKmFlagged: (confirmed - _previousDayGpsKm).abs() > 20.0,
                    );

                    // Ghi lịch sử kiểm tra xe 5 ảnh lên Backend API
                    final String todayStr = DateTime.now().toIso8601String().substring(0, 10);
                    final String img1 = _capturedPhotos.isNotEmpty ? _capturedPhotos[0].imagePath : '';
                    final String img2 = _capturedPhotos.length > 1 ? _capturedPhotos[1].imagePath : '';
                    final String img3 = _capturedPhotos.length > 2 ? _capturedPhotos[2].imagePath : '';
                    final String img4 = _capturedPhotos.length > 3 ? _capturedPhotos[3].imagePath : '';
                    final String img5 = _capturedPhotos.length > 4 ? _capturedPhotos[4].imagePath : '';

                    AdminService.submitInspection(
                      checkDate: todayStr,
                      plateNumber: state.selectedPlate,
                      imgFront: img1,
                      imgRear: img2,
                      imgLeft: img3,
                      imgRight: img4,
                      imgDashboard: img5,
                      gpsLat: _mockLat,
                      gpsLng: _mockLng,
                      gpsAccuracy: _mockAccuracy,
                      deviceId: "DEV-VIVO-Y21-9982",
                      kmOcr: _mockOcrKm,
                      kmConfirmed: confirmed,
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

  Widget _buildCameraPreview() {
    final controller = _cameraController;
    if (_isCameraReady && controller != null && controller.value.isInitialized) {
      // Phủ kín khung hình, giữ đúng tỉ lệ ống kính
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1080,
            height: controller.value.previewSize?.width ?? 1920,
            child: CameraPreview(controller),
          ),
        ),
      );
    }

    String message;
    Widget? action;
    switch (_permissionState) {
      case 'denied':
        message = "Ứng dụng chưa được cấp quyền Camera.\nVui lòng cho phép để chụp ảnh kiểm tra xe.";
        action = _buildPermissionButton("Cấp quyền Camera", _requestPermissionAndInitCamera);
        break;
      case 'permanentlyDenied':
        message = "Quyền Camera đã bị từ chối.\nVui lòng mở Cài đặt và bật quyền Camera cho ứng dụng.";
        action = _buildPermissionButton("Mở Cài đặt", () => openAppSettings());
        break;
      case 'noCamera':
        message = "Không tìm thấy camera trên thiết bị này.";
        break;
      case 'error':
        message = "Không khởi động được camera.";
        action = _buildPermissionButton("Thử lại", _requestPermissionAndInitCamera);
        break;
      default:
        message = "Đang khởi động camera...";
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_permissionState == 'checking')
            const CircularProgressIndicator(color: Colors.white70)
          else
            const Icon(Icons.no_photography_outlined, size: 56, color: Colors.white54),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }

  Widget _buildPermissionButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
              setState(() {
                _flashOn = !_flashOn;
                _userFlashOverride = true;
              });
              _applyFlash();
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
          // Ống kính camera thật (xem trước trực tiếp)
          Positioned.fill(child: _buildCameraPreview()),

          // Custom Overlay theo từng bước & loại xe
          Positioned.fill(
            child: CustomPaint(
              painter: CameraOverlayPainter(step: step, vehicleType: state.selectedVehicleType),
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

          // Cụm dưới cùng: Watermark (Biển số, Giờ, GPS) + thanh nút chụp
          // xếp dọc để watermark luôn nằm trong dải tối BÊN DƯỚI khung ngắm,
          // không đè lên viền vàng hay hình mẫu xe nữa
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Biển số: ${state.selectedPlate} | TX: ${state.currentDriverId}",
                            style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text("Giờ: ${DateTime.now().toLocal().toString().substring(0, 19)} (UTC+7)",
                            style: const TextStyle(color: Colors.white70, fontSize: 10)),
                        Text("GPS: $_mockLat, $_mockLng (±${_mockAccuracy}m) | DEV-VIVO-Y21-9982",
                            style: const TextStyle(color: Colors.white70, fontSize: 9)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
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
                  onTap: _isCameraReady && !_isCapturing ? _takePicture : null,
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
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isCameraReady ? Colors.white : Colors.white24,
                        ),
                        child: _isCapturing
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black54),
                              )
                            : null,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
