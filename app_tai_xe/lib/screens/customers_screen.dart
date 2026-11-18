import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_service.dart';
import '../widgets/center_loading_overlay.dart';
import '../widgets/virtualized_load_more_table.dart';
import 'package:file_picker/file_picker.dart';

/// Màn hình Quản lý Khách hàng.
/// Chỉ Điều phối viên, Quản lý / Giám đốc và Admin được vào (kiểm tra ở
/// main_navigation_screen.dart, dispatch_supervisor_screen.dart và phía server).
class CustomersScreen extends StatefulWidget {
  /// Báo số khách hàng (sau lọc / tổng) để hiện huy hiệu trên tiêu đề.
  final void Function(int filtered, int total)? onCountChanged;

  const CustomersScreen({super.key, this.onCountChanged});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _locations = [];
  String _query = '';
  bool _loading = true;

  // Bảng dữ liệu: Load More (tải thêm theo lô) + Virtualization
  int _currentPage = 1;
  int _pageSize = 20;
  String _sourceFilter = 'ALL'; // ALL | MANUAL | EXCEL

  // Nhóm Zalo OA: kết nối Zalo OA (cấp quyền khi cần) + lấy danh sách nhóm về phần mềm
  bool _groupsBusy = false;
  String _groupsProgress = '';
  Timer? _authTimer;
  int _authPolls = 0;

  // Import khách hàng từ Excel
  bool _importBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _authTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------- NHÓM ZALO OA ----------------

  /// Bấm nút "Nhóm Zalo OA":
  /// 1. Gọi máy chủ kết nối Zalo OA và lấy danh sách nhóm thực tế của OA.
  /// 2. Nếu OA chưa được cấp quyền (HTTP 409) thì mở trang cấp quyền Zalo,
  ///    chờ cấp quyền xong rồi tự lấy lại danh sách nhóm.
  /// Danh sách khách hàng KHÔNG đồng bộ từ Zalo (chỉ nhập tay hoặc import Excel).
  Future<void> _onZaloGroups() async {
    if (_groupsBusy) return;
    setState(() {
      _groupsBusy = true;
      _groupsProgress = 'Đang kết nối Zalo OA và lấy danh sách nhóm...';
    });
    await _fetchZaloGroups(allowAuthorize: true);
  }

