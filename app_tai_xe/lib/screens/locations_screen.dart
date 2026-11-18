import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/address_geocoder_service.dart';
import '../services/admin_service.dart';
import '../widgets/center_loading_overlay.dart';
import '../widgets/map_point_picker_dialog.dart';
import '../widgets/virtualized_load_more_table.dart';

/// Màn hình Điểm nhận / giao hàng.
/// Quản lý danh mục Điểm nhận hàng (PICKUP) và Điểm giao hàng (DELIVERY)
/// liên kết với Khách hàng, hỗ trợ Import chuẩn file DS DIEM VIETMAP.xlsx.
/// Chỉ Điều phối viên, Quản lý / Giám đốc và Admin được vào.
class LocationsScreen extends StatefulWidget {
  final void Function(int filtered, int total)? onCountChanged;

  const LocationsScreen({super.key, this.onCountChanged});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = true;
  List<Map<String, dynamic>> _locations = [];
  // ALL | PICKUP | DELIVERY
  String _filter = 'ALL';

  int _currentPage = 1;
  int _pageSize = 20;

  // Chọn nhiều điểm để xóa cùng lúc
  final Set<int> _selectedLocIds = {};
  bool _bulkBusy = false;

  // Import Excel DS DIEM VIETMAP.xlsx
  bool _importBusy = false;

  // Danh mục khách hàng (để gán điểm cho nhiều khách hàng trong form thêm / sửa)
  List<Map<String, dynamic>> _customers = [];

