import 'package:flutter/material.dart';
import '../services/admin_service.dart';

/// Dialog hiển thị khi Điều phối / Quản lý bấm nút "Duyệt Nhận Chuyến":
/// - Cho phép chọn 1 đơn hàng vận tải để gắn cho Tài xế + Xe vừa kiểm tra.
/// - Khi bấm "Duyệt & Gắn Đơn Hàng": vừa duyệt bản ghi kiểm tra xe (`approved`),
///   vừa cập nhật đơn hàng (`assigned_driver_id`, `assigned_vehicle_plate`, `status = 'assigned'`).
/// - Cũng có tùy chọn "Chỉ Duyệt (Chưa gắn đơn)" nếu chưa muốn gán đơn ngay.
class AssignOrderOnApproveDialog extends StatefulWidget {
  final Map<String, dynamic> inspectionRecord;
  final String reviewNote;

  const AssignOrderOnApproveDialog({
    super.key,
    required this.inspectionRecord,
    required this.reviewNote,
  });

  /// Mở dialog và trả về kết quả:
  /// `{'approved': true, 'order_code': '...'}` nếu đã duyệt thành công, hoặc `null` nếu hủy.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> inspectionRecord,
    required String reviewNote,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssignOrderOnApproveDialog(
        inspectionRecord: inspectionRecord,
        reviewNote: reviewNote,
      ),
    );
  }

  @override
  State<AssignOrderOnApproveDialog> createState() =>
      _AssignOrderOnApproveDialogState();
}