  Future<void> _fetchZaloGroups({required bool allowAuthorize}) async {
    final res = await AdminService.refreshZaloOaChatGroups();
    if (!mounted) return;
    if (res['ok'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final stats = (data['stats'] as Map?) ?? {};
      final groupCount = (stats['groups'] as num?)?.toInt() ?? 0;
      final linked = (stats['linked_customers'] as num?)?.toInt() ?? 0;
      final oaName = (data['oa_name'] ?? '').toString();
      await _load();
      _groupsStop(
        'Đã lấy $groupCount nhóm Zalo OA'
        '${oaName.isNotEmpty ? ' từ "$oaName"' : ''} về phần mềm'
        ' - $linked khách hàng đang gắn nhóm',
      );
      return;
    }
    if (res['status'] == 409 && allowAuthorize) {
      await _zaloAuthorize();
      return;
    }
    final msg = (res['message'] ?? '').toString();
    _groupsStop(msg.isNotEmpty ? msg : 'Không lấy được danh sách nhóm Zalo OA', error: true);
  }

  Future<void> _zaloAuthorize() async {
    final agree = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text("Kết nối Zalo OA", style: TextStyle(fontSize: 17)),
        content: const Text(
          "Phần mềm chưa được kết nối với Zalo OA.\n\n"
          "Ứng dụng sẽ mở trang Zalo để chủ (hoặc quản trị viên) Zalo OA bấm \"Cho phép\". "
          "Sau khi cấp quyền xong, quay lại đây, ứng dụng sẽ tự lấy danh sách nhóm Zalo OA về phần mềm.",
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Hủy bỏ"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0068FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Mở Zalo để cấp quyền"),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (agree != true) {
      _groupsStop('');
      return;
    }
    final res = await AdminService.requestZaloOaAuthorizeUrl();
    if (!mounted) return;
    final url = res['ok'] == true && res['data'] is Map
        ? (res['data']['authorize_url'] ?? '').toString()
        : '';
    if (url.isEmpty) {
      _groupsStop(
        res['ok'] == true ? 'Máy chủ không trả về link cấp quyền' : res['message'].toString(),
        error: true,
      );
      return;
    }
    bool opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    if (!opened) {
      _groupsStop('Không mở được trình duyệt để cấp quyền Zalo OA', error: true);
      return;
    }
    // Chờ chủ OA cấp quyền (tối đa ~5 phút), xong thì tự lấy danh sách nhóm
    setState(() => _groupsProgress = 'Đang chờ cấp quyền trên Zalo...');
    _authTimer?.cancel();
    _authPolls = 0;
    _authTimer = Timer.periodic(const Duration(seconds: 2), (_) => _authTick());
  }

  Future<void> _authTick() async {
    _authPolls++;
    final st = await AdminService.fetchZaloOaStatus();
    if (!mounted || _authTimer == null) return;
    final connected = st['ok'] == true &&
        st['data'] is Map &&
        (st['data'] as Map)['connected'] == true;
    if (connected) {
      _authTimer?.cancel();
      _authTimer = null;
      setState(() => _groupsProgress = 'Đã kết nối Zalo OA, đang lấy danh sách nhóm...');
      await _fetchZaloGroups(allowAuthorize: false);
    } else if (_authPolls >= 150) {
      _groupsStop('Hết thời gian chờ cấp quyền Zalo OA. Bấm lại nút "Nhóm Zalo OA" để thử lại.', error: true);
    }
  }

  void _groupsStop(String message, {bool error = false}) {
    _authTimer?.cancel();
    _authTimer = null;
    if (!mounted) return;
    setState(() {
      _groupsBusy = false;
      _groupsProgress = '';
    });
    if (message.isNotEmpty) _toast(message, error: error);
  }

  /// Import danh sách khách hàng từ file Excel (mẫu "cấu trúc khách hàng.xlsx").
  /// Chọn file qua FilePicker (web + desktop), gửi lên server, hiển thị kết quả chi tiết.
  Future<void> _importExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      _toast('Không đọc được nội dung file', error: true);
      return;
    }
    setState(() => _importBusy = true);
    final res = await AdminService.importCustomersExcel(
      bytes.toList(),
      f.name,
    );
    if (!mounted) return;
    setState(() => _importBusy = false);
    if (res['success'] == true) {
      await _load();
      _showImportResult(res);
    } else {
      _toast(res['message']?.toString() ?? 'Import thất bại', error: true);
    }
  }

  /// Dialog kết quả import: thống kê thành công/cập nhật/bỏ qua + chi tiết lỗi.
  void _showImportResult(Map<String, dynamic> res) {
    final inserted = res['inserted'] ?? 0;
    final updated = res['updated'] ?? 0;
    final skipped = res['skipped'] ?? 0;
    final groups = res['groupsLearned'] ?? 0;
    final withGroup = res['withGroup'] ?? 0;
    final missingGroupCols = (res['missingGroupColumns'] as List?) ?? [];
    final skippedDetails = (res['skippedDetails'] as List?) ?? [];
    final errors = (res['errors'] as List?) ?? [];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Text('Kết quả import khách hàng'),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _resultRow('Thêm mới', inserted, Colors.green.shade700),
              _resultRow('Cập nhật đã có', updated, Colors.blue.shade800),
              _resultRow('Bỏ qua (thiếu Tên KH)', skipped, Colors.orange.shade800),
              _resultRow('Đã lưu Nhóm Zalo (Group ID + Tên nhóm)', withGroup, Colors.green.shade800),
              _resultRow('Nhóm Zalo mới thêm vào danh sách nhóm', groups, const Color(0xFF0068FF)),
              const SizedBox(height: 12),
              if (missingGroupCols.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    'File không có cột: ${missingGroupCols.join(', ')}. '
                    'Nhóm Zalo OA của khách hàng chưa được lưu từ file này.',
                    style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (skippedDetails.isNotEmpty) ...[
                const Text('Chi tiết bỏ qua:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                ...skippedDetails.map((e) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('- $e', style: const TextStyle(fontSize: 12.5)),
                    )),
                const SizedBox(height: 8),
              ],
              if (errors.isNotEmpty) ...[
                const Text('Lỗi từng dòng:',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                ...errors.take(10).map((e) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('- $e',
                          style: const TextStyle(fontSize: 12.5, color: Colors.red)),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, dynamic value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text('$value', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AdminService.fetchCustomers(),
      AdminService.fetchLocations(),
    ]);
    if (!mounted) return;
    setState(() {
      _customers = results[0]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _locations = results[1]
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _loading = false;
    });
  }

  String _s(Map<String, dynamic> c, String key) =>
      (c[key] ?? '').toString().trim();

  List<Map<String, dynamic>> get _filtered {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return _customers;
    return _customers.where((c) {
      final inGroups = (c['zalo_oa_groups'] as List? ?? [])
          .any((g) => g.toString().toLowerCase().contains(q));
      if (inGroups) return true;
      // Tìm theo nhóm hội thoại (label hoặc group_id)
      final inChatGroups = (c['zalo_chat_groups'] as List? ?? []).any((g) {
        if (g is! Map) return false;
        return g['label'].toString().toLowerCase().contains(q) ||
            g['group_id'].toString().toLowerCase().contains(q);
      });
      if (inChatGroups) return true;
      final inPickups = (c['linked_pickup_locations'] as List? ?? []).any((l) {
        if (l is! Map) return false;
        return (l['name'] ?? '').toString().toLowerCase().contains(q) ||
            (l['address'] ?? '').toString().toLowerCase().contains(q);
      });
      if (inPickups) return true;
      final inDeliveries = (c['linked_delivery_locations'] as List? ?? []).any((l) {
        if (l is! Map) return false;
        return (l['name'] ?? '').toString().toLowerCase().contains(q) ||
            (l['address'] ?? '').toString().toLowerCase().contains(q);
      });
      if (inDeliveries) return true;
      return [
        'code',
        'name',
        'tax_code',
        'contact_person',
        'phone',
        'email',
        'address',
        'pickup_location_name',
        'delivery_location_name',
        'product_code',
      ].any((k) => _s(c, k).toLowerCase().contains(q));
    }).toList();
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  // ---------------- GIAO DIỆN (theo mẫu màn Đội xe & Tài xế) ----------------

  /// Khách hàng chỉ có 2 nguồn: nhập tay ('manual') hoặc import từ file Excel ('excel').
  bool _isExcel(Map<String, dynamic> c) => _s(c, 'source').toLowerCase() == 'excel';

  /// Danh sách sau khi lọc nguồn + tìm kiếm, sắp theo tên khách hàng.
  List<Map<String, dynamic>> get _visible {
    final list = _filtered.where((c) {
      if (_sourceFilter == 'EXCEL') return _isExcel(c);
      if (_sourceFilter == 'MANUAL') return !_isExcel(c);
      return true;
    }).toList();
    list.sort((a, b) => _s(a, 'name').toLowerCase().compareTo(_s(b, 'name').toLowerCase()));
    return list;
  }

  void _reportCount(int filtered, int total) {
    final cb = widget.onCountChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(filtered, total);
    });
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    bool busy = false,
    bool filled = false,
  }) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
    final iconW = Icon(icon, size: 15);
    final text = Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5));
    return SizedBox(
      height: 36,
      child: filled
          ? ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 36),
                fixedSize: const Size.fromHeight(36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: shape,
              ),
              icon: iconW,
              label: text,
              onPressed: onPressed,
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color.withValues(alpha: 0.45)),
                minimumSize: const Size(0, 36),
                fixedSize: const Size.fromHeight(36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: shape,
              ),
              icon: iconW,
              label: text,
              onPressed: onPressed,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    _reportCount(list.length, _customers.length);

    final totalItems = list.length;
    final totalPages = (totalItems / _pageSize).ceil().clamp(1, 99999);
    final validPage = _currentPage.clamp(1, totalPages);
    final endIndex = (validPage * _pageSize).clamp(0, totalItems);
    final pageItems = totalItems == 0 ? <Map<String, dynamic>>[] : list.sublist(0, endIndex);

    return Column(
      children: [
        // Thanh công cụ 1 hàng: Tìm kiếm + Lọc nguồn + Import Excel + Thêm + Nhóm Zalo OA
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
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 12.5),
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: (v) => setState(() {
                      _query = v;
                      _currentPage = 1;
                    }),
                    decoration: InputDecoration(
                      isDense: true,
                      constraints: const BoxConstraints(minHeight: 36, maxHeight: 36),
                      hintText: "Tìm theo tên, mã khách hàng, MST, SĐT, địa chỉ...",
                      hintStyle: const TextStyle(fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search, size: 17),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 36, maxHeight: 36),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 36, maxHeight: 36),
                              icon: const Icon(Icons.clear, size: 15),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _query = '';
                                _currentPage = 1;
                              }),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Bộ lọc theo nguồn khách hàng
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 36,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sourceFilter,
                    isExpanded: true,
                    isDense: true,
                    iconSize: 18,
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87, fontFamily: 'Nunito'),
                    decoration: const InputDecoration(
                      isDense: true,
                      constraints: BoxConstraints(minHeight: 36, maxHeight: 36),
                      prefixIcon: Icon(Icons.filter_alt_outlined, size: 17),
                      prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 36, maxHeight: 36),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text("Tất cả nguồn")),
                      DropdownMenuItem(value: 'MANUAL', child: Text("Thủ công")),
                      DropdownMenuItem(value: 'EXCEL', child: Text("Import Excel")),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _sourceFilter = val;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: "Import danh sách khách hàng từ file Excel (mẫu cấu trúc khách hàng)",
                child: _toolbarButton(
                  icon: Icons.upload_file_outlined,
                  label: _importBusy ? "Đang import..." : "Import Excel",
                  color: const Color(0xFF2E7D32),
                  onPressed: _importBusy ? null : _importExcel,
                ),
              ),
              const SizedBox(width: 10),
              _toolbarButton(
                icon: Icons.person_add_alt_1,
                label: "Thêm khách hàng",
                color: Colors.blue.shade800,
                filled: true,
                onPressed: () => _showForm(),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: "Kết nối Zalo OA và lấy đúng danh sách nhóm Zalo OA về phần mềm",
                child: _toolbarButton(
                  icon: Icons.groups_2_outlined,
                  label: _groupsBusy ? "Đang lấy nhóm..." : "Nhóm Zalo OA",
                  color: const Color(0xFF0068FF),
                  busy: _groupsBusy,
                  onPressed: _groupsBusy ? null : _onZaloGroups,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Bảng danh sách khách hàng
        Expanded(
          child: CenterLoadingOverlay(
            isLoading: _loading || _groupsBusy,
            message: _groupsProgress.isNotEmpty
                ? _groupsProgress
                : 'Đang tải danh sách khách hàng...',
            child: _loading
                ? const SizedBox.expand()
                : RefreshIndicator(
                    onRefresh: _load,
                    child: pageItems.isEmpty
                        ? _buildEmpty()
                        : _buildTable(
                            pageItems,
                            hasMore: endIndex < totalItems,
                            onLoadMore: () {
                              if (validPage < totalPages) {
                                setState(() => _currentPage = validPage + 1);
                              }
                            },
                          ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  _customers.isEmpty
                      ? "Chưa có khách hàng nào. Bấm \"Thêm khách hàng\" để tạo mới."
                      : "Không tìm thấy khách hàng nào phù hợp với bộ lọc",
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(
    List<Map<String, dynamic>> pageItems, {
    required bool hasMore,
    required VoidCallback onLoadMore,
  }) {
    DataColumn col(String label) => DataColumn(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );

    DataCell makeCell(Widget child) =>
        DataCell(Container(alignment: Alignment.centerLeft, child: child));

    return VirtualizedDataTable(
      headingRowHeight: 44,
      rowHeight: 62,
      horizontalMargin: 16,
      columnSpacing: 16,
      minTableWidth: 0,
      columnFlexes: const [14, 18, 20, 14, 22, 14],
      hasMore: hasMore,
      onLoadMore: onLoadMore,
      onRowTap: (idx) => _showCustomerDetailDialog(pageItems[idx]),
      columns: [
        col("Tên khách hàng"),
        col("Mã khách hàng"),
        col("Nhóm Zalo OA"),
        col("Điểm nhận (Điểm đi)"),
        col("Điểm giao & Sản phẩm"),
        col("Thao tác"),
      ],
      itemCount: pageItems.length,
      rowBuilder: (idx) {
        final c = pageItems[idx];
        final rowColor = idx % 2 == 0 ? Colors.white : Colors.grey.shade50;

        return DataRow(
          color: WidgetStateProperty.all(rowColor),
          cells: [
            // Cột 1: Tên khách hàng (+ nhãn Zalo OA)
            makeCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Builder(
                    builder: (_) {
                      final ava = _s(c, 'zalo_avatar');
                      if (ava.isNotEmpty) {
                        return Tooltip(
                          message: "ID Zalo: ${_s(c, 'zalo_user_id')}",
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.blue.shade50,
                            backgroundImage: NetworkImage(ava),
                            onBackgroundImageError: (_, _) {},
                          ),
                        );
                      }
                      return Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.storefront, size: 18, color: Colors.blue),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _s(c, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: Colors.blueGrey.shade900,
                          ),
                        ),
                        if (_s(c, 'note').isNotEmpty)
                          Text(
                            _s(c, 'note'),
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
            // Cột 2: Mã khách hàng
            makeCell(
              Text(
                _s(c, 'code'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            // Cột 3: Nhóm Zalo OA
            makeCell(_buildZaloGroupsCell(c)),
            // Cột 4: Điểm nhận (Điểm đi)
            makeCell(_buildPickupCell(c)),
            // Cột 5: Điểm giao & Sản phẩm
            makeCell(_buildDeliveryCell(c)),
            // Cột 6: Thao tác
            makeCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _rowButton(
                    icon: Icons.edit,
                    label: "Sửa",
                    color: Colors.blue.shade800,
                    border: Colors.blue.shade300,
                    onPressed: () => _showForm(customer: c),
                  ),
                  const SizedBox(width: 8),
                  _rowButton(
                    icon: Icons.delete_outline,
                    label: "Xóa",
                    color: Colors.red.shade700,
                    border: Colors.red.shade200,
                    onPressed: () => _confirmDelete(c),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCustomerDetailDialog(Map<String, dynamic> c) {
    final linkedPickups = (c['linked_pickup_locations'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final linkedDeliveries = (c['linked_delivery_locations'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    Widget infoItem(String label, String value, {bool bold = false}) {
      final display = value.trim().isEmpty ? '—' : value.trim();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              display,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: value.trim().isEmpty
                    ? Colors.grey.shade400
                    : Colors.blueGrey.shade900,
              ),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.storefront, size: 20, color: Colors.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s(c, 'name'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Mã KH: ${_s(c, 'code')}",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: infoItem(
                        "Điểm nhận mặc định (Điểm đi)",
                        _s(c, 'pickup_location_name'),
                        bold: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: infoItem(
                        "Điểm giao mặc định",
                        _s(c, 'delivery_location_name'),
                        bold: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: infoItem("Sản phẩm mặc định", _s(c, 'product_code')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: infoItem("Mảng hàng / Ghi chú", _s(c, 'note')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: infoItem("Tên nhóm Zalo OA", _s(c, 'zalo_group_name')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: infoItem("Group ID Zalo OA", _s(c, 'zalo_group_id')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: infoItem("Người liên hệ", _s(c, 'contact_person')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: infoItem("Số điện thoại", _s(c, 'phone')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: infoItem("Mã số thuế", _s(c, 'tax_code')),
                    ),
                  ],
                ),
                if (linkedPickups.isNotEmpty || linkedDeliveries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    "Điểm Nhận / Giao đã liên kết trong danh mục VietMap",
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  for (final loc in [...linkedPickups, ...linkedDeliveries])
                    Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (loc['kind'] ?? '') == 'PICKUP'
                            ? const Color(0xFFFFFBEB)
                            : Colors.blue.shade50.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (loc['kind'] ?? '') == 'PICKUP'
                              ? Colors.amber.shade300
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            (loc['kind'] ?? '') == 'PICKUP'
                                ? Icons.warehouse_outlined
                                : Icons.place,
                            size: 15,
                            color: (loc['kind'] ?? '') == 'PICKUP'
                                ? Colors.amber.shade900
                                : Colors.blue.shade800,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "${loc['name'] ?? ''}"
                              "${(loc['address'] ?? '').toString().trim().isNotEmpty ? ' — ${loc['address']}' : ''}",
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text("Đóng"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            icon: const Icon(Icons.edit, size: 15),
            label: const Text("Chỉnh sửa khách hàng"),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _showForm(customer: c);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPickupCell(Map<String, dynamic> c) {
    final linked = (c['linked_pickup_locations'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final fallbackName = _s(c, 'pickup_location_name');
    final primaryName = linked.isNotEmpty
        ? (linked.first['name'] ?? '').toString().trim()
        : fallbackName;
    if (primaryName.isEmpty) {
      return Text("—", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400));
    }
    final extraCount = linked.length > 1 ? linked.length - 1 : 0;
    final tooltipLines = linked.isNotEmpty
        ? linked.map((l) {
            final n = (l['name'] ?? '').toString();
            final a = (l['address'] ?? '').toString();
            return a.isNotEmpty ? "$n ($a)" : n;
          }).join('\n')
        : primaryName;
    return Tooltip(
      message: "Điểm nhận hàng:\n$tooltipLines",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber.shade400),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warehouse_outlined, size: 13, color: Colors.amber.shade900),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                extraCount > 0 ? "$primaryName (+$extraCount)" : primaryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryCell(Map<String, dynamic> c) {
    final linked = (c['linked_delivery_locations'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final fallbackDelivery = _s(c, 'delivery_location_name');
    final prod = _s(c, 'product_code').isNotEmpty ? _s(c, 'product_code') : _s(c, 'address');
    final primaryDelivery = linked.isNotEmpty
        ? (linked.first['name'] ?? '').toString().trim()
        : fallbackDelivery;
    final deliveryAddr = linked.isNotEmpty
        ? (linked.first['address'] ?? '').toString().trim()
        : '';

    if (primaryDelivery.isEmpty && prod.isEmpty) {
      return Text("—", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400));
    }

    final subText = [
      if (deliveryAddr.isNotEmpty) deliveryAddr,
      if (prod.isNotEmpty) "SP: $prod",
    ].join(' • ');

    return Tooltip(
      message: [
        if (primaryDelivery.isNotEmpty) "Điểm giao: $primaryDelivery",
        if (deliveryAddr.isNotEmpty) "Địa chỉ VietMap: $deliveryAddr",
        if (prod.isNotEmpty) "Sản phẩm: $prod",
      ].join('\n'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (primaryDelivery.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  linked.isNotEmpty ? Icons.place : Icons.location_on_outlined,
                  size: 13.5,
                  color: linked.isNotEmpty ? Colors.blue.shade800 : Colors.blueGrey.shade700,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    primaryDelivery,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: linked.isNotEmpty ? Colors.blue.shade900 : Colors.blueGrey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          if (subText.isNotEmpty)
            Text(
              subText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  /// Ô "Nhóm Zalo OA": hiện các nhóm của khách hàng.
  /// - Nhóm hội thoại (học qua webhook): pill xanh lá kèm icon nhóm, tooltip
  ///   hiển thị đầy đủ tên nhóm + group_id.
  /// - Nhãn tag phân loại (khi Zalo cấp quyền API Tag): pill xanh dương.
  /// Khách chưa có nhóm nào hiển thị gạch ngang mờ.
  Widget _buildZaloGroupsCell(Map<String, dynamic> c) {
    final chatGroups = (c['zalo_chat_groups'] as List? ?? [])
        .whereType<Map>()
        .map((g) => Map<String, dynamic>.from(g))
        .where((g) => (g['label'] ?? '').toString().isNotEmpty)
        .toList();
    final tagGroups = (c['zalo_oa_groups'] as List? ?? [])
        .map((e) => e.toString())
        .where((g) => g.isNotEmpty)
        .toList();
    if (chatGroups.isEmpty && tagGroups.isEmpty) {
      return Text("—", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400));
    }
    void showZaloGroupMembersDialog(String gid, String label) {
      final members = _customers.where((c) {
        final gs = (c['zalo_chat_groups'] as List? ?? []);
        return gs.any((g) => g is Map && (g['group_id'] ?? '').toString() == gid);
      }).toList();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.forum_outlined, size: 20, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: members.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "Chưa có khách hàng nào trong nhóm này được ghi nhận.\n"
                      "Thành viên nhóm sẽ tự động được học khi họ nhắn tin trong nhóm Zalo.",
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${members.length} khách hàng trong nhóm:",
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: SingleChildScrollView(
                          child: Column(
                            children: members.map((m) {
                              final mMap = Map<String, dynamic>.from(m);
                              final mName = _s(mMap, 'name');
                              final mCode = _s(mMap, 'code');
                              final mPhone = _s(mMap, 'phone');
                              final mzName = _s(mMap, 'zalo_display_name');
                              final mAvatar = _s(mMap, 'zalo_avatar');
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    if (mAvatar.isNotEmpty)
                                      CircleAvatar(
                                        radius: 12,
                                        backgroundColor: Colors.blue.shade50,
                                        backgroundImage: NetworkImage(mAvatar),
                                        onBackgroundImageError: (_, _) {},
                                      )
                                    else
                                      Icon(Icons.storefront, size: 16, color: Colors.blue.shade400),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            mName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueGrey,
                                            ),
                                          ),
                                          if (mzName.isNotEmpty && mzName != mName)
                                            Text(
                                              "Zalo: $mzName",
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (mCode.isNotEmpty)
                                      Text(
                                        mCode,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    if (mPhone.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Icon(Icons.phone, size: 12, color: Colors.grey.shade400),
                                      const SizedBox(width: 2),
                                      Text(
                                        mPhone,
                                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Đóng"),
            ),
          ],
        ),
      );
    }

    Widget tagPill(String g) {
      return Tooltip(
        message: "Nhãn phân loại Zalo: $g",
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF0068FF).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF0068FF).withValues(alpha: 0.25)),
          ),
          child: Text(
            g,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0068FF),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    void showGroupPickerDialog() {
      if (chatGroups.length == 1) {
        final g = chatGroups.first;
        showZaloGroupMembersDialog(
          (g['group_id'] ?? '').toString(),
          (g['label'] ?? '').toString(),
        );
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Icon(Icons.forum_outlined, size: 20, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Nhóm Zalo OA của ${_s(c, 'name')}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${chatGroups.length} nhóm - bấm vào nhóm để xem danh sách khách hàng:",
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Column(
                      children: chatGroups.map((g) {
                        final label = (g['label'] ?? '').toString();
                        final gid = (g['group_id'] ?? '').toString();
                        final gcount = (g['member_count'] as int? ?? 0);
                        return InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            showZaloGroupMembersDialog(gid, label);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.forum_outlined, size: 14, color: Colors.green.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                                if (gcount > 0)
                                  Text(
                                    "$gcount thành viên",
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Đóng"),
            ),
          ],
        ),
      );
    }

    Widget groupsCountButton() {
      final names = chatGroups
          .map((g) => "${(g['label'] ?? '').toString()}  (Group ID: ${(g['group_id'] ?? '').toString()})")
          .join("\n");
      return Tooltip(
        message: "${chatGroups.length} nhóm Zalo OA:\n$names\nBấm để xem khách hàng trong nhóm",
        child: InkWell(
          onTap: showGroupPickerDialog,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum_outlined, size: 13, color: Colors.green.shade800),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    chatGroups.length == 1
                        ? (chatGroups.first['label'] ?? '').toString()
                        : "${chatGroups.length} nhóm",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.green.shade900,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: groupsCountButton()),
        ...tagGroups.map((g) => Flexible(child: tagPill(g))),
      ],
    );
  }

  Widget _rowButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color border,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      onPressed: onPressed,
    );
  }

  Future<void> _showForm({Map<String, dynamic>? customer}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CustomerFormDialog(
        customer: customer,
        locations: _locations,
        onToast: _toast,
      ),
    );
    if (result == true) {
      _load();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text("Xác nhận xóa khách hàng", style: TextStyle(fontSize: 17)),
        content: Text(
          "Xóa khách hàng \"${_s(c, 'name')}\" (mã ${_s(c, 'code')})?",
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Hủy bỏ"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = int.tryParse('${c['id']}');
    if (id == null) return;
    final done = await AdminService.deleteCustomer(id);
    if (!mounted) return;
    if (done) {
      _toast("Đã xóa khách hàng");
      _load();
    } else {
      _toast("Không xóa được khách hàng", error: true);
    }
  }
}

class _CustomerFormDialog extends StatefulWidget {
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>> locations;
  final void Function(String msg, {bool error}) onToast;

  const _CustomerFormDialog({
    this.customer,
    required this.locations,
    required this.onToast,
  });

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  static const _fields = <(String, String, IconData, TextInputType)>[
    ('code', 'Mã khách hàng *', Icons.tag, TextInputType.text),
    ('name', 'Tên khách hàng *', Icons.business, TextInputType.text),
    ('pickup_location_name', 'Điểm nhận mặc định (Điểm đi)', Icons.warehouse_outlined, TextInputType.text),
    ('delivery_location_name', 'Điểm giao mặc định', Icons.place_outlined, TextInputType.text),
    ('product_code', 'Sản phẩm mặc định', Icons.inventory_2_outlined, TextInputType.text),
    ('zalo_group_id', 'Group ID nhóm Zalo OA', Icons.tag_outlined, TextInputType.text),
    ('zalo_group_name', 'Tên nhóm Zalo thực tế', Icons.forum_outlined, TextInputType.text),
    ('contact_person', 'Người liên hệ', Icons.person_outline, TextInputType.name),
    ('phone', 'Số điện thoại', Icons.phone_outlined, TextInputType.phone),
    ('email', 'Email', Icons.email_outlined, TextInputType.emailAddress),
    ('tax_code', 'Mã số thuế', Icons.receipt_long_outlined, TextInputType.text),
    ('address', 'Địa chỉ chi tiết', Icons.location_on_outlined, TextInputType.streetAddress),
    ('note', 'Ghi chú / Mảng hàng', Icons.notes_outlined, TextInputType.multiline),
  ];

  late final Map<String, TextEditingController> _ctrls;
  late final Set<int> _selectedPickupIds;
  late final Set<int> _selectedDeliveryIds;
  final TextEditingController _locSearchCtrl = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;

  bool get _isEdit => widget.customer != null;

  String _val(String key) => (widget.customer?[key] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final f in _fields)
        f.$1: TextEditingController(text: _isEdit ? _val(f.$1) : ''),
    };
    _selectedPickupIds = ((widget.customer?['pickup_location_ids'] as List?) ?? const [])
        .map((e) => int.tryParse('$e') ?? -1)
        .where((id) => id > 0)
        .toSet();
    _selectedDeliveryIds = ((widget.customer?['delivery_location_ids'] as List?) ?? const [])
        .map((e) => int.tryParse('$e') ?? -1)
        .where((id) => id > 0)
        .toSet();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _locSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final res = await AdminService.saveCustomer(
      id: _isEdit ? int.tryParse('${widget.customer!['id']}') : null,
      data: {
        for (final e in _ctrls.entries) e.key: e.value.text.trim(),
        'pickup_location_ids': _selectedPickupIds.toList(),
        'delivery_location_ids': _selectedDeliveryIds.toList(),
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.of(context).pop(true);
      widget.onToast(_isEdit ? "Đã cập nhật khách hàng" : "Đã thêm khách hàng");
    } else {
      widget.onToast(res['message'].toString(), error: true);
    }
  }

  Widget _buildLocationLinkSection() {
    final q = _locSearchCtrl.text.trim().toLowerCase();
    final filteredLocs = widget.locations.where((l) {
      if (q.isEmpty) return true;
      return (l['name'] ?? '').toString().toLowerCase().contains(q) ||
          (l['address'] ?? '').toString().toLowerCase().contains(q) ||
          (l['vietmap_id'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            const Text(
              "Liên kết Điểm Nhận / Giao trong danh mục VietMap",
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              "Nhận: ${_selectedPickupIds.length} • Giao: ${_selectedDeliveryIds.length}",
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Colors.teal.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _locSearchCtrl,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 12.5),
          decoration: const InputDecoration(
            isDense: true,
            hintText: "Tìm điểm nhận / giao trong danh mục VietMap...",
            prefixIcon: Icon(Icons.search, size: 17),
            prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 0),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 165),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: filteredLocs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    "Không có điểm khớp từ khóa",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredLocs.length,
                  itemBuilder: (context, index) {
                    final loc = filteredLocs[index];
                    final lid = int.tryParse('${loc['id']}');
                    final kind = (loc['kind'] ?? 'DELIVERY').toString().toUpperCase();
                    final isPickup = kind == 'PICKUP';
                    final checked = lid != null &&
                        (isPickup
                            ? _selectedPickupIds.contains(lid)
                            : _selectedDeliveryIds.contains(lid));
                    final name = (loc['name'] ?? '').toString();
                    final addr = (loc['address'] ?? '').toString();
                    return InkWell(
                      onTap: () {
                        if (lid == null) return;
                        setState(() {
                          if (isPickup) {
                            if (checked) {
                              _selectedPickupIds.remove(lid);
                            } else {
                              _selectedPickupIds.add(lid);
                              if (_ctrls['pickup_location_name']!.text.trim().isEmpty) {
                                _ctrls['pickup_location_name']!.text = name;
                              }
                            }
                          } else {
                            if (checked) {
                              _selectedDeliveryIds.remove(lid);
                            } else {
                              _selectedDeliveryIds.add(lid);
                              if (_ctrls['delivery_location_name']!.text.trim().isEmpty) {
                                _ctrls['delivery_location_name']!.text = name;
                              }
                            }
                          }
                        });
                      },
                      child: Container(
                        color: isPickup ? const Color(0xFFFFFBEB) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Checkbox(
                                value: checked,
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) {
                                  if (lid == null) return;
                                  setState(() {
                                    if (isPickup) {
                                      v == true
                                          ? _selectedPickupIds.add(lid)
                                          : _selectedPickupIds.remove(lid);
                                      if (v == true &&
                                          _ctrls['pickup_location_name']!.text.trim().isEmpty) {
                                        _ctrls['pickup_location_name']!.text = name;
                                      }
                                    } else {
                                      v == true
                                          ? _selectedDeliveryIds.add(lid)
                                          : _selectedDeliveryIds.remove(lid);
                                      if (v == true &&
                                          _ctrls['delivery_location_name']!.text.trim().isEmpty) {
                                        _ctrls['delivery_location_name']!.text = name;
                                      }
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: isPickup ? Colors.amber.shade100 : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                isPickup ? "Nhận" : "Giao",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPickup ? Colors.amber.shade900 : Colors.blue.shade800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                addr.isNotEmpty ? "$name ($addr)" : name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      title: Text(
        _isEdit ? "Sửa khách hàng" : "Thêm khách hàng",
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in _fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextFormField(
                      controller: _ctrls[f.$1],
                      keyboardType: f.$4,
                      maxLines: (f.$1 == 'note' || f.$1 == 'address') ? 2 : 1,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: f.$2,
                        prefixIcon: Icon(f.$3, size: 18),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if ((f.$1 == 'code' || f.$1 == 'name') && t.isEmpty) {
                          return "Không được để trống";
                        }
                        if (f.$1 == 'email' &&
                            t.isNotEmpty &&
                            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                          return "Email không hợp lệ";
                        }
                        return null;
                      },
                    ),
                  ),
                _buildLocationLinkSection(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text("Hủy bỏ"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade800,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 36),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          onPressed: _saving ? null : _handleSave,
          child: Text(_saving ? "Đang lưu..." : "Lưu"),
        ),
      ],
    );
  }
}
