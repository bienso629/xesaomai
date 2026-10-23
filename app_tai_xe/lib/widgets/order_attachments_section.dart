import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/admin_service.dart';
import '../screens/slip_capture_screen.dart';

/// Khối hiển thị & thao tác đầy đủ 5 nhóm hình chụp của một Đơn hàng vận tải:
/// 1. Ảnh bơm hàng: 2 ảnh bắt buộc Trước khi bơm và Đã bơm xong (do Tài xế chụp, có GPS)
/// 2. Phiếu cân (do Tài xế chụp ở Bước 3)
/// 3. Phiếu giao hàng (do Tài xế chụp ở Bước 4)
/// 4. Tình trạng Báo hỏng xe (do Tài xế chụp ảnh & báo hỏng trong lúc vận chuyển)
/// 5. Tình trạng Sửa chữa xe (do tài khoản Kỹ thuật chụp ảnh & cập nhật)
class OrderAttachmentsSection extends StatelessWidget {
  const OrderAttachmentsSection({
    super.key,
    required this.order,
    this.onOrderUpdated,
    this.readOnly = false,
  });

  final Map<String, dynamic> order;
  final ValueChanged<Map<String, dynamic>>? onOrderUpdated;
  final bool readOnly;

  static String resolvePhotoUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    final host = AdminService.baseUrl.replaceAll('/api/v1', '');
    final clean = s.startsWith('/') ? s.substring(1) : s;
    return '$host/$clean';
  }

  static void showFullImageDialog(
    BuildContext context, {
    required String title,
    required String rawUrl,
    String? subtitle,
  }) {
    final s = rawUrl.trim();
    if (s.isEmpty) return;
    final bool isLocalFile =
        s.startsWith('/') && !s.startsWith('/uploads/') && File(s).existsSync();
    final fullUrl = isLocalFile ? s : resolvePhotoUrl(s);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E293B),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_camera_back_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (subtitle != null && subtitle.trim().isNotEmpty)
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.all(8),
                  child: InteractiveViewer(
                    child: isLocalFile
                        ? Image.file(File(fullUrl), fit: BoxFit.contain)
                        : Image.network(
                            fullUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Text(
                                "Không tải được hình chụp từ máy chủ",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s.length > 16 ? s.substring(0, 16) : s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final roles = state.userRoles.map((r) => r.toLowerCase()).toList();
    final isAdminOrManager =
        state.currentUsername == 'admin' ||
        roles.contains('admin') ||
        roles.contains('manager') ||
        roles.contains('dispatcher');
    // Quan ly / Dieu phoi / Admin chi xem hinh chup cua cac bo phan, khong hien nut bat phai chup
    final allowCapture = !readOnly && !isAdminOrManager;
    final isDriver = allowCapture && roles.contains('driver');
    final isMechanic = allowCapture && roles.contains('mechanic');

    final int? orderId = order['id'] is int
        ? order['id'] as int
        : int.tryParse((order['id'] ?? '').toString());
    final orderCode = (order['order_code'] ?? '').toString();
    final plate =
        (order['assigned_vehicle_plate'] ?? order['vehicle_plate'] ?? '')
            .toString();

    final pumpBeforePhoto = (order['pump_slip_before_photo_url'] ??
            order['pump_before_photo_url'] ??
            '')
        .toString()
        .trim();
    final pumpBeforeTime = _fmtTime(order['pump_slip_before_time'] ?? order['pump_before_time']);
    final pumpBeforeBy = (order['pump_slip_before_by'] ?? order['pump_before_by'] ?? '').toString().trim();

    final pumpPhoto = (order['pump_slip_photo_url'] ?? '').toString().trim();
    final pumpTime = _fmtTime(order['pump_slip_time']);
    final pumpBy = (order['pump_slip_by'] ?? '').toString().trim();
    final pumpNote = (order['pump_slip_note'] ?? '').toString().trim();

    final weighPhoto = (order['weigh_slip_photo_url'] ?? '').toString().trim();
    final weighTime = _fmtTime(order['weigh_slip_time']);
    final weighTonnage = order['weigh_slip_tonnage'];
    final weighCode = (order['weigh_slip_code'] ?? '').toString().trim();

    final deliveryPhoto =
        (order['delivery_slip_photo_url'] ?? '').toString().trim();
    final deliveryTime = _fmtTime(order['delivery_slip_time']);
    final deliveryNote = (order['delivery_slip_note'] ?? '').toString().trim();

    final hasBreakdown =
        order['has_breakdown'] == true ||
        (order['breakdown_photo_url'] ?? '').toString().trim().isNotEmpty;
    final breakdownPhoto =
        (order['breakdown_photo_url'] ?? '').toString().trim();
    final breakdownReason =
        (order['breakdown_reason'] ?? '').toString().trim();
    final breakdownLoc = (order['breakdown_location'] ?? '').toString().trim();
    final breakdownTime = _fmtTime(order['breakdown_time']);
    final breakdownBy =
        (order['breakdown_reported_by'] ?? '').toString().trim();
    final breakdownStatus =
        (order['breakdown_status'] ?? '').toString().trim();

    final repairPhoto = (order['repair_photo_url'] ?? '').toString().trim();
    final repairStatus = (order['repair_status'] ?? '').toString().trim();
    final repairNote = (order['repair_note'] ?? '').toString().trim();
    final repairTime = _fmtTime(order['repair_time']);
    final repairBy = (order['repair_by'] ?? '').toString().trim();

    Future<void> captureType(String slipType) async {
      if (orderId == null) return;
      final res = await SlipCaptureScreen.show(
        context,
        slipType: slipType,
        orderId: orderId,
        orderCode: orderCode,
        vehiclePlate: plate,
      );
      if (res != null && onOrderUpdated != null) {
        onOrderUpdated!(res);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "HỒ SƠ HÌNH CHỤP CHỨNG TỪ & SỰ CỐ ĐƠN HÀNG",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        _buildAttachmentCard(
          context,
          icon: Icons.local_gas_station_outlined,
          accentColor: const Color(0xFF0284C7),
          title: "1a. Bơm hàng - Trước khi bơm (Tài xế, bắt buộc)",
          photoUrl: pumpBeforePhoto,
          statusText: pumpBeforePhoto.isNotEmpty
              ? "Đã chụp${pumpBeforeTime.isNotEmpty ? ' • $pumpBeforeTime' : ''}${pumpBeforeBy.isNotEmpty ? ' • $pumpBeforeBy' : ''}"
              : "Chưa có ảnh TRƯỚC khi bơm",
          canCapture: isDriver && orderId != null,
          captureLabel: pumpBeforePhoto.isNotEmpty
              ? "Chụp lại (Trước khi bơm)"
              : "Chụp ảnh Trước khi bơm",
          onCapture: () => captureType('pump_before'),
        ),
        const SizedBox(height: 8),
        _buildAttachmentCard(
          context,
          icon: Icons.local_gas_station_outlined,
          accentColor: const Color(0xFF0284C7),
          title: "1b. Bơm hàng - Đã bơm xong (Tài xế, bắt buộc)",
          photoUrl: pumpPhoto,
          statusText: pumpPhoto.isNotEmpty
              ? "Đã chụp${pumpTime.isNotEmpty ? ' • $pumpTime' : ''}${pumpBy.isNotEmpty ? ' • $pumpBy' : ''}"
              : "Chưa có ảnh ĐÃ BƠM XONG",
          detailText: pumpNote.isNotEmpty ? "Ghi chú: $pumpNote" : null,
          // Ảnh "Đã bơm xong" chỉ mở khi đã có ảnh "Trước khi bơm"
          canCapture: isDriver && orderId != null && pumpBeforePhoto.isNotEmpty,
          captureLabel: pumpPhoto.isNotEmpty
              ? "Chụp lại (Đã bơm xong)"
              : "Chụp ảnh Đã bơm xong",
          onCapture: () => captureType('pump_slip'),
        ),
        const SizedBox(height: 8),
        _buildAttachmentCard(
          context,
          icon: Icons.scale_outlined,
          accentColor: const Color(0xFF2563EB),
          title: "2. Phiếu cân hàng (Tài xế - Bước 3)",
          photoUrl: weighPhoto,
          statusText: weighPhoto.isNotEmpty
              ? "Đã chụp${weighTime.isNotEmpty ? ' • $weighTime' : ''}"
              : "Chưa có ảnh Phiếu cân",
          detailText: [
            if (weighTonnage != null && weighTonnage.toString() != '0')
              "Khối lượng cân: $weighTonnage Tấn",
            if (weighCode.isNotEmpty) "Mã phiếu: $weighCode",
          ].join(" • "),
          canCapture: isDriver && orderId != null,
          captureLabel:
              weighPhoto.isNotEmpty ? "Chụp lại Phiếu cân" : "Chụp Phiếu cân",
          onCapture: () => captureType('weigh_slip'),
        ),
        const SizedBox(height: 8),
        _buildAttachmentCard(
          context,
          icon: Icons.assignment_turned_in_outlined,
          accentColor: const Color(0xFF15803D),
          title: "3. Phiếu giao hàng (Tài xế - Bước 4)",
          photoUrl: deliveryPhoto,
          statusText: deliveryPhoto.isNotEmpty
              ? "Đã chụp${deliveryTime.isNotEmpty ? ' • $deliveryTime' : ''}"
              : "Chưa có ảnh Phiếu giao hàng",
          detailText: deliveryNote.isNotEmpty ? "Ghi chú: $deliveryNote" : null,
          canCapture: isDriver && orderId != null,
          captureLabel: deliveryPhoto.isNotEmpty
              ? "Chụp lại Phiếu giao"
              : "Chụp Phiếu giao hàng",
          onCapture: () => captureType('delivery_slip'),
        ),
        const SizedBox(height: 8),
        _buildAttachmentCard(
          context,
          icon: Icons.car_crash_outlined,
          accentColor: hasBreakdown
              ? const Color(0xFFDC2626)
              : const Color(0xFF64748B),
          title: "4. Tình trạng Báo hỏng xe (Tài xế báo sự cố)",
          photoUrl: breakdownPhoto,
          statusText: hasBreakdown
              ? (breakdownStatus == 'resolved'
                    ? "Đã khắc phục sự cố${breakdownTime.isNotEmpty ? ' • Báo lúc $breakdownTime' : ''}"
                    : "ĐANG BÁO HỎNG XE${breakdownTime.isNotEmpty ? ' • $breakdownTime' : ''}${breakdownBy.isNotEmpty ? ' • $breakdownBy' : ''}")
              : "Không có sự cố hỏng xe trên chuyến này",
          detailText: [
            if (breakdownReason.isNotEmpty) "Sự cố: $breakdownReason",
            if (breakdownLoc.isNotEmpty) "Vị trí: $breakdownLoc",
          ].join(" • "),
          canCapture: isDriver && orderId != null,
          captureLabel:
              hasBreakdown ? "Cập nhật ảnh Báo hỏng" : "Chụp & Báo hỏng xe",
          onCapture: () => captureType('breakdown'),
        ),
        const SizedBox(height: 8),
        _buildAttachmentCard(
          context,
          icon: Icons.build_circle_outlined,
          accentColor: const Color(0xFFD97706),
          title: "5. Báo cáo Sửa chữa xe (Tài khoản Kỹ thuật)",
          photoUrl: repairPhoto,
          statusText: repairPhoto.isNotEmpty
              ? "${repairStatus == 'fixed' ? 'Đã sửa chữa hoàn tất' : 'Đang sửa chữa'}${repairTime.isNotEmpty ? ' • $repairTime' : ''}${repairBy.isNotEmpty ? ' • KT: $repairBy' : ''}"
              : (hasBreakdown
                    ? "Đang chờ Kỹ thuật chụp ảnh & cập nhật kết quả sửa chữa"
                    : "Chưa có phát sinh sửa chữa"),
          detailText: repairNote.isNotEmpty
              ? "Ghi chú Kỹ thuật: $repairNote"
              : null,
          canCapture: isMechanic && orderId != null,
          captureLabel: repairPhoto.isNotEmpty
              ? "Cập nhật ảnh Sửa chữa"
              : "Chụp ảnh Sửa chữa (Kỹ thuật)",
          onCapture: () => captureType('repair'),
        ),
      ],
    );
  }

  Widget _buildAttachmentCard(
    BuildContext context, {
    required IconData icon,
    required Color accentColor,
    required String title,
    required String photoUrl,
    required String statusText,
    String? detailText,
    required bool canCapture,
    required String captureLabel,
    required VoidCallback onCapture,
  }) {
    final hasPhoto = photoUrl.trim().isNotEmpty;
    final bool isLocal =
        hasPhoto &&
        photoUrl.startsWith('/') &&
        !photoUrl.startsWith('/uploads/') &&
        File(photoUrl).existsSync();
    final resolvedUrl = hasPhoto
        ? (isLocal ? photoUrl : resolvePhotoUrl(photoUrl))
        : '';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasPhoto ? accentColor.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: hasPhoto
              ? accentColor.withValues(alpha: 0.35)
              : Colors.grey.shade300,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: hasPhoto
                ? () => showFullImageDialog(
                    context,
                    title: title,
                    rawUrl: photoUrl,
                    subtitle: statusText,
                  )
                : null,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasPhoto
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        isLocal
                            ? Image.file(File(resolvedUrl), fit: BoxFit.cover)
                            : Image.network(
                                resolvedUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.grey.shade500,
                                  size: 22,
                                ),
                              ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Icon(icon, color: accentColor, size: 22),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: hasPhoto ? FontWeight.w600 : FontWeight.normal,
                    color: hasPhoto ? accentColor : Colors.grey.shade600,
                  ),
                ),
                if (detailText != null && detailText.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detailText,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (hasPhoto)
                      SizedBox(
                        height: 28,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            side: BorderSide(
                              color: accentColor.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: () => showFullImageDialog(
                            context,
                            title: title,
                            rawUrl: photoUrl,
                            subtitle: statusText,
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 14),
                          label: const Text(
                            "Xem ảnh",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    if (canCapture)
                      SizedBox(
                        height: 28,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: onCapture,
                          icon: const Icon(Icons.camera_alt_outlined, size: 14),
                          label: Text(
                            captureLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
