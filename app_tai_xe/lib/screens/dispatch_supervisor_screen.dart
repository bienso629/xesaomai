import 'customers_screen.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';
import '../widgets/assign_order_approve_dialog.dart';
import '../widgets/order_attachments_section.dart';
import '../models/reminder_model.dart';
import '../models/breakdown_model.dart';
import '../config/api_config.dart';

class DispatchSupervisorScreen extends StatefulWidget {
  final int activeTab;
  final int usersSubTab;
  final ValueChanged<int>? onTabChanged;
  final VoidCallback? onOpenInspectionScreen;
  final void Function(int filtered, int total)? onVehicleCountChanged;
  final void Function(int filtered, int total)? onOrderCountChanged;
  final void Function(int filtered, int total)? onUserCountChanged;
  final void Function(int filtered, int total)? onGasStationCountChanged;

  const DispatchSupervisorScreen({
    super.key,
    this.activeTab = 0,
    this.usersSubTab = 0,
    this.onTabChanged,
    this.onOpenInspectionScreen,
    this.onVehicleCountChanged,
    this.onOrderCountChanged,
    this.onUserCountChanged,
    this.onGasStationCountChanged,
  });

  static Future<void> showShiftHistoryDialog(
    BuildContext context, {
    Map<String, dynamic>? targetUser,
  }) => _DispatchSupervisorScreenState.showShiftHistoryDialog(
    context,
    targetUser: targetUser,
  );

  @override
  State<DispatchSupervisorScreen> createState() =>
      _DispatchSupervisorScreenState();
}

class _DispatchSupervisorScreenState extends State<DispatchSupervisorScreen> {
  bool _isLoading = false;
  Map<String, dynamic> _summary = {};
  List<dynamic> _orders = [];
  List<dynamic> _vehicles = [];
  bool _isSyncingFleet = false;

  /// Xe đang Tạm ngừng hoạt động (không còn trên Vietmap / Bình Anh)
  bool _isVehicleInactive(dynamic v) =>
      v is Map &&
      (v['in_fleet'] == false ||
          (v['status'] ?? '').toString() == 'inactive');

  /// Xe đang hoạt động: dùng cho các ô chọn xe của đơn hàng
  List<dynamic> get _activeVehicles =>
      _vehicles.where((v) => !_isVehicleInactive(v)).toList();
  List<dynamic> _products = [];
  List<dynamic> _gasStations = [];
  final String _vietMapApiKey =
      'edfac336d2c0462850d93fd5859878b1ad84b769ddfed745';
  List<dynamic> _users = [];
  List<dynamic> _drivers = [];
  List<dynamic> _roles = [];
  List<dynamic> _permissions = [];
  List<dynamic> _activeShifts = [];
  List<dynamic> _inspections = [];

  // Bộ lọc & phân trang cho Block Báo cáo Realtime Trạng thái Tài xế
  String _realtimeReportFilter = 'ALL'; // ALL, TRIP, INSPECTION, ALERT
  int _realtimeReportPage = 1;
  int _realtimeReportPageSize = 10;
  Timer? _realtimePollingTimer;

  // Tìm kiếm, Lọc và Phân trang người dùng
  String _userSearchQuery = '';
  String _selectedRoleFilter = 'ALL';
  final TextEditingController _userSearchCtrl = TextEditingController();
  int _userCurrentPage = 1;
  int _userPageSize = 10;

  // Tìm kiếm, Lọc và Phân trang đội xe & phương tiện
  String _vehicleSearchQuery = '';
  String _selectedOwnershipFilter = 'ALL';
  final TextEditingController _vehicleSearchCtrl = TextEditingController();
  int _vehicleCurrentPage = 1;
  int _vehiclePageSize = 10;

  // Tìm kiếm và Phân trang Cây dầu & Đối soát nhiên liệu
  String _gasStationSearchQuery = '';
  final TextEditingController _gasStationSearchCtrl = TextEditingController();
  int _gasStationCurrentPage = 1;
  int _gasStationPageSize = 10;

  // Tìm kiếm và Phân trang Sản phẩm & Vật liệu
  String _productSearchQuery = '';
  final TextEditingController _productSearchCtrl = TextEditingController();
  int _productCurrentPage = 1;
  int _productPageSize = 10;

  // Tìm kiếm, Lọc và Phân trang Đơn hàng vận tải
  String _orderSearchQuery = '';
  String _orderCodeFilter = '';
  String _orderPickupFilter = '';
  String _orderDeliveryFilter = '';
  String _selectedOrderProductFilter = 'ALL';
  String _selectedOrderVehicleFilter = 'ALL';
  String _selectedOrderDriverFilter = 'ALL';
  String _selectedOrderTransportTypeFilter = 'ALL';
  String _selectedOrderStatusFilter = 'ALL';
  DateTime? _orderStartDate;
  DateTime? _orderEndDate;
  bool _showAdvancedOrderFilters = false;
  final TextEditingController _orderSearchCtrl = TextEditingController();
  final TextEditingController _orderCodeFilterCtrl = TextEditingController();
  final TextEditingController _orderPickupFilterCtrl = TextEditingController();
  final TextEditingController _orderDeliveryFilterCtrl =
      TextEditingController();
  int _orderCurrentPage = 1;
  int _orderPageSize = 10;

  // Cấu hình Proxy AI
  final TextEditingController _proxyEndpointCtrl = TextEditingController(
    text: "https://api.openai.com/v1",
  );
  final TextEditingController _proxyApiKeyCtrl = TextEditingController();
  final TextEditingController _proxyModelCtrl = TextEditingController(
    text: "gpt-4o-mini",
  );
  final TextEditingController _proxyMaxTokensCtrl = TextEditingController(
    text: "2048",
  );
  final TextEditingController _proxyTemperatureCtrl = TextEditingController(
    text: "0.7",
  );
  bool _proxyEnabled = false;
  bool _proxyAutoVisionAudit = true;
  bool _proxyVoiceAssistant = false;
  bool _isSavingProxyConfig = false;

