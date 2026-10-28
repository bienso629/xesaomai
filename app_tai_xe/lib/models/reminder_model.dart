enum ReminderType {
  movingWithoutInspection, // Di chuyển > 500m chưa kiểm tra
  arrivedZoneNotConfirmed, // Dừng vùng giao 15p chưa bấm ĐẾN
  weighSlipMissing,        // 60p sau giờ cân chưa gửi phiếu
  shiftEndReminder,        // Hết ca 19h / 07h
  dayEndSummary,           // Hết ngày 23h30
  unresponsiveDriver,      // Không phản hồi sau 2 lần
}

class ReminderRecord {
  final String id;
  final ReminderType type;
  final String driverId;
  final String vehiclePlate;
  final int attemptCount;
  final DateTime sentTime;
  DateTime? responseTime;
  final String message;

  ReminderRecord({
    required this.id,
    required this.type,
    required this.driverId,
    required this.vehiclePlate,
    required this.attemptCount,
    required this.sentTime,
    this.responseTime,
    required this.message,
  });
}
