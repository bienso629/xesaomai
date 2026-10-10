import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/inspection_model.dart';
import '../models/trip_model.dart';
import '../models/breakdown_model.dart';
import '../models/reminder_model.dart';
import '../models/quanlyxe_model.dart';
import 'quanlyxe_service.dart';

enum UserRole {
  driver,
  manager,
}

class AppState extends ChangeNotifier {
  // Vai trò người dùng hiện tại (Mặc định hoặc chuyển đổi giữa Quản lý và Tài xế)
  UserRole currentRole = UserRole.driver;

  // Phiên đăng nhập thực tế từ Backend API
  String? authToken;
  int? currentUserId;
  String? currentUsername;
  String? currentFullName;
  List<String> userRoles = [];

  void setLoggedInUser({
    required String token,
    required int userId,
    required String username,
    required String fullName,
    required List<String> roles,
  }) {
    authToken = token;
    currentUserId = userId;
    currentUsername = username;
    currentFullName = fullName;
    userRoles = roles;
    if (roles.contains('manager') || roles.contains('dispatcher') || roles.contains('mechanic')) {
      currentRole = UserRole.manager;
    } else {
      currentRole = UserRole.driver;
    }
    notifyListeners();
  }

  void setRole(UserRole role) {
    currentRole = role;
    notifyListeners();
  }

  // Tài xế hiện tại
  String currentDriverId = "TX-8839";
  String currentDriverName = "Nguyễn Văn Hùng";
  String selectedPlate = "50H-891.21";
  VehicleType selectedVehicleType = VehicleType.howo;

  // Danh mục xe trực (Đồng bộ trực tiếp từ Bình Anh API)
  List<String> availableVehicles = ["50H-891.21", "50H-538.61", "50H-882.60", "51D-477.61", "51D-477.41"];
  List<QuanLyXeInfo> liveVehicles = [];
  QuanLyXeStatus? currentGpsStatus;
  bool isLoadingGps = false;

  // 11 Lý do chờ bơm (đúng theo đặc tả)
  static const List<String> waitingReasons = [
    "Nhà máy chưa mở kho / hết chỗ đỗ",
    "Chờ bồn nhận hàng của khách xả rỗng",
    "Sự cố hệ thống bơm / đường ống nhà máy",
    "Chờ kết quả mẫu thử nghiệm chất lượng",
    "Ùn tắc phương tiện phía trước",
    "Chờ nhân viên kỹ thuật bên nhận ký phiếu",
    "Mất điện / cúp nguồn trạm bơm",
    "Chờ điều phối đổi bồn nhận khác",
    "Thời tiết mưa lớn ngập khu vực bơm",
    "Xe gặp trục trặc kỹ thuật bơm",
    "Khác (có xác nhận của giám sát kho)"
  ];

  // Trạng thái kiểm tra đầu ngày
  DailyInspectionRecord? todayInspection;
  bool isInspectionCompleted = false;

  // Danh sách báo hỏng
  final List<BreakdownReport> breakdownReports = [];

  // Danh sách nhắc nhở
  final List<ReminderRecord> activeReminders = [];

  // Chuyến xe hiện tại
  TripMilestone? currentTrip;

  // Lịch sử vi phạm & tuân thủ
  int uninspectedMoveViolations = 0;

  AppState() {
    _initSampleTrip();
    initQuanLyXeData();
  }

  Future<void> initQuanLyXeData() async {
    isLoadingGps = true;
    notifyListeners();
    try {
      final vehicles = await QuanLyXeService.fetchVehicles();
      if (vehicles.isNotEmpty) {
        liveVehicles = vehicles;
        availableVehicles = vehicles.map((v) => v.plate).toList();
        if (!availableVehicles.contains(selectedPlate)) {
          selectedPlate = availableVehicles.first;
        }
      }
      await refreshCurrentVehicleGps();
    } catch (e) {
      debugPrint("initQuanLyXeData error: $e");
    } finally {
      isLoadingGps = false;
      notifyListeners();
    }
  }

  Future<void> refreshCurrentVehicleGps() async {
    isLoadingGps = true;
    notifyListeners();
    try {
      final status = await QuanLyXeService.fetchVehicleStatus(selectedPlate);
      if (status != null) {
        currentGpsStatus = status;
        if (status.driverName.isNotEmpty && status.driverName != 'Chưa gắn thẻ') {
          currentDriverName = status.driverName;
        }
      }
    } catch (e) {
      debugPrint("refreshCurrentVehicleGps error: $e");
    } finally {
      isLoadingGps = false;
      notifyListeners();
    }
  }

  void _initSampleTrip() {
    currentTrip = TripMilestone(
      orderCode: "DH-XI-MANG-2026-092",
      vehiclePlate: selectedPlate,
      destinationName: "Trạm trộn Bê tông Nghi Sơn - Nhơn Trạch",
      destinationLat: 10.7025,
      destinationLng: 106.9452,
    );
  }

  void setVehicle(String plate, VehicleType type) {
    selectedPlate = plate;
    selectedVehicleType = type;
    if (currentTrip != null) {
      currentTrip = TripMilestone(
        orderCode: currentTrip!.orderCode,
        vehiclePlate: plate,
        destinationName: currentTrip!.destinationName,
        destinationLat: currentTrip!.destinationLat,
        destinationLng: currentTrip!.destinationLng,
      );
    }
    // Đổi xe thì reset kiểm tra đầu ngày của xe đó
    isInspectionCompleted = false;
    todayInspection = null;
    refreshCurrentVehicleGps();
    notifyListeners();
  }