class _AssignOrderOnApproveDialogState
    extends State<AssignOrderOnApproveDialog> {
  bool _isLoadingOrders = true;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _orders = [];
  int? _selectedOrderId;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _showAllOrders = false;

  int? get _driverId {
    final raw = widget.inspectionRecord['driver_id'];
    if (raw is int) return raw;
    if (raw != null) return int.tryParse(raw.toString());
    return null;
  }

  String get _driverName =>
      (widget.inspectionRecord['driver_name'] ??
              widget.inspectionRecord['driver_username'] ??
              'Tài xế')
          .toString();

  String get _driverPhone =>
      (widget.inspectionRecord['driver_phone'] ?? '').toString();

  String get _plateNumber =>
      (widget.inspectionRecord['plate_number'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoadingOrders = true);
    final raw = await AdminService.fetchOrders();
    final list = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Sắp xếp ưu tiên: đơn chưa gán tài xế hoặc đang waiting lên đầu, sau đó là đơn của chính tài xế này
    final dId = _driverId;
    list.sort((a, b) {
      int score(Map<String, dynamic> o) {
        final st = (o['status'] ?? 'waiting').toString().toLowerCase();
        final assignedDrv = o['assigned_driver_id'];
        if (st == 'completed' || st == 'cancelled') return 3;
        if (assignedDrv == null || st == 'waiting') return 0;
        if (dId != null && assignedDrv.toString() == dId.toString()) return 1;
        return 2;
      }

      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      final ida = (a['id'] is int) ? a['id'] as int : 0;
      final idb = (b['id'] is int) ? b['id'] as int : 0;
      return idb.compareTo(ida);
    });

    if (!mounted) return;
    setState(() {
      _orders = list;
      _isLoadingOrders = false;
      // Mặc định chọn đơn đầu tiên phù hợp (chưa hoàn thành)
      final candidates = _filteredOrders;
      if (candidates.isNotEmpty) {
        _selectedOrderId = candidates.first['id'] as int?;
      }
    });
  }

  List<Map<String, dynamic>> get _filteredOrders {
    final dId = _driverId;
    return _orders.where((o) {
      final st = (o['status'] ?? 'waiting').toString().toLowerCase();
      if (st == 'completed' || st == 'cancelled') return false;

      if (!_showAllOrders) {
        final assignedDrv = o['assigned_driver_id'];
        final isUnassigned = assignedDrv == null || st == 'waiting';
        final isSameDriver =
            dId != null && assignedDrv?.toString() == dId.toString();
        if (!isUnassigned && !isSameDriver) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final code = (o['order_code'] ?? '').toString().toLowerCase();
        final prod = (o['product_name'] ?? '').toString().toLowerCase();
        final pickup = (o['pickup_address'] ?? '').toString().toLowerCase();
        final delivery = (o['delivery_address'] ?? '').toString().toLowerCase();
        final factory = (o['factory_code'] ?? '').toString().toLowerCase();
        return code.contains(q) ||
            prod.contains(q) ||
            pickup.contains(q) ||
            delivery.contains(q) ||
            factory.contains(q);
      }
      return true;
    }).toList();
  }

  Future<void> _submit({required bool assignOrder}) async {
    if (assignOrder && _selectedOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Vui lòng chọn một đơn hàng để gắn cho tài xế.'),
        ),
      );
      return;
    }

    final int inspId = widget.inspectionRecord['id'] as int;
    setState(() => _isSubmitting = true);

    // 1. Duyệt kiểm tra xe
    final revRes = await AdminService.reviewInspection(
      inspId,
      flagStatus: 'approved',
      flagReason: widget.reviewNote,
    );

    if (revRes['success'] != true) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(revRes['message'] ?? 'Lỗi phê duyệt kiểm tra xe'),
        ),
      );
      return;
    }

    // 2. Nếu có chọn đơn hàng -> gắn đơn hàng cho tài xế & biển số xe
    String? assignedOrderCode;
    if (assignOrder && _selectedOrderId != null) {
      final selectedOrder = _orders.firstWhere(
        (o) => o['id'] == _selectedOrderId,
        orElse: () => <String, dynamic>{},
      );
      assignedOrderCode = (selectedOrder['order_code'] ?? '').toString();

      final payload = <String, dynamic>{
        'status': 'assigned',
        if (_driverId != null) 'assigned_driver_id': _driverId,
        if (_plateNumber.isNotEmpty) 'assigned_vehicle_plate': _plateNumber,
      };

      final ordRes = await AdminService.updateOrder(_selectedOrderId!, payload);
      if (ordRes['success'] != true) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange.shade800,
            content: Text(
              'Đã duyệt xe nhưng lỗi gắn đơn hàng: ${ordRes['message'] ?? 'Không rõ lỗi'}',
            ),
          ),
        );
        Navigator.of(context).pop({'approved': true, 'order_code': null});
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.of(context).pop({
      'approved': true,
      'order_code': assignedOrderCode,
    });
  }

  Map<String, dynamic> _statusBadge(String status) {
    switch (status.toLowerCase()) {
      case 'waiting':
        return {
          'label': 'Chờ nhận',
          'bg': Colors.amber.shade50,
          'fg': Colors.amber.shade900,
          'border': Colors.amber.shade300,
        };
      case 'assigned':
        return {
          'label': 'Đã gán xe',
          'bg': Colors.blue.shade50,
          'fg': Colors.blue.shade800,
          'border': Colors.blue.shade300,
        };
      case 'in_progress':
        return {
          'label': 'Đang chạy',
          'bg': Colors.green.shade50,
          'fg': Colors.green.shade800,
          'border': Colors.green.shade300,
        };
      default:
        return {
          'label': status,
          'bg': Colors.grey.shade100,
          'fg': Colors.grey.shade800,
          'border': Colors.grey.shade300,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_turned_in_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Duyệt Nhận Chuyến & Gắn Đơn Hàng Cho Tài Xế',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(null),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            ),

            // Thông tin Tài xế & Phương tiện được duyệt
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.blue.shade800),
                      const SizedBox(width: 6),
                      Text(
                        'Tài xế: $_driverName',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (_driverPhone.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '($_driverPhone)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 14,
                          color: Colors.blue.shade900,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Biển số: $_plateNumber',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Thanh tìm kiếm + lọc
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _searchQuery = v.trim()),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText:
                              'Tìm theo mã lệnh, mặt hàng, điểm lấy/giao...',
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text(
                      'Hiện cả đơn đã gán người khác',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    selected: _showAllOrders,
                    onSelected: (val) => setState(() => _showAllOrders = val),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),

            const Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Text(
                'Chọn đơn hàng vận tải cần gắn cho tài xế:',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ),

            // Danh sách đơn hàng
            Flexible(
              child: _isLoadingOrders
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Không có đơn hàng chờ nhận phù hợp.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (!_showAllOrders) ...[
                            const SizedBox(height: 6),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _showAllOrders = true),
                              child: const Text(
                                'Hiển thị tất cả đơn hàng đang hoạt động',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (ctx, idx) {
                        final o = filtered[idx];
                        final int? id = o['id'] as int?;
                        final bool isSelected =
                            id != null && id == _selectedOrderId;
                        final String code =
                            (o['order_code'] ?? 'ĐƠN-#$id').toString();
                        final String product =
                            (o['product_name'] ?? 'Chưa rõ mặt hàng')
                                .toString();
                        final String weight =
                            (o['cargo_weight_tons'] ?? '0').toString();
                        final String pickup =
                            (o['pickup_address'] ?? '---').toString();
                        final String delivery =
                            (o['delivery_address'] ?? '---').toString();
                        final String status =
                            (o['status'] ?? 'waiting').toString();
                        final String currentDrv =
                            (o['driver_name'] ?? '').toString();
                        final String currentPlate =
                            (o['assigned_vehicle_plate'] ?? '').toString();
                        final badge = _statusBadge(status);

                        return InkWell(
                          onTap: () => setState(() => _selectedOrderId = id),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.green.shade50.withValues(alpha: 0.6)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.green.shade700
                                    : const Color(0xFFCBD5E1),
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Radio<int>(
                                  value: id ?? -1,
                                  groupValue: _selectedOrderId,
                                  activeColor: Colors.green.shade700,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (v) =>
                                      setState(() => _selectedOrderId = v),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            code,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: badge['bg'] as Color,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: badge['border'] as Color,
                                              ),
                                            ),
                                            child: Text(
                                              badge['label'] as String,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: badge['fg'] as Color,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            '$product • $weight tấn',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Lấy hàng: $pickup  →  Giao: $delivery',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF475569),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (currentDrv.isNotEmpty ||
                                          currentPlate.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          'Đang gán: ${currentDrv.isNotEmpty ? currentDrv : "Chưa có tài xế"}${currentPlate.isNotEmpty ? " ($currentPlate)" : ""}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.blueGrey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
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

            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Footer buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 36,
                    child: TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(null),
                      child: const Text(
                        'Hủy',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _isSubmitting
                          ? null
                          : () => _submit(assignOrder: false),
                      child: const Text(
                        'Chỉ Duyệt (Chưa gắn đơn)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: (_isSubmitting || _selectedOrderId == null)
                          ? null
                          : () => _submit(assignOrder: true),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text(
                        'Duyệt & Gắn Đơn Hàng',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
