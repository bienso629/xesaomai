import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_service.dart';

/// Màn hình Điểm nhận / giao hàng.
/// - Tab "Danh mục": điểm do người dùng quản lý, dùng cho ô Nơi nhận hàng / Điểm giao hàng.
/// - Tab "Gợi ý từ GPS": điểm xe hay dừng đỗ, gom từ lịch sử Vietmap và Bình Anh, chờ duyệt.
/// Chỉ Điều phối viên, Quản lý / Giám đốc và Admin được vào.
class LocationsScreen extends StatefulWidget {
  final void Function(int filtered, int total)? onCountChanged;

  const LocationsScreen({super.key, this.onCountChanged});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  int _tab = 0; // 0 = Danh mục, 1 = Gợi ý từ GPS
  String _query = '';
  bool _loading = true;
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _suggestions = [];
  String _kindFilter = 'ALL'; // ALL | PICKUP | DELIVERY | BOTH
  String _sugStatus = 'PENDING'; // PENDING | IGNORED | APPROVED

  int _currentPage = 1;
  int _pageSize = 10;

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

  String _s(Map<String, dynamic> c, String key) => (c[key] ?? '').toString().trim();

  List<Map<String, dynamic>> _asMaps(List<dynamic> raw) =>
      raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      AdminService.fetchLocations(),
      AdminService.fetchLocationSuggestions(status: _sugStatus),
    ]);
    if (!mounted) return;
    setState(() {
      _locations = _asMaps(results[0]);
      _suggestions = _asMaps(results[1]);
      _loading = false;
    });
  }

  Future<void> _loadSuggestions() async {
    final rows = await AdminService.fetchLocationSuggestions(status: _sugStatus);
    if (!mounted) return;
    setState(() => _suggestions = _asMaps(rows));
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
    if (st['ok'] == true && st['data'] is Map && st['data']['running'] == true) {
      _startPolling();
    }
  }

  Future<void> _onScan() async {
    if (_scanBusy) return;
    final vmCtrl = TextEditingController(text: '30');
    final baCtrl = TextEditingController(text: '7');
    final minStopCtrl = TextEditingController(text: '15');
    final minVisitCtrl = TextEditingController(text: '2');
    final formKey = GlobalKey<FormState>();

    String? numValidator(String? v, int min, int max) {
      final n = int.tryParse((v ?? '').trim());
      if (n == null || n < min || n > max) return "Từ $min đến $max";
      return null;
    }

    Widget numField(TextEditingController c, String label, String helper, int min, int max) {
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
        title: const Text("Quét lịch sử dừng đỗ", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                    "Máy chủ sẽ lấy các lần dừng đỗ của toàn bộ xe Vietmap và Bình Anh, gom những chỗ "
                    "xe hay dừng thành gợi ý. Điểm đã có trong danh mục sẽ không gợi ý lại.",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  numField(vmCtrl, "Số ngày quét Vietmap", "0 = bỏ qua Vietmap, tối đa 31", 0, 31),
                  numField(baCtrl, "Số ngày quét Bình Anh", "0 = bỏ qua Bình Anh, tối đa 31 (quét lâu hơn Vietmap)", 0, 31),
                  numField(minStopCtrl, "Dừng tối thiểu (phút)", "Dừng ngắn hơn sẽ bị bỏ qua", 1, 1440),
                  numField(minVisitCtrl, "Số lần dừng tối thiểu", "Chỗ dừng ít hơn số lần này sẽ không thành gợi ý", 1, 100),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Hủy bỏ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
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
      'min_visits': int.parse(minVisitCtrl.text.trim()),
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
      setState(() => _scanProgress = (data['progress'] ?? 'Đang quét...').toString());
      return;
    }
    _scanTimer?.cancel();
    _scanTimer = null;
    final r = data['result'] is Map ? Map<String, dynamic>.from(data['result']) : <String, dynamic>{};
    int n(String k) => int.tryParse('${r[k] ?? 0}') ?? 0;
    final errors = (r['errors'] is List) ? (r['errors'] as List).join('; ') : '';
    setState(() {
      _scanBusy = false;
      _scanProgress = '';
    });
    if (data['error'] != null) {
      _toast("Quét lỗi: ${data['error']}", error: true);
    } else {
      _toast(
        "Quét xong: ${n('vietmap_stops')} lần dừng Vietmap, ${n('binhanh_stops')} lần dừng Bình Anh, "
        "gợi ý mới ${n('inserted')}, cập nhật ${n('updated')}"
        "${errors.isNotEmpty ? '. Lỗi: $errors' : ''}",
        error: errors.isNotEmpty,
      );
    }
    _loadSuggestions();
  }

  // ---------------- LỌC ----------------

  List<Map<String, dynamic>> get _visibleLocations {
    final q = _query.toLowerCase().trim();
    final list = _locations.where((l) {
      if (_kindFilter != 'ALL' && _s(l, 'kind') != _kindFilter) return false;
      if (q.isEmpty) return true;
      return ['name', 'address', 'note'].any((k) => _s(l, k).toLowerCase().contains(q));
    }).toList();
    list.sort((a, b) => _s(a, 'name').toLowerCase().compareTo(_s(b, 'name').toLowerCase()));
    return list;
  }

  List<Map<String, dynamic>> get _visibleSuggestions {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return _suggestions;
    return _suggestions
        .where((s) => ['address', 'station_name', 'vehicles'].any((k) => _s(s, k).toLowerCase().contains(q)))
        .toList();
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
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));
    final iconW = busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: filled ? Colors.white : color),
          )
        : Icon(icon, size: 15);
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

  Widget _tabChip(int index, String label, int count) {
    final selected = _tab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => setState(() {
        _tab = index;
        _currentPage = 1;
      }),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade800 : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: selected ? Colors.blue.shade800 : Colors.grey.shade300),
        ),
        child: Text(
          "$label ($count)",
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.blueGrey.shade800,
          ),
        ),
      ),
    );
  }

  Widget _filterDropdown() {
    final items = _tab == 0
        ? const [
            DropdownMenuItem(value: 'ALL', child: Text("Tất cả loại điểm")),
            DropdownMenuItem(value: 'PICKUP', child: Text("Điểm nhận")),
            DropdownMenuItem(value: 'DELIVERY', child: Text("Điểm giao")),
            DropdownMenuItem(value: 'BOTH', child: Text("Nhận và giao")),
          ]
        : const [
            DropdownMenuItem(value: 'PENDING', child: Text("Chờ duyệt")),
            DropdownMenuItem(value: 'IGNORED', child: Text("Đã bỏ qua")),
            DropdownMenuItem(value: 'APPROVED', child: Text("Đã duyệt")),
          ];
    return SizedBox(
      height: 36,
      child: DropdownButtonFormField<String>(
        key: ValueKey('filter_$_tab'),
        initialValue: _tab == 0 ? _kindFilter : _sugStatus,
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
        items: items,
        onChanged: (val) {
          if (val == null) return;
          setState(() {
            _currentPage = 1;
            if (_tab == 0) {
              _kindFilter = val;
            } else {
              _sugStatus = val;
            }
          });
          if (_tab == 1) _loadSuggestions();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locs = _visibleLocations;
    final sugs = _visibleSuggestions;
    _reportCount(locs.length, _locations.length);

    final totalItems = _tab == 0 ? locs.length : sugs.length;
    final totalPages = (totalItems / _pageSize).ceil().clamp(1, 99999);
    final validPage = _currentPage.clamp(1, totalPages);
    final startIndex = totalItems == 0 ? 0 : (validPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize > totalItems) ? totalItems : startIndex + _pageSize;
    final source = _tab == 0 ? locs : sugs;
    final pageItems = totalItems == 0 ? <Map<String, dynamic>>[] : source.sublist(startIndex, endIndex);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              _tabChip(0, "Danh mục", _locations.length),
              const SizedBox(width: 8),
              _tabChip(1, "Gợi ý từ GPS", _suggestions.length),
              const SizedBox(width: 12),
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
                      hintText: _tab == 0 ? "Tìm theo tên, địa chỉ, ghi chú..." : "Tìm theo địa chỉ, tên điểm, biển số...",
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
                message: "Gom các chỗ xe hay dừng đỗ từ lịch sử Vietmap và Bình Anh thành gợi ý",
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
        if (_scanProgress.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.teal.shade50,
            child: Text(
              _scanProgress,
              style: TextStyle(fontSize: 12, color: Colors.teal.shade800, fontWeight: FontWeight.w600),
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
                      : (_tab == 0 ? _buildLocationTable(pageItems) : _buildSuggestionTable(pageItems)),
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
    if (_tab == 0) {
      msg = _locations.isEmpty
          ? "Chưa có điểm nào. Bấm \"Thêm điểm\" hoặc duyệt từ tab \"Gợi ý từ GPS\"."
          : "Không tìm thấy điểm nào phù hợp với bộ lọc";
    } else {
      msg = _suggestions.isEmpty
          ? (_sugStatus == 'PENDING'
              ? "Chưa có gợi ý chờ duyệt. Bấm \"Quét GPS\" để gom từ lịch sử dừng đỗ."
              : "Không có gợi ý nào ở trạng thái này")
          : "Không tìm thấy gợi ý nào phù hợp";
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
                Icon(Icons.place_outlined, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(msg, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataColumn _col(String label) =>
      DataColumn(label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)));

  DataCell _cell(Widget child) => DataCell(Container(alignment: Alignment.centerLeft, child: child));

  Widget _plain(String text, {double maxWidth = 260}) {
    if (text.isEmpty) return Text("—", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400));
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
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
      child: Text(text, style: TextStyle(color: color.shade800, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  MaterialColor _kindColor(String kind) =>
      kind == 'PICKUP' ? Colors.blue : (kind == 'DELIVERY' ? Colors.orange : Colors.teal);

  String _coord(Map<String, dynamic> m) {
    final lat = double.tryParse(_s(m, 'latitude'));
    final lng = double.tryParse(_s(m, 'longitude'));
    if (lat == null || lng == null) return '';
    return "${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}";
  }

  String _providerLabel(String providers) => providers
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map((p) => p == 'vietmap' ? 'Vietmap' : (p == 'binhanh' ? 'Bình Anh' : p))
      .join(' + ');

  Widget _scrollTable(DataTable table) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth), child: table),
        ),
      ),
    );
  }

  Widget _buildLocationTable(List<Map<String, dynamic>> items) {
    return _scrollTable(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        headingRowHeight: 44,
        dividerThickness: 0,
        dataRowMaxHeight: 64,
        dataRowMinHeight: 58,
        horizontalMargin: 16,
        columnSpacing: 24,
        columns: [
          _col("Tên điểm"),
          _col("Loại"),
          _col("Địa chỉ"),
          _col("Tọa độ"),
          _col("Nguồn"),
          _col("Thao tác"),
        ],
        rows: List.generate(items.length, (idx) {
          final l = items[idx];
          final kind = _s(l, 'kind').isEmpty ? 'BOTH' : _s(l, 'kind');
          final src = _s(l, 'source');
          final fromGps = src.startsWith('GPS');
          return DataRow(
            color: WidgetStateProperty.all(idx % 2 == 0 ? Colors.white : Colors.grey.shade50),
            cells: [
              _cell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.place, size: 18, color: Colors.blue),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_s(l, 'name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.blueGrey.shade900)),
                        if (_s(l, 'note').isNotEmpty)
                          Text(_s(l, 'note'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              )),
              _cell(_badge(_kindLabels[kind] ?? kind, _kindColor(kind))),
              _cell(_plain(_s(l, 'address'))),
              _cell(_plain(_coord(l), maxWidth: 170)),
              _cell(Tooltip(
                message: fromGps ? "Duyệt từ gợi ý GPS (${_providerLabel(src.substring(4))})" : "Tạo thủ công",
                child: _badge(fromGps ? "GPS" : "Thủ công", fromGps ? Colors.teal : Colors.orange),
              )),
              _cell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _rowButton(Icons.edit, "Sửa", Colors.blue.shade800, Colors.blue.shade300, () => _showForm(location: l)),
                  const SizedBox(width: 8),
                  _rowButton(Icons.delete_outline, "Xóa", Colors.red.shade700, Colors.red.shade200, () => _confirmDelete(l)),
                ],
              )),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSuggestionTable(List<Map<String, dynamic>> items) {
    return _scrollTable(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        headingRowHeight: 44,
        dividerThickness: 0,
        dataRowMaxHeight: 68,
        dataRowMinHeight: 58,
        horizontalMargin: 16,
        columnSpacing: 24,
        columns: [
          _col("Địa chỉ dừng đỗ"),
          _col("Số lần dừng"),
          _col("Tổng thời gian"),
          _col("Xe"),
          _col("Nguồn"),
          _col("Lần cuối"),
          _col("Thao tác"),
        ],
        rows: List.generate(items.length, (idx) {
          final s = items[idx];
          final station = _s(s, 'station_name');
          final address = _s(s, 'address');
          final minutes = int.tryParse(_s(s, 'total_minutes')) ?? 0;
          final duration = minutes >= 60 ? "${minutes ~/ 60} giờ ${minutes % 60} phút" : "$minutes phút";
          final lastSeen = _s(s, 'last_seen').replaceFirst('T', ' ');
          final status = _s(s, 'status');
          return DataRow(
            color: WidgetStateProperty.all(idx % 2 == 0 ? Colors.white : Colors.grey.shade50),
            cells: [
              _cell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.isNotEmpty ? station : (address.isNotEmpty ? address : "Không rõ địa chỉ"),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.blueGrey.shade900),
                    ),
                    Text(
                      station.isNotEmpty && address.isNotEmpty ? "$address • ${_coord(s)}" : _coord(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              )),
              _cell(Text(_s(s, 'visit_count'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
              _cell(Text(duration, style: const TextStyle(fontSize: 12.5))),
              _cell(Tooltip(
                message: _s(s, 'vehicles'),
                child: Text("${_s(s, 'vehicle_count')} xe", style: const TextStyle(fontSize: 12.5)),
              )),
              _cell(_badge(_providerLabel(_s(s, 'providers')), Colors.teal)),
              _cell(_plain(lastSeen.length > 16 ? lastSeen.substring(0, 16) : lastSeen, maxWidth: 130)),
              _cell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status == 'PENDING') ...[
                    _rowButton(Icons.check, "Duyệt", Colors.green.shade800, Colors.green.shade300, () => _approve(s)),
                    const SizedBox(width: 8),
                    _rowButton(Icons.block, "Bỏ qua", Colors.grey.shade700, Colors.grey.shade400, () => _ignore(s)),
                  ] else if (status == 'IGNORED')
                    _rowButton(Icons.undo, "Khôi phục", Colors.blue.shade800, Colors.blue.shade300, () => _restore(s))
                  else
                    _badge("Đã duyệt", Colors.green),
                ],
              )),
            ],
          );
        }),
      ),
    );
  }

  Widget _rowButton(IconData icon, String label, Color color, Color border, VoidCallback onPressed) {
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

  Widget _buildPagination({
    required int totalItems,
    required int startIndex,
    required int endIndex,
    required int validPage,
    required int totalPages,
  }) {
    Widget navBtn(IconData icon, String tip, bool enabled, int page) => IconButton(
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
            "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems ${_tab == 0 ? 'điểm' : 'gợi ý'}",
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
          Row(
            children: [
              const Text("Số dòng/trang: ", style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(width: 4),
              DropdownButton<int>(
                value: _pageSize,
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
                      _pageSize = val;
                      _currentPage = 1;
                    });
                  }
                },
              ),
              const SizedBox(width: 14),
              navBtn(Icons.first_page, "Trang đầu", validPage > 1, 1),
              navBtn(Icons.chevron_left, "Trang trước", validPage > 1, validPage - 1),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text("$validPage / $totalPages",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
              ),
              const SizedBox(width: 4),
              navBtn(Icons.chevron_right, "Trang sau", validPage < totalPages, validPage + 1),
              navBtn(Icons.last_page, "Trang cuối", validPage < totalPages, totalPages),
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
      style: const TextStyle(fontSize: 13, color: Colors.black87, fontFamily: 'Nunito'),
      decoration: const InputDecoration(labelText: "Loại điểm *", prefixIcon: Icon(Icons.swap_vert, size: 18)),
      items: _kindLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _textField(TextEditingController c, String label, IconData icon,
      {int maxLines = 1, TextInputType? type, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: type,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18)),
        validator: validator,
      ),
    );
  }

  Future<void> _showForm({Map<String, dynamic>? location}) async {
    final isEdit = location != null;
    final nameCtrl = TextEditingController(text: isEdit ? _s(location, 'name') : '');
    final addrCtrl = TextEditingController(text: isEdit ? _s(location, 'address') : '');
    final latCtrl = TextEditingController(text: isEdit ? _s(location, 'latitude') : '');
    final lngCtrl = TextEditingController(text: isEdit ? _s(location, 'longitude') : '');
    final radiusCtrl = TextEditingController(text: isEdit ? _s(location, 'radius_m') : '300');
    final noteCtrl = TextEditingController(text: isEdit ? _s(location, 'note') : '');
    String kind = isEdit && _kindLabels.containsKey(_s(location, 'kind')) ? _s(location, 'kind') : 'BOTH';
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
          title: Text(isEdit ? "Sửa điểm nhận / giao" : "Thêm điểm nhận / giao",
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _textField(nameCtrl, "Tên điểm *", Icons.place_outlined,
                        validator: (v) => (v ?? '').trim().isEmpty ? "Không được để trống" : null),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _kindDropdown(kind, (v) => setDialogState(() => kind = v)),
                    ),
                    _textField(addrCtrl, "Địa chỉ", Icons.location_on_outlined, maxLines: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _textField(latCtrl, "Vĩ độ", Icons.my_location,
                              type: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              validator: (v) => coordValidator(v, 90)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _textField(lngCtrl, "Kinh độ", Icons.my_location,
                              type: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              validator: (v) => coordValidator(v, 180)),
                        ),
                      ],
                    ),
                    _textField(radiusCtrl, "Bán kính nhận diện (m)", Icons.radar, type: TextInputType.number,
                        validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return null;
                      final n = int.tryParse(t);
                      return (n == null || n < 10 || n > 5000) ? "Từ 10 đến 5000" : null;
                    }),
                    _textField(noteCtrl, "Ghi chú", Icons.notes_outlined, maxLines: 2),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text("Hủy bỏ")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final lat = double.tryParse(latCtrl.text.trim());
                      final lng = double.tryParse(lngCtrl.text.trim());
                      if ((lat == null) != (lng == null)) {
                        _toast("Phải nhập đủ cả vĩ độ và kinh độ, hoặc để trống cả hai", error: true);
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
    for (final c in [nameCtrl, addrCtrl, latCtrl, lngCtrl, radiusCtrl, noteCtrl]) {
      c.dispose();
    }
  }

  Future<void> _approve(Map<String, dynamic> s) async {
    final station = _s(s, 'station_name');
    final address = _s(s, 'address');
    final nameCtrl = TextEditingController(text: station.isNotEmpty ? station : address);
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
          title: const Text("Duyệt gợi ý vào danh mục", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                      "${_s(s, 'visit_count')} lần dừng, ${_s(s, 'vehicle_count')} xe "
                      "(${_providerLabel(_s(s, 'providers'))}). Tọa độ: ${_coord(s)}",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),
                    _textField(nameCtrl, "Tên điểm *", Icons.place_outlined,
                        validator: (v) => (v ?? '').trim().isEmpty ? "Đặt tên dễ nhớ, ví dụ: Kho Xi Măng Bỉm Sơn" : null),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _kindDropdown(kind, (v) => setDialogState(() => kind = v)),
                    ),
                    _textField(addrCtrl, "Địa chỉ", Icons.location_on_outlined, maxLines: 2),
                    _textField(noteCtrl, "Ghi chú", Icons.notes_outlined, maxLines: 2),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text("Hủy bỏ")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(64, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => saving = true);
                      final res = await AdminService.approveLocationSuggestion(int.parse('${s['id']}'), {
                        'name': nameCtrl.text.trim(),
                        'address': addrCtrl.text.trim(),
                        'kind': kind,
                        'note': noteCtrl.text.trim(),
                      });
                      if (!dialogContext.mounted) return;
                      setDialogState(() => saving = false);
                      if (res['ok'] == true) {
                        Navigator.pop(dialogContext);
                        _toast("Đã thêm \"${nameCtrl.text.trim()}\" vào danh mục");
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
    final res = await AdminService.ignoreLocationSuggestion(int.parse('${s['id']}'));
    if (!mounted) return;
    if (res['ok'] == true) {
      _toast("Đã bỏ qua gợi ý");
      _loadSuggestions();
    } else {
      _toast(res['message'].toString(), error: true);
    }
  }

  Future<void> _restore(Map<String, dynamic> s) async {
    final res = await AdminService.restoreLocationSuggestion(int.parse('${s['id']}'));
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
          "Nếu điểm này được duyệt từ gợi ý GPS, gợi ý sẽ quay về hàng chờ duyệt.",
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Hủy bỏ")),
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
