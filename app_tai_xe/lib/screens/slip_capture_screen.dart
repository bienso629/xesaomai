import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';
import '../services/gps_service.dart';

/// Màn hình chụp ảnh chứng từ & sự cố gắn vào Đơn hàng vận tải:
/// - 'pump_before'   : Ảnh bơm hàng TRƯỚC KHI BƠM (tài khoản Tài xế chụp, bắt buộc)
/// - 'weigh'         : Phiếu cân (tài khoản Tài xế chụp ở Bước 2)
/// - 'arrival'       : Ảnh Đến điểm giao (tài khoản Tài xế chụp ở Bước 3, kèm GPS)
/// - 'delivery'      : Phiếu giao hàng (tài khoản Tài xế chụp ở Bước 4)
/// - 'breakdown'     : Báo hỏng xe trong lúc vận chuyển (tài khoản Tài xế chụp)
/// - 'repair'        : Báo cáo tình trạng sửa chữa xe (tài khoản Kỹ thuật chụp)
///
/// Bo góc 4px theo QUY_TAC_STYLE_APP.md, nút bấm chuẩn 30-36px.
class SlipCaptureScreen extends StatefulWidget {
  const SlipCaptureScreen({
    super.key,
    required this.slipType,
    this.orderId,
    this.orderCode,
    this.vehiclePlate,
  });

  final String slipType;
  final int? orderId;
  final String? orderCode;
  final String? vehiclePlate;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String slipType,
    int? orderId,
    String? orderCode,
    String? vehiclePlate,
  }) {
    return Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SlipCaptureScreen(
          slipType: slipType,
          orderId: orderId,
          orderCode: orderCode,
          vehiclePlate: vehiclePlate,
        ),
      ),
    );
  }

  @override
  State<SlipCaptureScreen> createState() => _SlipCaptureScreenState();
}

