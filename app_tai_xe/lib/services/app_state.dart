import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/inspection_model.dart';
import '../models/trip_model.dart';
import '../models/breakdown_model.dart';
import '../models/reminder_model.dart';
import '../models/quanlyxe_model.dart';
import 'quanlyxe_service.dart';
import 'admin_service.dart';

enum UserRole {
  driver,
  manager,
}

class AppState extends ChangeNotifier {
  // Vai trò người dùng hiện tại (Mặc định mở Tổng quan Quản lý hoặc chuyển đổi với Tài xế)
  UserRole currentRole = UserRole.manager;

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
    currentDriverName = fullName;
    currentDriverId = "TX-${userId.toString().padLeft(4, '0')}";
    if (roles.contains('admin') || roles.contains('manager') || roles.contains('dispatcher') || roles.contains('mechanic') || username.toLowerCase() == 'admin') {
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
  Map<String, QuanLyXeStatus> allFleetVehiclesStatus = {};
  bool isLoadingGps = false;
  bool isLoadingFleetGps = false;

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

  // Xe chỉ ĐỦ ĐIỀU KIỆN CHẠY khi Điều phối viên bấm "Duyệt Nhận Chuyến" trên server.
  // Tài xế gửi đủ 5 ảnh KHÔNG tự động kích hoạt trạng thái này.
  bool isApprovedByDispatcher = false;

  // Danh sách báo hỏng
  final List<BreakdownReport> breakdownReports = [];

  // Danh sách nhắc nhở
  final List<ReminderRecord> activeReminders = [];

  // Chuyến xe hiện tại
  TripMilestone? currentTrip;

  // Lịch sử vi phạm & tuân thủ
  int uninspectedMoveViolations = 0;

  AppState() {
    currentTrip = null;
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
      await refreshAllFleetGps();
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

  Future<void> refreshAllFleetGps({bool force = false}) async {
    isLoadingFleetGps = true;
    notifyListeners();
    try {
      final statuses = await QuanLyXeService.fetchAllVehiclesStatus(forceRefresh: force);
      if (statuses.isNotEmpty) {
        allFleetVehiclesStatus = statuses;
        // Đồng bộ danh sách biển số từ cả 2 nguồn Vietmap + Bình Anh
        final mergedPlates = statuses.keys.toList()..sort();
        availableVehicles = mergedPlates;
        if (!availableVehicles.contains(selectedPlate) && availableVehicles.isNotEmpty) {
          selectedPlate = availableVehicles.first;
        }
        // Nếu xe đang chọn có trong danh sách statuses thì cập nhật luôn currentGpsStatus
        if (statuses.containsKey(selectedPlate)) {
          currentGpsStatus = statuses[selectedPlate];
        }
      }
    } catch (e) {
      debugPrint("refreshAllFleetGps error: $e");
    } finally {
      isLoadingFleetGps = false;
      notifyListeners();
    }
  }

  /// Đồng bộ chuyến hiện tại từ đơn hàng do Điều phối gắn sau khi xe đã được Duyệt Nhận Chuyến.
  /// Nếu xe chưa được duyệt nhận chuyến hoặc chưa có đơn hàng gắn cho xe -> currentTrip = null.
  void syncAssignedTripFromOrder(Map<String, dynamic>? order) {
    if (!isApprovedByDispatcher || order == null) {
      if (currentTrip != null) {
        currentTrip = null;
        notifyListeners();
      }
      return;
    }
    final String code = (order['order_code'] ?? '').toString().trim();
    if (code.isEmpty) {
      if (currentTrip != null) {
        currentTrip = null;
        notifyListeners();
      }
      return;
    }
    final String dest = (order['delivery_address'] ?? order['destination_name'] ?? 'Điểm giao khách hàng').toString().trim();
    final double dLat = double.tryParse('${order['delivery_lat'] ?? ''}') ?? 10.7500;
    final double dLng = double.tryParse('${order['delivery_lng'] ?? ''}') ?? 106.7500;

    final int? oid = order['id'] is int
        ? order['id'] as int
        : int.tryParse('${order['id'] ?? ''}');
    if (currentTrip == null ||
        currentTrip!.orderCode != code ||
        currentTrip!.vehiclePlate != selectedPlate) {
      currentTrip = TripMilestone(
        orderId: oid,
        orderCode: code,
        vehiclePlate: selectedPlate,
        destinationName: dest,
        destinationLat: dLat,
        destinationLng: dLng,
      );
    } else if (currentTrip!.orderId == null && oid != null) {
      currentTrip!.orderId = oid;
    }
    final pBefore = (order['pump_slip_before_photo_url'] ?? '').toString().trim();
    if (pBefore.isNotEmpty) currentTrip!.pumpBeforePhotoUrl = pBefore;
    final pAfter = (order['pump_slip_photo_url'] ?? '').toString().trim();
    if (pAfter.isNotEmpty) currentTrip!.pumpAfterPhotoUrl = pAfter;
    final wPhoto = (order['weigh_slip_photo_url'] ?? '').toString().trim();
    if (wPhoto.isNotEmpty) {
      currentTrip!.weighSlipPhotoUrl = wPhoto;
      final wTon = order['weigh_slip_tonnage'];
      if (wTon is num) currentTrip!.weighTonnage = wTon.toDouble();
    }
    final dPhoto = (order['delivery_slip_photo_url'] ?? '').toString().trim();
    if (dPhoto.isNotEmpty) {
      currentTrip!.deliverySlipPhotoUrl = dPhoto;
    }
    if (order['has_breakdown'] == true) {
      currentTrip!.hasBreakdown = true;
      currentTrip!.breakdownReason = (order['breakdown_reason'] ?? '').toString();
      currentTrip!.breakdownPhotoUrl = (order['breakdown_photo_url'] ?? '').toString();
    }
    notifyListeners();
  }

  void setVehicle(String plate, VehicleType type) {
    selectedPlate = plate;
    selectedVehicleType = type;
    // Đổi xe thì reset kiểm tra đầu ngày và xóa chuyến của xe cũ cho đến khi đồng bộ lại
    currentTrip = null;
    isInspectionCompleted = false;
    isApprovedByDispatcher = false;
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
    // Tài xế mới chỉ gửi đủ 5 ảnh: reset cờ duyệt, chờ Điều phối bấm "Duyệt Nhận Chuyến"
    isApprovedByDispatcher = false;
    notifyListeners();
  }

  /// Đồng bộ trạng thái duyệt của Điều phối từ server về cho lần kiểm tra hôm nay.
  /// Xe chỉ đủ điều kiện chạy khi server trả flag_status == 'approved'
  /// (tức Điều phối viên đã bấm "Duyệt Nhận Chuyến").
  Future<void> refreshInspectionApprovalStatus() async {
    try {
      final String todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final data = await AdminService.fetchInspections(
        date: todayStr,
        plateNumber: selectedPlate,
      );
      bool approved = false;
      if (data.isNotEmpty) {
        // Chọn bản ghi kiểm tra có id lớn nhất (mới nhất) của biển số đang chọn
        Map<String, dynamic>? latest;
        int maxId = -1;
        for (final item in data) {
          if (item is! Map) continue;
          final rawId = item['id'];
          final int id = rawId is int ? rawId : (int.tryParse('$rawId') ?? -1);
          if (id > maxId) {
            maxId = id;
            latest = item as Map<String, dynamic>;
          }
        }
        final status = (latest?['flag_status'] ?? '').toString().trim().toLowerCase();
        approved = status == 'approved';
      }
      final bool completedToday = data.isNotEmpty;
      bool changed = false;
      if (isInspectionCompleted != completedToday) {
        isInspectionCompleted = completedToday;
        changed = true;
      }
      if (isApprovedByDispatcher != approved) {
        isApprovedByDispatcher = approved;
        changed = true;
      }
      if (!approved && currentTrip != null) {
        currentTrip = null;
        changed = true;
      }
      if (changed) {
        notifyListeners();
      }
    } catch (_) {
      // Lỗi mạng: giữ nguyên trạng thái hiện tại, không tự ý kích hoạt
    }
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

  // Ảnh bơm hàng TRƯỚC KHI BƠM (Tài xế chụp, có GPS)
  void recordPumpBeforePhoto({required String photoUrl}) {
    if (currentTrip == null) return;
    currentTrip!.pumpBeforePhotoUrl = photoUrl;
    notifyListeners();
  }

  // Ảnh bơm hàng ĐÃ BƠM XONG (Tài xế chụp, có GPS)
  void recordPumpAfterPhoto({required String photoUrl}) {
    if (currentTrip == null) return;
    currentTrip!.pumpAfterPhotoUrl = photoUrl;
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