  static const _kindLabels = {
    'PICKUP': 'Điểm nhận',
    'DELIVERY': 'Điểm giao',
    'BOTH': 'Nhận và giao',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _s(Map<String, dynamic> c, String key) =>
      (c[key] ?? '').toString().trim();

  List<Map<String, dynamic>> _asMaps(List<dynamic> raw) =>
      raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AdminService.fetchLocations(),
      AdminService.fetchCustomers(),
    ]);
    if (!mounted) return;
    setState(() {
      _locations = _asMaps(results[0]);
      _customers = _asMaps(results[1]);
      _loading = false;
      _pruneSelection();
    });
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  void _reportCount(int filtered, int total) {
    final cb = widget.onCountChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(filtered, total);
    });
  }

  // ---------------- LỌC & CHỌN DÒNG ----------------

  int? _locId(Map<String, dynamic> m) => int.tryParse(_s(m, 'id'));

  bool _canPick(Map<String, dynamic> m) => _locId(m) != null;

  bool _isPicked(Map<String, dynamic> m) {
    final id = _locId(m);
    return id != null && _selectedLocIds.contains(id);
  }

  void _setPicked(Map<String, dynamic> m, bool v) {
    final id = _locId(m);
    if (id == null) return;
    v ? _selectedLocIds.add(id) : _selectedLocIds.remove(id);
  }

  int get _pickedCount => _selectedLocIds.length;

  void _clearPicked() {
    _selectedLocIds.clear();
  }

  void _pruneSelection() {
    final locIds = _locations
        .map((x) => int.tryParse(_s(x, 'id')))
        .whereType<int>()
        .toSet();
    _selectedLocIds.retainWhere(locIds.contains);
  }

  /// Import danh sách Điểm nhận / Giao hàng từ file Excel (theo mẫu "DS DIEM VIETMAP.xlsx").
  /// - Dòng bôi vàng -> Điểm nhận (PICKUP)
  /// - Các dòng còn lại -> Điểm giao (DELIVERY)
  Future<void> _importExcel() async {
    if (_importBusy) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      _toast('Không đọc được nội dung file Excel', error: true);
      return;
    }
    if (!mounted) return;

    bool replaceAll = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Text(
            "Import Điểm nhận / Giao hàng (VietMap)",
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "File đã chọn: ${f.name}",
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  "Quy tắc nhận diện tự động theo mẫu DS DIEM VIETMAP.xlsx:\n"
                  "• Đọc đầy đủ 14 cột: #, Id, Danh Mục, Tên, Vĩ Độ, Kinh Độ, Địa Chỉ, Số ĐT, Bán Kính, Người Liên Hệ, Di Động, Email, Cho Phép Dừng Xe, Ghi Chú.\n"
                  "• Dòng bôi nền màu vàng -> Điểm nhận hàng (PICKUP).\n"
                  "• Các dòng còn lại -> Điểm giao hàng (DELIVERY).\n"
                  "• Tự động liên kết Điểm nhận/Giao với Khách hàng tương ứng.",
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setDialogState(() => replaceAll = !replaceAll),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: replaceAll ? Colors.amber.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: replaceAll ? Colors.amber.shade400 : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: replaceAll,
                            onChanged: (v) => setDialogState(() => replaceAll = v ?? true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "Xóa dữ liệu cũ của Điểm nhận/Giao và cập nhật mới hoàn toàn từ file Excel này",
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Hủy bỏ"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Tiến hành Import"),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _importBusy = true);
    final res = await AdminService.importLocationsExcel(
      bytes.toList(),
      f.name,
      replaceAll: replaceAll,
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

  void _showImportResult(Map<String, dynamic> res) {
    final inserted = res['inserted'] ?? 0;
    final updated = res['updated'] ?? 0;
    final pickupCount = res['pickupCount'] ?? 0;
    final deliveryCount = res['deliveryCount'] ?? 0;
    final linkedLocations = res['linkedLocations'] ?? 0;
    final linkedCustomers = res['linkedCustomers'] ?? 0;
    final errors = (res['errors'] as List?) ?? const [];

    Widget rowStat(String label, dynamic val, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              '$val',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Text(
              "Kết quả Import Điểm nhận / Giao",
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              rowStat("Thêm mới từ Excel", inserted, Colors.green.shade700),
              rowStat("Cập nhật điểm đã có", updated, Colors.blue.shade800),
              rowStat("Điểm nhận hàng (dòng bôi vàng)", pickupCount, Colors.amber.shade900),
              rowStat("Điểm giao hàng (dòng thường)", deliveryCount, Colors.teal.shade800),
              rowStat("Điểm đã tự động liên kết Khách hàng", linkedLocations, Colors.indigo.shade700),
              rowStat("Khách hàng đã gắn Điểm nhận / giao", linkedCustomers, Colors.purple.shade700),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  "Lỗi từng dòng:",
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                ...errors.take(8).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text("- $e", style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ),
                ),
              ],
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

  /// Danh sách điểm nhận / giao đã lọc và sắp xếp theo STT file Excel (#1..#109).
  List<Map<String, dynamic>> get _visibleRows {
    final q = _query.toLowerCase().trim();
    final locs = _locations.where((l) {
      final kind = _s(l, 'kind').isEmpty ? 'BOTH' : _s(l, 'kind');
      switch (_filter) {
        case 'PICKUP':
          if (kind == 'DELIVERY') return false;
          break;
        case 'DELIVERY':
          if (kind == 'PICKUP') return false;
          break;
      }
      if (q.isEmpty) return true;
      if ([
        'stt',
        'vietmap_id',
        'category',
        'name',
        'address',
        'phone',
        'contact_person',
        'mobile',
        'email',
        'note',
      ].any((k) => _s(l, k).toLowerCase().contains(q))) {
        return true;
      }
      return _customerNames(l).any((n) => n.toLowerCase().contains(q));
    }).toList();
    locs.sort((a, b) {
      final sa = int.tryParse(_s(a, 'stt')) ?? 999999;
      final sb = int.tryParse(_s(b, 'stt')) ?? 999999;
      if (sa != sb) return sa.compareTo(sb);
      final ia = int.tryParse(_s(a, 'id')) ?? 999999;
      final ib = int.tryParse(_s(b, 'id')) ?? 999999;
      return ia.compareTo(ib);
    });
    return locs;
  }

  // ---------------- GIAO DIỆN ----------------

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    bool busy = false,
    bool filled = false,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    );
    final iconW = Icon(icon, size: 15);
    final text = Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
    );
    return SizedBox(
      height: 36,
      child: filled
          ? ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 36),
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

  Widget _filterDropdown() {
    return SizedBox(
      height: 36,
      child: DropdownButtonFormField<String>(
        initialValue: _filter,
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
          constraints: BoxConstraints(minHeight: 36, maxHeight: 36),
          prefixIcon: Icon(Icons.filter_alt_outlined, size: 17),
          prefixIconConstraints: BoxConstraints(
            minWidth: 34,
            minHeight: 36,
            maxHeight: 36,
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        ),
        items: const [
          DropdownMenuItem(value: 'ALL', child: Text("Tất cả")),
          DropdownMenuItem(value: 'PICKUP', child: Text("Điểm nhận")),
          DropdownMenuItem(value: 'DELIVERY', child: Text("Điểm giao")),
        ],
        onChanged: (val) {
          if (val == null) return;
          setState(() {
            _filter = val;
            _currentPage = 1;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    _reportCount(rows.length, _locations.length);

    final totalItems = rows.length;
    final totalPages = (totalItems / _pageSize).ceil().clamp(1, 99999);
    final validPage = _currentPage.clamp(1, totalPages);
    final endIndex = (validPage * _pageSize).clamp(0, totalItems);
    final pageItems = totalItems == 0
        ? <Map<String, dynamic>>[]
        : rows.sublist(0, endIndex);

    return Column(
      children: [
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
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        maxHeight: 36,
                      ),
                      hintText: "Tìm theo tên điểm, khách hàng, địa chỉ, ghi chú...",
                      hintStyle: const TextStyle(fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search, size: 17),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 36,
                        maxHeight: 36,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 36,
                                maxHeight: 36,
                              ),
                              icon: const Icon(Icons.clear, size: 15),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _query = '';
                                _currentPage = 1;
                              }),
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
              Expanded(flex: 2, child: _filterDropdown()),
              const SizedBox(width: 10),
              Tooltip(
                message: "Import danh sách Điểm nhận/Giao từ file Excel theo mẫu DS DIEM VIETMAP.xlsx (dòng bôi vàng = Điểm nhận)",
                child: _toolbarButton(
                  icon: Icons.upload_file_outlined,
                  label: _importBusy ? "Đang import..." : "Import Excel",
                  color: const Color(0xFF2E7D32),
                  busy: _importBusy,
                  onPressed: _importBusy ? null : _importExcel,
                ),
              ),
              const SizedBox(width: 10),
              _toolbarButton(
                icon: Icons.add_location_alt_outlined,
                label: "Thêm điểm",
                color: Colors.blue.shade800,
                filled: true,
                onPressed: () => _showForm(),
              ),
            ],
          ),
        ),
        if (_pickedCount > 0) _buildBulkBar(rows),
        const Divider(height: 1),
        Expanded(
          child: CenterLoadingOverlay(
            isLoading: _loading || _importBusy || _bulkBusy,
            message: _importBusy
                ? 'Đang import danh sách Điểm nhận / giao từ Excel...'
                : (_bulkBusy
                    ? 'Đang xử lý hàng loạt...'
                    : 'Đang tải danh sách điểm nhận / giao...'),
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
    final msg = _locations.isEmpty
        ? "Chưa có điểm nào. Bấm \"Import Excel\" hoặc \"Thêm điểm\" để tạo danh mục."
        : "Không tìm thấy điểm nào phù hợp với bộ lọc";
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 48,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                Text(
                  msg,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataColumn _col(String label) => DataColumn(
    label: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
    ),
  );

  DataCell _cell(Widget child) =>
      DataCell(Container(alignment: Alignment.centerLeft, child: child));

  Widget _badge(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color.shade800,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  MaterialColor _kindColor(String kind) => kind == 'PICKUP'
      ? Colors.amber
      : (kind == 'DELIVERY' ? Colors.blue : Colors.teal);

  String _coord(Map<String, dynamic> m) {
    final lat = double.tryParse(_s(m, 'latitude'));
    final lng = double.tryParse(_s(m, 'longitude'));
    if (lat == null || lng == null) return '';
    return "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
  }

  Widget _buildTable(
    List<Map<String, dynamic>> items, {
    required bool hasMore,
    required VoidCallback onLoadMore,
  }) {
    return VirtualizedDataTable(
      headingRowHeight: 44,
      rowHeight: 62,
      horizontalMargin: 16,
      columnSpacing: 16,
      minTableWidth: 0,
      fixedColumnWidths: const [
        32,   // Checkbox
        42,   // #
        null, // Tên điểm / Địa chỉ
        null, // Loại điểm
        null, // Khách hàng liên kết
        null, // Tọa độ / Bán kính
        null, // Thao tác
      ],
      columnFlexes: const [
        1,
        1,
        30, // Tên điểm / Địa chỉ
        12, // Loại điểm
        20, // Khách hàng liên kết
        18, // Tọa độ / Bán kính
        15, // Thao tác
      ],
      hasMore: hasMore,
      onLoadMore: onLoadMore,
      onRowTap: (idx) {
        _showLocationDetailDialog(items[idx]);
      },
      columns: [
        DataColumn(label: _headerCheckbox(items)),
        _col("#"),
        _col("Tên điểm / Địa chỉ"),
        _col("Loại điểm"),
        _col("Khách hàng"),
        _col("Tọa độ / Bán kính"),
        _col("Thao tác"),
      ],
      itemCount: items.length,
      rowBuilder: (idx) {
        final m = items[idx];
        final selected = _isPicked(m);
        final isPickup = _s(m, 'kind') == 'PICKUP';
        return DataRow(
          color: WidgetStateProperty.all(
            selected
                ? Colors.green.shade50
                : (isPickup
                    ? const Color(0xFFFFFBEB)
                    : (idx % 2 == 0 ? Colors.white : Colors.grey.shade50)),
          ),
          cells: [
            DataCell(_rowCheckbox(m)),
            ..._locationCells(m, idx + 1),
          ],
        );
      },
    );
  }

  Widget _rowCheckbox(Map<String, dynamic> m) {
    if (!_canPick(m)) return const SizedBox(width: 24);
    return SizedBox(
      width: 24,
      height: 24,
      child: Checkbox(
        value: _isPicked(m),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        onChanged: _bulkBusy
            ? null
            : (v) => setState(() => _setPicked(m, v == true)),
      ),
    );
  }

  /// Ô ở tiêu đề: chọn / bỏ chọn mọi dòng trong trang đang xem.
  Widget _headerCheckbox(List<Map<String, dynamic>> items) {
    final pickable = items.where(_canPick).toList();
    if (pickable.isEmpty) return const SizedBox(width: 24);
    final picked = pickable.where(_isPicked).length;
    return Tooltip(
      message: "Chọn tất cả dòng trong trang này",
      child: SizedBox(
        width: 24,
        height: 24,
        child: Checkbox(
          tristate: true,
          value: picked == 0 ? false : (picked == pickable.length ? true : null),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          onChanged: _bulkBusy
               ? null
               : (_) => setState(() {
                  final v = picked != pickable.length;
                  for (final m in pickable) {
                    _setPicked(m, v);
                  }
                }),
        ),
      ),
    );
  }

  Widget _buildBulkBar(List<Map<String, dynamic>> rows) {
    final pickable = rows.where(_canPick).toList();
    final canSelectMore = pickable.any((m) => !_isPicked(m));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.green.shade50,
      child: Row(
        children: [
          Icon(Icons.checklist, size: 18, color: Colors.green.shade800),
          const SizedBox(width: 8),
          Text(
            "Đã chọn ${_selectedLocIds.length} điểm",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade900,
            ),
          ),
          if (canSelectMore) ...[
            const SizedBox(width: 12),
            TextButton(
              onPressed: _bulkBusy
                  ? null
                  : () => setState(() {
                      for (final m in pickable) {
                        _setPicked(m, true);
                      }
                    }),
              child: Text(
                "Chọn tất cả ${pickable.length} dòng đang lọc",
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: _bulkBusy ? null : () => setState(_clearPicked),
            child: const Text("Bỏ chọn", style: TextStyle(fontSize: 12.5)),
          ),
          if (_selectedLocIds.isNotEmpty) ...[
            const SizedBox(width: 8),
            _toolbarButton(
              icon: Icons.delete_outline,
              label: _bulkBusy
                  ? "Đang xử lý..."
                  : "Xóa ${_selectedLocIds.length} điểm",
              color: Colors.red.shade700,
              busy: _bulkBusy,
              onPressed: _bulkBusy ? null : _bulkDelete,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _bulkDelete() async {
    final ids = _selectedLocIds.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text(
          "Xóa ${ids.length} điểm khỏi danh mục",
          style: const TextStyle(fontSize: 17),
        ),
        content: const SizedBox(
          width: 460,
          child: Text(
            "Xác nhận xóa các điểm đã chọn khỏi danh mục? Đơn hàng cũ không bị ảnh hưởng.",
            style: TextStyle(fontSize: 13.5),
          ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text("Xóa ${ids.length} điểm"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _bulkBusy = true);
    final res = await AdminService.bulkDeleteLocations(ids);
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    if (res['ok'] != true) {
      _toast(res['message'].toString(), error: true);
      return;
    }
    final data = res['data'] is Map
        ? Map<String, dynamic>.from(res['data'] as Map)
        : <String, dynamic>{};
    final deleted = int.tryParse('${data['deleted'] ?? 0}') ?? 0;
    setState(() => _selectedLocIds.clear());
    _toast("Đã xóa $deleted điểm");
    _load();
  }

  /// Danh sách bản ghi khách hàng liên kết với điểm (customer_ids).
  List<Map<String, dynamic>> _linkedCustomers(Map<String, dynamic> l) {
    final ids = (l['customer_ids'] as List?) ?? const [];
    final idSet = ids.map((e) => int.tryParse('$e') ?? -1).toSet();
    return _customers
        .where((c) => idSet.contains(int.tryParse('${c['id']}')))
        .toList();
  }

  /// Danh sách tên khách hàng liên kết với điểm (customer_ids).
  List<String> _customerNames(Map<String, dynamic> l) {
    return _linkedCustomers(l)
        .map((c) => (c['name'] ?? '').toString().trim())
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Ô Khách hàng thu gọn trên 1 dòng: bấm vào để bật Dialog chi tiết Điểm & danh sách Khách hàng.
  Widget _customerCell(Map<String, dynamic> l, List<String> custNames) {
    if (custNames.isEmpty) {
      return Text(
        "Dùng chung",
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
      );
    }
    final first = custNames.first;
    final extra = custNames.length - 1;
    return Tooltip(
      message: "Bấm để xem chi tiết ${custNames.length} khách hàng liên kết",
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _showLocationDetailDialog(l),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.indigo.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 14,
                color: Colors.indigo.shade700,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ),
              if (extra > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade700,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    "+$extra",
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Hộp thoại xem chi tiết đầy đủ tất cả các cột VietMap của Điểm nhận/giao + Danh sách Khách hàng liên kết.
  void _showLocationDetailDialog(Map<String, dynamic> l) {
    final kind = _s(l, 'kind').isEmpty ? 'BOTH' : _s(l, 'kind');
    final isPickup = kind == 'PICKUP';
    final stt = _s(l, 'stt');
    final vietmapId = _s(l, 'vietmap_id');
    final category = _s(l, 'category').isNotEmpty ? _s(l, 'category') : 'Chưa phân loại';
    final name = _s(l, 'name');
    final address = _s(l, 'address');
    final lat = _s(l, 'latitude');
    final lng = _s(l, 'longitude');
    final radius = _s(l, 'radius_m').isNotEmpty ? "${_s(l, 'radius_m')} m" : '100 m';
    final phone = _s(l, 'phone');
    final mobile = _s(l, 'mobile');
    final contactPerson = _s(l, 'contact_person');
    final email = _s(l, 'email');
    final allowStop = l['allow_stop'] == true ||
        _s(l, 'allow_stop').toLowerCase() == 'true' ||
        _s(l, 'allow_stop') == '1';
    final note = _s(l, 'note');
    final linkedCusts = _linkedCustomers(l);
    final custFilterCtrl = TextEditingController();

    Widget infoItem(String label, String value, {Color? valueColor, bool bold = false}) {
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
                    : (valueColor ?? Colors.blueGrey.shade900),
              ),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final q = custFilterCtrl.text.trim().toLowerCase();
          final filteredCusts = linkedCusts.where((c) {
            if (q.isEmpty) return true;
            return _s(c, 'name').toLowerCase().contains(q) ||
                _s(c, 'code').toLowerCase().contains(q) ||
                _s(c, 'zalo_group_name').toLowerCase().contains(q) ||
                _s(c, 'product_code').toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            actionsPadding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isPickup ? Colors.amber.shade100 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isPickup ? Icons.warehouse_outlined : Icons.place,
                    size: 20,
                    color: isPickup ? Colors.amber.shade900 : Colors.blue.shade800,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (stt.isNotEmpty) "STT #$stt",
                          if (vietmapId.isNotEmpty) "Id VietMap: $vietmapId",
                          "Danh mục: $category",
                        ].join(' • '),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _badge(_kindLabels[kind] ?? kind, _kindColor(kind)),
              ],
            ),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 12),
                    const Text(
                      "Thông tin chi tiết Điểm nhận / giao (VietMap)",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: infoItem("# (Số thứ tự)", stt)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: infoItem(
                            "Id VietMap",
                            vietmapId,
                            valueColor: Colors.indigo.shade800,
                            bold: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: infoItem("Danh Mục", category)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    infoItem("Địa Chỉ", address, bold: true),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: infoItem("Vĩ Độ (Latitude)", lat)),
                        const SizedBox(width: 8),
                        Expanded(child: infoItem("Kinh Độ (Longitude)", lng)),
                        const SizedBox(width: 8),
                        Expanded(child: infoItem("Bán Kính", radius)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: infoItem("Số ĐT", phone)),
                        const SizedBox(width: 8),
                        Expanded(child: infoItem("Di Động", mobile)),
                        const SizedBox(width: 8),
                        Expanded(child: infoItem("Người Liên Hệ", contactPerson)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(flex: 2, child: infoItem("Email", email)),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: infoItem(
                            "Cho Phép Dừng Xe",
                            allowStop ? "Cho phép (True)" : "Không (False)",
                            valueColor: allowStop
                                ? Colors.green.shade800
                                : Colors.grey.shade700,
                            bold: true,
                          ),
                        ),
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      infoItem("Ghi Chú", note),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          "Khách hàng liên kết (${linkedCusts.length})",
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const Spacer(),
                        if (linkedCusts.isEmpty)
                          Text(
                            "Điểm dùng chung cho mọi khách hàng",
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                    if (linkedCusts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (linkedCusts.length > 4)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            height: 34,
                            child: TextField(
                              controller: custFilterCtrl,
                              onChanged: (_) => setDialogState(() {}),
                              style: const TextStyle(fontSize: 12.5),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: "Tìm nhanh khách hàng trong danh sách liên kết...",
                                prefixIcon: Icon(Icons.search, size: 16),
                                prefixIconConstraints: BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 34,
                                  maxHeight: 34,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: filteredCusts.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    "Không có khách hàng khớp từ khóa",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: filteredCusts.length,
                                  separatorBuilder: (_, _) => Divider(
                                    height: 1,
                                    color: Colors.grey.shade200,
                                  ),
                                  itemBuilder: (_, i) {
                                    final c = filteredCusts[i];
                                    final cName = _s(c, 'name');
                                    final cCode = _s(c, 'code');
                                    final cProd = _s(c, 'product_code');
                                    final cGroup = _s(c, 'zalo_group_name');
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.storefront_outlined,
                                            size: 16,
                                            color: Colors.indigo.shade700,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  "$cName  ($cCode)",
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors
                                                        .blueGrey.shade900,
                                                  ),
                                                ),
                                                if (cProd.isNotEmpty ||
                                                    cGroup.isNotEmpty)
                                                  Text(
                                                    [
                                                      if (cProd.isNotEmpty)
                                                        "SP: $cProd",
                                                      if (cGroup.isNotEmpty)
                                                        "Zalo: $cGroup",
                                                    ].join(' • '),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Colors.grey.shade600,
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
                label: const Text("Chỉnh sửa điểm"),
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showForm(location: l);
                },
              ),
            ],
          );
        },
      ),
    ).then((_) => custFilterCtrl.dispose());
  }

  List<DataCell> _locationCells(Map<String, dynamic> l, int fallbackIndex) {
    final kind = _s(l, 'kind').isEmpty ? 'BOTH' : _s(l, 'kind');
    final sttText = _s(l, 'stt').isNotEmpty ? _s(l, 'stt') : '$fallbackIndex';
    final vietmapId = _s(l, 'vietmap_id');
    final address = _s(l, 'address');
    final radius = _s(l, 'radius_m').isNotEmpty ? _s(l, 'radius_m') : '100';
    final allowStop = l['allow_stop'] == true ||
        _s(l, 'allow_stop').toLowerCase() == 'true' ||
        _s(l, 'allow_stop') == '1';
    final custNames = _customerNames(l);
    final coordStr = _coord(l);
    final subParts = <String>[
      if (vietmapId.isNotEmpty) "Id: $vietmapId",
      if (address.isNotEmpty) address,
    ];
    return [
      // 1. #
      _cell(
        Text(
          sttText,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.blueGrey.shade700,
          ),
        ),
      ),
      // 2. Tên điểm / Địa chỉ
      _cell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: kind == 'PICKUP'
                    ? Colors.amber.shade100
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                kind == 'PICKUP' ? Icons.warehouse_outlined : Icons.place,
                size: 17,
                color: kind == 'PICKUP'
                    ? Colors.amber.shade900
                    : Colors.blue.shade700,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _s(l, 'name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.blueGrey.shade900,
                    ),
                  ),
                  if (subParts.isNotEmpty)
                    Text(
                      subParts.join(' • '),
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
      // 3. Loại điểm (Điểm nhận - dòng bôi vàng / Điểm giao)
      _cell(_badge(_kindLabels[kind] ?? kind, _kindColor(kind))),
      // 4. Khách hàng liên kết (thu gọn 1 dòng, bấm để bật Dialog chi tiết)
      _cell(_customerCell(l, custNames)),
      // 5. Tọa độ / Bán kính
      _cell(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              coordStr.isNotEmpty ? coordStr : "—",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            Text(
              "Bán kính: ${radius}m${allowStop ? ' • Cho dừng' : ''}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
      // 6. Thao tác
      _cell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rowButton(
              Icons.edit,
              "Sửa",
              Colors.blue.shade800,
              Colors.blue.shade300,
              () => _showForm(location: l),
            ),
            const SizedBox(width: 6),
            _rowButton(
              Icons.delete_outline,
              "Xóa",
              Colors.red.shade700,
              Colors.red.shade200,
              () => _confirmDelete(l),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _rowButton(
    IconData icon,
    String label,
    Color color,
    Color border,
    VoidCallback onPressed,
  ) {
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
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      onPressed: onPressed,
    );
  }

  // ---------------- FORM ----------------

  Widget _kindDropdown(String value, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.swap_vert, size: 17),
        prefixIconConstraints: BoxConstraints(minWidth: 34, minHeight: 0),
      ),
      items: _kindLabels.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _textField(
    TextEditingController c,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? type,
    String? Function(String?)? validator,
    String? hint,
    ValueChanged<String>? onChanged,
    Widget? labelTrailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              if (labelTrailing != null) labelTrailing,
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: c,
            maxLines: maxLines,
            keyboardType: type,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 12.5),
              prefixIcon: Icon(icon, size: 17),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 34,
                minHeight: 0,
              ),
            ),
            validator: validator,
          ),
        ],
      ),
    );
  }

  /// Multiselect khách hàng liên kết với điểm nhận / giao.
  /// Gõ để tìm, tick chọn nhiều khách hàng; để trống = điểm dùng chung cho mọi khách hàng.
  Widget _buildCustomerMultiSelect({
    required Set<int> selectedCustomerIds,
    required TextEditingController searchCtrl,
    required VoidCallback onChanged,
  }) {
    final q = searchCtrl.text.trim().toLowerCase();
    final filtered = _customers.where((c) {
      if (q.isEmpty) return true;
      return (c['name'] ?? '').toString().toLowerCase().contains(q) ||
          (c['code'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              "Khách hàng liên kết",
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const Spacer(),
            Text(
              selectedCustomerIds.isEmpty
                  ? "Bỏ trống = dùng chung"
                  : "Đã chọn ${selectedCustomerIds.length}",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selectedCustomerIds.isEmpty
                    ? Colors.grey.shade500
                    : Colors.teal.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: searchCtrl,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            isDense: true,
            hintText: "Gõ để tìm khách hàng...",
            prefixIcon: const Icon(Icons.search, size: 17),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 0,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 150),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "Không có khách hàng khớp",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final c = filtered[index];
                    final cid = int.tryParse('${c['id']}');
                    final checked = cid != null && selectedCustomerIds.contains(cid);
                    return InkWell(
                      onTap: () {
                        if (cid == null) return;
                        checked
                            ? selectedCustomerIds.remove(cid)
                            : selectedCustomerIds.add(cid);
                        onChanged();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: Checkbox(
                                value: checked,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (v) {
                                  if (cid == null) return;
                                  v == true
                                      ? selectedCustomerIds.add(cid)
                                      : selectedCustomerIds.remove(cid);
                                  onChanged();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (c['name'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            Text(
                              (c['code'] ?? '').toString(),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
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

  Future<void> _showForm({Map<String, dynamic>? location}) async {
    final isEdit = location != null;
    final sttCtrl = TextEditingController(
      text: isEdit ? _s(location, 'stt') : '',
    );
    final vietmapIdCtrl = TextEditingController(
      text: isEdit ? _s(location, 'vietmap_id') : '',
    );
    final categoryCtrl = TextEditingController(
      text: isEdit && _s(location, 'category').isNotEmpty
          ? _s(location, 'category')
          : 'Chưa phân loại',
    );
    final nameCtrl = TextEditingController(
      text: isEdit ? _s(location, 'name') : '',
    );
    final addrCtrl = TextEditingController(
      text: isEdit ? _s(location, 'address') : '',
    );
    final latCtrl = TextEditingController(
      text: isEdit ? _s(location, 'latitude') : '',
    );
    final lngCtrl = TextEditingController(
      text: isEdit ? _s(location, 'longitude') : '',
    );
    final phoneCtrl = TextEditingController(
      text: isEdit ? _s(location, 'phone') : '',
    );
    final radiusCtrl = TextEditingController(
      text: isEdit ? _s(location, 'radius_m') : '100',
    );
    final contactPersonCtrl = TextEditingController(
      text: isEdit ? _s(location, 'contact_person') : '',
    );
    final mobileCtrl = TextEditingController(
      text: isEdit ? _s(location, 'mobile') : '',
    );
    final emailCtrl = TextEditingController(
      text: isEdit ? _s(location, 'email') : '',
    );
    bool allowStop = isEdit &&
        (location['allow_stop'] == true ||
            _s(location, 'allow_stop').toLowerCase() == 'true' ||
            _s(location, 'allow_stop') == '1');
    final noteCtrl = TextEditingController(
      text: isEdit ? _s(location, 'note') : '',
    );
    String kind = isEdit && _kindLabels.containsKey(_s(location, 'kind'))
        ? _s(location, 'kind')
        : 'DELIVERY';
    // Multiselect khách hàng liên kết với điểm: rỗng = điểm dùng chung cho mọi khách hàng
    final selectedCustomerIds = (isEdit
            ? ((location['customer_ids'] as List?) ?? const [])
            : const [])
        .map((e) => int.tryParse('$e') ?? -1)
        .where((id) => id > 0)
        .toSet();
    final custSearchCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    // Co chan moi setDialogState khi dialog dang dong: cac callback async
    // (luu diem, tai du lieu) khong duoc cham vao dialog da pop.
    bool dialogClosed = false;

    // Trang thai tu dong lay Vi do / Kinh do tu Dia chi
    Timer? geocodeDebounce;
    int geocodeSeq = 0;
    bool geocoding = false;
    String geocodeStatus = '';
    bool geocodeIsWarning = false;
    bool manualCoordEdited = false;
    bool initialCheckTriggered = false;
    List<AddressSuggestion> addrSuggestions = const [];

    String? coordValidator(String? v, double limit) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return null;
      final n = double.tryParse(t);
      if (n == null || n.abs() > limit) return "Không hợp lệ";
      return null;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> lookupCoords(
            String rawAddress, {
            String? refId,
            bool forceUpdate = false,
            bool showSuggestions = false,
          }) async {
            final q = rawAddress.trim();
            if (q.length < 3) {
              if (!dialogClosed && dialogContext.mounted) {
                setDialogState(() {
                  geocoding = false;
                  addrSuggestions = const [];
                });
              }
              return;
            }
            final mySeq = ++geocodeSeq;
            if (!dialogClosed && dialogContext.mounted) {
              setDialogState(() {
                geocoding = true;
                geocodeStatus = 'Đang tự động tra cứu Vĩ độ và Kinh độ...';
                geocodeIsWarning = false;
              });
            }

            final focusLat = double.tryParse(latCtrl.text.trim());
            final focusLng = double.tryParse(lngCtrl.text.trim());

            final futures = await Future.wait<dynamic>([
              showSuggestions
                  ? AddressGeocoderService.fetchSuggestions(
                      q,
                      focusLat: focusLat,
                      focusLng: focusLng,
                    )
                  : Future.value(const <AddressSuggestion>[]),
              (forceUpdate || !manualCoordEdited)
                  ? AddressGeocoderService.geocodeAddress(
                      q,
                      vietmapRefId: refId,
                    )
                  : Future.value(null),
            ]);

            if (dialogClosed || !dialogContext.mounted || mySeq != geocodeSeq) {
              return;
            }

            final sugs = futures[0] as List<AddressSuggestion>;
            final geo = futures[1] as GeocodedLocation?;

            setDialogState(() {
              geocoding = false;
              if (showSuggestions) {
                addrSuggestions = sugs;
              }
              if (forceUpdate || !manualCoordEdited) {
                if (geo != null) {
                  latCtrl.text = geo.latitude.toStringAsFixed(6);
                  lngCtrl.text = geo.longitude.toStringAsFixed(6);
                  final matchNote = geo.matchedAddress.isNotEmpty
                      ? ' (${geo.matchedAddress})'
                      : '';
                  geocodeStatus = 'Đã tự động điền tọa độ$matchNote';
                  geocodeIsWarning = false;
                } else {
                  geocodeStatus =
                      'Chưa tìm được tọa độ tự động từ địa chỉ này. Hãy nhập chi tiết hơn hoặc bấm "Bản đồ".';
                  geocodeIsWarning = true;
                }
              } else {
                geocodeStatus = '';
              }
            });
          }

          // Neu mo diem da co san dia chi nhung dang thieu toa do -> tu dong lay ngay
          if (!initialCheckTriggered) {
            initialCheckTriggered = true;
            if (addrCtrl.text.trim().length >= 3 &&
                latCtrl.text.trim().isEmpty &&
                lngCtrl.text.trim().isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!dialogClosed && dialogContext.mounted) {
                  lookupCoords(addrCtrl.text, forceUpdate: true);
                }
              });
            }
          }

          Widget compactActionBtn({
            required IconData icon,
            required String label,
            required VoidCallback? onTap,
            required Color color,
          }) {
            return SizedBox(
              height: 28,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                icon: Icon(icon, size: 14),
                label: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onTap,
              ),
            );
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            title: Text(
              isEdit ? "Sửa điểm nhận / giao" : "Thêm điểm nhận / giao",
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 540,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _textField(
                              sttCtrl,
                              "# (STT)",
                              Icons.format_list_numbered,
                              hint: "VD: 1",
                              type: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: _textField(
                              vietmapIdCtrl,
                              "Id (VietMap)",
                              Icons.tag,
                              hint: "VD: 98040",
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 4,
                            child: _textField(
                              categoryCtrl,
                              "Danh Mục",
                              Icons.category_outlined,
                              hint: "VD: Chưa phân loại",
                            ),
                          ),
                        ],
                      ),
                      _textField(
                        nameCtrl,
                        "Tên điểm *",
                        Icons.place_outlined,
                        hint: "VD: Ht_P.Hữu hoặc ACC244(Cầu N.Đ.Chiểu/F.Unisoil",
                        onChanged: (val) {
                          // Neu nguoi dung nhap Ten diem ma Dia chi va Toa do dang trong -> tu dong goi y toa do
                          if (addrCtrl.text.trim().isEmpty &&
                              !manualCoordEdited) {
                            geocodeDebounce?.cancel();
                            geocodeDebounce = Timer(
                              const Duration(milliseconds: 700),
                              () => lookupCoords(val, showSuggestions: false),
                            );
                          }
                        },
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? "Không được để trống"
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Loại điểm (Dòng bôi vàng = Điểm nhận, còn lại = Điểm giao)",
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _kindDropdown(kind, (v) {
                              if (!dialogClosed) setDialogState(() => kind = v);
                            }),
                          ],
                        ),
                      ),
                      _textField(
                        addrCtrl,
                        "Địa chỉ",
                        Icons.location_on_outlined,
                        maxLines: 2,
                        hint:
                            "Nhập địa chỉ (tự động điền Vĩ độ & Kinh độ bên dưới)",
                        labelTrailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            compactActionBtn(
                              icon: Icons.auto_fix_high_outlined,
                              label: geocoding ? "Đang lấy..." : "Lấy tọa độ",
                              color: Colors.teal.shade700,
                              onTap: geocoding
                                  ? null
                                  : () {
                                      geocodeDebounce?.cancel();
                                      manualCoordEdited = false;
                                      final q = addrCtrl.text.trim().isNotEmpty
                                          ? addrCtrl.text.trim()
                                          : nameCtrl.text.trim();
                                      if (q.length < 3) {
                                        _toast(
                                          "Hãy nhập Địa chỉ hoặc Tên điểm trước khi lấy tọa độ",
                                          error: true,
                                        );
                                        return;
                                      }
                                      lookupCoords(
                                        q,
                                        forceUpdate: true,
                                        showSuggestions: false,
                                      );
                                    },
                            ),
                            const SizedBox(width: 6),
                            compactActionBtn(
                              icon: Icons.map_outlined,
                              label: "Bản đồ",
                              color: Colors.blue.shade800,
                              onTap: () async {
                                final picked = await showMapPointPicker(
                                  dialogContext,
                                  apiKey:
                                      AddressGeocoderService.defaultVietmapKey,
                                  title: "Chọn vị trí điểm nhận / giao",
                                  initialLat: double.tryParse(
                                    latCtrl.text.trim(),
                                  ),
                                  initialLng: double.tryParse(
                                    lngCtrl.text.trim(),
                                  ),
                                  radiusM:
                                      int.tryParse(radiusCtrl.text.trim()) ??
                                      100,
                                  initialQuery: addrCtrl.text.trim().isNotEmpty
                                      ? addrCtrl.text.trim()
                                      : nameCtrl.text.trim(),
                                );
                                if (picked == null ||
                                    dialogClosed ||
                                    !dialogContext.mounted) {
                                  return;
                                }
                                setDialogState(() {
                                  manualCoordEdited = true;
                                  addrSuggestions = const [];
                                  latCtrl.text = picked.latitude
                                      .toStringAsFixed(6);
                                  lngCtrl.text = picked.longitude
                                      .toStringAsFixed(6);
                                  if (addrCtrl.text.trim().isEmpty &&
                                      picked.address.trim().isNotEmpty) {
                                    addrCtrl.text = picked.address.trim();
                                  }
                                  geocodeStatus =
                                      'Đã chọn tọa độ trực tiếp từ bản đồ';
                                  geocodeIsWarning = false;
                                });
                              },
                            ),
                          ],
                        ),
                        onChanged: (val) {
                          geocodeDebounce?.cancel();
                          // Neu nguoi dung chu dong sua Dia chi -> cho phep tu dong cap nhat lai toa do
                          manualCoordEdited = false;
                          if (val.trim().length < 3) {
                            setDialogState(() {
                              addrSuggestions = const [];
                              geocodeStatus = '';
                            });
                            return;
                          }
                          geocodeDebounce = Timer(
                            const Duration(milliseconds: 650),
                            () => lookupCoords(
                              val,
                              forceUpdate: true,
                              showSuggestions: true,
                            ),
                          );
                        },
                      ),
                      if (addrSuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.travel_explore,
                                      size: 14,
                                      color: Colors.blue.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        "Gợi ý địa chỉ khớp (bấm để chọn & điền tọa độ):",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () {
                                        if (!dialogClosed) {
                                          setDialogState(
                                            () => addrSuggestions = const [],
                                          );
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(height: 1, color: Colors.blue.shade100),
                              for (final sug in addrSuggestions)
                                InkWell(
                                  onTap: () {
                                    geocodeDebounce?.cancel();
                                    manualCoordEdited = false;
                                    addrCtrl.text = sug.display;
                                    if (nameCtrl.text.trim().isEmpty) {
                                      nameCtrl.text = sug.name;
                                    }
                                    setDialogState(
                                      () => addrSuggestions = const [],
                                    );
                                    lookupCoords(
                                      sug.display,
                                      refId: sug.refId,
                                      forceUpdate: true,
                                      showSuggestions: false,
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.place_outlined,
                                          size: 15,
                                          color: Colors.teal.shade700,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            sug.display,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (geocoding || geocodeStatus.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              if (geocoding)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                  ),
                                )
                              else
                                Icon(
                                  geocodeIsWarning
                                      ? Icons.info_outline
                                      : Icons.check_circle_outline,
                                  size: 14,
                                  color: geocodeIsWarning
                                      ? Colors.orange.shade800
                                      : Colors.green.shade700,
                                ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  geocodeStatus,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: geocoding
                                        ? Colors.blue.shade700
                                        : (geocodeIsWarning
                                              ? Colors.orange.shade800
                                              : Colors.green.shade700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _textField(
                              latCtrl,
                              "Vĩ độ",
                              Icons.my_location,
                              hint: "VD: 10.896916",
                              type: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              onChanged: (val) {
                                manualCoordEdited = true;
                                // Ho tro dan cap "lat, lng" tu Google Maps thang vao o Vi do
                                final parsed =
                                    AddressGeocoderService.tryParseRawCoordinates(
                                      val,
                                    );
                                if (parsed != null) {
                                  latCtrl.text = parsed.latitude
                                      .toStringAsFixed(6);
                                  lngCtrl.text = parsed.longitude
                                      .toStringAsFixed(6);
                                  setDialogState(() {
                                    geocodeStatus =
                                        'Đã tách cặp Vĩ độ / Kinh độ';
                                    geocodeIsWarning = false;
                                  });
                                }
                              },
                              validator: (v) => coordValidator(v, 90),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              lngCtrl,
                              "Kinh độ",
                              Icons.my_location,
                              hint: "VD: 107.242164",
                              type: const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              onChanged: (_) {
                                manualCoordEdited = true;
                              },
                              validator: (v) => coordValidator(v, 180),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              radiusCtrl,
                              "Bán Kính (m)",
                              Icons.radar,
                              hint: "VD: 100",
                              type: TextInputType.number,
                              validator: (v) {
                                final t = (v ?? '').trim();
                                if (t.isEmpty) return null;
                                final n = int.tryParse(t);
                                return (n == null || n < 0 || n > 5000)
                                    ? "Từ 0 đến 5000"
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              phoneCtrl,
                              "Số ĐT",
                              Icons.phone_outlined,
                              hint: "Số điện thoại bàn/trạm",
                              type: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              mobileCtrl,
                              "Di Động",
                              Icons.smartphone_outlined,
                              hint: "Số di động",
                              type: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              contactPersonCtrl,
                              "Người Liên Hệ",
                              Icons.person_outline,
                              hint: "Tên người liên hệ",
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              emailCtrl,
                              "Email",
                              Icons.email_outlined,
                              hint: "VD: dieuphoisaomai@gmail.com",
                              type: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            if (!dialogClosed) {
                              setDialogState(() => allowStop = !allowStop);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: allowStop,
                                    onChanged: (v) {
                                      if (!dialogClosed) {
                                        setDialogState(() => allowStop = v ?? false);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Cho Phép Dừng Xe (True / False)",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _textField(
                        noteCtrl,
                        "Ghi Chú",
                        Icons.notes_outlined,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      // Khách hàng liên kết (chọn nhiều): điểm không gán KH = dùng chung
                      _buildCustomerMultiSelect(
                        selectedCustomerIds: selectedCustomerIds,
                        searchCtrl: custSearchCtrl,
                        onChanged: () {
                          if (!dialogClosed) setDialogState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () {
                        dialogClosed = true;
                        geocodeDebounce?.cancel();
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(dialogContext);
                      },
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
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        geocodeDebounce?.cancel();
                        double? lat = double.tryParse(latCtrl.text.trim());
                        double? lng = double.tryParse(lngCtrl.text.trim());
                        if ((lat == null) != (lng == null)) {
                          _toast(
                            "Phải nhập đủ cả vĩ độ và kinh độ, hoặc để trống cả hai",
                            error: true,
                          );
                          return;
                        }
                        if (!dialogClosed) setDialogState(() => saving = true);

                        // Neu ca 2 o Vi do / Kinh do con trong ma da nhap Dia chi -> tu dong lay truoc khi luu
                        if (lat == null && lng == null && !manualCoordEdited) {
                          final fallbackQ = addrCtrl.text.trim().isNotEmpty
                              ? addrCtrl.text.trim()
                              : nameCtrl.text.trim();
                          if (fallbackQ.length >= 3) {
                            final autoGeo =
                                await AddressGeocoderService.geocodeAddress(
                                  fallbackQ,
                                );
                            if (autoGeo != null) {
                              lat = double.parse(
                                autoGeo.latitude.toStringAsFixed(6),
                              );
                              lng = double.parse(
                                autoGeo.longitude.toStringAsFixed(6),
                              );
                            }
                          }
                        }

                        final res = await AdminService.saveLocation(
                          id: isEdit ? int.tryParse('${location['id']}') : null,
                          data: {
                            'stt': int.tryParse(sttCtrl.text.trim()),
                            'vietmap_id': vietmapIdCtrl.text.trim(),
                            'category': categoryCtrl.text.trim(),
                            'name': nameCtrl.text.trim(),
                            'address': addrCtrl.text.trim(),
                            'kind': kind,
                            'latitude': lat,
                            'longitude': lng,
                            'phone': phoneCtrl.text.trim(),
                            'radius_m': int.tryParse(radiusCtrl.text.trim()),
                            'contact_person': contactPersonCtrl.text.trim(),
                            'mobile': mobileCtrl.text.trim(),
                            'email': emailCtrl.text.trim(),
                            'allow_stop': allowStop,
                            'note': noteCtrl.text.trim(),
                            'customer_ids': selectedCustomerIds.toList(),
                          },
                        );
                        if (dialogClosed || !dialogContext.mounted) return;
                        if (!dialogClosed) setDialogState(() => saving = false);
                        if (res['ok'] == true) {
                          // Go focus va cho frame hien tai ket truoc khi dong
                          // dialog (tranh loi assertion _dependents.isEmpty).
                          FocusManager.instance.primaryFocus?.unfocus();
                          await WidgetsBinding.instance.endOfFrame;
                          dialogClosed = true;
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          _toast(isEdit ? "Đã cập nhật điểm" : "Đã thêm điểm");
                          _load();
                        } else {
                          _toast(res['message'].toString(), error: true);
                        }
                      },
                child: Text(saving ? "Đang lưu..." : "Lưu"),
              ),
            ],
          );
        },
      ),
    );
    geocodeDebounce?.cancel();
    for (final c in [
      sttCtrl,
      vietmapIdCtrl,
      categoryCtrl,
      nameCtrl,
      addrCtrl,
      latCtrl,
      lngCtrl,
      phoneCtrl,
      radiusCtrl,
      contactPersonCtrl,
      mobileCtrl,
      emailCtrl,
      noteCtrl,
      custSearchCtrl,
    ]) {
      c.dispose();
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text("Xác nhận xóa điểm", style: TextStyle(fontSize: 17)),
        content: Text(
          "Xóa điểm \"${_s(l, 'name')}\" khỏi danh mục? Đơn hàng cũ không bị ảnh hưởng.",
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await AdminService.deleteLocation(int.parse('${l['id']}'));
    if (!mounted) return;
    if (res['ok'] == true) {
      _toast("Đã xóa điểm");
      _load();
    } else {
      _toast(res['message'].toString(), error: true);
    }
  }
}
