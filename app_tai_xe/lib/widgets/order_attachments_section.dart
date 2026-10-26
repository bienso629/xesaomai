import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracy,
    String? gpsCapturedAt,
    String? photoGeoLabel,
  }) {
    final s = rawUrl.trim();
    if (s.isEmpty) return;
    final bool isLocalFile =
        s.startsWith('/') && !s.startsWith('/uploads/') && File(s).existsSync();
    final fullUrl = isLocalFile ? s : resolvePhotoUrl(s);

    final bool hasGps = gpsLat != null &&
        gpsLng != null &&
        (gpsLat != 0.0 || gpsLng != 0.0);

    final bool isGeoWarning = photoGeoLabel != null &&
        (photoGeoLabel.startsWith('Ngoài') ||
         photoGeoLabel.contains('KHÔNG') ||
         photoGeoLabel.contains('không khớp') ||
         photoGeoLabel.contains('Cảnh báo'));

    final Color bgColor = !hasGps
        ? const Color(0xFF78350F).withValues(alpha: 0.85)
        : isGeoWarning
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.92)
            : const Color(0xFF064E3B).withValues(alpha: 0.85);

    final Color borderColor = !hasGps
        ? const Color(0xFFD97706).withValues(alpha: 0.4)
        : isGeoWarning
            ? const Color(0xFFEF4444).withValues(alpha: 0.5)
            : const Color(0xFF059669).withValues(alpha: 0.4);

    final IconData statusIcon = !hasGps
        ? Icons.location_off_outlined
        : isGeoWarning
            ? Icons.wrong_location_outlined
            : Icons.location_on;

    final Color iconColor = !hasGps
        ? const Color(0xFFFBBF24)
        : isGeoWarning
            ? const Color(0xFFF87171)
            : const Color(0xFF34D399);

    final Color accuracyTextColor = isGeoWarning
        ? const Color(0xFFFCA5A5)
        : const Color(0xFF6EE7B7);

    final Color geoLabelTextColor = isGeoWarning
        ? const Color(0xFFFECDD3)
        : const Color(0xFFA7F3D0);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 660),
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
              // Thanh thông tin tọa độ GPS lúc tài xế chụp ảnh
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: bgColor,
                  border: Border(
                    bottom: BorderSide(
                      color: borderColor,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      statusIcon,
                      color: iconColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: hasGps
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      "Tọa độ GPS lúc chụp: ${gpsLat.toStringAsFixed(6)}, ${gpsLng.toStringAsFixed(6)}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (gpsAccuracy != null && gpsAccuracy > 0)
                                      Text(
                                        "(±${gpsAccuracy.round()}m)",
                                        style: TextStyle(
                                          color: accuracyTextColor,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                                if (photoGeoLabel != null && photoGeoLabel.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    photoGeoLabel,
                                    style: TextStyle(
                                      color: geoLabelTextColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ] else if (gpsCapturedAt != null && gpsCapturedAt.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    "Thời điểm ghi nhận: $gpsCapturedAt",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : const Text(
                              "Không có thông tin tọa độ GPS ghi nhận lúc chụp",
                              style: TextStyle(
                                color: Color(0xFFFDE68A),
                                fontSize: 11.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                    ),
                    if (hasGps) ...[
                      const SizedBox(width: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(
                                text: "${gpsLat.toStringAsFixed(6)}, ${gpsLng.toStringAsFixed(6)}",
                              ));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Đã sao chép tọa độ GPS vào clipboard"),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy, size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    "Sao chép",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () async {
                              final uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$gpsLat,$gpsLng");
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF34D399),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.map_outlined, size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    "Mở Maps",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
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
    final showGeo = readOnly || isAdminOrManager;
    Widget? geo(String ptype) => showGeo ? _buildGeoCheck(order, ptype) : null;
    String? geoSummary(String ptype) => _geoLabel(order, ptype);

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
    final pumpBeforeLat = _asDouble(order['pump_slip_before_gps_lat'] ?? order['pump_before_gps_lat']);
    final pumpBeforeLng = _asDouble(order['pump_slip_before_gps_lng'] ?? order['pump_before_gps_lng']);
    final pumpBeforeAcc = _asDouble(order['pump_slip_before_gps_accuracy'] ?? order['pump_before_gps_accuracy']);
    final pumpBeforeGpsAt = (order['pump_slip_before_gps_captured_at'] ?? order['pump_before_gps_captured_at'] ?? '').toString();

    final pumpPhoto = (order['pump_slip_photo_url'] ?? '').toString().trim();
    final pumpTime = _fmtTime(order['pump_slip_time']);
    final pumpBy = (order['pump_slip_by'] ?? '').toString().trim();
    final pumpNote = (order['pump_slip_note'] ?? '').toString().trim();
    final pumpLat = _asDouble(order['pump_slip_gps_lat']);
    final pumpLng = _asDouble(order['pump_slip_gps_lng']);
    final pumpAcc = _asDouble(order['pump_slip_gps_accuracy']);
    final pumpGpsAt = (order['pump_slip_gps_captured_at'] ?? '').toString();

    final weighPhoto = (order['weigh_slip_photo_url'] ?? '').toString().trim();
    final weighTime = _fmtTime(order['weigh_slip_time']);
    final weighTonnage = order['weigh_slip_tonnage'];
    final weighCode = (order['weigh_slip_code'] ?? '').toString().trim();
    final weighLat = _asDouble(order['weigh_slip_gps_lat']);
    final weighLng = _asDouble(order['weigh_slip_gps_lng']);
    final weighAcc = _asDouble(order['weigh_slip_gps_accuracy']);
    final weighGpsAt = (order['weigh_slip_gps_captured_at'] ?? '').toString();

    final deliveryPhoto =
        (order['delivery_slip_photo_url'] ?? '').toString().trim();
    final deliveryTime = _fmtTime(order['delivery_slip_time']);
    final deliveryNote = (order['delivery_slip_note'] ?? '').toString().trim();
    final deliveryLat = _asDouble(order['delivery_slip_gps_lat']);
    final deliveryLng = _asDouble(order['delivery_slip_gps_lng']);
    final deliveryAcc = _asDouble(order['delivery_slip_gps_accuracy']);
    final deliveryGpsAt = (order['delivery_slip_gps_captured_at'] ?? '').toString();

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
    final breakdownLat = _asDouble(order['breakdown_gps_lat']);
    final breakdownLng = _asDouble(order['breakdown_gps_lng']);
    final breakdownAcc = _asDouble(order['breakdown_gps_accuracy']);
    final breakdownGpsAt = (order['breakdown_gps_captured_at'] ?? '').toString();

    final repairPhoto = (order['repair_photo_url'] ?? '').toString().trim();
    final repairStatus = (order['repair_status'] ?? '').toString().trim();
    final repairNote = (order['repair_note'] ?? '').toString().trim();
    final repairTime = _fmtTime(order['repair_time']);
    final repairBy = (order['repair_by'] ?? '').toString().trim();
    final repairLat = _asDouble(order['repair_gps_lat']);
    final repairLng = _asDouble(order['repair_gps_lng']);
    final repairAcc = _asDouble(order['repair_gps_accuracy']);
    final repairGpsAt = (order['repair_gps_captured_at'] ?? '').toString();

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
          geoCheck: geo('pump_slip_before'),
          onCapture: () => captureType('pump_before'),
          gpsLat: pumpBeforeLat,
          gpsLng: pumpBeforeLng,
          gpsAccuracy: pumpBeforeAcc,
          gpsCapturedAt: pumpBeforeGpsAt,
          photoGeoLabel: geoSummary('pump_slip_before'),
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
          geoCheck: geo('pump_slip'),
          onCapture: () => captureType('pump_slip'),
          gpsLat: pumpLat,
          gpsLng: pumpLng,
          gpsAccuracy: pumpAcc,
          gpsCapturedAt: pumpGpsAt,
          photoGeoLabel: geoSummary('pump_slip'),
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
          geoCheck: geo('weigh_slip'),
          onCapture: () => captureType('weigh_slip'),
          gpsLat: weighLat,
          gpsLng: weighLng,
          gpsAccuracy: weighAcc,
          gpsCapturedAt: weighGpsAt,
          photoGeoLabel: geoSummary('weigh_slip'),
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
          geoCheck: geo('delivery_slip'),
          onCapture: () => captureType('delivery_slip'),
          gpsLat: deliveryLat,
          gpsLng: deliveryLng,
          gpsAccuracy: deliveryAcc,
          gpsCapturedAt: deliveryGpsAt,
          photoGeoLabel: geoSummary('delivery_slip'),
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
          gpsLat: breakdownLat,
          gpsLng: breakdownLng,
          gpsAccuracy: breakdownAcc,
          gpsCapturedAt: breakdownGpsAt,
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
          gpsLat: repairLat,
          gpsLng: repairLng,
          gpsAccuracy: repairAcc,
          gpsCapturedAt: repairGpsAt,
        ),
      ],
    );
  }

  static String _fmtDistance(dynamic m) {
    final d = m is num ? m.toDouble() : double.tryParse('${m ?? ''}');
    if (d == null) return '';
    return d < 1000 ? '${d.round()} m' : '${(d / 1000).toStringAsFixed(1)} km';
  }

  /// Trích xuất chuỗi tóm tắt vị trí/đối chiếu GPS của ảnh
  static String? _geoLabel(Map<String, dynamic> order, String ptype) {
    final all = order['photo_geo_check'];
    if (all is! Map) return null;
    final c = all[ptype];
    if (c is! Map) return null;
    final matched = (c['matched'] ?? '').toString();

    final parts = <String>[];
    if (c['pickup_distance_m'] != null) {
      parts.add('Nơi nhận ${_fmtDistance(c['pickup_distance_m'])}');
    }
    if (c['delivery_distance_m'] != null) {
      parts.add('Điểm giao ${_fmtDistance(c['delivery_distance_m'])}');
    }

    String head;
    switch (matched) {
      case 'PICKUP':
        head = 'Tại Nơi nhận hàng';
        break;
      case 'DELIVERY':
        head = 'Tại Điểm giao hàng';
        break;
      case 'NONE':
        if (ptype == 'delivery_slip') {
          head = 'Ngoài điểm giao hàng';
        } else if (ptype == 'pump_slip_before' || ptype == 'pump_slip') {
          head = 'Ngoài điểm nhận hàng';
        } else {
          head = 'Ngoài điểm nhận/giao';
        }
        break;
      default:
        head = 'Đã ghi nhận tọa độ GPS';
    }
    return parts.isNotEmpty ? '$head (Cách ${parts.join(', ')})' : head;
  }

  /// Dòng đối chiếu GPS lúc chụp với Nơi nhận hàng / Điểm giao hàng của đơn.
  /// Dữ liệu lấy từ photo_geo_check do backend tính sẵn.
  static Widget? _buildGeoCheck(Map<String, dynamic> order, String ptype) {
    final all = order['photo_geo_check'];
    if (all is! Map) return null;
    final c = all[ptype];
    if (c is! Map) return null;
    final matched = (c['matched'] ?? '').toString();

    final parts = <String>[];
    if (c['pickup_distance_m'] != null) {
      parts.add('Nơi nhận ${_fmtDistance(c['pickup_distance_m'])}');
    }
    if (c['delivery_distance_m'] != null) {
      parts.add('Điểm giao ${_fmtDistance(c['delivery_distance_m'])}');
    }
    final acc = c['gps_accuracy'];
    final accText = acc is num ? ' (sai số GPS ±${acc.round()} m)' : '';

    late final Color color;
    late final IconData icon;
    late final String text;
    switch (matched) {
      case 'PICKUP':
        color = const Color(0xFF15803D);
        icon = Icons.verified_outlined;
        text = 'Chụp TẠI Nơi nhận hàng';
        break;
      case 'DELIVERY':
        color = const Color(0xFF15803D);
        icon = Icons.verified_outlined;
        text = 'Chụp TẠI Điểm giao hàng';
        break;
      case 'NONE':
        color = const Color(0xFFDC2626);
        icon = Icons.wrong_location_outlined;
        text = ptype == 'delivery_slip'
            ? 'KHÔNG ở Điểm giao hàng'
            : (ptype == 'pump_slip_before' || ptype == 'pump_slip')
                ? 'KHÔNG ở Nơi nhận hàng'
                : 'KHÔNG ở Nơi nhận hàng / Điểm giao hàng';
        break;
      default:
        color = const Color(0xFF64748B);
        icon = Icons.location_searching;
        text = 'Đơn chưa có tọa độ điểm nhận / giao để đối chiếu';
    }
    final detail = [
      if (parts.isNotEmpty) 'Cách ${parts.join(', ')}',
      if (accText.isNotEmpty) accText.trim(),
    ].join(' ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              detail.isEmpty ? text : '$text • $detail',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
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
    Widget? geoCheck,
    required bool canCapture,
    required String captureLabel,
    required VoidCallback onCapture,
    double? gpsLat,
    double? gpsLng,
    double? gpsAccuracy,
    String? gpsCapturedAt,
    String? photoGeoLabel,
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
                    gpsLat: gpsLat,
                    gpsLng: gpsLng,
                    gpsAccuracy: gpsAccuracy,
                    gpsCapturedAt: gpsCapturedAt,
                    photoGeoLabel: photoGeoLabel,
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
                if (geoCheck != null) ...[
                  const SizedBox(height: 4),
                  geoCheck,
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
                            gpsLat: gpsLat,
                            gpsLng: gpsLng,
                            gpsAccuracy: gpsAccuracy,
                            gpsCapturedAt: gpsCapturedAt,
                            photoGeoLabel: photoGeoLabel,
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
