import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/inspection_model.dart';
import '../services/admin_service.dart';
import '../services/app_state.dart';
import 'camera_inspection_screen.dart';
import 'slip_capture_screen.dart';
import 'breakdown_dialog.dart';

class DriverScheduleScreen extends StatefulWidget {
  const DriverScheduleScreen({super.key});

  @override
  State<DriverScheduleScreen> createState() => _DriverScheduleScreenState();
}

class _DriverScheduleScreenState extends State<DriverScheduleScreen> {
  final MapController _mapController = MapController();
  final String _vietMapApiKey = 'edfac336d2c0462850d93fd5859878b1ad84b769ddfed745';

  bool _isLoadingData = true;
  List<dynamic> _myAssignedVehicles = [];
  List<dynamic> _myOrders = [];
  Timer? _gpsRefreshTimer;
  LatLng? _lastCenteredPos;

  static const LatLng _defaultCenter = LatLng(10.7500, 106.7500);

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    _gpsRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _loadDriverData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _gpsRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingData = true;
      });
    }

    try {
      final state = context.read<AppState>();
      final results = await Future.wait([
        AdminService.fetchVehicles(),
        AdminService.fetchOrders(),
      ]);

      if (!mounted) return;

      final allVehicles = results[0];
      final allOrders = results[1];
      final myUserId = state.currentUserId;
      final myUsername = (state.currentUsername ?? '').trim().toLowerCase();

      // Lọc danh sách xe mà tài xế này được chỉ định quản lý (default_driver_id hoặc driver_username)
      final assignedVehicles = allVehicles.where((v) {
        if (v is! Map) return false;
        final defDriverId = v['default_driver_id'];
        final drvUser = (v['driver_username'] ?? '').toString().trim().toLowerCase();
        if (myUserId != null && defDriverId != null && defDriverId == myUserId) {
          return true;
        }
        if (myUsername.isNotEmpty && drvUser == myUsername) {
          return true;
        }
        return false;
      }).toList();

      // Nếu tài xế có xe chỉ định và xe đang chọn trong AppState chưa khớp, tự động gán xe chỉ định đầu tiên
      if (assignedVehicles.isNotEmpty) {
        final assignedPlates = assignedVehicles.map((v) => v['plate_number'].toString()).toList();
        if (!assignedPlates.contains(state.selectedPlate)) {
          final firstPlate = assignedPlates.first;
          VehicleType vType = VehicleType.howo;
          if (firstPlate.contains("772")) vType = VehicleType.shacman;
          if (firstPlate.contains("441")) vType = VehicleType.daewoo;
          state.setVehicle(firstPlate, vType);
        }
      }

      // Đồng bộ trạng thái Kiểm tra xe & Duyệt Nhận Chuyến của xe đang chọn từ server
      await state.refreshInspectionApprovalStatus();
      if (!mounted) return;

      // Chỉ khi xe ĐÃ ĐƯỢC DUYỆT NHẬN CHUYẾN (isApprovedByDispatcher == true)
      // mới cho phép lấy đơn hàng do Điều phối viên gắn cho xe/tài xế
      final activePlate = state.selectedPlate;
      List<dynamic> driverOrders = [];
      if (state.isApprovedByDispatcher) {
        driverOrders = allOrders.where((o) {
          if (o is! Map) return false;
          final status = (o['status'] ?? '').toString().trim().toLowerCase();
          if (status == 'completed' || status == 'cancelled' || status == 'waiting') {
            return false;
          }
          final ordDriverId = o['assigned_driver_id'];
          final ordPlate = (o['assigned_vehicle_plate'] ?? '').toString().trim();
          if (ordPlate.isNotEmpty && ordPlate == activePlate) {
            return true;
          }
          if (myUserId != null && ordDriverId != null && ordDriverId == myUserId) {
            return true;
          }
          return false;
        }).toList();
      }

      // Đồng bộ currentTrip: chỉ có Mã lệnh khi xe đã được Duyệt Nhận Chuyến + có đơn hàng gắn
      final Map<String, dynamic>? activeOrder = driverOrders.isNotEmpty
          ? Map<String, dynamic>.from(driverOrders.first as Map)
          : null;
      state.syncAssignedTripFromOrder(activeOrder);

      setState(() {
        _myAssignedVehicles = assignedVehicles;
        _myOrders = driverOrders;
        _isLoadingData = false;
      });

      await state.refreshCurrentVehicleGps();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
        });
      }
    }
  }

  LatLng _getCurrentVehiclePosition(AppState state) {
    final gps = state.currentGpsStatus;
    if (gps != null && gps.latitude > 0 && gps.longitude > 0) {
      return LatLng(gps.latitude, gps.longitude);
    }
    final fleetStatus = state.allFleetVehiclesStatus[state.selectedPlate];
    if (fleetStatus != null && fleetStatus.latitude > 0 && fleetStatus.longitude > 0) {
      return LatLng(fleetStatus.latitude, fleetStatus.longitude);
    }
    return _defaultCenter;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Khóa nhận chuyến cho đến khi Điều phối bấm "Duyệt Nhận Chuyến"
    final isLocked =
        !state.isApprovedByDispatcher || state.isVehicleLockedByBreakdown();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: () async {
          final AppState appState = context.read<AppState>();
          await _loadDriverData(silent: true);
          await appState.refreshInspectionApprovalStatus();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Thẻ thông tin Xe được giao quản lý & Trạng thái trực tiếp của riêng xe đó
              _buildManagedVehicleHeaderCard(context, state),
              const SizedBox(height: 12),

              // 2. Bản đồ thu gọn chỉ hiển thị duy nhất chiếc xe của tài xế & lộ trình điểm giao
              _buildSingleVehicleRouteMapCard(context, state),
              const SizedBox(height: 12),

              // 3. Mục Kiểm tra xe đầu ngày (5 ảnh) & Báo hỏng
              _buildDailyInspectionStatusCard(context, state),
              const SizedBox(height: 12),

              // 4. Lịch trình chuyến hàng & Bấm mốc giờ (ĐẾN / BƠM XONG / PHIẾU CÂN / PHIẾU GIAO HÀNG)
              _buildActiveScheduleMilestonesCard(context, state, isLocked),
              const SizedBox(height: 12),

              // 5. Danh sách các lệnh điều động / lịch trình phân công cho xe của tài xế
              _buildAssignedOrdersListCard(context, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManagedVehicleHeaderCard(BuildContext context, AppState state) {
    final gps = state.currentGpsStatus ?? state.allFleetVehiclesStatus[state.selectedPlate];
    final bool isOnline = gps != null && gps.latitude > 0 && gps.longitude > 0;
    final double speed = isOnline ? gps.speed : 0.0;
    final bool isAccOn = isOnline ? gps.isAccOn : false;
    final int odoKm = isOnline ? gps.odoKm : 0;

    final List<String> selectablePlates = _myAssignedVehicles.isNotEmpty
        ? _myAssignedVehicles.map((v) => v['plate_number'].toString()).toList()
        : state.availableVehicles;

    if (!selectablePlates.contains(state.selectedPlate) && selectablePlates.isNotEmpty) {
      selectablePlates.insert(0, state.selectedPlate);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: selectablePlates.contains(state.selectedPlate)
                        ? state.selectedPlate
                        : (selectablePlates.isNotEmpty ? selectablePlates.first : null),
                    isDense: true,
                    isExpanded: true,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    items: selectablePlates.map((plate) {
                      return DropdownMenuItem<String>(
                        value: plate,
                        child: Text(plate, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      );
                    }).toList(),
                    onChanged: (newPlate) {
                      if (newPlate != null) {
                        VehicleType vType = VehicleType.howo;
                        if (newPlate.contains("772")) vType = VehicleType.shacman;
                        if (newPlate.contains("441")) vType = VehicleType.daewoo;
                        state.setVehicle(newPlate, vType);
                        _lastCenteredPos = null;
                        final pos = _getCurrentVehiclePosition(state);
                        _mapController.move(pos, 14.5);
                        _loadDriverData(silent: true);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? (speed > 0 ? Colors.green.shade50 : Colors.amber.shade50)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isOnline
                              ? (speed > 0 ? Colors.green.shade300 : Colors.amber.shade300)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        isOnline
                            ? (speed > 0
                                ? "Đang chạy (${speed.toStringAsFixed(0)} km/h)"
                                : (isAccOn ? "Nổ máy dừng" : "Đang đỗ"))
                            : "Chờ tín hiệu GPS",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOnline
                              ? (speed > 0 ? Colors.green.shade800 : Colors.amber.shade900)
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blueGrey.shade200),
                      ),
                      child: Text(
                        "ODO: $odoKm km",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                      ),
                    ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleVehicleRouteMapCard(BuildContext context, AppState state) {
    final vehiclePos = _getCurrentVehiclePosition(state);
    if (vehiclePos != _defaultCenter && _lastCenteredPos != vehiclePos) {
      _lastCenteredPos = vehiclePos;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(vehiclePos, 14.5);
      });
    }
    final trip = state.currentTrip;
    final destPos = trip != null ? LatLng(trip.destinationLat, trip.destinationLng) : null;
    final gpsInfo = state.currentGpsStatus ?? state.allFleetVehiclesStatus[state.selectedPlate];
    final String address = (gpsInfo != null && gpsInfo.latitude > 0 && gpsInfo.longitude > 0 && gpsInfo.address.isNotEmpty)
        ? gpsInfo.address
        : "Đang đồng bộ vị trí trạm / bãi xe...";

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.route_outlined, size: 18, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Vị Trí & Lộ Trình Xe ${state.selectedPlate}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    _mapController.move(vehiclePos, 15.0);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location, size: 14, color: Colors.blue.shade800),
                        const SizedBox(width: 4),
                        Text(
                          "Về vị trí xe",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: vehiclePos,
                    initialZoom: 13.5,
                    minZoom: 6.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}@2x.png?apikey=$_vietMapApiKey',
                      userAgentPackageName: 'com.taxilogistics.driver.app_tai_xe',
                      tileProvider: NetworkTileProvider(),
                    ),
                    if (destPos != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [vehiclePos, destPos],
                            strokeWidth: 3.0,
                            color: Colors.blue.shade700,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        // Chỉ hiển thị duy nhất marker chiếc xe của tài xế
                        Marker(
                          point: vehiclePos,
                          width: 110,
                          height: 60,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber, width: 1.5),
                                ),
                                child: Text(
                                  state.selectedPlate,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Icon(Icons.local_shipping, color: Colors.blue.shade800, size: 30),
                            ],
                          ),
                        ),
                        // Điểm giao hàng trên lịch trình
                        if (destPos != null)
                          Marker(
                            point: destPos,
                            width: 120,
                            height: 55,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    "Điểm giao hàng",
                                    style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Icon(Icons.flag, color: Colors.red.shade700, size: 26),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Vị trí xe hiện tại: $address",
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyInspectionStatusCard(BuildContext context, AppState state) {
    final bool completed = state.isInspectionCompleted;
    // Xe chỉ "Đủ điều kiện chạy" khi Điều phối viên đã bấm "Duyệt Nhận Chuyến"
    final bool approved = state.isApprovedByDispatcher;
    final bool hasBreakdownLock = state.isVehicleLockedByBreakdown();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.camera_alt_outlined, color: Colors.blue.shade800, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "Kiểm Tra Xe Đầu Ngày (5 Ảnh Bắt Buộc)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: approved
                        ? Colors.green.shade50
                        : (completed ? Colors.blue.shade50 : Colors.orange.shade50),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: approved
                          ? Colors.green.shade300
                          : (completed ? Colors.blue.shade300 : Colors.orange.shade300),
                    ),
                  ),
                  child: Text(
                    approved
                        ? "Đủ điều kiện chạy"
                        : (completed ? "Chờ Điều phối duyệt" : "Chưa chụp 5 ảnh"),
                    style: TextStyle(
                      color: approved
                          ? Colors.green.shade800
                          : (completed ? Colors.blue.shade800 : Colors.orange.shade900),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              approved
                  ? "• Đã hoàn tất 5 ảnh (gầm trước, gầm sau, hông trái, hông phải, táp lô)\n• Số ODO xác nhận: ${state.todayInspection?.confirmedKm.toStringAsFixed(0)} km\n• Điều phối đã Duyệt Nhận Chuyến: xe ĐỦ ĐIỀU KIỆN CHẠY"
                  : (completed
                      ? "• Đã gửi đủ 5 ảnh lên hệ thống, đang chờ Điều phối viên kiểm tra\n• Xe CHƯA đủ điều kiện chạy cho đến khi Điều phối bấm \"Duyệt Nhận Chuyến\""
                      : "Theo quy định: Tài xế chụp đủ 5 ảnh gửi lên Điều phối kiểm tra. Chỉ khi Điều phối bấm \"Duyệt Nhận Chuyến\" xe mới đủ điều kiện chạy."),
              style: TextStyle(fontSize: 12.5, color: completed ? Colors.black87 : Colors.grey.shade700, height: 1.4),
            ),
            if (hasBreakdownLock) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.red.shade700, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Xe đang có Báo hỏng chờ Điều phối xử lý. Tạm khóa thao tác chuyến!",
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: completed ? Colors.blueGrey.shade700 : Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text(
                        completed ? "Chụp Lại 5 Ảnh" : "Chụp 5 ảnh ngay",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CameraInspectionScreen()),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(Icons.report_problem_outlined, size: 18),
                      label: const Text("Báo Hỏng", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => const BreakdownDialog(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveScheduleMilestonesCard(BuildContext context, AppState state, bool isLocked) {
    final bool approved = state.isApprovedByDispatcher;
    final bool completedInspection = state.isInspectionCompleted;
    final trip = approved ? state.currentTrip : null;
    final bool hasAssignedOrder = approved && trip != null && trip.orderCode.trim().isNotEmpty;
    final bool stepDisabled = isLocked || !hasAssignedOrder;

    String badgeText = "ĐANG THỰC HIỆN";
    if (!approved) {
      badgeText = completedInspection ? "CHỜ ĐIỀU PHỐI DUYỆT" : "CHỜ KIỂM TRA XE";
    } else if (!hasAssignedOrder) {
      badgeText = "CHỜ GẮN MÃ LỆNH";
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.event_note_outlined, color: Colors.blue.shade800, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          "Lịch Trình Chuyến & Mốc Giờ",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasAssignedOrder ? Colors.green.shade50 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: hasAssignedOrder ? Colors.green.shade400 : Colors.grey.shade400,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: hasAssignedOrder ? Colors.green.shade800 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (!hasAssignedOrder)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !approved
                            ? "Xe ${state.selectedPlate} chưa được kiểm tra & Duyệt Nhận Chuyến nên chưa có Mã lệnh. Vui lòng chụp đủ 5 ảnh kiểm tra xe và chờ Điều phối viên bấm 'Duyệt Nhận Chuyến' để gắn đơn hàng."
                            : "Xe ${state.selectedPlate} đã được Duyệt Nhận Chuyến. Đang chờ Điều phối viên gắn đơn hàng (Mã lệnh) cho xe.",
                        style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "Mã lệnh: ${trip.orderCode}",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.blue.shade900),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Xe: ${state.selectedPlate}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Điểm giao hàng: ${trip.destinationName}",
                      style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Mốc 1: ĐẾN ĐIỂM GIAO
            _buildMilestoneStepRow(
              title: "1. ĐẾN điểm giao hàng",
              timeText: (trip?.arrivedTime != null)
                  ? "Đã ghi nhận lúc ${trip!.arrivedTime!.hour.toString().padLeft(2, '0')}:${trip.arrivedTime!.minute.toString().padLeft(2, '0')} (GPS)"
                  : "Bấm khi xe đến trạm/kho khách hàng",
              isRecorded: trip?.arrivedTime != null,
              buttonLabel: "Bấm ĐẾN",
              isDisabled: stepDisabled || trip.arrivedTime != null,
              onPressed: () => _handleArrived(context, state),
            ),
            const SizedBox(height: 8),

            // Mốc 2: BƠM XONG
            _buildMilestoneStepRow(
              title: "2. BƠM XONG hàng",
              timeText: (trip?.pumpedTime != null)
                  ? "Hoàn tất lúc ${trip!.pumpedTime!.hour.toString().padLeft(2, '0')}:${trip.pumpedTime!.minute.toString().padLeft(2, '0')}"
                  : (trip?.arrivedTime != null ? "Đang chờ/bơm (${trip!.waitDurationMinutes} phút)" : "Chờ xác nhận mốc ĐẾN"),
              isRecorded: trip?.pumpedTime != null,
              buttonLabel: "BƠM XONG",
              isDisabled: stepDisabled || trip.arrivedTime == null || trip.pumpedTime != null,
              onPressed: () => _handlePumped(context, state),
            ),
            const SizedBox(height: 8),

            // Mốc 3: GỬI PHIẾU CÂN
            _buildMilestoneStepRow(
              title: "3. Chụp & Gửi Phiếu Cân",
              timeText: (trip?.weighSlipPhotoUrl != null)
                  ? "Khối lượng: ${trip!.weighTonnage} Tấn (Đã đồng bộ Zalo OA)"
                  : "Chụp phiếu cân OCR khối lượng & mã lệnh",
              isRecorded: trip?.weighSlipPhotoUrl != null,
              buttonLabel: "Phiếu Cân",
              isDisabled: stepDisabled,
              onPressed: () => SlipCaptureScreen.show(
                context,
                slipType: 'weigh',
                orderCode: trip?.orderCode ?? '',
              ),
            ),
            const SizedBox(height: 8),

            // Mốc 4: GỬI PHIẾU GIAO HÀNG
            _buildMilestoneStepRow(
              title: "4. Chụp & Gửi Phiếu Giao Hàng",
              timeText: (trip?.deliverySlipPhotoUrl != null)
                  ? "Đã gửi vào nhóm Zalo khách hàng"
                  : "Chụp biên bản giao nhận hàng hoàn tất chuyến",
              isRecorded: trip?.deliverySlipPhotoUrl != null,
              buttonLabel: "Phiếu GH",
              isDisabled: stepDisabled,
              onPressed: () => SlipCaptureScreen.show(
                context,
                slipType: 'delivery',
                orderCode: trip?.orderCode ?? '',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignedOrdersListCard(BuildContext context, AppState state) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.assignment_outlined, color: Colors.blue.shade800, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Lịch Trình Phân Công Xe ${state.selectedPlate}",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "${_myOrders.length} chuyến",
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (_isLoadingData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_myOrders.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.event_available_outlined, size: 32, color: Colors.grey.shade400),
                    const SizedBox(height: 6),
                    Text(
                      state.isApprovedByDispatcher ? "Chưa có đơn hàng nào được Điều phối viên gắn cho xe ${state.selectedPlate}." : "Xe ${state.selectedPlate} cần được kiểm tra và Duyệt Nhận Chuyến trước khi Điều phối viên gắn đơn hàng.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _myOrders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, idx) {
                  final o = _myOrders[idx] as Map<String, dynamic>;
                  final code = (o['order_code'] ?? 'ĐƠN HÀNG').toString();
                  final product = (o['product_name'] ?? 'Xi măng rời').toString();
                  final weight = (o['cargo_weight_tons'] ?? '--').toString();
                  final pickup = (o['pickup_address'] ?? 'Nhà máy/Trạm').toString();
                  final delivery = (o['delivery_address'] ?? 'Điểm giao khách hàng').toString();

                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                code,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade800),
                              ),
                            ),
                            Text(
                              "$product ($weight tấn)",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("• Nơi nhận: $pickup", style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        Text("• Điểm giao: $delivery", style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneStepRow({
    required String title,
    required String timeText,
    required bool isRecorded,
    required String buttonLabel,
    required bool isDisabled,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isRecorded ? Colors.green.shade50.withOpacity(0.5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isRecorded ? Colors.green.shade200 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            isRecorded ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isRecorded ? Colors.green.shade700 : Colors.grey.shade500,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isRecorded ? Colors.green.shade800 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDisabled ? Colors.grey.shade300 : Colors.blue.shade800,
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: isDisabled ? null : onPressed,
              child: Text(buttonLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _handleArrived(BuildContext context, AppState state) {
    const mockLat = 10.7325;
    const mockLng = 106.9152;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text("Xác nhận vị trí ĐẾN điểm giao", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          "Tọa độ GPS hiện tại đang cách tâm điểm giao hơn 2.0 km. Bạn có chắc chắn xe đã vào trạm giao hàng không?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Kiểm tra lại", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              state.recordArrival(lat: mockLat, lng: mockLng, forceConfirm: true);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green.shade700,
                  content: const Text("Đã ghi nhận mốc ĐẾN điểm giao hàng thành công!"),
                ),
              );
            },
            child: const Text("Xác nhận đã đến", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handlePumped(BuildContext context, AppState state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String selectedReason = AppState.waitingReasons.first;
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              title: Row(
                children: [
                  Icon(Icons.hourglass_bottom, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Xác nhận BƠM XONG (>120 phút)",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Thời gian từ lúc ĐẾN đến lúc BƠM XONG vượt quá 120 phút. Vui lòng chọn nguyên nhân chờ từ danh mục:",
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      items: AppState.waitingReasons.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedReason = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () {
                    state.recordPumpCompleted(lat: 10.7025, lng: 106.9452, reason: selectedReason);
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.green.shade700,
                        content: const Text("Đã ghi nhận mốc BƠM XONG và nguyên nhân chờ!"),
                      ),
                    );
                  },
                  child: const Text("Xác nhận BƠM XONG"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
