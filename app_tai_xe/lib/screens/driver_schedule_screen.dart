import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../widgets/center_loading_overlay.dart';
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
  // Trang thai Bao nghi cua xe dang chon (true = da bao nghi, Tam ngung hoat dong)
  bool _isResting = false;
  bool _isSendingRest = false;
  List<dynamic> _myOrders = [];
  List<dynamic> _gasStations = [];
  Map<String, dynamic>? _activeFuelRequest;
  Map<String, dynamic>? _latestFuelRequest;
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
        AdminService.fetchGasStations(),
      ]);

      if (!mounted) return;

      final allVehicles = results[0];
      final allOrders = results[1];
      final allGasStations = results[2];
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

      // Cap nhat trang thai Bao nghi theo xe dang chon (status 'inactive' = Tam ngung hoat dong)
      final selected = state.selectedPlate;
      Map? selectedVehicle;
      for (final v in assignedVehicles) {
        if (v is Map && (v['plate_number'] ?? '').toString() == selected) {
          selectedVehicle = v;
          break;
        }
      }
      final bool isResting = selectedVehicle != null &&
          (selectedVehicle['status'] ?? '').toString().trim().toLowerCase() == 'inactive';

      Map<String, dynamic>? activeFuelReq;
      Map<String, dynamic>? latestFuelReq;
      if (selected.trim().isNotEmpty) {
        final fuelInfo = await AdminService.fetchActiveFuelRequest(selected);
        if (fuelInfo != null) {
          if (fuelInfo['active_request'] is Map) {
            activeFuelReq = Map<String, dynamic>.from(
              fuelInfo['active_request'] as Map,
            );
          }
          if (fuelInfo['latest_request'] is Map) {
            latestFuelReq = Map<String, dynamic>.from(
              fuelInfo['latest_request'] as Map,
            );
          }
        }
      }
      if (!mounted) return;

      setState(() {
        _myAssignedVehicles = assignedVehicles;
        _myOrders = driverOrders;
        _gasStations = allGasStations;
        _activeFuelRequest = activeFuelReq;
        _latestFuelRequest = latestFuelReq;
        _isResting = isResting;
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
      body: CenterLoadingOverlay(
        isLoading: _isLoadingData || _isSendingRest,
        message: _isSendingRest ? 'Đang cập nhật trạng thái phương tiện...' : 'Đang tải lịch trình tài xế...',
        child: RefreshIndicator(
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

              // 3b. Nghiệp vụ Đổ dầu, Mở Mã QR Cây dầu 1 lần & Nghiệm thu (Task T2)
              _buildFuelRequestAndQrCard(context, state),
              const SizedBox(height: 12),

              // 4. Lịch trình chuyến hàng & 4 bước chụp hình (Trước bơm / Phiếu cân / Đến điểm giao / Phiếu giao)
              _buildActiveScheduleMilestonesCard(context, state, isLocked),
              const SizedBox(height: 12),

              // 5. Danh sách các lệnh điều động / lịch trình phân công cho xe của tài xế
              _buildAssignedOrdersListCard(context, state),
            ],
          ),
        ),
      ),
      ),
    );
  }

  // Bao nghi: chuyen trang thai Phuong tien thanh "Tam ngung hoat dong" (status = 'inactive')
  // Tro lai hoat dong: chuyen ve san sang (status = 'ready')
  Future<void> _toggleVehicleRest() async {
    final String plate = context.read<AppState>().selectedPlate;
    if (plate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa chọn phương tiện'), backgroundColor: Colors.orange),
      );
      return;
    }
    final bool goingRest = !_isResting;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text(goingRest ? 'Xác nhận Báo nghỉ' : 'Trở lại hoạt động',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          goingRest
              ? 'Chuyển phương tiện $plate sang trạng thái "Tạm ngừng hoạt động"?'
              : 'Kích hoạt lại phương tiện $plate trở lại hoạt động bình thường?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: goingRest ? Colors.red.shade700 : Colors.green.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(goingRest ? 'Báo nghỉ' : 'Kích hoạt'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSendingRest = true);
    final res = await AdminService.updateVehicle(plate, {
      'status': goingRest ? 'inactive' : 'ready',
    });
    if (!mounted) return;
    setState(() => _isSendingRest = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(goingRest
              ? 'Đã chuyển $plate sang "Tạm ngừng hoạt động"'
              : 'Đã kích hoạt lại $plate trở lại hoạt động'),
          backgroundColor: goingRest ? Colors.red.shade700 : Colors.green.shade600,
        ),
      );
      setState(() => _isResting = goingRest);
      if (mounted) await _loadDriverData(silent: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message']?.toString() ?? 'Cập nhật trạng thái thất bại'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
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
            const SizedBox(height: 8),
            // Nut "Bao nghi": chuyen trang thai Phuong tien thanh "Tam ngung hoat dong"
            SizedBox(
              height: 32,
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSendingRest ? null : _toggleVehicleRest,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isResting ? Colors.green.shade700 : Colors.red.shade700,
                  side: BorderSide(
                    color: _isResting ? Colors.green.shade400 : Colors.red.shade300,
                  ),
                  backgroundColor: _isResting ? Colors.green.shade50 : Colors.red.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(_isResting ? Icons.play_circle_outline : Icons.nightlight_outlined, size: 16),
                label: Text(
                  _isResting ? "Trở lại hoạt động" : "Báo nghỉ",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
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

            // Bước 1: PHIẾU CÂN (so GPS với Nơi nhận hàng)
            _buildMilestoneStepRow(
              title: "1. Chụp & Gửi Phiếu Cân",
              timeText: (trip?.weighSlipPhotoUrl != null)
                  ? (trip!.weighTonnage != null && trip.weighTonnage! > 0
                      ? "Khối lượng: ${trip.weighTonnage} Tấn (Đã gửi Điều phối)"
                      : "Đã chụp & gửi Phiếu cân (kèm GPS)")
                  : "Chụp phiếu cân khối lượng & mã lệnh (tại nơi nhận hàng)",
              isRecorded: trip?.weighSlipPhotoUrl != null,
              buttonLabel: trip?.weighSlipPhotoUrl != null ? "Chụp lại" : "Cân",
              isDisabled: stepDisabled,
              onPressed: () async {
                final updated = await SlipCaptureScreen.show(
                  context,
                  slipType: 'weigh',
                  orderId: trip?.orderId,
                  orderCode: trip?.orderCode ?? '',
                  vehiclePlate: state.selectedPlate,
                  orderData: trip?.rawOrder ?? state.activeOrder,
                );
                if (updated != null && mounted) {
                  await _loadDriverData(silent: true);
                }
              },
            ),
            const SizedBox(height: 8),

            // Bước 2: ĐẾN ĐIỂM GIAO (so GPS với Điểm giao hàng)
            _buildMilestoneStepRow(
              title: "2. Chụp ảnh ĐẾN ĐIỂM GIAO",
              timeText: (trip?.arrivalPhotoUrl != null)
                  ? "Đã gửi Điều phối (kèm GPS)"
                  : "Bắt buộc: chụp hiện trạng xe khi đến điểm giao hàng",
              isRecorded: trip?.arrivalPhotoUrl != null,
              buttonLabel: trip?.arrivalPhotoUrl != null ? "Chụp lại" : "Đến giao",
              isDisabled: stepDisabled,
              onPressed: () async {
                final updated = await SlipCaptureScreen.show(
                  context,
                  slipType: 'arrival',
                  orderId: trip?.orderId,
                  orderCode: trip?.orderCode ?? '',
                  vehiclePlate: state.selectedPlate,
                  orderData: trip?.rawOrder ?? state.activeOrder,
                );
                if (updated != null && mounted) {
                  await _loadDriverData(silent: true);
                }
              },
            ),
            const SizedBox(height: 8),

            // Bước 3: GIAO (Chụp & gửi Phiếu Giao Hàng)
            _buildMilestoneStepRow(
              title: "3. Chụp & Gửi Phiếu Giao Hàng",
              timeText: (trip?.deliverySlipPhotoUrl != null)
                  ? "Đã gửi Phiếu giao hàng (Chờ Điều phối xác nhận hoàn thành)"
                  : "Chụp biên bản giao nhận hàng gửi Điều phối kiểm tra",
              isRecorded: trip?.deliverySlipPhotoUrl != null,
              buttonLabel: trip?.deliverySlipPhotoUrl != null ? "Chụp lại" : "Giao",
              isDisabled: stepDisabled,
              onPressed: () async {
                final updated = await SlipCaptureScreen.show(
                  context,
                  slipType: 'delivery',
                  orderId: trip?.orderId,
                  orderCode: trip?.orderCode ?? '',
                  vehiclePlate: state.selectedPlate,
                  orderData: trip?.rawOrder ?? state.activeOrder,
                );
                if (updated != null && mounted) {
                  await _loadDriverData(silent: true);
                }
              },
            ),
            if (trip?.deliverySlipPhotoUrl != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.fact_check_outlined,
                      size: 18,
                      color: Colors.blue.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Đã gửi Phiếu giao hàng lên hệ thống. Đơn hàng sẽ hoàn thành sau khi Điều phối hoặc Quản lý kiểm tra hình chụp và xác nhận. Bạn vẫn có thể bấm 'Chụp lại' nếu ảnh mờ hoặc nhầm phiếu.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
            if (_myOrders.isEmpty)
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

  // ============ NGHIỆP VỤ ĐỔ DẦU, MỞ MÃ QR 1 LẦN & NGHIỆM THU (TASK T2) ============

  String _resolveFullImageUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${ApiConfig.host}$trimmed';
    }
    return '${ApiConfig.host}/$trimmed';
  }

  Future<String?> _captureOrPickFuelPhoto({required bool preferCamera}) async {
    try {
      if (preferCamera && (Platform.isAndroid || Platform.isIOS)) {
        final picker = ImagePicker();
        final XFile? photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 82,
          maxWidth: 1600,
        );
        if (photo != null) {
          final bytes = await photo.readAsBytes();
          final res = await AdminService.uploadImageBytes(bytes, photo.name);
          if (res['success'] == true && (res['url'] ?? '').toString().isNotEmpty) {
            return res['url'].toString();
          }
        }
        return null;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      Map<String, dynamic>? uploadRes;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        uploadRes = await AdminService.uploadImageBytes(file.bytes!, file.name);
      } else if (file.path != null && file.path!.isNotEmpty) {
        uploadRes = await AdminService.uploadImage(file.path!);
      }
      if (uploadRes != null &&
          uploadRes['success'] == true &&
          (uploadRes['url'] ?? '').toString().isNotEmpty) {
        return uploadRes['url'].toString();
      }
    } catch (_) {}
    return null;
  }

  Widget _buildFuelRequestAndQrCard(BuildContext context, AppState state) {
    final activeReq = _activeFuelRequest;
    final latestReq = _latestFuelRequest;
    final String status = (activeReq?['status'] ?? '').toString().toLowerCase();
    final bool isPending = status == 'pending';
    final bool isApproved = status == 'approved';
    final bool qrVisible = activeReq?['qr_visible'] == true;
    final String qrUrl = _resolveFullImageUrl(
      (activeReq?['active_qr_image_url'] ?? '').toString(),
    );
    final String qrWarning = (activeReq?['qr_warning'] ??
            'Lưu ý: Mã QR này chỉ có hiệu lực sử dụng cho 01 lần vào cây dầu (theo 01 lần phê duyệt đề xuất).')
        .toString();

    String badgeText = 'SẴN SÀNG ĐỀ XUẤT';
    Color badgeBg = Colors.orange.shade50;
    Color badgeBorder = Colors.orange.shade300;
    Color badgeTextCol = Colors.orange.shade900;

    if (isPending) {
      badgeText = 'CHỜ ĐIỀU PHỐI DUYỆT';
      badgeBg = Colors.blue.shade50;
      badgeBorder = Colors.blue.shade300;
      badgeTextCol = Colors.blue.shade900;
    } else if (isApproved) {
      badgeText = 'ĐÃ DUYỆT - MỞ MÃ QR 1 LẦN';
      badgeBg = Colors.green.shade50;
      badgeBorder = Colors.green.shade400;
      badgeTextCol = Colors.green.shade900;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: isApproved
              ? Colors.green.shade400
              : (isPending ? Colors.blue.shade300 : Colors.grey.shade300),
          width: isApproved ? 1.5 : 1,
        ),
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
                      Icon(
                        Icons.local_gas_station,
                        color: Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Nghiệp Vụ Đổ Dầu & Mã QR Cây Dầu',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeTextCol,
                      fontWeight: FontWeight.bold,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // TRƯỜNG HỢP 1: CHƯA CÓ ĐỀ XUẤT ĐANG MỞ (Tạo mới đề xuất đổ dầu)
            if (activeReq == null) ...[
              Text(
                'Khi cần ghé cây dầu: Bấm "Đề xuất đổ dầu" và bắt buộc chụp ảnh Đồng hồ taplo để gửi Điều phối viên duyệt mở Mã QR Cây dầu theo xe.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              if (latestReq != null &&
                  (latestReq['status'] ?? '').toString() == 'completed') ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        color: Colors.green.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Đã hoàn tất nghiệm thu lượt đổ dầu gần nhất tại ${latestReq['resolved_gas_station_name'] ?? latestReq['gas_station_name'] ?? 'cây dầu'} (Đã chụp đủ Taplo + Phiếu nhận dầu, Mã QR đã tự động ẩn).',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (latestReq != null &&
                  (latestReq['status'] ?? '').toString() == 'rejected') ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    'Đề xuất đổ dầu gần nhất bị từ chối${(latestReq['approved_note'] ?? '').toString().isNotEmpty ? ': ${latestReq['approved_note']}' : '.'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  icon: const Icon(Icons.local_gas_station, size: 18),
                  label: const Text(
                    'Đề xuất đổ dầu (Chụp Đồng hồ Taplo)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  onPressed: () => _showCreateFuelRequestDialog(state),
                ),
              ),
            ],

            // TRƯỜNG HỢP 2: ĐANG CHỜ ĐIỀU PHỐI VIÊN BẤM DUYỆT (status == 'pending')
            if (isPending && activeReq != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          color: Colors.blue.shade800,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đã gửi đề xuất đổ dầu cho xe ${activeReq['plate_number']} • Đang chờ Điều phối bấm Duyệt (OK)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Cây dầu đăng ký: ${activeReq['resolved_gas_station_name'] ?? activeReq['gas_station_name'] ?? 'Theo phân bổ Điều phối'}\n'
                      '• Chỉ số Km Taplo lúc đề xuất: ${activeReq['before_odo_km'] ?? '--'} km\n'
                      '• Tài xế chỉ được phép ghé cây dầu sau khi Điều phối viên bấm Duyệt (OK) và hệ thống mở Mã QR.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade800,
                          side: BorderSide(color: Colors.blue.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text(
                          'Kiểm tra trạng thái duyệt',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () => _loadDriverData(silent: false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade800,
                        side: BorderSide(color: Colors.orange.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text(
                        'Chụp lại Taplo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _showCreateFuelRequestDialog(
                        state,
                        existingRequest: activeReq,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // TRƯỜNG HỢP 3: ĐIỀU PHỐI ĐÃ DUYỆT -> MỞ MÃ QR 1 LẦN & CHỜ CHỤP 2 ẢNH NGHIỆM THU ĐÓNG QR
            if (isApproved && activeReq != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          color: Colors.green.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Điều phối đã duyệt (${activeReq['approved_by_name'] ?? 'Điều phối'}) • Mở Mã QR Cây dầu: ${activeReq['resolved_gas_station_name'] ?? activeReq['gas_station_name'] ?? ''}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (qrVisible && qrUrl.isNotEmpty)
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _showFullScreenFuelQrDialog(
                          qrUrl: qrUrl,
                          plateNumber: (activeReq['plate_number'] ?? '').toString(),
                          stationName:
                              (activeReq['resolved_gas_station_name'] ??
                                      activeReq['gas_station_name'] ??
                                      'Cây dầu')
                                  .toString(),
                          warningText: qrWarning,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.indigo.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                width: 220,
                                height: 220,
                                child: Image.network(
                                  qrUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Icon(
                                      Icons.qr_code_2,
                                      size: 72,
                                      color: Colors.indigo.shade400,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Xe ${activeReq['plate_number']} • Bấm vào ảnh QR để phóng to cho nhân viên cây dầu quét',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    // Hộp cảnh báo hiệu lực 1 lần bắt buộc theo Yêu cầu 02
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.shade600),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red.shade800,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              qrWarning,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Giai đoạn 3: Chụp 2 ảnh sau khi đổ dầu xong để đóng lượt đổ và tự động ẩn Mã QR
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.teal.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bước nghiệm thu sau khi đổ dầu xong (Đóng lượt đổ & Ẩn Mã QR):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.teal.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bắt buộc chụp đủ 02 ảnh: (1) Ảnh Đồng hồ taplo sau khi đổ và (2) Ảnh Phiếu nhận dầu. Ngay sau khi gửi, Mã QR Cây dầu sẽ tự động ẩn.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        icon: const Icon(Icons.task_alt, size: 18),
                        label: const Text(
                          'Chụp Taplo + Phiếu nhận dầu (Đóng lượt đổ & Ẩn QR)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        onPressed: () =>
                            _showCompleteFuelRequestDialog(activeReq, state),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullScreenFuelQrDialog({
    required String qrUrl,
    required String plateNumber,
    required String stationName,
    required String warningText,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        final Size screenSize = MediaQuery.of(ctx).size;
        final double targetWidth = math.min(560.0, screenSize.width * 0.94);
        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          constraints: BoxConstraints(
            minWidth: 300,
            maxWidth: targetWidth,
          ),
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_2, color: Colors.indigo.shade800, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mã QR Cây dầu - Xe $plateNumber ($stationName)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 16),
                SizedBox(
                  width: 300,
                  height: 300,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Image.network(qrUrl, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber.shade600),
                  ),
                  child: Text(
                    warningText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateFuelRequestDialog(
    AppState state, {
    Map<String, dynamic>? existingRequest,
  }) async {
    final String plate = state.selectedPlate.trim();
    if (plate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Vui lòng chọn phương tiện trước khi tạo đề xuất đổ dầu.'),
        ),
      );
      return;
    }

    int? selectedStationId = int.tryParse(
      (existingRequest?['gas_station_id'] ?? '').toString(),
    );
    if (selectedStationId == null && _gasStations.isNotEmpty) {
      for (final gs in _gasStations) {
        if (gs is Map && gs['qr_plates'] is List) {
          final plates = (gs['qr_plates'] as List)
              .map((e) => e.toString().toUpperCase())
              .toList();
          if (plates.contains(plate.toUpperCase())) {
            selectedStationId = int.tryParse((gs['id'] ?? '').toString());
            break;
          }
        }
      }
      selectedStationId ??= int.tryParse(
        (_gasStations.first['id'] ?? '').toString(),
      );
    }

    final gps =
        state.currentGpsStatus ?? state.allFleetVehiclesStatus[state.selectedPlate];
    final int currentOdo = (gps != null && gps.odoKm > 0)
        ? gps.odoKm
        : (state.todayInspection?.confirmedKm.round() ?? 0);

    final odoCtrl = TextEditingController(
      text: existingRequest?['before_odo_km'] != null
          ? existingRequest!['before_odo_km'].toString()
          : (currentOdo > 0 ? '$currentOdo' : ''),
    );
    final noteCtrl = TextEditingController(
      text: (existingRequest?['request_note'] ?? '').toString(),
    );
    String taploPhotoUrl =
        (existingRequest?['before_taplo_photo_url'] ?? '').toString();
    bool isUploadingPhoto = false;
    bool isSubmitting = false;
    String errorText = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final Size screenSize = MediaQuery.of(ctx).size;
          final double targetWidth = math.min(580.0, screenSize.width * 0.95);
          final previewTaploUrl = _resolveFullImageUrl(taploPhotoUrl);

          Future<void> handleTakeTaplo({required bool useCamera}) async {
            setDialogState(() {
              isUploadingPhoto = true;
              errorText = '';
            });
            final uploaded = await _captureOrPickFuelPhoto(
              preferCamera: useCamera,
            );
            setDialogState(() {
              isUploadingPhoto = false;
              if (uploaded != null && uploaded.isNotEmpty) {
                taploPhotoUrl = uploaded;
              } else {
                errorText = 'Chưa tải được ảnh Đồng hồ taplo. Vui lòng thử lại.';
              }
            });
          }

          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            constraints: BoxConstraints(
              minWidth: 310,
              maxWidth: targetWidth,
            ),
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.local_gas_station,
                          color: Colors.orange.shade800,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đề xuất đổ dầu - Xe $plate',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Bắt buộc chụp ảnh Đồng hồ taplo trước khi gửi đề xuất',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  if (_gasStations.isNotEmpty) ...[
                    DropdownButtonFormField<int>(
                      value: selectedStationId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Chọn Cây dầu dự kiến ghé đổ (*)',
                        prefixIcon: const Icon(
                          Icons.local_gas_station_outlined,
                          size: 18,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      items: _gasStations
                          .map((gs) {
                            final id = int.tryParse((gs['id'] ?? '').toString());
                            if (id == null) return null;
                            final name = (gs['name'] ?? 'Cây dầu #$id').toString();
                            return DropdownMenuItem<int>(
                              value: id,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          })
                          .whereType<DropdownMenuItem<int>>()
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedStationId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Khu vực bắt buộc chụp ảnh Đồng hồ taplo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: taploPhotoUrl.isNotEmpty
                            ? Colors.green.shade400
                            : Colors.orange.shade300,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Ảnh chụp Đồng hồ Taplo hiện tại (* Bắt buộc)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (taploPhotoUrl.isNotEmpty)
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.shade700,
                                size: 18,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (taploPhotoUrl.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              height: 150,
                              width: double.infinity,
                              color: Colors.black12,
                              child: Image.network(
                                previewTaploUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.image_outlined, size: 40),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            if (Platform.isAndroid || Platform.isIOS) ...[
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade800,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    icon: const Icon(Icons.camera_alt, size: 16),
                                    label: Text(
                                      isUploadingPhoto
                                          ? 'Đang tải...'
                                          : 'Chụp Camera Taplo',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    onPressed: isUploadingPhoto
                                        ? null
                                        : () => handleTakeTaplo(useCamera: true),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.indigo.shade800,
                                    side: BorderSide(
                                      color: Colors.indigo.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  icon: isUploadingPhoto
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.add_a_photo_outlined,
                                          size: 16,
                                        ),
                                  label: Text(
                                    taploPhotoUrl.isEmpty
                                        ? 'Chụp / Tải ảnh Đồng hồ Taplo'
                                        : 'Chụp / Đổi ảnh Taplo khác',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: isUploadingPhoto
                                      ? null
                                      : () => handleTakeTaplo(useCamera: false),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: odoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Số Km Đồng hồ Taplo (ODO)',
                            hintText: 'VD: 124650',
                            prefixIcon: const Icon(Icons.speed, size: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: noteCtrl,
                          decoration: InputDecoration(
                            labelText: 'Ghi chú (Tùy chọn)',
                            hintText: 'VD: Xin đổ dầu chạy chuyến chiều',
                            prefixIcon: const Icon(Icons.notes, size: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        errorText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 36,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_outlined, size: 16),
                          label: Text(
                            isSubmitting
                                ? 'Đang gửi...'
                                : 'Gửi Đề xuất đổ dầu',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          onPressed: (isSubmitting || isUploadingPhoto)
                              ? null
                              : () async {
                                  if (taploPhotoUrl.trim().isEmpty) {
                                    setDialogState(() {
                                      errorText =
                                          'Bắt buộc phải chụp ảnh Đồng hồ taplo trước khi gửi đề xuất đổ dầu!';
                                    });
                                    return;
                                  }
                                  setDialogState(() {
                                    isSubmitting = true;
                                    errorText = '';
                                  });
                                  final odoVal = double.tryParse(
                                    odoCtrl.text.trim().replaceAll(',', '.'),
                                  );
                                  final res =
                                      await AdminService.createFuelRequest(
                                        plateNumber: plate,
                                        beforeTaploPhotoUrl: taploPhotoUrl,
                                        beforeOdoKm: odoVal,
                                        gasStationId: selectedStationId,
                                        orderId: state.currentTrip?.orderId,
                                        orderCode: state.currentTrip?.orderCode,
                                        requestNote: noteCtrl.text.trim(),
                                        gpsLat: gps?.latitude,
                                        gpsLng: gps?.longitude,
                                      );
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    Navigator.pop(ctx);
                                    await _loadDriverData(silent: false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.green.shade700,
                                        content: const Text(
                                          'Đã gửi Đề xuất đổ dầu kèm ảnh Đồng hồ taplo cho Điều phối duyệt!',
                                        ),
                                      ),
                                    );
                                  } else {
                                    setDialogState(() {
                                      isSubmitting = false;
                                      errorText = (res['message'] ??
                                              'Gửi đề xuất thất bại')
                                          .toString();
                                    });
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCompleteFuelRequestDialog(
    Map<String, dynamic> activeReq,
    AppState state,
  ) async {
    final int? reqId = int.tryParse((activeReq['id'] ?? '').toString());
    if (reqId == null) return;
    final String plate = (activeReq['plate_number'] ?? state.selectedPlate)
        .toString();

    final odoCtrl = TextEditingController(
      text: (activeReq['before_odo_km'] ?? '').toString(),
    );
    final litersCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String afterTaploUrl = '';
    String receiptPhotoUrl = '';
    bool isUploadingTaplo = false;
    bool isUploadingReceipt = false;
    bool isSubmitting = false;
    String errorText = '';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final Size screenSize = MediaQuery.of(ctx).size;
          final double targetWidth = math.min(620.0, screenSize.width * 0.95);

          Future<void> pickPhoto({required bool isTaplo}) async {
            setDialogState(() {
              if (isTaplo) {
                isUploadingTaplo = true;
              } else {
                isUploadingReceipt = true;
              }
              errorText = '';
            });
            final uploaded = await _captureOrPickFuelPhoto(preferCamera: false);
            setDialogState(() {
              if (isTaplo) {
                isUploadingTaplo = false;
                if (uploaded != null && uploaded.isNotEmpty) {
                  afterTaploUrl = uploaded;
                }
              } else {
                isUploadingReceipt = false;
                if (uploaded != null && uploaded.isNotEmpty) {
                  receiptPhotoUrl = uploaded;
                }
              }
            });
          }

          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            constraints: BoxConstraints(
              minWidth: 310,
              maxWidth: targetWidth,
            ),
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.task_alt,
                          color: Colors.teal.shade800,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nghiệm thu sau khi đổ dầu - Xe $plate',
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Chụp đủ 02 ảnh (Đồng hồ taplo + Phiếu nhận dầu) để đóng lượt đổ và ẩn Mã QR',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  // Ảnh 1: Đồng hồ taplo sau khi đổ
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: afterTaploUrl.isNotEmpty
                            ? Colors.green.shade400
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          afterTaploUrl.isNotEmpty
                              ? Icons.check_circle
                              : Icons.speed_outlined,
                          color: afterTaploUrl.isNotEmpty
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            afterTaploUrl.isNotEmpty
                                ? '1. Đã chụp Ảnh Đồng hồ Taplo (sau khi đổ)'
                                : '1. Ảnh Đồng hồ Taplo sau khi đổ (* Bắt buộc)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            icon: isUploadingTaplo
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.camera_alt_outlined, size: 15),
                            label: Text(
                              afterTaploUrl.isEmpty ? 'Chụp Taplo' : 'Chụp lại',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: isUploadingTaplo
                                ? null
                                : () => pickPhoto(isTaplo: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Ảnh 2: Phiếu nhận dầu
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: receiptPhotoUrl.isNotEmpty
                            ? Colors.green.shade400
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          receiptPhotoUrl.isNotEmpty
                              ? Icons.check_circle
                              : Icons.receipt_long_outlined,
                          color: receiptPhotoUrl.isNotEmpty
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            receiptPhotoUrl.isNotEmpty
                                ? '2. Đã chụp Ảnh Phiếu nhận dầu (Phiếu đổ dầu)'
                                : '2. Ảnh Phiếu nhận dầu / Phiếu đổ dầu (* Bắt buộc)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            icon: isUploadingReceipt
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.camera_alt_outlined, size: 15),
                            label: Text(
                              receiptPhotoUrl.isEmpty
                                  ? 'Chụp Phiếu dầu'
                                  : 'Chụp lại',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onPressed: isUploadingReceipt
                                ? null
                                : () => pickPhoto(isTaplo: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: odoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Số Km Taplo sau khi đổ',
                            prefixIcon: const Icon(Icons.speed, size: 18),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: litersCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Số lít dầu nhận (Tùy chọn)',
                            prefixIcon: const Icon(
                              Icons.local_gas_station,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Ghi chú nghiệm thu (Tùy chọn)',
                      prefixIcon: const Icon(Icons.notes, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        errorText,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 36,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          icon: isSubmitting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline, size: 16),
                          label: Text(
                            isSubmitting
                                ? 'Đang gửi...'
                                : 'Hoàn tất đổ dầu & Ẩn Mã QR',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          onPressed:
                              (isSubmitting ||
                                  isUploadingTaplo ||
                                  isUploadingReceipt)
                              ? null
                              : () async {
                                  if (afterTaploUrl.isEmpty ||
                                      receiptPhotoUrl.isEmpty) {
                                    setDialogState(() {
                                      errorText =
                                          'Bắt buộc phải chụp đủ 02 ảnh: (1) Ảnh Đồng hồ taplo sau khi đổ và (2) Ảnh Phiếu nhận dầu!';
                                    });
                                    return;
                                  }
                                  setDialogState(() {
                                    isSubmitting = true;
                                    errorText = '';
                                  });
                                  final gps =
                                      state.currentGpsStatus ??
                                      state.allFleetVehiclesStatus[state
                                          .selectedPlate];
                                  final res =
                                      await AdminService.completeFuelRequest(
                                        reqId,
                                        afterTaploPhotoUrl: afterTaploUrl,
                                        fuelReceiptPhotoUrl: receiptPhotoUrl,
                                        afterOdoKm: double.tryParse(
                                          odoCtrl.text
                                              .trim()
                                              .replaceAll(',', '.'),
                                        ),
                                        litersFilled: double.tryParse(
                                          litersCtrl.text
                                              .trim()
                                              .replaceAll(',', '.'),
                                        ),
                                        note: noteCtrl.text.trim(),
                                        gpsLat: gps?.latitude,
                                        gpsLng: gps?.longitude,
                                      );
                                  if (!mounted) return;
                                  if (res['success'] == true) {
                                    Navigator.pop(ctx);
                                    await _loadDriverData(silent: false);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.green.shade700,
                                        content: const Text(
                                          'Đã nghiệm thu hoàn tất lượt đổ dầu! Mã QR Cây dầu đã tự động ẩn.',
                                        ),
                                      ),
                                    );
                                  } else {
                                    setDialogState(() {
                                      isSubmitting = false;
                                      errorText = (res['message'] ??
                                              'Không thể gửi nghiệm thu')
                                          .toString();
                                    });
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
