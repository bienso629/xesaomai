import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/inspection_model.dart';
import '../models/reminder_model.dart';
import '../services/app_state.dart';
import 'camera_inspection_screen.dart';
import 'weigh_slip_dialog.dart';
import 'breakdown_dialog.dart';
import 'dispatch_supervisor_screen.dart';

class HomeDriverScreen extends StatelessWidget {
  const HomeDriverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isLocked = !state.isInspectionCompleted || state.isVehicleLockedByBreakdown();

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
      body: SingleChildScrollView(
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
            const SizedBox(height: 16),

            // Khu vực mô phỏng nhắc nhở nền (Background Check Simulator)
            _buildSimulationActionsCard(context, state),
          ],
        ),
      ),
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
                const Icon(Icons.local_shipping, color: Colors.blueGrey),
                const SizedBox(width: 8),
                const Text("Chọn xe trực:", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: state.selectedPlate,
                  items: state.availableVehicles.map((plate) {
                    return DropdownMenuItem(
                      value: plate,
                      child: Text(plate, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                const Spacer(),
                Chip(
                  label: Text(
                    state.selectedVehicleType.name.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                  backgroundColor: Colors.grey.shade400,
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDailyInspectionCard(BuildContext context, AppState state) {
    final bool completed = state.isInspectionCompleted;
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
                    color: completed ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    completed ? "Đã kiểm tra" : "Chưa kiểm tra",
                    style: TextStyle(
                      color: completed ? Colors.green.shade800 : Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              completed
                  ? "• Đã chụp đủ 5 ảnh (gầm trước, gầm sau, hông trái, hông phải, táp lô)\n• Số km táp lô: ${state.todayInspection?.confirmedKm.toStringAsFixed(0)} km\n• Trạng thái cờ: ${state.todayInspection?.flagStatus}"
                  : "Xe CHỈ ĐƯỢC NHẬN CHUYẾN khi đã có đủ bộ 5 ảnh kiểm tra đầu ngày.",
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
    final trip = state.currentTrip;
    if (trip == null) return const SizedBox.shrink();

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
                if (isLocked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(6)),
                    child: const Text("ĐANG KHÓA", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                  ),
              ],
            ),
            const Divider(),
            Text("Mã đơn: ${trip.orderCode}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            Text("Điểm đến: ${trip.destinationName}", style: const TextStyle(fontSize: 13, color: Colors.black87)),
            const SizedBox(height: 12),

            // Nút 1: ĐẾN ĐIỂM GIAO
            _buildMilestoneRow(
              title: "1. ĐẾN điểm giao",
              timeText: trip.arrivedTime != null
                  ? "${trip.arrivedTime!.hour}:${trip.arrivedTime!.minute.toString().padLeft(2, '0')} (GPS đã ghi)"
                  : "Chưa ghi nhận",
              isRecorded: trip.arrivedTime != null,
              buttonLabel: "Bấm ĐẾN",
              isDisabled: isLocked || trip.arrivedTime != null,
              onPressed: () => _handleArrived(context, state),
            ),
            const SizedBox(height: 10),

            // Nút 2: BƠM XONG (Kiểm tra > 120 phút chọn nguyên nhân)
            _buildMilestoneRow(
              title: "2. BƠM XONG",
              timeText: trip.pumpedTime != null
                  ? "${trip.pumpedTime!.hour}:${trip.pumpedTime!.minute.toString().padLeft(2, '0')}"
                  : (trip.arrivedTime != null ? "Đang bơm (${trip.waitDurationMinutes} phút)" : "Chờ đến"),
              isRecorded: trip.pumpedTime != null,
              buttonLabel: "BƠM XONG",
              isDisabled: isLocked || trip.arrivedTime == null || trip.pumpedTime != null,
              onPressed: () => _handlePumped(context, state),
            ),
            const SizedBox(height: 10),

            // Nút 3: GỬI PHIẾU CÂN (OCR + Tự đăng Zalo nhóm KH)
            _buildMilestoneRow(
              title: "3. Phiếu cân",
              timeText: trip.weighSlipPhotoUrl != null
                  ? "${trip.weighTonnage} Tấn (Đã gửi Zalo OA)"
                  : "Chưa gửi phiếu",
              isRecorded: trip.weighSlipPhotoUrl != null,
              buttonLabel: "Gửi Phiếu Cân",
              isDisabled: isLocked,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const WeighSlipDialog(),
                );
              },
            ),
            const SizedBox(height: 10),

            // Nút 4: GỬI PHIẾU GIAO HÀNG
            _buildMilestoneRow(
              title: "4. Phiếu giao hàng",
              timeText: trip.deliverySlipPhotoUrl != null ? "Đã gửi Zalo KH" : "Chưa gửi phiếu",
              isRecorded: trip.deliverySlipPhotoUrl != null,
              buttonLabel: "Gửi Phiếu GH",
              isDisabled: isLocked,
              onPressed: () {
                state.recordDeliverySlip(photoUrl: "storage/slips/pgh_${DateTime.now().millisecondsSinceEpoch}.jpg");
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Colors.green,
                    content: Text("Đã chụp và tự động gửi Phiếu giao hàng vào nhóm Zalo OA khách hàng!"),
                  ),
                );
              },
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
        title: const Text("Xác nhận khoảng cách GPS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          "Tọa độ GPS hiện tại đang cách điểm giao hơn 2.0 km (khoảng 3.5 km). Bạn có chắc chắn đã đến đúng trạm không?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Kiểm tra lại")),
          ElevatedButton(
            onPressed: () {
              state.recordArrival(lat: mockLat, lng: mockLng, forceConfirm: true);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Đã lưu mốc ĐẾN điểm giao thành công!")),
              );
            },
            child: const Text("Xác nhận đã đến"),
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
                  Text("Bơm xong (>120 phút)", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Thời gian từ lúc ĐẾN đến BƠM XONG vượt quá 120 phút (135 phút). Vui lòng chọn nguyên nhân chờ:",
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: AppState.waitingReasons.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r, style: const TextStyle(fontSize: 12)),
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
                  child: const Text("Xác nhận BƠM XONG"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSimulationActionsCard(BuildContext context, AppState state) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: Colors.grey.shade400, width: 1)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.notifications_active, color: Colors.teal),
                SizedBox(width: 8),
                Text("Mô phỏng Kịch bản Nhắc nhở nền (Tự động)",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text("Chạy >500m chưa chụp", style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    state.triggerReminder(
                      ReminderType.movingWithoutInspection,
                      "CẢNH BÁO: Xe di chuyển > 500m mà chưa chụp đủ 5 ảnh! Đã ghi 1 lần vi phạm và báo Điều phối.",
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.redAccent,
                        content: Text("Nhắc nhở: Xe di chuyển chưa kiểm tra! Đã ghi vi phạm."),
                      ),
                    );
                  },
                ),
                ActionChip(
                  label: const Text("Dừng 15p chưa bấm ĐẾN", style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    state.triggerReminder(
                      ReminderType.arrivedZoneNotConfirmed,
                      "Nhắc nhở: Xe đã dừng ở trạm 15 phút, vui lòng bấm nút ĐẾN điểm giao.",
                    );
                  },
                ),
                ActionChip(
                  label: const Text("Đến >120p chưa bơm xong", style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    state.triggerReminder(
                      ReminderType.pumpingOverdue,
                      "Nhắc nhở: Đã ĐẾN quá 120 phút chưa bấm BƠM XONG. Vui lòng cập nhật lý do.",
                    );
                  },
                ),
                ActionChip(
                  label: const Text("Tổng kết hết ca 19h / 07h", style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    state.triggerReminder(
                      ReminderType.shiftEndReminder,
                      "Gộp mọi khoản còn thiếu cuối ca thành thông báo gửi Điều phối giao ca.",
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
}
