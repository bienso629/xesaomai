import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/quanlyxe_service.dart';

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
  String _statusFilter = 'all'; // 'all', 'running', 'stopped', 'off'

  // Toạ độ định vị cố định/lịch sử của các xe offline trong hệ thống
  static const Map<String, LatLng> _offlineFallbackLocations = {
    'BON SG-9999': LatLng(10.3800, 105.4200), // Long Xuyên, An Giang
    'SC-9964-3': LatLng(10.1800, 106.6000), // Bình Đại, Bến Tre
    'SG-9963 MŨI': LatLng(9.6500, 106.5200), // Duyên Hải, Trà Vinh
    'CT-079.18': LatLng(10.0452, 105.7469), // Cần Thơ
    'CT-079.18(02)': LatLng(10.0350, 105.7700), // Cái Răng, Cần Thơ
    'CT-103.02': LatLng(10.0200, 105.7800), // Cần Thơ
    '51D-743.06': LatLng(10.7200, 106.7300), // Quận 7, TP.HCM
    '51H-665.69': LatLng(10.8200, 106.6800), // Bình Thạnh, TP.HCM
    'CT-10933': LatLng(9.7800, 105.4700), // Vị Thanh, Hậu Giang
    'SG-9963': LatLng(10.7500, 106.6500), // Quận 5, TP.HCM
    '50H-999.88': LatLng(10.9300, 106.8500), // Biên Hòa, Đồng Nai
    '50H-888.99': LatLng(10.7000, 106.9400), // Nhơn Trạch, Đồng Nai
    '51D-999.00': LatLng(10.8600, 106.7800), // Thủ Đức, TP.HCM
  };

  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // Tự động làm mới toạ độ toàn đội xe mỗi 30 giây
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        context.read<AppState>().refreshAllFleetGps();
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final fleetStatuses = state.allFleetVehiclesStatus;
    final allPlates = QuanLyXeService.allFleetPlates;

    // Tổng hợp dữ liệu cho 28 xe
    final List<_VehicleMapItem> allVehicles = allPlates.map((plate) {
      final status = fleetStatuses[plate];
      if (status != null && status.latitude > 0 && status.longitude > 0) {
        return _VehicleMapItem(
          plate: plate,
          position: LatLng(status.latitude, status.longitude),
          speed: status.speed,
          isAccOn: status.isAccOn,
          address: status.address,
          driverName: status.driverName,
          odoKm: status.odoKm,
          isOnline: true,
          statusText: status.speed > 0
              ? 'Đang chạy (${status.speed.toStringAsFixed(0)} km/h)'
              : (status.isAccOn ? 'Nổ máy dừng' : 'Tắt máy đỗ'),
        );
      } else {
        final fallback = _offlineFallbackLocations[plate] ?? defaultCenter;
        return _VehicleMapItem(
          plate: plate,
          position: fallback,
          speed: 0,
          isAccOn: false,
          address: 'Vị trí bãi / Trạm vệ tinh',
          driverName: 'Chưa gắn ca',
          odoKm: 0,
          isOnline: false,
          statusText: 'Mất tín hiệu / Tắt máy',
        );
      }
    }).toList();

    // Thống kê số lượng theo trạng thái
    final int runningCount = allVehicles.where((v) => v.isOnline && v.speed > 0).length;
    final int idlingCount = allVehicles.where((v) => v.isOnline && v.speed == 0 && v.isAccOn).length;
    final int stoppedCount = allVehicles.where((v) => v.isOnline && !v.isAccOn).length;
    final int offlineCount = allVehicles.where((v) => !v.isOnline).length;

    // Lọc danh sách theo từ khoá và bộ lọc trạng thái
    final filteredVehicles = allVehicles.where((v) {
      if (_searchQuery.isNotEmpty && !v.plate.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_statusFilter == 'running') return v.isOnline && v.speed > 0;
      if (_statusFilter == 'stopped') return v.isOnline && v.speed == 0;
      if (_statusFilter == 'off') return !v.isOnline;
      return true;
    }).toList();

    // Tạo các Markers trên bản đồ
    final markers = allVehicles.map((vehicle) {
      final isSelected = vehicle.plate == (_selectedPlateOnMap ?? state.selectedPlate);
      final Color markerColor = vehicle.isOnline
          ? (vehicle.speed > 0 ? const Color(0xFF16A34A) : (vehicle.isAccOn ? const Color(0xFFEAB308) : const Color(0xFF64748B)))
          : const Color(0xFF94A3B8);

      return Marker(
        point: vehicle.position,
        width: isSelected ? 110 : 85,
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

    // Lấy thông tin xe được chọn để hiển thị thẻ chi tiết
    final selectedVehicle = allVehicles.firstWhere(
      (v) => v.plate == (_selectedPlateOnMap ?? state.selectedPlate),
      orElse: () => allVehicles.first,
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
        title: Row(
          children: [
            const Text(
              'Bản Đồ Giám Sát GPS Toàn Đội Xe',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '28 Xe',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới toạ độ toàn đội xe',
            icon: state.isLoadingFleetGps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                  )
                : const Icon(Icons.refresh),
            onPressed: () => state.refreshAllFleetGps(),
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
          // Khung danh sách 28 xe bên trái (Tương tự ảnh giao diện)
          if (_showPanel)
            Container(
              width: isWide ? 340 : 280,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey.shade300, width: 1)),
              ),
              child: Column(
                children: [
                  // Thanh trạng thái thống kê màu sắc
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    color: const Color(0xFFF8FAFC),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('Tất cả (28)', 'all'),
                          const SizedBox(width: 4),
                          _buildFilterChip('Đang chạy ($runningCount)', 'running'),
                          const SizedBox(width: 4),
                          _buildFilterChip('Đang đỗ ($stoppedCount)', 'stopped'),
                          const SizedBox(width: 4),
                          _buildFilterChip('Offline ($offlineCount)', 'off'),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 12),
                  // Danh sách cuộn các xe
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredVehicles.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, index) {
                        final v = filteredVehicles[index];
                        final isSel = v.plate == (_selectedPlateOnMap ?? state.selectedPlate);
                        final Color statusColor = v.isOnline
                            ? (v.speed > 0
                                ? const Color(0xFF16A34A)
                                : (v.isAccOn ? const Color(0xFFEAB308) : const Color(0xFF64748B)))
                            : const Color(0xFF94A3B8);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedPlateOnMap = v.plate;
                            });
                            _mapController.move(v.position, 15.0);
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
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            v.plate,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: isSel ? Colors.blue.shade900 : Colors.black87,
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
                                Row(
                                  children: [
                                    Text(
                                      'Xe: ${selectedVehicle.plate}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(width: 8),
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
                        tooltip: 'Xem toàn bộ 28 xe',
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
  final double speed;
  final bool isAccOn;
  final String address;
  final String driverName;
  final int odoKm;
  final bool isOnline;
  final String statusText;

  _VehicleMapItem({
    required this.plate,
    required this.position,
    required this.speed,
    required this.isAccOn,
    required this.address,
    required this.driverName,
    required this.odoKm,
    required this.isOnline,
    required this.statusText,
  });
}
