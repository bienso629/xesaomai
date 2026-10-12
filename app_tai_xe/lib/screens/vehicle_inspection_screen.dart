import 'dart:io';
import 'package:flutter/material.dart';
import '../services/admin_service.dart';

class VehicleInspectionReviewScreen extends StatefulWidget {
  const VehicleInspectionReviewScreen({super.key});

  @override
  State<VehicleInspectionReviewScreen> createState() => _VehicleInspectionReviewScreenState();
}

class _VehicleInspectionReviewScreenState extends State<VehicleInspectionReviewScreen> {
  bool _isLoading = true;
  List<dynamic> _inspections = [];
  Map<String, dynamic>? _selectedRecord;
  String _filterPlate = '';
  String _filterStatus = 'ALL'; // ALL, pending, approved, monitored, rejected
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadInspections();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
        // Lọc theo trạng thái nếu có
        final filteredList = _getFilteredInspections();
        if (filteredList.isNotEmpty) {
          _selectedRecord = filteredList.first as Map<String, dynamic>;
          _noteCtrl.text = _selectedRecord?['flag_reason'] ?? '';
        } else {
          _selectedRecord = null;
          _noteCtrl.clear();
        }
        _isLoading = false;
      });
    }
  }

  List<dynamic> _getFilteredInspections() {
    if (_filterStatus == 'ALL') return _inspections;
    return _inspections.where((item) {
      final flagStatus = (item['flag_status'] ?? 'none').toString().toLowerCase();
      if (_filterStatus == 'pending') {
        return flagStatus == 'none' || flagStatus.isEmpty;
      }
      return flagStatus == _filterStatus;
    }).toList();
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
            backgroundColor: status == 'approved'
                ? Colors.green.shade700
                : (status == 'rejected' ? Colors.red.shade700 : Colors.amber.shade800),
            content: Text(
              status == 'approved'
                  ? "Đã phê duyệt kiểm tra xe! Xe được phép nhận chuyến."
                  : (status == 'rejected'
                      ? "Đã từ chối / Yêu cầu tài xế chụp kiểm tra lại."
                      : "Đã chuyển sang trạng thái theo dõi kỹ thuật."),
            ),
          ),
        );
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
                        Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 4),
                        Text("Chưa có ảnh", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
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

  @override
  Widget build(BuildContext context) {
    final filteredList = _getFilteredInspections();
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1100;

    return RefreshIndicator(
      onRefresh: _loadInspections,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thanh công cụ tìm kiếm và lọc trạng thái duyệt
            Row(
              children: [
                SizedBox(
                  width: 280,
                  height: 44,
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: "Tìm theo biển số xe...",
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44, maxHeight: 44),
                      suffixIcon: _filterPlate.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _filterPlate = '');
                                _loadInspections();
                              },
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44, maxHeight: 44),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onSubmitted: (val) {
                      setState(() => _filterPlate = val.trim());
                      _loadInspections();
                    },
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(64, 44),
                    ),
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: const Text("Tìm Kiếm", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() => _filterPlate = _searchCtrl.text.trim());
                      _loadInspections();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                const Text("Lọc trạng thái:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFilterChoiceChip("Tất cả", 'ALL', Colors.blueGrey),
                    const SizedBox(width: 6),
                    _buildFilterChoiceChip("Chưa duyệt", 'pending', Colors.blueGrey),
                    const SizedBox(width: 6),
                    _buildFilterChoiceChip("Đã duyệt", 'approved', Colors.green),
                    const SizedBox(width: 6),
                    _buildFilterChoiceChip("Đang theo dõi", 'monitored', Colors.amber),
                    const SizedBox(width: 6),
                    _buildFilterChoiceChip("Từ chối / Chụp lại", 'rejected', Colors.red),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueGrey.shade800,
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(64, 44),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Tải lại", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    onPressed: _loadInspections,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Khung làm việc 2 cột: Danh sách bên trái, Chi tiết 5 ảnh bên phải
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cột 1: Danh sách các lượt nộp ảnh kiểm tra xe
                        Container(
                          width: 330,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.list_alt, size: 18, color: Colors.blueGrey),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Danh sách kiểm tra (${filteredList.length})",
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: filteredList.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.fact_check_outlined, size: 42, color: Colors.grey.shade400),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Không có bản ghi kiểm tra xe nào",
                                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.all(8),
                                        itemCount: filteredList.length,
                                        separatorBuilder: (ctx, i) => const SizedBox(height: 6),
                                        itemBuilder: (ctx, idx) {
                                          final item = filteredList[idx];
                                          final isSelected = _selectedRecord?['id'] == item['id'];
                                          final flagStatus = (item['flag_status'] ?? 'none').toString().toLowerCase();

                                          Color statusColor = Colors.grey.shade700;
                                          Color statusBg = Colors.grey.shade100;
                                          String statusLabel = "Chưa duyệt";
                                          if (flagStatus == 'approved') {
                                            statusColor = Colors.green.shade800;
                                            statusBg = Colors.green.shade50;
                                            statusLabel = "Đã duyệt";
                                          } else if (flagStatus == 'rejected') {
                                            statusColor = Colors.red.shade800;
                                            statusBg = Colors.red.shade50;
                                            statusLabel = "Từ chối / Chụp lại";
                                          } else if (flagStatus == 'monitored') {
                                            statusColor = Colors.amber.shade900;
                                            statusBg = Colors.amber.shade50;
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
                                                          color: statusBg,
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                                        ),
                                                        child: Text(
                                                          statusLabel,
                                                          style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.person, size: 14, color: Colors.teal),
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
                                                  const SizedBox(height: 3),
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
                        const SizedBox(width: 14),

                        // Cột 2: Toàn cảnh 5 ảnh và thanh điều khiển phê duyệt
                        Expanded(
                          child: _selectedRecord == null
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.touch_app_outlined, size: 48, color: Colors.grey.shade400),
                                        const SizedBox(height: 12),
                                        Text(
                                          "Vui lòng chọn một lượt kiểm tra xe ở danh sách bên trái để soi chi tiết 5 ảnh.",
                                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Thẻ thông tin tóm tắt xe & ODO
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                                                        "Biển số: ${_selectedRecord!['plate_number']}",
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: Colors.blueGrey.shade300),
                                                        ),
                                                        child: Text(
                                                          "${_selectedRecord!['vehicle_type'] ?? 'Xe đầu kéo'}",
                                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    "Tài xế giao nhận ca: ${_selectedRecord!['driver_name']} • Điện thoại: ${_selectedRecord!['driver_phone'] ?? 'N/A'}",
                                                    style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  "Km Táp-lô: ${_selectedRecord!['km_confirmed'] ?? _selectedRecord!['km_ocr'] ?? 'N/A'} km",
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.indigo),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  "Thời gian gửi: ${_selectedRecord!['completed_at'] ?? _selectedRecord!['created_at'] ?? 'Hôm nay'}",
                                                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Lưới hiển thị 5 ảnh kiểm tra góc máy
                                      Expanded(
                                        child: GridView.count(
                                          crossAxisCount: isDesktop ? 3 : 2,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          childAspectRatio: 1.25,
                                          children: [
                                            _buildPhotoThumbnail("1. Gầm trước xe (Cản & Trục lái)", _selectedRecord!['img_front_underbody'], Icons.front_hand_outlined),
                                            _buildPhotoThumbnail("2. Bầu vi sai & Gầm sau xe", _selectedRecord!['img_rear_underbody'], Icons.settings_suggest_outlined),
                                            _buildPhotoThumbnail("3. Hông trái xe (Lốp & Bồn)", _selectedRecord!['img_left_side'], Icons.compare_arrows_outlined),
                                            _buildPhotoThumbnail("4. Hông phải xe (Bình dầu & Lốp)", _selectedRecord!['img_right_side'], Icons.swap_horiz_outlined),
                                            _buildPhotoThumbnail("5. Táp-lô & Đồng hồ ODO", _selectedRecord!['img_dashboard'], Icons.speed_outlined),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Khối thao tác duyệt / từ chối của Điều phối viên
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
                                              child: SizedBox(
                                                height: 44,
                                                child: TextField(
                                                  controller: _noteCtrl,
                                                  textAlignVertical: TextAlignVertical.center,
                                                  style: const TextStyle(fontSize: 13.5),
                                                  decoration: InputDecoration(
                                                    hintText: "Ghi chú kiểm tra của Điều phối (ví dụ: cản nứt, lệch km hành trình, ảnh mờ...)",
                                                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    isDense: true,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(4),
                                                      borderSide: BorderSide(color: Colors.grey.shade400),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(4),
                                                      borderSide: BorderSide(color: Colors.grey.shade400),
                                                    ),
                                                    focusedBorder: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(4),
                                                      borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            if (_isSubmitting)
                                              const SizedBox(width: 44, height: 44, child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)))
                                            else
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    height: 44,
                                                    child: ElevatedButton.icon(
                                                      style: ElevatedButton.styleFrom(
                                                        elevation: 0,
                                                        shadowColor: Colors.transparent,
                                                        backgroundColor: Colors.green.shade700,
                                                        foregroundColor: Colors.white,
                                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                                        minimumSize: const Size(64, 44),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                      ),
                                                      icon: const Icon(Icons.check_circle_outline, size: 18),
                                                      label: const Text("Duyệt Nhận Chuyến", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                      onPressed: () => _updateReviewStatus('approved'),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  SizedBox(
                                                    height: 44,
                                                    child: OutlinedButton.icon(
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: Colors.amber.shade900,
                                                        side: BorderSide(color: Colors.amber.shade700, width: 1.2),
                                                        backgroundColor: Colors.amber.shade50.withValues(alpha: 0.3),
                                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                                        minimumSize: const Size(64, 44),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                      ),
                                                      icon: const Icon(Icons.visibility_outlined, size: 18),
                                                      label: const Text("Theo Dõi", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                      onPressed: () => _updateReviewStatus('monitored'),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  SizedBox(
                                                    height: 44,
                                                    child: OutlinedButton.icon(
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: Colors.red.shade700,
                                                        side: BorderSide(color: Colors.red.shade400, width: 1.2),
                                                        backgroundColor: Colors.red.shade50.withValues(alpha: 0.3),
                                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                                        minimumSize: const Size(64, 44),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                      ),
                                                      icon: const Icon(Icons.cancel_outlined, size: 18),
                                                      label: const Text("Yêu Cầu Chụp Lại", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                                      onPressed: () => _updateReviewStatus('rejected'),
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
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChoiceChip(String label, String value, MaterialColor color) {
    final isSelected = _filterStatus == value;
    final Color activeColor = color.shade700;
    final Color bg = isSelected ? activeColor.withValues(alpha: 0.12) : Colors.white;
    final Color border = isSelected ? activeColor : Colors.grey.shade300;
    final Color textColor = isSelected ? (color == Colors.blueGrey ? Colors.blueGrey.shade900 : activeColor) : Colors.grey.shade700;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _filterStatus = value;
            final list = _getFilteredInspections();
            if (list.isNotEmpty) {
              _selectedRecord = list.first as Map<String, dynamic>;
              _noteCtrl.text = _selectedRecord?['flag_reason'] ?? '';
            } else {
              _selectedRecord = null;
              _noteCtrl.clear();
            }
          });
        },
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: border, width: isSelected ? 1.5 : 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : color.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: textColor,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 5),
                Icon(Icons.check, size: 14, color: activeColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
