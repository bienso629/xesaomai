import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Toạ độ mặc định TP. Hồ Chí Minh (Trung tâm Quận 1 / Chợ Bến Thành)
  static const LatLng defaultHcmLocation = LatLng(10.7769, 106.7009);
  static const LatLng customerLocation = LatLng(10.7025, 106.9452); // Trạm trộn Nhơn Trạch

  final MapController _mapController = MapController();
  final String _vietMapApiKey = '7GDc6Vk0KdTGBx6yRKYZGM6eQKHThzA4';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final liveStatus = state.currentGpsStatus;

    // Vị trí xe từ GPS Bình Anh thực tế (hoặc mặc định trung tâm HCM nếu chưa nhận toạ độ)
    final LatLng vehiclePos = (liveStatus != null && liveStatus.latitude > 0 && liveStatus.longitude > 0)
        ? LatLng(liveStatus.latitude, liveStatus.longitude)
        : defaultHcmLocation;

    return Scaffold(
      appBar: AppBar(
        title: Text('Giám Sát: ${state.selectedPlate} (VietMap)'),
        backgroundColor: Colors.amber.shade700,
        actions: [
          IconButton(
            tooltip: 'Làm mới toạ độ GPS',
            icon: state.isLoadingGps
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh),
            onPressed: () => state.refreshCurrentVehicleGps(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: vehiclePos,
              initialZoom: 14.5,
              minZoom: 5.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}@2x.png?apikey=$_vietMapApiKey',
                userAgentPackageName: 'com.taxilogistics.driver.app_tai_xe',
                tileProvider: NetworkTileProvider(),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: vehiclePos,
                    width: 80,
                    height: 70,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade900,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            state.selectedPlate,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Icon(
                          Icons.local_shipping,
                          color: (liveStatus?.isAccOn ?? true) ? Colors.green.shade700 : Colors.blueGrey,
                          size: 34,
                        ),
                      ],
                    ),
                  ),
                  const Marker(
                    point: customerLocation,
                    width: 50,
                    height: 50,
                    child: Icon(
                      Icons.location_on,
                      color: Colors.redAccent,
                      size: 44,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
              color: Colors.white.withOpacity(0.95),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      (liveStatus?.isAccOn ?? false) ? Icons.directions_car : Icons.power_settings_new,
                      color: (liveStatus?.isAccOn ?? false) ? Colors.green : Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Công ty Cổ phần Thương Mại Xi Măng Sao Mai',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            liveStatus != null
                                ? 'GPS: ${liveStatus.address.isNotEmpty ? liveStatus.address : "Đang cập nhật"}'
                                : 'Vị trí: Trung tâm TP.HCM (Chưa có GPS)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                          Text(
                            liveStatus != null
                                ? 'Tốc độ: ${liveStatus.speed.toStringAsFixed(0)} km/h | Máy: ${liveStatus.isAccOn ? "BẬT" : "TẮT"} | ODO: ${liveStatus.odoKm} km'
                                : 'Cách điểm giao: 1.2 km (khoảng 4 phút)',
                            style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_in',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, currentZoom + 1);
                  },
                  child: const Icon(Icons.add, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_out',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, currentZoom - 1);
                  },
                  child: const Icon(Icons.remove, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'btn_my_location',
                  backgroundColor: Colors.white,
                  onPressed: () {
                    _mapController.move(defaultHcmLocation, 15.0);
                  },
                  child: const Icon(Icons.my_location, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
