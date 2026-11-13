import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'center_loading_overlay.dart';
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
    extends State<RealtimeHeaderNotificationBell>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  bool _isLoading = false;
  bool _isPanelOpen = false;
  List<dynamic> _inspections = [];
  List<dynamic> _orders = [];

  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final ValueNotifier<List<Map<String, dynamic>>> _reportsNotifier;
  OverlayEntry? _slidePanelOverlay;

  @override
  void initState() {
    super.initState();
    _reportsNotifier = ValueNotifier<List<Map<String, dynamic>>>([]);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().ensureReadNotificationsLoaded();
      }
    });

    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _fetchData(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_isPanelOpen) {
      _slidePanelOverlay?.remove();
      _slidePanelOverlay = null;
    }
    _animController.dispose();
    _reportsNotifier.dispose();
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
        final state = context.read<AppState>();
        await state.ensureReadNotificationsLoaded();
        setState(() {
          _inspections = results[0];
          _orders = results[1];
          _isLoading = false;
        });
        final collected = _collectReports(state);
        await state.seedHistoricalNotificationsIfNeeded(collected);
        if (mounted) {
          _reportsNotifier.value = collected;
        }
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
      final rawId = item['id'] ?? '${plate}_${dt.millisecondsSinceEpoch}';
      final notifId =
          'insp_${rawId}_${flagStatus}_${hasAbnormal}_$hasDeviation';

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
        'id': notifId,
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
      final dt = _parseTime(o['updated_at'] ?? o['created_at']);
      final rawOrderId =
          o['id'] ?? (orderCode.isNotEmpty ? orderCode : dt.millisecondsSinceEpoch);
      final bool hasDeliverySlip =
          (o['delivery_slip_photo_url'] ?? '').toString().trim().isNotEmpty;
      final bool hasArrivalPhoto =
          (o['arrival_photo_url'] ?? '').toString().trim().isNotEmpty;
      final bool hasWeighSlip =
          (o['weigh_slip_photo_url'] ?? '').toString().trim().isNotEmpty;
      final String photoMilestoneTag =
          '${hasWeighSlip ? 'w' : ''}${hasArrivalPhoto ? 'a' : ''}${hasDeliverySlip ? 'd' : ''}';
      final orderNotifId = 'order_${rawOrderId}_${status}_$photoMilestoneTag';

      String statusLabel;
      Color badgeColor;
      IconData iconData;
      String groupKey = 'TRIP';

      switch (status) {
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
        case 'in_progress':
        case 'in_transit':
        case 'delivering':
        case 'moving':
          if (hasDeliverySlip) {
            statusLabel = 'Đã gửi Phiếu giao • Chờ duyệt hoàn thành';
            badgeColor = Colors.teal.shade700;
            iconData = Icons.fact_check_rounded;
          } else if (hasArrivalPhoto) {
            statusLabel = 'Đã đến điểm giao hàng';
            badgeColor = Colors.teal.shade700;
            iconData = Icons.location_on_rounded;
          } else {
            statusLabel = 'Đang vận chuyển trên đường';
            badgeColor = Colors.blue.shade700;
            iconData = Icons.local_shipping_rounded;
          }
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
        default:
          statusLabel = 'Đã nhận lệnh điều động';
          badgeColor = Colors.amber.shade900;
          iconData = Icons.assignment_ind_rounded;
      }

      final weightStr = tons != null ? ' • $tons tấn' : '';
      reports.add({
        'id': orderNotifId,
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
            final distPickup =
                checkData['pickup_distance_m'] ?? checkData['pickup_dist_m'];
            final distDelivery = checkData['delivery_distance_m'] ??
                checkData['delivery_dist_m'];

            String distMsg = '';
            if (distPickup != null && distDelivery != null) {
              distMsg =
                  ' (Cách Nhận: ${distPickup}m, Cách Giao: ${distDelivery}m)';
            }

            reports.add({
              'id': 'gps_${rawOrderId}_$photoType',
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
        'id': 'breakdown_${b.id}_${b.decision}',
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
      case 'arrival_photo':
        return 'Đến điểm giao';
      case 'delivery_slip':
        return 'Phiếu giao hàng';
      default:
        return 'Giao nhận ca';
    }
  }

  double _calculateTopOffset() {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final pos = box.localToGlobal(Offset.zero);
      final calculatedBottom = pos.dy + box.size.height + 4.0;
      final standard = kToolbarHeight + topPadding + 1.0;
      if ((calculatedBottom - standard).abs() < 12.0) {
        return standard;
      }
      return calculatedBottom;
    }
    return kToolbarHeight + topPadding + 1.0;
  }

  void _toggleSlidePanel() {
    if (_isPanelOpen) {
      _closeSlidePanel();
    } else {
      _openSlidePanel();
    }
  }

  void _openSlidePanel() {
    if (_isPanelOpen) return;
    _slidePanelOverlay?.remove();
    _slidePanelOverlay = _buildOverlayEntry();
    Overlay.of(context).insert(_slidePanelOverlay!);
    setState(() => _isPanelOpen = true);
    _animController.forward();
  }

  Future<void> _closeSlidePanel() async {
    if (!_isPanelOpen) return;
    setState(() => _isPanelOpen = false);
    try {
      await _animController.reverse();
    } catch (_) {}
    if (!_isPanelOpen) {
      _slidePanelOverlay?.remove();
      _slidePanelOverlay = null;
    }
  }

  OverlayEntry _buildOverlayEntry() {
    return OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final topOffset = _calculateTopOffset();
        final panelWidth = size.width > 500 ? 450.0 : size.width * 0.92;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _closeSlidePanel,
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                // 1. Nền mờ Backdrop bên dưới Header
                Positioned(
                  left: 0,
                  top: topOffset,
                  right: 0,
                  bottom: 0,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _closeSlidePanel,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                ),

                // 2. Slide Panel từ lề phải
                Positioned(
                  top: topOffset,
                  bottom: 0,
                  right: 0,
                  width: panelWidth,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Material(
                      elevation: 16,
                      shadowColor: Colors.black54,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            left: BorderSide(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                        ),
                        child: _SlideNotificationPanelContent(
                          reportsNotifier: _reportsNotifier,
                          onRefresh: () => _fetchData(silent: false),
                          onClose: _closeSlidePanel,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final reports = _collectReports(state);

    // Đảm bảo dữ liệu lịch sử cũ trước hôm nay đã được seed lần đầu cho tài khoản hiện tại
    if ((!state.isNotifStorageReady || !state.isNotifInitialSeeded) &&
        reports.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          state.seedHistoricalNotificationsIfNeeded(reports);
        }
      });
    }

    // Cập nhật tức thì danh sách báo cáo khi có biến động số lượng hoặc bản tin đầu
    final String prevFirstId = _reportsNotifier.value.isNotEmpty
        ? (_reportsNotifier.value.first['id'] ?? '').toString()
        : '';
    final String currFirstId =
        reports.isNotEmpty ? (reports.first['id'] ?? '').toString() : '';
    if (_reportsNotifier.value.length != reports.length ||
        prevFirstId != currFirstId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _reportsNotifier.value = reports;
        }
      });
    }

    final unreadReports = reports
        .where((r) => !state.isNotificationRead((r['id'] ?? '').toString()))
        .toList();
    final int unreadCount = unreadReports.length;
    final int unreadAlertCount =
        unreadReports.where((r) => r['group'] == 'ALERT').length;
    final int totalCount = reports.length;

    final bool isActive = _isPanelOpen;
    final bool hasUnreadAlert = unreadAlertCount > 0;
    final bool hasAnyUnread = unreadCount > 0;

    final Color activeThemeColor =
        hasUnreadAlert ? Colors.red.shade600 : Colors.blue.shade700;

    String tooltipText;
    if (isActive) {
      tooltipText = 'Đóng bảng thông báo';
    } else if (hasAnyUnread) {
      tooltipText = hasUnreadAlert
          ? 'Báo cáo Realtime: $unreadCount tin chưa đọc ($unreadAlertCount cảnh báo mới)'
          : 'Báo cáo Realtime: $unreadCount tin mới chưa đọc';
    } else {
      tooltipText = 'Báo cáo Realtime: Đã đọc tất cả ($totalCount thông báo)';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? (hasUnreadAlert ? Colors.red.shade50 : Colors.blue.shade50)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: isActive
            ? Border.all(
                color: hasUnreadAlert
                    ? Colors.red.shade400
                    : Colors.blue.shade600,
                width: 1.5,
              )
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: Icon(
              hasUnreadAlert
                  ? Icons.notifications_active_rounded
                  : (hasAnyUnread || isActive
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded),
              color: hasUnreadAlert
                  ? Colors.red.shade600
                  : (hasAnyUnread || isActive
                      ? Colors.blue.shade800
                      : Colors.blueGrey.shade700),
              size: 22,
            ),
            tooltip: tooltipText,
            onPressed: _toggleSlidePanel,
          ),
          // Chỉ hiển thị con số trên chuông khi thực sự có tin CHƯA ĐỌC
          if (hasAnyUnread)
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: _toggleSlidePanel,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: activeThemeColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
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

