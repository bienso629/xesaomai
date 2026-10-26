import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_service.dart';

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
  String _query = '';
  bool _loading = true;

  // Bảng dữ liệu: phân trang + sắp xếp
  int _currentPage = 1;
  int _pageSize = 10;
  String _sourceFilter = 'ALL'; // ALL | ZALO | MANUAL

  // Đồng bộ Zalo OA
  bool _zaloBusy = false;
  String _zaloProgress = '';
  Timer? _zaloTimer;
  int _zaloPolls = 0;
  bool _zaloWaitingAuth = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zaloTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------- ĐỒNG BỘ ZALO OA ----------------

  Future<void> _onZaloSync() async {
    if (_zaloBusy) return;
    setState(() {
      _zaloBusy = true;
      _zaloProgress = 'Đang kiểm tra kết nối Zalo OA...';
    });
    final st = await AdminService.fetchZaloOaStatus();
    if (!mounted) return;
    if (st['ok'] != true) {
      _zaloStop(st['message'].toString(), error: true);
      return;
    }
    final data = Map<String, dynamic>.from(st['data'] as Map);
    if (data['configured'] != true) {
      _zaloStop(
        'Máy chủ chưa cấu hình ZALO_APP_ID / ZALO_APP_SECRET',
        error: true,
      );
      return;
    }
    final sync = data['sync'] is Map ? Map<String, dynamic>.from(data['sync']) : {};
    if (sync['running'] == true) {
      _zaloPoll(); // Có người khác đang đồng bộ, chỉ theo dõi tiến độ
      return;
    }
    if (data['connected'] == true) {
      await _zaloStartSync();
    } else {
      await _zaloAuthorize();
    }
  }

  Future<void> _zaloAuthorize() async {
    final agree = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text("Cấp quyền Zalo OA", style: TextStyle(fontSize: 17)),
        content: const Text(
          "Ứng dụng sẽ mở trang Zalo để chủ (hoặc quản trị viên) Zalo OA đồng ý "
          "cho phép đọc danh sách người quan tâm OA.\n\n"
          "Sau khi bấm \"Cho phép\" trên Zalo, quay lại đây, ứng dụng sẽ tự đồng bộ "
          "danh sách vào Khách hàng.",
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
      _zaloStop('');
      return;
    }
    final res = await AdminService.requestZaloOaAuthorizeUrl();
    if (!mounted) return;
    final url = res['ok'] == true && res['data'] is Map
        ? (res['data']['authorize_url'] ?? '').toString()
        : '';
    if (url.isEmpty) {
      _zaloStop(
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
      _zaloStop('Không mở được trình duyệt để cấp quyền Zalo OA', error: true);
      return;
    }
    // Chờ chủ OA cấp quyền xong (tối đa ~5 phút), rồi tự đồng bộ
    setState(() {
      _zaloWaitingAuth = true;
      _zaloProgress = 'Đang chờ cấp quyền trên Zalo...';
    });
    _zaloPoll();
  }

  Future<void> _zaloStartSync() async {
    setState(() => _zaloProgress = 'Đang bắt đầu đồng bộ...');
    final res = await AdminService.startZaloOaSync();
    if (!mounted) return;
    if (res['ok'] != true) {
      if (res['status'] == 409) {
        setState(() => _zaloBusy = false);
        await _zaloAuthorize(); // Token đã mất hiệu lực, xin cấp quyền lại
        return;
      }
      _zaloStop(res['message'].toString(), error: true);
      return;
    }
    _zaloWaitingAuth = false;
    _zaloPoll();
  }

  void _zaloPoll() {
    _zaloTimer?.cancel();
    _zaloPolls = 0;
    setState(() => _zaloBusy = true);
    _zaloTimer = Timer.periodic(const Duration(seconds: 2), (_) => _zaloTick());
  }

  Future<void> _zaloTick() async {
    _zaloPolls++;
    final st = await AdminService.fetchZaloOaStatus();
    if (!mounted || _zaloTimer == null) return;
    if (st['ok'] != true || st['data'] is! Map) {
      if (_zaloPolls > 5) _zaloStop(st['message'].toString(), error: true);
      return;
    }
    final data = Map<String, dynamic>.from(st['data'] as Map);
    final sync = data['sync'] is Map ? Map<String, dynamic>.from(data['sync']) : <String, dynamic>{};

    if (_zaloWaitingAuth) {
      if (data['connected'] == true) {
        _zaloTimer?.cancel();
        _zaloTimer = null;
        _zaloWaitingAuth = false;
        await _zaloStartSync();
      } else if (_zaloPolls >= 150) {
        _zaloStop('Hết thời gian chờ cấp quyền Zalo OA. Bấm lại nút để thử lại.', error: true);
      }
      return;
    }

    int n(String k) => int.tryParse('${sync[k] ?? 0}') ?? 0;
    if (sync['running'] == true) {
      setState(() => _zaloProgress = n('total') > 0
          ? 'Đang đồng bộ Zalo OA: ${n('processed')}/${n('total')}'
          : 'Đang lấy danh sách người dùng Zalo OA...');
      return;
    }
    _zaloTimer?.cancel();
    _zaloTimer = null;
    if (sync['error'] != null) {
      _zaloStop(sync['error'].toString(), error: true);
    } else {
      _zaloStop(
        'Đồng bộ xong ${n('total')} liên hệ: thêm mới ${n('created')}, '
        'cập nhật ${n('updated')}, gắn theo SĐT ${n('linked')}'
        '${n('failed') > 0 ? ', lỗi ${n('failed')}' : ''}',
      );
    }
    _load();
  }

  void _zaloStop(String message, {bool error = false}) {
    _zaloTimer?.cancel();
    _zaloTimer = null;
    if (!mounted) return;
    setState(() {
      _zaloBusy = false;
      _zaloWaitingAuth = false;
      _zaloProgress = '';
    });
    if (message.isNotEmpty) _toast(message, error: error);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AdminService.fetchCustomers();
    if (!mounted) return;
    setState(() {
      _customers = rows
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
      return [
        'code',
        'name',
        'tax_code',
        'contact_person',
        'phone',
        'email',
        'address',
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

  bool _isZalo(Map<String, dynamic> c) => _s(c, 'zalo_user_id').isNotEmpty;

  /// Danh sách sau khi lọc nguồn + tìm kiếm, sắp theo tên khách hàng.
  List<Map<String, dynamic>> get _visible {
    final list = _filtered.where((c) {
      if (_sourceFilter == 'ZALO') return _isZalo(c);
      if (_sourceFilter == 'MANUAL') return !_isZalo(c);
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
    final startIndex = totalItems == 0 ? 0 : (validPage - 1) * _pageSize;
    final endIndex = (startIndex + _pageSize > totalItems) ? totalItems : startIndex + _pageSize;
    final pageItems = totalItems == 0 ? <Map<String, dynamic>>[] : list.sublist(startIndex, endIndex);

    return Column(
      children: [
        // Thanh công cụ 1 hàng: Tìm kiếm + Lọc nguồn + Thêm + Đồng bộ Zalo OA
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
                      DropdownMenuItem(value: 'ZALO', child: Text("Zalo OA")),
                      DropdownMenuItem(value: 'MANUAL', child: Text("Thủ công")),
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
              _toolbarButton(
                icon: Icons.person_add_alt_1,
                label: "Thêm khách hàng",
                color: Colors.blue.shade800,
                filled: true,
                onPressed: () => _showForm(),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: "Xin quyền Zalo OA và đồng bộ danh sách người quan tâm vào Khách hàng",
                child: _toolbarButton(
                  icon: Icons.sync,
                  label: _zaloBusy ? "Đang đồng bộ..." : "Đồng bộ Zalo OA",
                  color: const Color(0xFF0068FF),
                  busy: _zaloBusy,
                  onPressed: _zaloBusy ? null : _onZaloSync,
                ),
              ),
            ],
          ),
        ),
        if (_zaloProgress.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: const Color(0xFFE6F0FF),
            child: Text(
              _zaloProgress,
              style: const TextStyle(fontSize: 12, color: Color(0xFF0068FF), fontWeight: FontWeight.w600),
            ),
          ),
        const Divider(height: 1),
        // Bảng danh sách khách hàng
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: pageItems.isEmpty ? _buildEmpty() : _buildTable(pageItems),
                ),
        ),
        // THANH ĐIỀU HƯỚNG PHÂN TRANG
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

  Widget _buildTable(List<Map<String, dynamic>> pageItems) {
    DataColumn col(String label) => DataColumn(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );

    DataCell makeCell(Widget child) =>
        DataCell(Container(alignment: Alignment.centerLeft, child: child));

    Widget plainText(String text, {double maxWidth = 260}) {
      if (text.isEmpty) {
        return Text("—", style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400));
      }
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, color: Colors.black87),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                headingRowHeight: 44,
                dividerThickness: 0,
                dataRowMaxHeight: 64,
                dataRowMinHeight: 58,
                horizontalMargin: 16,
                columnSpacing: 24,
                columns: [
                  col("Tên khách hàng"),
                  col("Mã khách hàng"),
                  col("Nguồn"),
                  col("Người liên hệ"),
                  col("Mã số thuế"),
                  col("Địa chỉ"),
                  col("Thao tác"),
                ],
                rows: List.generate(pageItems.length, (idx) {
                  final c = pageItems[idx];
                  final rowColor = idx % 2 == 0 ? Colors.white : Colors.grey.shade50;
                  final isZalo = _isZalo(c);
                  final zaloName = _s(c, 'zalo_display_name');
                  final contactName = _s(c, 'contact_person');
                  final phone = _s(c, 'phone');
                  final email = _s(c, 'email');
                  final subLine = [phone, email].where((e) => e.isNotEmpty).join(' • ');

                  return DataRow(
                    color: WidgetStateProperty.all(rowColor),
                    cells: [
                      // Cột 1: Tên khách hàng (+ nhãn Zalo OA)
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
                              child: const Icon(Icons.storefront, size: 18, color: Colors.blue),
                            ),
                            const SizedBox(width: 10),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
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
                      makeCell(Text(_s(c, 'code'), style: const TextStyle(fontSize: 12.5))),
                      // Cột 3: Nguồn (nhãn giống "Xe nội bộ")
                      makeCell(
                        Tooltip(
                          message: isZalo
                              ? "Zalo${zaloName.isEmpty ? '' : ': $zaloName'} • ID ${_s(c, 'zalo_user_id')}"
                              : "Tạo thủ công trên phần mềm",
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isZalo ? Colors.blue.shade50 : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isZalo ? Colors.blue.shade200 : Colors.orange.shade200,
                              ),
                            ),
                            child: Text(
                              isZalo ? "Zalo OA" : "Thủ công",
                              style: TextStyle(
                                color: isZalo ? Colors.blue.shade800 : Colors.orange.shade900,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Cột 4: Người liên hệ (giống cột Tài xế chỉ định)
                      makeCell(
                        (contactName.isEmpty && subLine.isEmpty)
                            ? Text(
                                "Chưa có liên hệ",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade500,
                                ),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person, size: 15, color: Colors.teal),
                                      const SizedBox(width: 4),
                                      Text(
                                        contactName.isNotEmpty ? contactName : _s(c, 'name'),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (subLine.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subLine,
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      // Cột 5: Mã số thuế
                      makeCell(plainText(_s(c, 'tax_code'), maxWidth: 150)),
                      // Cột 6: Địa chỉ
                      makeCell(plainText(_s(c, 'address'))),
                      // Cột 7: Thao tác
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
                }),
              ),
            ),
          ),
        );
      },
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

  Widget _buildPagination({
    required int totalItems,
    required int startIndex,
    required int endIndex,
    required int validPage,
    required int totalPages,
  }) {
    Widget navBtn(IconData icon, String tip, bool enabled, int page) {
      return IconButton(
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        tooltip: tip,
        onPressed: enabled ? () => setState(() => _currentPage = page) : null,
      );
    }

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
            "Hiển thị ${startIndex + 1} - $endIndex trên tổng số $totalItems khách hàng",
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
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "$validPage / $totalPages",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                ),
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

  Future<void> _showForm({Map<String, dynamic>? customer}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CustomerFormDialog(
        customer: customer,
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
  final void Function(String msg, {bool error}) onToast;

  const _CustomerFormDialog({
    this.customer,
    required this.onToast,
  });

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  static const _fields = <(String, String, IconData, TextInputType)>[
    ('code', 'Mã khách hàng *', Icons.tag, TextInputType.text),
    ('name', 'Tên khách hàng *', Icons.business, TextInputType.text),
    ('tax_code', 'Mã số thuế', Icons.receipt_long_outlined, TextInputType.text),
    ('contact_person', 'Người liên hệ', Icons.person_outline, TextInputType.name),
    ('phone', 'Số điện thoại', Icons.phone_outlined, TextInputType.phone),
    ('email', 'Email', Icons.email_outlined, TextInputType.emailAddress),
    ('address', 'Địa chỉ', Icons.location_on_outlined, TextInputType.streetAddress),
    ('note', 'Ghi chú', Icons.notes_outlined, TextInputType.multiline),
  ];

  late final Map<String, TextEditingController> _ctrls;
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
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final res = await AdminService.saveCustomer(
      id: _isEdit ? int.tryParse('${widget.customer!['id']}') : null,
      data: {
        for (final e in _ctrls.entries) e.key: e.value.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      title: Text(
        _isEdit ? "Sửa khách hàng" : "Thêm khách hàng",
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 460,
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
