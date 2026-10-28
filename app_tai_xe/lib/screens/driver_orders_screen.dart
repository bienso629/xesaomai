import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/app_state.dart';
import '../widgets/order_attachments_section.dart';

class DriverOrdersScreen extends StatefulWidget {
  const DriverOrdersScreen({super.key});

  @override
  State<DriverOrdersScreen> createState() => _DriverOrdersScreenState();
}

class _DriverOrdersScreenState extends State<DriverOrdersScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _myVehicles = [];
  List<Map<String, dynamic>> _orders = [];
  String _selectedPlate = 'all';
  String _statusFilter = 'all';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final state = context.read<AppState>();
      final currentUserId = state.currentUserId;
      final roles = state.userRoles.map((r) => r.toLowerCase()).toList();
      final isGasOrMechanicOrManager =
          state.currentUsername == 'admin' ||
          roles.contains('gas_station') ||
          roles.contains('mechanic') ||
          roles.contains('admin') ||
          roles.contains('manager') ||
          roles.contains('dispatcher');

      final results = await Future.wait([
        AdminService.fetchVehicles(),
        AdminService.fetchOrders(),
      ]);

      final vehiclesRaw = results[0];
      final ordersRaw = results[1];

      final myVehicles = <Map<String, dynamic>>[];
      final myPlates = <String>{};
      for (final raw in vehiclesRaw) {
        final v = Map<String, dynamic>.from(raw as Map);
        final driverId = v['default_driver_id'] ?? v['driver_id'];
        final plate = (v['plate_number'] ?? v['license_plate'] ?? '')
            .toString()
            .trim();
        if (plate.isEmpty) continue;
        if (isGasOrMechanicOrManager ||
            (currentUserId != null &&
                driverId != null &&
                driverId.toString() == currentUserId.toString())) {
          myVehicles.add(v);
          myPlates.add(plate);
        }
      }

      if (myPlates.isEmpty &&
          state.selectedPlate.trim().isNotEmpty &&
          !state.selectedPlate.contains('Chưa')) {
        myPlates.add(state.selectedPlate.trim());
      }

      final myOrders = <Map<String, dynamic>>[];
      for (final raw in ordersRaw) {
        final o = Map<String, dynamic>.from(raw as Map);
        if (isGasOrMechanicOrManager) {
          myOrders.add(o);
          continue;
        }
        final oPlate =
            (o['assigned_vehicle_plate'] ?? o['vehicle_plate'] ?? '')
                .toString()
                .trim();
        final oDriverId = o['assigned_driver_id'] ?? o['driver_id'];
        final matchPlate = oPlate.isNotEmpty && myPlates.contains(oPlate);
        final matchDriver =
            currentUserId != null &&
            oDriverId != null &&
            oDriverId.toString() == currentUserId.toString();
        if (matchPlate || matchDriver) {
          myOrders.add(o);
          if (oPlate.isNotEmpty && !myPlates.contains(oPlate)) {
            myPlates.add(oPlate);
            myVehicles.add({'plate_number': oPlate});
          }
        }
      }

      myOrders.sort((a, b) {
        final idA = int.tryParse((a['id'] ?? '0').toString()) ?? 0;
        final idB = int.tryParse((b['id'] ?? '0').toString()) ?? 0;
        return idB.compareTo(idA);
      });

      if (!mounted) return;
      setState(() {
        _myVehicles = myVehicles;
        _orders = myOrders;
        if (_selectedPlate != 'all' && !myPlates.contains(_selectedPlate)) {
          _selectedPlate = 'all';
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final q = _searchController.text.trim().toLowerCase();
    return _orders.where((o) {
      final plate =
          (o['assigned_vehicle_plate'] ?? o['vehicle_plate'] ?? '').toString();
      if (_selectedPlate != 'all' && plate != _selectedPlate) {
        return false;
      }
      final st = (o['status'] ?? 'waiting').toString().toLowerCase();
      if (_statusFilter == 'completed') {
        if (st != 'completed' && st != 'delivered') return false;
      } else if (_statusFilter == 'active') {
        if (![
          'assigned',
          'in_progress',
          'in_transit',
          'arrived',
          'pumping',
          'pumped',
        ].contains(st)) {
          return false;
        }
      } else if (_statusFilter == 'cancelled') {
        if (st != 'cancelled') return false;
      }
      if (q.isNotEmpty) {
        final code = (o['order_code'] ?? '').toString().toLowerCase();
        final cust = (o['customer_name'] ?? '').toString().toLowerCase();
        final prod = (o['product_name'] ?? '').toString().toLowerCase();
        final pick = (o['pickup_location'] ?? '').toString().toLowerCase();
        final deliv = (o['delivery_location'] ?? '').toString().toLowerCase();
        final pLower = plate.toLowerCase();
        if (!code.contains(q) &&
            !cust.contains(q) &&
            !prod.contains(q) &&
            !pick.contains(q) &&
            !deliv.contains(q) &&
            !pLower.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _statusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return 'Hoàn thành';
      case 'in_progress':
      case 'in_transit':
      case 'arrived':
      case 'pumping':
      case 'pumped':
        return 'Đang vận chuyển';
      case 'assigned':
        return 'Đã phân công';
      case 'cancelled':
        return 'Đã hủy';
      default:
        return 'Chờ nhận';
    }
  }

  Color _statusColor(String raw) {
    switch (raw.toLowerCase()) {
      case 'completed':
      case 'delivered':
        return const Color(0xFF15803D);
      case 'in_progress':
      case 'in_transit':
      case 'arrived':
      case 'pumping':
      case 'pumped':
        return const Color(0xFF2563EB);
      case 'assigned':
        return const Color(0xFFD97706);
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '---';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length > 16 ? s.substring(0, 16) : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredOrders;
    final totalCount = _orders.length;
    final completedCount = _orders.where((o) {
      final s = (o['status'] ?? '').toString().toLowerCase();
      return s == 'completed' || s == 'delivered';
    }).length;
    final activeCount = _orders.where((o) {
      final s = (o['status'] ?? '').toString().toLowerCase();
      return [
        'assigned',
        'in_progress',
        'in_transit',
        'arrived',
        'pumping',
        'pumped',
      ].contains(s);
    }).length;
    double totalTons = 0;
    for (final o in _orders) {
      final s = (o['status'] ?? '').toString().toLowerCase();
      if (s == 'completed' || s == 'delivered') {
        final w = o['cargo_weight_tons'];
        if (w is num) {
          totalTons += w.toDouble();
        } else {
          totalTons += double.tryParse((w ?? '0').toString()) ?? 0;
        }
      }
    }

    return Container(
      color: const Color(0xFFF1F5F9),
      child: Column(
        children: [
          _buildTopFilterBar(
            totalCount: totalCount,
            completedCount: completedCount,
            activeCount: activeCount,
            totalTons: totalTons,
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) => _buildOrderCard(list[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopFilterBar({
    required int totalCount,
    required int completedCount,
    required int activeCount,
    required double totalTons,
  }) {
    final plates = <String>[];
    for (final v in _myVehicles) {
      final p = (v['plate_number'] ?? v['license_plate'] ?? '')
          .toString()
          .trim();
      if (p.isNotEmpty && !plates.contains(p)) plates.add(p);
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  "Tổng đơn",
                  "$totalCount",
                  const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  "Đã vận chuyển",
                  "$completedCount",
                  const Color(0xFF15803D),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  "Đang chạy",
                  "$activeCount",
                  const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  "Sản lượng",
                  "${totalTons.toStringAsFixed(1)} T",
                  const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (plates.isNotEmpty) ...[
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedPlate,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text("Tất cả xe"),
                        ),
                        ...plates.map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text("Xe $p"),
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedPlate = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: "Tìm mã đơn, mặt hàng, điểm lấy/giao...",
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 17),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear, size: 15),
                              padding: EdgeInsets.zero,
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Color(0xFF2563EB)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                width: 36,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  onPressed: _loadData,
                  child: const Icon(Icons.refresh, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'Tất cả ($totalCount)'),
                const SizedBox(width: 6),
                _buildFilterChip(
                  'completed',
                  'Đã vận chuyển ($completedCount)',
                ),
                const SizedBox(width: 6),
                _buildFilterChip('active', 'Đang vận chuyển ($activeCount)'),
                const SizedBox(width: 6),
                _buildFilterChip('cancelled', 'Đã hủy'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final selected = _statusFilter == key;
    return InkWell(
      onTap: () => setState(() => _statusFilter = key),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? const Color(0xFF1E293B) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              "Chưa có đơn hàng vận chuyển",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Các đơn hàng mà xe của bạn đã nhận hoặc hoàn thành vận chuyển sẽ hiển thị tại đây.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final code = (order['order_code'] ?? '---').toString();
    final statusRaw = (order['status'] ?? 'waiting').toString();
    final statusColor = _statusColor(statusRaw);
    final statusText = _statusLabel(statusRaw);
    final plate =
        (order['assigned_vehicle_plate'] ??
                order['vehicle_plate'] ??
                'Chưa gán xe')
            .toString();
    final product = (order['product_name'] ?? '---').toString();
    final weight = order['cargo_weight_tons'] ?? 0;
    final pickup = (order['pickup_location'] ?? '---').toString();
    final delivery = (order['delivery_location'] ?? '---').toString();
    final customer = (order['customer_name'] ?? '').toString().trim();
    final timeStr = _formatDate(order['updated_at'] ?? order['created_at']);

    return InkWell(
      onTap: () => _showOrderDetailDialog(order),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 16,
                  color: Color(0xFF1E293B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    plate,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    "$product • $weight Tấn",
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.route_outlined,
                  size: 14,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    "$pickup → $delivery",
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
            if (customer.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.business_outlined,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      "Khách hàng: $customer",
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF475569),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            _buildAttachmentBadgesRow(order),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentBadgesRow(Map<String, dynamic> order) {
    final hasPumpBefore = (order['pump_slip_before_photo_url'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasWeigh =
        (order['weigh_slip_photo_url'] ?? '').toString().trim().isNotEmpty;
    final hasDelivery =
        (order['delivery_slip_photo_url'] ?? '').toString().trim().isNotEmpty;
    final hasBreakdown =
        order['has_breakdown'] == true ||
        (order['breakdown_photo_url'] ?? '').toString().trim().isNotEmpty;
    final hasRepair =
        (order['repair_photo_url'] ?? '').toString().trim().isNotEmpty;

    Widget chip(String label, bool active, Color activeColor, IconData icon) {
      final c = active ? activeColor : Colors.grey.shade500;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active
                ? activeColor.withValues(alpha: 0.4)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                color: c,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        chip(
          "Trước bơm",
          hasPumpBefore,
          const Color(0xFF0284C7),
          Icons.local_gas_station_outlined,
        ),
        chip(
          "Phiếu cân",
          hasWeigh,
          const Color(0xFF2563EB),
          Icons.scale_outlined,
        ),
        chip(
          "Phiếu giao",
          hasDelivery,
          const Color(0xFF15803D),
          Icons.assignment_turned_in_outlined,
        ),
        if (hasBreakdown)
          chip(
            "Báo hỏng",
            true,
            const Color(0xFFDC2626),
            Icons.car_crash_outlined,
          ),
        if (hasBreakdown || hasRepair)
          chip(
            "Sửa chữa KT",
            hasRepair,
            const Color(0xFFD97706),
            Icons.build_circle_outlined,
          ),
      ],
    );
  }

  void _showOrderDetailDialog(Map<String, dynamic> order) {
    final code = (order['order_code'] ?? '---').toString();
    final customer = (order['customer_name'] ?? 'Khách lẻ / Nội bộ').toString();
    final product = (order['product_name'] ?? '---').toString();
    final weight = order['cargo_weight_tons'] ?? 0;
    final pickup = (order['pickup_location'] ?? '---').toString();
    final delivery = (order['delivery_location'] ?? '---').toString();
    final plate =
        (order['assigned_vehicle_plate'] ??
                order['vehicle_plate'] ??
                'Chưa gán xe')
            .toString();
    final driverName = (order['driver_name'] ?? '---').toString();
    final statusRaw = (order['status'] ?? 'waiting').toString();
    final notes = (order['notes'] ?? '').toString().trim();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Chi tiết đơn hàng: $code",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow("Mã lệnh vận chuyển", code),
                      _detailRow("Trạng thái", _statusLabel(statusRaw)),
                      _detailRow("Biển số xe", plate),
                      _detailRow("Tài xế", driverName),
                      _detailRow("Khách hàng", customer),
                      _detailRow("Mặt hàng & Khối lượng", "$product ($weight Tấn)"),
                      _detailRow("Điểm nhận hàng", pickup),
                      _detailRow("Điểm giao hàng", delivery),
                      _detailRow(
                        "Cập nhật lần cuối",
                        _formatDate(order['updated_at'] ?? order['created_at']),
                      ),
                      if (notes.isNotEmpty) _detailRow("Ghi chú", notes),
                      const Divider(height: 22),
                      OrderAttachmentsSection(
                        order: order,
                        onOrderUpdated: (updated) {
                          Navigator.pop(ctx);
                          _loadData();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