class _SlideNotificationPanelContent extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> reportsNotifier;
  final Future<void> Function() onRefresh;
  final VoidCallback onClose;

  const _SlideNotificationPanelContent({
    required this.reportsNotifier,
    required this.onRefresh,
    required this.onClose,
  });

  @override
  State<_SlideNotificationPanelContent> createState() =>
      _SlideNotificationPanelContentState();
}

class _SlideNotificationPanelContentState
    extends State<_SlideNotificationPanelContent> {
  String _filterGroup = 'ALL'; // ALL, UNREAD, ALERT, INSPECTION, TRIP
  String _searchQuery = '';
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return CenterLoadingOverlay(
      isLoading: _isRefreshing,
      message: 'Đang làm mới thông báo...',
      child: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: widget.reportsNotifier,
        builder: (ctx, allReports, _) {
          final unreadAll = allReports
              .where((r) => !state.isNotificationRead((r['id'] ?? '').toString()))
              .toList();
          final int unreadCount = unreadAll.length;
          final int unreadAlertCount =
              unreadAll.where((r) => r['group'] == 'ALERT').length;
          final int totalAlerts =
              allReports.where((r) => r['group'] == 'ALERT').length;
          final int inspectionCount =
              allReports.where((r) => r['group'] == 'INSPECTION').length;
          final int tripCount =
              allReports.where((r) => r['group'] == 'TRIP').length;

          final filtered = allReports.where((r) {
            final id = (r['id'] ?? '').toString();
            final isRead = state.isNotificationRead(id);
            if (_filterGroup == 'UNREAD' && isRead) return false;
            if (_filterGroup != 'ALL' &&
                _filterGroup != 'UNREAD' &&
                r['group'] != _filterGroup) {
              return false;
            }
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final driver =
                  (r['driver_name'] ?? '').toString().toLowerCase();
              final plate = (r['plate'] ?? '').toString().toLowerCase();
              final title = (r['title'] ?? '').toString().toLowerCase();
              final desc =
                  (r['description'] ?? '').toString().toLowerCase();
              return driver.contains(q) ||
                  plate.contains(q) ||
                  title.contains(q) ||
                  desc.contains(q);
            }
            return true;
          }).toList();

          return Column(
            children: [
              // 1. Header Panel
              Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.zero,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade900.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        unreadCount > 0
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color: unreadCount > 0
                            ? Colors.amberAccent
                            : Colors.blueGrey.shade200,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Báo cáo Realtime Trạng thái',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          unreadCount > 0
                              ? RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11.5,
                                      fontFamily: 'Nunito',
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '$unreadCount chưa đọc',
                                        style: TextStyle(
                                          color: unreadAlertCount > 0
                                              ? Colors.redAccent.shade100
                                              : Colors.amberAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (unreadAlertCount > 0)
                                        TextSpan(
                                          text: ' ($unreadAlertCount cảnh báo)',
                                          style: TextStyle(
                                            color: Colors.redAccent.shade100,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      TextSpan(
                                        text: ' • Tổng ${allReports.length}',
                                      ),
                                    ],
                                  ),
                                )
                              : Text(
                                  'Đã đọc tất cả • Tổng ${allReports.length} tin',
                                  style: TextStyle(
                                    color: Colors.green.shade300,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    // Nút Đánh dấu đã đọc tất cả (cao 30px chuẩn QUY_TAC_STYLE_APP.md)
                    Tooltip(
                      message: unreadCount > 0
                          ? 'Đánh dấu tất cả $unreadCount tin chưa đọc thành Đã đọc'
                          : 'Tất cả thông báo đều đã được đọc',
                      child: TextButton.icon(
                        onPressed: unreadCount > 0
                            ? () {
                                final allIds = allReports
                                    .map((r) => (r['id'] ?? '').toString())
                                    .where((id) => id.isNotEmpty);
                                state.markAllNotificationsRead(allIds);
                              }
                            : null,
                        icon: Icon(
                          Icons.done_all_rounded,
                          size: 15,
                          color: unreadCount > 0
                              ? Colors.white
                              : Colors.blueGrey.shade600,
                        ),
                        label: Text(
                          unreadCount > 0 ? 'Đọc tất cả' : 'Đã đọc hết',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: unreadCount > 0
                                ? Colors.white
                                : Colors.blueGrey.shade600,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: unreadCount > 0
                              ? Colors.blue.shade700
                              : Colors.white.withValues(alpha: 0.06),
                          minimumSize: const Size(0, 30),
                          fixedSize: const Size.fromHeight(30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 19),
                      tooltip: 'Làm mới dữ liệu',
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: () async {
                        setState(() => _isRefreshing = true);
                        await widget.onRefresh();
                        if (mounted) setState(() => _isRefreshing = false);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 19),
                      tooltip: 'Đóng bảng (Esc)',
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // 2. Bộ lọc & Tìm kiếm
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border:
                      Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 36,
                      child: TextField(
                        onChanged: (val) =>
                            setState(() => _searchQuery = val),
                        style: const TextStyle(fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: 'Tìm theo tên tài xế, biển số, mã đơn...',
                          hintStyle: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(
                              minWidth: 34, minHeight: 36, maxHeight: 36),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 0, horizontal: 8),
                          fillColor: Colors.white,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(
                                color: Colors.blue.shade700, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            key: 'ALL',
                            label: 'Tất cả (${allReports.length})',
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            key: 'UNREAD',
                            label: 'Chưa đọc ($unreadCount)',
                            icon: Icons.mark_chat_unread_outlined,
                            customColor: unreadAlertCount > 0
                                ? Colors.red.shade700
                                : Colors.blue.shade800,
                            highlightUnread: unreadCount > 0,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            key: 'ALERT',
                            label: unreadAlertCount > 0
                                ? 'Cảnh báo ($unreadAlertCount/$totalAlerts)'
                                : 'Cảnh báo ($totalAlerts)',
                            icon: Icons.warning_amber_rounded,
                            customColor: Colors.red.shade700,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            key: 'INSPECTION',
                            label: '5 ảnh ($inspectionCount)',
                            icon: Icons.photo_camera_outlined,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            key: 'TRIP',
                            label: 'Chuyến ($tripCount)',
                            icon: Icons.local_shipping_outlined,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Danh sách thông báo
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _filterGroup == 'UNREAD'
                                  ? Icons.mark_email_read_outlined
                                  : Icons.notifications_off_outlined,
                              size: 44,
                              color: _filterGroup == 'UNREAD'
                                  ? Colors.green.shade400
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _filterGroup == 'UNREAD'
                                  ? 'Tuyệt vời! Bạn đã đọc hết tất cả thông báo.'
                                  : 'Không có báo cáo trạng thái phù hợp',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: _filterGroup == 'UNREAD'
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: filtered.length,
                        separatorBuilder: (ctx, idx) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = filtered[idx];
                          final String notifId = (item['id'] ?? '').toString();
                          final bool isRead =
                              state.isNotificationRead(notifId);
                          final Color baseColor =
                              item['color'] ?? Colors.blue;
                          final IconData icon = item['icon'] ?? Icons.info;
                          final String driver = item['driver_name'] ?? '';
                          final String plate = item['plate'] ?? '';
                          final String title = item['title'] ?? '';
                          final String desc = item['description'] ?? '';
                          final String time = item['time_label'] ?? '';
                          final bool isAlert = item['group'] == 'ALERT';

                          // Màu sắc & độ tương phản tách biệt rõ rệt giữa CHƯA ĐỌC và ĐÃ ĐỌC
                          final Color cardBgColor = !isRead
                              ? (isAlert
                                  ? Colors.red.shade50.withValues(alpha: 0.75)
                                  : Colors.blue.shade50.withValues(alpha: 0.5))
                              : Colors.grey.shade50;

                          final Color borderColor = !isRead
                              ? (isAlert
                                  ? Colors.red.shade300
                                  : Colors.blue.shade200)
                              : Colors.grey.shade200;

                          final Color leftAccentColor = isAlert
                              ? Colors.red.shade600
                              : Colors.blue.shade700;

                          return Material(
                            color: cardBgColor,
                            borderRadius: BorderRadius.circular(4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              mouseCursor: SystemMouseCursors.click,
                              hoverColor: Colors.blue.withValues(alpha: 0.04),
                              onTap: () {
                                if (!isRead) {
                                  state.markNotificationRead(notifId);
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: borderColor,
                                    width: !isRead && isAlert ? 1.2 : 1,
                                  ),
                                ),
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Thanh chỉ báo bên trái cho tin CHƯA ĐỌC
                                      if (!isRead)
                                        Container(
                                          width: 4,
                                          decoration: BoxDecoration(
                                            color: leftAccentColor,
                                            borderRadius:
                                                const BorderRadius.only(
                                              topLeft: Radius.circular(3),
                                              bottomLeft: Radius.circular(3),
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Opacity(
                                                opacity: isRead ? 0.55 : 1.0,
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: baseColor.withValues(
                                                        alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Icon(icon,
                                                      color: baseColor,
                                                      size: 20),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        if (!isRead) ...[
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 5,
                                                              vertical: 1.5,
                                                            ),
                                                            margin:
                                                                const EdgeInsets
                                                                    .only(
                                                                    right: 6),
                                                            decoration:
                                                                BoxDecoration(
                                                              color:
                                                                  leftAccentColor,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                            ),
                                                            child: const Text(
                                                              'MỚI',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 9.5,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                letterSpacing:
                                                                    0.3,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        Expanded(
                                                          child: Text(
                                                            title,
                                                            style: TextStyle(
                                                              fontWeight: !isRead
                                                                  ? FontWeight
                                                                      .w700
                                                                  : FontWeight
                                                                      .w500,
                                                              fontSize: 13,
                                                              color: !isRead
                                                                  ? (isAlert
                                                                      ? Colors
                                                                          .red
                                                                          .shade900
                                                                      : const Color(
                                                                          0xFF0F172A))
                                                                  : Colors
                                                                      .blueGrey
                                                                      .shade600,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 5,
                                                            vertical: 2,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isRead
                                                                ? Colors.grey
                                                                    .shade100
                                                                : Colors.white,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                            border: Border.all(
                                                              color: Colors.grey
                                                                  .shade300,
                                                              width: 0.6,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            time,
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              color: isRead
                                                                  ? Colors.grey
                                                                      .shade500
                                                                  : Colors.grey
                                                                      .shade800,
                                                              fontWeight: !isRead
                                                                  ? FontWeight
                                                                      .w700
                                                                  : FontWeight
                                                                      .normal,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Row(
                                                      children: [
                                                        if (plate.isNotEmpty)
                                                          Opacity(
                                                            opacity: isRead
                                                                ? 0.72
                                                                : 1.0,
                                                            child: Container(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 5,
                                                                vertical: 1.5,
                                                              ),
                                                              margin:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      right: 6),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .amber
                                                                    .shade100,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            4),
                                                                border:
                                                                    Border.all(
                                                                  color: Colors
                                                                      .amber
                                                                      .shade300,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                plate,
                                                                style:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      10.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .amber
                                                                      .shade900,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        if (driver.isNotEmpty)
                                                          Expanded(
                                                            child: Text(
                                                              driver,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 11.5,
                                                                fontWeight:
                                                                    !isRead
                                                                        ? FontWeight
                                                                            .w600
                                                                        : FontWeight
                                                                            .normal,
                                                                color: isRead
                                                                    ? Colors
                                                                        .grey
                                                                        .shade600
                                                                    : Colors
                                                                        .blueGrey
                                                                        .shade800,
                                                              ),
                                                            ),
                                                          ),
                                                        // Nút trạng thái Đã đọc / Chưa đọc trực quan trên từng tin
                                                        Tooltip(
                                                          message: isRead
                                                              ? 'Đã đọc • Bấm để đánh dấu chưa đọc lại'
                                                              : 'Chưa đọc • Bấm để đánh dấu đã đọc',
                                                          child: InkWell(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        4),
                                                            mouseCursor:
                                                                SystemMouseCursors
                                                                    .click,
                                                            onTap: () {
                                                              state
                                                                  .toggleNotificationRead(
                                                                      notifId);
                                                            },
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                horizontal: 4,
                                                                vertical: 2,
                                                              ),
                                                              child: Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Icon(
                                                                    isRead
                                                                        ? Icons
                                                                            .done_all_rounded
                                                                        : Icons
                                                                            .circle,
                                                                    size: isRead
                                                                        ? 13
                                                                        : 8,
                                                                    color: isRead
                                                                        ? Colors
                                                                            .grey
                                                                            .shade500
                                                                        : leftAccentColor,
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 3),
                                                                  Text(
                                                                    isRead
                                                                        ? 'Đã đọc'
                                                                        : 'Chưa đọc',
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          10.5,
                                                                      fontWeight: isRead
                                                                          ? FontWeight
                                                                              .normal
                                                                          : FontWeight
                                                                              .w600,
                                                                      color: isRead
                                                                          ? Colors
                                                                              .grey
                                                                              .shade500
                                                                          : leftAccentColor,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      desc,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isRead
                                                            ? Colors
                                                                .grey.shade600
                                                            : Colors.blueGrey
                                                                .shade800,
                                                        height: 1.32,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // 4. Footer trạng thái
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cập nhật mỗi 15s • Bấm vào tin để đánh dấu đã đọc',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Text(
                      'Esc để đóng',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip({
    required String key,
    required String label,
    IconData? icon,
    Color? customColor,
    bool highlightUnread = false,
  }) {
    final isSelected = _filterGroup == key;
    final activeColor = customColor ?? Colors.blue.shade800;

    return InkWell(
      onTap: () => setState(() => _filterGroup = key),
      borderRadius: BorderRadius.circular(4),
      mouseCursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (highlightUnread
                  ? activeColor.withValues(alpha: 0.08)
                  : Colors.white),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (highlightUnread
                    ? activeColor.withValues(alpha: 0.45)
                    : Colors.grey.shade300),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13.5,
                color: isSelected
                    ? Colors.white
                    : (highlightUnread
                        ? activeColor
                        : (customColor ?? Colors.blueGrey.shade700)),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected || highlightUnread
                    ? FontWeight.w600
                    : FontWeight.normal,
                color: isSelected
                    ? Colors.white
                    : (highlightUnread
                        ? activeColor
                        : Colors.blueGrey.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
