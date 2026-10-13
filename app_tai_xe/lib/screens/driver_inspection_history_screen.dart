import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/app_state.dart';

class DriverInspectionHistoryScreen extends StatefulWidget {
  const DriverInspectionHistoryScreen({super.key});

  @override
  State<DriverInspectionHistoryScreen> createState() => _DriverInspectionHistoryScreenState();
}

class _DriverInspectionHistoryScreenState extends State<DriverInspectionHistoryScreen> {
  bool _isLoading = true;
  List<dynamic> _inspections = [];
  Map<String, dynamic>? _selectedRecord;
  DateTime? _filterDate;
  final TextEditingController _dateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final String? dateStr = _filterDate != null
        ? "${_filterDate!.year.toString().padLeft(4, '0')}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}"
        : null;

    final data = await AdminService.fetchInspections(
      date: dateStr,
    );

    if (mounted) {
      final state = context.read<AppState>();
      final myUserId = state.currentUserId;
      final myUsername = state.currentUsername?.trim().toLowerCase() ?? '';

      // Lọc danh sách lượt chụp của chính tài xế đang đăng nhập
      final myInspections = data.where((item) {
        if (item is! Map) return false;
        final driverId = item['driver_id'];
        final driverUsername = (item['driver_username'] ?? '').toString().trim().toLowerCase();
        if (myUserId != null && driverId != null && driverId == myUserId) {
          return true;
        }
        if (myUsername.isNotEmpty && driverUsername == myUsername) {
          return true;
        }
        return false;
      }).toList();

      setState(() {
        _inspections = myInspections;
        if (_inspections.isNotEmpty) {
          // Giữ record đang chọn nếu còn trong list, ngược lại lấy record đầu tiên
          if (_selectedRecord != null) {
            final exists = _inspections.firstWhere(
              (it) => it['id'] == _selectedRecord?['id'],
              orElse: () => null,
            );
            _selectedRecord = exists != null ? (exists as Map<String, dynamic>) : (_inspections.first as Map<String, dynamic>);
          } else {
            _selectedRecord = _inspections.first as Map<String, dynamic>;
          }
        } else {
          _selectedRecord = null;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _filterDate = picked;
        _dateCtrl.text = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
      _loadHistory();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _filterDate = null;
      _dateCtrl.clear();
    });
    _loadHistory();
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
      final fullUrl = url.startsWith('http')
          ? url
          : 'https://saomai-api.type.vn/${url.startsWith('/') ? url.substring(1) : url}';
      return Image.network(
        fullUrl,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _buildPlaceholderIcon(),
      );
    }
  }

  Widget _buildPlaceholderIcon() {
    return Container(
      color: Colors.blueGrey.shade50,
      child: Center(
        child: Icon(Icons.image, size: 36, color: Colors.blueGrey.shade300),
      ),
    );
  }

