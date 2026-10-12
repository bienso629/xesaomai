import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';

class DispatchSupervisorScreen extends StatefulWidget {
  final int activeTab;
  final int usersSubTab;
  final ValueChanged<int>? onTabChanged;

  const DispatchSupervisorScreen({
    super.key,
    this.activeTab = 0,
    this.usersSubTab = 0,
    this.onTabChanged,
  });

  static Future<void> showShiftHistoryDialog(BuildContext context, {Map<String, dynamic>? targetUser}) =>
      _DispatchSupervisorScreenState.showShiftHistoryDialog(context, targetUser: targetUser);

  @override
  State<DispatchSupervisorScreen> createState() => _DispatchSupervisorScreenState();
}

class _DispatchSupervisorScreenState extends State<DispatchSupervisorScreen> {
  bool _isLoading = false;
  Map<String, dynamic> _summary = {};
  List<dynamic> _orders = [];
  List<dynamic> _vehicles = [];
  List<dynamic> _products = [];
  List<dynamic> _gasStations = [];
  List<dynamic> _users = [];
  List<dynamic> _roles = [];
  List<dynamic> _permissions = [];
  List<dynamic> _activeShifts = [];

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

  @override
  void initState() {
    super.initState();
    _loadAllManagementData();
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    _vehicleSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllManagementData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      AdminService.fetchSummary(),
      AdminService.fetchOrders(),
      AdminService.fetchVehicles(),
      AdminService.fetchProducts(),
      AdminService.fetchGasStations(),
      AdminService.fetchUsers(),
      AdminService.fetchRoles(),
      AdminService.fetchPermissions(),
      AdminService.fetchActiveShifts(),
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
        _isLoading = false;
      });
    }
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
        return _buildOrdersTab();
      case 2:
        return _buildVehiclesTab();
      case 3:
        return _buildUserListSubtab();
      case 4:
        return _buildGasStationsTab();
      case 5:
        return _buildProductsTab();
      case 6:
        return _buildRolesSubtab();
      default:
        return _buildOverviewTab(state);
    }
  }

  // TAB 1: Tổng quan điều hành & Báo cáo tuân thủ
  Widget _buildOverviewTab(AppState state) {
    return RefreshIndicator(
      onRefresh: _loadAllManagementData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.hub_outlined, color: Colors.blue),
                      SizedBox(width: 8),
                      Text("Tích hợp Zalo OA & GPS Vietmap / Bình Anh",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Divider(),
                  Text(
                    "• Zalo OA (Group KH Nhơn Trạch): Nhận yêu cầu 55 tấn xi măng lúc 07:15.\n"
                    "• Đề xuất 3 xe gần nhất từ Vietmap/Bình Anh: 51D-928.45 (cách 1.2km) - 51D-772.19 (cách 3.4km) - 60C-441.82 (cách 5.1km).",
                    style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildMetricCard("Tổng người dùng", "${_users.length} tài khoản", Icons.people, Colors.indigo),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard("Tổng phương tiện", "${_summary['total_vehicles'] ?? _vehicles.length} xe", Icons.directions_car, Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard("Đơn hàng hôm nay", "${_summary['total_orders'] ?? _orders.length} đơn", Icons.receipt_long, Colors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  "Tỷ lệ tuân thủ 5 ảnh",
                  _summary['compliance_rate'] ?? "96.4%",
                  Icons.verified_user,
                  Colors.purple,
                  onTap: () => _showVehicleInspectionsDialog(null, null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // KHỐI QUẢN LÝ CA TRỰC ĐIỀU PHỐI (DISPATCHER SHIFTS & ON DUTY)
          _buildActiveDispatchersCard(state),
        ],
      ),
    );
  }

  // TAB 2: Đơn hàng vận tải
  Widget _buildOrdersTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      itemBuilder: (context, index) {
        final o = _orders[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(o['order_code'] ?? 'MÃ ĐƠN HÀNG', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_translateTransportType(o['transport_type']), style: TextStyle(color: Colors.blue.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text("Sản phẩm: ${o['product_name'] ?? 'Vật liệu'} (${o['cargo_weight_tons']} tấn)", style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text("• Nơi nhận: ${o['pickup_address'] ?? 'N/A'}", style: const TextStyle(fontSize: 12, color: Colors.black87)),
                Text("• Điểm giao: ${o['delivery_address'] ?? 'N/A'}", style: const TextStyle(fontSize: 12, color: Colors.black87)),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Xe: ${o['assigned_vehicle_plate'] ?? 'Chưa gán'}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("Tài xế: ${o['driver_name'] ?? 'Nguyễn Văn A'}", style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
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
            final driverName = (v['driver_name'] ?? '').toString().toLowerCase();
            final ownerCompany = (v['owner_company'] ?? '').toString().toLowerCase();

            final match = plate.contains(query) ||
                vtype.contains(query) ||
                driverName.contains(query) ||
                ownerCompany.contains(query);
            if (!match) return false;
          }

          return true;
        }).toList();

        final totalItems = filteredVehicles.length;
        final totalPages = (totalItems / _vehiclePageSize).ceil().clamp(1, 99999);
        final validPage = _vehicleCurrentPage.clamp(1, totalPages);
        final startIndex = totalItems == 0 ? 0 : (validPage - 1) * _vehiclePageSize;
        final endIndex = (startIndex + _vehiclePageSize > totalItems) ? totalItems : startIndex + _vehiclePageSize;
        final paginatedVehicles = totalItems == 0 ? [] : filteredVehicles.sublist(startIndex, endIndex);

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
                      height: 44,
                      child: TextField(
                        controller: _vehicleSearchCtrl,
                        onChanged: (val) {
                          setState(() {
                            _vehicleSearchQuery = val;
                            _vehicleCurrentPage = 1;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "Tìm theo biển số xe, loại xe, tài xế phụ trách...",
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _vehicleSearchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _vehicleSearchCtrl.clear();
                                    setState(() {
                                      _vehicleSearchQuery = '';
                                      _vehicleCurrentPage = 1;
                                    });
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Bộ lọc theo Hình thức sở hữu
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 44,
                      child: DropdownButtonFormField<String>(
                        value: _selectedOwnershipFilter,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.filter_alt_outlined, size: 20),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text("Tất cả sở hữu")),
                          DropdownMenuItem(value: 'INTERNAL', child: Text("Xe nội bộ")),
                          DropdownMenuItem(value: 'RENTAL', child: Text("Xe thuê ngoài")),
                          DropdownMenuItem(value: 'CUSTOMER_SELF', child: Text("Xe khách hàng")),
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
                  const SizedBox(width: 14),
                  // Thống kê số lượng phương tiện
                  Text(
                    "(${filteredVehicles.length}/${_vehicles.length} phương tiện)",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                  ),
                  const SizedBox(width: 14),
                  // Nút làm mới dữ liệu
                  SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue.shade800,
                        side: BorderSide(color: Colors.blue.shade300),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text("Tải lại danh sách", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      onPressed: _loadAllManagementData,
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
                          Icon(Icons.no_transfer, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            "Không tìm thấy phương tiện nào phù hợp với bộ lọc",
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
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
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                                headingRowHeight: 44,
                                dividerThickness: 0,
                                dataRowMaxHeight: 64,
                                dataRowMinHeight: 58,
                                horizontalMargin: 16,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(label: Text("Biển số xe", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataColumn(label: Text("Loại phương tiện", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataColumn(label: Text("Hình thức sở hữu", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataColumn(label: Text("Tài xế chỉ định", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataColumn(label: Text("Đơn vị quản lý", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataColumn(label: Text("Trạng thái", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                  DataColumn(label: Text("Thao tác", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                ],
                                rows: List.generate(paginatedVehicles.length, (idx) {
                                  final v = paginatedVehicles[idx];
                                  final rowColor = idx % 2 == 0 ? Colors.white : Colors.grey.shade50;
                                  final plate = (v['plate_number'] ?? 'N/A').toString();
                                  final vtype = (v['vehicle_type'] ?? 'Xe tải').toString();
                                  final ownType = (v['ownership_type'] ?? 'INTERNAL').toString();
                                  final driverName = (v['driver_name'] ?? '').toString();
                                  final driverUsername = (v['driver_username'] ?? '').toString();
                                  final driverPhone = (v['driver_phone'] ?? '').toString();
                                  final ownerCompany = (v['owner_company'] ?? 'Sao Mai Logistics').toString();

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
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Icon(Icons.local_shipping, size: 18, color: Colors.blue),
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
                                          ],
                                        ),
                                      ),
                                      // Cột 2: Loại phương tiện
                                      makeCell(
                                        Text(vtype, style: const TextStyle(fontSize: 12.5)),
                                      ),
                                      // Cột 3: Hình thức sở hữu
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: ownBg,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: ownBorder),
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
                                                borderRadius: BorderRadius.circular(4),
                                                onTap: () {
                                                  final driverId = v['default_driver_id'];
                                                  dynamic matchedUser;
                                                  if (driverId != null) {
                                                    for (final u in _users) {
                                                      if (u is Map && u['id'] == driverId) {
                                                        matchedUser = u;
                                                        break;
                                                      }
                                                    }
                                                  }
                                                  if (matchedUser == null && driverUsername.isNotEmpty) {
                                                    for (final u in _users) {
                                                      if (u is Map && u['username'] == driverUsername) {
                                                        matchedUser = u;
                                                        break;
                                                      }
                                                    }
                                                  }
                                                  if (matchedUser != null) {
                                                    _showEditUserDialog(Map<String, dynamic>.from(matchedUser as Map));
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        backgroundColor: Colors.orange,
                                                        content: Text("Không tìm thấy thông tin tài khoản người dùng."),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.person, size: 15, color: Colors.teal),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            driverName,
                                                            style: const TextStyle(
                                                              fontSize: 12.5,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.teal,
                                                              decoration: TextDecoration.underline,
                                                              decorationColor: Colors.teal,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          if (driverUsername.isNotEmpty)
                                                            Text(
                                                              "@$driverUsername",
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors.blueGrey.shade700,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          if (driverUsername.isNotEmpty && driverPhone.isNotEmpty)
                                                            Text(
                                                              " • ",
                                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                                            ),
                                                          if (driverPhone.isNotEmpty)
                                                            Text(
                                                              driverPhone,
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors.grey.shade600,
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
                                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                                        ),
                                      ),
                                      // Cột 6: Trạng thái
                                      makeCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.green.shade200),
                                          ),
                                          child: Text(
                                            "Sẵn sàng hoạt động",
                                            style: TextStyle(
                                              color: Colors.green.shade800,
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
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.teal.shade700,
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              ),
                                              icon: const Icon(Icons.photo_library_outlined, size: 14),
                                              label: const Text("5 Ảnh", style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                              onPressed: () => _showVehicleInspectionsDialog(plate, v),
                                            ),
                                            const SizedBox(width: 6),
                                            OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.blue.shade800,
                                                side: BorderSide(color: Colors.blue.shade300),
                                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                                minimumSize: const Size(0, 32),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              ),
                                              icon: const Icon(Icons.edit, size: 14),
                                              label: const Text("Sửa", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                              onPressed: () => _showEditVehicleDialog(v),
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
                  border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Thông tin số bản ghi hiển thị
                    Text(
                      "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems phương tiện",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                    // Cụm điều khiển: Chọn PageSize + Các nút chuyển trang
                    Row(
                      children: [
                        const Text("Số dòng/trang: ", style: TextStyle(fontSize: 12, color: Colors.black87)),
                        const SizedBox(width: 4),
                        DropdownButton<int>(
                          value: _vehiclePageSize,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold),
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
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                        final roleCodes = (u['role_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                        if (!roleCodes.contains(_selectedRoleFilter)) {
                          return false;
                        }
                      }

                      // 2. Kiểm tra từ khóa tìm kiếm (Search Query)
                      if (query.isNotEmpty) {
                        final username = (u['username'] ?? '').toString().toLowerCase();
                        final fullName = (u['full_name'] ?? '').toString().toLowerCase();
                        final phone = (u['phone'] ?? '').toString().toLowerCase();
                        final roleNames = ((u['role_names'] as List<dynamic>?)?.join(' ') ?? '').toLowerCase();
                        final address = (u['address'] ?? '').toString().toLowerCase();
                        final email = (u['email'] ?? '').toString().toLowerCase();

                        final match = username.contains(query) ||
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
                    final startIndex = totalItems == 0 ? 0 : (validPage - 1) * _userPageSize;
                    final endIndex = (startIndex + _userPageSize > totalItems) ? totalItems : startIndex + _userPageSize;
                    final paginatedUsers = totalItems == 0 ? [] : filteredUsers.sublist(startIndex, endIndex);

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
                                  height: 44,
                                  child: TextField(
                                    controller: _userSearchCtrl,
                                    onChanged: (val) {
                                      setState(() {
                                        _userSearchQuery = val;
                                        _userCurrentPage = 1;
                                      });
                                    },
                                    decoration: InputDecoration(
                                      hintText: "Tìm theo tên, username, số điện thoại, email...",
                                      hintStyle: const TextStyle(fontSize: 13),
                                      prefixIcon: const Icon(Icons.search, size: 20),
                                      suffixIcon: _userSearchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear, size: 18),
                                              onPressed: () {
                                                _userSearchCtrl.clear();
                                                setState(() {
                                                  _userSearchQuery = '';
                                                  _userCurrentPage = 1;
                                                });
                                              },
                                            )
                                          : null,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Bộ lọc theo Vai trò
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 44,
                                  child: DropdownButtonFormField<String>(
                                    value: _selectedRoleFilter,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.filter_list, size: 20),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    ),
                                    items: [
                                      const DropdownMenuItem(value: 'ALL', child: Text("Tất cả vai trò")),
                                      ..._roles.map((r) => DropdownMenuItem(
                                            value: r['code'].toString(),
                                            child: Text(r['name'] ?? r['code']),
                                          )),
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
                              const SizedBox(width: 14),
                              // Thống kê số lượng bản ghi
                              Text(
                                "(${filteredUsers.length}/${_users.length} tài khoản)",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                              ),
                              const SizedBox(width: 14),
                              // Nút Thêm tài khoản mới (Nút nội dòng toolbar: chuẩn chiều cao 38px, không lấn át thị giác)
                              SizedBox(
                                height: 38,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade800,
                                    foregroundColor: Colors.white,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  icon: const Icon(Icons.person_add, size: 16),
                                  label: const Text("Thêm tài khoản mới", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                                      Icon(Icons.search_off, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      Text(
                                        "Không tìm thấy tài khoản người dùng phù hợp",
                                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
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
                                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                          child: DataTable(
                                            headingRowColor: MaterialStateProperty.all(Colors.grey.shade100),
                                            headingRowHeight: 44,
                                            dividerThickness: 0,
                                            dataRowMaxHeight: 76,
                                            dataRowMinHeight: 72,
                                            horizontalMargin: 16,
                                            columnSpacing: 20,
                                            columns: const [
                                              DataColumn(label: Text("Ảnh", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                              DataColumn(label: Text("Tài khoản & Họ tên", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                              DataColumn(label: Text("Số điện thoại", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                              DataColumn(label: Text("Vai trò & Phân loại", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                              DataColumn(label: Text("Trạng thái", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                              DataColumn(label: Text("Lịch sử", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                              DataColumn(label: Text("Thao tác", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                            ],
                                            rows: List.generate(paginatedUsers.length, (rowIndex) {
                                              final u = paginatedUsers[rowIndex];
                                              final roles = (u['role_names'] as List<dynamic>?)?.join(', ') ?? 'Chưa gán vai trò';
                                              final isSystemAdmin = u['username'] == 'admin';
                                              final isLastRow = rowIndex == paginatedUsers.length - 1;
                                              final cellBorder = isLastRow
                                                  ? null
                                                  : Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1));

                                              DataCell makeCell(Widget child, {AlignmentGeometry alignment = Alignment.centerLeft}) {
                                                return DataCell(
                                                  Container(
                                                    alignment: alignment,
                                                    decoration: BoxDecoration(border: cellBorder),
                                                    child: child,
                                                  ),
                                                );
                                              }

                                              return DataRow(
                                                cells: [
                                                  // Cột 1: Avatar 1:1 bo góc 4px
                                                  makeCell(
                                                    Padding(
                                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                                      child: _buildUserAvatarItem(u, size: 52.0),
                                                    ),
                                                  ),
                                                  // Cột 2: Tài khoản & Họ tên
                                                  makeCell(
                                                    Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          u['full_name'] ?? u['username'],
                                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          "(@${u['username']})",
                                                          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                                        ),
                                                        if (u['email'] != null && u['email'].toString().isNotEmpty)
                                                          Text(
                                                            u['email'],
                                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                                                        final roleNames = (u['role_names'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                                                        final roleCodes = (u['role_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                                                        if (roleNames.isEmpty) {
                                                          return const Text("Chưa gán", style: TextStyle(fontSize: 12, color: Colors.grey));
                                                        }
                                                        final isDriver = roleCodes.contains('driver');
                                                        final driverType = u['driver_type'];
                                                        return Wrap(
                                                          spacing: 6,
                                                          runSpacing: 4,
                                                          crossAxisAlignment: WrapCrossAlignment.center,
                                                          children: [
                                                            ...List.generate(roleNames.length, (idx) {
                                                              final name = roleNames[idx];
                                                              final code = idx < roleCodes.length ? roleCodes[idx] : '';
                                                              Color bgColor = Colors.indigo.shade50;
                                                              Color borderColor = Colors.indigo.shade200;
                                                              Color textColor = Colors.indigo.shade800;

                                                              if (code == 'admin') {
                                                                bgColor = Colors.red.shade50;
                                                                borderColor = Colors.red.shade200;
                                                                textColor = Colors.red.shade900;
                                                              } else if (code == 'driver') {
                                                                bgColor = Colors.teal.shade50;
                                                                borderColor = Colors.teal.shade200;
                                                                textColor = Colors.teal.shade900;
                                                              } else if (code == 'gas_station') {
                                                                bgColor = Colors.amber.shade50;
                                                                borderColor = Colors.amber.shade300;
                                                                textColor = Colors.orange.shade900;
                                                              } else if (code == 'dispatcher') {
                                                                bgColor = Colors.blue.shade50;
                                                                borderColor = Colors.blue.shade200;
                                                                textColor = Colors.blue.shade800;
                                                              } else if (code == 'mechanic') {
                                                                bgColor = Colors.purple.shade50;
                                                                borderColor = Colors.purple.shade200;
                                                                textColor = Colors.purple.shade900;
                                                              }

                                                              return Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: bgColor,
                                                                  borderRadius: BorderRadius.circular(4),
                                                                  border: Border.all(color: borderColor),
                                                                ),
                                                                child: Text(
                                                                  name,
                                                                  style: TextStyle(
                                                                    color: textColor,
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              );
                                                            }),
                                                            if (isDriver && driverType != null && driverType.toString().isNotEmpty)
                                                              Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: Colors.blueGrey.shade50,
                                                                  borderRadius: BorderRadius.circular(4),
                                                                  border: Border.all(color: Colors.blueGrey.shade200),
                                                                ),
                                                                child: Text(
                                                                  _translateDriverType(driverType),
                                                                  style: TextStyle(
                                                                    fontSize: 11,
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Colors.blueGrey.shade900,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                  // Cột 6: Trạng thái
                                                  makeCell(
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: u['is_active'] == true ? Colors.green.shade50 : Colors.red.shade50,
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(
                                                          color: u['is_active'] == true ? Colors.green.shade200 : Colors.red.shade200,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        u['is_active'] == true ? "Hoạt động" : "Khóa",
                                                        style: TextStyle(
                                                          color: u['is_active'] == true ? Colors.green.shade800 : Colors.red.shade800,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  // Cột 7: Lịch sử trực ca
                                                  makeCell(
                                                    Builder(
                                                      builder: (context) {
                                                        final roleCodes = (u['role_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                                                        final isDispatcherUser = roleCodes.contains('dispatcher');

                                                        if (isDispatcherUser) {
                                                          return OutlinedButton.icon(
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: Colors.blue.shade900,
                                                              side: BorderSide(color: Colors.blue.shade300),
                                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                                              minimumSize: const Size(0, 32),
                                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                            ),
                                                            icon: const Icon(Icons.history, size: 14),
                                                            label: const Text("Lịch sử ca trực", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                            onPressed: () => showShiftHistoryDialog(context, targetUser: u),
                                                          );
                                                        } else {
                                                          return Text(
                                                            "-",
                                                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
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
                                                            foregroundColor: Colors.blueGrey.shade800,
                                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                                            minimumSize: const Size(0, 32),
                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                          ),
                                                          icon: const Icon(Icons.key, size: 14),
                                                          label: const Text("Mật khẩu", style: TextStyle(fontSize: 11)),
                                                          onPressed: () => _showChangePasswordDialog(u),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        OutlinedButton.icon(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor: Colors.blue.shade800,
                                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                                            minimumSize: const Size(0, 32),
                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                          ),
                                                          icon: const Icon(Icons.edit, size: 14),
                                                          label: const Text("Sửa", style: TextStyle(fontSize: 11)),
                                                          onPressed: () => _showEditUserDialog(u),
                                                        ),
                                                        if (!isSystemAdmin) ...[
                                                          const SizedBox(width: 6),
                                                          OutlinedButton.icon(
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: Colors.red.shade700,
                                                              side: BorderSide(color: Colors.red.shade300),
                                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                                              minimumSize: const Size(0, 32),
                                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                            ),
                                                            icon: const Icon(Icons.delete_outline, size: 14),
                                                            label: const Text("Xóa", style: TextStyle(fontSize: 11)),
                                                            onPressed: () => _confirmDeleteUser(u),
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
                            border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Thông tin số bản ghi hiển thị
                              Text(
                                "Hiển thị ${startIndex + 1} - ${endIndex} trên tổng số ${totalItems} tài khoản",
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                              ),
                              // Cụm điều khiển: Chọn PageSize + Các nút chuyển trang
                              Row(
                                children: [
                                  const Text("Số dòng/trang: ", style: TextStyle(fontSize: 12, color: Colors.black87)),
                                  const SizedBox(width: 4),
                                  DropdownButton<int>(
                                    value: _userPageSize,
                                    underline: const SizedBox(),
                                    isDense: true,
                                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold),
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
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    splashRadius: 16,
                                    onPressed: validPage > 1 ? () => setState(() => _userCurrentPage = 1) : null,
                                  ),
                                  // Nút trang trước
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left, size: 18),
                                    tooltip: "Trang trước",
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    splashRadius: 16,
                                    onPressed: validPage > 1 ? () => setState(() => _userCurrentPage = validPage - 1) : null,
                                  ),
                                  const SizedBox(width: 4),
                                  // Hiển thị số trang hiện tại / tổng số trang
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blue.shade200),
                                    ),
                                    child: Text(
                                      "Trang $validPage / $totalPages",
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Nút trang sau
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right, size: 18),
                                    tooltip: "Trang sau",
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    splashRadius: 16,
                                    onPressed: validPage < totalPages ? () => setState(() => _userCurrentPage = validPage + 1) : null,
                                  ),
                                  // Nút tới trang cuối
                                  IconButton(
                                    icon: const Icon(Icons.last_page, size: 18),
                                    tooltip: "Trang cuối",
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    splashRadius: 16,
                                    onPressed: validPage < totalPages ? () => setState(() => _userCurrentPage = totalPages) : null,
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                            icon: const Icon(Icons.add_moderator, size: 16),
                            label: const Text("Thêm vai trò mới", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                        final permCodes = (r['permission_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                        final permNames = (r['permission_names'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                        final isSystemCore = r['is_system'] == true || ['admin', 'driver', 'dispatcher', 'gas_station', 'mechanic', 'manager'].contains(r['code']);

                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      r['code'] == 'admin' ? Icons.verified_user : Icons.shield_outlined,
                                      color: r['code'] == 'admin' ? Colors.red.shade700 : Colors.indigo,
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
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.grey.shade400),
                                                ),
                                                child: Text(
                                                  "Mã: ${r['code']}",
                                                  style: TextStyle(color: Colors.blueGrey.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              if (isSystemCore) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade50,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.amber.shade300),
                                                  ),
                                                  child: Text(
                                                    "Hệ thống",
                                                    style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          if (r['description'] != null && r['description'].toString().isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              r['description'],
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            minimumSize: const Size(0, 32),
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          icon: const Icon(Icons.tune, size: 14),
                                          label: const Text("Cấu hình quyền", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          onPressed: () => _showEditRoleDialog(r),
                                        ),
                                        if (!isSystemCore) ...[
                                          const SizedBox(width: 8),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.red.shade700,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              minimumSize: const Size(0, 32),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            icon: const Icon(Icons.delete_outline, size: 14),
                                            label: const Text("Xóa", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (permNames.isEmpty)
                                  Text(
                                    "Chưa được cấp bất kỳ quyền nào. Bấm 'Cấu hình quyền' để thêm quyền chức năng.",
                                    style: TextStyle(fontSize: 12, color: Colors.red.shade400, fontStyle: FontStyle.italic),
                                  )
                                else
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: List.generate(permNames.length, (pIdx) {
                                      final pName = permNames[pIdx];
                                      final pCode = pIdx < permCodes.length ? permCodes[pIdx] : '';
                                      
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
                                      } else if (pCode.startsWith('vehicle:') || pCode.startsWith('driver:')) {
                                        chipBg = Colors.blue.shade50;
                                        chipBorder = Colors.blue.shade200;
                                        chipText = Colors.blue.shade900;
                                      } else if (pCode.startsWith('fuel:') || pCode.startsWith('gas_station:')) {
                                        chipBg = Colors.amber.shade50;
                                        chipBorder = Colors.amber.shade200;
                                        chipText = Colors.orange.shade900;
                                      } else if (pCode.startsWith('inspection:')) {
                                        chipBg = Colors.purple.shade50;
                                        chipBorder = Colors.purple.shade200;
                                        chipText = Colors.purple.shade900;
                                      } else if (pCode.startsWith('breakdown:') || pCode.startsWith('maintenance:')) {
                                        chipBg = Colors.brown.shade50;
                                        chipBorder = Colors.brown.shade200;
                                        chipText = Colors.brown.shade900;
                                      } else if (pCode.startsWith('user:') || pCode.startsWith('system:')) {
                                        chipBg = Colors.indigo.shade50;
                                        chipBorder = Colors.indigo.shade200;
                                        chipText = Colors.indigo.shade900;
                                      }

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: chipBg,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: chipBorder),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.check_circle_outline, size: 12, color: Colors.green),
                                            const SizedBox(width: 4),
                                            Text(
                                              pName,
                                              style: TextStyle(color: chipText, fontSize: 11, fontWeight: FontWeight.w600),
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

  // TAB 5: Cây dầu đối soát GPS & Nhiên liệu
  Widget _buildGasStationsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _gasStations.length,
      itemBuilder: (context, index) {
        final gs = _gasStations[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_gas_station, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(gs['name'] ?? 'Tên trạm cấp dầu', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Địa chỉ: ${gs['address']}", style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text("Tọa độ GPS: Lat ${gs['lat']} - Lng ${gs['lng']}", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                Text("Bán kính cho phép đối soát: ${gs['allowed_radius_meters']} mét (Kiểm tra lệch vị trí tự động)", style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ],
            ),
          ),
        );
      },
    );
  }

  // TAB 6: Sản phẩm vật liệu xây dựng
  Widget _buildProductsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final p = _products[index];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.amber.shade100,
              child: const Icon(Icons.category, color: Colors.deepOrange),
            ),
            title: Text(p['name'] ?? 'Tên sản phẩm', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Mã: ${p['code']} | Đơn vị tính: ${p['unit']}\nThời gian bơm chuẩn: ${p['standard_pump_time_minutes']} phút"),
            trailing: p['requires_air_pump'] == true
                ? const Chip(label: Text("Cần máy nén"), backgroundColor: Colors.amber)
                : const Chip(label: Text("Không nén khí")),
          ),
        );
      },
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

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade500),
                ],
              ),
              const SizedBox(height: 10),
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDispatchersCard(AppState state) {
    final currentUserId = state.currentUserId;
    // Nút Nhận ca chỉ dành riêng cho tài khoản có vai trò Điều phối viên (dispatcher)
    // Quản trị viên (admin) và Giám đốc (manager) chỉ được xem, tuyệt đối không hiển thị nút này
    final username = (state.currentUsername ?? '').trim().toLowerCase();
    final userRoles = state.userRoles.map((r) => r.toString().toLowerCase()).toList();
    final bool isDispatcher = userRoles.contains('dispatcher') &&
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.headset_mic, color: Colors.blue.shade800, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Điều phối viên Đang trực ca",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          "Hệ thống cho phép nhiều điều phối viên cùng nhận ca và đồng hành trực tuyến",
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text(
                            "Nhận ca trực",
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _handleCheckinShift(state),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Bạn đang trong ca (${myActiveShift['shift_name'] ?? 'Ca ngày'})",
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade300),
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              icon: const Icon(Icons.logout, size: 15),
                              label: const Text(
                                "Bàn giao / Hết ca",
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                    Icon(Icons.info_outline, size: 18, color: Colors.blueGrey.shade400),
                    const SizedBox(width: 8),
                    Text(
                      "Chưa có điều phối viên nào nhận ca trong thời điểm hiện tại.",
                      style: TextStyle(fontSize: 12.5, color: Colors.blueGrey.shade600),
                    ),
                  ],
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: _activeShifts.map((shift) {
                  final fullName = shift['full_name'] ?? shift['username'] ?? 'Điều phối';
                  final username = shift['username'] ?? '';
                  final phone = shift['phone'] ?? '';
                  final startedAtStr = shift['started_at']?.toString() ?? '';
                  final shiftName = shift['shift_name'] ?? 'Ca ngày';

                  String timeFormatted = '';
                  try {
                    final dt = DateTime.parse(startedAtStr).toLocal();
                    timeFormatted = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day}/${dt.month})";
                  } catch (_) {
                    timeFormatted = startedAtStr;
                  }

                  final bool isMe = shift['user_id'] == currentUserId;

                  return Container(
                    constraints: const BoxConstraints(minWidth: 260),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue.shade50.withOpacity(0.5) : Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isMe ? Colors.blue.shade300 : Colors.grey.shade300,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade700,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      "Tôi",
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "@$username • $shiftName",
                              style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
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
                                  style: TextStyle(fontSize: 10.5, color: Colors.green.shade800, fontWeight: FontWeight.w600),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text("• SĐT: $phone", style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
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
              Text("Nhận ca trực điều phối", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                const Text("Chọn ca trực:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedShift,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Ca ngày', child: Text("Ca ngày (07:00 - 19:00)")),
                    DropdownMenuItem(value: 'Ca đêm', child: Text("Ca đêm (19:00 - 07:00)")),
                    DropdownMenuItem(value: 'Ca tăng cường', child: Text("Ca tăng cường / Giờ cao điểm")),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedShift = val);
                  },
                ),
                const SizedBox(height: 12),
                const Text("Ghi chú bắt đầu ca (nếu có):", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    hintText: "Nhập ghi chú hoặc dặn dò khi nhận ca...",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
          content: Text(res['success'] == true ? "Đã nhận ca trực thành công! Trạng thái đang làm việc đã được cập nhật." : "Lỗi: ${res['message']}"),
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
            Text("Bàn giao ca trực & Kết thúc", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
              const Text("Nội dung bàn giao / Ghi chú ca sau:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  hintText: "Ghi chú đơn hàng cần chú ý, sự cố xe đang theo dõi...",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
          content: Text(res['success'] == true ? "Đã bàn giao và kết thúc ca trực thành công!" : "Lỗi: ${res['message']}"),
        ),
      );
    }
  }

  Future<void> _showShiftHistoryDialog() async {
    showShiftHistoryDialog(context);
  }

  static Future<void> showShiftHistoryDialog(BuildContext context, {Map<String, dynamic>? targetUser}) async {
    final int? filterUserId = targetUser?['id'] as int?;
    final String? filterFullName = targetUser?['full_name'] as String? ?? targetUser?['username'] as String?;

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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: Container(
                width: 980,
                height: 620,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FutureBuilder<List<dynamic>>(
                  future: AdminService.fetchShiftHistory(userId: filterUserId, limit: 100),
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
                                  child: Icon(Icons.history, color: Colors.blue.shade800, size: 22),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      filterFullName != null
                                          ? "Nhật ký & Lịch sử ca trực - $filterFullName"
                                          : "Nhật ký & Lịch sử ca trực Điều phối viên",
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      filterFullName != null
                                          ? "Ghi nhận chi tiết thời gian nhận ca, kết thúc, bàn giao công việc của $filterFullName"
                                          : "Ghi nhận chi tiết thời gian nhận ca, kết thúc, bàn giao công việc của từng điều phối viên",
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.filter_alt, size: 18, color: Colors.blue.shade800),
                              const SizedBox(width: 8),
                              const Text(
                                "Lọc theo ngày:",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: filterDate != null ? Colors.blue.shade600 : Colors.grey.shade400),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.calendar_today, size: 14, color: filterDate != null ? Colors.blue.shade800 : Colors.grey.shade700),
                                      const SizedBox(width: 6),
                                      Text(
                                        filterDate != null
                                            ? "${filterDate!.day.toString().padLeft(2, '0')}/${filterDate!.month.toString().padLeft(2, '0')}/${filterDate!.year}"
                                            : "Tất cả các ngày",
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: filterDate != null ? FontWeight.bold : FontWeight.normal,
                                          color: filterDate != null ? Colors.blue.shade900 : Colors.black87,
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
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: const Icon(Icons.clear, size: 15, color: Colors.red),
                                  label: const Text("Xóa lọc ngày", style: TextStyle(fontSize: 12, color: Colors.red)),
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
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const Expanded(
                            child: Center(
                              child: CircularProgressIndicator(),
                            ),
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
                                  Icon(Icons.event_busy, size: 48, color: Colors.blueGrey.shade300),
                                  const SizedBox(height: 12),
                                  Text(
                                    filterFullName != null
                                        ? "Điều phối viên $filterFullName chưa có lịch sử ca trực nào."
                                        : "Chưa có dữ liệu lịch sử ca trực nào được ghi nhận.",
                                    style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade600),
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
                                  final startedAtStr = shift['started_at']?.toString() ?? '';
                                  if (startedAtStr.isEmpty) return false;
                                  try {
                                    final dt = DateTime.parse(startedAtStr).toLocal();
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
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.search_off, size: 48, color: Colors.blueGrey.shade300),
                                          const SizedBox(height: 12),
                                          Text(
                                            "Không tìm thấy ca trực nào trong ngày ${filterDate!.day.toString().padLeft(2, '0')}/${filterDate!.month.toString().padLeft(2, '0')}/${filterDate!.year}",
                                            style: TextStyle(fontSize: 13.5, color: Colors.blueGrey.shade700),
                                          ),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                              side: BorderSide(color: Colors.blue.shade600, width: 1.2),
                                              foregroundColor: Colors.blue.shade800,
                                            ),
                                            icon: const Icon(Icons.refresh, size: 16),
                                            label: const Text(
                                              "Hiển thị tất cả",
                                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
                                final totalPages = (totalItems / shiftPageSize).ceil();
                                final validPage = shiftCurrentPage > totalPages ? totalPages : (shiftCurrentPage < 1 ? 1 : shiftCurrentPage);
                                final startIndex = (validPage - 1) * shiftPageSize;
                                final endIndex = (startIndex + shiftPageSize > totalItems) ? totalItems : startIndex + shiftPageSize;
                                final pagedShifts = filteredShifts.sublist(startIndex, endIndex);

                                return Column(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                          child: ListView.separated(
                                            itemCount: pagedShifts.length,
                                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                                            itemBuilder: (context, index) {
                                              final shift = pagedShifts[index];
                                              final shiftName = shift['shift_name'] ?? 'Ca ngày';
                                              final status = shift['status'] ?? 'active';
                                              final isActive = status == 'active';
                                              final note = shift['note']?.toString() ?? '';
                                              final handoverNote = shift['handover_note']?.toString() ?? '';
                                              final durationHours = shift['duration_hours']?.toString() ?? '';

                                              final startedAtStr = shift['started_at']?.toString() ?? '';
                                              final endedAtStr = shift['ended_at']?.toString() ?? '';

                                              String startFmt = '-';
                                              if (startedAtStr.isNotEmpty) {
                                                try {
                                                  final dt = DateTime.parse(startedAtStr).toLocal();
                                                  startFmt = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year})";
                                                } catch (_) {
                                                  startFmt = startedAtStr;
                                                }
                                              }

                                              String endFmt = 'Đang trực';
                                              if (endedAtStr.isNotEmpty) {
                                                try {
                                                  final dt = DateTime.parse(endedAtStr).toLocal();
                                                  endFmt = "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year})";
                                                } catch (_) {
                                                  endFmt = endedAtStr;
                                                }
                                              }

                                              return Container(
                                                color: isActive ? Colors.blue.shade50.withOpacity(0.3) : Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                                child: Row(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    // Thông tin ca trực (đã bỏ avatar, tên đầy đủ và username theo yêu cầu)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.shade50,
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: Colors.blue.shade200),
                                                      ),
                                                      child: Text(
                                                        shiftName,
                                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 2: Thời gian bắt đầu
                                                    SizedBox(
                                                      width: 175,
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.login, size: 14, color: Colors.green.shade700),
                                                          const SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              "Bắt đầu: $startFmt",
                                                              style: const TextStyle(fontSize: 12),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
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
                                                          Icon(Icons.logout, size: 14, color: isActive ? Colors.orange.shade700 : Colors.blueGrey.shade700),
                                                          const SizedBox(width: 6),
                                                          Expanded(
                                                            child: Text(
                                                              "Kết thúc: $endFmt",
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: isActive ? Colors.green.shade800 : Colors.black87,
                                                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
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
                                                        durationHours.isNotEmpty ? "Thời lượng: $durationHours giờ" : "-",
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          color: Colors.blueGrey.shade700,
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 5: Ghi chú nhận ca & bàn giao
                                                    Expanded(
                                                      flex: 4,
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          if (note.isNotEmpty)
                                                            Text(
                                                              "Ghi chú nhận ca: $note",
                                                              style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          if (handoverNote.isNotEmpty) ...[
                                                            if (note.isNotEmpty) const SizedBox(height: 4),
                                                            Text(
                                                              "Bàn giao ca sau: $handoverNote",
                                                              style: TextStyle(fontSize: 11.5, color: Colors.teal.shade900, fontWeight: FontWeight.w600),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                          if (note.isEmpty && handoverNote.isEmpty)
                                                            Text(
                                                              "Không có ghi chú",
                                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Cột 6: Tag trạng thái ca
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: isActive ? Colors.green.shade400 : Colors.grey.shade400),
                                                      ),
                                                      child: Text(
                                                        isActive ? "Đang trực" : "Đã hoàn thành",
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                          color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
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
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border(
                                          left: BorderSide(color: Colors.grey.shade300, width: 1),
                                          right: BorderSide(color: Colors.grey.shade300, width: 1),
                                          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                                        ),
                                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            "Hiển thị ${startIndex + 1} - ${endIndex} trên tổng số ${totalItems} ca trực",
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                                          ),
                                          Row(
                                            children: [
                                              const Text("Số dòng/trang: ", style: TextStyle(fontSize: 12, color: Colors.black87)),
                                              const SizedBox(width: 4),
                                              DropdownButton<int>(
                                                value: shiftPageSize,
                                                underline: const SizedBox(),
                                                isDense: true,
                                                style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold),
                                                items: const [
                                                  DropdownMenuItem(value: 5, child: Text("5")),
                                                  DropdownMenuItem(value: 10, child: Text("10")),
                                                  DropdownMenuItem(value: 20, child: Text("20")),
                                                  DropdownMenuItem(value: 50, child: Text("50")),
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
                                                icon: const Icon(Icons.first_page, size: 18),
                                                tooltip: "Trang đầu",
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                splashRadius: 16,
                                                onPressed: validPage > 1 ? () => setDialogState(() => shiftCurrentPage = 1) : null,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.chevron_left, size: 18),
                                                tooltip: "Trang trước",
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                splashRadius: 16,
                                                onPressed: validPage > 1 ? () => setDialogState(() => shiftCurrentPage = validPage - 1) : null,
                                              ),
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.blue.shade200),
                                                ),
                                                child: Text(
                                                  "Trang $validPage / $totalPages",
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(Icons.chevron_right, size: 18),
                                                tooltip: "Trang sau",
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                splashRadius: 16,
                                                onPressed: validPage < totalPages ? () => setDialogState(() => shiftCurrentPage = validPage + 1) : null,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.last_page, size: 18),
                                                tooltip: "Trang cuối",
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                splashRadius: 16,
                                                onPressed: validPage < totalPages ? () => setDialogState(() => shiftCurrentPage = totalPages) : null,
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
          const SnackBar(content: Text("Đang tải ảnh lên máy chủ..."), duration: Duration(seconds: 1)),
        );
        final uploadRes = await AdminService.uploadImage(selectedPath);
        if (uploadRes['success'] == true) {
          setDialogState(() {
            controller.text = uploadRes['url'];
          });
          if (mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(backgroundColor: Colors.green, content: Text("Tải ảnh thành công: ${uploadRes['filename']}")),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(backgroundColor: Colors.red, content: Text("Lỗi: ${uploadRes['message']}")),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text("Không thể mở trình chọn ảnh: $e")),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: Icon(icon, size: 18),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 38, maxHeight: 38),
                    hintText: "Chọn tệp từ máy hoặc nhập URL",
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                label: const Text("Chọn & Tải lên", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                  style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.w600),
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
              Text("Thêm tài khoản mới", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(labelText: "Tên đăng nhập (username) *"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Mật khẩu ban đầu *"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: fullNameCtrl,
                    decoration: const InputDecoration(labelText: "Họ và tên hiển thị *"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: "Số điện thoại liên hệ *"),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRoleCode,
                    decoration: const InputDecoration(labelText: "Vai trò phân quyền"),
                    items: const [
                      DropdownMenuItem(value: "driver", child: Text("Tài xế")),
                      DropdownMenuItem(value: "dispatcher", child: Text("Điều phối")),
                      DropdownMenuItem(value: "gas_station", child: Text("Cây dầu / Trạm cấp nhiên liệu")),
                      DropdownMenuItem(value: "mechanic", child: Text("Kỹ thuật")),
                      DropdownMenuItem(value: "director", child: Text("Ban Giám Đốc / Trưởng BP")),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedRoleCode = val);
                    },
                  ),
                  if (selectedRoleCode == "driver") ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedDriverType,
                      decoration: const InputDecoration(labelText: "Phân loại tài xế"),
                      items: const [
                        DropdownMenuItem(value: "INTERNAL", child: Text("Tài xế công ty (Nội bộ)")),
                        DropdownMenuItem(value: "RENTAL", child: Text("Tài xế thuê ngoài")),
                        DropdownMenuItem(value: "CUSTOMER_SELF", child: Text("Khách hàng tự chở")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedDriverType = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Row(
                      children: const [
                        Icon(Icons.badge_outlined, color: Colors.blueGrey, size: 18),
                        SizedBox(width: 6),
                        Text("Hồ sơ tài xế vận chuyển", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
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
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(
                        labelText: "Địa chỉ thường trú / tạm trú",
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: "E-mail (nếu có)",
                              prefixIcon: Icon(Icons.email_outlined, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: "Tuổi",
                              prefixIcon: Icon(Icons.cake_outlined, size: 20),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: gender,
                            decoration: const InputDecoration(
                              labelText: "Giới tính",
                              prefixIcon: Icon(Icons.wc, size: 20),
                            ),
                            items: const [
                              DropdownMenuItem(value: "Nam", child: Text("Nam")),
                              DropdownMenuItem(value: "Nữ", child: Text("Nữ")),
                              DropdownMenuItem(value: "Khác", child: Text("Khác")),
                            ],
                            onChanged: (val) {
                              if (val != null) setDialogState(() => gender = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Ghi chú",
                        prefixIcon: Icon(Icons.note_alt_outlined),
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
                    const SnackBar(content: Text("Vui lòng điền đủ tên đăng nhập, mật khẩu và họ tên")),
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
                  "driver_type": selectedRoleCode == "driver" ? selectedDriverType : null,
                  "role_codes": [selectedRoleCode],
                };

                if (selectedRoleCode == "driver") {
                  payload["avatar_url"] = avatarCtrl.text.trim().isNotEmpty ? avatarCtrl.text.trim() : null;
                  payload["id_card_front_url"] = idCardFrontCtrl.text.trim().isNotEmpty ? idCardFrontCtrl.text.trim() : null;
                  payload["id_card_back_url"] = idCardBackCtrl.text.trim().isNotEmpty ? idCardBackCtrl.text.trim() : null;
                  payload["address"] = addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null;
                  payload["email"] = emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null;
                  payload["age"] = int.tryParse(ageCtrl.text.trim());
                  payload["gender"] = gender;
                  payload["notes"] = notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null;
                }

                final res = await AdminService.createUser(payload);

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                    content: Text(res['success'] == true ? "Đã tạo tài khoản thành công!" : "Lỗi: ${res['message']}"),
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
    final vtypeCtrl = TextEditingController(text: (v['vehicle_type'] ?? '').toString());
    final ownerCompanyCtrl = TextEditingController(text: (v['owner_company'] ?? 'Sao Mai Logistics').toString());
    String ownershipType = (v['ownership_type'] ?? 'INTERNAL').toString();
    if (!['INTERNAL', 'RENTAL', 'CUSTOMER_SELF'].contains(ownershipType)) {
      ownershipType = 'INTERNAL';
    }
    int? selectedDriverId = v['default_driver_id'] as int?;

    // Lọc danh sách các tài khoản tài xế có thể gán
    final driverUsers = _users.where((u) {
      if (u is! Map) return false;
      final roleCodes = (u['role_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      return roleCodes.contains('driver') || u['driver_type'] != null;
    }).toList();

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
                child: const Icon(Icons.local_shipping, size: 20, color: Colors.blue),
              ),
              const SizedBox(width: 10),
              Text("Chỉnh sửa phương tiện: $plate", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                  TextFormField(
                    initialValue: plate,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: "Biển kiểm soát (Cố định)",
                      prefixIcon: Icon(Icons.pin),
                      filled: true,
                      fillColor: Color(0xFFF1F5F9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Loại phương tiện
                  TextField(
                    controller: vtypeCtrl,
                    decoration: const InputDecoration(
                      labelText: "Loại phương tiện *",
                      hintText: "Ví dụ: Đầu kéo, Xe container, Xe tải...",
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Hình thức sở hữu
                  DropdownButtonFormField<String>(
                    value: ownershipType,
                    decoration: const InputDecoration(
                      labelText: "Hình thức sở hữu *",
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: "INTERNAL", child: Text("Xe nội bộ")),
                      DropdownMenuItem(value: "RENTAL", child: Text("Xe thuê ngoài")),
                      DropdownMenuItem(value: "CUSTOMER_SELF", child: Text("Khách tự vận chuyển")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => ownershipType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Tài xế chỉ định
                  DropdownButtonFormField<int?>(
                    value: selectedDriverId,
                    decoration: const InputDecoration(
                      labelText: "Tài xế chỉ định phụ trách",
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text("Chưa phân bổ tài xế", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                      ),
                      ...driverUsers.map((u) {
                        final id = u['id'] as int;
                        final name = (u['full_name'] ?? u['username'] ?? '').toString();
                        final phone = (u['phone'] ?? '').toString();
                        final label = phone.isNotEmpty ? "$name ($phone)" : name;
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(label),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedDriverId = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  // Đơn vị quản lý
                  TextField(
                    controller: ownerCompanyCtrl,
                    decoration: const InputDecoration(
                      labelText: "Đơn vị quản lý / Công ty sở hữu",
                      hintText: "Ví dụ: Sao Mai Logistics",
                      prefixIcon: Icon(Icons.apartment_outlined),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                minimumSize: const Size(100, 44),
              ),
              onPressed: () async {
                final vtype = vtypeCtrl.text.trim();
                if (vtype.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Vui lòng nhập loại phương tiện")),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final payload = <String, dynamic>{
                  "vehicle_type": vtype,
                  "ownership_type": ownershipType,
                  "default_driver_id": selectedDriverId ?? -1,
                  "owner_company": ownerCompanyCtrl.text.trim().isNotEmpty ? ownerCompanyCtrl.text.trim() : "Sao Mai Logistics",
                };

                final res = await AdminService.updateVehicle(plate, payload);
                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                    content: Text(res['success'] == true ? "Đã cập nhật thông tin phương tiện $plate thành công!" : "Lỗi: ${res['message']}"),
                  ),
                );
              },
              child: const Text("Lưu thay đổi", style: TextStyle(fontWeight: FontWeight.bold)),
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
    final ageCtrl = TextEditingController(text: user['age'] != null ? user['age'].toString() : '');
    final notesCtrl = TextEditingController(text: user['notes'] ?? '');
    final avatarCtrl = TextEditingController(text: user['avatar_url'] ?? '');
    final idCardFrontCtrl = TextEditingController(text: user['id_card_front_url'] ?? '');
    final idCardBackCtrl = TextEditingController(text: user['id_card_back_url'] ?? '');
    String gender = user['gender'] ?? "Nam";
    String selectedDriverType = user['driver_type'] ?? "INTERNAL";
    bool isActive = user['is_active'] ?? true;
    final userRoles = (user['role_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    String selectedRoleCode = userRoles.isNotEmpty ? userRoles.first : "driver";

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
              Text("Chỉnh sửa: @${user['username']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: fullNameCtrl,
                    decoration: const InputDecoration(labelText: "Họ và tên hiển thị *"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: "Số điện thoại *"),
                  ),
                  if (!isSystemAdmin) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRoleCode,
                      decoration: const InputDecoration(labelText: "Vai trò phân quyền"),
                      items: const [
                        DropdownMenuItem(value: "driver", child: Text("Tài xế")),
                        DropdownMenuItem(value: "dispatcher", child: Text("Điều phối")),
                        DropdownMenuItem(value: "gas_station", child: Text("Cây dầu / Trạm cấp nhiên liệu")),
                        DropdownMenuItem(value: "mechanic", child: Text("Kỹ thuật")),
                        DropdownMenuItem(value: "director", child: Text("Ban Giám Đốc / Trưởng BP")),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRoleCode = val);
                      },
                    ),
                    if (selectedRoleCode == "driver") ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedDriverType,
                        decoration: const InputDecoration(labelText: "Phân loại tài xế"),
                        items: const [
                          DropdownMenuItem(value: "INTERNAL", child: Text("Tài xế công ty (Nội bộ)")),
                          DropdownMenuItem(value: "RENTAL", child: Text("Tài xế thuê ngoài")),
                          DropdownMenuItem(value: "CUSTOMER_SELF", child: Text("Khách hàng tự chở")),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedDriverType = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      Row(
                        children: const [
                          Icon(Icons.badge_outlined, color: Colors.blueGrey, size: 18),
                          SizedBox(width: 6),
                          Text("Hồ sơ tài xế vận chuyển", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
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
                      TextField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(
                          labelText: "Địa chỉ thường trú / tạm trú",
                          prefixIcon: Icon(Icons.home_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: "E-mail (nếu có)",
                                prefixIcon: Icon(Icons.email_outlined, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: ageCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: "Tuổi",
                                prefixIcon: Icon(Icons.cake_outlined, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: gender,
                              decoration: const InputDecoration(
                                labelText: "Giới tính",
                                prefixIcon: Icon(Icons.wc, size: 20),
                              ),
                              items: const [
                                DropdownMenuItem(value: "Nam", child: Text("Nam")),
                                DropdownMenuItem(value: "Nữ", child: Text("Nữ")),
                                DropdownMenuItem(value: "Khác", child: Text("Khác")),
                              ],
                              onChanged: (val) {
                                if (val != null) setDialogState(() => gender = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: "Ghi chú",
                          prefixIcon: Icon(Icons.note_alt_outlined),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    hoverColor: Colors.transparent,
                    title: const Text("Trạng thái hoạt động", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(isActive ? "Tài khoản đang được phép đăng nhập" : "Đã khóa tài khoản này"),
                    value: isActive,
                    activeColor: Colors.green,
                    onChanged: isSystemAdmin ? null : (val) => setDialogState(() => isActive = val),
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
                  payload["driver_type"] = selectedRoleCode == "driver" ? selectedDriverType : null;
                  payload["role_codes"] = [selectedRoleCode];
                  if (selectedRoleCode == "driver") {
                    payload["avatar_url"] = avatarCtrl.text.trim().isNotEmpty ? avatarCtrl.text.trim() : null;
                    payload["id_card_front_url"] = idCardFrontCtrl.text.trim().isNotEmpty ? idCardFrontCtrl.text.trim() : null;
                    payload["id_card_back_url"] = idCardBackCtrl.text.trim().isNotEmpty ? idCardBackCtrl.text.trim() : null;
                    payload["address"] = addressCtrl.text.trim().isNotEmpty ? addressCtrl.text.trim() : null;
                    payload["email"] = emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null;
                    payload["age"] = int.tryParse(ageCtrl.text.trim());
                    payload["gender"] = gender;
                    payload["notes"] = notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null;
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
                    backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                    content: Text(res['success'] == true ? "Đã cập nhật thông tin thành công!" : "Lỗi: ${res['message']}"),
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
            Text("Đổi mật khẩu: @${user['username']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Mật khẩu mới *"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Xác nhận mật khẩu mới *"),
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
                  const SnackBar(content: Text("Mật khẩu mới phải có ít nhất 4 ký tự")),
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
                  backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                  content: Text(res['success'] == true ? "Đã đổi mật khẩu cho @${user['username']} thành công!" : "Lỗi: ${res['message']}"),
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
            Text("Xác nhận xóa tài khoản", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                  backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                  content: Text(res['success'] == true ? "Đã xóa tài khoản thành công!" : "Lỗi: ${res['message']}"),
                ),
              );
            },
            child: const Text("Xóa vĩnh viễn"),
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
              Text("Thêm vai trò phân quyền mới", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: "Mã vai trò (code - viết liền, không dấu) *",
                      hintText: "Ví dụ: accountant, supervisor, qc...",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Tên vai trò hiển thị *",
                      hintText: "Ví dụ: Kế toán vận tải, Giám sát kho...",
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: "Mô tả vai trò",
                      hintText: "Mô tả trách nhiệm và nhiệm vụ của vai trò này...",
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Cấp quyền hành động chức năng:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                      ),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            if (selectedPerms.length == _permissions.length) {
                              selectedPerms.clear();
                            } else {
                              selectedPerms.addAll(_permissions.map((p) => p['code'].toString()));
                            }
                          });
                        },
                        child: Text(
                          selectedPerms.length == _permissions.length ? "Bỏ chọn tất cả" : "Chọn tất cả",
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                    border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_getModuleIcon(modKey), size: 16, color: Colors.indigo.shade800),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getModuleLabel(modKey),
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo.shade900),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "(${permsInMod.where((p) => selectedPerms.contains(p['code'])).length}/${permsInMod.length})",
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                                ...permsInMod.map((p) {
                                  final pCode = p['code'].toString();
                                  final pName = p['name'] ?? pCode;
                                  final isChecked = selectedPerms.contains(pCode);

                                  final isUserManage = pCode == 'user:manage';
                                  return CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                                              color: isUserManage ? Colors.grey.shade600 : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isUserManage)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.red.shade200),
                                            ),
                                            child: Text(
                                              "Chỉ Admin tối cao",
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      "Mã: $pCode",
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    onChanged: isUserManage ? null : (val) {
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
                    const SnackBar(content: Text("Vui lòng điền đầy đủ mã và tên vai trò")),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final res = await AdminService.createRole({
                  "code": code,
                  "name": name,
                  "description": descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                  "permission_codes": selectedPerms.toList(),
                });

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                    content: Text(res['success'] == true ? "Đã tạo vai trò mới thành công!" : "Lỗi: ${res['message']}"),
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
    final existingPerms = (role['permission_codes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final selectedPerms = Set<String>.from(existingPerms);
    final isSystemCore = role['is_system'] == true || ['admin', 'driver', 'dispatcher', 'gas_station', 'mechanic', 'manager'].contains(role['code']);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Row(
            children: [
              const Icon(Icons.tune, color: Colors.indigo),
              const SizedBox(width: 8),
              Text("Cấu hình vai trò & quyền: ${role['name']}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          "Mã định danh hệ thống: ${role['code']}${isSystemCore ? ' (Vai trò cốt lõi)' : ''}",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: "Tên vai trò hiển thị *"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: "Mô tả vai trò"),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Danh sách hành động chức năng (${selectedPerms.length}/${_permissions.length}):",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                      ),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            if (selectedPerms.length == _permissions.length) {
                              selectedPerms.clear();
                            } else {
                              selectedPerms.addAll(_permissions.map((p) => p['code'].toString()));
                            }
                          });
                        },
                        child: Text(
                          selectedPerms.length == _permissions.length ? "Bỏ chọn tất cả" : "Chọn tất cả",
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                    border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(_getModuleIcon(modKey), size: 16, color: Colors.indigo.shade800),
                                      const SizedBox(width: 8),
                                      Text(
                                        _getModuleLabel(modKey),
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo.shade900),
                                      ),
                                      const Spacer(),
                                      Text(
                                        "(${permsInMod.where((p) => selectedPerms.contains(p['code'])).length}/${permsInMod.length})",
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                                ...permsInMod.map((p) {
                                  final pCode = p['code'].toString();
                                  final pName = p['name'] ?? pCode;
                                  final isChecked = selectedPerms.contains(pCode);

                                  final isUserManage = pCode == 'user:manage';
                                  final isLocked = isUserManage && role['code'] != 'admin';
                                  return CheckboxListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
                                              color: isLocked ? Colors.grey.shade600 : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        if (isUserManage)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.red.shade200),
                                            ),
                                            child: Text(
                                              "Chỉ Admin tối cao",
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      "Mã: $pCode",
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    onChanged: isLocked ? null : (val) {
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
                    const SnackBar(content: Text("Tên vai trò không được để trống")),
                  );
                  return;
                }

                Navigator.of(dialogCtx).pop();
                setState(() => _isLoading = true);

                final res = await AdminService.updateRole(role['id'], {
                  "name": name,
                  "description": descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                  "permission_codes": selectedPerms.toList(),
                });

                await _loadAllManagementData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                    content: Text(res['success'] == true ? "Đã cập nhật vai trò & quyền thành công!" : "Lỗi: ${res['message']}"),
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
            Text("Xác nhận xóa vai trò", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  backgroundColor: res['success'] == true ? Colors.green : Colors.red,
                  content: Text(res['success'] == true ? "Đã xóa vai trò thành công!" : "Lỗi: ${res['message']}"),
                ),
              );
            },
            child: const Text("Xóa vĩnh viễn"),
          ),
        ],
      ),
    );
  }

  static Widget _buildUserAvatarItem(Map<String, dynamic> u, {double size = 48.0}) {
    final avatarUrl = u['avatar_url']?.toString().trim();
    final isDispatcher = u['role_codes'] != null && (u['role_codes'] as List<dynamic>).contains('dispatcher');
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
    } else if (avatarUrl.startsWith('/uploads/') || avatarUrl.startsWith('uploads/')) {
      final cleanPath = avatarUrl.startsWith('/') ? avatarUrl : '/$avatarUrl';
      imageWidget = Image.network(
        'http://localhost:8000$cleanPath',
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
          'http://localhost:8000/$avatarUrl',
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
        child: AspectRatio(
          aspectRatio: 1.0,
          child: imageWidget,
        ),
      ),
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
  State<_VehicleInspectionsModal> createState() => _VehicleInspectionsModalState();
}

class _VehicleInspectionsModalState extends State<_VehicleInspectionsModal> {
  bool _isLoading = true;
  List<dynamic> _inspections = [];
  Map<String, dynamic>? _selectedRecord;
  String _filterPlate = '';
  final TextEditingController _noteCtrl = TextEditingController();
  bool _isSubmitting = false;

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
            backgroundColor: status == 'approved' ? Colors.green.shade700 : (status == 'rejected' ? Colors.red.shade700 : Colors.amber.shade800),
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
          SnackBar(backgroundColor: Colors.red, content: Text(res['message'] ?? 'Lỗi cập nhật')),
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
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
                            child: const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 32, color: Colors.grey.shade400),
                        const SizedBox(height: 4),
                        Text("Chưa có ảnh", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeImage(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon(),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon(),
        );
      }
      return Image.network(
        'http://localhost:8000/$url',
        fit: BoxFit.cover,
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
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
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
                  child: const Icon(Icons.verified_user, color: Colors.teal, size: 24),
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
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.blueGrey),
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
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history, size: 16, color: Colors.blueGrey),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Danh sách kiểm tra (${_inspections.length})",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const Spacer(),
                                    if (_filterPlate.isNotEmpty)
                                      InkWell(
                                        onTap: () {
                                          setState(() => _filterPlate = '');
                                          _loadInspections();
                                        },
                                        child: const Text("Xem tất cả xe", style: TextStyle(fontSize: 11, color: Colors.blue, decoration: TextDecoration.underline)),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _inspections.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.find_in_page_outlined, size: 40, color: Colors.grey.shade400),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Không có dữ liệu ảnh giao ca",
                                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        itemCount: _inspections.length,
                                        separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                                        itemBuilder: (ctx, idx) {
                                          final item = _inspections[idx];
                                          final isSelected = _selectedRecord?['id'] == item['id'];
                                          final flagStatus = (item['flag_status'] ?? 'none').toString().toLowerCase();

                                          Color statusColor = Colors.grey;
                                          String statusLabel = "Chưa duyệt";
                                          if (flagStatus == 'approved') {
                                            statusColor = Colors.green;
                                            statusLabel = "Đã duyệt";
                                          } else if (flagStatus == 'rejected') {
                                            statusColor = Colors.red;
                                            statusLabel = "Từ chối / Chờ chụp lại";
                                          } else if (flagStatus == 'monitored') {
                                            statusColor = Colors.amber.shade900;
                                            statusLabel = "Đang theo dõi";
                                          }

                                          final plate = item['plate_number'] ?? 'N/A';
                                          final driver = item['driver_name'] ?? 'Tài xế';
                                          final date = item['check_date'] ?? '';

                                          return InkWell(
                                            borderRadius: BorderRadius.circular(4),
                                            onTap: () {
                                              setState(() {
                                                _selectedRecord = item;
                                                _noteCtrl.text = item['flag_reason'] ?? '';
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: isSelected ? Colors.teal.shade50 : Colors.white,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isSelected ? Colors.teal : Colors.grey.shade300,
                                                  width: isSelected ? 1.5 : 1,
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        plate,
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                                      ),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: statusColor.withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: statusColor.withOpacity(0.4)),
                                                        ),
                                                        child: Text(
                                                          statusLabel,
                                                          style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.person, size: 13, color: Colors.teal),
                                                      const SizedBox(width: 4),
                                                      Expanded(
                                                        child: Text(
                                                          driver,
                                                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                                                      const SizedBox(width: 4),
                                                      Text(date, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                                      const Spacer(),
                                                      if (item['flag_deviation_km'] == true)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: Colors.red.shade100,
                                                            borderRadius: BorderRadius.circular(2),
                                                          ),
                                                          child: const Text("Lệch km", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
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
                                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                  ),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Thông tin tóm tắt xe & tài xế
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade50,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.blueGrey.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      "Xe: ${_selectedRecord!['plate_number']}",
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      "(${_selectedRecord!['vehicle_type'] ?? 'Xe đầu kéo'})",
                                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  "Tài xế giao ca: ${_selectedRecord!['driver_name']} • SĐT: ${_selectedRecord!['driver_phone'] ?? 'N/A'}",
                                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                "Km Táp-lô: ${_selectedRecord!['km_confirmed'] ?? _selectedRecord!['km_ocr'] ?? 'N/A'} km",
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                "Thời gian nộp: ${_selectedRecord!['completed_at'] ?? _selectedRecord!['created_at'] ?? 'Hôm nay'}",
                                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    // Lưới 5 ảnh
                                    Expanded(
                                      child: GridView.count(
                                        crossAxisCount: isDesktop ? 3 : 2,
                                        crossAxisSpacing: 10,
                                        mainAxisSpacing: 10,
                                        childAspectRatio: 1.25,
                                        children: [
                                          _buildPhotoThumbnail("1. Gầm trước xe", _selectedRecord!['img_front_underbody'], Icons.front_hand_outlined),
                                          _buildPhotoThumbnail("2. Bầu vi sai & Gầm sau", _selectedRecord!['img_rear_underbody'], Icons.settings_suggest_outlined),
                                          _buildPhotoThumbnail("3. Hông trái xe", _selectedRecord!['img_left_side'], Icons.compare_arrows_outlined),
                                          _buildPhotoThumbnail("4. Hông phải xe", _selectedRecord!['img_right_side'], Icons.swap_horiz_outlined),
                                          _buildPhotoThumbnail("5. Táp-lô & Đồng hồ ODO", _selectedRecord!['img_dashboard'], Icons.speed_outlined),
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
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _noteCtrl,
                                              decoration: const InputDecoration(
                                                labelText: "Ghi chú kiểm tra của Điều phối (nếu xe xước vỡ hoặc lệch km)",
                                                border: OutlineInputBorder(),
                                                isDense: true,
                                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          if (_isSubmitting)
                                            const SizedBox(width: 32, height: 32, child: CircularProgressIndicator())
                                          else
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green.shade700,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                  ),
                                                  icon: const Icon(Icons.check_circle_outline, size: 16),
                                                  label: const Text("Duyệt Nhận Chuyến", style: TextStyle(fontWeight: FontWeight.bold)),
                                                  onPressed: () => _updateReviewStatus('approved'),
                                                ),
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.amber.shade900,
                                                    side: BorderSide(color: Colors.amber.shade700),
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                  ),
                                                  icon: const Icon(Icons.visibility_outlined, size: 16),
                                                  label: const Text("Theo Dõi"),
                                                  onPressed: () => _updateReviewStatus('monitored'),
                                                ),
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.red.shade700,
                                                    side: BorderSide(color: Colors.red.shade400),
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                  ),
                                                  icon: const Icon(Icons.cancel_outlined, size: 16),
                                                  label: const Text("Yêu Cầu Chụp Lại"),
                                                  onPressed: () => _updateReviewStatus('rejected'),
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