  // Cập nhật kết quả kiểm tra 5 ảnh
  void completeDailyInspection({
    required List<PhotoMetadata> photos,
    required double ocrKm,
    required double confirmedKm,
    required bool isKmFlagged,
  }) {
    todayInspection = DailyInspectionRecord(
      id: "KT-${DateTime.now().millisecondsSinceEpoch}",
      date: DateTime.now(),
      vehiclePlate: selectedPlate,
      driverId: currentDriverId,
      vehicleType: selectedVehicleType,
      photos: photos,
      ocrKm: ocrKm,
      confirmedKm: confirmedKm,
      isKmFlagged: isKmFlagged,
      isCompleted: true,
      flagStatus: isKmFlagged ? 'Theo doi' : 'None',
    );
    isInspectionCompleted = true;
    notifyListeners();
  }

  // Báo hỏng xe
  void addBreakdownReport(BreakdownCategory cat, String photoPath, String desc) {
    final report = BreakdownReport(
      id: "BH-${DateTime.now().millisecondsSinceEpoch}",
      timestamp: DateTime.now(),
      vehiclePlate: selectedPlate,
      driverId: currentDriverId,
      category: cat,
      photoPath: photoPath,
      description: desc,
      decision: "cho_duyet",
    );
    breakdownReports.add(report);
    notifyListeners();
  }

  // Điều phối duyệt báo hỏng
  void resolveBreakdown(String reportId, String decision, String handlerName) {
    final index = breakdownReports.indexWhere((r) => r.id == reportId);
    if (index != -1) {
      breakdownReports[index].decision = decision;
      breakdownReports[index].decisionBy = handlerName;
      breakdownReports[index].decisionTime = DateTime.now();
      notifyListeners();
    }
  }

  // Xử lý cờ bất thường
  void resolveInspectionFlag(String decision, String handlerName) {
    if (todayInspection != null) {
      todayInspection = DailyInspectionRecord(
        id: todayInspection!.id,
        date: todayInspection!.date,
        vehiclePlate: todayInspection!.vehiclePlate,
        driverId: todayInspection!.driverId,
        vehicleType: todayInspection!.vehicleType,
        photos: todayInspection!.photos,
        ocrKm: todayInspection!.ocrKm,
        confirmedKm: todayInspection!.confirmedKm,
        isKmFlagged: todayInspection!.isKmFlagged,
        isCompleted: todayInspection!.isCompleted,
        flagStatus: decision,
        flagHandler: "$handlerName (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})",
      );
      notifyListeners();
    }
  }

  // Kiểm tra xe có đang bị giữ bởi báo hỏng không
  bool isVehicleLockedByBreakdown() {
    return breakdownReports.any((b) => b.decision == "cho_duyet" || b.decision == "vao_xuong");
  }

  // Mốc giờ chuyến: ĐẾN ĐIỂM GIAO
  bool recordArrival({required double lat, required double lng, required bool forceConfirm}) {
    if (currentTrip == null) return false;

    // Tính khoảng cách tới đích
    final distKm = _calculateDistanceKm(lat, lng, currentTrip!.destinationLat, currentTrip!.destinationLng);
    if (distKm > 2.0 && !forceConfirm) {
      return false; // Cần popup xác nhận nếu cách xa > 2km
    }

    currentTrip!.arrivedTime = DateTime.now();
    currentTrip!.arrivedLat = lat;
    currentTrip!.arrivedLng = lng;
    currentTrip!.arrivedSource = "app";
    notifyListeners();
    return true;
  }

  // Mốc giờ chuyến: BƠM XONG
  void recordPumpCompleted({
    required double lat,
    required double lng,
    String? reason,
  }) {
    if (currentTrip == null) return;
    currentTrip!.pumpedTime = DateTime.now();
    currentTrip!.pumpedLat = lat;
    currentTrip!.pumpedLng = lng;
    currentTrip!.pumpedSource = "app";
    currentTrip!.waitingReason = reason;
    notifyListeners();
  }

  // Gửi Phiếu Cân (OCR mã, tấn, giờ cân)
  void recordWeighSlip({
    required String photoUrl,
    required double tonnage,
    required DateTime weighTime,
  }) {
    if (currentTrip == null) return;
    currentTrip!.weighSlipPhotoUrl = photoUrl;
    currentTrip!.weighTonnage = tonnage;
    currentTrip!.weighTime = weighTime;
    currentTrip!.weighOrderStatus = "da gui Zalo";
    notifyListeners();
  }

  // Gửi Phiếu Giao Hàng (Tự động đẩy Zalo OA group)
  void recordDeliverySlip({required String photoUrl}) {
    if (currentTrip == null) return;
    currentTrip!.deliverySlipPhotoUrl = photoUrl;
    currentTrip!.deliveryTime = DateTime.now();
    currentTrip!.deliveryZaloStatus = "da gui Zalo OA";
    notifyListeners();
  }

  // Kích hoạt mô phỏng nhắc nhở nền
  void triggerReminder(ReminderType type, String message) {
    activeReminders.insert(
      0,
      ReminderRecord(
        id: "REM-${DateTime.now().millisecondsSinceEpoch}",
        type: type,
        driverId: currentDriverId,
        vehiclePlate: selectedPlate,
        attemptCount: 1,
        sentTime: DateTime.now(),
        message: message,
      ),
    );
    if (type == ReminderType.movingWithoutInspection) {
      uninspectedMoveViolations++;
    }
    notifyListeners();
  }

  // Tính khoảng cách Haversine sơ bộ
  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }
}
