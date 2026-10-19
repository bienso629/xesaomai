import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_service.dart';

class VehicleInspectionReviewScreen extends StatefulWidget {
  const VehicleInspectionReviewScreen({super.key});

  @override
  State<VehicleInspectionReviewScreen> createState() =>
      _VehicleInspectionReviewScreenState();
}

class _VehicleInspectionReviewScreenState
    extends State<VehicleInspectionReviewScreen> {
  bool _isLoading = true;
  List<dynamic> _inspections = [];
  Map<String, dynamic>? _selectedRecord;
  String _filterPlate = '';
  DateTime? _filterDate =
      DateTime.now(); // Mặc định chỉ hiển thị danh sách của ngày hiện tại
  String _filterStatus = 'ALL'; // ALL, pending, approved, monitored, rejected
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _isAiChecking = false; // Dang goi Proxy AI kiem tra chat luong xe
  // Lịch sử các lượt chụp 5 ảnh của biển số đang xem (phục vụ slide xem ngày trước / ngày sau)
  List<dynamic> _plateHistory = [];
  int _historyIndex = 0;

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
    final String? dateStr = _filterDate != null
        ? "${_filterDate!.year.toString().padLeft(4, '0')}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}"
        : null;

    final data = await AdminService.fetchInspections(
      plateNumber: _filterPlate.isNotEmpty ? _filterPlate : null,
      date: dateStr,
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
    // Tải lịch sử các lượt chụp của biển số đang chọn để phục vụ slide xem ngày trước / ngày sau
    final String plateKey = (_selectedRecord?['plate_number'] ?? '').toString();
    if (plateKey.isNotEmpty) {
      _loadPlateHistory(
        plateKey,
        focusInspectionId: _focusIdOf(_selectedRecord),
      );
    } else if (mounted) {
      setState(() {
        _plateHistory = [];
        _historyIndex = 0;
      });
    }
  }

  Future<void> _pickFilterDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: "CHỌN NGÀY KIỂM TRA XE",
      cancelText: "HỦY",
      confirmText: "CHỌN",
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
      _loadInspections();
    }
  }

  List<dynamic> _getFilteredInspections() {
    if (_filterStatus == 'ALL') return _inspections;
    return _inspections.where((item) {
      final flagStatus = (item['flag_status'] ?? 'none')
          .toString()
          .toLowerCase();
      if (_filterStatus == 'pending') {
        return flagStatus == 'none' || flagStatus.isEmpty;
      }
      return flagStatus == _filterStatus;
    }).toList();
  }

  /// Lấy id dạng int từ bản ghi (chống dữ liệu id trả về dạng chuỗi)
  int? _focusIdOf(dynamic record) {
    if (record == null) return null;
    final id = record['id'];
    if (id is int) return id;
    return int.tryParse('$id');
  }

  /// Tải toàn bộ lịch sử chụp 5 ảnh của một biển số (mọi ngày), sắp xếp theo ngày tăng dần.
  /// Cùng một ngày có nhiều lượt chụp thì lượt mới nhất (id lớn) đứng sau để slide tới được lượt mới.
  Future<void> _loadPlateHistory(String plate, {int? focusInspectionId}) async {
    final data = await AdminService.fetchInspections(plateNumber: plate);
    final list = [...data];
    list.sort((a, b) {
      final dateA = (a['check_date'] ?? '').toString();
      final dateB = (b['check_date'] ?? '').toString();
      final byDate = dateA.compareTo(dateB);
      if (byDate != 0) return byDate;
      final idA = (a['id'] as num?) ?? 0;
      final idB = (b['id'] as num?) ?? 0;
      return idA.compareTo(idB);
    });

    if (mounted) {
      setState(() {
        _plateHistory = list;
        // Mặc định trỏ tới bản ghi đang chọn trong danh sách; không thấy thì theo ngày, cuối cùng là lượt mới nhất
        int idx = -1;
        if (focusInspectionId != null) {
          idx = list.indexWhere((e) => e['id'] == focusInspectionId);
        }
        if (idx < 0 && _selectedRecord != null) {
          final selectedDate = (_selectedRecord!['check_date'] ?? '')
              .toString();
          idx = list.indexWhere(
            (e) => (e['check_date'] ?? '').toString() == selectedDate,
          );
        }
        _historyIndex = idx >= 0 ? idx : (list.isEmpty ? 0 : list.length - 1);
        if (list.isNotEmpty) {
          _selectedRecord = list[_historyIndex];
          _noteCtrl.text = _selectedRecord?['flag_reason'] ?? '';
        }
      });
    }
  }

  /// Trượt tới lượt chụp liền trước (delta = -1) hoặc liền sau (delta = 1) của biển số
  void _slideHistory(int delta) {
    if (_plateHistory.isEmpty) return;
    final next = (_historyIndex + delta).clamp(0, _plateHistory.length - 1);
    if (next == _historyIndex) return;
    setState(() {
      _historyIndex = next;
      _selectedRecord = _plateHistory[next];
      _noteCtrl.text = _selectedRecord?['flag_reason'] ?? '';
    });
  }

  /// Định dạng ngày dd/MM/yyyy từ chuỗi YYYY-MM-DD
  String _formatDateLabel(String dateRaw) {
    try {
      final d = DateTime.parse(dateRaw);
      return "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}";
    } catch (_) {
      return dateRaw;
    }
  }

  /// Thanh slide xem ảnh chụp ngày trước / ngày sau của một biển số xe nhất định
  Widget _buildDayNavBar() {
    if (_plateHistory.isEmpty) return const SizedBox.shrink();
    final viewed = _plateHistory[_historyIndex];
    final dateRaw = (viewed['check_date'] ?? '').toString();

    final bool canPrev = _historyIndex > 0;
    final bool canNext = _historyIndex < _plateHistory.length - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(
            Icons.photo_library_outlined,
            size: 18,
            color: Colors.blue,
          ),
          const Text(
            "Slide soi ảnh theo ngày:",
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          // Nút lùi về ảnh chụp ngày trước
          SizedBox(
            height: 36,
            width: 36,
            child: IconButton(
              tooltip: "Ảnh ngày trước",
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_left, size: 22),
              color: canPrev ? Colors.blue.shade800 : Colors.grey.shade400,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(
                    color: canPrev
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
                  ),
                ),
              ),
              onPressed: canPrev ? () => _slideHistory(-1) : null,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Ngày: ${_formatDateLabel(dateRaw)}",
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ],
          ),
          // Nút chuyển tới ảnh chụp ngày sau
          SizedBox(
            height: 36,
            width: 36,
            child: IconButton(
              tooltip: "Ảnh ngày sau",
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.chevron_right, size: 22),
              color: canNext ? Colors.blue.shade800 : Colors.grey.shade400,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(
                    color: canNext
                        ? Colors.blue.shade300
                        : Colors.grey.shade300,
                  ),
                ),
              ),
              onPressed: canNext ? () => _slideHistory(1) : null,
            ),
          ),
        ],
      ),
    );
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
                : (status == 'rejected'
                      ? Colors.red.shade700
                      : Colors.amber.shade800),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            color: Colors.grey.shade200,
            child: Row(
              children: [
                Icon(icon, size: 15, color: Colors.blueGrey.shade800),
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
                          size: 36,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Chưa có ảnh",
                          style: TextStyle(
                            fontSize: 12,
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
        url.startsWith('http')
            ? url
            : 'https://saomai-api.type.vn/${url.startsWith('/') ? url.substring(1) : url}',
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
        constraints: const BoxConstraints(maxWidth: 850),
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
            LayoutBuilder(
              builder: (ctx, constraints) {
                final bool isNarrow = constraints.maxWidth < 950;

                final leftFilters = Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      height: 36,
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 12.5),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: "Tìm theo biển số xe...",
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade500,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          suffixIcon: _filterPlate.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    minHeight: 36,
                                    maxHeight: 36,
                                  ),
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _filterPlate = '');
                                    _loadInspections();
                                  },
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 36,
                            maxHeight: 36,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onSubmitted: (val) {
                          setState(() => _filterPlate = val.trim());
                          _loadInspections();
                        },
                      ),
                    ),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade800,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(64, 36),
                          fixedSize: const Size.fromHeight(36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.filter_list, size: 16),
                        label: const Text(
                          "Tìm Kiếm",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          setState(
                            () => _filterPlate = _searchCtrl.text.trim(),
                          );
                          _loadInspections();
                        },
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "Lọc:",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildFilterChoiceChip(
                              "Tất cả",
                              'ALL',
                              Colors.blueGrey,
                            ),
                            _buildFilterChoiceChip(
                              "Chưa duyệt",
                              'pending',
                              Colors.blueGrey,
                            ),
                            _buildFilterChoiceChip(
                              "Đã duyệt",
                              'approved',
                              Colors.green,
                            ),
                            _buildFilterChoiceChip(
                              "Theo dõi",
                              'monitored',
                              Colors.amber,
                            ),
                            _buildFilterChoiceChip(
                              "Chụp lại",
                              'rejected',
                              Colors.red,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                );

                final rightButtons = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Lọc theo ngày
                    SizedBox(
                      height: 36,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _filterDate != null
                              ? Colors.blue.shade800
                              : Colors.blueGrey.shade800,
                          backgroundColor: _filterDate != null
                              ? Colors.blue.shade50
                              : Colors.white,
                          side: BorderSide(
                            color: _filterDate != null
                                ? Colors.blue
                                : Colors.grey.shade400,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(64, 36),
                          fixedSize: const Size.fromHeight(36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: _filterDate != null
                              ? Colors.blue.shade800
                              : Colors.blueGrey,
                        ),
                        label: Text(
                          _filterDate != null
                              ? "Ngày: ${_filterDate!.day.toString().padLeft(2, '0')}/${_filterDate!.month.toString().padLeft(2, '0')}/${_filterDate!.year}"
                              : "Tất cả ngày",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _filterDate != null
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        onPressed: _pickFilterDate,
                      ),
                    ),
                    if (_filterDate != null) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 36,
                        width: 36,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: "Xóa lọc ngày",
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                              side: BorderSide(color: Colors.grey.shade400),
                            ),
                          ),
                          onPressed: () {
                            setState(() => _filterDate = null);
                            _loadInspections();
                          },
                        ),
                      ),
                    ],
                  ],
                );

                if (isNarrow) {
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [leftFilters, rightButtons],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: leftFilters),
                    const SizedBox(width: 12),
                    rightButtons,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    topRight: Radius.circular(4),
                                  ),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.list_alt,
                                      size: 18,
                                      color: Colors.blueGrey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _filterDate != null
                                            ? "Danh sách hôm nay (${filteredList.length})"
                                            : "Danh sách kiểm tra (${filteredList.length})",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(
                                      height: 32,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              Colors.blueGrey.shade800,
                                          backgroundColor: Colors.white,
                                          side: BorderSide(
                                            color: Colors.grey.shade300,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(
                                          Icons.refresh,
                                          size: 15,
                                        ),
                                        label: const Text(
                                          "Tải lại",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        onPressed: _loadInspections,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: filteredList.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.fact_check_outlined,
                                              size: 42,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              "Không có bản ghi kiểm tra xe nào",
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.all(8),
                                        itemCount: filteredList.length,
                                        separatorBuilder: (ctx, i) =>
                                            const SizedBox(height: 6),
                                        itemBuilder: (ctx, idx) {
                                          final item = filteredList[idx];
                                          final isSelected =
                                              _selectedRecord?['id'] ==
                                              item['id'];
                                          final flagStatus =
                                              (item['flag_status'] ?? 'none')
                                                  .toString()
                                                  .toLowerCase();

                                          Color statusColor =
                                              Colors.grey.shade700;
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
                                          } else if (flagStatus ==
                                              'monitored') {
                                            statusColor = Colors.amber.shade900;
                                            statusBg = Colors.amber.shade50;
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
                                              });
                                              final String plateKey =
                                                  (item['plate_number'] ?? '')
                                                      .toString();
                                              if (plateKey.isNotEmpty) {
                                                _loadPlateHistory(
                                                  plateKey,
                                                  focusInspectionId: _focusIdOf(
                                                    item,
                                                  ),
                                                );
                                              }
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
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            plate,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      13.5,
                                                                ),
                                                          ),
                                                          if (isSelected) ...[
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        6,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .white,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      3,
                                                                    ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .blueGrey
                                                                      .shade300,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                "${item['vehicle_type'] ?? 'Xe đầu kéo'}",
                                                                style: const TextStyle(
                                                                  fontSize:
                                                                      10.5,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Colors
                                                                      .blueGrey,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: statusBg,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                3,
                                                              ),
                                                          border: Border.all(
                                                            color: statusColor
                                                                .withValues(
                                                                  alpha: 0.3,
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
                                                  const SizedBox(height: 5),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.person,
                                                        size: 14,
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
                                                  const SizedBox(height: 3),
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

                                                  if (isSelected) ...[
                                                    const SizedBox(height: 8),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            "Điện thoại: ${item['driver_phone'] ?? 'N/A'}",
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .black87,
                                                                ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Km Táp-lô: ${item['km_confirmed'] ?? item['km_ocr'] ?? 'N/A'} km",
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                        color: Colors.indigo,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      "Thời gian gửi: ${item['completed_at'] ?? item['created_at'] ?? 'Hôm nay'}",
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
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
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.touch_app_outlined,
                                          size: 48,
                                          color: Colors.grey.shade400,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          "Vui lòng chọn một lượt kiểm tra xe ở danh sách bên trái để soi chi tiết 5 ảnh.",
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
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
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Thanh slide xem ảnh chụp ngày trước / ngày sau của biển số đang chọn
                                      _buildDayNavBar(),
                                      const SizedBox(height: 10),

                                      // Lưới hiển thị 5 ảnh kiểm tra góc máy
                                      Expanded(
                                        child: GridView.count(
                                          crossAxisCount: isDesktop ? 3 : 2,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          childAspectRatio: 1.25,
                                          children: [
                                            _buildPhotoThumbnail(
                                              "1. Gầm trước xe (Cản & Trục lái)",
                                              _selectedRecord!['img_front_underbody'],
                                              Icons.front_hand_outlined,
                                            ),
                                            _buildPhotoThumbnail(
                                              "2. Bầu vi sai & Gầm sau xe",
                                              _selectedRecord!['img_rear_underbody'],
                                              Icons.settings_suggest_outlined,
                                            ),
                                            _buildPhotoThumbnail(
                                              "3. Hông trái xe (Lốp & Bồn)",
                                              _selectedRecord!['img_left_side'],
                                              Icons.compare_arrows_outlined,
                                            ),
                                            _buildPhotoThumbnail(
                                              "4. Hông phải xe (Bình dầu & Lốp)",
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

                                      // Khối thao tác duyệt / từ chối của Điều phối viên
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        child: LayoutBuilder(
                                          builder: (ctx, constraints) {
                                            final isNarrow =
                                                constraints.maxWidth < 620;
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                SizedBox(
                                                  height: 44,
                                                  child: TextField(
                                                    controller: _noteCtrl,
                                                    textAlignVertical:
                                                        TextAlignVertical
                                                            .center,
                                                    style: const TextStyle(
                                                      fontSize: 13.5,
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText:
                                                          "Ghi chú kiểm tra của Điều phối (ví dụ: cản nứt, lệch km hành trình, ảnh mờ...)",
                                                      hintStyle: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors
                                                            .grey
                                                            .shade500,
                                                      ),
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      isDense: true,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 16,
                                                          ),
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        borderSide: BorderSide(
                                                          color: Colors
                                                              .grey
                                                              .shade400,
                                                        ),
                                                      ),
                                                      enabledBorder:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                            borderSide:
                                                                BorderSide(
                                                                  color: Colors
                                                                      .grey
                                                                      .shade400,
                                                                ),
                                                          ),
                                                      focusedBorder:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                            borderSide:
                                                                const BorderSide(
                                                                  color: Colors
                                                                      .blue,
                                                                  width: 1.5,
                                                                ),
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                if (_isSubmitting)
                                                  const Center(
                                                    child: SizedBox(
                                                      width: 32,
                                                      height: 32,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2.5,
                                                          ),
                                                    ),
                                                  )
                                                else
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    alignment: isNarrow
                                                        ? WrapAlignment.start
                                                        : WrapAlignment.end,
                                                    children: [
                                                      SizedBox(
                                                        height: 44,
                                                        child: OutlinedButton.icon(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor: Colors.purple.shade700,
                                                            side: BorderSide(color: Colors.purple.shade400, width: 1.2),
                                                            backgroundColor: Colors.purple.shade50.withValues(alpha: 0.3),
                                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                                            minimumSize: const Size(64, 44),
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                                          ),
                                                          icon: _isAiChecking
                                                              ? const SizedBox(
                                                                  width: 18,
                                                                  height: 18,
                                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                                )
                                                              : const Icon(Icons.auto_awesome, size: 18),
                                                          label: const Text(
                                                            "Kiểm tra chất lượng xe",
                                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                                          ),
                                                          onPressed: _isAiChecking ? null : _runAiQualityCheck,
                                                        ),
                                                      ),

                                                      SizedBox(
                                                        height: 44,
                                                        child: ElevatedButton.icon(
                                                          style: ElevatedButton.styleFrom(
                                                            elevation: 0,
                                                            shadowColor: Colors
                                                                .transparent,
                                                            backgroundColor:
                                                                Colors
                                                                    .green
                                                                    .shade700,
                                                            foregroundColor:
                                                                Colors.white,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      16,
                                                                ),
                                                            minimumSize:
                                                                const Size(
                                                                  64,
                                                                  44,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .check_circle_outline,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            "Duyệt Nhận Chuyến",
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13.5,
                                                            ),
                                                          ),
                                                          onPressed: () =>
                                                              _updateReviewStatus(
                                                                'approved',
                                                              ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 44,
                                                        child: OutlinedButton.icon(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor:
                                                                Colors
                                                                    .amber
                                                                    .shade900,
                                                            side: BorderSide(
                                                              color: Colors
                                                                  .amber
                                                                  .shade700,
                                                              width: 1.2,
                                                            ),
                                                            backgroundColor:
                                                                Colors
                                                                    .amber
                                                                    .shade50
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      14,
                                                                ),
                                                            minimumSize:
                                                                const Size(
                                                                  64,
                                                                  44,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .visibility_outlined,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            "Theo Dõi",
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13.5,
                                                            ),
                                                          ),
                                                          onPressed: () =>
                                                              _updateReviewStatus(
                                                                'monitored',
                                                              ),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height: 44,
                                                        child: OutlinedButton.icon(
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor:
                                                                Colors
                                                                    .red
                                                                    .shade700,
                                                            side: BorderSide(
                                                              color: Colors
                                                                  .red
                                                                  .shade400,
                                                              width: 1.2,
                                                            ),
                                                            backgroundColor:
                                                                Colors
                                                                    .red
                                                                    .shade50
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      14,
                                                                ),
                                                            minimumSize:
                                                                const Size(
                                                                  64,
                                                                  44,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                          ),
                                                          icon: const Icon(
                                                            Icons
                                                                .cancel_outlined,
                                                            size: 18,
                                                          ),
                                                          label: const Text(
                                                            "Yêu Cầu Chụp Lại",
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 13.5,
                                                            ),
                                                          ),
                                                          onPressed: () =>
                                                              _updateReviewStatus(
                                                                'rejected',
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                              ],
                                            );
                                          },
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

  /// Gọi Proxy AI (OpenAI-compatible Vision) soi 5 ảnh tài xế chụp đầu ca,
  /// đánh giá chất lượng toàn diện của xe có đủ tiêu chuẩn an toàn để khởi hành
  /// hay không, gợi ý cho Điều phối và Quản lý.
  Future<void> _runAiQualityCheck() async {
    final record = _selectedRecord;
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chưa chọn lượt kiểm tra để phân tích")),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('proxy_ai_enabled') ?? false)) {
      _showAiResultDialog(
        title: "Proxy AI chưa bật",
        content:
            "Chưa kích hoạt Gateway Proxy AI. Vào Cài đặt > Cấu Hình Proxy AI & Trợ Lý Thông Minh để bật trước khi dùng chức năng này.",
      );
      return;
    }
    final apiKey = (prefs.getString('proxy_ai_api_key') ?? '').trim();
    if (apiKey.isEmpty) {
      _showAiResultDialog(
        title: "Thiếu API key",
        content:
            "Chưa cấu hình API key cho Proxy AI. Vào Cài đặt > Cấu Hình Proxy AI để bổ sung.",
      );
      return;
    }
    setState(() => _isAiChecking = true);
    try {
      final specs = <Map<String, String>>[
        {'field': 'img_front_underbody', 'label': 'Ảnh gầm trước'},
        {'field': 'img_rear_underbody', 'label': 'Ảnh gầm sau'},
        {'field': 'img_left_side', 'label': 'Ảnh bên trái xe'},
        {'field': 'img_right_side', 'label': 'Ảnh bên phải xe'},
        {'field': 'img_dashboard', 'label': 'Ảnh đồng hồ táp-lô'},
      ];
      final plate = (record['plate_number'] ?? record['plate'] ?? '')
          .toString();
      final driver = (record['driver_name'] ?? '').toString();
      final content = <Map<String, dynamic>>[
        {
          'type': 'text',
          'text':
              'Đây là 5 ảnh kiểm tra xe đầu ca do tài xế chụp (thứ tự gửi: gầm trước, gầm sau, bên trái, bên phải, đồng hồ táp-lô; một số ảnh có thể thiếu hoặc không đọc được). '
                  'Biển số: ${plate.isEmpty ? 'không rõ' : plate}. '
                  'Tài xế: ${driver.isEmpty ? 'không rõ' : driver}. '
                  'Hãy đánh giá chất lượng toàn diện của xe và khả năng an toàn để khởi hành.',
        },
      ];
      for (final spec in specs) {
        final bytes = await _loadImageBytes(
          record[spec['field']]?.toString() ?? '',
        );
        if (bytes == null) continue;
        content.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,${base64Encode(bytes)}',
          },
        });
      }
      if (content.length <= 1) {
        _showAiResultDialog(
          title: "Không có ảnh hợp lệ",
          content:
              "Lượt kiểm tra này không tải được ảnh nào để phân tích. Vui lòng kiểm tra lại dữ liệu ảnh.",
        );
        return;
      }
      final endpoint = (prefs.getString('proxy_ai_endpoint') ??
              'https://api.openai.com/v1')
          .trim();
      final normalized = endpoint.endsWith('/')
          ? endpoint.substring(0, endpoint.length - 1)
          : endpoint;
      final url = '$normalized/chat/completions';
      final model = (prefs.getString('proxy_ai_model') ?? 'gpt-4o-mini')
          .trim();
      final maxTokens =
          int.tryParse(prefs.getString('proxy_ai_max_tokens') ?? '2048') ??
              2048;
      final temperature =
          double.tryParse(prefs.getString('proxy_ai_temperature') ?? '0.7') ??
              0.7;
      final resp = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'temperature': temperature,
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'system', 'content': _aiSystemPrompt()},
                {'role': 'user', 'content': content},
              ],
            }),
          )
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        final bodyPreview = resp.body.length > 600
            ? resp.body.substring(0, 600)
            : resp.body;
        _showAiResultDialog(
          title: "Lỗi Proxy AI",
          content: "Máy chủ AI trả về mã ${resp.statusCode}:\n$bodyPreview",
        );
        return;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      String text = '';
      if (choices != null && choices.isNotEmpty) {
        final message =
            (choices.first as Map<String, dynamic>)['message']
                as Map<String, dynamic>?;
        text = message?['content']?.toString() ?? '';
      }
      if (text.trim().isEmpty) {
        _showAiResultDialog(
          title: "Kết quả trống",
          content:
              "AI không trả về nội dung phân tích. Vui lòng thử lại sau.",
        );
        return;
      }
      _showAiResultDialog(
        title: "Kiểm tra chất lượng xe (AI)",
        content: text.trim(),
      );
    } catch (e) {
      _showAiResultDialog(
        title: "Lỗi kết nối Proxy AI",
        content: "Không gọi được máy chủ AI:\n$e",
      );
    } finally {
      if (mounted) setState(() => _isAiChecking = false);
    }
  }

  /// System prompt chuẩn cho bài kiểm tra chất lượng xe đầu ca.
  String _aiSystemPrompt() {
    return 'Bạn là chuyên gia kiểm định an toàn phương tiện đường bộ (xe đầu kéo, xe tải). '
        'Bạn nhận 5 ảnh kiểm tra xe đầu ca do tài xế tự chụp: gầm trước, gầm sau, hai bên hông xe và đồng hồ táp-lô. '
        'Hãy phân tích kỹ từng ảnh: gầm xe (nứt khung, rò rỉ dầu/nước làm mát, ốc vít lỏng, bình xăng, la zăng), '
        'thân xe (vỡ kính, gương chiếu hậu, đèn, lốp mòn hoặc non hơi, vết móp nứt nghiêm trọng), '
        'táp-lô (đèn cảnh báo đang sáng, mã lỗi động cơ, áp suất lốp, mức nhiên liệu). '
        'Trả lời bằng tiếng Việt, ngắn gọn, theo đúng cấu trúc: '
        '1) KẾT LUẬN: ĐẠT TIÊU CHUẨN / KHÔNG ĐẠT / CẦN THEO DÕI trước khi khởi hành; '
        '2) PHÁT HIỆN THEO TỪNG ẢNH (nêu rõ ảnh nào có vấn đề, ảnh mờ hoặc thiếu thì ghi rõ); '
        '3) RỦI RO AN TOÀN nếu cho xe chạy; '
        '4) GỢI Ý CHO ĐIỀU PHỐI & QUẢN LÝ: duyệt khởi hành, yêu cầu chụp lại, hay đưa xe vào sửa chữa. '
        'Không suy diễn khi thiếu dữ liệu, ưu tiên an toàn là trên hết.';
  }

  /// Tải bytes ảnh từ URL hoặc file cục bộ (khớp logic hiển thị _buildSafeImage).
  Future<List<int>?> _loadImageBytes(String raw) async {
    try {
      if (raw.isEmpty) return null;
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        final resp = await http
            .get(Uri.parse(raw))
            .timeout(const Duration(seconds: 30));
        return resp.statusCode == 200 ? resp.bodyBytes : null;
      }
      final f = File(raw);
      if (f.existsSync()) {
        return f.readAsBytesSync();
      }
      final fixed = raw.startsWith('/')
          ? 'https://saomai-api.type.vn$raw'
          : 'https://saomai-api.type.vn/$raw';
      final resp = await http
          .get(Uri.parse(fixed))
          .timeout(const Duration(seconds: 30));
      return resp.statusCode == 200 ? resp.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Hộp thoại hiển thị kết quả/lỗi của Proxy AI.
  void _showAiResultDialog({
    required String title,
    required String content,
  }) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, size: 22, color: Colors.purple.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            content,
            style: const TextStyle(fontSize: 14.5, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Đã hiểu"),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChoiceChip(
    String label,
    String value,
    MaterialColor color,
  ) {
    final isSelected = _filterStatus == value;
    final Color activeColor = color.shade700;
    final Color bg = isSelected
        ? activeColor.withValues(alpha: 0.12)
        : Colors.white;
    final Color border = isSelected ? activeColor : Colors.grey.shade300;
    final Color textColor = isSelected
        ? (color == Colors.blueGrey ? Colors.blueGrey.shade900 : activeColor)
        : Colors.grey.shade700;

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
          final String plateKey = (_selectedRecord?['plate_number'] ?? '')
              .toString();
          if (plateKey.isNotEmpty) {
            _loadPlateHistory(
              plateKey,
              focusInspectionId: _focusIdOf(_selectedRecord),
            );
          } else if (mounted) {
            setState(() {
              _plateHistory = [];
              _historyIndex = 0;
            });
          }
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
