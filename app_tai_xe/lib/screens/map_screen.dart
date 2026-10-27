import '../widgets/realtime_header_notification_bell.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';

class MapScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onToggleDesktopSidebar;
  final bool isDesktopSidebarCollapsed;

  const MapScreen({
    super.key,
    this.onOpenDrawer,
    this.onToggleDesktopSidebar,
    this.isDesktopSidebarCollapsed = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Toạ độ mặc định khu vực Đông Nam Bộ & TP. Hồ Chí Minh
  static const LatLng defaultCenter = LatLng(10.8500, 107.0000);

  final MapController _mapController = MapController();
  // Key bản đồ số Map Tiles Vietmap (được hệ thống quanlyxe.vn sử dụng tải tile)
  final String _vietMapApiKey = 'edfac336d2c0462850d93fd5859878b1ad84b769ddfed745';

  // Bộ lọc tìm kiếm và hiển thị
  String _searchQuery = '';
  String? _selectedPlateOnMap;
  bool _showPanel = true;
  String _statusFilter = 'running'; // 'all', 'running', 'stopped', 'assigned' - Mặc định tab "Đang chạy"

  Timer? _autoRefreshTimer;
  List<dynamic> _allOrders = [];
  bool _isLoadingOrders = false;


  Future<void> _loadAllOrders() async {
    if (!mounted) return;
    setState(() {
      _isLoadingOrders = true;
    });
    try {
      final orders = await AdminService.fetchOrders();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _isLoadingOrders = false;
        });
      }
    } catch (e) {
      debugPrint("MapScreen load orders error: $e");
      if (mounted) {
        setState(() {
          _isLoadingOrders = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // Tải dữ liệu GPS từ 2 dịch vụ Vietmap & Bình Anh ngay khi mở màn hình
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().refreshAllFleetGps();
        _loadAllOrders();
      }
    });
    // Tự động làm mới toạ độ toàn đội xe mỗi 30 giây
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        context.read<AppState>().refreshAllFleetGps();
        _loadAllOrders();
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }


  /// Kiem tra xe co don hang dang thuc hien (chua hoan thanh / chua huy) hay khong
  bool _hasActiveOrder(String plate) {
    final cleanPlate = plate.replaceAll('-', '').replaceAll('.', '').trim().toLowerCase();
    return _allOrders.any((o) {
      final assignedPlate = (o['assigned_vehicle_plate'] ?? '').toString().replaceAll('-', '').replaceAll('.', '').trim().toLowerCase();
      final status = (o['status'] ?? 'waiting').toString().toLowerCase();
      return assignedPlate == cleanPlate && status != 'completed' && status != 'cancelled';
    });
  }

  Widget _buildOrderInfo(String plate) {
    // Chuẩn hóa biển số xe để so sánh chính xác nhất
    final cleanPlate = plate.replaceAll('-', '').replaceAll('.', '').trim().toLowerCase();
    
    // Tìm đơn hàng chưa hoàn thành / chưa hủy gắn với xe này
    final vehicleOrders = _allOrders.where((o) {
      final assignedPlate = (o['assigned_vehicle_plate'] ?? '').toString().replaceAll('-', '').replaceAll('.', '').trim().toLowerCase();
      final status = (o['status'] ?? 'waiting').toString().toLowerCase();
      return assignedPlate == cleanPlate && status != 'completed' && status != 'cancelled';
    }).toList();

    if (_isLoadingOrders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blue),
            ),
            SizedBox(width: 6),
            Text('Đang tải thông tin đơn hàng...', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );
    }

    if (vehicleOrders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 12, color: Colors.grey),
            SizedBox(width: 4),
            Text(
              'Xe hiện chưa có đơn hàng vận chuyển nào',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    final order = vehicleOrders.first; // Lấy đơn hàng hiện tại mới nhất
    final orderCode = (order['order_code'] ?? 'MÃ ĐƠN').toString();
    final customerName = (order['customer_name'] ?? 'Khách lẻ').toString();
    final productName = (order['product_name'] ?? 'Hàng hóa').toString();
    final statusStr = (order['status_label'] ?? order['status'] ?? 'Đang xử lý').toString();
    final deliveryAddress = (order['delivery_address'] ?? 'Điểm giao hàng').toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
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
              Icon(Icons.local_shipping, size: 14, color: Colors.blue.shade800),
              const SizedBox(width: 6),
              Text(
                'Đơn: $orderCode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue.shade900),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.shade800,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  statusStr.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Khách: $customerName | Hàng: $productName',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(height: 1),
          Text(
            'Điểm giao: $deliveryAddress',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  String _formatGpsTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fleetStatuses = state.allFleetVehiclesStatus;
    final sortedPlates = fleetStatuses.keys.toList()..sort();

    // Tổng hợp dữ liệu thực tế từ đúng 2 dịch vụ Vietmap & Bình Anh
    final List<_VehicleMapItem> allVehicles = sortedPlates.map((plate) {
      final status = fleetStatuses[plate]!;
      final bool hasValidCoords = status.latitude > 0 && status.longitude > 0;
      final String timeStr = _formatGpsTime(status.gpsTime);
      final String providerCode = status.gpsProvider.toLowerCase();
      final String providerLabel = status.providerDisplayName;

      String statusText;
      if (hasValidCoords) {
        if (status.speed > 0) {
          statusText = 'Đang chạy (${status.speed.toStringAsFixed(0)} km/h)';
        } else if (status.isAccOn) {
          statusText = 'Nổ máy dừng';
        } else {
          statusText = status.stateLabel != null && status.stateLabel!.isNotEmpty
              ? status.stateLabel!
              : 'Tắt máy đỗ';
        }
      } else {
        statusText = timeStr.isNotEmpty ? 'Mất tín hiệu ($timeStr)' : 'Chưa có tọa độ GPS';
      }

      return _VehicleMapItem(
        plate: plate,
        position: hasValidCoords ? LatLng(status.latitude, status.longitude) : defaultCenter,
        hasValidCoords: hasValidCoords,
        speed: status.speed,
        isAccOn: status.isAccOn,
        address: status.address.isNotEmpty ? status.address : 'Chưa xác định vị trí',
        driverName: status.driverName.isNotEmpty ? status.driverName : 'Chưa gắn thẻ',
        odoKm: status.odoKm,
        isOnline: hasValidCoords,
        statusText: statusText,
        providerCode: providerCode,
        providerLabel: providerLabel,
      );
    }).toList();

    // Thống kê theo nguồn dịch vụ GPS
    final int vietmapCount = allVehicles.where((v) => v.providerCode == 'vietmap').length;
    final int binhanhCount = allVehicles.where((v) => v.providerCode == 'binhanh').length;

    final providerFiltered = allVehicles;

    // Thống kê số lượng theo trạng thái
    final int runningCount = providerFiltered.where((v) => v.isOnline && v.speed > 0).length;
    final int idlingCount = providerFiltered.where((v) => v.isOnline && v.speed == 0 && v.isAccOn).length;
    final int stoppedCount = providerFiltered.where((v) => v.isOnline && !v.isAccOn).length;
    final int offlineCount = providerFiltered.where((v) => !v.isOnline).length;
    // So xe da duoc gan don hang (don chua hoan thanh / chua huy)
    final int assignedOrderCount = providerFiltered.where((v) => _hasActiveOrder(v.plate)).length;

    // Lọc danh sách theo từ khoá và bộ lọc trạng thái
    final filteredVehicles = providerFiltered.where((v) {
      if (_searchQuery.isNotEmpty && !v.plate.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_statusFilter == 'running') return v.isOnline && v.speed > 0;
      if (_statusFilter == 'stopped') return v.isOnline && v.speed == 0;
      if (_statusFilter == 'assigned') return _hasActiveOrder(v.plate);
      return true;
    }).toList();

    // Tạo các Markers trên bản đồ (chỉ vẽ các xe có toạ độ hợp lệ thuộc bộ lọc nguồn hiện tại)
    final markers = filteredVehicles.where((v) => v.hasValidCoords).map((vehicle) {
      final isSelected = vehicle.plate == (_selectedPlateOnMap ?? state.selectedPlate);
      final Color markerColor = vehicle.isOnline
          ? (vehicle.speed > 0
              ? const Color(0xFF16A34A)
              : (vehicle.isAccOn ? const Color(0xFFEAB308) : const Color(0xFF64748B)))
          : const Color(0xFF94A3B8);

      return Marker(
        point: vehicle.position,
        width: isSelected ? 116 : 92,
        height: isSelected ? 65 : 55,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedPlateOnMap = vehicle.plate;
            });
            _mapController.move(vehicle.position, 15.0);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0F172A) : markerColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected ? Colors.amber : Colors.white,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Text(
                  vehicle.plate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(
                Icons.local_shipping,
                color: markerColor,
                size: isSelected ? 34 : 26,
              ),
            ],
          ),
        ),
      );
    }).toList();

    // Lấy thông tin xe được chọn để hiển thị thẻ chi tiết (chỉ chọn từ danh sách đang lọc)
    final _VehicleMapItem? selectedVehicle = filteredVehicles.isEmpty
        ? null
        : filteredVehicles.firstWhere(
            (v) => v.plate == (_selectedPlateOnMap ?? state.selectedPlate),
            orElse: () => filteredVehicles.first,
          );

    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.blueGrey.shade900,
        leading: widget.onOpenDrawer != null
            ? IconButton(
                icon: const Icon(Icons.menu),
                tooltip: "Mở menu chức năng",
                onPressed: widget.onOpenDrawer,
              )
            : (widget.onToggleDesktopSidebar != null && widget.isDesktopSidebarCollapsed
                ? IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: "Mở rộng thanh điều hướng",
                    onPressed: widget.onToggleDesktopSidebar,
                  )
                : null),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            const Text(
              'Bản Đồ Giám Sát GPS Toàn Đội Xe',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${allVehicles.length} Xe',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Text(
                'Vietmap: $vietmapCount | Bình Anh: $binhanhCount',
                style: TextStyle(
                  color: Colors.indigo.shade900,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        actions: [
          const RealtimeHeaderNotificationBell(),
          IconButton(
            tooltip: 'Làm mới toạ độ Vietmap & Bình Anh',
            icon: state.isLoadingFleetGps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                  )
                : const Icon(Icons.refresh),
            onPressed: () => state.refreshAllFleetGps(force: true),
          ),
          IconButton(
            tooltip: _showPanel ? 'Ẩn danh sách xe' : 'Hiện danh sách xe',
            icon: Icon(_showPanel ? Icons.view_sidebar : Icons.view_sidebar_outlined),
            onPressed: () {
              setState(() {
                _showPanel = !_showPanel;
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.grey.shade300,
            height: 1,
          ),
        ),
      ),
      body: Row(
        children: [
          // Khung danh sách xe bên trái
          if (_showPanel)
            Container(
              width: isWide ? 360 : 320,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1)),
              ),
              child: Column(
                children: [
                  // Thanh trạng thái thống kê màu sắc
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatusBadge('Chạy', runningCount, const Color(0xFF16A34A)),
                        _buildStatusBadge('Dừng máy', idlingCount, const Color(0xFFEAB308)),
                        _buildStatusBadge('Tắt máy', stoppedCount, const Color(0xFF64748B)),
                        _buildStatusBadge('Mất tín hiệu', offlineCount, const Color(0xFF94A3B8)),
                      ],
                    ),
                  ),
                  // Ô tìm kiếm biển số
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Tìm biển kiểm soát...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim();
                        });
                      },
                    ),
                  ),
                  // Bộ lọc trạng thái nhanh
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _buildFilterChip('Tất cả (${providerFiltered.length})', 'all'),
                        _buildFilterChip('Đang chạy ($runningCount)', 'running'),
                        _buildFilterChip('Đang đỗ (${idlingCount + stoppedCount})', 'stopped'),
                        _buildFilterChip('Đã gắn đơn ($assignedOrderCount)', 'assigned'),
                      ],
                    ),
                  ),
                  const Divider(height: 12),
                  // Danh sách cuộn các xe
                  Expanded(
                    child: filteredVehicles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                state.isLoadingFleetGps
                                    ? 'Đang đồng bộ dữ liệu GPS từ Vietmap & Bình Anh...'
                                    : 'Không có xe phù hợp bộ lọc',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredVehicles.length,
                            separatorBuilder: (_, _) => Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (context, index) {
                              final v = filteredVehicles[index];
                              final isSel = v.plate == (_selectedPlateOnMap ?? state.selectedPlate);
                              final Color statusColor = v.isOnline
                                  ? (v.speed > 0
                                      ? const Color(0xFF16A34A)
                                      : (v.isAccOn ? const Color(0xFFEAB308) : const Color(0xFF64748B)))
                                  : const Color(0xFF94A3B8);
                              final bool isBinhAnh = v.providerCode == 'binhanh';

                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    _selectedPlateOnMap = v.plate;
                                  });
                                  if (v.hasValidCoords) {
                                    _mapController.move(v.position, 15.0);
                                  }
                                },
                                child: Container(
                                  color: isSel ? Colors.blue.shade50 : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          v.plate,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 13,
                                                            color: isSel ? Colors.blue.shade900 : Colors.black87,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                        decoration: BoxDecoration(
                                                          color: isBinhAnh
                                                              ? Colors.teal.shade50
                                                              : Colors.indigo.shade50,
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(
                                                            color: isBinhAnh
                                                                ? Colors.teal.shade200
                                                                : Colors.indigo.shade200,
                                                            width: 0.8,
                                                          ),
                                                        ),
                                                        child: Text(
                                                          v.providerLabel,
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            fontWeight: FontWeight.w600,
                                                            color: isBinhAnh
                                                                ? Colors.teal.shade800
                                                                : Colors.indigo.shade800,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (v.isOnline && v.speed > 0)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.shade100,
                                                      borderRadius: BorderRadius.circular(3),
                                                    ),
                                                    child: Text(
                                                      '${v.speed.toStringAsFixed(0)} km/h',
                                                      style: TextStyle(
                                                        color: Colors.green.shade900,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              v.address,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

          // Vùng hiển thị bản đồ Vietmap
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(
                    initialCenter: defaultCenter,
                    initialZoom: 9.5,
                    minZoom: 5.0,
                    maxZoom: 18.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}@2x.png?apikey=$_vietMapApiKey',
                      userAgentPackageName: 'com.taxilogistics.driver.app_tai_xe',
                      tileProvider: NetworkTileProvider(),
                    ),
                    MarkerLayer(markers: markers),
                  ],
                ),

                // Card thông tin chi tiết của xe đang chọn (Góc trên)
                if (selectedVehicle != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              selectedVehicle.isOnline && selectedVehicle.speed > 0
                                  ? Icons.directions_car
                                  : (selectedVehicle.isAccOn ? Icons.power_settings_new : Icons.local_parking),
                              color: selectedVehicle.isOnline
                                  ? (selectedVehicle.speed > 0
                                      ? Colors.green
                                      : (selectedVehicle.isAccOn ? Colors.amber.shade700 : Colors.grey))
                                  : Colors.grey,
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        'Xe: ${selectedVehicle.plate}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: selectedVehicle.providerCode == 'binhanh'
                                              ? Colors.teal.shade50
                                              : Colors.indigo.shade50,
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                            color: selectedVehicle.providerCode == 'binhanh'
                                                ? Colors.teal.shade300
                                                : Colors.indigo.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          'GPS: ${selectedVehicle.providerLabel}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: selectedVehicle.providerCode == 'binhanh'
                                                ? Colors.teal.shade900
                                                : Colors.indigo.shade900,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: selectedVehicle.isOnline ? Colors.green.shade50 : Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(
                                            color: selectedVehicle.isOnline ? Colors.green.shade300 : Colors.grey.shade400,
                                          ),
                                        ),
                                        child: Text(
                                          selectedVehicle.statusText,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: selectedVehicle.isOnline ? Colors.green.shade900 : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Vị trí: ${selectedVehicle.address}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                                  ),
                                  // Tìm kiếm đơn hàng gán cho xe hiện tại
                                  _buildOrderInfo(selectedVehicle.plate),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tài xế: ${selectedVehicle.driverName} | Tốc độ: ${selectedVehicle.speed.toStringAsFixed(0)} km/h | ODO: ${selectedVehicle.odoKm} km',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blueGrey.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Các nút điều khiển Zoom và vị trí
                Positioned(
                  bottom: 24,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'btn_zoom_in_all',
                        backgroundColor: Colors.white,
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom + 1);
                        },
                        child: const Icon(Icons.add, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'btn_zoom_out_all',
                        backgroundColor: Colors.white,
                        onPressed: () {
                          final currentZoom = _mapController.camera.zoom;
                          _mapController.move(_mapController.camera.center, currentZoom - 1);
                        },
                        child: const Icon(Icons.remove, color: Colors.black87),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'btn_overview_all',
                        tooltip: 'Xem toàn bộ đội xe (${allVehicles.length} xe)',
                        backgroundColor: Colors.white,
                        onPressed: () {
                          _mapController.move(defaultCenter, 9.5);
                        },
                        child: const Icon(Icons.map, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _statusFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? const Color(0xFF1E293B) : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

}

class _VehicleMapItem {
  final String plate;
  final LatLng position;
  final bool hasValidCoords;
  final double speed;
  final bool isAccOn;
  final String address;
  final String driverName;
  final int odoKm;
  final bool isOnline;
  final String statusText;
  final String providerCode;
  final String providerLabel;

  _VehicleMapItem({
    required this.plate,
    required this.position,
    required this.hasValidCoords,
    required this.speed,
    required this.isAccOn,
    required this.address,
    required this.driverName,
    required this.odoKm,
    required this.isOnline,
    required this.statusText,
    required this.providerCode,
    required this.providerLabel,
  });
}
