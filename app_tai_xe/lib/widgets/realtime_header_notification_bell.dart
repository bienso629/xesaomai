import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';
import '../models/breakdown_model.dart';

class RealtimeHeaderNotificationBell extends StatefulWidget {
  const RealtimeHeaderNotificationBell({super.key});

  @override
  State<RealtimeHeaderNotificationBell> createState() =>
      _RealtimeHeaderNotificationBellState();
}

class _RealtimeHeaderNotificationBellState
    extends State<RealtimeHeaderNotificationBell> {
  Timer? _timer;
  bool _isLoading = false;
  List<dynamic> _inspections = [];
  List<dynamic> _orders = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _fetchData(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (_isLoading && !silent) return;
    if (!silent) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        AdminService.fetchInspections(),
        AdminService.fetchOrders(),
      ]);
      if (mounted) {
        setState(() {
          _inspections = results[0];
          _orders = results[1];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  DateTime _parseTime(dynamic raw, [DateTime? fallback]) {
    if (raw != null) {
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) return dt.toLocal();
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatClock(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '--:--';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$h:$m ($d/$mo)';
  }

  List<Map<String, dynamic>> _collectReports(AppState state) {
    final reports = <Map<String, dynamic>>[];

    // 1. Báo cáo Kiểm tra xe 5 ảnh
    for (final item in _inspections) {
      if (item is! Map) continue;
      final plate = (item['plate_number'] ?? 'Chưa rõ xe').toString();
      final driverName =
          (item['driver_name'] ?? item['driver_username'] ?? 'Tài xế')
              .toString();
      final phone = (item['driver_phone'] ?? '').toString();
      final flagStatus = (item['flag_status'] ?? 'pending').toString();
      final hasDeviation = item['flag_deviation_km'] == true;
      final hasAbnormal = item['has_abnormal_flag'] == true;
      final kmConfirmed = item['km_confirmed'] ?? item['km_ocr'];
      final flagReason = (item['flag_reason'] ?? '').toString().trim();
      final dt = _parseTime(item['completed_at'] ?? item['created_at']);

      String statusLabel;
      Color badgeColor;
      IconData iconData;
      String groupKey = 'INSPECTION';

      if (flagStatus == 'approved') {
        statusLabel = 'Đủ điều kiện nhận chuyến';
        badgeColor = Colors.green.shade700;
        iconData = Icons.verified_rounded;
      } else if (flagStatus == 'rejected' || hasAbnormal) {
        statusLabel = 'Yêu cầu chụp lại / Bất thường';
        badgeColor = Colors.red.shade700;
        iconData = Icons.report_problem_rounded;
        groupKey = 'ALERT';
      } else if (flagStatus == 'monitoring' || hasDeviation) {
        statusLabel = 'Đang theo dõi kỹ thuật';
        badgeColor = Colors.orange.shade800;
        iconData = Icons.visibility_rounded;
        groupKey = 'ALERT';
      } else {
        statusLabel = 'Vừa gửi 5 ảnh giao ca';
        badgeColor = Colors.blue.shade700;
        iconData = Icons.photo_camera_rounded;
      }

      final kmText =
          kmConfirmed != null ? 'ODO: $kmConfirmed km' : 'Đủ 5 góc ảnh';
      final desc = flagReason.isNotEmpty
          ? 'Kiểm tra xe $plate ($kmText) • Ghi chú: $flagReason'
          : 'Đã gửi báo cáo kiểm tra 5 ảnh xe $plate ($kmText)';

      reports.add({
        'driver_name': driverName,
        'phone': phone,
        'plate': plate,
        'title': statusLabel,
        'description': desc,
        'time_label': _formatClock(dt),
        'timestamp': dt,
        'color': badgeColor,
        'icon': iconData,
        'group': groupKey,
        'type': 'INSPECTION',
      });
    }

    // 2. Báo cáo Đơn hàng & Cảnh báo GPS ngoài bán kính
    for (final o in _orders) {
      if (o is! Map) continue;
      final orderCode = (o['order_code'] ?? '').toString();
      final plate = (o['assigned_vehicle_plate'] ?? '').toString();
      final driverName = (o['driver_name'] ?? '').toString();
      if (plate.isEmpty && driverName.isEmpty) continue;

      final status = (o['status'] ?? 'assigned').toString().toLowerCase();
      final product = (o['product_name'] ?? 'Vật liệu').toString();
      final pickup = (o['pickup_address'] ?? '').toString();
      final delivery = (o['delivery_address'] ?? '').toString();
      final tons = o['cargo_weight_tons'];
      final dt = _parseTime(o['created_at']);

      String statusLabel;
      Color badgeColor;
      IconData iconData;
      String groupKey = 'TRIP';

      switch (status) {
        case 'in_transit':
        case 'delivering':
        case 'moving':
          statusLabel = 'Đang vận chuyển trên đường';
          badgeColor = Colors.blue.shade700;
          iconData = Icons.local_shipping_rounded;
          break;
        case 'arrived':
        case 'at_site':
          statusLabel = 'Đã đến điểm giao hàng';
          badgeColor = Colors.teal.shade700;
          iconData = Icons.location_on_rounded;
          break;
        case 'pumping':
        case 'unloading':
          statusLabel = 'Đang bơm / xả hàng';
          badgeColor = Colors.indigo.shade700;
          iconData = Icons.downloading_rounded;
          break;
        case 'completed':
        case 'done':
          statusLabel = 'Hoàn thành chuyến hàng';
          badgeColor = Colors.green.shade700;
          iconData = Icons.task_alt_rounded;
          break;
        case 'delayed':
        case 'incident':
        case 'cancelled':
          statusLabel = 'Cảnh báo chậm trễ / Sự cố';
          badgeColor = Colors.red.shade700;
          iconData = Icons.warning_amber_rounded;
          groupKey = 'ALERT';
          break;
        default:
          statusLabel = 'Đã nhận lệnh điều động';
          badgeColor = Colors.amber.shade900;
          iconData = Icons.assignment_ind_rounded;
      }

      final weightStr = tons != null ? ' • $tons tấn' : '';
      reports.add({
        'driver_name': driverName.isNotEmpty ? driverName : 'Tài xế xe $plate',
        'phone': '',
        'plate': plate.isNotEmpty ? plate : 'Chưa gán xe',
        'title': statusLabel,
        'description':
            'Đơn $orderCode ($product$weightStr): $pickup → $delivery',
        'time_label': _formatClock(dt),
        'timestamp': dt,
        'color': badgeColor,
        'icon': iconData,
        'group': groupKey,
        'type': 'ORDER',
      });

      // Kiểm tra xem có ảnh nào bị CẢNH BÁO NGOÀI BÁN KÍNH GPS (matched == 'NONE')
      final photoGeo = o['photo_geo_check'];
      if (photoGeo is Map) {
        photoGeo.forEach((photoType, checkData) {
          if (checkData is Map && checkData['matched'] == 'NONE') {
            final pName = _getPhotoTypeName(photoType.toString());
            final distPickup = checkData['pickup_dist_m'];
            final distDelivery = checkData['delivery_dist_m'];

            String distMsg = '';
            if (distPickup != null && distDelivery != null) {
              distMsg =
                  ' (Cách Nhận: ${distPickup}m, Cách Giao: ${distDelivery}m)';
            }

            reports.add({
              'driver_name':
                  driverName.isNotEmpty ? driverName : 'Tài xế xe $plate',
              'phone': '',
              'plate': plate.isNotEmpty ? plate : 'Chưa gán xe',
              'title': 'CẢNH BÁO GPS: Ảnh ngoài bán kính',
              'description':
                  'Đơn $orderCode: Chụp ảnh $pName không thuộc Nơi nhận & Điểm giao$distMsg',
              'time_label': _formatClock(dt),
              'timestamp': dt,
              'color': Colors.red.shade700,
              'icon': Icons.location_off_rounded,
              'group': 'ALERT',
              'type': 'GPS_ALERT',
            });
          }
        });
      }
    }

    // 3. Báo cáo hỏng xe trong phiên AppState
    for (final b in state.breakdownReports) {
      final dt = b.timestamp;
      reports.add({
        'driver_name': state.currentDriverName,
        'phone': '',
        'plate': b.vehiclePlate,
        'title': 'Báo hỏng xe: ${b.category.displayName}',
        'description': b.description.isNotEmpty
            ? b.description
            : 'Tài xế gửi cảnh báo sự cố kỹ thuật cần hỗ trợ',
        'time_label': _formatClock(dt),
        'timestamp': dt,
        'color': Colors.red.shade700,
        'icon': Icons.car_crash_rounded,
        'group': 'ALERT',
        'type': 'VEHICLE',
      });
    }

    // Sắp xếp mới nhất lên đầu
    reports.sort((a, b) {
      final tA = a['timestamp'] as DateTime;
      final tB = b['timestamp'] as DateTime;
      return tB.compareTo(tA);
    });

    return reports;
  }

  String _getPhotoTypeName(String key) {
    switch (key) {
      case 'pump_slip_before':
        return 'Trước khi bơm';
      case 'weigh_slip':
        return 'Phiếu cân';
      case 'delivery_slip':
        return 'Phiếu giao hàng';
      default:
        return 'Giao nhận ca';
    }
  }

  void _showNotificationModal(
      BuildContext context, List<Map<String, dynamic>> reports) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _NotificationListDialog(
        initialReports: reports,
        onRefresh: () => _fetchData(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final reports = _collectReports(state);
    final alertCount = reports.where((r) => r['group'] == 'ALERT').length;
    final totalCount = reports.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(
              alertCount > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: alertCount > 0
                  ? Colors.red.shade600
                  : Colors.blueGrey.shade700,
              size: 24,
            ),
            tooltip: 'Báo cáo Realtime Trạng thái Tài xế ($totalCount)',
            onPressed: () => _showNotificationModal(context, reports),
          ),
          if (totalCount > 0)
            Positioned(
              right: 6,
              top: 6,
              child: GestureDetector(
                onTap: () => _showNotificationModal(context, reports),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: alertCount > 0 ? Colors.red.shade600 : Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    alertCount > 0 ? '$alertCount' : '$totalCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationListDialog extends StatefulWidget {
  final List<Map<String, dynamic>> initialReports;
  final Future<void> Function() onRefresh;

  const _NotificationListDialog({
    required this.initialReports,
    required this.onRefresh,
  });

  @override
  State<_NotificationListDialog> createState() =>
      _NotificationListDialogState();
}

class _NotificationListDialogState extends State<_NotificationListDialog> {
  String _filterGroup = 'ALL'; // ALL, ALERT, INSPECTION, TRIP
  String _searchQuery = '';
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 700;

    final filtered = widget.initialReports.where((r) {
      if (_filterGroup != 'ALL' && r['group'] != _filterGroup) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final driver = (r['driver_name'] ?? '').toString().toLowerCase();
        final plate = (r['plate'] ?? '').toString().toLowerCase();
        final title = (r['title'] ?? '').toString().toLowerCase();
        final desc = (r['description'] ?? '').toString().toLowerCase();
        return driver.contains(q) ||
            plate.contains(q) ||
            title.contains(q) ||
            desc.contains(q);
      }
      return true;
    }).toList();

    final alertCount =
        widget.initialReports.where((r) => r['group'] == 'ALERT').length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isDesktop ? size.width * 0.2 : 16,
        vertical: isDesktop ? 60 : 30,
      ),
      child: Container(
        width: isDesktop ? 650 : double.infinity,
        height: size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header Dialog
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade900.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_active_rounded,
                      color: Colors.amberAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Báo cáo Realtime Trạng thái Tài xế',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.initialReports.length} thông báo • $alertCount cảnh báo bất thường',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                    tooltip: 'Làm mới dữ liệu',
                    onPressed: () async {
                      setState(() => _isRefreshing = true);
                      await widget.onRefresh();
                      if (mounted) setState(() => _isRefreshing = false);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Bộ lọc & Ô tìm kiếm
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Tìm theo tên tài xế, biển số, mã đơn...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 12),
                      fillColor: Colors.white,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('ALL', 'Tất cả (${widget.initialReports.length})'),
                        const SizedBox(width: 6),
                        _buildFilterChip('ALERT', '⚠️ Cảnh báo & Bất thường ($alertCount)',
                            color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        _buildFilterChip('INSPECTION', '📷 5 ảnh giao ca'),
                        const SizedBox(width: 6),
                        _buildFilterChip('TRIP', '🚚 Chuyến hàng'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Danh sách thông báo
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'Không có báo cáo trạng thái phù hợp',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, idx) {
                        final item = filtered[idx];
                        final Color color = item['color'] ?? Colors.blue;
                        final IconData icon = item['icon'] ?? Icons.info;
                        final String driver = item['driver_name'] ?? '';
                        final String plate = item['plate'] ?? '';
                        final String title = item['title'] ?? '';
                        final String desc = item['description'] ?? '';
                        final String time = item['time_label'] ?? '';
                        final bool isAlert = item['group'] == 'ALERT';

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isAlert
                                ? Colors.red.shade50.withOpacity(0.6)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isAlert
                                  ? Colors.red.shade200
                                  : Colors.grey.shade200,
                              width: isAlert ? 1.5 : 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(icon, color: color, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: isAlert
                                                  ? Colors.red.shade900
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            time,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (plate.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            margin:
                                                const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: Colors.amber.shade300),
                                            ),
                                            child: Text(
                                              plate,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                          ),
                                        if (driver.isNotEmpty)
                                          Text(
                                            driver,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blueGrey.shade800,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.blueGrey.shade700,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, {Color? color}) {
    final isSelected = _filterGroup == key;
    final activeColor = color ?? Colors.blue.shade700;

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.grey.shade800,
        ),
      ),
      selected: isSelected,
      selectedColor: activeColor,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? activeColor : Colors.grey.shade300,
        ),
      ),
      onSelected: (_) => setState(() => _filterGroup = key),
    );
  }
}
