import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_service.dart';

/// Màn hình Quản lý Khách hàng.
/// Chỉ Điều phối viên, Quản lý / Giám đốc và Admin được vào (kiểm tra ở
/// main_navigation_screen.dart, dispatch_supervisor_screen.dart và phía server).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  String _query = '';
  bool _loading = true;

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

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Column(
      children: [
        // Thanh công cụ: tìm kiếm + thêm mới + tải lại
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 12.5),
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        maxHeight: 36,
                      ),
                      hintText: "Tìm theo tên, mã, MST, SĐT, địa chỉ...",
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
                              icon: const Icon(Icons.close, size: 15),
                              onPressed: () => setState(() {
                                _searchCtrl.clear();
                                _query = '';
                              }),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
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
                  icon: const Icon(Icons.person_add_alt_1, size: 17),
                  label: const Text(
                    "Thêm",
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _showForm(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: Tooltip(
                  message: "Xin quyền Zalo OA và đồng bộ toàn bộ danh sách liên hệ vào Khách hàng",
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0068FF),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF0068FF).withValues(alpha: 0.6),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 36),
                      fixedSize: const Size.fromHeight(36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    icon: _zaloBusy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.sync, size: 17),
                    label: const Text(
                      "Đồng bộ Zalo OA",
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _zaloBusy ? null : _onZaloSync,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Colors.grey.shade100,
          child: Text(
            [
              _query.isEmpty
                  ? "${_customers.length} khách hàng"
                  : "${list.length}/${_customers.length} khách hàng",
              if (_zaloProgress.isNotEmpty) _zaloProgress,
            ].join("  •  "),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _buildCard(list[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _customers.isEmpty
                ? "Chưa có khách hàng nào. Bấm \"Thêm\" để tạo mới."
                : "Không tìm thấy khách hàng phù hợp",
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    Widget line(IconData icon, String text) {
      if (text.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800),
              ),
            ),
          ],
        ),
      );
    }

    final contact = [
      _s(c, 'contact_person'),
      _s(c, 'phone'),
    ].where((e) => e.isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _s(c, 'code'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _s(c, 'name'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                line(Icons.person_outline, contact),
                line(Icons.chat_bubble_outline,
                    _s(c, 'zalo_user_id').isEmpty
                        ? ''
                        : "Zalo: ${_s(c, 'zalo_display_name').isEmpty ? '' : '${_s(c, 'zalo_display_name')} • '}ID ${_s(c, 'zalo_user_id')}"),
                line(Icons.receipt_long_outlined,
                    _s(c, 'tax_code').isEmpty ? '' : "MST: ${_s(c, 'tax_code')}"),
                line(Icons.email_outlined, _s(c, 'email')),
                line(Icons.location_on_outlined, _s(c, 'address')),
                line(Icons.notes_outlined, _s(c, 'note')),
              ],
            ),
          ),
          IconButton(
            tooltip: "Sửa khách hàng",
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.edit_outlined, size: 19, color: Colors.blue.shade700),
            onPressed: () => _showForm(customer: c),
          ),
          IconButton(
            tooltip: "Xóa khách hàng",
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 19, color: Colors.red.shade600),
            onPressed: () => _confirmDelete(c),
          ),
        ],
      ),
    );
  }

  Future<void> _showForm({Map<String, dynamic>? customer}) async {
    final isEdit = customer != null;
    const fields = <(String, String, IconData, TextInputType)>[
      ('code', 'Mã khách hàng *', Icons.tag, TextInputType.text),
      ('name', 'Tên khách hàng *', Icons.business, TextInputType.text),
      ('tax_code', 'Mã số thuế', Icons.receipt_long_outlined, TextInputType.text),
      ('contact_person', 'Người liên hệ', Icons.person_outline, TextInputType.name),
      ('phone', 'Số điện thoại', Icons.phone_outlined, TextInputType.phone),
      ('email', 'Email', Icons.email_outlined, TextInputType.emailAddress),
      ('address', 'Địa chỉ', Icons.location_on_outlined, TextInputType.streetAddress),
      ('note', 'Ghi chú', Icons.notes_outlined, TextInputType.multiline),
    ];
    final ctrls = {
      for (final f in fields)
        f.$1: TextEditingController(text: isEdit ? _s(customer, f.$1) : ''),
    };
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: Text(
            isEdit ? "Sửa khách hàng" : "Thêm khách hàng",
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
                    for (final f in fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextFormField(
                          controller: ctrls[f.$1],
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
                      setDialogState(() => saving = true);
                      final res = await AdminService.saveCustomer(
                        id: isEdit ? int.tryParse('${customer['id']}') : null,
                        data: {
                          for (final e in ctrls.entries) e.key: e.value.text.trim(),
                        },
                      );
                      if (!dialogContext.mounted) return;
                      setDialogState(() => saving = false);
                      if (res['success'] == true) {
                        Navigator.pop(dialogContext);
                        _toast(isEdit ? "Đã cập nhật khách hàng" : "Đã thêm khách hàng");
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
    for (final c in ctrls.values) {
      c.dispose();
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