class _SlipCaptureScreenState extends State<SlipCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isSubmitting = false;
  String _permissionState = 'checking';
  String? _capturedPath;
  bool _flashOn = false;

  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _tonnageController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  String _repairStatus = 'fixed';

  String get _normalizedType {
    switch (widget.slipType) {
      case 'pump_before':
      case 'pump_slip_before':
        return 'pump_slip_before';
      case 'weigh':
      case 'weigh_slip':
        return 'weigh_slip';
      case 'arrival':
      case 'arrival_photo':
        return 'arrival_photo';
      case 'delivery':
      case 'delivery_slip':
        return 'delivery_slip';
      case 'breakdown':
        return 'breakdown';
      case 'repair':
        return 'repair';
      default:
        return widget.slipType;
    }
  }

  String get _screenTitle {
    switch (_normalizedType) {
      case 'pump_slip_before':
        return "Chụp Ảnh Bơm Hàng - Trước Khi Bơm";
      case 'weigh_slip':
        return "Chụp Phiếu Cân (Bước 2)";
      case 'arrival_photo':
        return "Chụp Ảnh Đến Điểm Giao Hàng (Bước 3)";
      case 'delivery_slip':
        return "Chụp Phiếu Giao Hàng (Bước 4)";
      case 'breakdown':
        return "Chụp Ảnh & Báo Hỏng Xe";
      case 'repair':
        return "Chụp Ảnh Báo Cáo Sửa Chữa Xe";
      default:
        return "Chụp Ảnh Chứng Từ";
    }
  }

  String get _guideText {
    switch (_normalizedType) {
      case 'pump_slip_before':
        return "Căn chỉnh đồng hồ cây dầu / vòi bơm TRƯỚC KHI BƠM vào khung (hiển thị số 0 hoặc số ban đầu).";
      case 'weigh_slip':
        return "Căn chỉnh giấy Phiếu cân vào khung, đảm bảo đọc rõ khối lượng và mã lệnh.";
      case 'arrival_photo':
        return "Chụp rõ cổng/biển số/hiện trạng xe khi xe ĐÃ ĐẾN ĐIỂM GIAO HÀNG (kèm tọa độ GPS tự động).";
      case 'delivery_slip':
        return "Căn chỉnh Phiếu giao hàng (biên bản giao nhận) vào khung, đảm bảo rõ chữ ký và khối lượng.";
      case 'breakdown':
        return "Chụp rõ vị trí/bộ phận xe gặp sự cố hỏng hóc trong quá trình vận chuyển.";
      case 'repair':
        return "Chụp rõ hiện trạng bộ phận xe sau khi kiểm tra / khắc phục sửa chữa.";
      default:
        return "Căn chỉnh hình chụp rõ nét vào khung.";
    }
  }

  /// Tọa độ GPS lấy NGAY lúc bấm chụp. Bắt buộc phải có mới cho gửi ảnh.
  GpsFix? _gpsFix;
  bool _isLocating = false;
  GpsException? _gpsError;

  Future<void> _captureGpsFix() async {
    setState(() {
      _isLocating = true;
      _gpsError = null;
      _gpsFix = null;
    });
    try {
      final fix = await GpsService.getCurrentFix();
      if (mounted) setState(() => _gpsFix = fix);
    } on GpsException catch (e) {
      if (mounted) setState(() => _gpsError = e);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndInitCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _noteController.dispose();
    _tonnageController.dispose();
    _codeController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.inactive ||
        lifecycle == AppLifecycleState.paused) {
      final c = _cameraController;
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
      c?.dispose();
    } else if (lifecycle == AppLifecycleState.resumed &&
        _cameraController == null) {
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
      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isCameraReady = true;
        _permissionState = 'granted';
      });
    } on CameraException {
      if (mounted) setState(() => _permissionState = 'error');
    }
  }

  Future<void> _takePicture() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);
    try {
      try {
        await controller.setFlashMode(
          _flashOn ? FlashMode.always : FlashMode.off,
        );
      } catch (_) {}
      final file = await controller.takePicture();
      if (!mounted) return;
      setState(() => _capturedPath = file.path);
      _captureGpsFix();
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text("Chụp ảnh thất bại: ${e.description ?? e.code}"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _confirmSubmit() async {
    final path = _capturedPath;
    if (path == null || _isSubmitting) return;

    if (_normalizedType == 'breakdown' &&
        _noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: const Text("Vui lòng nhập mô tả tình trạng hỏng xe!"),
        ),
      );
      return;
    }

    final gps = _gpsFix;
    if (gps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text(
            _isLocating
                ? "Đang lấy tọa độ GPS, vui lòng chờ vài giây..."
                : "Ảnh chưa có tọa độ GPS. Bấm \"Lấy lại GPS\" rồi gửi lại.",
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final state = context.read<AppState>();
    final now = DateTime.now();
    final int? targetOrderId = widget.orderId ?? state.currentTrip?.orderId;

    Map<String, dynamic>? updatedOrder;
    try {
      final bytes = await File(path).readAsBytes();
      final b64 = "data:image/jpeg;base64,${base64Encode(bytes)}";
      final tonnageVal = double.tryParse(
        _tonnageController.text.trim().replaceAll(',', '.'),
      );

      if (targetOrderId != null) {
        final res = await AdminService.submitOrderAttachment(
          orderId: targetOrderId,
          photoType: _normalizedType,
          photoBase64: b64,
          note: _noteController.text.trim(),
          tonnage: tonnageVal,
          slipCode: _codeController.text.trim(),
          location: _locationController.text.trim(),
          gpsLat: gps.lat,
          gpsLng: gps.lng,
          gpsAccuracy: gps.accuracy,
          gpsCapturedAt: gps.capturedAt.toIso8601String(),
          repairStatus: _normalizedType == 'repair' ? _repairStatus : null,
        );
        if (res == null || res.containsKey('_error')) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            final errorMsg = res != null && res.containsKey('_error')
                ? res['_error'].toString()
                : "Không thể tải ảnh phiếu lên máy chủ! Vui lòng kiểm tra kết nối mạng và thử lại.";
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: Colors.red.shade700,
                content: Text(errorMsg),
              ),
            );
          }
          return;
        }
        updatedOrder = res;
      }

      final remoteUrl = updatedOrder != null
          ? (updatedOrder['${_normalizedType}_photo_url']?.toString() ?? path)
          : path;

      if (_normalizedType == 'weigh_slip') {
        state.recordWeighSlip(
          photoUrl: remoteUrl,
          tonnage: tonnageVal ?? 0,
          weighTime: now,
        );
      } else if (_normalizedType == 'delivery_slip') {
        state.recordDeliverySlip(photoUrl: remoteUrl);
      } else if (_normalizedType == 'arrival_photo') {
        state.recordArrivalPhoto(photoUrl: remoteUrl);
      } else if (_normalizedType == 'pump_slip_before') {
        state.recordPumpBeforePhoto(photoUrl: remoteUrl);
      } else if (_normalizedType == 'breakdown') {
        if (state.currentTrip != null) {
          state.currentTrip!.hasBreakdown = true;
          state.currentTrip!.breakdownReason = _noteController.text.trim();
          state.currentTrip!.breakdownPhotoUrl = remoteUrl;
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

    if (!mounted) return;
    Navigator.of(context).pop(updatedOrder ?? {'local_path': path});

    String successMsg;
    switch (_normalizedType) {
      case 'pump_slip_before':
        successMsg =
            "Đã gửi ảnh TRƯỚC KHI BƠM cho Điều phối (đơn ${widget.orderCode ?? ''})!";
        break;
      case 'weigh_slip':
        successMsg =
            "Đã chụp và lưu Phiếu Cân vào đơn hàng ${widget.orderCode ?? ''}!";
        break;
      case 'arrival_photo':
        successMsg =
            "Đã ghi nhận ảnh ĐẾN ĐIỂM GIAO cho đơn ${widget.orderCode ?? ''}!";
        break;
      case 'delivery_slip':
        successMsg =
            "Đã chụp và lưu Phiếu Giao Hàng — Hoàn thành đơn ${widget.orderCode ?? ''}!";
        break;
      case 'breakdown':
        successMsg =
            "Đã gửi ảnh Báo Hỏng Xe lên Điều phối & bộ phận Kỹ thuật!";
        break;
      case 'repair':
        successMsg =
            "Đã cập nhật ảnh tình trạng sửa chữa xe cho đơn ${widget.orderCode ?? ''}!";
        break;
      default:
        successMsg = "Đã lưu hình chụp thành công!";
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text(successMsg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _screenTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            if ((widget.orderCode ?? '').isNotEmpty ||
                (widget.vehiclePlate ?? '').isNotEmpty)
              Text(
                [
                  if ((widget.orderCode ?? '').isNotEmpty)
                    "Đơn: ${widget.orderCode}",
                  if ((widget.vehiclePlate ?? '').isNotEmpty)
                    "Xe: ${widget.vehiclePlate}",
                ].join(" • "),
                style: const TextStyle(fontSize: 11.5, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_permissionState) {
      case 'checking':
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      case 'denied':
      case 'permanentlyDenied':
        return _buildPermissionDenied();
      case 'noCamera':
        return const Center(
          child: Text(
            "Thiết bị không có camera",
            style: TextStyle(color: Colors.white),
          ),
        );
      case 'error':
        return _buildErrorRetry();
      default:
        return _buildCameraPreview();
    }
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, color: Colors.white54, size: 56),
            const SizedBox(height: 14),
            Text(
              _permissionState == 'permanentlyDenied'
                  ? "Quyền camera bị từ chối vĩnh viễn. Vui lòng cấp quyền trong Cài đặt."
                  : "Cần cấp quyền camera để chụp phiếu. Vui lòng thử lại.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                minimumSize: const Size(120, 36),
              ),
              onPressed: () {
                if (_permissionState == 'permanentlyDenied') {
                  openAppSettings();
                } else {
                  _requestPermissionAndInitCamera();
                }
              },
              child: Text(
                _permissionState == 'permanentlyDenied'
                    ? "Mở Cài đặt"
                    : "Thử lại",
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorRetry() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 56),
          const SizedBox(height: 14),
          const Text(
            "Không khởi tạo được camera",
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              minimumSize: const Size(120, 36),
            ),
            onPressed: _requestPermissionAndInitCamera,
            child: const Text(
              "Thử lại",
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraMetadataFields() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_normalizedType == 'weigh_slip') ...[
            Row(
              children: [
                Expanded(
                  child: _buildDarkTextField(
                    controller: _tonnageController,
                    label: "Khối lượng cân (Tấn)",
                    hint: "VD: 32.5",
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildDarkTextField(
                    controller: _codeController,
                    label: "Mã phiếu cân (nếu có)",
                    hint: "VD: PC-0082",
                  ),
                ),
              ],
            ),
          ] else if (_normalizedType == 'pump_slip_before') ...[
            _buildDarkTextField(
              controller: _noteController,
              label: "Ghi chú trước khi bơm (nếu có)",
              hint: "VD: Bồn rỗng, đồng hồ về 0...",
            ),
          ] else if (_normalizedType == 'delivery_slip') ...[
            _buildDarkTextField(
              controller: _noteController,
              label: "Ghi chú giao hàng (nếu có)",
              hint: "VD: Khách hàng đã ký nhận đủ...",
            ),
          ] else if (_normalizedType == 'breakdown') ...[
            _buildDarkTextField(
              controller: _noteController,
              label: "Mô tả tình trạng hỏng xe (*)",
              hint: "VD: Nổ lốp sau bên phụ / Lỗi hệ thống bơm...",
            ),
            const SizedBox(height: 8),
            _buildDarkTextField(
              controller: _locationController,
              label: "Vị trí gặp sự cố",
              hint: "VD: Km18 Cao tốc Long Thành / Quốc lộ 51...",
            ),
          ] else if (_normalizedType == 'repair') ...[
            Row(
              children: [
                const Text(
                  "Kết quả xử lý:",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                ChoiceChip(
                  label: const Text("Đã khắc phục xong"),
                  selected: _repairStatus == 'fixed',
                  selectedColor: Colors.green.shade700,
                  backgroundColor: Colors.white10,
                  labelStyle: TextStyle(
                    color: _repairStatus == 'fixed'
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) => setState(() => _repairStatus = 'fixed'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Đang sửa chữa"),
                  selected: _repairStatus == 'repairing',
                  selectedColor: Colors.orange.shade800,
                  backgroundColor: Colors.white10,
                  labelStyle: TextStyle(
                    color: _repairStatus == 'repairing'
                        ? Colors.white
                        : Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) =>
                      setState(() => _repairStatus = 'repairing'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildDarkTextField(
              controller: _noteController,
              label: "Ghi chú tình trạng sửa chữa Kỹ thuật",
              hint: "VD: Đã thay tuy-ô thủy lực, xe tiếp tục hành trình...",
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDarkTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 12.5),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 11.5),
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11.5),
          filled: true,
          fillColor: Colors.white10,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.blueAccent),
          ),
        ),
      ),
    );
  }

  Widget _buildGpsStatusBar() {
    final fix = _gpsFix;
    final err = _gpsError;
    Color bg;
    Widget content;
    if (fix != null) {
      bg = const Color(0xFF14532D);
      content = Text(
        "GPS: ${fix.display}",
        style: const TextStyle(color: Colors.white, fontSize: 12),
      );
    } else if (_isLocating) {
      bg = const Color(0xFF1E3A8A);
      content = const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
          SizedBox(width: 8),
          Text(
            "Đang lấy tọa độ GPS...",
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      );
    } else {
      bg = const Color(0xFF7F1D1D);
      content = Row(
        children: [
          Expanded(
            child: Text(
              err?.message ?? "Chưa có tọa độ GPS.",
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          if (err != null &&
              (err.needsAppSettings || err.needsLocationSettings))
            TextButton(
              onPressed: () => GpsService.openSettingsFor(err),
              child: const Text(
                "Mở Cài đặt",
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          TextButton(
            onPressed: _captureGpsFix,
            child: const Text(
              "Lấy lại GPS",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController;
    final captured = _capturedPath;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (captured != null)
                Image.file(File(captured), fit: BoxFit.contain)
              else if (controller != null && _isCameraReady)
                CameraPreview(controller)
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              if (captured == null)
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _guideText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (captured != null) _buildGpsStatusBar(),
        if (captured != null) _buildExtraMetadataFields(),
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (captured == null)
                IconButton(
                  onPressed: () {
                    setState(() => _flashOn = !_flashOn);
                    final c = _cameraController;
                    if (c != null && c.value.isInitialized) {
                      c.setFlashMode(
                        _flashOn ? FlashMode.always : FlashMode.off,
                      );
                    }
                  },
                  icon: Icon(
                    _flashOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 28,
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() {
                          _capturedPath = null;
                          _gpsFix = null;
                          _gpsError = null;
                        }),
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    "Chụp lại",
                    style: TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
                ),
              GestureDetector(
                onTap: _isSubmitting
                    ? null
                    : (captured == null ? _takePicture : _confirmSubmit),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: captured == null
                        ? Colors.white
                        : Colors.green.shade600,
                    border: Border.all(color: Colors.white70, width: 3),
                  ),
                  child: _isSubmitting
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Icon(
                          captured == null ? Icons.camera_alt : Icons.check,
                          color: captured == null
                              ? Colors.black87
                              : Colors.white,
                          size: 30,
                        ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ],
    );
  }
}