  void _showFullPhotoDialog(String title, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Container(
          width: 850,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
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

  Widget _buildStatusBadge(String? status) {
    String label = "Đang kiểm tra";
    Color bg = Colors.amber.shade50;
    Color fg = Colors.amber.shade900;
    Color border = Colors.amber.shade300;

    switch (status) {
      case 'approved':
        label = "Đã Phê Duyệt";
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        border = Colors.green.shade300;
        break;
      case 'rejected':
        label = "Yêu Cầu Chụp Lại";
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        border = Colors.red.shade300;
        break;
      case 'monitored':
        label = "Theo Dõi Kỹ Thuật";
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        border = Colors.blue.shade300;
        break;
      case 'none':
      case 'ignored':
        label = "Hợp Lệ Tự Động";
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade800;
        border = Colors.teal.shade300;
        break;
      default:
        label = "Chờ Duyệt";
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        border = Colors.amber.shade300;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg),
      ),
    );
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Icon(icon, size: 15, color: Colors.blueGrey.shade800),
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
                    mouseCursor: SystemMouseCursors.click,
                    onTap: () => _showFullPhotoDialog(title, url),
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
                        Icon(Icons.no_photography_outlined, size: 28, color: Colors.grey.shade400),
                        const SizedBox(height: 4),
                        Text(
                          "Chưa có ảnh",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordDetail(Map<String, dynamic> record) {
    final plate = record['plate_number'] ?? 'Không rõ';
    final date = record['check_date'] ?? 'Không rõ';
    final completedAt = record['completed_at'] ?? '';
    final kmOcr = record['km_ocr'];
    final kmConfirmed = record['km_confirmed'];
    final status = record['flag_status'];
    final reason = record['flag_reason'] ?? '';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          "Xe: $plate",
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(width: 10),
                        _buildStatusBadge(status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Ngày kiểm tra: $date ${completedAt.isNotEmpty ? '• Lúc: ${completedAt.toString().substring(11, 16)}' : ''}",
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.speed, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        "ODO: ${kmConfirmed ?? kmOcr ?? '--'} km",
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (reason.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Ghi chú điều hành: $reason",
                      style: TextStyle(fontSize: 12.5, color: Colors.brown.shade900),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.25,
                children: [
                  _buildPhotoThumbnail("1. Gầm trước", record['img_front_underbody'], Icons.directions_car),
                  _buildPhotoThumbnail("2. Gầm sau", record['img_rear_underbody'], Icons.directions_car_filled),
                  _buildPhotoThumbnail("3. Hông trái", record['img_left_side'], Icons.compare_arrows),
                  _buildPhotoThumbnail("4. Hông phải", record['img_right_side'], Icons.compare_arrows),
                  _buildPhotoThumbnail("5. Táp-lô (ODO)", record['img_dashboard'], Icons.speed),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final isDesktop = mediaWidth >= 1000;

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // Thanh công cụ lọc ngày và làm mới
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  height: 44,
                  child: TextField(
                    controller: _dateCtrl,
                    readOnly: true,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Lọc theo ngày kiểm tra",
                      hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44, maxHeight: 44),
                      suffixIcon: _filterDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _clearDateFilter,
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44, maxHeight: 44),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      isDense: true,
                    ),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      minimumSize: const Size(64, 44),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Làm mới", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: _loadHistory,
                  ),
                ),
                const Spacer(),
                Text(
                  "Tổng cộng: ${_inspections.length} lượt kiểm tra",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700),
                ),
              ],
            ),
          ),
          // Nội dung hiển thị
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _inspections.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off, size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              "Chưa có dữ liệu hình chụp kiểm tra xe nào.",
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Các bức ảnh chụp bàn giao ca của bạn sẽ được hiển thị lưu trữ tại đây.",
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : isDesktop
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Danh sách các lượt chụp bên trái
                                SizedBox(
                                  width: 330,
                                  child: Card(
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      side: BorderSide(color: Colors.grey.shade300),
                                    ),
                                    child: ListView.separated(
                                      itemCount: _inspections.length,
                                      separatorBuilder: (ctx, index) => Divider(height: 1, color: Colors.grey.shade200),
                                      itemBuilder: (ctx, index) {
                                        final item = _inspections[index] as Map<String, dynamic>;
                                        final isSelected = _selectedRecord?['id'] == item['id'];
                                        final plate = item['plate_number'] ?? 'Không rõ';
                                        final date = item['check_date'] ?? '';
                                        final status = item['flag_status'];

                                        return ListTile(
                                          dense: true,
                                          selected: isSelected,
                                          selectedTileColor: Colors.blue.shade50,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          onTap: () {
                                            setState(() {
                                              _selectedRecord = item;
                                            });
                                          },
                                          title: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                plate,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: isSelected ? Colors.blue.shade900 : Colors.black87,
                                                ),
                                              ),
                                              _buildStatusBadge(status),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              "Ngày: $date",
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Khung chi tiết 5 bức ảnh bên phải
                                Expanded(
                                  child: _selectedRecord != null
                                      ? _buildRecordDetail(_selectedRecord!)
                                      : const SizedBox(),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _inspections.length,
                            itemBuilder: (ctx, index) {
                              final item = _inspections[index] as Map<String, dynamic>;
                              return Container(
                                height: 480,
                                margin: const EdgeInsets.only(bottom: 14),
                                child: _buildRecordDetail(item),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
