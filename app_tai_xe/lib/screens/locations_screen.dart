import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_service.dart';

/// Màn hình Điểm nhận / giao hàng.
/// Một danh sách duy nhất gồm:
/// - Điểm đã xác nhận: dùng cho ô Nơi nhận hàng / Điểm giao hàng trong form đơn.
/// - Gợi ý từ lịch sử dừng đỗ GPS: chờ điều phối duyệt (Duyệt / Bỏ qua) ngay trên dòng.
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
  List<Map<String, dynamic>> _suggestions = [];
  // ALL = đã xác nhận + chờ duyệt | CONFIRMED | PENDING | PICKUP | DELIVERY | IGNORED
  String _filter = 'ALL';

  int _currentPage = 1;
  int _pageSize = 10;

  // Chọn nhiều gợi ý chờ duyệt để duyệt cùng lúc
  final Set<int> _selectedIds = {};
  // Chọn nhiều điểm đã xác nhận để xóa cùng lúc
  final Set<int> _selectedLocIds = {};
  bool _bulkBusy = false;

  // Quét GPS
  bool _scanBusy = false;
  String _scanProgress = '';
  Timer? _scanTimer;

  static const _kindLabels = {
    'PICKUP': 'Điểm nhận',
    'DELIVERY': 'Điểm giao',
    'BOTH': 'Nhận và giao',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _checkRunningScan();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
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
      AdminService.fetchLocationSuggestions(status: 'ALL'),
    ]);
    if (!mounted) return;
    setState(() {
      _locations = _asMaps(results[0]);
      _suggestions = _asMaps(results[1]);
      _loading = false;
      _pruneSelection();
    });
  }

  Future<void> _loadSuggestions() async {
    final rows = await AdminService.fetchLocationSuggestions(status: 'ALL');
    if (!mounted) return;
    setState(() {
      _suggestions = _asMaps(rows);
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

  // ---------------- QUÉT GPS ----------------

  Future<void> _checkRunningScan() async {
    final st = await AdminService.fetchLocationScanStatus();
    if (!mounted) return;
    if (st['ok'] == true &&
        st['data'] is Map &&
        st['data']['running'] == true) {
      _startPolling();
    }
  }

  Future<void> _onScan() async {
    if (_scanBusy) return;
    final vmCtrl = TextEditingController(text: '30');
    final baCtrl = TextEditingController(text: '7');
    final minStopCtrl = TextEditingController(text: '15');
    final formKey = GlobalKey<FormState>();

    String? numValidator(String? v, int min, int max) {
      final n = int.tryParse((v ?? '').trim());
      if (n == null || n < min || n > max) return "Từ $min đến $max";
      return null;
    }

    Widget numField(
      TextEditingController c,
      String label,
      String helper,
      int min,
      int max,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(labelText: label, helperText: helper),
          validator: (v) => numValidator(v, min, max),
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text(
          "Quét lịch sử dừng đỗ",
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Máy chủ sẽ lấy toàn bộ các lần dừng đỗ của đội xe và đề xuất hết thành gợi ý, "
                    "kể cả chỗ chỉ dừng 1 lần. Địa chỉ đã có trong danh mục hoặc đã từng gợi ý sẽ không lấy lại.",
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  numField(
                    vmCtrl,
                    "Số ngày quét Vietmap",
                    "0 = bỏ qua Vietmap, tối đa 31",
                    0,
                    31,
                  ),
                  numField(
                    baCtrl,
                    "Số ngày quét Bình Anh",
                    "0 = bỏ qua Bình Anh, tối đa 31 (quét lâu hơn Vietmap)",
                    0,
                    31,
                  ),
                  numField(
                    minStopCtrl,
                    "Dừng tối thiểu (phút)",
                    "Dừng ngắn hơn sẽ bị bỏ qua",
                    1,
                    1440,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Hủy bỏ"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: () {
              if (formKey.currentState!.validate())
                Navigator.pop(dialogContext, true);
            },
            child: const Text("Bắt đầu quét"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final options = {
      'vietmap_days': int.parse(vmCtrl.text.trim()),
      'binhanh_days': int.parse(baCtrl.text.trim()),
      'min_stop_minutes': int.parse(minStopCtrl.text.trim()),
    };
    final res = await AdminService.startLocationScan(options);
    if (!mounted) return;
    if (res['ok'] != true) {
      _toast(res['message'].toString(), error: true);
      return;
    }
    _startPolling();
  }

  void _startPolling() {
    _scanTimer?.cancel();
    setState(() {
      _scanBusy = true;
      _scanProgress = 'Đang quét...';
    });
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _scanTick());
  }

  Future<void> _scanTick() async {
    final st = await AdminService.fetchLocationScanStatus();
    if (!mounted || _scanTimer == null) return;
    if (st['ok'] != true || st['data'] is! Map) return;
    final data = Map<String, dynamic>.from(st['data'] as Map);
    if (data['running'] == true) {
      setState(
        () => _scanProgress = (data['progress'] ?? 'Đang quét...').toString(),
      );
      return;
    }
    _scanTimer?.cancel();
    _scanTimer = null;
    final r = data['result'] is Map
        ? Map<String, dynamic>.from(data['result'])
        : <String, dynamic>{};
    int n(String k) => int.tryParse('${r[k] ?? 0}') ?? 0;
    final errors = (r['errors'] is List)
        ? (r['errors'] as List).join('; ')
        : '';
    setState(() {
      _scanBusy = false;
      _scanProgress = '';
    });
    if (data['error'] != null) {
      _toast("Quét lỗi: ${data['error']}", error: true);
    } else {
      _toast(
        "Quét xong: ${n('stops')} lần dừng, gợi ý mới ${n('inserted')}, "
        "bỏ qua ${n('skipped_existing')} địa chỉ đã gợi ý và ${n('skipped_in_catalog')} địa chỉ đã có trong danh mục"
        "${errors.isNotEmpty ? '. Lỗi: $errors' : ''}",
        error: errors.isNotEmpty,
      );
    }
    _loadSuggestions();
  }

  // ---------------- LỌC ----------------

  bool _isLoc(Map<String, dynamic> m) => m['_row'] == 'LOC';

  int get _pendingCount =>
      _suggestions.where((x) => _s(x, 'status') == 'PENDING').length;

  int? _sugId(Map<String, dynamic> m) => int.tryParse(_s(m, 'id'));

  bool _isSelectable(Map<String, dynamic> m) =>
      !_isLoc(m) && _s(m, 'status') == 'PENDING' && _sugId(m) != null;

  int? _locId(Map<String, dynamic> m) =>
      _isLoc(m) ? int.tryParse(_s(m, 'id')) : null;

  /// Dòng có ô chọn: gợi ý chờ duyệt (để duyệt) hoặc điểm đã xác nhận (để xóa).
  bool _canPick(Map<String, dynamic> m) =>
      _isSelectable(m) || _locId(m) != null;

  bool _isPicked(Map<String, dynamic> m) {
    if (_isLoc(m)) {
      final id = _locId(m);
      return id != null && _selectedLocIds.contains(id);
    }
    final id = _sugId(m);
    return id != null && _selectedIds.contains(id);
  }

  void _setPicked(Map<String, dynamic> m, bool v) {
    if (_isLoc(m)) {
      final id = _locId(m);
      if (id == null) return;
      v ? _selectedLocIds.add(id) : _selectedLocIds.remove(id);
    } else if (_isSelectable(m)) {
      final id = _sugId(m)!;
      v ? _selectedIds.add(id) : _selectedIds.remove(id);
    }
  }

  int get _pickedCount => _selectedIds.length + _selectedLocIds.length;

  void _clearPicked() {
    _selectedIds.clear();
    _selectedLocIds.clear();
  }

  /// Bỏ khỏi danh sách đang chọn những gợi ý không còn chờ duyệt (đã duyệt, bỏ qua, bị xóa).
  void _pruneSelection() {
    final pending = _suggestions
        .where((x) => _s(x, 'status') == 'PENDING')
        .map(_sugId)
        .whereType<int>()
        .toSet();
    _selectedIds.retainWhere(pending.contains);
    final locIds = _locations
        .map((x) => int.tryParse(_s(x, 'id')))
        .whereType<int>()
        .toSet();
    _selectedLocIds.retainWhere(locIds.contains);
  }

  /// Danh sách gộp: điểm đã xác nhận (theo tên) rồi tới gợi ý GPS (theo số lần dừng).
  /// Gợi ý đã duyệt không hiện lại vì đã nằm trong danh sách điểm.
  List<Map<String, dynamic>> get _visibleRows {
    final q = _query.toLowerCase().trim();
    final locs = _locations.map((l) => {...l, '_row': 'LOC'}).where((l) {
      final kind = _s(l, 'kind').isEmpty ? 'BOTH' : _s(l, 'kind');
      switch (_filter) {
        case 'PENDING':
        case 'IGNORED':
          return false;
        case 'PICKUP':
          if (kind == 'DELIVERY') return false;
          break;
        case 'DELIVERY':
          if (kind == 'PICKUP') return false;
          break;
      }
      if (q.isEmpty) return true;
      return [
        'name',
        'address',
        'note',
      ].any((k) => _s(l, k).toLowerCase().contains(q));
    }).toList();
    locs.sort(
      (a, b) =>
          _s(a, 'name').toLowerCase().compareTo(_s(b, 'name').toLowerCase()),
    );

    final wantStatus = _filter == 'IGNORED'
        ? 'IGNORED'
        : ((_filter == 'ALL' || _filter == 'PENDING') ? 'PENDING' : null);
    final sugs = wantStatus == null
        ? <Map<String, dynamic>>[]
        : _suggestions
              .where((x) => _s(x, 'status') == wantStatus)
              .map((x) => {...x, '_row': 'SUG'})
              .where((x) {
                if (q.isEmpty) return true;
                return [
                  'address',
                  'station_name',
                  'vehicles',
                ].any((k) => _s(x, k).toLowerCase().contains(q));
              })
              .toList();
    return [...locs, ...sugs];
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
    final iconW = busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? Colors.white : color,
            ),
          )
        : Icon(icon, size: 15);
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
          DropdownMenuItem(value: 'CONFIRMED', child: Text("Đã xác nhận")),
          DropdownMenuItem(value: 'PENDING', child: Text("Chờ duyệt (từ GPS)")),
          DropdownMenuItem(value: 'PICKUP', child: Text("Điểm nhận")),
          DropdownMenuItem(value: 'DELIVERY', child: Text("Điểm giao")),
          DropdownMenuItem(value: 'IGNORED', child: Text("Đã bỏ qua")),
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
    _reportCount(rows.length, _locations.length + _pendingCount);

    final totalItems = rows.length;
    final totalPages = (totalItems / _pageSize).ceil().clamp(1, 99999);
    final validPage = _currentPage.clamp(1, totalPages);
    final startIndex = totalItems == 0 ? 0 : (validPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize > totalItems)
        ? totalItems
        : startIndex + _pageSize;
    final pageItems = totalItems == 0
        ? <Map<String, dynamic>>[]
        : rows.sublist(startIndex, endIndex);

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
                      hintText: "Tìm theo tên, địa chỉ, ghi chú, biển số...",
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
              const SizedBox(width: 12),
              _toolbarButton(
                icon: Icons.add_location_alt_outlined,
                label: "Thêm điểm",
                color: Colors.blue.shade800,
                filled: true,
                onPressed: () => _showForm(),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message:
                    "Lấy các chỗ xe từng dừng đỗ từ lịch sử GPS thành gợi ý",
                child: _toolbarButton(
                  icon: Icons.travel_explore,
                  label: _scanBusy ? "Đang quét..." : "Quét GPS",
                  color: Colors.teal.shade700,
                  busy: _scanBusy,
                  onPressed: _scanBusy ? null : _onScan,
                ),
              ),
            ],
          ),
        ),
        if (_pickedCount > 0) _buildBulkBar(rows),
        if (_scanProgress.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.teal.shade50,
            child: Text(
              _scanProgress,
              style: TextStyle(
                fontSize: 12,
                color: Colors.teal.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: pageItems.isEmpty
                      ? _buildEmpty()
                      : _buildTable(pageItems),
                ),
        ),
        if (!_loading && totalItems > 0)
          _buildPagination(
            totalItems: totalItems,
            startIndex: startIndex,
            endIndex: endIndex,
            validPage: validPage,
            totalPages: totalPages,
          ),
      ],
    );
  }

  Widget _buildEmpty() {
    final String msg;
    if (_locations.isEmpty && _suggestions.isEmpty) {
      msg =
          "Chưa có điểm nào. Bấm \"Thêm điểm\" hoặc \"Quét GPS\" để lấy các chỗ xe từng dừng đỗ.";
    } else if (_filter == 'IGNORED') {
      msg = "Không có gợi ý nào đã bỏ qua";
    } else {
      msg = "Không tìm thấy điểm nào phù hợp với bộ lọc";
    }
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

  Widget _plain(String text, {double maxWidth = 260}) {
    if (text.isEmpty)
      return Text(
        "—",
        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
      );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }

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
      ? Colors.blue
      : (kind == 'DELIVERY' ? Colors.orange : Colors.teal);

  String _coord(Map<String, dynamic> m) {
    final lat = double.tryParse(_s(m, 'latitude'));
    final lng = double.tryParse(_s(m, 'longitude'));
    if (lat == null || lng == null) return '';
    return "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
  }

  Widget _scrollTable(DataTable table) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: table,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> items) {
    return _scrollTable(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        headingRowHeight: 44,
        dividerThickness: 0,
        dataRowMaxHeight: 68,
        dataRowMinHeight: 58,
        horizontalMargin: 8,
        columnSpacing: 24,
        columns: [
          DataColumn(label: _headerCheckbox(items)),
          _col("Tên điểm / Địa chỉ"),
          _col("Trạng thái"),
          _col("Loại"),
          _col("Tọa độ"),
          _col("Dừng đỗ"),
          _col("Thao tác"),
        ],
        rows: List.generate(items.length, (idx) {
          final m = items[idx];
          final isLoc = _isLoc(m);
          final selected = _isPicked(m);
          return DataRow(
            color: WidgetStateProperty.all(
              selected
                  ? Colors.green.shade50
                  : (idx % 2 == 0 ? Colors.white : Colors.grey.shade50),
            ),
            cells: [
              DataCell(_rowCheckbox(m)),
              ...(isLoc ? _locationCells(m) : _suggestionCells(m)),
            ],
          );
        }),
      ),
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

  /// Ô ở tiêu đề: chọn / bỏ chọn mọi dòng chọn được (điểm và gợi ý chờ duyệt) của trang đang xem.
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
    final parts = <String>[
      if (_selectedLocIds.isNotEmpty)
        "${_selectedLocIds.length} điểm đã xác nhận",
      if (_selectedIds.isNotEmpty) "${_selectedIds.length} gợi ý chờ duyệt",
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.green.shade50,
      child: Row(
        children: [
          Icon(Icons.checklist, size: 18, color: Colors.green.shade800),
          const SizedBox(width: 8),
          Text(
            "Đã chọn ${parts.join(', ')}",
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
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(width: 8),
            _toolbarButton(
              icon: Icons.done_all,
              label: _bulkBusy
                  ? "Đang duyệt..."
                  : "Duyệt ${_selectedIds.length} điểm",
              color: Colors.green.shade700,
              filled: true,
              busy: _bulkBusy,
              onPressed: _bulkBusy ? null : _bulkApprove,
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
            "Đơn hàng cũ không bị ảnh hưởng. Điểm nào được duyệt từ gợi ý GPS thì gợi ý đó quay về trạng thái Chờ duyệt.",
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

  Future<void> _bulkApprove() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final picked = _suggestions.where((x) => ids.contains(_sugId(x))).toList();
    String kind = 'BOTH';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Text(
            "Duyệt ${ids.length} gợi ý vào danh mục",
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Tên điểm sẽ lấy theo địa chỉ GPS, bán kính mặc định 100 m. "
                  "Muốn đổi tên dễ nhớ thì bấm Sửa từng điểm sau khi duyệt.",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                _kindDropdown(kind, (v) => setDialogState(() => kind = v)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: picked.length,
                      itemBuilder: (_, i) {
                        final x = picked[i];
                        final station = _s(x, 'station_name');
                        final name = station.isNotEmpty
                            ? station
                            : _s(x, 'address');
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: Text(
                            "${i + 1}. ${name.isEmpty ? 'Không rõ địa chỉ' : name}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        );
                      },
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
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text("Duyệt ${ids.length} điểm"),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _bulkBusy = true);
    final res = await AdminService.bulkApproveLocationSuggestions(
      ids,
      kind: kind,
    );
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    if (res['ok'] != true) {
      _toast(res['message'].toString(), error: true);
      return;
    }
    final data = res['data'] is Map
        ? Map<String, dynamic>.from(res['data'] as Map)
        : <String, dynamic>{};
    final approved = int.tryParse('${data['approved'] ?? 0}') ?? 0;
    final skippedItems = (data['skipped_items'] is List)
        ? data['skipped_items'] as List
        : const [];
    setState(() => _selectedIds.clear());
    if (skippedItems.isEmpty) {
      _toast("Đã duyệt $approved điểm vào danh mục");
    } else {
      final reasons = skippedItems
          .whereType<Map>()
          .map((e) => (e['reason'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .take(3)
          .join('; ');
      _toast(
        "Đã duyệt $approved điểm, bỏ qua ${skippedItems.length}: $reasons",
        error: approved == 0,
      );
    }
    _load();
  }

  Widget _nameCell({
    required String title,
    required String subtitle,
    required bool confirmed,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: confirmed ? Colors.blue.shade50 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            confirmed ? Icons.place : Icons.wrong_location_outlined,
            size: 18,
            color: confirmed ? Colors.blue : Colors.amber.shade800,
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blueGrey.shade900,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<DataCell> _locationCells(Map<String, dynamic> l) {
    final kind = _s(l, 'kind').isEmpty ? 'BOTH' : _s(l, 'kind');
    final fromGps = _s(l, 'source').startsWith('GPS');
    final address = _s(l, 'address');
    final note = _s(l, 'note');
    return [
      _cell(
        _nameCell(
          title: _s(l, 'name'),
          subtitle: [address, note].where((e) => e.isNotEmpty).join(' • '),
          confirmed: true,
        ),
      ),
      _cell(
        Tooltip(
          message: fromGps ? "Đã duyệt từ lịch sử dừng đỗ GPS" : "Tạo thủ công",
          child: _badge("Đã xác nhận", Colors.green),
        ),
      ),
      _cell(_badge(_kindLabels[kind] ?? kind, _kindColor(kind))),
      _cell(_plain(_coord(l), maxWidth: 170)),
      _cell(
        Text(
          "—",
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
        ),
      ),
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
            const SizedBox(width: 8),
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

  List<DataCell> _suggestionCells(Map<String, dynamic> x) {
    final station = _s(x, 'station_name');
    final address = _s(x, 'address');
    final minutes = int.tryParse(_s(x, 'total_minutes')) ?? 0;
    final duration = minutes >= 60
        ? "${minutes ~/ 60} giờ ${minutes % 60} phút"
        : "$minutes phút";
    final lastSeen = _s(x, 'last_seen').replaceFirst('T', ' ');
    final lastShort = lastSeen.length > 16
        ? lastSeen.substring(0, 16)
        : lastSeen;
    final status = _s(x, 'status');
    final ignored = status == 'IGNORED';
    return [
      _cell(
        _nameCell(
          title: station.isNotEmpty
              ? station
              : (address.isNotEmpty ? address : "Không rõ địa chỉ"),
          subtitle: station.isNotEmpty && address.isNotEmpty ? address : '',
          confirmed: false,
        ),
      ),
      _cell(
        Tooltip(
          message:
              "Lấy từ lịch sử dừng đỗ GPS, chưa dùng được trong form đơn cho tới khi duyệt",
          child: ignored
              ? _badge("Đã bỏ qua", Colors.grey)
              : _badge("Chờ duyệt", Colors.amber),
        ),
      ),
      _cell(
        Text(
          "—",
          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
        ),
      ),
      _cell(_plain(_coord(x), maxWidth: 170)),
      _cell(
        Tooltip(
          message:
              "Xe: ${_s(x, 'vehicles')}\nTổng thời gian: $duration\nLần cuối: $lastShort",
          child: Text(
            "${_s(x, 'visit_count')} lần • ${_s(x, 'vehicle_count')} xe",
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      _cell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ignored)
              _rowButton(
                Icons.undo,
                "Khôi phục",
                Colors.blue.shade800,
                Colors.blue.shade300,
                () => _restore(x),
              )
            else ...[
              _rowButton(
                Icons.check,
                "Duyệt",
                Colors.green.shade800,
                Colors.green.shade300,
                () => _approve(x),
              ),
              const SizedBox(width: 8),
              _rowButton(
                Icons.block,
                "Bỏ qua",
                Colors.grey.shade700,
                Colors.grey.shade400,
                () => _ignore(x),
              ),
            ],
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

  Widget _buildPagination({
    required int totalItems,
    required int startIndex,
    required int endIndex,
    required int validPage,
    required int totalPages,
  }) {
    Widget navBtn(IconData icon, String tip, bool enabled, int page) =>
        IconButton(
          icon: Icon(icon, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: tip,
          onPressed: enabled ? () => setState(() => _currentPage = page) : null,
        );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade400, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems điểm",
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
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<int>(
                tooltip: "Số dòng mỗi trang",
                initialValue: _pageSize,
                position: PopupMenuPosition.over,
                constraints: const BoxConstraints(minWidth: 64),
                onSelected: (val) => setState(() {
                  _pageSize = val;
                  _currentPage = 1;
                }),
                itemBuilder: (_) => const [5, 10, 20, 50]
                    .map(
                      (n) => PopupMenuItem<int>(
                        value: n,
                        height: 36,
                        child: Text(
                          "$n",
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    )
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$_pageSize",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              navBtn(Icons.first_page, "Trang đầu", validPage > 1, 1),
              navBtn(
                Icons.chevron_left,
                "Trang trước",
                validPage > 1,
                validPage - 1,
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
              navBtn(
                Icons.chevron_right,
                "Trang sau",
                validPage < totalPages,
                validPage + 1,
              ),
              navBtn(
                Icons.last_page,
                "Trang cuối",
                validPage < totalPages,
                totalPages,
              ),
            ],
          ),
        ],
      ),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: c,
            maxLines: maxLines,
            keyboardType: type,
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

  Future<void> _showForm({Map<String, dynamic>? location}) async {
    final isEdit = location != null;
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
    final radiusCtrl = TextEditingController(
      text: isEdit ? _s(location, 'radius_m') : '100',
    );
    final noteCtrl = TextEditingController(
      text: isEdit ? _s(location, 'note') : '',
    );
    String kind = isEdit && _kindLabels.containsKey(_s(location, 'kind'))
        ? _s(location, 'kind')
        : 'BOTH';
    final formKey = GlobalKey<FormState>();
    bool saving = false;

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
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Text(
            isEdit ? "Sửa điểm nhận / giao" : "Thêm điểm nhận / giao",
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _textField(
                      nameCtrl,
                      "Tên điểm *",
                      Icons.place_outlined,
                      hint: "VD: Kho Xi Măng Bỉm Sơn",
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? "Không được để trống"
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _kindDropdown(
                        kind,
                        (v) => setDialogState(() => kind = v),
                      ),
                    ),
                    _textField(
                      addrCtrl,
                      "Địa chỉ",
                      Icons.location_on_outlined,
                      maxLines: 2,
                      hint: "Nhập địa chỉ chi tiết",
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
                            validator: (v) => coordValidator(v, 180),
                          ),
                        ),
                      ],
                    ),
                    _textField(
                      radiusCtrl,
                      "Bán kính nhận diện (m)",
                      Icons.radar,
                      hint: "VD: 100",
                      type: TextInputType.number,
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final n = int.tryParse(t);
                        return (n == null || n < 10 || n > 5000)
                            ? "Từ 10 đến 5000"
                            : null;
                      },
                    ),
                    _textField(
                      noteCtrl,
                      "Ghi chú",
                      Icons.notes_outlined,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
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
                      final lat = double.tryParse(latCtrl.text.trim());
                      final lng = double.tryParse(lngCtrl.text.trim());
                      if ((lat == null) != (lng == null)) {
                        _toast(
                          "Phải nhập đủ cả vĩ độ và kinh độ, hoặc để trống cả hai",
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      final res = await AdminService.saveLocation(
                        id: isEdit ? int.tryParse('${location['id']}') : null,
                        data: {
                          'name': nameCtrl.text.trim(),
                          'address': addrCtrl.text.trim(),
                          'kind': kind,
                          'latitude': lat,
                          'longitude': lng,
                          'radius_m': int.tryParse(radiusCtrl.text.trim()),
                          'note': noteCtrl.text.trim(),
                        },
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() => saving = false);
                      if (res['ok'] == true) {
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
        ),
      ),
    );
    for (final c in [
      nameCtrl,
      addrCtrl,
      latCtrl,
      lngCtrl,
      radiusCtrl,
      noteCtrl,
    ]) {
      c.dispose();
    }
  }

  Future<void> _approve(Map<String, dynamic> s) async {
    final station = _s(s, 'station_name');
    final address = _s(s, 'address');
    final nameCtrl = TextEditingController(
      text: station.isNotEmpty ? station : address,
    );
    final addrCtrl = TextEditingController(text: address);
    final noteCtrl = TextEditingController();
    String kind = 'BOTH';
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Text(
            "Duyệt gợi ý vào danh mục",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${_s(s, 'visit_count')} lần dừng, ${_s(s, 'vehicle_count')} xe. Tọa độ: ${_coord(s)}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      nameCtrl,
                      "Tên điểm *",
                      Icons.place_outlined,
                      hint: "VD: Kho Xi Măng Bỉm Sơn",
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? "Đặt tên dễ nhớ, ví dụ: Kho Xi Măng Bỉm Sơn"
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _kindDropdown(
                        kind,
                        (v) => setDialogState(() => kind = v),
                      ),
                    ),
                    _textField(
                      addrCtrl,
                      "Địa chỉ",
                      Icons.location_on_outlined,
                      maxLines: 2,
                      hint: "Nhập địa chỉ chi tiết",
                    ),
                    _textField(
                      noteCtrl,
                      "Ghi chú",
                      Icons.notes_outlined,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text("Hủy bỏ"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
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
                      setDialogState(() => saving = true);
                      final res = await AdminService.approveLocationSuggestion(
                        int.parse('${s['id']}'),
                        {
                          'name': nameCtrl.text.trim(),
                          'address': addrCtrl.text.trim(),
                          'kind': kind,
                          'note': noteCtrl.text.trim(),
                        },
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() => saving = false);
                      if (res['ok'] == true) {
                        Navigator.pop(dialogContext);
                        _toast(
                          "Đã thêm \"${nameCtrl.text.trim()}\" vào danh mục",
                        );
                        _load();
                      } else {
                        _toast(res['message'].toString(), error: true);
                      }
                    },
              child: Text(saving ? "Đang lưu..." : "Duyệt"),
            ),
          ],
        ),
      ),
    );
    for (final c in [nameCtrl, addrCtrl, noteCtrl]) {
      c.dispose();
    }
  }

  Future<void> _ignore(Map<String, dynamic> s) async {
    final res = await AdminService.ignoreLocationSuggestion(
      int.parse('${s['id']}'),
    );
    if (!mounted) return;
    if (res['ok'] == true) {
      _toast("Đã bỏ qua gợi ý");
      _loadSuggestions();
    } else {
      _toast(res['message'].toString(), error: true);
    }
  }

  Future<void> _restore(Map<String, dynamic> s) async {
    final res = await AdminService.restoreLocationSuggestion(
      int.parse('${s['id']}'),
    );
    if (!mounted) return;
    if (res['ok'] == true) {
      _toast("Đã đưa gợi ý về hàng chờ duyệt");
      _loadSuggestions();
    } else {
      _toast(res['message'].toString(), error: true);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text("Xác nhận xóa điểm", style: TextStyle(fontSize: 17)),
        content: Text(
          "Xóa điểm \"${_s(l, 'name')}\" khỏi danh mục? Đơn hàng cũ không bị ảnh hưởng. "
          "Nếu điểm này được duyệt từ gợi ý GPS, gợi ý sẽ quay về trạng thái Chờ duyệt.",
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
