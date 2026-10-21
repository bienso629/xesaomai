import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/inspection_model.dart';
import '../services/app_state.dart';
import 'camera_inspection_screen.dart';
import 'slip_capture_screen.dart';
import 'breakdown_dialog.dart';
import 'dispatch_supervisor_screen.dart';

class HomeDriverScreen extends StatelessWidget {
  final bool showAppBar;
  const HomeDriverScreen({super.key, this.showAppBar = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Khóa nhận chuyến cho đến khi Điều phối bấm "Duyệt Nhận Chuyến"
    final isLocked =
        !state.isApprovedByDispatcher || state.isVehicleLockedByBreakdown();

    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thông tin tài xế và chọn xe
          _buildDriverVehicleCard(context, state),
          const SizedBox(height: 16),

          // Mục Kiểm tra xe đầu ngày (5 ảnh)
          _buildDailyInspectionCard(context, state),
          const SizedBox(height: 16),

          // Quản lý chuyến & Mốc giờ (Đến / Bơm xong / Phiếu cân / Giao hàng)
          _buildTripMilestonesCard(context, state, isLocked),
        ],
      ),
    );

    if (!showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tài xế Sao Mai", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: "Màn hình Điều phối & Giám sát",
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DispatchSupervisorScreen()),
              );
            },
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildDriverVehicleCard(BuildContext context, AppState state) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: const Icon(Icons.person, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state.currentDriverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("Mã TX: ${state.currentDriverId} | UTC+7", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.local_shipping_outlined, color: Colors.blueGrey, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Chọn xe trực:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  height: 40,
                  child: DropdownButtonFormField<String>(
                    value: state.selectedPlate,
                    isDense: true,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.blue.shade700, width: 1.5),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: state.availableVehicles.map((plate) {
                      return DropdownMenuItem(
                        value: plate,
                        child: Text(plate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (newPlate) {
                      if (newPlate != null) {
                        VehicleType vType = VehicleType.howo;
                        if (newPlate.contains("772")) vType = VehicleType.shacman;
                        if (newPlate.contains("441")) vType = VehicleType.daewoo;
                        state.setVehicle(newPlate, vType);
                      }
                    },
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blueGrey.shade200, width: 1),
                  ),
                  child: Text(
                    state.selectedVehicleType.name.toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyInspectionCard(BuildContext context, AppState state) {
    final bool completed = state.isInspectionCompleted;
    // Xe chỉ "Đủ điều kiện chạy" khi Điều phối viên đã bấm "Duyệt Nhận Chuyến"
    final bool approved = state.isApprovedByDispatcher;
    final bool hasBreakdownLock = state.isVehicleLockedByBreakdown();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: const [
                      Icon(Icons.camera_alt, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Kiểm tra xe đầu ngày (5 ảnh)",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: approved
                        ? Colors.green.shade100
                        : (completed ? Colors.blue.shade100 : Colors.orange.shade100),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    approved
                        ? "Đủ điều kiện chạy"
                        : (completed ? "Chờ Điều phối duyệt" : "Chưa kiểm tra"),
                    style: TextStyle(
                      color: approved
                          ? Colors.green.shade800
                          : (completed ? Colors.blue.shade800 : Colors.orange.shade800),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              approved
                  ? "• Đã chụp đủ 5 ảnh (gầm trước, gầm sau, hông trái, hông phải, táp lô)\n• Số km táp lô: ${state.todayInspection?.confirmedKm.toStringAsFixed(0)} km\n• Điều phối đã Duyệt Nhận Chuyến: xe ĐỦ ĐIỀU KIỆN CHẠY"
                  : (completed
                      ? "• Đã gửi đủ 5 ảnh lên hệ thống, đang chờ Điều phối viên kiểm tra\n• Xe CHƯA đủ điều kiện chạy cho đến khi Điều phối bấm \"Duyệt Nhận Chuyến\""
                      : "Xe CHỈ ĐƯỢC NHẬN CHUYẾN khi Điều phối đã bấm \"Duyệt Nhận Chuyến\" sau khi kiểm tra bộ 5 ảnh đầu ngày."),
              style: TextStyle(fontSize: 13, color: completed ? Colors.black87 : Colors.grey.shade700),
            ),
            if (hasBreakdownLock) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.lock, color: Colors.red, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Xe đang có Báo hỏng chờ Điều phối duyệt hoặc Đưa vào xưởng. Nút Nhận chuyến bị khóa!",
                        style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: completed ? Colors.grey.shade600 : Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.camera, color: Colors.white),
                    label: Text(
                      completed ? "Chụp lại 5 ảnh" : "Bắt đầu chụp 5 ảnh",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CameraInspectionScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: const BorderSide(color: Colors.deepOrange),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  ),
                  icon: const Icon(Icons.warning_amber),
                  label: const Text("Báo hỏng"),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => const BreakdownDialog(),
                    );
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTripMilestonesCard(BuildContext context, AppState state, bool isLocked) {
    final bool approved = state.isApprovedByDispatcher;
    final trip = approved ? state.currentTrip : null;
    final bool hasAssignedOrder = approved && trip != null && trip.orderCode.trim().isNotEmpty;
    final bool stepDisabled = isLocked || !hasAssignedOrder;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Lịch Chuyến & Mốc Giờ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                if (stepDisabled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      !approved ? "CHỜ KIỂM TRA XE" : "CHỜ GẮN MÃ LỆNH",
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54),
                    ),
                  ),
              ],
            ),
            const Divider(),
            if (!hasAssignedOrder)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  !approved
                      ? "Xe chưa kiểm tra & Duyệt Nhận Chuyến nên chưa có Mã lệnh."
                      : "Xe đã duyệt — Đang chờ Điều phối viên gắn Mã lệnh cho xe.",
                  style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
                ),
              )
            else ...[
              Text("Mã đơn: ${trip.orderCode}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              Text("Điểm đến: ${trip.destinationName}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ],
            const SizedBox(height: 12),

            // Nút 1: ĐẾN ĐIỂM GIAO
            _buildMilestoneRow(
              title: "1. ĐẾN điểm giao",
              timeText: trip?.arrivedTime != null
                  ? "${trip!.arrivedTime!.hour}:${trip.arrivedTime!.minute.toString().padLeft(2, '0')} (GPS đã ghi)"
                  : "Chưa ghi nhận",
              isRecorded: trip?.arrivedTime != null,
              buttonLabel: "Bấm ĐẾN",
              isDisabled: stepDisabled || trip.arrivedTime != null,
              onPressed: () => _handleArrived(context, state),
            ),
            const SizedBox(height: 10),

            // Nút 2: BƠM XONG (Kiểm tra > 120 phút chọn nguyên nhân)
            _buildMilestoneRow(
              title: "2. BƠM XONG",
              timeText: trip?.pumpedTime != null
                  ? "${trip!.pumpedTime!.hour}:${trip.pumpedTime!.minute.toString().padLeft(2, '0')}"
                  : (trip?.arrivedTime != null ? "Đang bơm (${trip!.waitDurationMinutes} phút)" : "Chờ đến"),
              isRecorded: trip?.pumpedTime != null,
              buttonLabel: "BƠM XONG",
              isDisabled: stepDisabled || trip.arrivedTime == null || trip.pumpedTime != null,
              onPressed: () => _handlePumped(context, state),
            ),
            const SizedBox(height: 10),

            // Nút 3: GỬI PHIẾU CÂN (OCR + Tự đăng Zalo nhóm KH)
            _buildMilestoneRow(
              title: "3. Phiếu cân",
              timeText: trip?.weighSlipPhotoUrl != null
                  ? "${trip!.weighTonnage} Tấn (Đã gửi Zalo OA)"
                  : "Chưa gửi phiếu",
              isRecorded: trip?.weighSlipPhotoUrl != null,
              buttonLabel: "Gửi Phiếu Cân",
              isDisabled: stepDisabled,
              onPressed: () => SlipCaptureScreen.show(
                context,
                slipType: 'weigh',
                orderCode: trip?.orderCode ?? '',
              ),
            ),
            const SizedBox(height: 10),

            // Nút 4: GỬI PHIẾU GIAO HÀNG
            _buildMilestoneRow(
              title: "4. Phiếu giao hàng",
              timeText: trip?.deliverySlipPhotoUrl != null ? "Đã gửi Zalo KH" : "Chưa gửi phiếu",
              isRecorded: trip?.deliverySlipPhotoUrl != null,
              buttonLabel: "Gửi Phiếu GH",
              isDisabled: stepDisabled,
              onPressed: () => SlipCaptureScreen.show(
                context,
                slipType: 'delivery',
                orderCode: trip?.orderCode ?? '',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneRow({
    required String title,
    required String timeText,
    required bool isRecorded,
    required String buttonLabel,
    required bool isDisabled,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isRecorded ? Colors.green.withOpacity(0.06) : Colors.grey.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            isRecorded ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isRecorded ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(timeText, style: TextStyle(fontSize: 11, color: isRecorded ? Colors.green.shade800 : Colors.grey.shade600)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDisabled ? Colors.grey.shade400 : Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: isDisabled ? null : onPressed,
            child: Text(buttonLabel, style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleArrived(BuildContext context, AppState state) {
    // Giả lập tọa độ GPS tài xế cách điểm giao 3.5km (> 2km hỏi xác nhận)
    const mockLat = 10.7325;
    const mockLng = 106.9152;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận khoảng cách GPS", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          "Tọa độ GPS hiện tại đang cách điểm giao hơn 2.0 km (khoảng 3.5 km). Bạn có chắc chắn đã đến đúng trạm không?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Kiểm tra lại", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ElevatedButton(
            onPressed: () {
              state.recordArrival(lat: mockLat, lng: mockLng, forceConfirm: true);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Đã lưu mốc ĐẾN điểm giao thành công!")),
              );
            },
            child: const Text("Xác nhận đã đến", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handlePumped(BuildContext context, AppState state) {
    // Giả lập tình huống thời gian bơm > 120 phút bắt buộc chọn 1 trong 11 nguyên nhân chờ
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String selectedReason = AppState.waitingReasons.first;
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.hourglass_bottom, color: Colors.amber),
                  SizedBox(width: 8),
                  Text("Bơm xong (>120 phút)", style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Thời gian từ lúc ĐẾN đến BƠM XONG vượt quá 120 phút (135 phút). Vui lòng chọn nguyên nhân chờ:",
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: AppState.waitingReasons.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => selectedReason = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    state.recordPumpCompleted(lat: 10.7025, lng: 106.9452, reason: selectedReason);
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Đã ghi nhận mốc BƠM XONG và nguyên nhân chờ!")),
                    );
                  },
                  child: const Text("Xác nhận BƠM XONG", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
