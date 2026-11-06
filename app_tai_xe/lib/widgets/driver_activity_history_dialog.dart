import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/admin_service.dart';

/// Dialog tra cứu "Lịch sử hoạt động" của Tài xế (Báo nghỉ, Hủy báo nghỉ, ...)
/// cho Điều phối / Quản lý. Dữ liệu lấy từ endpoint /driver-activity-logs.
class DriverActivityHistoryDialog extends StatefulWidget {
  final Map<String, dynamic>? targetUser;

  const DriverActivityHistoryDialog({super.key, this.targetUser});

  static Future<void> show(
    BuildContext context, {
    Map<String, dynamic>? targetUser,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => DriverActivityHistoryDialog(targetUser: targetUser),
    );
  }

  @override
  State<DriverActivityHistoryDialog> createState() =>
      _DriverActivityHistoryDialogState();
}

class _DriverActivityHistoryDialogState
    extends State<DriverActivityHistoryDialog> {
  DateTime? _filterDate;
  String? _filterAction;
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Danh sách loại hoạt động hiển thị trong bộ lọc (khớp action backend ghi)
  static const Map<String, String> _actionLabels = {
    'BAO_NGHI': 'Báo nghỉ',
    'VEHOATDONG': 'Hủy báo nghỉ / Kích hoạt xe',
  };

  Future<List<dynamic>> _loadLogs() async {
    return AdminService.fetchDriverActivityLogs(
      userId: widget.targetUser?['id'] as int?,
      username: widget.targetUser?['username'] as String?,
      action: _filterAction,
      dateFrom: _filterDate != null
          ? '${_filterDate!.year.toString().padLeft(4, '0')}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}'
          : null,
      dateTo: _filterDate != null
          ? '${_filterDate!.year.toString().padLeft(4, '0')}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')} 23:59:59'
          : null,
      limit: 200,
    );
  }

  String _formatTime(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} (${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year})";
    } catch (_) {
      return iso;
    }
  }

  MaterialColor _actionColor(String action) {
    switch (action) {
      case 'BAO_NGHI':
        return Colors.red;
      case 'VEHOATDONG':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }


  @override
  Widget build(BuildContext context) {
    final String? filterFullName =
        widget.targetUser?['full_name'] as String? ??
        widget.targetUser?['username'] as String?;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(
        minWidth: 320,
        maxWidth: math.min(760.0, MediaQuery.of(context).size.width * 0.98),
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: FutureBuilder<List<dynamic>>(
          future: _loadLogs(),
          builder: (context, snapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.fact_check,
                        color: Colors.teal.shade800,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filterFullName != null
                                ? "Lịch sử hoạt động - $filterFullName"
                                : "Lịch sử hoạt động Tài xế",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            filterFullName != null
                                ? "Ghi nhận Báo nghỉ, Hủy báo nghỉ và các hoạt động của tài xế $filterFullName"
                                : "Ghi nhận Báo nghỉ, Hủy báo nghỉ và các hoạt động của tài xế",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: "Đóng",
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                // Thanh bộ lọc: ngày + loại hoạt động
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      Icon(
                        Icons.filter_alt,
                        size: 18,
                        color: Colors.teal.shade800,
                      ),
                      const Text(
                        "Lọc:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      // Bộ lọc theo ngày
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _filterDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            helpText: "CHỌN NGÀY XEM",
                            cancelText: "HỦY",
                            confirmText: "CHỌN",
                          );
                          if (picked != null) {
                            setState(() {
                              _filterDate = picked;
                              _currentPage = 1;
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _filterDate != null
                                  ? Colors.teal.shade600
                                  : Colors.grey.shade400,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: _filterDate != null
                                    ? Colors.teal.shade800
                                    : Colors.grey.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _filterDate != null
                                    ? "${_filterDate!.day.toString().padLeft(2, '0')}/${_filterDate!.month.toString().padLeft(2, '0')}/${_filterDate!.year}"
                                    : "Tất cả các ngày",
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: _filterDate != null
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _filterDate != null
                                      ? Colors.teal.shade900
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_filterDate != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(
                            Icons.clear,
                            size: 15,
                            color: Colors.red,
                          ),
                          label: const Text(
                            "Xóa lọc ngày",
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                          onPressed: () {
                            setState(() {
                              _filterDate = null;
                              _currentPage = 1;
                            });
                          },
                        ),
                      // Bộ lọc theo loại hoạt động
                      DropdownButton<String>(
                        value: _filterAction,
                        hint: const Text(
                          "Tất cả loại hoạt động",
                          style: TextStyle(fontSize: 12.5),
                        ),
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        items: _actionLabels.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _filterAction = v;
                            _currentPage = 1;
                          });
                        },
                      ),
                      if (_filterAction != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(
                            Icons.clear,
                            size: 15,
                            color: Colors.red,
                          ),
                          label: const Text(
                            "Xóa lọc loại",
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                          onPressed: () {
                            setState(() {
                              _filterAction = null;
                              _currentPage = 1;
                            });
                          },
                        ),
                    ],
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Expanded(
                    child: Center(
                      child: Text(
                        "Lỗi tải lịch sử hoạt động: ${snapshot.error}",
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
                          Icon(
                            Icons.event_busy,
                            size: 48,
                            color: Colors.blueGrey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            filterFullName != null
                                ? "Tài xế $filterFullName chưa có lịch sử hoạt động nào."
                                : "Chưa có dữ liệu lịch sử hoạt động nào được ghi nhận.",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blueGrey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final logs = snapshot.data!;
                        final totalPages = (logs.length / _pageSize).ceil();
                        final validPage = _currentPage > totalPages
                            ? totalPages
                            : (_currentPage < 1 ? 1 : _currentPage);
                        final startIndex = (validPage - 1) * _pageSize;
                        final endIndex =
                            (startIndex + _pageSize > logs.length)
                            ? logs.length
                            : startIndex + _pageSize;
                        final pagedLogs = logs.sublist(startIndex, endIndex);

                        return Column(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                  child: ListView.separated(
                                    itemCount: pagedLogs.length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color: Colors.grey.shade200,
                                    ),
                                    itemBuilder: (context, index) {
                                      final log = pagedLogs[index];
                                      final action =
                                          log['action']?.toString() ?? '';
                                      final label =
                                          _actionLabels[action] ?? action;
                                      final detail =
                                          log['action_detail']?.toString() ?? '';
                                      final plate =
                                          log['plate']?.toString() ?? '';
                                      final createdAt =
                                          log['created_at']?.toString() ?? '';
                                      final fullName =
                                          log['full_name']?.toString() ?? '';
                                      final username =
                                          log['username']?.toString() ?? '';
                                      final MaterialColor color = _actionColor(action);

                                      return Container(
                                        color: index.isEven
                                            ? Colors.white
                                            : Colors.grey.shade50,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: color.withOpacity(0.08),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.event_note,
                                                size: 18,
                                                color: color,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: color
                                                              .withOpacity(0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                          border: Border.all(
                                                            color: color
                                                                .withOpacity(
                                                              0.4,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          label,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: color
                                                                .shade900,
                                                          ),
                                                        ),
                                                      ),
                                                      if (plate.isNotEmpty) ...[
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          plate,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors
                                                                .blueGrey
                                                                .shade800,
                                                          ),
                                                        ),
                                                      ],
                                                      const Spacer(),
                                                      Text(
                                                        _formatTime(createdAt),
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  if (detail.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      detail,
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        color: Colors
                                                            .grey.shade800,
                                                      ),
                                                    ),
                                                  ],
                                                  if (fullName.isNotEmpty ||
                                                      username.isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        top: 2,
                                                      ),
                                                      child: Text(
                                                        "Tài khoản: $username${fullName.isNotEmpty ? " - $fullName" : ""}",
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors
                                                              .grey.shade500,
                                                        ),
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
                            ),
                            // Phân trang
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: validPage > 1
                                        ? () => setState(() {
                                              _currentPage = validPage - 1;
                                            })
                                        : null,
                                  ),
                                  Text(
                                    "Trang $validPage/$totalPages (${logs.length} bản ghi)",
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: validPage < totalPages
                                        ? () => setState(() {
                                              _currentPage = validPage + 1;
                                            })
                                        : null,
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
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
  }
}