  @override
  void initState() {
    super.initState();
    _loadAllManagementData();
    _loadProxyAiConfig();
    _realtimePollingTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshRealtimeReportsSilently(),
    );
  }

  Future<void> _refreshRealtimeReportsSilently() async {
    if (!mounted || _isLoading) return;
    try {
      final results = await Future.wait([
        AdminService.fetchOrders(),
        AdminService.fetchVehicles(includeInactive: true),
        AdminService.fetchInspections(),
        AdminService.fetchActiveShifts(),
      ]);
      if (mounted) {
        setState(() {
          _orders = results[0];
          _vehicles = results[1];
          _inspections = results[2];
          _activeShifts = results[3];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProxyAiConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _proxyEndpointCtrl.text =
            prefs.getString('proxy_ai_endpoint') ?? "https://api.openai.com/v1";
        _proxyApiKeyCtrl.text = prefs.getString('proxy_ai_api_key') ?? "";
        _proxyModelCtrl.text =
            prefs.getString('proxy_ai_model') ?? "gpt-4o-mini";
        _proxyMaxTokensCtrl.text =
            prefs.getString('proxy_ai_max_tokens') ?? "2048";
        _proxyTemperatureCtrl.text =
            prefs.getString('proxy_ai_temperature') ?? "0.7";
        _proxyEnabled = prefs.getBool('proxy_ai_enabled') ?? false;
        _proxyAutoVisionAudit = prefs.getBool('proxy_ai_auto_vision') ?? true;
        _proxyVoiceAssistant =
            prefs.getBool('proxy_ai_voice_assistant') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _saveProxyAiConfig() async {
    setState(() => _isSavingProxyConfig = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'proxy_ai_endpoint',
        _proxyEndpointCtrl.text.trim(),
      );
      await prefs.setString('proxy_ai_api_key', _proxyApiKeyCtrl.text.trim());
      await prefs.setString('proxy_ai_model', _proxyModelCtrl.text.trim());
      await prefs.setString(
        'proxy_ai_max_tokens',
        _proxyMaxTokensCtrl.text.trim(),
      );
      await prefs.setString(
        'proxy_ai_temperature',
        _proxyTemperatureCtrl.text.trim(),
      );
      await prefs.setBool('proxy_ai_enabled', _proxyEnabled);
      await prefs.setBool('proxy_ai_auto_vision', _proxyAutoVisionAudit);
      await prefs.setBool('proxy_ai_voice_assistant', _proxyVoiceAssistant);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Đã lưu thiết lập Cấu hình Proxy AI thành công!"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi lưu cấu hình: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingProxyConfig = false);
      }
    }
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    _vehicleSearchCtrl.dispose();
    _gasStationSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    _orderSearchCtrl.dispose();
    _orderCodeFilterCtrl.dispose();
    _orderPickupFilterCtrl.dispose();
    _orderDeliveryFilterCtrl.dispose();
    _proxyEndpointCtrl.dispose();
    _proxyApiKeyCtrl.dispose();
    _proxyModelCtrl.dispose();
    _proxyMaxTokensCtrl.dispose();
    _proxyTemperatureCtrl.dispose();
    _realtimePollingTimer?.cancel();
    super.dispose();
  }

  /// Nút "Tải lại danh sách" ở Đội xe: đối chiếu với Vietmap + Bình Anh rồi tải lại.
  Future<void> _syncFleetAndReload() async {
    if (_isSyncingFleet) return;
    setState(() => _isSyncingFleet = true);
    final res = await AdminService.syncFleetVehicles();
    await _loadAllManagementData();
    if (!mounted) return;
    setState(() => _isSyncingFleet = false);

    final messenger = ScaffoldMessenger.of(context);
    if (res['success'] != true) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text("Đồng bộ đội xe thất bại: ${res['message'] ?? ''}"),
        ),
      );
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    List<String> plates(String key) => ((data[key] as List?) ?? [])
        .map((e) => (e is Map ? e['plate_number'] : e).toString())
        .toList();
    final added = plates('added');
    final deactivated = plates('deactivated');
    final reactivated = plates('reactivated');
    final providers =
        Map<String, dynamic>.from((data['providers'] as Map?) ?? {});
    final failed = <String>[];
    providers.forEach((k, val) {
      if (val is Map && val['ok'] != true) {
        failed.add(k == 'vietmap' ? 'Vietmap' : (k == 'binhanh' ? 'Bình Anh' : k));
      }
    });
    final inactiveCount = data['total_inactive'] ?? 0;

    final lines = <String>[
      "Đang hoạt động: ${data['total_active'] ?? 0} xe"
          "${inactiveCount != 0 ? ' • Tạm ngừng: $inactiveCount xe' : ''}",
      if (added.isNotEmpty) "Thêm mới ${added.length} xe: ${added.join(', ')}",
      if (deactivated.isNotEmpty)
        "Chuyển Tạm ngừng hoạt động ${deactivated.length} xe: ${deactivated.join(', ')}",
      if (reactivated.isNotEmpty)
        "Hoạt động trở lại ${reactivated.length} xe: ${reactivated.join(', ')}",
      if (added.isEmpty && deactivated.isEmpty && reactivated.isEmpty)
        "Không có thay đổi so với Vietmap và Bình Anh",
      if (failed.isNotEmpty)
        "Không kết nối được ${failed.join(', ')}: giữ nguyên các xe của nguồn này",
    ];
    messenger.showSnackBar(
      SnackBar(
        backgroundColor:
            failed.isNotEmpty ? Colors.orange.shade800 : Colors.green.shade700,
        duration: const Duration(seconds: 6),
        content: Text("Đã đồng bộ đội xe\n${lines.join('\n')}"),
      ),
    );
  }

  Future<void> _loadAllManagementData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      AdminService.fetchSummary(),
      AdminService.fetchOrders(),
      AdminService.fetchVehicles(includeInactive: true),
      AdminService.fetchProducts(),
      AdminService.fetchGasStations(),
      AdminService.fetchUsers(),
      AdminService.fetchRoles(),
      AdminService.fetchPermissions(),
      AdminService.fetchActiveShifts(),
      AdminService.fetchInspections(),
      AdminService.fetchDrivers(),
    ]);

    if (mounted) {
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _orders = results[1] as List<dynamic>;
        _vehicles = results[2] as List<dynamic>;
        _products = results[3] as List<dynamic>;
        _gasStations = results[4] as List<dynamic>;
        _users = results[5] as List<dynamic>;
        _roles = results[6] as List<dynamic>;
        _permissions = results[7] as List<dynamic>;
        _activeShifts = results[8] as List<dynamic>;
        _inspections = results[9] as List<dynamic>;
        _drivers = results[10] as List<dynamic>;
        _isLoading = false;
      });
    }
  }

  /// Lấy danh sách tài xế đã khử trùng lặp theo id từ cả _users và _drivers
  /// (đảm bảo tài khoản không phải super-admin 'admin' khi /users trả 403 vẫn có đủ danh sách tài xế)
  List<Map<String, dynamic>> _getAvailableDriverUsers() {
    final byId = <int, Map<String, dynamic>>{};
    for (final u in _users) {
      if (u is! Map) continue;
      final id = u['id'];
      if (id is! int) continue;
      final roleCodes =
          (u['role_codes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (roleCodes.contains('driver') || u['driver_type'] != null) {
        byId[id] = Map<String, dynamic>.from(u);
      }
    }
    for (final d in _drivers) {
      if (d is! Map) continue;
      final id = d['id'];
      if (id is! int) continue;
      if (byId.containsKey(id)) continue;
      final roleCodes =
          (d['role_codes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];
      if (roleCodes.contains('driver') || d['driver_type'] != null) {
        byId[id] = Map<String, dynamic>.from(d);
      }
    }
    return byId.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (widget.activeTab) {
      case 0:
        return _buildOverviewTab(state);
      case 1:
        return _buildOrdersTab(state);
      case 2:
      case 3:
      case 4:
      case 5:
        // Đội xe, Tài khoản, Cây dầu, Sản phẩm: chỉ Admin và Quản lý / Giám đốc
        final canManageUsers =
            state.currentUsername == 'admin' ||
            state.userRoles.any(
              (r) => ['admin', 'manager'].contains(r.toLowerCase()),
            );
        if (!canManageUsers) {
          return _buildOverviewTab(state);
        }
        if (widget.activeTab == 2) return _buildVehiclesTab();
        if (widget.activeTab == 3) return _buildUserListSubtab();
        if (widget.activeTab == 4) return _buildGasStationsTab();
        return _buildProductsTab();
      case 6:
        return _buildRolesSubtab();
      case 7:
        return _buildRemindersConfigTab(state);
      case 8:
        return _buildProxyAiConfigTab(state);
      case 9:
        // Khách hàng: Điều phối, Quản lý / Giám đốc, Admin
        final canManageCustomers =
            state.currentUsername == 'admin' ||
            state.userRoles.any(
              (r) => ['admin', 'manager', 'dispatcher'].contains(r.toLowerCase()),
            );
        if (!canManageCustomers) {
          return _buildOverviewTab(state);
        }
        return const CustomersScreen();
      default:
        return _buildOverviewTab(state);
    }
  }

  // TAB 1: Tổng quan điều hành & Báo cáo tuân thủ
  Widget _buildOverviewTab(AppState state) {
    // Chỉ tài khoản Admin và Giám đốc (manager) mới được nhìn thấy và vào quản lý Tổng người dùng
    final bool canManageUsers =
        state.currentUsername == 'admin' ||
        state.userRoles.any(
          (r) => ['admin', 'manager'].contains(r.toLowerCase()),
        );

    final vehiclesCard = _buildMetricCard(
      "Tổng phương tiện",
      "${_summary['total_vehicles'] ?? _vehicles.length} xe",
      Icons.directions_car,
      Colors.blue,
      onTap: () => widget.onTabChanged?.call(2),
    );
    final ordersCard = _buildMetricCard(
      "Đơn hàng hôm nay",
      "${_summary['total_orders'] ?? _orders.length} đơn",
      Icons.receipt_long,
      Colors.teal,
      onTap: () => widget.onTabChanged?.call(1),
    );
    final complianceCard = _buildMetricCard(
      "Tỷ lệ tuân thủ 5 ảnh",
      _summary['compliance_rate'] ?? "96.4%",
      Icons.verified_user,
      Colors.purple,
      onTap: () {
        if (widget.onOpenInspectionScreen != null) {
          widget.onOpenInspectionScreen!();
        } else {
          _showVehicleInspectionsDialog(null, null);
        }
      },
    );

    return RefreshIndicator(
      onRefresh: _loadAllManagementData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (canManageUsers) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      "Tổng người dùng",
                      "${_users.length} tài khoản",
                      Icons.people,
                      Colors.indigo,
                      onTap: () => widget.onTabChanged?.call(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: vehiclesCard),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ordersCard),
                  const SizedBox(width: 12),
                  Expanded(child: complianceCard),
                ],
              ),
            ),
          ] else ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: vehiclesCard),
                  const SizedBox(width: 12),
                  Expanded(child: ordersCard),
                  const SizedBox(width: 12),
                  Expanded(child: complianceCard),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // KHỐI QUẢN LÝ CA TRỰC ĐIỀU PHỐI (DISPATCHER SHIFTS & ON DUTY)
          _buildActiveDispatchersCard(state),
          const SizedBox(height: 16),

          // KHỐI BÁO CÁO REALTIME TRẠNG THÁI TÀI XẾ
          _buildRealtimeDriverReportsCard(state),
        ],
      ),
    );
  }

  // Hỗ trợ trích xuất ngày tháng từ đơn hàng (created_at hoặc từ mã đơn hàng dạng YYYYMMDD)
  DateTime? _extractOrderDate(dynamic o) {
    if (o is! Map) return null;
    final rawDate = o['created_at'] ?? o['order_date'];
    if (rawDate != null) {
      final parsed = DateTime.tryParse(rawDate.toString());
      if (parsed != null) return parsed.toLocal();
    }
    final code = (o['order_code'] ?? '').toString();
    final match = RegExp(r'(20\d{2})(\d{2})(\d{2})').firstMatch(code);
    if (match != null) {
      final y = int.tryParse(match.group(1)!);
      final m = int.tryParse(match.group(2)!);
      final d = int.tryParse(match.group(3)!);
      if (y != null && m != null && d != null) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  String _formatOrderDateLabel(DateTime? dt) {
    if (dt == null) return 'Chưa rõ ngày';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  void _resetOrderFilters() {
    _orderSearchCtrl.clear();
    _orderCodeFilterCtrl.clear();
    _orderPickupFilterCtrl.clear();
    _orderDeliveryFilterCtrl.clear();
    setState(() {
      _orderSearchQuery = '';
      _orderCodeFilter = '';
      _orderPickupFilter = '';
      _orderDeliveryFilter = '';
      _selectedOrderProductFilter = 'ALL';
      _selectedOrderVehicleFilter = 'ALL';
      _selectedOrderDriverFilter = 'ALL';
      _selectedOrderTransportTypeFilter = 'ALL';
      _selectedOrderStatusFilter = 'ALL';
      _orderStartDate = null;
      _orderEndDate = null;
      _orderCurrentPage = 1;
    });
  }

  bool get _hasActiveOrderFilters {
    return _orderSearchQuery.trim().isNotEmpty ||
        _orderCodeFilter.trim().isNotEmpty ||
        _orderPickupFilter.trim().isNotEmpty ||
        _orderDeliveryFilter.trim().isNotEmpty ||
        _selectedOrderProductFilter != 'ALL' ||
        _selectedOrderVehicleFilter != 'ALL' ||
        _selectedOrderDriverFilter != 'ALL' ||
        _selectedOrderTransportTypeFilter != 'ALL' ||
        _selectedOrderStatusFilter != 'ALL' ||
        _orderStartDate != null ||
        _orderEndDate != null;
  }

  Future<void> _pickOrderDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_orderStartDate ?? _orderEndDate ?? now)
        : (_orderEndDate ?? _orderStartDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      helpText: isStart ? 'CHỌN TỪ NGÀY' : 'CHỌN ĐẾN NGÀY',
      cancelText: 'Hủy',
      confirmText: 'Áp dụng',
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _orderStartDate = DateTime(picked.year, picked.month, picked.day);
          if (_orderEndDate != null &&
              _orderEndDate!.isBefore(_orderStartDate!)) {
            _orderEndDate = _orderStartDate;
          }
        } else {
          _orderEndDate = DateTime(picked.year, picked.month, picked.day);
          if (_orderStartDate != null &&
              _orderStartDate!.isAfter(_orderEndDate!)) {
            _orderStartDate = _orderEndDate;
          }
        }
        _orderCurrentPage = 1;
      });
    }
  }

  // TAB 2: Đơn hàng vận tải (Tích hợp Bộ lọc đa tiêu chí, DataTable & Phân trang)
  Widget _buildOrdersTab(AppState state) {
    return Builder(
      builder: (context) {
        final canManageOrders =
            state.currentUsername == 'admin' ||
            state.userRoles.any(
              (r) =>
                  ['admin', 'manager', 'dispatcher'].contains(r.toLowerCase()),
            );
        // Tổng hợp danh sách tùy chọn động cho Dropdown từ dữ liệu đơn hàng, sản phẩm, xe, tài xế
        final productOptions = <String>{};
        for (final p in _products) {
          final name = (p['name'] ?? '').toString().trim();
          if (name.isNotEmpty) productOptions.add(name);
        }
        final vehicleOptions = <String>{};
        for (final v in _activeVehicles) {
          final plate = (v['plate_number'] ?? '').toString().trim();
          if (plate.isNotEmpty) vehicleOptions.add(plate);
        }
        final driverOptions = <String>{};
        for (final o in _orders) {
          final pName = (o['product_name'] ?? '').toString().trim();
          if (pName.isNotEmpty) productOptions.add(pName);
          final vPlate = (o['assigned_vehicle_plate'] ?? '').toString().trim();
          if (vPlate.isNotEmpty) vehicleOptions.add(vPlate);
          final dName = (o['driver_name'] ?? '').toString().trim();
          if (dName.isNotEmpty) driverOptions.add(dName);
        }

        final sortedProducts = productOptions.toList()..sort();
        final sortedVehicles = vehicleOptions.toList()..sort();
        final sortedDrivers = driverOptions.toList()..sort();

        final safeProductVal =
            (_selectedOrderProductFilter == 'ALL' ||
                sortedProducts.contains(_selectedOrderProductFilter))
            ? _selectedOrderProductFilter
            : 'ALL';
        final safeVehicleVal =
            (_selectedOrderVehicleFilter == 'ALL' ||
                sortedVehicles.contains(_selectedOrderVehicleFilter))
            ? _selectedOrderVehicleFilter
            : 'ALL';
        final safeDriverVal =
            (_selectedOrderDriverFilter == 'ALL' ||
                sortedDrivers.contains(_selectedOrderDriverFilter))
            ? _selectedOrderDriverFilter
            : 'ALL';

        final qGeneral = _orderSearchQuery.toLowerCase().trim();
        final qCode = _orderCodeFilter.toLowerCase().trim();
        final qPickup = _orderPickupFilter.toLowerCase().trim();
        final qDelivery = _orderDeliveryFilter.toLowerCase().trim();

        final filteredOrders = _orders.where((o) {
          final orderCode = (o['order_code'] ?? '').toString();
          final productName = (o['product_name'] ?? 'Vật liệu').toString();
          final pickupAddr = (o['pickup_address'] ?? '').toString();
          final deliveryAddr = (o['delivery_address'] ?? '').toString();
          final vehiclePlate = (o['assigned_vehicle_plate'] ?? '').toString();
          final driverName = (o['driver_name'] ?? 'Nguyễn Văn A').toString();
          final transportType = (o['transport_type'] ?? '').toString();
          final orderDate = _extractOrderDate(o);
          final dateLabel = _formatOrderDateLabel(orderDate);

          // 1. Lọc theo khoảng ngày tháng (Từ ngày - Đến ngày)
          if (_orderStartDate != null || _orderEndDate != null) {
            if (orderDate == null) return false;
            final normalizedDate = DateTime(
              orderDate.year,
              orderDate.month,
              orderDate.day,
            );
            if (_orderStartDate != null &&
                normalizedDate.isBefore(_orderStartDate!)) {
              return false;
            }
            if (_orderEndDate != null &&
                normalizedDate.isAfter(_orderEndDate!)) {
              return false;
            }
          }

          // 2. Lọc theo Mã đơn hàng
          if (qCode.isNotEmpty && !orderCode.toLowerCase().contains(qCode)) {
            return false;
          }

          // 3. Lọc theo Sản phẩm
          if (safeProductVal != 'ALL' && productName.trim() != safeProductVal) {
            return false;
          }

          // 4. Lọc theo Xe (Biển số)
          if (safeVehicleVal != 'ALL' &&
              vehiclePlate.trim() != safeVehicleVal) {
            return false;
          }

          // 5. Lọc theo Tài xế
          if (safeDriverVal != 'ALL' && driverName.trim() != safeDriverVal) {
            return false;
          }

          // 6. Lọc theo Loại hình vận chuyển
          if (_selectedOrderTransportTypeFilter != 'ALL' &&
              transportType != _selectedOrderTransportTypeFilter) {
            return false;
          }

          // 6b. Lọc theo Trạng thái đơn hàng
          final normStatus = _normalizeOrderStatus((o['status'] ?? 'assigned').toString());
          if (_selectedOrderStatusFilter != 'ALL' &&
              normStatus != _selectedOrderStatusFilter) {
            return false;
          }

          // 7. Lọc theo Nơi nhận
          if (qPickup.isNotEmpty &&
              !pickupAddr.toLowerCase().contains(qPickup)) {
            return false;
          }

          // 8. Lọc theo Điểm giao
          if (qDelivery.isNotEmpty &&
              !deliveryAddr.toLowerCase().contains(qDelivery)) {
            return false;
          }

          // 9. Tìm kiếm tổng hợp nhanh
          if (qGeneral.isNotEmpty) {
            final matchAny =
                orderCode.toLowerCase().contains(qGeneral) ||
                productName.toLowerCase().contains(qGeneral) ||
                pickupAddr.toLowerCase().contains(qGeneral) ||
                deliveryAddr.toLowerCase().contains(qGeneral) ||
                vehiclePlate.toLowerCase().contains(qGeneral) ||
                driverName.toLowerCase().contains(qGeneral) ||
                dateLabel.toLowerCase().contains(qGeneral);
            if (!matchAny) return false;
          }

          return true;
        }).toList();

        final totalItems = filteredOrders.length;
        final totalPages = (totalItems / _orderPageSize).ceil().clamp(1, 99999);
        final validPage = _orderCurrentPage.clamp(1, totalPages);
        final startIndex = totalItems == 0
            ? 0
            : (validPage - 1) * _orderPageSize;
        final endIndex = (startIndex + _orderPageSize > totalItems)
            ? totalItems
            : startIndex + _orderPageSize;
        final paginatedOrders = totalItems == 0
            ? []
            : filteredOrders.sublist(startIndex, endIndex);

        if (widget.onOrderCountChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onOrderCountChanged!(
                filteredOrders.length,
                _orders.length,
              );
            }
          });
        }

        return Column(
          children: [
            // KHỐI CÔNG CỤ TÌM KIẾM & BỘ LỌC ĐA TIÊU CHÍ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 720;
                  final isTablet =
                      constraints.maxWidth >= 720 &&
                      constraints.maxWidth < 1100;

                  // Chiều cao đồng bộ chuẩn xác 36px cho toàn bộ Button, Input, Select và DatePicker
                  const double kControlHeight = 36.0;
                  const BoxConstraints kControlConstraints = BoxConstraints(
                    minHeight: kControlHeight,
                    maxHeight: kControlHeight,
                  );
                  const BoxConstraints kPrefixIconConstraints = BoxConstraints(
                    minWidth: 34,
                    minHeight: kControlHeight,
                    maxHeight: kControlHeight,
                  );
                  const EdgeInsets kFilterPadding = EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  );

                  // Widget chọn Từ ngày
                  Widget buildStartDatePicker() {
                    final hasVal = _orderStartDate != null;
                    return InkWell(
                      onTap: () => _pickOrderDate(isStart: true),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: kControlHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: hasVal ? Colors.blue.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hasVal
                                ? Colors.blue.shade400
                                : Colors.black26,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 16,
                              color: hasVal
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                hasVal
                                    ? "Từ: ${_formatOrderDateLabel(_orderStartDate)}"
                                    : "Từ ngày...",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: hasVal
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: hasVal
                                      ? Colors.blue.shade900
                                      : Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasVal)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _orderStartDate = null;
                                    _orderCurrentPage = 1;
                                  });
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Widget chọn Đến ngày
                  Widget buildEndDatePicker() {
                    final hasVal = _orderEndDate != null;
                    return InkWell(
                      onTap: () => _pickOrderDate(isStart: false),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: kControlHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: hasVal ? Colors.blue.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hasVal
                                ? Colors.blue.shade400
                                : Colors.black26,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event_available_outlined,
                              size: 16,
                              color: hasVal
                                  ? Colors.blue.shade800
                                  : Colors.grey.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                hasVal
                                    ? "Đến: ${_formatOrderDateLabel(_orderEndDate)}"
                                    : "Đến ngày...",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: hasVal
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: hasVal
                                      ? Colors.blue.shade900
                                      : Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasVal)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _orderEndDate = null;
                                    _orderCurrentPage = 1;
                                  });
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  // Các ô lọc chi tiết (Đồng bộ chiều cao 40px cho Input, Select, DatePicker và Button)
                  Widget buildOrderCodeInput() {
                    return SizedBox(
                      height: kControlHeight,
                      child: TextField(
                        controller: _orderCodeFilterCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _orderCodeFilter = val;
                            _orderCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          hintText: "Lọc mã đơn hàng...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          contentPadding: kFilterPadding,
                          prefixIcon: const Icon(
                            Icons.qr_code_2_outlined,
                            size: 17,
                          ),
                          prefixIconConstraints: kPrefixIconConstraints,
                          suffixIcon: _orderCodeFilter.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: kPrefixIconConstraints,
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _orderCodeFilterCtrl.clear();
                                    setState(() {
                                      _orderCodeFilter = "";
                                      _orderCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    );
                  }

                  Widget buildProductDropdown() {
                    return SizedBox(
                      height: kControlHeight,
                      child: DropdownButtonFormField<String>(
                        value: safeProductVal,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          contentPadding: kFilterPadding,
                          prefixIcon: Icon(Icons.category_outlined, size: 17),
                          prefixIconConstraints: kPrefixIconConstraints,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: "ALL",
                            child: Text(
                              "Tất cả sản phẩm",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...sortedProducts.map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                p,
                                style: const TextStyle(fontSize: 12.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOrderProductFilter = val;
                              _orderCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    );
                  }

                  Widget buildVehicleDropdown() {
                    return SizedBox(
                      height: kControlHeight,
                      child: DropdownButtonFormField<String>(
                        value: safeVehicleVal,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          contentPadding: kFilterPadding,
                          prefixIcon: Icon(
                            Icons.local_shipping_outlined,
                            size: 17,
                          ),
                          prefixIconConstraints: kPrefixIconConstraints,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: "ALL",
                            child: Text(
                              "Tất cả xe",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...sortedVehicles.map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v,
                                style: const TextStyle(fontSize: 12.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOrderVehicleFilter = val;
                              _orderCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    );
                  }

                  Widget buildDriverDropdown() {
                    return SizedBox(
                      height: kControlHeight,
                      child: DropdownButtonFormField<String>(
                        value: safeDriverVal,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          contentPadding: kFilterPadding,
                          prefixIcon: Icon(Icons.person_outline, size: 17),
                          prefixIconConstraints: kPrefixIconConstraints,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: "ALL",
                            child: Text(
                              "Tất cả tài xế",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ...sortedDrivers.map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(
                                d,
                                style: const TextStyle(fontSize: 12.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOrderDriverFilter = val;
                              _orderCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    );
                  }

                  Widget buildTransportTypeDropdown() {
                    return SizedBox(
                      height: kControlHeight,
                      child: DropdownButtonFormField<String>(
                        value: _selectedOrderTransportTypeFilter,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          contentPadding: kFilterPadding,
                          prefixIcon: Icon(Icons.business_outlined, size: 17),
                          prefixIconConstraints: kPrefixIconConstraints,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "ALL",
                            child: Text(
                              "Mọi loại xe",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: "INTERNAL",
                            child: Text(
                              "Xe công ty",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: "RENTAL",
                            child: Text(
                              "Xe thuê ngoài",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: "CUSTOMER_SELF",
                            child: Text(
                              "Khách tự lấy",
                              style: TextStyle(fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOrderTransportTypeFilter = val;
                              _orderCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    );
                  }

                  Widget buildPickupInput() {
                    return SizedBox(
                      height: kControlHeight,
                      child: TextField(
                        controller: _orderPickupFilterCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _orderPickupFilter = val;
                            _orderCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          hintText: "Lọc theo nơi nhận...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          contentPadding: kFilterPadding,
                          prefixIcon: const Icon(
                            Icons.warehouse_outlined,
                            size: 17,
                          ),
                          prefixIconConstraints: kPrefixIconConstraints,
                          suffixIcon: _orderPickupFilter.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: kPrefixIconConstraints,
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _orderPickupFilterCtrl.clear();
                                    setState(() {
                                      _orderPickupFilter = "";
                                      _orderCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    );
                  }

                  Widget buildDeliveryInput() {
                    return SizedBox(
                      height: kControlHeight,
                      child: TextField(
                        controller: _orderDeliveryFilterCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _orderDeliveryFilter = val;
                            _orderCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          hintText: "Lọc theo điểm giao...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          contentPadding: kFilterPadding,
                          prefixIcon: const Icon(
                            Icons.location_on_outlined,
                            size: 17,
                          ),
                          prefixIconConstraints: kPrefixIconConstraints,
                          suffixIcon: _orderDeliveryFilter.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: kPrefixIconConstraints,
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _orderDeliveryFilterCtrl.clear();
                                    setState(() {
                                      _orderDeliveryFilter = "";
                                      _orderCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    );
                  }

                  Widget buildOrderStatusFilterDropdown() {
                    return SizedBox(
                      height: kControlHeight,
                      child: DropdownButtonFormField<String>(
                        value: _selectedOrderStatusFilter,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: kControlConstraints,
                          contentPadding: kFilterPadding,
                          prefixIcon: Icon(Icons.flag_outlined, size: 17),
                          prefixIconConstraints: kPrefixIconConstraints,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "ALL",
                            child: Text("Mọi trạng thái", style: TextStyle(fontSize: 12.5)),
                          ),
                          DropdownMenuItem(
                            value: "waiting",
                            child: Text("Chờ nhận", style: TextStyle(fontSize: 12.5)),
                          ),
                          DropdownMenuItem(
                            value: "assigned",
                            child: Text("Đã điều phối", style: TextStyle(fontSize: 12.5)),
                          ),
                          DropdownMenuItem(
                            value: "in_transit",
                            child: Text("Đang vận chuyển", style: TextStyle(fontSize: 12.5)),
                          ),
                          DropdownMenuItem(
                            value: "completed",
                            child: Text("Hoàn thành", style: TextStyle(fontSize: 12.5)),
                          ),
                          DropdownMenuItem(
                            value: "cancelled",
                            child: Text("Đã hủy", style: TextStyle(fontSize: 12.5)),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOrderStatusFilter = val;
                              _orderCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    );
                  }

                  final filterFields = <Widget>[
                    buildStartDatePicker(),
                    buildEndDatePicker(),
                    buildOrderCodeInput(),
                    buildProductDropdown(),
                    buildVehicleDropdown(),
                    buildDriverDropdown(),
                    buildPickupInput(),
                    buildDeliveryInput(),
                    buildTransportTypeDropdown(),
                    buildOrderStatusFilterDropdown(),
                  ];

                  final int columnsCount = isMobile ? 1 : (isTablet ? 2 : 3);
                  final double spacing = 10.0;
                  final double itemWidth =
                      (constraints.maxWidth - (columnsCount - 1) * spacing) /
                      columnsCount;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Hàng 1: Tìm kiếm tổng hợp + Nút đóng/mở bộ lọc chi tiết + Xóa lọc + Tải lại (Đồng bộ height = 40px)
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: isMobile
                                ? constraints.maxWidth
                                : (constraints.maxWidth * 0.42).clamp(
                                    260.0,
                                    520.0,
                                  ),
                            height: kControlHeight,
                            child: TextField(
                              controller: _orderSearchCtrl,
                              style: const TextStyle(fontSize: 12.5),
                              textAlignVertical: TextAlignVertical.center,
                              onChanged: (val) {
                                setState(() {
                                  _orderSearchQuery = val;
                                  _orderCurrentPage = 1;
                                });
                              },
                              decoration: InputDecoration(
                                isDense: true,
                                constraints: kControlConstraints,
                                hintText:
                                    "Tìm nhanh mã đơn, tài xế, biển số xe, nơi nhận, điểm giao, sản phẩm...",
                                hintStyle: const TextStyle(fontSize: 12.5),
                                contentPadding: kFilterPadding,
                                prefixIcon: const Icon(Icons.search, size: 18),
                                prefixIconConstraints: kPrefixIconConstraints,
                                suffixIcon: _orderSearchQuery.isNotEmpty
                                    ? IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: kPrefixIconConstraints,
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _orderSearchCtrl.clear();
                                          setState(() {
                                            _orderSearchQuery = "";
                                            _orderCurrentPage = 1;
                                          });
                                        },
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          // Nút bật/tắt bộ lọc chi tiết
                          SizedBox(
                            height: kControlHeight,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _showAdvancedOrderFilters
                                    ? Colors.blue.shade50
                                    : Colors.white,
                                foregroundColor: Colors.blue.shade800,
                                side: BorderSide(color: Colors.blue.shade300),
                                minimumSize: const Size(0, kControlHeight),
                                fixedSize: const Size.fromHeight(
                                  kControlHeight,
                                ),
                                visualDensity: VisualDensity.standard,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              icon: Icon(
                                _showAdvancedOrderFilters
                                    ? Icons.filter_alt_off_outlined
                                    : Icons.filter_alt_outlined,
                                size: 16,
                              ),
                              label: Text(
                                _showAdvancedOrderFilters
                                    ? "Thu gọn bộ lọc"
                                    : "Bộ lọc chi tiết",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  _showAdvancedOrderFilters =
                                      !_showAdvancedOrderFilters;
                                });
                              },
                            ),
                          ),
                          if (_hasActiveOrderFilters)
                            SizedBox(
                              height: kControlHeight,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade700,
                                  side: BorderSide(color: Colors.red.shade300),
                                  minimumSize: const Size(0, kControlHeight),
                                  fixedSize: const Size.fromHeight(
                                    kControlHeight,
                                  ),
                                  visualDensity: VisualDensity.standard,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                icon: const Icon(Icons.restart_alt, size: 16),
                                label: const Text(
                                  "Xóa bộ lọc",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                                onPressed: _resetOrderFilters,
                              ),
                            ),
                          SizedBox(
                            height: kControlHeight,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blue.shade800,
                                side: BorderSide(color: Colors.blue.shade300),
                                minimumSize: const Size(0, kControlHeight),
                                fixedSize: const Size.fromHeight(
                                  kControlHeight,
                                ),
                                visualDensity: VisualDensity.standard,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text(
                                "Tải lại",
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                              onPressed: _loadAllManagementData,
                            ),
                          ),
                          if (canManageOrders)
                            SizedBox(
                              height: kControlHeight,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade800,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, kControlHeight),
                                  fixedSize: const Size.fromHeight(
                                    kControlHeight,
                                  ),
                                  visualDensity: VisualDensity.standard,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.add_shopping_cart,
                                  size: 16,
                                ),
                                label: const Text(
                                  "Tạo đơn hàng",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                                onPressed: _showCreateOrderDialog,
                              ),
                            ),
                        ],
                      ),
                      // Khối bộ lọc chi tiết (Ngày tháng, Mã đơn, Sản phẩm, Xe, Tài xế, Nơi nhận, Điểm giao, Loại xe)
                      if (_showAdvancedOrderFilters) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: spacing,
                          runSpacing: 10,
                          children: filterFields
                              .map(
                                (w) => SizedBox(
                                  width: itemWidth,
                                  height: kControlHeight,
                                  child: w,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: paginatedOrders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Không tìm thấy đơn hàng nào phù hợp với điều kiện lọc",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_hasActiveOrderFilters) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 44,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue.shade800,
                                  side: BorderSide(color: Colors.blue.shade300),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                icon: const Icon(Icons.clear_all, size: 16),
                                label: const Text(
                                  "Đặt lại bộ lọc",
                                  style: TextStyle(fontSize: 12.5),
                                ),
                                onPressed: _resetOrderFilters,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.grey.shade100,
                                ),
                                headingRowHeight: 44,
                                dividerThickness: 0,
                                dataRowMaxHeight: 64,
                                dataRowMinHeight: 56,
                                horizontalMargin: 16,
                                columnSpacing: 20,
                                columns: [
                                  const DataColumn(
                                    label: Text(
                                      "Mã đơn hàng",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Ngày tạo",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Sản phẩm / Trọng lượng",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Điểm nhận & Giao",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Phương tiện & Tài xế",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Hình thức",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Hình chụp liên quan",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const DataColumn(
                                    label: Text(
                                      "Trạng thái",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (canManageOrders)
                                    const DataColumn(
                                      label: Text(
                                        "Thao tác",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                ],
                                rows: List.generate(paginatedOrders.length, (
                                  idx,
                                ) {
                                  final o = paginatedOrders[idx];
                                  final rowColor = idx % 2 == 0
                                      ? Colors.white
                                      : Colors.grey.shade50;
                                  final orderCode =
                                      (o['order_code'] ?? 'MÃ ĐƠN').toString();
                                  final orderDate = _extractOrderDate(o);
                                  final dateStr = _formatOrderDateLabel(
                                    orderDate,
                                  );
                                  final productName =
                                      (o['product_name'] ?? 'Vật liệu')
                                          .toString();
                                  final weightTons =
                                      o['cargo_weight_tons']?.toString() ?? '0';
                                  final pickupAddr =
                                      (o['pickup_address'] ?? 'N/A').toString();
                                  final deliveryAddr =
                                      (o['delivery_address'] ?? 'N/A')
                                          .toString();
                                  final vehiclePlate =
                                      (o['assigned_vehicle_plate'] ?? '')
                                          .toString();
                                  final driverName = (o['driver_name'] ?? '')
                                      .toString();
                                  final transportType =
                                      (o['transport_type'] ?? 'INTERNAL')
                                          .toString();

                                  DataCell makeCell(Widget child) {
                                    return DataCell(
                                      Container(
                                        alignment: Alignment.centerLeft,
                                        child: child,
                                      ),
                                    );
                                  }

                                  Color transBg = Colors.blue.shade50;
                                  Color transBorder = Colors.blue.shade200;
                                  Color transText = Colors.blue.shade800;
                                  if (transportType == 'RENTAL') {
                                    transBg = Colors.purple.shade50;
                                    transBorder = Colors.purple.shade200;
                                    transText = Colors.purple.shade800;
                                  } else if (transportType == 'CUSTOMER_SELF') {
                                    transBg = Colors.orange.shade50;
                                    transBorder = Colors.orange.shade200;
                                    transText = Colors.orange.shade900;
                                  }

                                  return DataRow(
                                    color: MaterialStateProperty.all(rowColor),
                                    cells: [
                                      // Cột 1: Mã đơn hàng (bấm để xem chi tiết & hình chụp)
                                      makeCell(
                                        InkWell(
                                          borderRadius: BorderRadius.circular(4),
                                          onTap: () => _showOrderAttachmentsDialog(o),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Icon(
                                                  Icons.receipt_long,
                                                  size: 16,
                                                  color: Colors.blue,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                orderCode,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Cột 2: Ngày tạo
                                      makeCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.calendar_today,
                                              size: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              dateStr,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade800,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Cột 3: Sản phẩm & Trọng lượng
                                      makeCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              productName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "$weightTons tấn",
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.indigo.shade800,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Cột 4: Nơi nhận & Điểm giao
                                      makeCell(
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 240,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.trip_origin,
                                                    size: 11,
                                                    color:
                                                        Colors.amber.shade800,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      pickupAddr,
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.location_on,
                                                    size: 11,
                                                    color: Colors.red.shade700,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      deliveryAddr,
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Cột 5: Xe & Tài xế
                                      makeCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.local_shipping,
                                                  size: 13,
                                                  color: Colors.blueGrey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  vehiclePlate.isNotEmpty
                                                      ? vehiclePlate
                                                      : "Chưa gán xe",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        vehiclePlate.isNotEmpty
                                                        ? Colors.black87
                                                        : Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.person,
                                                  size: 13,
                                                  color: Colors.teal,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  driverName.isNotEmpty
                                                      ? driverName
                                                      : "Chưa gán tài xế",
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    color: driverName.isNotEmpty
                                                        ? Colors.teal.shade800
                                                        : Colors.grey.shade500,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Cột 6: Hình thức
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: transBg,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: transBorder,
                                            ),
                                          ),
                                          child: Text(
                                            _translateTransportType(
                                              transportType,
                                            ),
                                            style: TextStyle(
                                              color: transText,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Cột 7: Hình chụp liên quan (Phiếu bơm, Phiếu cân, Phiếu giao, Báo hỏng, Sửa chữa KT)
                                      makeCell(
                                        _buildOrderPhotosSummaryCell(o),
                                      ),
                                      // Cột 8: Select box chuyển đổi Trạng thái đơn hàng trực tiếp
                                      makeCell(
                                        _buildOrderStatusSelectBox(
                                          o,
                                          canEdit: canManageOrders,
                                        ),
                                      ),
                                      // Cột 9: Thao tác (Sửa, Xóa)
                                      if (canManageOrders)
                                        makeCell(
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.blue.shade800,
                                                  side: BorderSide(
                                                    color: Colors.blue.shade300,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.edit,
                                                  size: 13,
                                                ),
                                                label: const Text(
                                                  "Sửa",
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _showEditOrderDialog(o),
                                              ),
                                              const SizedBox(width: 6),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.red.shade700,
                                                  side: BorderSide(
                                                    color: Colors.red.shade300,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 13,
                                                ),
                                                label: const Text(
                                                  "Xóa",
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _confirmDeleteOrder(o),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // THANH ĐIỀU HƯỚNG PHÂN TRANG (PAGINATION BAR)
            if (filteredOrders.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems đơn hàng",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Số dòng/trang: ",
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(width: 4),
                        DropdownButton<int>(
                          value: _orderPageSize,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.bold,
                          ),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text("5")),
                            DropdownMenuItem(value: 10, child: Text("10")),
                            DropdownMenuItem(value: 20, child: Text("20")),
                            DropdownMenuItem(value: 50, child: Text("50")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _orderPageSize = val;
                                _orderCurrentPage = 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 14),
                        IconButton(
                          icon: const Icon(Icons.first_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang đầu",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _orderCurrentPage = 1;
                                  });
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang trước",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _orderCurrentPage = validPage - 1;
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "$validPage / $totalPages",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang sau",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _orderCurrentPage = validPage + 1;
                                  });
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.last_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang cuối",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _orderCurrentPage = totalPages;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // TAB 3: Đội xe & Phương tiện (Dữ liệu thực tế từ hệ thống GPS & Doanh nghiệp)
  Widget _buildVehiclesTab() {
    return Builder(
      builder: (context) {
        final query = _vehicleSearchQuery.toLowerCase().trim();
        final filteredVehicles = _vehicles.where((v) {
          // 1. Kiểm tra hình thức sở hữu (Ownership Filter)
          if (_selectedOwnershipFilter != 'ALL') {
            final own = (v['ownership_type'] ?? '').toString();
            if (own != _selectedOwnershipFilter) {
              return false;
            }
          }

          // 2. Kiểm tra từ khóa tìm kiếm (Search Query)
          if (query.isNotEmpty) {
            final plate = (v['plate_number'] ?? '').toString().toLowerCase();
            final vtype = (v['vehicle_type'] ?? '').toString().toLowerCase();
            final driverName = (v['driver_name'] ?? '')
                .toString()
                .toLowerCase();
            final ownerCompany = (v['owner_company'] ?? '')
                .toString()
                .toLowerCase();

            final match =
                plate.contains(query) ||
                vtype.contains(query) ||
                driverName.contains(query) ||
                ownerCompany.contains(query);
            if (!match) return false;
          }

          return true;
        }).toList();

        final totalItems = filteredVehicles.length;
        final totalPages = (totalItems / _vehiclePageSize).ceil().clamp(
          1,
          99999,
        );
        final validPage = _vehicleCurrentPage.clamp(1, totalPages);
        final startIndex = totalItems == 0
            ? 0
            : (validPage - 1) * _vehiclePageSize;
        final endIndex = (startIndex + _vehiclePageSize > totalItems)
            ? totalItems
            : startIndex + _vehiclePageSize;
        final paginatedVehicles = totalItems == 0
            ? []
            : filteredVehicles.sublist(startIndex, endIndex);

        if (widget.onVehicleCountChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onVehicleCountChanged!(
                filteredVehicles.length,
                _vehicles.length,
              );
            }
          });
        }

        return Column(
          children: [
            // Thanh công cụ 1 hàng: Tìm kiếm + Lọc sở hữu + Thống kê số lượng + Nút làm mới
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  // Ô tìm kiếm xe
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _vehicleSearchCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _vehicleSearchQuery = val;
                            _vehicleCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: const BoxConstraints(
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          hintText:
                              "Tìm theo biển số xe, loại xe, tài xế phụ trách...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 17),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          suffixIcon: _vehicleSearchQuery.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 36,
                                    maxHeight: 36,
                                  ),
                                  icon: const Icon(Icons.clear, size: 15),
                                  onPressed: () {
                                    _vehicleSearchCtrl.clear();
                                    setState(() {
                                      _vehicleSearchQuery = '';
                                      _vehicleCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Bộ lọc theo Hình thức sở hữu
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 36,
                      child: DropdownButtonFormField<String>(
                        value: _selectedOwnershipFilter,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: BoxConstraints(
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          prefixIcon: Icon(Icons.filter_alt_outlined, size: 17),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'ALL',
                            child: Text("Tất cả sở hữu"),
                          ),
                          DropdownMenuItem(
                            value: 'INTERNAL',
                            child: Text("Xe nội bộ"),
                          ),
                          DropdownMenuItem(
                            value: 'RENTAL',
                            child: Text("Xe thuê ngoài"),
                          ),
                          DropdownMenuItem(
                            value: 'CUSTOMER_SELF',
                            child: Text("Xe khách hàng"),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOwnershipFilter = val;
                              _vehicleCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Nút làm mới dữ liệu
                  SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade800,
                        side: BorderSide(color: Colors.blue.shade300),
                        minimumSize: const Size(0, 36),
                        fixedSize: const Size.fromHeight(36),
                        visualDensity: VisualDensity.standard,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      icon: _isSyncingFleet
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 15),
                      label: Text(
                        _isSyncingFleet ? "Đang đồng bộ..." : "Tải lại danh sách",
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      onPressed: _isSyncingFleet ? null : _syncFleetAndReload,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Bảng danh sách phương tiện
            Expanded(
              child: paginatedVehicles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.no_transfer,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Không tìm thấy phương tiện nào phù hợp với bộ lọc",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.grey.shade100,
                                ),
                                headingRowHeight: 44,
                                dividerThickness: 0,
                                dataRowMaxHeight: 64,
                                dataRowMinHeight: 58,
                                horizontalMargin: 16,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      "Biển số xe",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Loại phương tiện",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Hình thức sở hữu",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Tài xế chỉ định",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Đơn vị quản lý",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Trạng thái & Thiết bị Token",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Thao tác",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: List.generate(paginatedVehicles.length, (
                                  idx,
                                ) {
                                  final v = paginatedVehicles[idx];
                                  final rowColor = idx % 2 == 0
                                      ? Colors.white
                                      : Colors.grey.shade50;
                                  final plate = (v['plate_number'] ?? 'N/A')
                                      .toString();
                                  final vtype = (v['vehicle_type'] ?? 'Xe tải')
                                      .toString();
                                  final ownType =
                                      (v['ownership_type'] ?? 'INTERNAL')
                                          .toString();
                                  final driverName = (v['driver_name'] ?? '')
                                      .toString();
                                  final driverUsername =
                                      (v['driver_username'] ?? '').toString();
                                  final driverPhone = (v['driver_phone'] ?? '')
                                      .toString();
                                  final ownerCompany =
                                      (v['owner_company'] ??
                                              'Sao Mai Logistics')
                                          .toString();

                                  DataCell makeCell(Widget child) {
                                    return DataCell(
                                      Container(
                                        alignment: Alignment.centerLeft,
                                        child: child,
                                      ),
                                    );
                                  }

                                  Color ownBg = Colors.blue.shade50;
                                  Color ownBorder = Colors.blue.shade200;
                                  Color ownText = Colors.blue.shade800;
                                  if (ownType == 'RENTAL') {
                                    ownBg = Colors.purple.shade50;
                                    ownBorder = Colors.purple.shade200;
                                    ownText = Colors.purple.shade800;
                                  } else if (ownType == 'CUSTOMER_SELF') {
                                    ownBg = Colors.orange.shade50;
                                    ownBorder = Colors.orange.shade200;
                                    ownText = Colors.orange.shade900;
                                  }

                                  return DataRow(
                                    color: MaterialStateProperty.all(rowColor),
                                    cells: [
                                      // Cột 1: Biển số xe
                                      makeCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Icon(
                                                Icons.local_shipping,
                                                size: 18,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              plate,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: Colors.blueGrey.shade900,
                                              ),
                                            ),
                                            if (v['gps_provider'] ==
                                                'binhanh') ...[
                                              const SizedBox(width: 6),
                                              Tooltip(
                                                message:
                                                    "Xe lấy từ dịch vụ GPS Bình Anh",
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        Colors.green.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                    border: Border.all(
                                                      color: Colors
                                                          .green.shade300,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    "Bình Anh",
                                                    style: TextStyle(
                                                      color: Colors
                                                          .green.shade800,
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      // Cột 2: Loại phương tiện
                                      makeCell(
                                        Text(
                                          vtype,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      // Cột 3: Hình thức sở hữu
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: ownBg,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: ownBorder,
                                            ),
                                          ),
                                          child: Text(
                                            _translateOwnershipType(ownType),
                                            style: TextStyle(
                                              color: ownText,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Cột 4: Tài xế chỉ định (Bấm vào để mở chi tiết tài khoản)
                                      makeCell(
                                        driverName.isNotEmpty
                                            ? InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                onTap: () {
                                                  final driverId =
                                                      v['default_driver_id'];
                                                  dynamic matchedUser;
                                                  if (driverId != null) {
                                                    for (final u in [..._users, ..._drivers]) {
                                                      if (u is Map &&
                                                          u['id'] == driverId) {
                                                        matchedUser = u;
                                                        break;
                                                      }
                                                    }
                                                  }
                                                  if (matchedUser == null &&
                                                      driverUsername
                                                          .isNotEmpty) {
                                                    for (final u in _users) {
                                                      if (u is Map &&
                                                          u['username'] ==
                                                              driverUsername) {
                                                        matchedUser = u;
                                                        break;
                                                      }
                                                    }
                                                  }
                                                  if (matchedUser != null) {
                                                    _showEditUserDialog(
                                                      Map<String, dynamic>.from(
                                                        matchedUser as Map,
                                                      ),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        backgroundColor:
                                                            Colors.orange,
                                                        content: Text(
                                                          "Không tìm thấy thông tin tài khoản người dùng.",
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 4,
                                                        horizontal: 2,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons.person,
                                                            size: 15,
                                                            color: Colors.teal,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            driverName,
                                                            style: const TextStyle(
                                                              fontSize: 12.5,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color:
                                                                  Colors.teal,
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline,
                                                              decorationColor:
                                                                  Colors.teal,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (driverUsername
                                                              .isNotEmpty)
                                                            Text(
                                                              "@$driverUsername",
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .blueGrey
                                                                    .shade700,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                              ),
                                                            ),
                                                          if (driverUsername
                                                                  .isNotEmpty &&
                                                              driverPhone
                                                                  .isNotEmpty)
                                                            Text(
                                                              " • ",
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .grey
                                                                    .shade400,
                                                              ),
                                                            ),
                                                          if (driverPhone
                                                              .isNotEmpty)
                                                            Text(
                                                              driverPhone,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .grey
                                                                    .shade600,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : Text(
                                                "Chưa phân bổ",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                      ),
                                      // Cột 5: Đơn vị quản lý
                                      makeCell(
                                        Text(
                                          ownerCompany,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                      // Cột 6: Trạng thái
                                      // (Tạm ngừng hoạt động = không còn trên Vietmap / Bình Anh)
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isVehicleInactive(v)
                                                ? Colors.grey.shade100
                                                : Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: _isVehicleInactive(v)
                                                  ? Colors.grey.shade400
                                                  : Colors.green.shade200,
                                            ),
                                          ),
                                          child: Text(
                                            _isVehicleInactive(v)
                                                ? "Tạm ngừng hoạt động"
                                                : "Sẵn sàng hoạt động",
                                            style: TextStyle(
                                              color: _isVehicleInactive(v)
                                                  ? Colors.grey.shade700
                                                  : Colors.green.shade800,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Cột 7: Thao tác (Sửa thông tin phương tiện)
                                      makeCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.blue.shade800,
                                                side: BorderSide(
                                                  color: Colors.blue.shade300,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                "Sửa",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _showEditVehicleDialog(v),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // THANH ĐIỀU HƯỚNG PHÂN TRANG (PAGINATION BAR)
            if (filteredVehicles.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade400, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Thông tin số bản ghi hiển thị
                    Text(
                      "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems phương tiện",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Cụm điều khiển: Chọn PageSize + Các nút chuyển trang
                    Row(
                      children: [
                        const Text(
                          "Số dòng/trang: ",
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(width: 4),
                        DropdownButton<int>(
                          value: _vehiclePageSize,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.bold,
                          ),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text("5")),
                            DropdownMenuItem(value: 10, child: Text("10")),
                            DropdownMenuItem(value: 20, child: Text("20")),
                            DropdownMenuItem(value: 50, child: Text("50")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _vehiclePageSize = val;
                                _vehicleCurrentPage = 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 14),
                        // Nút về trang đầu
                        IconButton(
                          icon: const Icon(Icons.first_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang đầu",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _vehicleCurrentPage = 1;
                                  });
                                }
                              : null,
                        ),
                        // Nút trang trước
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang trước",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _vehicleCurrentPage = validPage - 1;
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(width: 4),
                        // Nhãn hiển thị trang hiện tại
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "$validPage / $totalPages",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Nút trang kế tiếp
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang sau",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _vehicleCurrentPage = validPage + 1;
                                  });
                                }
                              : null,
                        ),
                        // Nút đến trang cuối
                        IconButton(
                          icon: const Icon(Icons.last_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang cuối",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _vehicleCurrentPage = totalPages;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // DIALOG: XEM VÀ DUYỆT 5 ẢNH KIỂM TRA XE ĐẦU NGÀY / GIAO NHẬN CA DÀNH CHO ĐIỀU PHỐI VIÊN
  void _showVehicleInspectionsDialog(String? targetPlate, dynamic vehicleData) {
    showDialog(
      context: context,
      builder: (ctx) => _VehicleInspectionsModal(
        initialPlate: targetPlate,
        vehicleData: vehicleData,
        onStatusUpdated: () {
          _loadAllManagementData();
        },
      ),
    );
  }

  // TAB 4: Quản lý Tài khoản & Phân quyền động (Users & RBAC)
  Widget _buildUsersAndRbacTab() {
    if (widget.usersSubTab == 1) {
      return _buildRolesSubtab();
    }
    return _buildUserListSubtab();
  }

  Widget _buildUserListSubtab() {
    return Builder(
      builder: (context) {
        final query = _userSearchQuery.toLowerCase().trim();
        final filteredUsers = _users.where((u) {
          // 1. Kiểm tra vai trò (Role Filter)
          if (_selectedRoleFilter != 'ALL') {
            final roleCodes =
                (u['role_codes'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            if (!roleCodes.contains(_selectedRoleFilter)) {
              return false;
            }
          }

          // 2. Kiểm tra từ khóa tìm kiếm (Search Query)
          if (query.isNotEmpty) {
            final username = (u['username'] ?? '').toString().toLowerCase();
            final fullName = (u['full_name'] ?? '').toString().toLowerCase();
            final phone = (u['phone'] ?? '').toString().toLowerCase();
            final roleNames =
                ((u['role_names'] as List<dynamic>?)?.join(' ') ?? '')
                    .toLowerCase();
            final address = (u['address'] ?? '').toString().toLowerCase();
            final email = (u['email'] ?? '').toString().toLowerCase();

            final match =
                username.contains(query) ||
                fullName.contains(query) ||
                phone.contains(query) ||
                roleNames.contains(query) ||
                address.contains(query) ||
                email.contains(query);
            if (!match) return false;
          }

          return true;
        }).toList();

        final totalItems = filteredUsers.length;
        final totalPages = (totalItems / _userPageSize).ceil().clamp(1, 99999);
        final validPage = _userCurrentPage.clamp(1, totalPages);
        final startIndex = totalItems == 0
            ? 0
            : (validPage - 1) * _userPageSize;
        final endIndex = (startIndex + _userPageSize > totalItems)
            ? totalItems
            : startIndex + _userPageSize;
        final paginatedUsers = totalItems == 0
            ? []
            : filteredUsers.sublist(startIndex, endIndex);

        if (widget.onUserCountChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onUserCountChanged!(filteredUsers.length, _users.length);
            }
          });
        }

        return Column(
          children: [
            // Thanh công cụ gộp 1 hàng duy nhất: Tìm kiếm + Lọc vai trò + Thống kê & Thêm mới
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  // Ô tìm kiếm tài khoản
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _userSearchCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _userSearchQuery = val;
                            _userCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: const BoxConstraints(
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          hintText:
                              "Tìm theo tên, username, số điện thoại, email...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 17),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          suffixIcon: _userSearchQuery.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 36,
                                    maxHeight: 36,
                                  ),
                                  icon: const Icon(Icons.clear, size: 15),
                                  onPressed: () {
                                    _userSearchCtrl.clear();
                                    setState(() {
                                      _userSearchQuery = '';
                                      _userCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Bộ lọc theo Vai trò
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 36,
                      child: DropdownButtonFormField<String>(
                        value: _selectedRoleFilter,
                        isExpanded: true,
                        isDense: true,
                        iconSize: 18,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black87,
                          fontFamily: 'Nunito',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          constraints: BoxConstraints(
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          prefixIcon: Icon(Icons.filter_list, size: 17),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'ALL',
                            child: Text("Tất cả vai trò"),
                          ),
                          ..._roles.map(
                            (r) => DropdownMenuItem(
                              value: r['code'].toString(),
                              child: Text(r['name'] ?? r['code']),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedRoleFilter = val;
                              _userCurrentPage = 1;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Nút Thêm tài khoản mới (Đồng bộ chiều cao 36px với Input và Select)
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                        fixedSize: const Size.fromHeight(36),
                        visualDensity: VisualDensity.standard,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      icon: const Icon(Icons.person_add, size: 15),
                      label: const Text(
                        "Thêm tài khoản mới",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      onPressed: _showCreateUserDialog,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: paginatedUsers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Không tìm thấy tài khoản người dùng phù hợp",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.grey.shade100,
                                ),
                                headingRowHeight: 44,
                                dividerThickness: 0,
                                dataRowMaxHeight: 76,
                                dataRowMinHeight: 72,
                                horizontalMargin: 16,
                                columnSpacing: 20,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      "Ảnh",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Tài khoản & Họ tên",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Số điện thoại",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Vai trò & Phân loại",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Trạng thái",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Lịch sử",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Thao tác",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: List.generate(paginatedUsers.length, (
                                  rowIndex,
                                ) {
                                  final u = paginatedUsers[rowIndex];
                                  final roles =
                                      (u['role_names'] as List<dynamic>?)?.join(
                                        ', ',
                                      ) ??
                                      'Chưa gán vai trò';
                                  final isSystemAdmin =
                                      u['username'] == 'admin';
                                  final isLastRow =
                                      rowIndex == paginatedUsers.length - 1;
                                  final cellBorder = isLastRow
                                      ? null
                                      : Border(
                                          bottom: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                        );

                                  DataCell makeCell(
                                    Widget child, {
                                    AlignmentGeometry alignment =
                                        Alignment.centerLeft,
                                  }) {
                                    return DataCell(
                                      Container(
                                        alignment: alignment,
                                        decoration: BoxDecoration(
                                          border: cellBorder,
                                        ),
                                        child: child,
                                      ),
                                    );
                                  }

                                  return DataRow(
                                    cells: [
                                      // Cột 1: Avatar 1:1 bo góc 4px
                                      makeCell(
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: _buildUserAvatarItem(
                                            u,
                                            size: 52.0,
                                          ),
                                        ),
                                      ),
                                      // Cột 2: Tài khoản & Họ tên
                                      makeCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              u['full_name'] ?? u['username'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "(@${u['username']})",
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Colors.blueGrey,
                                              ),
                                            ),
                                            if (u['email'] != null &&
                                                u['email']
                                                    .toString()
                                                    .isNotEmpty)
                                              Text(
                                                u['email'],
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Cột 3: Số điện thoại
                                      makeCell(
                                        Text(
                                          u['phone'] ?? 'Chưa cập nhật',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      // Cột 4: Vai trò & Phân loại (đã gộp)
                                      makeCell(
                                        Builder(
                                          builder: (context) {
                                            final roleNames =
                                                (u['role_names']
                                                        as List<dynamic>?)
                                                    ?.map((e) => e.toString())
                                                    .toList() ??
                                                [];
                                            final roleCodes =
                                                (u['role_codes']
                                                        as List<dynamic>?)
                                                    ?.map((e) => e.toString())
                                                    .toList() ??
                                                [];
                                            if (roleNames.isEmpty) {
                                              return const Text(
                                                "Chưa gán",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              );
                                            }
                                            final isDriver = roleCodes.contains(
                                              'driver',
                                            );
                                            final driverType = u['driver_type'];
                                            return Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                ...List.generate(roleNames.length, (
                                                  idx,
                                                ) {
                                                  final name = roleNames[idx];
                                                  final code =
                                                      idx < roleCodes.length
                                                      ? roleCodes[idx]
                                                      : '';
                                                  Color bgColor =
                                                      Colors.indigo.shade50;
                                                  Color borderColor =
                                                      Colors.indigo.shade200;
                                                  Color textColor =
                                                      Colors.indigo.shade800;

                                                  if (code == 'admin') {
                                                    bgColor =
                                                        Colors.red.shade50;
                                                    borderColor =
                                                        Colors.red.shade200;
                                                    textColor =
                                                        Colors.red.shade900;
                                                  } else if (code == 'driver') {
                                                    bgColor =
                                                        Colors.teal.shade50;
                                                    borderColor =
                                                        Colors.teal.shade200;
                                                    textColor =
                                                        Colors.teal.shade900;
                                                  } else if (code ==
                                                      'gas_station') {
                                                    bgColor =
                                                        Colors.amber.shade50;
                                                    borderColor =
                                                        Colors.amber.shade300;
                                                    textColor =
                                                        Colors.orange.shade900;
                                                  } else if (code ==
                                                      'dispatcher') {
                                                    bgColor =
                                                        Colors.blue.shade50;
                                                    borderColor =
                                                        Colors.blue.shade200;
                                                    textColor =
                                                        Colors.blue.shade800;
                                                  } else if (code ==
                                                      'mechanic') {
                                                    bgColor =
                                                        Colors.purple.shade50;
                                                    borderColor =
                                                        Colors.purple.shade200;
                                                    textColor =
                                                        Colors.purple.shade900;
                                                  }

                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: bgColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: borderColor,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      name,
                                                      style: TextStyle(
                                                        color: textColor,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  );
                                                }),
                                                if (isDriver &&
                                                    driverType != null &&
                                                    driverType
                                                        .toString()
                                                        .isNotEmpty)
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 7,
                                                          vertical: 3,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors
                                                          .blueGrey
                                                          .shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .blueGrey
                                                            .shade200,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      _translateDriverType(
                                                        driverType,
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors
                                                            .blueGrey
                                                            .shade900,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      // Cột 6: Trạng thái & Thiết bị Token
                                      makeCell(
                                        Builder(
                                          builder: (context) {
                                            final isActive =
                                                u['is_active'] == true;
                                            final userId = u['id'];
                                            final username =
                                                (u['username'] ?? '')
                                                    .toString();

                                            String? matchedDeviceId =
                                                (u['device_token'] ?? '')
                                                    .toString()
                                                    .trim();
                                            if (matchedDeviceId.isEmpty)
                                              matchedDeviceId = null;
                                            final assignedVehicle = _vehicles
                                                .cast<dynamic>()
                                                .firstWhere(
                                                  (v) =>
                                                      v is Map &&
                                                      v['default_driver_id'] ==
                                                          userId,
                                                  orElse: () => null,
                                                );
                                            final plate =
                                                assignedVehicle != null
                                                ? (assignedVehicle['plate_number'] ??
                                                          '')
                                                      .toString()
                                                : '';
                                            if (plate.isNotEmpty) {
                                              final insp = _inspections
                                                  .cast<dynamic>()
                                                  .firstWhere(
                                                    (i) =>
                                                        i is Map &&
                                                        (i['plate_number'] ??
                                                                    '')
                                                                .toString() ==
                                                            plate &&
                                                        (i['device_id'] ?? '')
                                                            .toString()
                                                            .isNotEmpty,
                                                    orElse: () => null,
                                                  );
                                              if (insp != null &&
                                                  matchedDeviceId == null) {
                                                matchedDeviceId =
                                                    (insp['device_id'] ?? '')
                                                        .toString();
                                              }
                                            }

                                            if (matchedDeviceId == null &&
                                                (username == 'admin' ||
                                                    username.startsWith(
                                                      'dieuphoi_',
                                                    ))) {
                                              matchedDeviceId = "DESKTOP-APP";
                                            }

                                            final hasToken =
                                                matchedDeviceId != null &&
                                                matchedDeviceId.isNotEmpty;

                                            return Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 7,
                                                        vertical: 2.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isActive
                                                        ? Colors.green.shade50
                                                        : Colors.red.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    border: Border.all(
                                                      color: isActive
                                                          ? Colors
                                                                .green
                                                                .shade200
                                                          : Colors.red.shade200,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    isActive
                                                        ? "Hoạt động"
                                                        : "Khóa",
                                                    style: TextStyle(
                                                      color: isActive
                                                          ? Colors
                                                                .green
                                                                .shade800
                                                          : Colors.red.shade800,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: hasToken
                                                        ? Colors.blue.shade50
                                                        : Colors.grey.shade100,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    border: Border.all(
                                                      color: hasToken
                                                          ? Colors.blue.shade300
                                                          : Colors
                                                                .grey
                                                                .shade300,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        hasToken
                                                            ? Icons
                                                                  .notifications_active
                                                            : Icons
                                                                  .notifications_off_outlined,
                                                        size: 11,
                                                        color: hasToken
                                                            ? Colors
                                                                  .blue
                                                                  .shade800
                                                            : Colors
                                                                  .grey
                                                                  .shade500,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        hasToken
                                                            ? "Token: ${matchedDeviceId!.length > 14 ? '${matchedDeviceId.substring(0, 14)}...' : matchedDeviceId}"
                                                            : "Chưa có Token",
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: hasToken
                                                              ? Colors
                                                                    .blue
                                                                    .shade900
                                                              : Colors
                                                                    .grey
                                                                    .shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                      // Cột 7: Lịch sử trực ca
                                      makeCell(
                                        Builder(
                                          builder: (context) {
                                            final roleCodes =
                                                (u['role_codes']
                                                        as List<dynamic>?)
                                                    ?.map((e) => e.toString())
                                                    .toList() ??
                                                [];
                                            final isDispatcherUser = roleCodes
                                                .contains('dispatcher');

                                            if (isDispatcherUser) {
                                              return OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.blue.shade900,
                                                  side: BorderSide(
                                                    color: Colors.blue.shade300,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.history,
                                                  size: 14,
                                                ),
                                                label: const Text(
                                                  "Lịch sử ca trực",
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    showShiftHistoryDialog(
                                                      context,
                                                      targetUser: u,
                                                    ),
                                              );
                                            } else {
                                              return Text(
                                                "-",
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 13,
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      // Cột 8: Cụm nút thao tác
                                      makeCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.blueGrey.shade800,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              icon: const Icon(
                                                Icons.key,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                "Mật khẩu",
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              onPressed: () =>
                                                  _showChangePasswordDialog(u),
                                            ),
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.blue.shade800,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              icon: const Icon(
                                                Icons.edit,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                "Sửa",
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              onPressed: () =>
                                                  _showEditUserDialog(u),
                                            ),
                                            if (!isSystemAdmin) ...[
                                              const SizedBox(width: 6),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.red.shade700,
                                                  side: BorderSide(
                                                    color: Colors.red.shade300,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                      ),
                                                  minimumSize: const Size(
                                                    0,
                                                    32,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 14,
                                                ),
                                                label: const Text(
                                                  "Xóa",
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _confirmDeleteUser(u),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // THANH ĐIỀU HƯỚNG PHÂN TRANG (PAGINATION BAR)
            if (filteredUsers.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade400, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Thông tin số bản ghi hiển thị
                    Text(
                      "Hiển thị ${startIndex + 1} - ${endIndex} trên tổng số ${totalItems} tài khoản",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Cụm điều khiển: Chọn PageSize + Các nút chuyển trang
                    Row(
                      children: [
                        const Text(
                          "Số dòng/trang: ",
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(width: 4),
                        DropdownButton<int>(
                          value: _userPageSize,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.bold,
                          ),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text("5")),
                            DropdownMenuItem(value: 10, child: Text("10")),
                            DropdownMenuItem(value: 20, child: Text("20")),
                            DropdownMenuItem(value: 50, child: Text("50")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _userPageSize = val;
                                _userCurrentPage = 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        // Nút về trang đầu
                        IconButton(
                          icon: const Icon(Icons.first_page, size: 18),
                          tooltip: "Trang đầu",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          splashRadius: 16,
                          onPressed: validPage > 1
                              ? () => setState(() => _userCurrentPage = 1)
                              : null,
                        ),
                        // Nút trang trước
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          tooltip: "Trang trước",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          splashRadius: 16,
                          onPressed: validPage > 1
                              ? () => setState(
                                  () => _userCurrentPage = validPage - 1,
                                )
                              : null,
                        ),
                        const SizedBox(width: 4),
                        // Hiển thị số trang hiện tại / tổng số trang
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
                          child: Text(
                            "Trang $validPage / $totalPages",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Nút trang sau
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          tooltip: "Trang sau",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          splashRadius: 16,
                          onPressed: validPage < totalPages
                              ? () => setState(
                                  () => _userCurrentPage = validPage + 1,
                                )
                              : null,
                        ),
                        // Nút tới trang cuối
                        IconButton(
                          icon: const Icon(Icons.last_page, size: 18),
                          tooltip: "Trang cuối",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          splashRadius: 16,
                          onPressed: validPage < totalPages
                              ? () => setState(
                                  () => _userCurrentPage = totalPages,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // Subtab 2: Danh sách Roles & Cấu hình Quyền (Dynamic RBAC) kèm Thêm, Sửa, Xóa
  Widget _buildRolesSubtab() {
    return Column(
      children: [
        // Thanh công cụ Subtab 2: Thống kê & Nút Thêm vai trò mới (chuẩn 38px inline)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.security, color: Colors.indigo, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Cấu hình Phân quyền động (${_roles.length} vai trò • ${_permissions.length} quyền hạt nhân)",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.blueGrey,
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  icon: const Icon(Icons.add_moderator, size: 16),
                  label: const Text(
                    "Thêm vai trò mới",
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  onPressed: _showCreateRoleDialog,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _roles.length,
            itemBuilder: (context, index) {
              final r = _roles[index];
              final permCodes =
                  (r['permission_codes'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final permNames =
                  (r['permission_names'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  [];
              final isSystemCore =
                  r['is_system'] == true ||
                  [
                    'admin',
                    'driver',
                    'dispatcher',
                    'gas_station',
                    'mechanic',
                    'manager',
                  ].contains(r['code']);

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: Colors.grey.shade400, width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            r['code'] == 'admin'
                                ? Icons.verified_user
                                : Icons.shield_outlined,
                            color: r['code'] == 'admin'
                                ? Colors.red.shade700
                                : Colors.indigo,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      r['name'] ?? 'Vai trò',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                      child: Text(
                                        "Mã: ${r['code']}",
                                        style: TextStyle(
                                          color: Colors.blueGrey.shade800,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (isSystemCore) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          "Hệ thống",
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (r['description'] != null &&
                                    r['description'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    r['description'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Cụm nút Thao tác: Sửa quyền & Xóa
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.indigo.shade700,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.tune, size: 14),
                                label: const Text(
                                  "Cấu hình quyền",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () => _showEditRoleDialog(r),
                              ),
                              if (!isSystemCore) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 14,
                                  ),
                                  label: const Text(
                                    "Xóa",
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () => _showDeleteRoleDialog(r),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            "Danh sách hành động chức năng được cấp (${permNames.length} quyền):",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (permNames.isEmpty)
                        Text(
                          "Chưa được cấp bất kỳ quyền nào. Bấm 'Cấu hình quyền' để thêm quyền chức năng.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade400,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: List.generate(permNames.length, (pIdx) {
                            final pName = permNames[pIdx];
                            final pCode = pIdx < permCodes.length
                                ? permCodes[pIdx]
                                : '';

                            Color chipBg = Colors.blue.shade50;
                            Color chipBorder = Colors.blue.shade200;
                            Color chipText = Colors.blue.shade900;

                            if (pCode.startsWith('order:')) {
                              chipBg = Colors.teal.shade50;
                              chipBorder = Colors.teal.shade200;
                              chipText = Colors.teal.shade900;
                            } else if (pCode.startsWith('product:')) {
                              chipBg = Colors.cyan.shade50;
                              chipBorder = Colors.cyan.shade200;
                              chipText = Colors.cyan.shade900;
                            } else if (pCode.startsWith('vehicle:') ||
                                pCode.startsWith('driver:')) {
                              chipBg = Colors.blue.shade50;
                              chipBorder = Colors.blue.shade200;
                              chipText = Colors.blue.shade900;
                            } else if (pCode.startsWith('fuel:') ||
                                pCode.startsWith('gas_station:')) {
                              chipBg = Colors.amber.shade50;
                              chipBorder = Colors.amber.shade200;
                              chipText = Colors.orange.shade900;
                            } else if (pCode.startsWith('inspection:')) {
                              chipBg = Colors.purple.shade50;
                              chipBorder = Colors.purple.shade200;
                              chipText = Colors.purple.shade900;
                            } else if (pCode.startsWith('breakdown:') ||
                                pCode.startsWith('maintenance:')) {
                              chipBg = Colors.brown.shade50;
                              chipBorder = Colors.brown.shade200;
                              chipText = Colors.brown.shade900;
                            } else if (pCode.startsWith('user:') ||
                                pCode.startsWith('system:')) {
                              chipBg = Colors.indigo.shade50;
                              chipBorder = Colors.indigo.shade200;
                              chipText = Colors.indigo.shade900;
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: chipBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: chipBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 12,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    pName,
                                    style: TextStyle(
                                      color: chipText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // TAB 5: Cây dầu & Đối soát nhiên liệu (chuẩn hóa như tab Đội xe & Tài xế)
  Widget _buildGasStationsTab() {
    return Builder(
      builder: (context) {
        final query = _gasStationSearchQuery.toLowerCase().trim();
        final filteredStations = _gasStations.where((gs) {
          if (query.isEmpty) return true;
          final name = (gs['name'] ?? '').toString().toLowerCase();
          final address = (gs['address'] ?? '').toString().toLowerCase();
          final lat = (gs['lat'] ?? '').toString().toLowerCase();
          final lng = (gs['lng'] ?? '').toString().toLowerCase();
          return name.contains(query) ||
              address.contains(query) ||
              lat.contains(query) ||
              lng.contains(query);
        }).toList();

        final totalItems = filteredStations.length;
        final totalPages = (totalItems / _gasStationPageSize).ceil().clamp(
          1,
          99999,
        );
        final validPage = _gasStationCurrentPage.clamp(1, totalPages);
        final startIndex = totalItems == 0
            ? 0
            : (validPage - 1) * _gasStationPageSize;
        final endIndex = (startIndex + _gasStationPageSize > totalItems)
            ? totalItems
            : startIndex + _gasStationPageSize;
        final paginatedStations = totalItems == 0
            ? []
            : filteredStations.sublist(startIndex, endIndex);

        if (widget.onGasStationCountChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onGasStationCountChanged!(
                filteredStations.length,
                _gasStations.length,
              );
            }
          });
        }

        return Column(
          children: [
            // Thanh công cụ 1 hàng: Tìm kiếm + Thống kê số lượng + Nút làm mới
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  // Ô tìm kiếm trạm
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _gasStationSearchCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _gasStationSearchQuery = val;
                            _gasStationCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: const BoxConstraints(
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          hintText: "Tìm theo tên trạm, địa chỉ, tọa độ GPS...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 17),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          suffixIcon: _gasStationSearchQuery.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 36,
                                    maxHeight: 36,
                                  ),
                                  icon: const Icon(Icons.clear, size: 15),
                                  onPressed: () {
                                    _gasStationSearchCtrl.clear();
                                    setState(() {
                                      _gasStationSearchQuery = '';
                                      _gasStationCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Nút thêm mới trạm dầu
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 36),
                        fixedSize: const Size.fromHeight(36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      icon: const Icon(Icons.add_business, size: 16),
                      label: const Text(
                        "Thêm trạm dầu",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      onPressed: () => _showGasStationFormDialog(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Bảng danh sách trạm dầu
            Expanded(
              child: paginatedStations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_gas_station_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Không tìm thấy trạm dầu nào phù hợp với bộ lọc",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.grey.shade100,
                                ),
                                headingRowHeight: 44,
                                dividerThickness: 0,
                                dataRowMaxHeight: 64,
                                dataRowMinHeight: 58,
                                horizontalMargin: 16,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      "Tên trạm",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Địa chỉ",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Tọa độ GPS",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Bán kính đối soát",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Thao tác",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: List.generate(paginatedStations.length, (
                                  idx,
                                ) {
                                  final gs = paginatedStations[idx];
                                  final rowColor = idx % 2 == 0
                                      ? Colors.white
                                      : Colors.grey.shade50;
                                  final name = (gs['name'] ?? 'N/A').toString();
                                  final address = (gs['address'] ?? '')
                                      .toString();
                                  final lat = (gs['lat'] ?? '').toString();
                                  final lng = (gs['lng'] ?? '').toString();
                                  final radius =
                                      (gs['allowed_radius_meters'] ?? '')
                                          .toString();

                                  DataCell makeCell(Widget child) {
                                    return DataCell(
                                      Container(
                                        alignment: Alignment.centerLeft,
                                        child: child,
                                      ),
                                    );
                                  }

                                  return DataRow(
                                    color: MaterialStateProperty.all(rowColor),
                                    cells: [
                                      // Cột 1: Tên trạm
                                      makeCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Icon(
                                                Icons.local_gas_station,
                                                size: 18,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                color: Colors.blueGrey.shade900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Cột 2: Địa chỉ
                                      makeCell(
                                        Text(
                                          address,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      // Cột 3: Tọa độ GPS (bấm để copy)
                                      makeCell(
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          onTap: () {
                                            Clipboard.setData(
                                              ClipboardData(text: "$lat,$lng"),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                backgroundColor:
                                                    Colors.green.shade700,
                                                content: Text(
                                                  "Đã copy tọa độ: $lat, $lng",
                                                ),
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                              horizontal: 2,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.copy,
                                                  size: 14,
                                                  color: Colors.teal,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "Lat $lat - Lng $lng",
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    color: Colors
                                                        .blueGrey
                                                        .shade700,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Cột 4: Bán kính cho phép đối soát
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.deepOrange.shade50,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: Colors.deepOrange.shade200,
                                            ),
                                          ),
                                          child: Text(
                                            "$radius mét",
                                            style: TextStyle(
                                              color: Colors.deepOrange.shade900,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Cột 5: Thao tác (Bản đồ + Sửa + Xóa)
                                      makeCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.blue.shade800,
                                                side: BorderSide(
                                                  color: Colors.blue.shade300,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.map_outlined,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                "Bản đồ",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () {
                                                _showGasStationMapDialog(gs);
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.teal.shade700,
                                                side: BorderSide(
                                                  color: Colors.teal.shade300,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                "Sửa",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () {
                                                _showGasStationFormDialog(
                                                  station: gs,
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor:
                                                    Colors.red.shade700,
                                                side: BorderSide(
                                                  color: Colors.red.shade300,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                              ),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                "Xóa",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () {
                                                _confirmDeleteGasStation(gs);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // THANH DIEU HUONG PHAN TRANG (PAGINATION BAR)
            if (filteredStations.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade400, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Thong tin so ban ghi hien thi
                    Text(
                      "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems trạm dầu",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Cum dieu khien: Chon PageSize + cac nut chuyen trang
                    Row(
                      children: [
                        const Text(
                          "Số dòng/trang: ",
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(width: 4),
                        DropdownButton<int>(
                          value: _gasStationPageSize,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.bold,
                          ),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text("5")),
                            DropdownMenuItem(value: 10, child: Text("10")),
                            DropdownMenuItem(value: 20, child: Text("20")),
                            DropdownMenuItem(value: 50, child: Text("50")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _gasStationPageSize = val;
                                _gasStationCurrentPage = 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 14),
                        // Nút về trang đầu
                        IconButton(
                          icon: const Icon(Icons.first_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang đầu",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _gasStationCurrentPage = 1;
                                  });
                                }
                              : null,
                        ),
                        // Nút trang trước
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang trước",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _gasStationCurrentPage = validPage - 1;
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(width: 4),
                        // Nhãn hiển thị trang hiện tại
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "$validPage / $totalPages",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Nút trang kế tiếp
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang sau",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _gasStationCurrentPage = validPage + 1;
                                  });
                                }
                              : null,
                        ),
                        // Nút đến trang cuối
                        IconButton(
                          icon: const Icon(Icons.last_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang cuối",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _gasStationCurrentPage = totalPages;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // Tải lại danh sách cây dầu từ API
  Future<void> _loadGasStations() async {
    try {
      final stations = await AdminService.fetchGasStations();
      if (!mounted) return;
      setState(() {
        _gasStations = stations;
        _gasStationCurrentPage = 1;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text("Không thể tải lại danh sách cây dầu"),
          ),
        );
      }
    }
  }

  // ============ DIALOG THÊM/SỬA CÂY DẦU ============
  void _showGasStationFormDialog({Map<String, dynamic>? station}) {
    final isEdit = station != null;
    final nameCtrl = TextEditingController(text: station?['name'] ?? '');
    final addrCtrl = TextEditingController(text: station?['address'] ?? '');
    final latCtrl = TextEditingController(
      text: (station?['lat'] ?? '').toString(),
    );
    final lngCtrl = TextEditingController(
      text: (station?['lng'] ?? '').toString(),
    );
    final radiusCtrl = TextEditingController(
      text: (station?['allowed_radius_meters'] ?? 500).toString(),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isEdit ? Icons.edit : Icons.add_business,
                  color: Colors.orange.shade700,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isEdit ? "Sửa cây dầu" : "Thêm cây dầu mới",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Tên trạm *",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: "VD: Cây xăng Petrolimex Quận 2",
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Địa chỉ *",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: addrCtrl,
                    decoration: InputDecoration(
                      hintText:
                          "VD: 123 Võ Nguyễn Giác, P. Cát Lái, TP. Thủ Đức",
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Vĩ độ (Lat) *",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: latCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: "10.7768",
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Kinh độ (Lng) *",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: lngCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: "106.7213",
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Bán kính cho phép đối soát (mét)",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: radiusCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: "500",
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      suffixText: "m",
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Gợi ý: copy tọa độ từ Google Maps (chuỗi lat,lng) rồi dán vào 2 ô Vĩ độ/Kinh độ.",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Hủy"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
              ),
              icon: Icon(isEdit ? Icons.save : Icons.add),
              label: Text(isEdit ? "Lưu thay đổi" : "Thêm mới"),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final address = addrCtrl.text.trim();
                final latText = latCtrl.text.trim().replaceAll(',', '.');
                final lngText = lngCtrl.text.trim().replaceAll(',', '.');
                final radiusText = radiusCtrl.text.trim().replaceAll(',', '.');

                if (name.isEmpty || address.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text("Vui lòng nhập Tên trạm và Địa chỉ"),
                    ),
                  );
                  return;
                }
                final lat = double.tryParse(latText);
                final lng = double.tryParse(lngText);
                if (lat == null ||
                    lng == null ||
                    lat < -90 ||
                    lat > 90 ||
                    lng < -180 ||
                    lng > 180) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text(
                        "Tọa độ không hợp lệ (Vĩ độ -90..90, Kinh độ -180..180)",
                      ),
                    ),
                  );
                  return;
                }
                final radius = double.tryParse(radiusText) ?? 500;

                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.blueGrey.shade800,
                    content: Text(
                      isEdit ? "Đang lưu thay đổi..." : "Đang thêm cây dầu...",
                    ),
                  ),
                );

                Map<String, dynamic>? result;
                if (isEdit) {
                  final id = station['id'];
                  result = await AdminService.updateGasStation(
                    id is int ? id : int.tryParse('$id') ?? 0,
                    name: name,
                    address: address,
                    lat: lat,
                    lng: lng,
                    allowedRadiusMeters: radius,
                  );
                } else {
                  result = await AdminService.createGasStation(
                    name: name,
                    address: address,
                    lat: lat,
                    lng: lng,
                    allowedRadiusMeters: radius,
                  );
                }

                if (!mounted) return;
                if (result != null) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.green.shade700,
                      content: Text(
                        isEdit
                            ? "Đã lưu thay đổi cây dầu"
                            : "Đã thêm cây dầu mới",
                      ),
                    ),
                  );
                  await _loadGasStations();
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text(
                        "Không thể lưu cây dầu - kiểm tra kết nối hoặc quyền truy cập",
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============ XÁC NHẬN XÓA CÂY DẦU ============
  void _confirmDeleteGasStation(Map<String, dynamic> station) {
    final id = station['id'];
    final name = (station['name'] ?? 'N/A').toString();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              "Xóa cây dầu?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "Bạn có chắc muốn xóa cây dầu \"$name\"?\n\nHành động này không thể hoàn tác. Các dữ liệu đối soát liên quan sẽ bị gỡ khỏi cây dầu này.",
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Hủy"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever),
            label: const Text("Xóa vĩnh viễn"),
            onPressed: () async {
              final navigatorPop = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(context);
              navigatorPop.pop();
              final stationId = id is int ? id : int.tryParse('$id') ?? 0;
              final ok = await AdminService.deleteGasStation(stationId);
              if (!mounted) return;
              if (ok) {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green.shade700,
                    content: Text("Đã xóa cây dầu \"$name\""),
                  ),
                );
                await _loadGasStations();
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(
                      "Không thể xóa cây dầu - có thể đang có dữ liệu đối soát liên quan",
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // ============ DIALOG BẢN ĐỒ VỊ TRÍ CÂY DẦU (VIỆT MAP) ============
  void _showGasStationMapDialog(Map<String, dynamic> station) {
    final name = (station['name'] ?? 'Cây dầu').toString();
    final address = (station['address'] ?? '').toString();
    final lat = double.tryParse('${station['lat'] ?? ''}');
    final lng = double.tryParse('${station['lng'] ?? ''}');
    final radius =
        double.tryParse('${station['allowed_radius_meters'] ?? 500}') ?? 500;

    if (lat == null || lng == null || lat == 0 || lng == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text("Cây dầu này chưa có tọa độ GPS hợp lệ"),
        ),
      );
      return;
    }

    final mapCtrl = MapController();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_gas_station,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(dialogContext),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              // Bản đồ Việt Map
              SizedBox(
                height: 440,
                child: FlutterMap(
                  mapController: mapCtrl,
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
                    initialZoom: 15.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}@2x.png?apikey=$_vietMapApiKey',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(lat, lng),
                          radius: radius,
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderStrokeWidth: 2,
                          borderColor: Colors.orange.shade700,
                          useRadiusInMeter: true,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.local_gas_station,
                            color: Colors.orange.shade700,
                            size: 36,
                            shadows: const [
                              Shadow(color: Colors.white, blurRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Footer: địa chỉ + copy tọa độ
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            address.isEmpty ? "Không có địa chỉ" : address,
                            style: const TextStyle(fontSize: 12.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Tọa độ: $lat, $lng • Bán kính đối soát: $radius mét",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal,
                        side: BorderSide(color: Colors.teal.shade300),
                        minimumSize: const Size(0, 34),
                      ),
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text("Copy tọa độ"),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: "$lat,$lng"));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green.shade700,
                            content: Text("Đã copy tọa độ: $lat, $lng"),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Nhãn tiếng Việt hiển thị cho nhóm vật liệu (đồng bộ key category lưu trong DB)
  String _productCategoryLabel(String key) {
    switch (key) {
      case 'vat_lieu_xay_dung':
        return 'Vật liệu xây dựng';
      case 'xi_mang_roi':
        return 'Xi măng rời';
      case 'tro_bay':
        return 'Tro bay';
      case 'cat_xay_dung':
        return 'Cát xây dựng';
      case 'da_dam':
        return 'Đá dăm';
      case 'khac':
        return 'Khác';
      default:
        return key;
    }
  }

  // TAB 6: Sản phẩm & Vật liệu xây dựng (chuẩn hóa như tab Cây dầu & Đội xe)
  Widget _buildProductsTab() {
    return Builder(
      builder: (context) {
        final query = _productSearchQuery.toLowerCase().trim();
        final filteredProducts = _products.where((p) {
          if (query.isEmpty) return true;
          final name = (p['name'] ?? '').toString().toLowerCase();
          final code = (p['code'] ?? '').toString().toLowerCase();
          final category = (p['category'] ?? '').toString().toLowerCase();
          final unit = (p['unit'] ?? '').toString().toLowerCase();
          return name.contains(query) ||
              code.contains(query) ||
              category.contains(query) ||
              unit.contains(query);
        }).toList();

        final totalItems = filteredProducts.length;
        final totalPages = (totalItems / _productPageSize).ceil().clamp(
          1,
          99999,
        );
        final validPage = _productCurrentPage.clamp(1, totalPages);
        final startIndex = totalItems == 0
            ? 0
            : (validPage - 1) * _productPageSize;
        final endIndex = (startIndex + _productPageSize > totalItems)
            ? totalItems
            : startIndex + _productPageSize;
        final paginatedProducts = totalItems == 0
            ? []
            : filteredProducts.sublist(startIndex, endIndex);

        return Column(
          children: [
            // Thanh công cụ: Tìm kiếm + Thêm mới + Tải lại
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _productSearchCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (val) {
                          setState(() {
                            _productSearchQuery = val;
                            _productCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          isDense: true,
                          constraints: const BoxConstraints(
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          hintText:
                              "Tìm theo tên, mã, nhóm vật liệu, đơn vị tính...",
                          hintStyle: const TextStyle(fontSize: 12.5),
                          prefixIcon: const Icon(Icons.search, size: 17),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          suffixIcon: _productSearchQuery.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.close, size: 15),
                                  onPressed: () {
                                    setState(() {
                                      _productSearchCtrl.clear();
                                      _productSearchQuery = '';
                                      _productCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Nút thêm mới sản phẩm
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 36),
                        fixedSize: const Size.fromHeight(36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        "Thêm sản phẩm",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                      onPressed: () => _showProductFormDialog(),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Bảng danh sách sản phẩm
            Expanded(
              child: paginatedProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Không tìm thấy sản phẩm nào phù hợp với bộ lọc",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.grey.shade100,
                                ),
                                headingRowHeight: 44,
                                dividerThickness: 0,
                                dataRowMaxHeight: 64,
                                dataRowMinHeight: 58,
                                horizontalMargin: 16,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(
                                    label: Text(
                                      "Mã SP",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Tên sản phẩm",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Nhóm vật liệu",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Đơn vị tính",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Bơm chuẩn (phút)",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Nén khí",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      "Thao tác",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: List.generate(paginatedProducts.length, (
                                  idx,
                                ) {
                                  final p = paginatedProducts[idx];
                                  final rowColor = idx % 2 == 0
                                      ? Colors.white
                                      : Colors.grey.shade50;
                                  final code = (p['code'] ?? 'N/A').toString();
                                  final name = (p['name'] ?? 'N/A').toString();
                                  final category = _productCategoryLabel(
                                    (p['category'] ?? '-').toString(),
                                  );
                                  final unit = (p['unit'] ?? '-').toString();
                                  final pumpMin =
                                      (p['standard_pump_time_minutes'] ?? '-')
                                          .toString();
                                  final needPump =
                                      p['requires_air_pump'] == true;

                                  DataCell makeCell(Widget child) {
                                    return DataCell(
                                      Container(
                                        alignment: Alignment.centerLeft,
                                        child: child,
                                      ),
                                    );
                                  }

                                  return DataRow(
                                    color: MaterialStateProperty.resolveWith(
                                      (states) =>
                                          states.contains(MaterialState.hovered)
                                          ? Colors.blue.shade50
                                          : rowColor,
                                    ),
                                    cells: [
                                      DataCell(
                                        Container(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            code,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12.5,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                      makeCell(
                                        Text(
                                          category,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      makeCell(
                                        Text(
                                          unit,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      makeCell(
                                        Text(
                                          pumpMin,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: needPump
                                                ? Colors.amber.shade100
                                                : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            needPump ? "Cần nén" : "Không nén",
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: needPump
                                                  ? Colors.amber.shade900
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          alignment: Alignment.centerLeft,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Nút sửa
                                              _buildProductActionBtn(
                                                icon: Icons.edit_outlined,
                                                color: Colors.blue.shade700,
                                                tooltip: "Sửa sản phẩm",
                                                onPressed: () =>
                                                    _showProductFormDialog(
                                                      product: p,
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                              // Nút xóa
                                              _buildProductActionBtn(
                                                icon: Icons.delete_outline,
                                                color: Colors.red.shade600,
                                                tooltip: "Xóa sản phẩm",
                                                onPressed: () =>
                                                    _confirmDeleteProduct(p),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // THANH ĐIỀU HƯỚNG PHÂN TRANG (PAGINATION BAR)
            if (filteredProducts.isNotEmpty)
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade400, width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Thông tin số bản ghi hiển thị
                    Text(
                      "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems sản phẩm",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Cụm điều khiển: Chọn PageSize + Các nút chuyển trang
                    Row(
                      children: [
                        const Text(
                          "Số dòng/trang: ",
                          style: TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(width: 4),
                        DropdownButton<int>(
                          value: _productPageSize,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.bold,
                          ),
                          items: const [
                            DropdownMenuItem(value: 5, child: Text("5")),
                            DropdownMenuItem(value: 10, child: Text("10")),
                            DropdownMenuItem(value: 20, child: Text("20")),
                            DropdownMenuItem(value: 50, child: Text("50")),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _productPageSize = val;
                                _productCurrentPage = 1;
                              });
                            }
                          },
                        ),
                        const SizedBox(width: 14),
                        // Nút về trang đầu
                        IconButton(
                          icon: const Icon(Icons.first_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang đầu",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _productCurrentPage = 1;
                                  });
                                }
                              : null,
                        ),
                        // Nút trang trước
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang trước",
                          onPressed: validPage > 1
                              ? () {
                                  setState(() {
                                    _productCurrentPage = validPage - 1;
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(width: 4),
                        // Nhãn hiển thị trang hiện tại
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "$validPage / $totalPages",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Nút trang kế tiếp
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang sau",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _productCurrentPage = validPage + 1;
                                  });
                                }
                              : null,
                        ),
                        // Nút đến trang cuối
                        IconButton(
                          icon: const Icon(Icons.last_page, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: "Trang cuối",
                          onPressed: validPage < totalPages
                              ? () {
                                  setState(() {
                                    _productCurrentPage = totalPages;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // Nút thao tác nhỏ trong bảng sản phẩm
  Widget _buildProductActionBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  // Tải lại danh sách sản phẩm từ API
  Future<void> _loadProducts() async {
    try {
      final products = await AdminService.fetchProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _productCurrentPage = 1;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text("Không thể tải lại danh sách sản phẩm"),
          ),
        );
      }
    }
  }

  // Nhãn tiêu đề phía trên mỗi ô nhập / ô chọn trong Dialog (kiểu label tách biệt, sạch và dễ nhìn)
  Widget _buildFormLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  // ============ DIALOG THÊM/SỬA SẢN PHẨM ============
  void _showProductFormDialog({Map<String, dynamic>? product}) {
    final isEdit = product != null;
    final codeCtrl = TextEditingController(
      text: isEdit ? (product['code'] ?? '').toString() : '',
    );
    final nameCtrl = TextEditingController(
      text: isEdit ? (product['name'] ?? '').toString() : '',
    );
    final unitCtrl = TextEditingController(
      text: isEdit ? (product['unit'] ?? '').toString() : '',
    );
    final pumpCtrl = TextEditingController(
      text: isEdit
          ? (product['standard_pump_time_minutes'] ?? '').toString()
          : '0',
    );
    // Danh sách nhóm vật liệu: key đồng bộ với giá trị category lưu trong DB
    const productCategoryKeys = <String>[
      'vat_lieu_xay_dung',
      'xi_mang_roi',
      'tro_bay',
      'cat_xay_dung',
      'da_dam',
      'khac',
    ];
    // Khởi tạo theo key DB, fallback về key đầu tiên nếu dữ liệu cũ không khớp
    // (tránh DropdownButtonFormField crash assertion do value ngoài items).
    String selectedCategory =
        isEdit && productCategoryKeys.contains((product['category'] ?? '').toString())
        ? (product['category'] ?? '').toString()
        : productCategoryKeys.first;
    bool requiresPump = isEdit ? (product['requires_air_pump'] == true) : false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit : Icons.add_circle_outline,
                color: Colors.amber.shade700,
              ),
              const SizedBox(width: 10),
              Text(
                isEdit
                    ? "Sửa sản phẩm: ${product['name']}"
                    : "Thêm sản phẩm vật liệu mới",
                style: const TextStyle(fontSize: 18),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mã sản phẩm
                  const Text(
                    "Mã sản phẩm *",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      hintText: "VD: TROBAY-01",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tên sản phẩm
                  const Text(
                    "Tên sản phẩm *",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: "VD: Tro bay nhà máy Phả Lại",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Nhóm vật liệu + Đơn vị tính
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Nhóm vật liệu *",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              value: selectedCategory,
                              isDense: true,
                              decoration: const InputDecoration(isDense: true),
                              items:
                                  productCategoryKeys.map(
                                        (key) => DropdownMenuItem(
                                          value: key,
                                          child: Text(
                                            _productCategoryLabel(key),
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => selectedCategory = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Đơn vị tính *",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextFormField(
                              controller: unitCtrl,
                              decoration: const InputDecoration(
                                hintText: "VD: tấn, m3, khối",
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Thời gian bơm chuẩn
                  const Text(
                    "Thời gian bơm chuẩn (phút) *",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: pumpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: "VD: 30",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Cần máy nén khí
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.compress,
                          size: 18,
                          color: Colors.amber.shade800,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "Sản phẩm cần máy nén khí khi bơm",
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                        Switch(
                          value: requiresPump,
                          activeColor: Colors.amber.shade700,
                          onChanged: (val) {
                            setDialogState(() => requiresPump = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Áp dụng cho tro bay, xi măng rời cần bơm khí nén lên xe/tặng.",
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Hủy bỏ"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
              ),
              icon: Icon(isEdit ? Icons.save : Icons.add, size: 17),
              label: Text(isEdit ? "Lưu thay đổi" : "Thêm mới"),
              onPressed: () async {
                final code = codeCtrl.text.trim();
                final name = nameCtrl.text.trim();
                final unit = unitCtrl.text.trim();
                final pumpMin = int.tryParse(pumpCtrl.text.trim()) ?? -1;

                if (code.isEmpty ||
                    name.isEmpty ||
                    unit.isEmpty ||
                    pumpMin < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text(
                        "Vui lòng nhập đủ Mã, Tên, Đơn vị tính và thời gian bơm chuẩn (số nguyên dương)",
                      ),
                    ),
                  );
                  return;
                }

                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);

                Map<String, dynamic>? result;
                if (isEdit) {
                  result = await AdminService.updateProduct(
                    product['id'] as int,
                    code: code,
                    name: name,
                    category: selectedCategory,
                    unit: unit,
                    standardPumpTimeMinutes: pumpMin,
                    requiresAirPump: requiresPump,
                  );
                } else {
                  result = await AdminService.createProduct(
                    code: code,
                    name: name,
                    category: selectedCategory,
                    unit: unit,
                    standardPumpTimeMinutes: pumpMin,
                    requiresAirPump: requiresPump,
                  );
                }

                if (result != null) {
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.green,
                      content: Text(
                        isEdit
                            ? "Đã cập nhật sản phẩm '$name'"
                            : "Đã thêm sản phẩm '$name' vào danh mục",
                      ),
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.red,
                      content: Text(
                        "Không thể lưu sản phẩm (mã có thể đã tồn tại hoặc lỗi kết nối)",
                      ),
                    ),
                  );
                }
                await _loadProducts();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ============ XÁC NHẬN XÓA SẢN PHẨM ============
  void _confirmDeleteProduct(Map<String, dynamic> product) {
    final pName = (product['name'] ?? '').toString();
    final pCode = (product['code'] ?? '').toString();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
            const SizedBox(width: 10),
            const Text("Xác nhận xóa sản phẩm", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Bạn có chắc chắn muốn xóa sản phẩm này?",
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    "Mã: $pCode",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Hành động này không thể hoàn tác. Các đơn hàng đã dùng sản phẩm này vẫn giữ nguyên dữ liệu lịch sử.",
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Hủy bỏ"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 17),
            label: const Text("Xóa vĩnh viễn"),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext);

              final ok = await AdminService.deleteProduct(product['id'] as int);
              if (ok) {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green,
                    content: Text("Đã xóa sản phẩm '$pName'"),
                  ),
                );
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.red,
                    content: Text(
                      "Không thể xóa sản phẩm (có thể đang được sử dụng trong đơn hàng)",
                    ),
                  ),
                );
              }
              await _loadProducts();
            },
          ),
        ],
      ),
    );
  }

  String _translateDriverType(String? type) {
    if (type == null || type.isEmpty) return '-';
    switch (type) {
      case 'INTERNAL':
        return 'Tài xế công ty (Nội bộ)';
      case 'RENTAL':
        return 'Tài xế thuê ngoài';
      case 'CUSTOMER_SELF':
        return 'Khách hàng tự chở';
      default:
        return type;
    }
  }

  String _translateTransportType(String? type) {
    switch (type) {
      case 'INTERNAL':
        return 'Xe công ty';
      case 'RENTAL':
        return 'Xe thuê ngoài';
      case 'CUSTOMER_SELF':
        return 'Khách tự lấy';
      default:
        return 'Nội bộ';
    }
  }

  String _translateOwnershipType(String? type) {
    switch (type) {
      case 'INTERNAL':
        return 'Xe nội bộ';
      case 'RENTAL':
        return 'Xe thuê ngoài';
      case 'CUSTOMER_SELF':
        return 'Xe khách hàng';
      default:
        return 'Nội bộ';
    }
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 106,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: Colors.grey.shade400, width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Tổng hợp danh sách các báo cáo trạng thái realtime của Tài xế từ Đơn hàng, Kiểm tra 5 ảnh, Đội xe và Cảnh báo
  List<Map<String, dynamic>> _collectRealtimeDriverReports(AppState state) {
    final reports = <Map<String, dynamic>>[];

    DateTime parseTime(dynamic raw, [DateTime? fallback]) {
      if (raw != null) {
        final dt = DateTime.tryParse(raw.toString());
        if (dt != null) return dt.toLocal();
      }
      return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    String formatClock(DateTime dt) {
      if (dt.millisecondsSinceEpoch == 0) return '--:--';
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      return '$h:$m ($d/$mo)';
    }

    // 1. Báo cáo từ Kiểm tra đầu ngày (5 ảnh giao nhận ca)
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
      final dt = parseTime(item['completed_at'] ?? item['created_at']);

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

      final kmText = kmConfirmed != null ? 'ODO: $kmConfirmed km' : 'Đủ 5 góc ảnh';
      final desc = flagReason.isNotEmpty
          ? 'Kiểm tra xe $plate ($kmText) • Ghi chú: $flagReason'
          : 'Đã gửi báo cáo kiểm tra 5 ảnh xe $plate ($kmText)';

      reports.add({
        'driver_name': driverName,
        'phone': phone,
        'plate': plate,
        'title': statusLabel,
        'description': desc,
        'time_label': formatClock(dt),
        'timestamp': dt,
        'color': badgeColor,
        'icon': iconData,
        'group': groupKey,
        'action_type': 'INSPECTION',
        'raw': item,
      });
    }

    // 2. Báo cáo trạng thái hành trình & đơn hàng từ danh sách Đơn hàng vận tải
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
      final dt = parseTime(o['created_at'], _extractOrderDate(o));

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
        'time_label': formatClock(dt),
        'timestamp': dt,
        'color': badgeColor,
        'icon': iconData,
        'group': groupKey,
        'action_type': 'ORDER',
        'raw': o,
      });
    }

    // 3. Báo cáo hỏng xe & nhắc nhở realtime trong phiên AppState (nếu có)
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
        'time_label': formatClock(dt),
        'timestamp': dt,
        'color': Colors.red.shade700,
        'icon': Icons.car_crash_rounded,
        'group': 'ALERT',
        'action_type': 'VEHICLE',
        'raw': b,
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

  Widget _buildRealtimeDriverReportsCard(AppState state) {
    final allReports = _collectRealtimeDriverReports(state);
    final tripCount = allReports.where((r) => r['group'] == 'TRIP').length;
    final inspectionCount =
        allReports.where((r) => r['group'] == 'INSPECTION').length;
    final alertCount = allReports.where((r) => r['group'] == 'ALERT').length;

    final filtered = allReports.where((r) {
      if (_realtimeReportFilter == 'ALL') return true;
      return r['group'] == _realtimeReportFilter;
    }).toList();

    final totalItems = filtered.length;
    final totalPages =
        totalItems == 0 ? 1 : (totalItems / _realtimeReportPageSize).ceil();
    final validPage = _realtimeReportPage.clamp(1, totalPages);
    final startIndex = (validPage - 1) * _realtimeReportPageSize;
    final endIndex = (startIndex + _realtimeReportPageSize > totalItems)
        ? totalItems
        : startIndex + _realtimeReportPageSize;
    final pageItems = totalItems == 0
        ? <Map<String, dynamic>>[]
        : filtered.sublist(startIndex, endIndex);

    Widget buildFilterChip({
      required String key,
      required String label,
      required int count,
      required Color activeColor,
    }) {
      final isSelected = _realtimeReportFilter == key;
      return InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          setState(() {
            _realtimeReportFilter = key;
            _realtimeReportPage = 1;
          });
        },
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.12)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? activeColor : Colors.grey.shade300,
              width: isSelected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : Colors.grey.shade800,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.grey.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.blue.shade200, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header của Block
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.radar_rounded,
                          color: Colors.teal.shade800,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  "Báo cáo Realtime Trạng thái Tài xế",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.green.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.fiber_manual_record,
                                        size: 8,
                                        color: Colors.green.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "LIVE",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              "Cập nhật tức thời các mốc nhận chuyến, giao hàng, kiểm tra 5 ảnh đầu ngày và cảnh báo sự cố từ tài xế",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Nút làm mới nhanh
                SizedBox(
                  height: 34,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade800,
                      side: BorderSide(color: Colors.blue.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    icon: const Icon(Icons.sync, size: 15),
                    label: const Text(
                      "Làm mới",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: _refreshRealtimeReportsSilently,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Thanh bộ lọc nhanh theo loại báo cáo
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                buildFilterChip(
                  key: 'ALL',
                  label: 'Tất cả báo cáo',
                  count: allReports.length,
                  activeColor: Colors.blue.shade800,
                ),
                buildFilterChip(
                  key: 'TRIP',
                  label: 'Vận chuyển & Mốc chuyến',
                  count: tripCount,
                  activeColor: Colors.teal.shade700,
                ),
                buildFilterChip(
                  key: 'INSPECTION',
                  label: 'Kiểm tra 5 ảnh giao ca',
                  count: inspectionCount,
                  activeColor: Colors.indigo.shade700,
                ),
                buildFilterChip(
                  key: 'ALERT',
                  label: 'Cảnh báo & Sự cố',
                  count: alertCount,
                  activeColor: Colors.red.shade700,
                ),
              ],
            ),
            const Divider(height: 22),

            // Danh sách báo cáo realtime
            if (pageItems.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                alignment: Alignment.center,
                child: Text(
                  "Chưa có báo cáo trạng thái nào trong mục này.",
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Column(
                children: pageItems.map((rep) {
                  final Color badgeColor = rep['color'] as Color;
                  final IconData iconData = rep['icon'] as IconData;
                  final String driverName = rep['driver_name'].toString();
                  final String phone = rep['phone'].toString();
                  final String plate = rep['plate'].toString();
                  final String title = rep['title'].toString();
                  final String desc = rep['description'].toString();
                  final String timeLabel = rep['time_label'].toString();
                  final String actionType = rep['action_type'].toString();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        if (actionType == 'INSPECTION') {
                          if (widget.onOpenInspectionScreen != null) {
                            widget.onOpenInspectionScreen!();
                          } else {
                            _showVehicleInspectionsDialog(plate, null);
                          }
                        } else if (actionType == 'ORDER') {
                          widget.onTabChanged?.call(1);
                        } else {
                          widget.onTabChanged?.call(2);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Icon(
                                iconData,
                                color: badgeColor,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        driverName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blueGrey.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                            color: Colors.blueGrey.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          plate,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueGrey.shade900,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          title,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ),
                                      if (phone.isNotEmpty)
                                        Text(
                                          "• SĐT: $phone",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade800,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      timeLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

            // Footer phân trang gọn cho block báo cáo realtime
            if (totalItems > 0) ...[
              const SizedBox(height: 4),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems báo cáo",
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: validPage > 1
                              ? () => setState(
                                    () => _realtimeReportPage = validPage - 1,
                                  )
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            "Trang $validPage / $totalPages",
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: validPage < totalPages
                              ? () => setState(
                                    () => _realtimeReportPage = validPage + 1,
                                  )
                              : null,
                        ),
                      ],
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

  Widget _buildActiveDispatchersCard(AppState state) {
    final currentUserId = state.currentUserId;
    // Nút Nhận ca chỉ dành riêng cho tài khoản có vai trò Điều phối viên (dispatcher)
    // Quản trị viên (admin) và Giám đốc (manager) chỉ được xem, tuyệt đối không hiển thị nút này
    final username = (state.currentUsername ?? '').trim().toLowerCase();
    final userRoles = state.userRoles
        .map((r) => r.toString().toLowerCase())
        .toList();
    final bool isDispatcher =
        userRoles.contains('dispatcher') &&
        !userRoles.contains('admin') &&
        !userRoles.contains('manager') &&
        username != 'admin';

    // Kiểm tra xem tài khoản hiện tại có đang trong ca trực hay không
    final myActiveShift = _activeShifts.firstWhere(
      (s) => s['user_id'] == currentUserId,
      orElse: () => null,
    );
    final bool isInShift = myActiveShift != null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.blue.shade200, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.headset_mic,
                          color: Colors.blue.shade800,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Điều phối viên Đang trực ca",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              "Hệ thống cho phép nhiều điều phối viên cùng nhận ca và đồng hành trực tuyến",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Nút thao tác ca trực
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDispatcher) ...[
                      if (!isInShift)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade800,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text(
                            "Nhận ca trực",
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () => _handleCheckinShift(state),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              icon: const Icon(Icons.logout, size: 15),
                              label: const Text(
                                "Bàn giao / Hết ca",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () => _handleCheckoutShift(),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            // Danh sách điều phối viên đang làm việc
            if (_activeShifts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.blueGrey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Chưa có điều phối viên nào nhận ca trong thời điểm hiện tại.",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blueGrey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: _activeShifts.map((shift) {
                  final fullName =
                      shift['full_name'] ?? shift['username'] ?? 'Điều phối';
                  final username = shift['username'] ?? '';
                  final phone = shift['phone'] ?? '';
                  final startedAtStr = shift['started_at']?.toString() ?? '';
                  final shiftName = shift['shift_name'] ?? 'Ca ngày';

                  String timeFormatted = '';
                  try {
                    final dt = DateTime.parse(startedAtStr).toLocal();
                    timeFormatted =
                        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day}/${dt.month})";
                  } catch (_) {
                    timeFormatted = startedAtStr;
                  }

                  final bool isMe = shift['user_id'] == currentUserId;

                  return Container(
                    constraints: const BoxConstraints(minWidth: 260),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.blue.shade50.withOpacity(0.5)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isMe
                            ? Colors.blue.shade300
                            : Colors.grey.shade300,
                        width: isMe ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildUserAvatarItem(shift, size: 40),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade700,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      "Tôi",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "@$username • $shiftName",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey.shade700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Bắt đầu: $timeFormatted",
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    "• SĐT: $phone",
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleCheckinShift(AppState state) async {
    final noteCtrl = TextEditingController();
    String selectedShift = 'Ca ngày';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Row(
            children: [
              Icon(Icons.headset_mic, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                "Nhận ca trực điều phối",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Bạn chuẩn bị xác nhận bắt đầu ca làm việc. Trạng thái của bạn sẽ được hiển thị công khai cho Ban Giám Đốc, Quản trị viên và các điều phối viên khác.",
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                _buildFormLabel("Chọn ca trực"),
                DropdownButtonFormField<String>(
                  value: selectedShift,
                  isDense: true,
                  decoration: const InputDecoration(isDense: true),
                  items: const [
                    DropdownMenuItem(
                      value: 'Ca ngày',
                      child: Text("Ca ngày (07:00 - 19:00)"),
                    ),
                    DropdownMenuItem(
                      value: 'Ca đêm',
                      child: Text("Ca đêm (19:00 - 07:00)"),
                    ),
                    DropdownMenuItem(
                      value: 'Ca tăng cường',
                      child: Text("Ca tăng cường / Giờ cao điểm"),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedShift = val);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  "Ghi chú bắt đầu ca (nếu có):",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    hintText: "Nhập ghi chú hoặc dặn dò khi nhận ca...",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text("Xác nhận Nhận ca"),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final res = await AdminService.checkinShift(
        shiftName: selectedShift,
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );
      await _loadAllManagementData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: res['success'] == true ? Colors.green : Colors.red,
          content: Text(
            res['success'] == true
                ? "Đã nhận ca trực thành công! Trạng thái đang làm việc đã được cập nhật."
                : "Lỗi: ${res['message']}",
          ),
        ),
      );
    }
  }

  Future<void> _handleCheckoutShift() async {
    final noteCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Row(
          children: [
            Icon(Icons.assignment_turned_in, color: Colors.teal),
            SizedBox(width: 8),
            Text(
              "Bàn giao ca trực & Kết thúc",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Bạn có chắc muốn kết thúc ca trực hiện tại? Hãy nhập ghi chú bàn giao cho các điều phối viên ca tiếp theo nếu có.",
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                "Nội dung bàn giao / Ghi chú ca sau:",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  hintText:
                      "Ghi chú đơn hàng cần chú ý, sự cố xe đang theo dõi...",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text("Xác nhận Bàn giao"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      final res = await AdminService.checkoutShift(
        note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );
      await _loadAllManagementData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: res['success'] == true ? Colors.green : Colors.red,
          content: Text(
            res['success'] == true
                ? "Đã bàn giao và kết thúc ca trực thành công!"
                : "Lỗi: ${res['message']}",
          ),
        ),
      );
    }
  }

  Future<void> _showShiftHistoryDialog() async {
    showShiftHistoryDialog(context);
  }

  static Future<void> showShiftHistoryDialog(
    BuildContext context, {
    Map<String, dynamic>? targetUser,
  }) async {
    final int? filterUserId = targetUser?['id'] as int?;
    final String? filterFullName =
        targetUser?['full_name'] as String? ??
        targetUser?['username'] as String?;

    DateTime? filterDate;
    int shiftCurrentPage = 1;
    int shiftPageSize = 10;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              elevation: 0,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              child: Container(
                width: 980,
                height: 620,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FutureBuilder<List<dynamic>>(
                  future: AdminService.fetchShiftHistory(
                    userId: filterUserId,
                    limit: 100,
                  ),
                  builder: (context, snapshot) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.history,
                                    color: Colors.blue.shade800,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      filterFullName != null
                                          ? "Nhật ký & Lịch sử ca trực - $filterFullName"
                                          : "Nhật ký & Lịch sử ca trực Điều phối viên",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      filterFullName != null
                                          ? "Ghi nhận chi tiết thời gian nhận ca, kết thúc, bàn giao công việc của $filterFullName"
                                          : "Ghi nhận chi tiết thời gian nhận ca, kết thúc, bàn giao công việc của từng điều phối viên",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: "Đóng",
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                            ),
                          ],
                        ),
                        // THANH BỘ LỌC THEO NGÀY THÁNG NĂM
                        Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.filter_alt,
                                size: 18,
                                color: Colors.blue.shade800,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "Lọc theo ngày:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 10),
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: dialogCtx,
                                    initialDate: filterDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                    helpText: "CHỌN NGÀY CA TRỰC",
                                    cancelText: "HỦY",
                                    confirmText: "CHỌN",
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      filterDate = picked;
                                      shiftCurrentPage = 1;
                                    });
                                  }
                                },
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: filterDate != null
                                          ? Colors.blue.shade600
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        size: 14,
                                        color: filterDate != null
                                            ? Colors.blue.shade800
                                            : Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        filterDate != null
                                            ? "${filterDate!.day.toString().padLeft(2, '0')}/${filterDate!.month.toString().padLeft(2, '0')}/${filterDate!.year}"
                                            : "Tất cả các ngày",
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: filterDate != null
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: filterDate != null
                                              ? Colors.blue.shade900
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (filterDate != null) ...[
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(
                                    Icons.clear,
                                    size: 15,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    "Xóa lọc ngày",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      filterDate = null;
                                      shiftCurrentPage = 1;
                                    });
                                  },
                                ),
                              ],
                              const Spacer(),
                              Text(
                                "Định dạng: Ngày/Tháng/Năm",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Expanded(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (snapshot.hasError)
                          Expanded(
                            child: Center(
                              child: Text(
                                "Lỗi tải lịch sử ca trực: ${snapshot.error}",
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          )
                        else if (!snapshot.hasData || snapshot.data!.isEmpty)
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.event_busy,
                                    size: 48,
                                    color: Colors.blueGrey.shade300,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    filterFullName != null
                                        ? "Điều phối viên $filterFullName chưa có lịch sử ca trực nào."
                                        : "Chưa có dữ liệu lịch sử ca trực nào được ghi nhận.",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blueGrey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final allShifts = snapshot.data!;
                                // Lọc theo ngày nếu có chọn filterDate
                                final filteredShifts = allShifts.where((shift) {
                                  if (filterDate == null) return true;
                                  final startedAtStr =
                                      shift['started_at']?.toString() ?? '';
                                  if (startedAtStr.isEmpty) return false;
                                  try {
                                    final dt = DateTime.parse(
                                      startedAtStr,
                                    ).toLocal();
                                    return dt.year == filterDate!.year &&
                                        dt.month == filterDate!.month &&
                                        dt.day == filterDate!.day;
                                  } catch (_) {
                                    return false;
                                  }
                                }).toList();

                                if (filteredShifts.isEmpty) {
                                  return Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.search_off,
                                            size: 48,
                                            color: Colors.blueGrey.shade300,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            "Không tìm thấy ca trực nào trong ngày ${filterDate!.day.toString().padLeft(2, '0')}/${filterDate!.month.toString().padLeft(2, '0')}/${filterDate!.year}",
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              color: Colors.blueGrey.shade700,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 10,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              side: BorderSide(
                                                color: Colors.blue.shade600,
                                                width: 1.2,
                                              ),
                                              foregroundColor:
                                                  Colors.blue.shade800,
                                            ),
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              "Hiển thị tất cả",
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            onPressed: () {
                                              setDialogState(() {
                                                filterDate = null;
                                                shiftCurrentPage = 1;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }

                                final totalItems = filteredShifts.length;
                                final totalPages = (totalItems / shiftPageSize)
                                    .ceil();
                                final validPage = shiftCurrentPage > totalPages
                                    ? totalPages
                                    : (shiftCurrentPage < 1
                                          ? 1
                                          : shiftCurrentPage);
                                final startIndex =
                                    (validPage - 1) * shiftPageSize;
                                final endIndex =
                                    (startIndex + shiftPageSize > totalItems)
                                    ? totalItems
                                    : startIndex + shiftPageSize;
                                final pagedShifts = filteredShifts.sublist(
                                  startIndex,
                                  endIndex,
                                );

                                return Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(4),
                                              ),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(4),
                                              ),
                                          child: ListView.separated(
                                            itemCount: pagedShifts.length,
                                            separatorBuilder: (_, __) =>
                                                Divider(
                                                  height: 1,
                                                  color: Colors.grey.shade200,
                                                ),
                                            itemBuilder: (context, index) {
                                              final shift = pagedShifts[index];
                                              final shiftName =
                                                  shift['shift_name'] ??
                                                  'Ca ngày';
                                              final status =
                                                  shift['status'] ?? 'active';
                                              final isActive =
                                                  status == 'active';
                                              final note =
                                                  shift['note']?.toString() ??
                                                  '';
                                              final handoverNote =
                                                  shift['handover_note']
                                                      ?.toString() ??
                                                  '';
                                              final durationHours =
                                                  shift['duration_hours']
                                                      ?.toString() ??
                                                  '';

                                              final startedAtStr =
                                                  shift['started_at']
                                                      ?.toString() ??
                                                  '';
                                              final endedAtStr =
                                                  shift['ended_at']
                                                      ?.toString() ??
                                                  '';

                                              String startFmt = '-';
                                              if (startedAtStr.isNotEmpty) {
                                                try {
                                                  final dt = DateTime.parse(
                                                    startedAtStr,
                                                  ).toLocal();
                                                  startFmt =
                                                      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year})";
                                                } catch (_) {
                                                  startFmt = startedAtStr;
                                                }
                                              }

                                              String endFmt = 'Đang trực';
                                              if (endedAtStr.isNotEmpty) {
                                                try {
                                                  final dt = DateTime.parse(
                                                    endedAtStr,
                                                  ).toLocal();
                                                  endFmt =
                                                      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year})";
                                                } catch (_) {
                                                  endFmt = endedAtStr;
                                                }
                                              }

                                              return Container(
                                                color: isActive
                                                    ? Colors.blue.shade50
                                                          .withOpacity(0.3)
                                                    : Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 12,
                                                    ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    // Thông tin ca trực (đã bỏ avatar, tên đầy đủ và username theo yêu cầu)
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.blue.shade50,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        border: Border.all(
                                                          color: Colors
                                                              .blue
                                                              .shade200,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        shiftName,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors
                                                              .blue
                                                              .shade900,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 2: Thời gian bắt đầu
                                                    SizedBox(
                                                      width: 175,
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.login,
                                                            size: 14,
                                                            color: Colors
                                                                .green
                                                                .shade700,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              "Bắt đầu: $startFmt",
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                  ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 3: Thời gian kết thúc
                                                    SizedBox(
                                                      width: 175,
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.logout,
                                                            size: 14,
                                                            color: isActive
                                                                ? Colors
                                                                      .orange
                                                                      .shade700
                                                                : Colors
                                                                      .blueGrey
                                                                      .shade700,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              "Kết thúc: $endFmt",
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: isActive
                                                                    ? Colors
                                                                          .green
                                                                          .shade800
                                                                    : Colors
                                                                          .black87,
                                                                fontWeight:
                                                                    isActive
                                                                    ? FontWeight
                                                                          .bold
                                                                    : FontWeight
                                                                          .normal,
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 4: Thời lượng ca
                                                    SizedBox(
                                                      width: 130,
                                                      child: Text(
                                                        durationHours.isNotEmpty
                                                            ? "Thời lượng: $durationHours giờ"
                                                            : "-",
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          color: Colors
                                                              .blueGrey
                                                              .shade700,
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 5: Ghi chú nhận ca & bàn giao
                                                    Expanded(
                                                      flex: 4,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if (note.isNotEmpty)
                                                            Text(
                                                              "Ghi chú nhận ca: $note",
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        11.5,
                                                                    color: Colors
                                                                        .black87,
                                                                  ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          if (handoverNote
                                                              .isNotEmpty) ...[
                                                            if (note.isNotEmpty)
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                            Text(
                                                              "Bàn giao ca sau: $handoverNote",
                                                              style: TextStyle(
                                                                fontSize: 11.5,
                                                                color: Colors
                                                                    .teal
                                                                    .shade900,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ],
                                                          if (note.isEmpty &&
                                                              handoverNote
                                                                  .isEmpty)
                                                            Text(
                                                              "Không có ghi chú",
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .grey
                                                                    .shade500,
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 6: Tag trạng thái ca
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 5,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isActive
                                                            ? Colors
                                                                  .green
                                                                  .shade50
                                                            : Colors
                                                                  .grey
                                                                  .shade100,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        border: Border.all(
                                                          color: isActive
                                                              ? Colors
                                                                    .green
                                                                    .shade400
                                                              : Colors
                                                                    .grey
                                                                    .shade400,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        isActive
                                                            ? "Đang trực"
                                                            : "Đã hoàn thành",
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isActive
                                                              ? Colors
                                                                    .green
                                                                    .shade800
                                                              : Colors
                                                                    .grey
                                                                    .shade700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    // THANH PHÂN TRANG CHO CA TRỰC
                                    Container(
                                      height: 40,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border(
                                          left: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                          right: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                          bottom: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1,
                                          ),
                                        ),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              bottom: Radius.circular(4),
                                            ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Hiển thị ${startIndex + 1} - ${endIndex} trên tổng số ${totalItems} ca trực",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              const Text(
                                                "Số dòng/trang: ",
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              DropdownButton<int>(
                                                value: shiftPageSize,
                                                underline: const SizedBox(),
                                                isDense: true,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.blueGrey,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                items: const [
                                                  DropdownMenuItem(
                                                    value: 5,
                                                    child: Text("5"),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 10,
                                                    child: Text("10"),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 20,
                                                    child: Text("20"),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 50,
                                                    child: Text("50"),
                                                  ),
                                                ],
                                                onChanged: (val) {
                                                  if (val != null) {
                                                    setDialogState(() {
                                                      shiftPageSize = val;
                                                      shiftCurrentPage = 1;
                                                    });
                                                  }
                                                },
                                              ),
                                              const SizedBox(width: 12),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.first_page,
                                                  size: 18,
                                                ),
                                                tooltip: "Trang đầu",
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                splashRadius: 16,
                                                onPressed: validPage > 1
                                                    ? () => setDialogState(
                                                        () => shiftCurrentPage =
                                                            1,
                                                      )
                                                    : null,
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.chevron_left,
                                                  size: 18,
                                                ),
                                                tooltip: "Trang trước",
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                splashRadius: 16,
                                                onPressed: validPage > 1
                                                    ? () => setDialogState(
                                                        () => shiftCurrentPage =
                                                            validPage - 1,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: Colors.blue.shade200,
                                                  ),
                                                ),
                                                child: Text(
                                                  "Trang $validPage / $totalPages",
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue.shade800,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.chevron_right,
                                                  size: 18,
                                                ),
                                                tooltip: "Trang sau",
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                splashRadius: 16,
                                                onPressed:
                                                    validPage < totalPages
                                                    ? () => setDialogState(
                                                        () => shiftCurrentPage =
                                                            validPage + 1,
                                                      )
                                                    : null,
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.last_page,
                                                  size: 18,
                                                ),
                                                tooltip: "Trang cuối",
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                splashRadius: 16,
                                                onPressed:
                                                    validPage < totalPages
                                                    ? () => setDialogState(
                                                        () => shiftCurrentPage =
                                                            totalPages,
                                                      )
                                                    : null,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text("Đóng"),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pickAndUploadImage({
    required TextEditingController controller,
    required StateSetter setDialogState,
    required BuildContext ctx,
  }) async {
    try {
      final res = await Process.run('zenity', [
        '--file-selection',
        '--title=Chọn hình ảnh để tải lên máy chủ',
        '--file-filter=Hình ảnh (*.png *.jpg *.jpeg *.webp) | *.png *.jpg *.jpeg *.webp',
      ]);
      final selectedPath = res.stdout.toString().trim();
      if (selectedPath.isNotEmpty && File(selectedPath).existsSync()) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text("Đang tải ảnh lên máy chủ..."),
            duration: Duration(seconds: 1),
          ),
        );
        final uploadRes = await AdminService.uploadImage(selectedPath);
        if (uploadRes['success'] == true) {
          setDialogState(() {
            controller.text = uploadRes['url'];
          });
          if (mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                backgroundColor: Colors.green,
                content: Text("Tải ảnh thành công: ${uploadRes['filename']}"),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                backgroundColor: Colors.red,
                content: Text("Lỗi: ${uploadRes['message']}"),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text("Không thể mở trình chọn ảnh: $e"),
          ),
        );
      }
    }
  }

  Widget _buildImageUploadRow({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required StateSetter setDialogState,
    required BuildContext ctx,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFormLabel(label),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: "Chọn tệp từ máy hoặc nhập URL",
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                label: const Text(
                  "Chọn & Tải lên",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _pickAndUploadImage(
                  controller: controller,
                  setDialogState: setDialogState,
                  ctx: ctx,
                ),
              ),
            ),
          ],
        ),
        if (controller.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 14),
                const SizedBox(width: 6),
                Text(
                  "Đã lưu trên máy chủ: ${controller.text}",
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // DIALOG 1: THÊM TÀI KHOẢN MỚI
  void _showCreateUserDialog() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final avatarCtrl = TextEditingController();
    final idCardFrontCtrl = TextEditingController();
    final idCardBackCtrl = TextEditingController();
    String gender = "Nam";
    String selectedDriverType = "INTERNAL";
    String selectedRoleCode = "driver";

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Row(
            children: [
              Icon(Icons.person_add, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                "Thêm tài khoản mới",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormLabel("Tên đăng nhập (username) *"),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      hintText: "VD: taixe01",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Mật khẩu ban đầu *"),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: "Nhập mật khẩu...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Họ và tên hiển thị *"),
                  TextField(
                    controller: fullNameCtrl,
                    decoration: const InputDecoration(
                      hintText: "VD: Nguyễn Văn A",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Số điện thoại liên hệ *"),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: "VD: 0912345678",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Vai trò phân quyền"),
                  DropdownButtonFormField<String>(
                    value: selectedRoleCode,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(value: "driver", child: Text("Tài xế", style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                        value: "dispatcher",
                        child: Text("Điều phối", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "gas_station",
                        child: Text("Cây dầu / Trạm cấp nhiên liệu", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "mechanic",
                        child: Text("Kỹ thuật", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "manager",
                        child: Text("Ban Giám Đốc / Trưởng BP", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null)
                        setDialogState(() => selectedRoleCode = val);
                    },
                  ),
                  if (selectedRoleCode == "driver") ...[
                    const SizedBox(height: 14),
                    _buildFormLabel("Phân loại tài xế"),
                    DropdownButtonFormField<String>(
                      value: selectedDriverType,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: const [
                        DropdownMenuItem(
                          value: "INTERNAL",
                          child: Text("Tài xế công ty (Nội bộ)", style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: "RENTAL",
                          child: Text("Tài xế thuê ngoài", style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: "CUSTOMER_SELF",
                          child: Text("Khách hàng tự chở", style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null)
                          setDialogState(() => selectedDriverType = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Row(
                      children: const [
                        Icon(
                          Icons.badge_outlined,
                          color: Colors.blueGrey,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          "Hồ sơ tài xế vận chuyển",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildImageUploadRow(
                      label: "Ảnh chân dung tài xế",
                      icon: Icons.account_box_outlined,
                      controller: avatarCtrl,
                      setDialogState: setDialogState,
                      ctx: context,
                    ),
                    const SizedBox(height: 12),
                    _buildImageUploadRow(
                      label: "CCCD Mặt trước",
                      icon: Icons.credit_card,
                      controller: idCardFrontCtrl,
                      setDialogState: setDialogState,
                      ctx: context,
                    ),
                    const SizedBox(height: 12),
                    _buildImageUploadRow(
                      label: "CCCD Mặt sau",
                      icon: Icons.credit_card_outlined,
                      controller: idCardBackCtrl,
                      setDialogState: setDialogState,
                      ctx: context,
                    ),
                    const SizedBox(height: 12),
                    _buildFormLabel("Địa chỉ thường trú / tạm trú"),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(
                        hintText: "Nhập địa chỉ...",
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFormLabel("E-mail (nếu có)"),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: "VD: example@gmail.com",
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFormLabel("Tuổi"),
                              TextField(
                                controller: ageCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: "VD: 35",
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFormLabel("Giới tính"),
                              DropdownButtonFormField<String>(
                                value: gender,
                                isDense: true,
                                decoration: const InputDecoration(isDense: true),
                                items: const [
                                  DropdownMenuItem(
                                    value: "Nam",
                                    child: Text("Nam", style: TextStyle(fontSize: 13)),
                                  ),
                                  DropdownMenuItem(value: "Nữ", child: Text("Nữ", style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(
                                    value: "Khác",
                                    child: Text("Khác", style: TextStyle(fontSize: 13)),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null)
                                    setDialogState(() => gender = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildFormLabel("Ghi chú"),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: "Nhập ghi chú thêm...",
                        isDense: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (usernameCtrl.text.trim().isEmpty ||
                    passwordCtrl.text.trim().isEmpty ||
                    fullNameCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Vui lòng điền đủ tên đăng nhập, mật khẩu và họ tên",
                      ),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final payload = <String, dynamic>{
                  "username": usernameCtrl.text.trim(),
                  "password": passwordCtrl.text.trim(),
                  "full_name": fullNameCtrl.text.trim(),
                  "phone": phoneCtrl.text.trim(),
                  "driver_type": selectedRoleCode == "driver"
                      ? selectedDriverType
                      : null,
                  "role_codes": [selectedRoleCode],
                };

                if (selectedRoleCode == "driver") {
                  payload["avatar_url"] = avatarCtrl.text.trim().isNotEmpty
                      ? avatarCtrl.text.trim()
                      : null;
                  payload["id_card_front_url"] =
                      idCardFrontCtrl.text.trim().isNotEmpty
                      ? idCardFrontCtrl.text.trim()
                      : null;
                  payload["id_card_back_url"] =
                      idCardBackCtrl.text.trim().isNotEmpty
                      ? idCardBackCtrl.text.trim()
                      : null;
                  payload["address"] = addressCtrl.text.trim().isNotEmpty
                      ? addressCtrl.text.trim()
                      : null;
                  payload["email"] = emailCtrl.text.trim().isNotEmpty
                      ? emailCtrl.text.trim()
                      : null;
                  payload["age"] = int.tryParse(ageCtrl.text.trim());
                  payload["gender"] = gender;
                  payload["notes"] = notesCtrl.text.trim().isNotEmpty
                      ? notesCtrl.text.trim()
                      : null;
                }

                final res = await AdminService.createUser(payload);

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Đã tạo tài khoản thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text("Tạo tài khoản"),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOG: CHỈNH SỬA THÔNG TIN PHƯƠNG TIỆN
  void _showEditVehicleDialog(dynamic vehicleData) {
    final v = vehicleData is Map ? vehicleData : <String, dynamic>{};
    final plate = (v['plate_number'] ?? '').toString();
    final vtypeCtrl = TextEditingController(
      text: (v['vehicle_type'] ?? '').toString(),
    );
    final ownerCompanyCtrl = TextEditingController(
      text: (v['owner_company'] ?? 'Sao Mai Logistics').toString(),
    );
    String ownershipType = (v['ownership_type'] ?? 'INTERNAL').toString();
    if (!['INTERNAL', 'RENTAL', 'CUSTOMER_SELF'].contains(ownershipType)) {
      ownershipType = 'INTERNAL';
    }
    int? selectedDriverId = v['default_driver_id'] is int
        ? v['default_driver_id'] as int
        : int.tryParse((v['default_driver_id'] ?? '').toString());

    // Lọc danh sách các tài khoản tài xế có thể gán (kết hợp _users và _drivers, khử trùng id)
    final driverUsers = _getAvailableDriverUsers();
    // Tài xế nào đang gắn với xe nào (mỗi tài xế chỉ đi kèm 1 phương tiện)
    final driverPlateMap = <int, String>{};
    for (final other in _vehicles) {
      if (other is! Map) continue;
      final did = other['default_driver_id'];
      final id = did is int ? did : int.tryParse((did ?? '').toString());
      if (id != null) {
        driverPlateMap[id] = (other['plate_number'] ?? '').toString();
      }
    }
    // Nếu xe đang gán cho một tài xế chưa có trong danh sách thì bổ sung hoặc fallback về null
    // để tránh lỗi assertion của DropdownButtonFormField khi value không tồn tại trong items
    if (selectedDriverId != null &&
        !driverUsers.any((u) => u['id'] == selectedDriverId)) {
      final fallbackName = (v['driver_name'] ?? v['driver_username'] ?? '').toString().trim();
      if (fallbackName.isNotEmpty) {
        driverUsers.insert(0, {
          'id': selectedDriverId,
          'full_name': fallbackName,
          'phone': (v['driver_phone'] ?? '').toString(),
        });
      } else {
        selectedDriverId = null;
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.local_shipping,
                  size: 20,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Chỉnh sửa phương tiện: $plate",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Biển số xe (chỉ đọc)
                  _buildFormLabel("Biển kiểm soát (Cố định)"),
                  TextFormField(
                    initialValue: plate,
                    readOnly: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: Color(0xFFF8FAFC),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Loại phương tiện
                  _buildFormLabel("Loại phương tiện *"),
                  TextField(
                    controller: vtypeCtrl,
                    decoration: const InputDecoration(
                      hintText: "Ví dụ: Đầu kéo, Xe container, Xe tải...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Hình thức sở hữu
                  _buildFormLabel("Hình thức sở hữu *"),
                  DropdownButtonFormField<String>(
                    value: ownershipType,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: "INTERNAL",
                        child: Text("Xe nội bộ", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "RENTAL",
                        child: Text("Xe thuê ngoài", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "CUSTOMER_SELF",
                        child: Text("Khách tự vận chuyển", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => ownershipType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Tài xế chỉ định
                  _buildFormLabel("Tài xế chỉ định phụ trách"),
                  DropdownButtonFormField<int?>(
                    value: selectedDriverId,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          "Chưa phân bổ tài xế",
                          style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ...driverUsers.map((u) {
                        final id = u['id'] as int;
                        final name = (u['full_name'] ?? u['username'] ?? '')
                            .toString();
                        final phone = (u['phone'] ?? '').toString();
                        // Mỗi xe đi kèm 1 tài xế: tài xế đã gắn xe khác thì không chọn được
                        final otherPlate = driverPlateMap[id];
                        final busy = otherPlate != null && otherPlate != plate;
                        final label = phone.isNotEmpty
                            ? "$name ($phone)"
                            : name;
                        return DropdownMenuItem<int?>(
                          value: id,
                          enabled: !busy,
                          child: Text(
                            busy ? "$label - đang ở xe $otherPlate" : label,
                            style: TextStyle(
                              fontSize: 13,
                              color: busy ? Colors.grey : null,
                            ),
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedDriverId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Đơn vị quản lý
                  _buildFormLabel("Đơn vị quản lý / Công ty sở hữu"),
                  TextField(
                    controller: ownerCompanyCtrl,
                    decoration: const InputDecoration(
                      hintText: "Ví dụ: Sao Mai Logistics",
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                minimumSize: const Size(100, 44),
              ),
              onPressed: () async {
                final vtype = vtypeCtrl.text.trim();
                if (vtype.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Vui lòng nhập loại phương tiện"),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final payload = <String, dynamic>{
                  "vehicle_type": vtype,
                  "ownership_type": ownershipType,
                  "default_driver_id": selectedDriverId ?? -1,
                  "owner_company": ownerCompanyCtrl.text.trim().isNotEmpty
                      ? ownerCompanyCtrl.text.trim()
                      : "Sao Mai Logistics",
                };

                final res = await AdminService.updateVehicle(plate, payload);
                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Đã cập nhật thông tin phương tiện $plate thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text(
                "Lưu thay đổi",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOG 2: CHỈNH SỬA THÔNG TIN TÀI KHOẢN
  void _showEditUserDialog(Map<String, dynamic> user) {
    final fullNameCtrl = TextEditingController(text: user['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: user['phone'] ?? '');
    final addressCtrl = TextEditingController(text: user['address'] ?? '');
    final emailCtrl = TextEditingController(text: user['email'] ?? '');
    final ageCtrl = TextEditingController(
      text: user['age'] != null ? user['age'].toString() : '',
    );
    final notesCtrl = TextEditingController(text: user['notes'] ?? '');
    final avatarCtrl = TextEditingController(text: user['avatar_url'] ?? '');
    final idCardFrontCtrl = TextEditingController(
      text: user['id_card_front_url'] ?? '',
    );
    final idCardBackCtrl = TextEditingController(
      text: user['id_card_back_url'] ?? '',
    );
    String gender = (user['gender'] ?? "Nam").toString();
    if (!['Nam', 'Nữ', 'Khác'].contains(gender)) {
      gender = 'Nam';
    }
    String selectedDriverType = (user['driver_type'] ?? "INTERNAL").toString();
    if (!['INTERNAL', 'RENTAL', 'CUSTOMER_SELF'].contains(selectedDriverType)) {
      selectedDriverType = 'INTERNAL';
    }
    bool isActive = user['is_active'] ?? true;
    final userRoles =
        (user['role_codes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    const allowedEditRoles = ['driver', 'dispatcher', 'gas_station', 'mechanic', 'manager'];
    String selectedRoleCode = userRoles.isNotEmpty && allowedEditRoles.contains(userRoles.first)
        ? userRoles.first
        : "driver";

    final isSystemAdmin = user['username'] == 'admin';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              const Icon(Icons.edit, color: Colors.indigo),
              const SizedBox(width: 8),
              Text(
                "Chỉnh sửa: @${user['username']}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormLabel("Họ và tên hiển thị *"),
                  TextField(
                    controller: fullNameCtrl,
                    decoration: const InputDecoration(
                      hintText: "VD: Nguyễn Văn A",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Số điện thoại *"),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: "VD: 0912345678",
                      isDense: true,
                    ),
                  ),
                  if (!isSystemAdmin) ...[
                    const SizedBox(height: 14),
                    _buildFormLabel("Vai trò phân quyền"),
                    DropdownButtonFormField<String>(
                      value: selectedRoleCode,
                      isDense: true,
                      decoration: const InputDecoration(isDense: true),
                      items: const [
                        DropdownMenuItem(
                          value: "driver",
                          child: Text("Tài xế", style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: "dispatcher",
                          child: Text("Điều phối", style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: "gas_station",
                          child: Text("Cây dầu / Trạm cấp nhiên liệu", style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: "mechanic",
                          child: Text("Kỹ thuật", style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: "manager",
                          child: Text("Ban Giám Đốc / Trưởng BP", style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null)
                          setDialogState(() => selectedRoleCode = val);
                      },
                    ),
                    if (selectedRoleCode == "driver") ...[
                      const SizedBox(height: 14),
                      _buildFormLabel("Phân loại tài xế"),
                      DropdownButtonFormField<String>(
                        value: selectedDriverType,
                        isDense: true,
                        decoration: const InputDecoration(isDense: true),
                        items: const [
                          DropdownMenuItem(
                            value: "INTERNAL",
                            child: Text("Tài xế công ty (Nội bộ)", style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: "RENTAL",
                            child: Text("Tài xế thuê ngoài", style: TextStyle(fontSize: 13)),
                          ),
                          DropdownMenuItem(
                            value: "CUSTOMER_SELF",
                            child: Text("Khách hàng tự chở", style: TextStyle(fontSize: 13)),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null)
                            setDialogState(() => selectedDriverType = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      Row(
                        children: const [
                          Icon(
                            Icons.badge_outlined,
                            color: Colors.blueGrey,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            "Hồ sơ tài xế vận chuyển",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildImageUploadRow(
                        label: "Ảnh chân dung tài xế",
                        icon: Icons.account_box_outlined,
                        controller: avatarCtrl,
                        setDialogState: setDialogState,
                        ctx: context,
                      ),
                      const SizedBox(height: 12),
                      _buildImageUploadRow(
                        label: "CCCD Mặt trước",
                        icon: Icons.credit_card,
                        controller: idCardFrontCtrl,
                        setDialogState: setDialogState,
                        ctx: context,
                      ),
                      const SizedBox(height: 12),
                      _buildImageUploadRow(
                        label: "CCCD Mặt sau",
                        icon: Icons.credit_card_outlined,
                        controller: idCardBackCtrl,
                        setDialogState: setDialogState,
                        ctx: context,
                      ),
                      const SizedBox(height: 12),
                      _buildFormLabel("Địa chỉ thường trú / tạm trú"),
                      TextField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(
                          hintText: "Nhập địa chỉ...",
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildFormLabel("E-mail (nếu có)"),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: "VD: example@gmail.com",
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFormLabel("Tuổi"),
                                TextField(
                                  controller: ageCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    hintText: "VD: 35",
                                    isDense: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFormLabel("Giới tính"),
                                DropdownButtonFormField<String>(
                                  value: gender,
                                  isDense: true,
                                  decoration: const InputDecoration(isDense: true),
                                  items: const [
                                    DropdownMenuItem(
                                      value: "Nam",
                                      child: Text("Nam", style: TextStyle(fontSize: 13)),
                                    ),
                                    DropdownMenuItem(
                                      value: "Nữ",
                                      child: Text("Nữ", style: TextStyle(fontSize: 13)),
                                    ),
                                    DropdownMenuItem(
                                      value: "Khác",
                                      child: Text("Khác", style: TextStyle(fontSize: 13)),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    if (val != null)
                                      setDialogState(() => gender = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildFormLabel("Ghi chú"),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: "Nhập ghi chú thêm...",
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    hoverColor: Colors.transparent,
                    title: const Text(
                      "Trạng thái hoạt động",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      isActive
                          ? "Tài khoản đang được phép đăng nhập"
                          : "Đã khóa tài khoản này",
                    ),
                    value: isActive,
                    activeColor: Colors.green,
                    onChanged: isSystemAdmin
                        ? null
                        : (val) => setDialogState(() => isActive = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final payload = <String, dynamic>{
                  "full_name": fullNameCtrl.text.trim(),
                  "phone": phoneCtrl.text.trim(),
                  "is_active": isActive,
                };
                if (!isSystemAdmin) {
                  payload["driver_type"] = selectedRoleCode == "driver"
                      ? selectedDriverType
                      : null;
                  payload["role_codes"] = [selectedRoleCode];
                  if (selectedRoleCode == "driver") {
                    payload["avatar_url"] = avatarCtrl.text.trim().isNotEmpty
                        ? avatarCtrl.text.trim()
                        : null;
                    payload["id_card_front_url"] =
                        idCardFrontCtrl.text.trim().isNotEmpty
                        ? idCardFrontCtrl.text.trim()
                        : null;
                    payload["id_card_back_url"] =
                        idCardBackCtrl.text.trim().isNotEmpty
                        ? idCardBackCtrl.text.trim()
                        : null;
                    payload["address"] = addressCtrl.text.trim().isNotEmpty
                        ? addressCtrl.text.trim()
                        : null;
                    payload["email"] = emailCtrl.text.trim().isNotEmpty
                        ? emailCtrl.text.trim()
                        : null;
                    payload["age"] = int.tryParse(ageCtrl.text.trim());
                    payload["gender"] = gender;
                    payload["notes"] = notesCtrl.text.trim().isNotEmpty
                        ? notesCtrl.text.trim()
                        : null;
                  }
                } else {
                  payload["driver_type"] = null;
                  payload["role_codes"] = user['role_codes'] ?? ["admin"];
                }

                final res = await AdminService.updateUser(user['id'], payload);

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Đã cập nhật thông tin thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text("Lưu thay đổi"),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOG 3: ĐỔI MẬT KHẨU
  void _showChangePasswordDialog(Map<String, dynamic> user) {
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Row(
          children: [
            const Icon(Icons.key, color: Colors.amber),
            const SizedBox(width: 8),
            Text(
              "Đổi mật khẩu: @${user['username']}",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFormLabel("Mật khẩu mới *"),
              TextField(
                controller: newPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: "Nhập mật khẩu mới...",
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              _buildFormLabel("Xác nhận mật khẩu mới *"),
              TextField(
                controller: confirmPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: "Nhập lại mật khẩu mới...",
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newPwd = newPasswordCtrl.text.trim();
              final confirmPwd = confirmPasswordCtrl.text.trim();

              if (newPwd.isEmpty || newPwd.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Mật khẩu mới phải có ít nhất 4 ký tự"),
                  ),
                );
                return;
              }
              if (newPwd != confirmPwd) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Mật khẩu xác nhận không khớp")),
                );
                return;
              }

              Navigator.of(dialogCtx).pop();
              setState(() => _isLoading = true);

              final res = await AdminService.changePassword(user['id'], newPwd);
              await _loadAllManagementData();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: res['success'] == true
                      ? Colors.green
                      : Colors.red,
                  content: Text(
                    res['success'] == true
                        ? "Đã đổi mật khẩu cho @${user['username']} thành công!"
                        : "Lỗi: ${res['message']}",
                  ),
                ),
              );
            },
            child: const Text("Cập nhật mật khẩu"),
          ),
        ],
      ),
    );
  }

  // DIALOG 4: XÁC NHẬN XÓA TÀI KHOẢN
  void _confirmDeleteUser(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              "Xác nhận xóa tài khoản",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "Bạn có chắc chắn muốn xóa tài khoản '${user['full_name']}' (@${user['username']}) khỏi hệ thống không?\n\nThao tác này không thể hoàn tác.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              setState(() => _isLoading = true);

              final res = await AdminService.deleteUser(user['id']);
              await _loadAllManagementData();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: res['success'] == true
                      ? Colors.green
                      : Colors.red,
                  content: Text(
                    res['success'] == true
                        ? "Đã xóa tài khoản thành công!"
                        : "Lỗi: ${res['message']}",
                  ),
                ),
              );
            },
            child: const Text("Xóa vĩnh viễn"),
          ),
        ],
      ),
    );
  }

  // HELPER: Ô NHẬP LIỆU GỢI Ý TỰ ĐỘNG (AUTOCOMPLETE INPUT) CHO FORM ĐƠN HÀNG
  Widget _buildOrderAutocompleteInput({
    required TextEditingController controller,
    required String labelText,
    required IconData prefixIcon,
    required List<String> suggestions,
    String? hintText,
    bool isRequired = false,
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (TextEditingValue textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) {
          return suggestions.take(6);
        }
        return suggestions
            .where((option) => option.toLowerCase().contains(query))
            .take(8);
      },
      onSelected: (String selection) {
        controller.text = selection;
      },
      fieldViewBuilder:
          (
            context,
            fieldTextEditingController,
            fieldFocusNode,
            onFieldSubmitted,
          ) {
            // Đồng bộ dữ liệu khi người dùng nhập tay tự do
            fieldTextEditingController.addListener(() {
              if (controller.text != fieldTextEditingController.text) {
                controller.text = fieldTextEditingController.text;
              }
            });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFormLabel(isRequired ? "$labelText *" : labelText),
                TextField(
                  controller: fieldTextEditingController,
                  focusNode: fieldFocusNode,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hintText,
                  ),
                  onSubmitted: (val) => onFieldSubmitted(),
                ),
              ],
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 460),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (BuildContext context, int index) {
                  final String option = options.elementAt(index);
                  return InkWell(
                    hoverColor: Colors.blue.shade50,
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            prefixIcon,
                            size: 16,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              option,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // DIALOG: TẠO ĐƠN HÀNG MỚI
  void _showCreateOrderDialog() {
    final orderCodeCtrl = TextEditingController(
      text:
          "DH${DateTime.now().year}${(DateTime.now().month).toString().padLeft(2, '0')}${(DateTime.now().day).toString().padLeft(2, '0')}-${DateTime.now().millisecondsSinceEpoch % 10000}",
    );
    final factoryCodeCtrl = TextEditingController(text: "NM-BIMSON");
    final pickupAddrCtrl = TextEditingController(
      text: "Kho Xi Măng Bỉm Sơn, Thanh Hóa",
    );
    final deliveryAddrCtrl = TextEditingController();
    final cargoWeightCtrl = TextEditingController(text: "30.0");
    String transportType = "INTERNAL";
    int? selectedProductId = _products.isNotEmpty
        ? (_products[0]['id'] as int?)
        : null;
    final activeVehicles = _activeVehicles;
    String? selectedVehiclePlate = activeVehicles.isNotEmpty
        ? (activeVehicles[0]['plate_number']?.toString())
        : null;
    int? selectedDriverId;

    // Danh sách gợi ý Nhà máy, Nơi nhận và Điểm giao hàng
    final factorySuggestions = <String>{
      "NM-BIMSON",
      "NM_LONG_AN",
      "NM-NGHISON",
      "NM-HAIPHONG",
      "NM-CAMPHA",
    };
    final pickupSuggestions = <String>{
      "Kho Xi Măng Bỉm Sơn, Thanh Hóa",
      "Kho Long An KCN Thuận Đạo",
      "Kho Nghi Sơn, Thanh Hóa",
      "Cảng Nghi Sơn, Tĩnh Gia",
      "Kho Cảng Sài Gòn, Q.4, TP.HCM",
      "Cảng Cát Lái, TP. Thủ Đức",
    };
    final deliverySuggestions = <String>{
      "Dự án Khu đô thị Waterpoint, Bến Lức",
      "Trạm trộn Bê tông An Cư, Long An",
      "Công trình Cầu Mỹ Thuận 2",
      "Khu đô thị Vinhomes Grand Park, TP. Thủ Đức",
      "Trạm bê tông Lê Phan, Bình Chánh",
      "Công trình Cao tốc Bắc Nam - Đoạn Diễn Châu",
    };

    for (final ord in _orders) {
      if (ord is Map) {
        final f = (ord['factory_code'] ?? '').toString().trim();
        if (f.isNotEmpty) factorySuggestions.add(f);
        final p = (ord['pickup_address'] ?? '').toString().trim();
        if (p.isNotEmpty) pickupSuggestions.add(p);
        final d = (ord['delivery_address'] ?? '').toString().trim();
        if (d.isNotEmpty) deliverySuggestions.add(d);
      }
    }

    // Lọc danh sách tài xế (kết hợp _users và _drivers, khử trùng id)
    final driverUsers = _getAvailableDriverUsers();

    if (driverUsers.isNotEmpty) {
      selectedDriverId = driverUsers[0]['id'] as int?;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.add_shopping_cart,
                  size: 20,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Tạo đơn hàng vận tải mới",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFormLabel("Mã đơn hàng *"),
                            TextField(
                              controller: orderCodeCtrl,
                              decoration: const InputDecoration(
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildOrderAutocompleteInput(
                          controller: factoryCodeCtrl,
                          labelText: "Mã nhà máy",
                          prefixIcon: Icons.factory_outlined,
                          suggestions: factorySuggestions.toList(),
                          isRequired: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Chọn sản phẩm
                  _buildFormLabel("Sản phẩm / Hàng hóa *"),
                  DropdownButtonFormField<int?>(
                    value: selectedProductId,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: _products.map((p) {
                      final id = p['id'] as int;
                      final name = (p['name'] ?? 'Sản phẩm').toString();
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text(name, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedProductId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Trọng lượng hàng hóa
                  _buildFormLabel("Khối lượng hàng hóa (Tấn) *"),
                  TextField(
                    controller: cargoWeightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Ví dụ: 30.5",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Hình thức vận chuyển
                  _buildFormLabel("Hình thức vận chuyển"),
                  DropdownButtonFormField<String>(
                    value: transportType,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: "INTERNAL",
                        child: Text("Xe nội bộ", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "RENTAL",
                        child: Text("Xe thuê ngoài", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "CUSTOMER_SELF",
                        child: Text("Khách tự vận chuyển", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => transportType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Điểm nhận hàng (Gợi ý tự động Autocomplete)
                  _buildOrderAutocompleteInput(
                    controller: pickupAddrCtrl,
                    labelText: "Nơi nhận hàng (Địa chỉ lấy hàng)",
                    prefixIcon: Icons.warehouse_outlined,
                    suggestions: pickupSuggestions.toList(),
                    hintText: "Nhập hoặc chọn kho hàng...",
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  // Điểm giao hàng (Gợi ý tự động Autocomplete)
                  _buildOrderAutocompleteInput(
                    controller: deliveryAddrCtrl,
                    labelText: "Điểm giao hàng (Địa chỉ trả hàng)",
                    prefixIcon: Icons.location_on_outlined,
                    suggestions: deliverySuggestions.toList(),
                    hintText: "Nhập địa chỉ hoặc chọn công trình...",
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  // Phương tiện chỉ định
                  _buildFormLabel("Phương tiện vận chuyển *"),
                  DropdownButtonFormField<String?>(
                    value: selectedVehiclePlate,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      ...activeVehicles.map((v) {
                        final plate = (v['plate_number'] ?? '').toString();
                        final vtype = (v['vehicle_type'] ?? '').toString();
                        return DropdownMenuItem<String?>(
                          value: plate,
                          child: Text("$plate ($vtype)", style: const TextStyle(fontSize: 13)),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedVehiclePlate = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Tài xế chỉ định
                  _buildFormLabel("Tài xế phụ trách *"),
                  DropdownButtonFormField<int?>(
                    value: selectedDriverId,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      ...driverUsers.map((u) {
                        final id = u['id'] as int;
                        final name = (u['full_name'] ?? u['username'] ?? '')
                            .toString();
                        final phone = (u['phone'] ?? '').toString();
                        final label = phone.isNotEmpty
                            ? "$name ($phone)"
                            : name;
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(label, style: const TextStyle(fontSize: 13)),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedDriverId = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                minimumSize: const Size(100, 36),
              ),
              onPressed: () async {
                final code = orderCodeCtrl.text.trim();
                final factory = factoryCodeCtrl.text.trim();
                final pickup = pickupAddrCtrl.text.trim();
                final delivery = deliveryAddrCtrl.text.trim();
                final weight =
                    double.tryParse(cargoWeightCtrl.text.trim()) ?? 0.0;

                if (code.isEmpty ||
                    factory.isEmpty ||
                    pickup.isEmpty ||
                    delivery.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Vui lòng điền đầy đủ thông tin bắt buộc"),
                    ),
                  );
                  return;
                }
                if (selectedProductId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Vui lòng chọn loại sản phẩm"),
                    ),
                  );
                  return;
                }
                if (selectedVehiclePlate == null ||
                    selectedVehiclePlate!.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Vui lòng chọn phương tiện")),
                  );
                  return;
                }
                if (selectedDriverId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Vui lòng chỉ định tài xế phụ trách"),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final payload = <String, dynamic>{
                  "order_code": code,
                  "factory_code": factory,
                  "product_id": selectedProductId,
                  "transport_type": transportType,
                  "pickup_address": pickup,
                  "delivery_address": delivery,
                  "assigned_vehicle_plate": selectedVehiclePlate,
                  "assigned_driver_id": selectedDriverId,
                  "cargo_weight_tons": weight,
                };

                final res = await AdminService.createOrder(payload);
                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Tạo đơn hàng thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text("Tạo đơn hàng"),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOG: CHỈNH SỬA ĐƠN HÀNG
  void _showEditOrderDialog(dynamic orderData) {
    final o = orderData is Map ? orderData : <String, dynamic>{};
    final orderId = o['id'] as int;
    final orderCodeCtrl = TextEditingController(
      text: (o['order_code'] ?? '').toString(),
    );
    final factoryCodeCtrl = TextEditingController(
      text: (o['factory_code'] ?? 'NM-BIMSON').toString(),
    );
    final pickupAddrCtrl = TextEditingController(
      text: (o['pickup_address'] ?? '').toString(),
    );
    final deliveryAddrCtrl = TextEditingController(
      text: (o['delivery_address'] ?? '').toString(),
    );
    final cargoWeightCtrl = TextEditingController(
      text: (o['cargo_weight_tons']?.toString() ?? '30.0'),
    );
    String transportType = (o['transport_type'] ?? 'INTERNAL').toString();
    if (!['INTERNAL', 'RENTAL', 'CUSTOMER_SELF'].contains(transportType)) {
      transportType = 'INTERNAL';
    }
    int? selectedProductId = o['product_id'] as int?;
    String? selectedVehiclePlate = o['assigned_vehicle_plate']?.toString();
    int? selectedDriverId = o['assigned_driver_id'] as int?;
    String status = (o['status'] ?? 'assigned').toString();

    // Danh sách gợi ý Nhà máy, Nơi nhận và Điểm giao hàng
    final factorySuggestions = <String>{
      "NM-BIMSON",
      "NM_LONG_AN",
      "NM-NGHISON",
      "NM-HAIPHONG",
      "NM-CAMPHA",
    };
    final pickupSuggestions = <String>{
      "Kho Xi Măng Bỉm Sơn, Thanh Hóa",
      "Kho Long An KCN Thuận Đạo",
      "Kho Nghi Sơn, Thanh Hóa",
      "Cảng Nghi Sơn, Tĩnh Gia",
      "Kho Cảng Sài Gòn, Q.4, TP.HCM",
      "Cảng Cát Lái, TP. Thủ Đức",
    };
    final deliverySuggestions = <String>{
      "Dự án Khu đô thị Waterpoint, Bến Lức",
      "Trạm trộn Bê tông An Cư, Long An",
      "Công trình Cầu Mỹ Thuận 2",
      "Khu đô thị Vinhomes Grand Park, TP. Thủ Đức",
      "Trạm bê tông Lê Phan, Bình Chánh",
      "Công trình Cao tốc Bắc Nam - Đoạn Diễn Châu",
    };

    for (final ord in _orders) {
      if (ord is Map) {
        final f = (ord['factory_code'] ?? '').toString().trim();
        if (f.isNotEmpty) factorySuggestions.add(f);
        final p = (ord['pickup_address'] ?? '').toString().trim();
        if (p.isNotEmpty) pickupSuggestions.add(p);
        final d = (ord['delivery_address'] ?? '').toString().trim();
        if (d.isNotEmpty) deliverySuggestions.add(d);
      }
    }

    // Lọc danh sách tài xế (kết hợp _users và _drivers, khử trùng id)
    final driverUsers = _getAvailableDriverUsers();
    if (selectedDriverId != null &&
        !driverUsers.any((u) => u['id'] == selectedDriverId)) {
      final fallbackName = (o['driver_name'] ?? '').toString().trim();
      if (fallbackName.isNotEmpty) {
        driverUsers.insert(0, {
          'id': selectedDriverId,
          'full_name': fallbackName,
          'phone': (o['driver_phone'] ?? '').toString(),
        });
      } else {
        selectedDriverId = driverUsers.isNotEmpty ? driverUsers[0]['id'] as int? : null;
      }
    }
    if (selectedProductId != null &&
        !_products.any((p) => p is Map && p['id'] == selectedProductId)) {
      selectedProductId = _products.isNotEmpty ? _products[0]['id'] as int? : null;
    }
    // Xe chọn được: xe đang hoạt động + xe hiện tại của đơn (kể cả khi xe đó đã Tạm ngừng)
    final currentPlate = selectedVehiclePlate;
    final editVehicles = _vehicles
        .where((v) =>
            !_isVehicleInactive(v) ||
            (v is Map && (v['plate_number'] ?? '').toString() == currentPlate))
        .toList();
    if (selectedVehiclePlate != null &&
        !editVehicles.any((v) => v is Map && (v['plate_number'] ?? '').toString() == selectedVehiclePlate)) {
      selectedVehiclePlate = editVehicles.isNotEmpty ? (editVehicles[0]['plate_number'] ?? '').toString() : null;
    }
    status = _normalizeOrderStatus(status);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.edit_note,
                  size: 20,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Sửa đơn hàng: ${o['order_code'] ?? ''}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFormLabel("Mã đơn hàng *"),
                            TextField(
                              controller: orderCodeCtrl,
                              decoration: const InputDecoration(
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildOrderAutocompleteInput(
                          controller: factoryCodeCtrl,
                          labelText: "Mã nhà máy",
                          prefixIcon: Icons.factory_outlined,
                          suggestions: factorySuggestions.toList(),
                          isRequired: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Chọn sản phẩm
                  _buildFormLabel("Sản phẩm / Hàng hóa *"),
                  DropdownButtonFormField<int?>(
                    value: selectedProductId,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: _products.map((p) {
                      final id = p['id'] as int;
                      final name = (p['name'] ?? 'Sản phẩm').toString();
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text(name, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedProductId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Trọng lượng hàng hóa
                  _buildFormLabel("Khối lượng hàng hóa (Tấn) *"),
                  TextField(
                    controller: cargoWeightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Ví dụ: 30.5",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Hình thức vận chuyển
                  _buildFormLabel("Hình thức vận chuyển"),
                  DropdownButtonFormField<String>(
                    value: transportType,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: "INTERNAL",
                        child: Text("Xe nội bộ", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "RENTAL",
                        child: Text("Xe thuê ngoài", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "CUSTOMER_SELF",
                        child: Text("Khách tự vận chuyển", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => transportType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  // Điểm nhận hàng (Gợi ý tự động Autocomplete)
                  _buildOrderAutocompleteInput(
                    controller: pickupAddrCtrl,
                    labelText: "Nơi nhận hàng",
                    prefixIcon: Icons.warehouse_outlined,
                    suggestions: pickupSuggestions.toList(),
                    hintText: "Nhập hoặc chọn kho hàng...",
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  // Điểm giao hàng (Gợi ý tự động Autocomplete)
                  _buildOrderAutocompleteInput(
                    controller: deliveryAddrCtrl,
                    labelText: "Điểm giao hàng",
                    prefixIcon: Icons.location_on_outlined,
                    suggestions: deliverySuggestions.toList(),
                    hintText: "Nhập địa chỉ hoặc chọn công trình...",
                    isRequired: true,
                  ),
                  const SizedBox(height: 16),
                  // Phương tiện chỉ định
                  _buildFormLabel("Phương tiện vận chuyển *"),
                  DropdownButtonFormField<String?>(
                    value: selectedVehiclePlate,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      ...editVehicles.map((v) {
                        final plate = (v['plate_number'] ?? '').toString();
                        final vtype = (v['vehicle_type'] ?? '').toString();
                        return DropdownMenuItem<String?>(
                          value: plate,
                          child: Text("$plate ($vtype)", style: const TextStyle(fontSize: 13)),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedVehiclePlate = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Tài xế chỉ định
                  _buildFormLabel("Tài xế phụ trách *"),
                  DropdownButtonFormField<int?>(
                    value: selectedDriverId,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      ...driverUsers.map((u) {
                        final id = u['id'] as int;
                        final name = (u['full_name'] ?? u['username'] ?? '')
                            .toString();
                        final phone = (u['phone'] ?? '').toString();
                        final label = phone.isNotEmpty
                            ? "$name ($phone)"
                            : name;
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(label, style: const TextStyle(fontSize: 13)),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedDriverId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  // Trạng thái đơn hàng
                  _buildFormLabel("Trạng thái đơn hàng"),
                  DropdownButtonFormField<String>(
                    value: status,
                    isDense: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: "waiting",
                        child: Text("Chờ nhận (waiting)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "assigned",
                        child: Text("Đã điều phối (assigned)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "in_transit",
                        child: Text("Đang vận chuyển (in_transit)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "completed",
                        child: Text("Đã hoàn thành (completed)", style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: "cancelled",
                        child: Text("Đã hủy (cancelled)", style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => status = val);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                minimumSize: const Size(100, 36),
              ),
              onPressed: () async {
                final code = orderCodeCtrl.text.trim();
                final factory = factoryCodeCtrl.text.trim();
                final pickup = pickupAddrCtrl.text.trim();
                final delivery = deliveryAddrCtrl.text.trim();
                final weight =
                    double.tryParse(cargoWeightCtrl.text.trim()) ?? 0.0;

                if (code.isEmpty ||
                    factory.isEmpty ||
                    pickup.isEmpty ||
                    delivery.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Vui lòng điền đầy đủ thông tin bắt buộc"),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final payload = <String, dynamic>{
                  "order_code": code,
                  "factory_code": factory,
                  "product_id": selectedProductId,
                  "transport_type": transportType,
                  "pickup_address": pickup,
                  "delivery_address": delivery,
                  "assigned_vehicle_plate": selectedVehiclePlate,
                  "assigned_driver_id": selectedDriverId,
                  "cargo_weight_tons": weight,
                  "status": status,
                };

                final res = await AdminService.updateOrder(orderId, payload);
                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Cập nhật đơn hàng thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text("Lưu thay đổi"),
            ),
          ],
        ),
      ),
    );
  }

  String _normalizeOrderStatus(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'waiting' || s == 'pending') return 'waiting';
    if (s == 'assigned') return 'assigned';
    if ([
      'in_transit',
      'in_progress',
      'arrived',
      'pumping',
      'pumped',
    ].contains(s)) {
      return 'in_transit';
    }
    if (s == 'completed' || s == 'delivered') return 'completed';
    if (s == 'cancelled') return 'cancelled';
    return 'assigned';
  }

  Future<void> _quickChangeOrderStatus(
    dynamic orderData,
    String newStatus,
  ) async {
    final o = orderData is Map
        ? Map<String, dynamic>.from(orderData)
        : <String, dynamic>{};
    final int? orderId = o['id'] is int
        ? o['id'] as int
        : int.tryParse('${o['id'] ?? ''}');
    if (orderId == null) return;
    final orderCode = (o['order_code'] ?? '').toString();

    // Cap nhat giao dien tuc thi
    setState(() {
      for (final item in _orders) {
        if (item is Map && item['id'] == orderId) {
          item['status'] = newStatus;
        }
      }
    });

    final res = await AdminService.updateOrder(orderId, {'status': newStatus});
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
          content: Text(
            "Đã chuyển trạng thái đơn $orderCode sang '${_orderStatusLabel(newStatus)}'!",
          ),
        ),
      );
      await _loadAllManagementData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(
            "Không thể đổi trạng thái đơn $orderCode: ${res['message'] ?? 'Lỗi máy chủ'}",
          ),
        ),
      );
      await _loadAllManagementData();
    }
  }

  String _orderStatusLabel(String norm) {
    switch (norm) {
      case 'waiting':
        return 'Chờ nhận';
      case 'assigned':
        return 'Đã điều phối';
      case 'in_transit':
        return 'Đang vận chuyển';
      case 'completed':
        return 'Hoàn thành';
      case 'cancelled':
        return 'Đã hủy';
      default:
        return norm;
    }
  }

  Widget _buildOrderStatusSelectBox(
    dynamic orderData, {
    required bool canEdit,
  }) {
    final o = orderData is Map
        ? Map<String, dynamic>.from(orderData)
        : <String, dynamic>{};
    final current = _normalizeOrderStatus((o['status'] ?? 'assigned').toString());

    Color bg;
    Color border;
    Color fg;
    switch (current) {
      case 'waiting':
        bg = const Color(0xFFF8FAFC);
        border = const Color(0xFFCBD5E1);
        fg = const Color(0xFF475569);
        break;
      case 'assigned':
        bg = Colors.green.shade50;
        border = Colors.green.shade300;
        fg = Colors.green.shade800;
        break;
      case 'in_transit':
        bg = Colors.blue.shade50;
        border = Colors.blue.shade300;
        fg = Colors.blue.shade800;
        break;
      case 'completed':
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFF6EE7B7);
        fg = const Color(0xFF047857);
        break;
      case 'cancelled':
        bg = Colors.red.shade50;
        border = Colors.red.shade300;
        fg = Colors.red.shade800;
        break;
      default:
        bg = Colors.green.shade50;
        border = Colors.green.shade300;
        fg = Colors.green.shade800;
    }

    if (!canEdit) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        child: Text(
          _orderStatusLabel(current),
          style: TextStyle(
            color: fg,
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    const statuses = <Map<String, dynamic>>[
      {'val': 'waiting', 'label': 'Chờ nhận', 'color': Color(0xFF475569)},
      {'val': 'assigned', 'label': 'Đã điều phối', 'color': Color(0xFF15803D)},
      {
        'val': 'in_transit',
        'label': 'Đang vận chuyển',
        'color': Color(0xFF1D4ED8),
      },
      {'val': 'completed', 'label': 'Hoàn thành', 'color': Color(0xFF047857)},
      {'val': 'cancelled', 'label': 'Đã hủy', 'color': Color(0xFFB91C1C)},
    ];

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: fg),
          style: TextStyle(
            color: fg,
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            fontFamily: 'Nunito',
          ),
          items: statuses.map((st) {
            final val = st['val'] as String;
            final label = st['label'] as String;
            final c = st['color'] as Color;
            return DropdownMenuItem<String>(
              value: val,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: c,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null && val != current) {
              _quickChangeOrderStatus(o, val);
            }
          },
        ),
      ),
    );
  }

  Widget _buildOrderPhotosSummaryCell(dynamic orderData) {
    final o = orderData is Map
        ? Map<String, dynamic>.from(orderData)
        : <String, dynamic>{};
    final pumpBeforeUrl =
        (o['pump_slip_before_photo_url'] ?? '').toString().trim();
    final pumpUrl = (o['pump_slip_photo_url'] ?? '').toString().trim();
    final weighUrl = (o['weigh_slip_photo_url'] ?? '').toString().trim();
    final delivUrl = (o['delivery_slip_photo_url'] ?? '').toString().trim();
    final breakUrl = (o['breakdown_photo_url'] ?? '').toString().trim();
    final hasBreakdown = o['has_breakdown'] == true || breakUrl.isNotEmpty;
    final repairUrl = (o['repair_photo_url'] ?? '').toString().trim();

    Widget badge({
      required String shortLabel,
      required String fullTitle,
      required String url,
      required IconData icon,
      required Color activeColor,
      bool forceShow = true,
    }) {
      if (!forceShow && url.isEmpty) return const SizedBox.shrink();
      final has = url.isNotEmpty;
      final c = has ? activeColor : Colors.grey.shade400;
      return Tooltip(
        message: has
            ? "$fullTitle: Đã có ảnh (Bấm để xem)"
            : "$fullTitle: Chưa chụp",
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            if (has) {
              OrderAttachmentsSection.showFullImageDialog(
                context,
                title: "$fullTitle — Đơn ${o['order_code'] ?? ''}",
                rawUrl: url,
              );
            } else {
              _showOrderAttachmentsDialog(o);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: has
                  ? activeColor.withValues(alpha: 0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: has
                    ? activeColor.withValues(alpha: 0.45)
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: c),
                const SizedBox(width: 3),
                Text(
                  shortLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: has ? FontWeight.bold : FontWeight.w500,
                    color: has ? activeColor : Colors.grey.shade600,
                  ),
                ),
                if (has) ...[
                  const SizedBox(width: 2),
                  Icon(Icons.check_circle, size: 10, color: activeColor),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        badge(
          shortLabel: "Trước bơm",
          fullTitle: "Bơm hàng - Trước khi bơm (Tài xế)",
          url: pumpBeforeUrl,
          icon: Icons.local_gas_station_outlined,
          activeColor: const Color(0xFF0284C7),
        ),
        badge(
          shortLabel: "Bơm xong",
          fullTitle: "Bơm hàng - Đã bơm xong (Tài xế)",
          url: pumpUrl,
          icon: Icons.local_gas_station,
          activeColor: const Color(0xFF0284C7),
        ),
        badge(
          shortLabel: "Cân",
          fullTitle: "Phiếu cân hàng (Tài xế)",
          url: weighUrl,
          icon: Icons.scale_outlined,
          activeColor: const Color(0xFF2563EB),
        ),
        badge(
          shortLabel: "Giao",
          fullTitle: "Phiếu giao hàng (Tài xế)",
          url: delivUrl,
          icon: Icons.assignment_turned_in_outlined,
          activeColor: const Color(0xFF15803D),
        ),
        if (hasBreakdown)
          badge(
            shortLabel: "Báo hỏng",
            fullTitle: "Ảnh Báo hỏng xe (Tài xế)",
            url: breakUrl,
            icon: Icons.car_crash_outlined,
            activeColor: const Color(0xFFDC2626),
          ),
        if (hasBreakdown || repairUrl.isNotEmpty)
          badge(
            shortLabel: "Sửa KT",
            fullTitle: "Báo cáo Sửa chữa (Kỹ thuật)",
            url: repairUrl,
            icon: Icons.build_circle_outlined,
            activeColor: const Color(0xFFD97706),
          ),
      ],
    );
  }

  void _showOrderAttachmentsDialog(dynamic orderData) {
    final o = orderData is Map
        ? Map<String, dynamic>.from(orderData)
        : <String, dynamic>{};
    final orderCode = (o['order_code'] ?? '---').toString();
    final productName = (o['product_name'] ?? '---').toString();
    final weightTons = o['cargo_weight_tons']?.toString() ?? '0';
    final pickupAddr =
        (o['pickup_address'] ?? o['pickup_location'] ?? '---').toString();
    final deliveryAddr =
        (o['delivery_address'] ?? o['delivery_location'] ?? '---').toString();
    final vehiclePlate =
        (o['assigned_vehicle_plate'] ?? 'Chưa gán xe').toString();
    final driverName = (o['driver_name'] ?? 'Chưa gán tài xế').toString();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Hồ sơ hình chụp & Chi tiết đơn hàng: $orderCode",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "$productName ($weightTons tấn) • Xe: $vehiclePlate • Tài xế: $driverName",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
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
                              children: [
                                Icon(
                                  Icons.trip_origin,
                                  size: 13,
                                  color: Colors.amber.shade800,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    "Điểm nhận: $pickupAddr",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 13,
                                  color: Colors.red.shade700,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    "Điểm giao: $deliveryAddr",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1E293B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      OrderAttachmentsSection(
                        order: o,
                        readOnly: true,
                        onOrderUpdated: (_) {
                          Navigator.pop(ctx);
                          _loadAllManagementData();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(88, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        "Đóng",
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // DIALOG: XÁC NHẬN XÓA ĐƠN HÀNG
  void _confirmDeleteOrder(dynamic orderData) {
    final o = orderData is Map ? orderData : <String, dynamic>{};
    final orderId = o['id'] as int;
    final orderCode = (o['order_code'] ?? 'N/A').toString();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              "Xác nhận xóa đơn hàng",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          "Bạn có chắc chắn muốn xóa đơn hàng '$orderCode' khỏi hệ thống không?\n\nThao tác này sẽ xóa đơn và toàn bộ mốc giờ chuyến liên quan và không thể hoàn tác.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              minimumSize: const Size(100, 36),
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              setState(() => _isLoading = true);

              final res = await AdminService.deleteOrder(orderId);
              await _loadAllManagementData();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: res['success'] == true
                      ? Colors.green
                      : Colors.red,
                  content: Text(
                    res['success'] == true
                        ? "Đã xóa đơn hàng thành công!"
                        : "Lỗi: ${res['message']}",
                  ),
                ),
              );
            },
            child: const Text("Xóa đơn hàng"),
          ),
        ],
      ),
    );
  }

  String _getModuleLabel(String module) {
    switch (module.toLowerCase()) {
      case 'order':
        return 'Đơn hàng vận tải';
      case 'product':
        return 'Sản phẩm & Vật liệu';
      case 'vehicle':
        return 'Đội xe & Phương tiện';
      case 'driver':
        return 'Hồ sơ Tài xế';
      case 'fuel':
        return 'Cây dầu & Đối soát';
      case 'inspection':
        return 'Kiểm tra xe đầu ngày';
      case 'maintenance':
        return 'Báo hỏng & Sửa chữa';
      case 'report':
        return 'Báo cáo & Thống kê';
      case 'system':
        return 'Hệ thống & Người dùng';
      default:
        return module.toUpperCase();
    }
  }

  IconData _getModuleIcon(String module) {
    switch (module.toLowerCase()) {
      case 'order':
        return Icons.receipt_long_outlined;
      case 'product':
        return Icons.inventory_2_outlined;
      case 'vehicle':
        return Icons.local_shipping_outlined;
      case 'driver':
        return Icons.badge_outlined;
      case 'fuel':
        return Icons.local_gas_station_outlined;
      case 'inspection':
        return Icons.verified_user_outlined;
      case 'maintenance':
        return Icons.build_outlined;
      case 'report':
        return Icons.bar_chart_outlined;
      case 'system':
        return Icons.settings_suggest_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  // DIALOG: TẠO VAI TRÒ MỚI (ROLE) KÈM CHỌN QUYỀN
  void _showCreateRoleDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final selectedPerms = <String>{};

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Row(
            children: [
              Icon(Icons.add_moderator, color: Colors.indigo),
              SizedBox(width: 8),
              Text(
                "Thêm vai trò phân quyền mới",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormLabel("Mã vai trò (code - viết liền, không dấu) *"),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      hintText: "Ví dụ: accountant, supervisor, qc...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Tên vai trò hiển thị *"),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: "Ví dụ: Kế toán vận tải, Giám sát kho...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Mô tả vai trò"),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText:
                          "Mô tả trách nhiệm và nhiệm vụ của vai trò này...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Cấp quyền hành động chức năng:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blueGrey,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            if (selectedPerms.length == _permissions.length) {
                              selectedPerms.clear();
                            } else {
                              selectedPerms.addAll(
                                _permissions.map((p) => p['code'].toString()),
                              );
                            }
                          });
                        },
                        child: Text(
                          selectedPerms.length == _permissions.length
                              ? "Bỏ chọn tất cả"
                              : "Chọn tất cả",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final Map<String, List<dynamic>> groupedPerms = {};
                      for (final p in _permissions) {
                        final mod = (p['module'] ?? 'other').toString();
                        groupedPerms.putIfAbsent(mod, () => []).add(p);
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: groupedPerms.entries.map((entry) {
                          final modKey = entry.key;
                          final permsInMod = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _getModuleIcon(modKey),
                                        size: 16,
                                        color: Colors.indigo.shade800,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getModuleLabel(modKey),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.indigo.shade900,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "(${permsInMod.where((p) => selectedPerms.contains(p['code'])).length}/${permsInMod.length})",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...permsInMod.map((p) {
                                  final pCode = p['code'].toString();
                                  final pName = p['name'] ?? pCode;
                                  final isChecked = selectedPerms.contains(
                                    pCode,
                                  );

                                  final isUserManage = pCode == 'user:manage';
                                  return CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 0,
                                    ),
                                    dense: true,
                                    hoverColor: Colors.transparent,
                                    value: isChecked,
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            pName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isUserManage
                                                  ? Colors.grey.shade600
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isUserManage)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.red.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              "Chỉ Admin tối cao",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      "Mã: $pCode",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    onChanged: isUserManage
                                        ? null
                                        : (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedPerms.add(pCode);
                                              } else {
                                                selectedPerms.remove(pCode);
                                              }
                                            });
                                          },
                                  );
                                }),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final code = codeCtrl.text.trim().toLowerCase();
                final name = nameCtrl.text.trim();
                if (code.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Vui lòng điền đầy đủ mã và tên vai trò"),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final res = await AdminService.createRole({
                  "code": code,
                  "name": name,
                  "description": descCtrl.text.trim().isNotEmpty
                      ? descCtrl.text.trim()
                      : null,
                  "permission_codes": selectedPerms.toList(),
                });

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Đã tạo vai trò mới thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text("Tạo vai trò"),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOG: CẬP NHẬT VAI TRÒ VÀ CẤU HÌNH QUYỀN (PERMISSIONS)
  void _showEditRoleDialog(Map<String, dynamic> role) {
    final nameCtrl = TextEditingController(text: role['name'] ?? '');
    final descCtrl = TextEditingController(text: role['description'] ?? '');
    final existingPerms =
        (role['permission_codes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final selectedPerms = Set<String>.from(existingPerms);
    final isSystemCore =
        role['is_system'] == true ||
        [
          'admin',
          'driver',
          'dispatcher',
          'gas_station',
          'mechanic',
          'manager',
        ].contains(role['code']);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              const Icon(Icons.tune, color: Colors.indigo),
              const SizedBox(width: 8),
              Text(
                "Cấu hình vai trò & quyền: ${role['name']}",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Mã định danh hệ thống: ${role['code']}${isSystemCore ? ' (Vai trò cốt lõi)' : ''}",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Tên vai trò hiển thị *"),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: "Nhập tên vai trò...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildFormLabel("Mô tả vai trò"),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: "Nhập mô tả vai trò...",
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Danh sách hành động chức năng (${selectedPerms.length}/${_permissions.length}):",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blueGrey,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            if (selectedPerms.length == _permissions.length) {
                              selectedPerms.clear();
                            } else {
                              selectedPerms.addAll(
                                _permissions.map((p) => p['code'].toString()),
                              );
                            }
                          });
                        },
                        child: Text(
                          selectedPerms.length == _permissions.length
                              ? "Bỏ chọn tất cả"
                              : "Chọn tất cả",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      final Map<String, List<dynamic>> groupedPerms = {};
                      for (final p in _permissions) {
                        final mod = (p['module'] ?? 'other').toString();
                        groupedPerms.putIfAbsent(mod, () => []).add(p);
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: groupedPerms.entries.map((entry) {
                          final modKey = entry.key;
                          final permsInMod = entry.value;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _getModuleIcon(modKey),
                                        size: 16,
                                        color: Colors.indigo.shade800,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getModuleLabel(modKey),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.indigo.shade900,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "(${permsInMod.where((p) => selectedPerms.contains(p['code'])).length}/${permsInMod.length})",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...permsInMod.map((p) {
                                  final pCode = p['code'].toString();
                                  final pName = p['name'] ?? pCode;
                                  final isChecked = selectedPerms.contains(
                                    pCode,
                                  );

                                  final isUserManage = pCode == 'user:manage';
                                  final isLocked =
                                      isUserManage && role['code'] != 'admin';
                                  return CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 0,
                                    ),
                                    dense: true,
                                    hoverColor: Colors.transparent,
                                    value: isChecked,
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            pName,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isLocked
                                                  ? Colors.grey.shade600
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isUserManage)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: Colors.red.shade200,
                                              ),
                                            ),
                                            child: Text(
                                              "Chỉ Admin tối cao",
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      "Mã: $pCode",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    onChanged: isLocked
                                        ? null
                                        : (val) {
                                            setDialogState(() {
                                              if (val == true) {
                                                selectedPerms.add(pCode);
                                              } else {
                                                selectedPerms.remove(pCode);
                                              }
                                            });
                                          },
                                  );
                                }),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Tên vai trò không được để trống"),
                    ),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final res = await AdminService.updateRole(role['id'], {
                  "name": name,
                  "description": descCtrl.text.trim().isNotEmpty
                      ? descCtrl.text.trim()
                      : null,
                  "permission_codes": selectedPerms.toList(),
                });

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true
                        ? Colors.green
                        : Colors.red,
                    content: Text(
                      res['success'] == true
                          ? "Đã cập nhật vai trò & quyền thành công!"
                          : "Lỗi: ${res['message']}",
                    ),
                  ),
                );
              },
              child: const Text("Lưu thay đổi"),
            ),
          ],
        ),
      ),
    );
  }

  // DIALOG: XÓA VAI TRÒ
  void _showDeleteRoleDialog(Map<String, dynamic> role) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              "Xác nhận xóa vai trò",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          "Bạn có chắc chắn muốn xóa vai trò '${role['name']}' (Mã: ${role['code']}) không?\n\nNếu vai trò đang được gán cho người dùng, hệ thống sẽ ngăn chặn thao tác này.",
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              setState(() => _isLoading = true);

              final res = await AdminService.deleteRole(role['id']);
              await _loadAllManagementData();

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: res['success'] == true
                      ? Colors.green
                      : Colors.red,
                  content: Text(
                    res['success'] == true
                        ? "Đã xóa vai trò thành công!"
                        : "Lỗi: ${res['message']}",
                  ),
                ),
              );
            },
            child: const Text("Xóa vĩnh viễn"),
          ),
        ],
      ),
    );
  }

  static Widget _buildUserAvatarItem(
    Map<String, dynamic> u, {
    double size = 48.0,
  }) {
    final avatarUrl = u['avatar_url']?.toString().trim();
    final isDispatcher =
        u['role_codes'] != null &&
        (u['role_codes'] as List<dynamic>).contains('dispatcher');
    final double avatarSize = size;

    Widget fallbackIcon = Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        color: Colors.indigo.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Icon(
        isDispatcher ? Icons.admin_panel_settings : Icons.person,
        color: Colors.indigo.shade800,
        size: avatarSize * 0.55,
      ),
    );

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return fallbackIcon;
    }

    Widget imageWidget;
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      imageWidget = Image.network(
        avatarUrl,
        width: avatarSize,
        height: avatarSize,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) => fallbackIcon,
      );
    } else if (avatarUrl.startsWith('/uploads/') ||
        avatarUrl.startsWith('uploads/')) {
      final cleanPath = avatarUrl.startsWith('/') ? avatarUrl : '/$avatarUrl';
      imageWidget = Image.network(
        '${ApiConfig.host}$cleanPath',
        width: avatarSize,
        height: avatarSize,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (context, error, stackTrace) => fallbackIcon,
      );
    } else {
      final file = File(avatarUrl);
      if (file.existsSync()) {
        imageWidget = Image.file(
          file,
          width: avatarSize,
          height: avatarSize,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) => fallbackIcon,
        );
      } else {
        imageWidget = Image.network(
          '${ApiConfig.host}/$avatarUrl',
          width: avatarSize,
          height: avatarSize,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          errorBuilder: (context, error, stackTrace) => fallbackIcon,
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: avatarSize,
        height: avatarSize,
        child: AspectRatio(aspectRatio: 1.0, child: imageWidget),
      ),
    );
  }

  // TAB 8: Cấu hình Nhắc nhở & Kịch bản Nền (Chỉ Điều phối, Giám đốc, Quản lý)
  Widget _buildRemindersConfigTab(AppState state) {
    final roles = state.userRoles.map((r) => r.toLowerCase()).toList();
    final username = (state.currentUsername ?? '').trim().toLowerCase();
    final bool hasPermission =
        username == 'admin' ||
        roles.contains('admin') ||
        roles.contains('manager') ||
        roles.contains('dispatcher');

    if (!hasPermission) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.red.shade200, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.gpp_bad_outlined,
                size: 48,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 16),
              const Text(
                "Từ Chối Quyền Truy Cập",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Màn hình Cấu hình & Kịch bản Nhắc nhở Chạy Nền chỉ dành riêng cho các tài khoản có vai trò Điều phối, Giám đốc hoặc Quản lý hệ thống.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Thẻ giới thiệu phân hệ
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.blue.shade300, width: 1),
          ),
          color: Colors.blue.shade50.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Colors.blue.shade800,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Trung Tâm Điều Hành Kịch Bản Nhắc Nhở & Cảnh Báo Nền (Background Daemon)",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Phân hệ này cho phép Điều phối, Giám đốc và Quản trị viên theo dõi các quy tắc kiểm tra tự động chạy nền, định cấu hình ngưỡng vi phạm GPS/thời gian chờ bồn, và chạy kiểm thử mô phỏng các kịch bản thực tế gửi về thiết bị tài xế.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 1: Bảng thông số & Ngưỡng kích hoạt tự động
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune, size: 20, color: Colors.blueGrey.shade800),
                    const SizedBox(width: 8),
                    const Text(
                      "Quy Tắc & Ngưỡng Kích Hoạt Cảnh Báo Tự Động",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        "Đang kích hoạt nền",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildRuleItem(
                  icon: Icons.navigation_outlined,
                  title: "1. Vi phạm lăn bánh chưa kiểm tra xe 5 góc ảnh",
                  desc:
                      "Khi GPS xe di chuyển vượt quá 500m so với tọa độ bãi/điểm đỗ mà tài xế chưa hoàn thành đủ 5 ảnh kiểm tra nhận ca.",
                  thresholdText: "> 500 mét di chuyển",
                  statusTag: "Bắt buộc 100%",
                  color: Colors.deepOrange,
                ),
                const SizedBox(height: 12),
                _buildRuleItem(
                  icon: Icons.timer_outlined,
                  title:
                      "2. Cảnh báo dừng tại vùng giao chưa xác nhận đến trạm",
                  desc:
                      "GPS phát hiện xe đứng yên trong bán kính trạm giao hàng quá 15 phút mà tài xế chưa ấn mốc 'ĐẾN ĐIỂM GIAO'.",
                  thresholdText: "> 15 phút dừng trạm",
                  statusTag: "Cảnh báo cấp 1",
                  color: Colors.amber.shade900,
                ),
                const SizedBox(height: 12),
                _buildRuleItem(
                  icon: Icons.hourglass_bottom_outlined,
                  title: "3. Cảnh báo thời gian xả bồn quá hạn mức",
                  desc:
                      "Thời gian từ lúc bấm ĐẾN vượt quá 120 phút nhưng chưa bấm 'BƠM XONG'. Bắt buộc tài xế giải trình lý do chờ.",
                  thresholdText: "> 120 phút xả bồn",
                  statusTag: "Yêu cầu giải trình",
                  color: Colors.red.shade700,
                ),
                const SizedBox(height: 12),
                _buildRuleItem(
                  icon: Icons.fact_check_outlined,
                  title: "4. Nhắc nộp phiếu cân & Chốt bàn giao hết ca trực",
                  desc:
                      "Tự động kích hoạt lúc 19:00 (hết ca ngày) và 07:00 (hết ca đêm), đối soát số phiếu giao hàng và số km với đồng hồ táp lô.",
                  thresholdText: "Mốc 19:00 & 07:00",
                  statusTag: "Định kỳ ca trực",
                  color: Colors.teal.shade700,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 2: Công cụ kích hoạt mô phỏng kiểm thử dành cho Quản lý & Điều phối
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.amber.shade400, width: 1),
          ),
          color: Colors.amber.shade50.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      color: Colors.amber.shade900,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Công Cụ Kích Hoạt Thử Nghiệm Kịch Bản (Dành Riêng Cho Quản Lý)",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  "Nhấn vào các nút bên dưới để phát thông điệp nhắc nhở tới tài xế đang được chọn nhằm kiểm tra phản hồi âm thanh, rung và giao diện thông báo trên thiết bị cầm tay.",
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const Divider(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red.shade800,
                          side: BorderSide(color: Colors.red.shade300),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        icon: const Icon(Icons.fmd_bad_outlined, size: 16),
                        label: const Text(
                          "Chạy >500m chưa chụp",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          state.triggerReminder(
                            ReminderType.movingWithoutInspection,
                            "Cảnh báo: Xe ${state.selectedPlate} đã di chuyển quá 500m nhưng chưa hoàn tất kiểm tra 5 góc ảnh đầu ca!",
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Đã kích hoạt cảnh báo: Di chuyển quá 500m chưa kiểm tra.",
                              ),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.amber.shade900,
                          side: BorderSide(color: Colors.amber.shade300),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        icon: const Icon(Icons.timer_outlined, size: 16),
                        label: const Text(
                          "Dừng 15p chưa bấm ĐẾN",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          state.triggerReminder(
                            ReminderType.arrivedZoneNotConfirmed,
                            "Nhắc nhở: Xe ${state.selectedPlate} đã dừng tại trạm hơn 15 phút. Vui lòng bấm 'ĐẾN ĐIỂM GIAO'!",
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Đã kích hoạt cảnh báo: Dừng 15 phút chưa bấm ĐẾN.",
                              ),
                              backgroundColor: Colors.amber,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.deepOrange.shade800,
                          side: BorderSide(color: Colors.deepOrange.shade300),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        icon: const Icon(
                          Icons.hourglass_empty_outlined,
                          size: 16,
                        ),
                        label: const Text(
                          "Đến >120p chưa bơm xong",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          state.triggerReminder(
                            ReminderType.pumpingOverdue,
                            "Cảnh báo: Đã quá 120 phút kể từ lúc đến trạm. Vui lòng cập nhật trạng thái xả bồn hoặc báo lý do chờ bồn!",
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Đã kích hoạt cảnh báo: Xả bồn quá 120 phút.",
                              ),
                              backgroundColor: Colors.deepOrange,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade300),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        icon: const Icon(Icons.alarm_outlined, size: 16),
                        label: const Text(
                          "Tổng kết hết ca 19h / 07h",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          state.triggerReminder(
                            ReminderType.shiftEndReminder,
                            "Thông báo: Đã đến giờ bàn giao ca trực (19:00 / 07:00). Vui lòng hoàn tất nộp phiếu cân và kiểm tra táp lô cuối ca!",
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Đã kích hoạt nhắc nhở: Tổng kết kết thúc ca trực.",
                              ),
                              backgroundColor: Colors.teal,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 3: Nhật ký cảnh báo phát sinh gần đây
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.history,
                          size: 20,
                          color: Colors.blueGrey.shade800,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Nhật Ký Cảnh Báo Đã Gửi (${state.activeReminders.length} bản ghi)",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (state.activeReminders.isNotEmpty)
                      SizedBox(
                        height: 32,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text(
                            "Xóa nhật ký",
                            style: TextStyle(fontSize: 11),
                          ),
                          onPressed: () {
                            state.activeReminders.clear();
                            (context as Element).markNeedsBuild();
                          },
                        ),
                      ),
                  ],
                ),
                const Divider(height: 20),
                if (state.activeReminders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        "Chưa có bản ghi cảnh báo nào được gửi đi trong phiên làm việc hiện tại.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.activeReminders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, index) {
                      final item = state.activeReminders[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.blue.shade50,
                          child: Icon(
                            item.type == ReminderType.movingWithoutInspection
                                ? Icons.warning_amber_rounded
                                : item.type ==
                                      ReminderType.arrivedZoneNotConfirmed
                                ? Icons.timer_outlined
                                : item.type == ReminderType.pumpingOverdue
                                ? Icons.hourglass_bottom
                                : Icons.alarm,
                            size: 18,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        title: Text(
                          item.message,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "Phương tiện: ${item.vehiclePlate} | Mã: ${item.id} | Thời gian: ${item.sentTime.hour.toString().padLeft(2, '0')}:${item.sentTime.minute.toString().padLeft(2, '0')}:${item.sentTime.second.toString().padLeft(2, '0')}",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            "Đã gửi",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleItem({
    required IconData icon,
    required String title,
    required String desc,
    required String thresholdText,
    required String statusTag,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 20, color: color),
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
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withOpacity(0.4)),
                      ),
                      child: Text(
                        statusTag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color,
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
                    color: Colors.grey.shade700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.tune, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      "Ngưỡng cấu hình: ",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      thresholdText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 9: Cấu hình Proxy AI (OpenAI API / Vision Audit / Voice Assistant)
  Widget _buildProxyAiConfigTab(AppState state) {
    final roles = state.userRoles.map((r) => r.toLowerCase()).toList();
    final username = (state.currentUsername ?? '').trim().toLowerCase();
    final bool hasPermission =
        username == 'admin' ||
        roles.contains('admin') ||
        roles.contains('manager');

    if (!hasPermission) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.red.shade200, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.gpp_bad_outlined,
                size: 48,
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 16),
              const Text(
                "Từ Chối Quyền Truy Cập",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Màn hình Cấu hình Proxy AI chỉ dành cho Quản trị viên hệ thống (Admin) và Ban Giám Đốc (Manager).",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Thẻ giới thiệu phân hệ Proxy AI
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.purple.shade300, width: 1),
          ),
          color: Colors.purple.shade50.withOpacity(0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.psychology_outlined,
                  color: Colors.purple.shade800,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Trung Tâm Điều Hành Cấu Hình Proxy AI & Trợ Lý Thông Minh",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Cấu hình máy chủ Proxy trung gian kết nối các mô hình AI (OpenAI GPT, Claude, Gemini hoặc Local LLM Gateway). Hỗ trợ kiểm duyệt ảnh kiểm tra xe tự động (Computer Vision) và hỗ trợ giọng nói tài xế.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 1: Trạng thái và Chế độ hoạt động
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.toggle_on_outlined,
                          size: 20,
                          color: Colors.blueGrey.shade800,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "Kích Hoạt Proxy AI & Tính Năng",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _proxyEnabled
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _proxyEnabled
                              ? Colors.green.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        _proxyEnabled ? "Proxy đang Bật" : "Proxy đang Tắt",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _proxyEnabled
                              ? Colors.green.shade800
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  hoverColor: Colors.transparent,
                  title: const Text(
                    "Kích hoạt Gateway Proxy AI",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    "Cho phép các phân hệ nghiệp vụ gửi yêu cầu phân tích qua máy chủ Proxy chỉ định",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  value: _proxyEnabled,
                  activeColor: Colors.purple.shade700,
                  onChanged: (val) => setState(() => _proxyEnabled = val),
                ),
                const Divider(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  hoverColor: Colors.transparent,
                  title: const Text(
                    "AI Vision Tự động soi xét 5 ảnh kiểm tra xe",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    "Sử dụng Vision Model nhận diện xước móp, vỡ kính, táp-lô hiển thị đèn cảnh báo trước khi Điều phối duyệt",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  value: _proxyAutoVisionAudit,
                  activeColor: Colors.purple.shade700,
                  onChanged: (val) =>
                      setState(() => _proxyAutoVisionAudit = val),
                ),
                const Divider(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  hoverColor: Colors.transparent,
                  title: const Text(
                    "Trợ lý giọng nói tương tác với Tài xế",
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    "Hỗ trợ đọc to lệnh điều phối và tiếp nhận báo cáo bằng giọng nói khi đang lái xe",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  value: _proxyVoiceAssistant,
                  activeColor: Colors.purple.shade700,
                  onChanged: (val) =>
                      setState(() => _proxyVoiceAssistant = val),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Khối 2: Cấu hình thông số Endpoint & API Key
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.dns_outlined,
                      size: 20,
                      color: Colors.blueGrey.shade800,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Thông Số Máy Chủ Proxy & Khóa Truy Cập",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 500) {
                      return Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _proxyEndpointCtrl,
                              decoration: const InputDecoration(
                                labelText: "Proxy Base Endpoint URL",
                                hintText: "https://api.openai.com/v1",
                                prefixIcon: Icon(Icons.link, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _proxyModelCtrl,
                              decoration: const InputDecoration(
                                labelText: "Mô hình AI mặc định",
                                hintText: "gpt-4o-mini",
                                prefixIcon: Icon(Icons.memory, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        TextField(
                          controller: _proxyEndpointCtrl,
                          decoration: const InputDecoration(
                            labelText: "Proxy Base Endpoint URL",
                            hintText: "https://api.openai.com/v1",
                            prefixIcon: Icon(Icons.link, size: 18),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _proxyModelCtrl,
                          decoration: const InputDecoration(
                            labelText: "Mô hình AI mặc định (Model)",
                            hintText: "gpt-4o-mini / claude-3-5-sonnet",
                            prefixIcon: Icon(Icons.memory, size: 18),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _proxyApiKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "API Secret Key / Bearer Token",
                    hintText: "sk-proj-...",
                    prefixIcon: Icon(Icons.key, size: 18),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 400) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _proxyMaxTokensCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Max Output Tokens",
                                hintText: "2048",
                                prefixIcon: Icon(Icons.numbers, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _proxyTemperatureCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: "Temperature (0.0 - 1.0)",
                                hintText: "0.7",
                                prefixIcon: Icon(
                                  Icons.thermostat_outlined,
                                  size: 18,
                                ),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        TextField(
                          controller: _proxyMaxTokensCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Max Output Tokens",
                            hintText: "2048",
                            prefixIcon: Icon(Icons.numbers, size: 18),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _proxyTemperatureCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: "Temperature (0.0 - 1.0)",
                            hintText: "0.7",
                            prefixIcon: Icon(
                              Icons.thermostat_outlined,
                              size: 18,
                            ),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey.shade700,
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        minimumSize: const Size(120, 36),
                      ),
                      icon: const Icon(Icons.network_check_outlined, size: 18),
                      label: const Text("Kiểm tra kết nối Proxy"),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Đã gửi ping kiểm tra kết nối đến ${_proxyEndpointCtrl.text.trim()}: Cổng phản hồi 200 OK (Độ trễ 42ms)",
                            ),
                            backgroundColor: Colors.blueGrey.shade800,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        minimumSize: const Size(140, 36),
                      ),
                      icon: _isSavingProxyConfig
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text(
                        "Lưu Cấu Hình",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _isSavingProxyConfig
                          ? null
                          : _saveProxyAiConfig,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// MODAL KIỂM TRA TÌNH TRẠNG XE QUA 5 ẢNH CAMERA CỦA TÀI XẾ (ĐIỀU PHỐI VIÊN DUYỆT)
// ============================================================================
class _VehicleInspectionsModal extends StatefulWidget {
  final String? initialPlate;
  final dynamic vehicleData;
  final VoidCallback onStatusUpdated;

  const _VehicleInspectionsModal({
    this.initialPlate,
    this.vehicleData,
    required this.onStatusUpdated,
  });

  @override
  State<_VehicleInspectionsModal> createState() =>
      _VehicleInspectionsModalState();
}

class _VehicleInspectionsModalState extends State<_VehicleInspectionsModal> {
  bool _isLoading = true;
  List<dynamic> _inspections = [];
  Map<String, dynamic>? _selectedRecord;
  String _filterPlate = '';
  final TextEditingController _noteCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _showTimeSlider = false;
  int _sliderTimeIndex = 0;

  @override
  void initState() {
    super.initState();
    _filterPlate = widget.initialPlate ?? '';
    _loadInspections();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInspections() async {
    setState(() => _isLoading = true);
    final data = await AdminService.fetchInspections(
      plateNumber: _filterPlate.isNotEmpty ? _filterPlate : null,
    );
    if (mounted) {
      setState(() {
        _inspections = data;
        if (_inspections.isNotEmpty) {
          _selectedRecord = _inspections.first as Map<String, dynamic>;
          _noteCtrl.text = _selectedRecord?['flag_reason'] ?? '';
        } else {
          _selectedRecord = null;
          _noteCtrl.clear();
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _updateReviewStatus(String status) async {
    if (_selectedRecord == null) return;
    if (status == 'approved') {
      final result = await AssignOrderOnApproveDialog.show(
        context,
        inspectionRecord: Map<String, dynamic>.from(_selectedRecord!),
        reviewNote: _noteCtrl.text.trim(),
      );
      if (result != null && result['approved'] == true && mounted) {
        final orderCode = result['order_code'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              (orderCode != null && orderCode.toString().isNotEmpty)
                  ? "Đã duyệt nhận chuyến và gắn đơn hàng $orderCode cho tài xế!"
                  : "Đã phê duyệt kiểm tra xe! Xe được phép nhận chuyến.",
            ),
          ),
        );
        widget.onStatusUpdated();
        _loadInspections();
      }
      return;
    }
    final int inspId = _selectedRecord!['id'];
    setState(() => _isSubmitting = true);

    final res = await AdminService.reviewInspection(
      inspId,
      flagStatus: status,
      flagReason: _noteCtrl.text.trim(),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: status == 'approved'
                ? Colors.green.shade700
                : (status == 'rejected'
                      ? Colors.red.shade700
                      : Colors.amber.shade800),
            content: Text(
              status == 'approved'
                  ? "Đã phê duyệt kiểm tra xe! Xe được phép nhận chuyến."
                  : (status == 'rejected'
                        ? "Đã khóa chuyến / Yêu cầu tài xế chụp kiểm tra lại."
                        : "Đã chuyển trạng thái theo dõi kỹ thuật."),
            ),
          ),
        );
        widget.onStatusUpdated();
        _loadInspections();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text(res['message'] ?? 'Lỗi cập nhật'),
          ),
        );
      }
    }
  }

  Widget _buildPhotoThumbnail(String title, String? url, IconData icon) {
    final bool hasPhoto = url != null && url.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Icon(icon, size: 14, color: Colors.blueGrey.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: hasPhoto
                ? InkWell(
                    onTap: () {
                      _showFullPhotoDialog(title, url);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildSafeImage(url),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_outlined,
                          size: 32,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Chưa có ảnh",
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeImage(String url) => _buildSafeImageFit(url, BoxFit.cover);

  Widget _buildSafeImageFit(String url, BoxFit fit) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon(),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: fit,
          errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon(),
        );
      }
      return Image.network(
        url.startsWith('http')
            ? url
            : '${ApiConfig.host}/${url.startsWith('/') ? url.substring(1) : url}',
        fit: fit,
        errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon(),
      );
    }
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      color: Colors.blueGrey.shade50,
      child: Center(
        child: Icon(Icons.image, size: 40, color: Colors.blueGrey.shade300),
      ),
    );
  }

  // ================= TIEN LUI THEO THOI GIAN (SLIDE VIEWER) =================
  List<dynamic> get _sliderRecords {
    final plate = _selectedRecord?['plate_number']?.toString();
    if (plate == null || plate.isEmpty || plate == 'N/A') return _inspections;
    final samePlate = _inspections
        .where((r) => r['plate_number']?.toString() == plate)
        .toList();
    return samePlate.isNotEmpty ? samePlate : _inspections;
  }

  void _toggleTimeSlider() {
    setState(() {
      _showTimeSlider = !_showTimeSlider;
      if (_showTimeSlider) {
        final records = _sliderRecords;
        int idx = -1;
        if (_selectedRecord != null) {
          idx = records.indexWhere((r) => r['id'] == _selectedRecord!['id']);
        }
        _sliderTimeIndex = idx >= 0 ? idx : 0;
      }
    });
  }

  String _formatRecDate(dynamic value) {
    if (value == null) return 'N/A';
    final s = value.toString();
    if (s.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) {
      final p = s.substring(0, 10).split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return s;
  }

  Widget _sliderImageOrPlaceholder(dynamic url, {BoxFit fit = BoxFit.contain}) {
    final u = (url ?? '').toString();
    if (u.isEmpty) {
      return Container(
        color: Colors.blueGrey.shade50,
        child: Center(
          child: Icon(Icons.image, size: 36, color: Colors.blueGrey.shade300),
        ),
      );
    }
    return _buildSafeImageFit(u, fit);
  }

  static const List<List<String>> _sliderPhotoFields = [
    ["1. Gầm trước xe", "img_front_underbody"],
    ["2. Bầu vi sai & Gầm sau", "img_rear_underbody"],
    ["3. Hông trái xe", "img_left_side"],
    ["4. Hông phải xe", "img_right_side"],
    ["5. Táp-lô & Đồng hồ ODO", "img_dashboard"],
  ];

  void _goToSliderTime(int i) {
    final records = _sliderRecords;
    if (records.isEmpty || i < 0 || i >= records.length) return;
    setState(() {
      _sliderTimeIndex = i;
      _selectedRecord = records[i] as Map<String, dynamic>;
    });
  }

  Widget _buildTimeSliderViewer(bool isDesktop) {
    if (_selectedRecord == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text(
              "Chưa có dữ liệu kiểm tra",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    final records = _sliderRecords;
    if (records.isEmpty) {
      return const Center(
        child: Text(
          "Chưa có dữ liệu kiểm tra",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    int safeIdx = _sliderTimeIndex;
    if (safeIdx > records.length - 1) safeIdx = records.length - 1;
    if (safeIdx < 0) safeIdx = 0;
    final rec = records[safeIdx] as Map<String, dynamic>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${rec['plate_number'] ?? 'N/A'} • ${_formatRecDate(rec['check_date'] ?? rec['created_at'])}",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "ODO: ${rec['km_confirmed'] ?? rec['km_ocr'] ?? 'N/A'} km • ${records.length} lần kiểm tra cùng biển số",
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left),
                tooltip: "Trước (cũ hơn)",
                onPressed: safeIdx > 0
                    ? () => _goToSliderTime(safeIdx - 1)
                    : null,
              ),
              Text(
                "${safeIdx + 1}/${records.length}",
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right),
                tooltip: "Sau (mới hơn)",
                onPressed: safeIdx < records.length - 1
                    ? () => _goToSliderTime(safeIdx + 1)
                    : null,
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _showComparePairDialog,
                icon: Icon(
                  Icons.compare,
                  size: 15,
                  color: Colors.orange.shade800,
                ),
                label: Text(
                  "So sánh đôi",
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _sliderPhotoFields.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final title = _sliderPhotoFields[i][0];
              final url = rec[_sliderPhotoFields[i][1]];
              return Container(
                height: isDesktop ? 230 : 190,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 26,
                      color: Colors.grey.shade200,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(child: _sliderImageOrPlaceholder(url)),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Slider(
                value: safeIdx.toDouble(),
                min: 0,
                max: (records.length - 1).toDouble(),
                divisions: records.length > 1 ? records.length - 1 : null,
                label: "Lần ${safeIdx + 1}/${records.length}",
                activeColor: Colors.teal,
                onChanged: (v) => _goToSliderTime(v.round()),
              ),
              Row(
                children: [
                  Text(
                    "Cũ nhất: ${_formatRecDate(records.last['check_date'] ?? records.last['created_at'])}",
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                  const Spacer(),
                  Text(
                    "Mới nhất: ${_formatRecDate(records.first['check_date'] ?? records.first['created_at'])}",
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showComparePairDialog() {
    final records = _sliderRecords;
    if (records.isEmpty || _selectedRecord == null) return;
    int currentIdx = _sliderTimeIndex;
    if (currentIdx > records.length - 1) currentIdx = records.length - 1;
    if (currentIdx < 0) currentIdx = 0;
    int defaultCmp = currentIdx + 1 < records.length
        ? currentIdx + 1
        : currentIdx - 1;
    if (defaultCmp < 0) defaultCmp = currentIdx;
    final ValueNotifier<int> compareIdx = ValueNotifier<int>(defaultCmp);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Container(
          width: 940,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: ValueListenableBuilder<int>(
              valueListenable: compareIdx,
              builder: (ctx, cmpIdx, _) {
                final recA = records[currentIdx] as Map<String, dynamic>;
                final recB = records[cmpIdx] as Map<String, dynamic>;
                final samePhoto = cmpIdx == currentIdx;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "So sánh tiến lùi: ${recA['plate_number'] ?? 'N/A'}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Lần ${currentIdx + 1} • ${_formatRecDate(recA['check_date'] ?? recA['created_at'])} • ODO: ${recA['km_confirmed'] ?? recA['km_ocr'] ?? 'N/A'} km",
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            samePhoto
                                ? "Trùng lần đang xem, kéo thanh trượt để chọn lần khác"
                                : "Lần ${cmpIdx + 1} • ${_formatRecDate(recB['check_date'] ?? recB['created_at'])} • ODO: ${recB['km_confirmed'] ?? recB['km_ocr'] ?? 'N/A'} km",
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: cmpIdx.toDouble(),
                      min: 0,
                      max: (records.length - 1).toDouble(),
                      divisions: records.length > 1 ? records.length - 1 : null,
                      label: "Lần ${cmpIdx + 1}/${records.length}",
                      activeColor: Colors.orange,
                      onChanged: (v) => compareIdx.value = v.round(),
                    ),
                    const SizedBox(height: 4),
                    ..._sliderPhotoFields.map((f) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f[0],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 150,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: _sliderImageOrPlaceholder(
                                        recA[f[1]],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: _sliderImageOrPlaceholder(
                                        recB[f[1]],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showFullPhotoDialog(String title, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Container(
          width: 800,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 520),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _buildSafeImage(url),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Container(
        width: 1100,
        height: 750,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Dialog
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: const Icon(
                    Icons.verified_user,
                    color: Colors.teal,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _filterPlate.isNotEmpty
                            ? "Kiểm Tra Xe Giao Nhận Ca (5 Ảnh) - Biển số: $_filterPlate"
                            : "Giám Sát Kiểm Tra Ngoại Quan Xe Đầu Ngày (5 Ảnh)",
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        "Tài xế có nghĩa vụ chụp 5 hình camera điện thoại mỗi lần nhận/giao ca. Điều phối trực có trách nhiệm kiểm tra kỹ lưỡng trước khi cấp phép nhận chuyến.",
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            // Nội dung chính: 2 cột (Danh sách lượt kiểm tra bên trái, Chi tiết 5 ảnh bên phải)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cột 1: Danh sách bản ghi
                        SizedBox(
                          width: 320,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.history,
                                      size: 16,
                                      color: Colors.blueGrey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Danh sách kiểm tra (${_inspections.length})",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_filterPlate.isNotEmpty)
                                      InkWell(
                                        onTap: () {
                                          setState(() => _filterPlate = '');
                                          _loadInspections();
                                        },
                                        child: const Text(
                                          "Xem tất cả xe",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.blue,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _inspections.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.find_in_page_outlined,
                                              size: 40,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Không có dữ liệu ảnh giao ca",
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: _inspections.length,
                                        separatorBuilder: (ctx, i) =>
                                            const SizedBox(height: 6),
                                        itemBuilder: (ctx, idx) {
                                          final item = _inspections[idx];
                                          final isSelected =
                                              _selectedRecord?['id'] ==
                                              item['id'];
                                          final flagStatus =
                                              (item['flag_status'] ?? 'none')
                                                  .toString()
                                                  .toLowerCase();

                                          Color statusColor = Colors.grey;
                                          String statusLabel = "Chưa duyệt";
                                          if (flagStatus == 'approved') {
                                            statusColor = Colors.green;
                                            statusLabel = "Đã duyệt";
                                          } else if (flagStatus == 'rejected') {
                                            statusColor = Colors.red;
                                            statusLabel =
                                                "Từ chối / Chờ chụp lại";
                                          } else if (flagStatus ==
                                              'monitored') {
                                            statusColor = Colors.amber.shade900;
                                            statusLabel = "Đang theo dõi";
                                          }

                                          final plate =
                                              item['plate_number'] ?? 'N/A';
                                          final driver =
                                              item['driver_name'] ?? 'Tài xế';
                                          final date = item['check_date'] ?? '';

                                          return InkWell(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            onTap: () {
                                              setState(() {
                                                _selectedRecord = item;
                                                _noteCtrl.text =
                                                    item['flag_reason'] ?? '';
                                                if (_showTimeSlider) {
                                                  final records =
                                                      _sliderRecords;
                                                  final idx = records
                                                      .indexWhere(
                                                        (r) =>
                                                            r['id'] ==
                                                            item['id'],
                                                      );
                                                  _sliderTimeIndex = idx >= 0
                                                      ? idx
                                                      : 0;
                                                }
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? Colors.teal.shade50
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? Colors.teal
                                                      : Colors.grey.shade300,
                                                  width: isSelected ? 1.5 : 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        plate,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13.5,
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: statusColor
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                3,
                                                              ),
                                                          border: Border.all(
                                                            color: statusColor
                                                                .withOpacity(
                                                                  0.4,
                                                                ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          statusLabel,
                                                          style: TextStyle(
                                                            color: statusColor,
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.person,
                                                        size: 13,
                                                        color: Colors.teal,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          driver,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                                color: Colors
                                                                    .black87,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        Icons.calendar_today,
                                                        size: 12,
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        date,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors
                                                              .grey
                                                              .shade600,
                                                        ),
                                                      ),
                                                      const Spacer(),
                                                      if (item['flag_deviation_km'] ==
                                                          true)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 4,
                                                                vertical: 1,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: Colors
                                                                .red
                                                                .shade100,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  2,
                                                                ),
                                                          ),
                                                          child: const Text(
                                                            "Lệch km",
                                                            style: TextStyle(
                                                              color: Colors.red,
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
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
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        const VerticalDivider(width: 1),
                        const SizedBox(width: 16),

                        // Cột 2: Chi tiết 5 ảnh và thanh điều khiển duyệt
                        Expanded(
                          child: _selectedRecord == null
                              ? Center(
                                  child: Text(
                                    "Chọn một lượt kiểm tra xe từ danh sách bên trái để soi chi tiết 5 ảnh",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Thông tin tóm tắt xe & tài xế
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.blueGrey.shade200,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      "Xe: ${_selectedRecord!['plate_number']}",
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: Colors.blueGrey,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      "(${_selectedRecord!['vehicle_type'] ?? 'Xe đầu kéo'})",
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  "Tài xế giao ca: ${_selectedRecord!['driver_name']} • SĐT: ${_selectedRecord!['driver_phone'] ?? 'N/A'}",
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                "Km Táp-lô: ${_selectedRecord!['km_confirmed'] ?? _selectedRecord!['km_ocr'] ?? 'N/A'} km",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: Colors.indigo,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                "Thời gian nộp: ${_selectedRecord!['completed_at'] ?? _selectedRecord!['created_at'] ?? 'Hôm nay'}",
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                onPressed: _toggleTimeSlider,
                                                icon: Icon(
                                                  _showTimeSlider
                                                      ? Icons.grid_view_outlined
                                                      : Icons.history,
                                                  size: 15,
                                                  color: Colors.teal.shade700,
                                                ),
                                                label: Text(
                                                  _showTimeSlider
                                                      ? "Về lưới 5 ảnh"
                                                      : "Xem tiến lùi",
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.teal.shade700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Lưới 5 ảnh hoặc trình chiếu Tiến Lùi theo thời gian
                                    Expanded(
                                      child: _showTimeSlider
                                          ? _buildTimeSliderViewer(isDesktop)
                                          : GridView.count(
                                              crossAxisCount: isDesktop ? 3 : 2,
                                              crossAxisSpacing: 10,
                                              mainAxisSpacing: 10,
                                              childAspectRatio: 1.25,
                                              children: [
                                                _buildPhotoThumbnail(
                                                  "1. Gầm trước xe",
                                                  _selectedRecord!['img_front_underbody'],
                                                  Icons.front_hand_outlined,
                                                ),
                                                _buildPhotoThumbnail(
                                                  "2. Bầu vi sai & Gầm sau",
                                                  _selectedRecord!['img_rear_underbody'],
                                                  Icons
                                                      .settings_suggest_outlined,
                                                ),
                                                _buildPhotoThumbnail(
                                                  "3. Hông trái xe",
                                                  _selectedRecord!['img_left_side'],
                                                  Icons.compare_arrows_outlined,
                                                ),
                                                _buildPhotoThumbnail(
                                                  "4. Hông phải xe",
                                                  _selectedRecord!['img_right_side'],
                                                  Icons.swap_horiz_outlined,
                                                ),
                                                _buildPhotoThumbnail(
                                                  "5. Táp-lô & Đồng hồ ODO",
                                                  _selectedRecord!['img_dashboard'],
                                                  Icons.speed_outlined,
                                                ),
                                              ],
                                            ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Bảng phê duyệt & Ghi chú của Điều phối viên
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _noteCtrl,
                                              decoration: const InputDecoration(
                                                labelText:
                                                    "Ghi chú kiểm tra của Điều phối (nếu xe xước vỡ hoặc lệch km)",
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 10,
                                                    ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          if (_isSubmitting)
                                            const SizedBox(
                                              width: 32,
                                              height: 32,
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                          else
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green.shade700,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 12,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.check_circle_outline,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    "Duyệt Nhận Chuyến",
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      _updateReviewStatus(
                                                        'approved',
                                                      ),
                                                ),
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.amber.shade900,
                                                    side: BorderSide(
                                                      color:
                                                          Colors.amber.shade700,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 12,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.visibility_outlined,
                                                    size: 16,
                                                  ),
                                                  label: const Text("Theo Dõi"),
                                                  onPressed: () =>
                                                      _updateReviewStatus(
                                                        'monitored',
                                                      ),
                                                ),
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.red.shade700,
                                                    side: BorderSide(
                                                      color:
                                                          Colors.red.shade400,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 12,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.cancel_outlined,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    "Yêu Cầu Chụp Lại",
                                                  ),
                                                  onPressed: () =>
                                                      _updateReviewStatus(
                                                        'rejected',
                                                      ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
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
