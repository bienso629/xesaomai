enum BreakdownCategory {
  tire,       // Lốp
  oilLeak,    // Rò dầu
  leafSpring, // Nhíp
  tank,       // Bồn
  electrical, // Điện
  other,      // Khác
}

extension BreakdownCategoryExt on BreakdownCategory {
  String get displayName {
    switch (this) {
      case BreakdownCategory.tire:
        return 'Lốp xe';
      case BreakdownCategory.oilLeak:
        return 'Rò rỉ dầu mỡ';
      case BreakdownCategory.leafSpring:
        return 'Hệ thống nhíp';
      case BreakdownCategory.tank:
        return 'Bồn chứa / van xả';
      case BreakdownCategory.electrical:
        return 'Hệ thống điện / đèn';
      case BreakdownCategory.other:
        return 'Hạng mục khác';
    }
  }
}

class BreakdownReport {
  final String id;
  final DateTime timestamp;
  final String vehiclePlate;
  final String driverId;
  final BreakdownCategory category;
  final String photoPath;
  final String description;
  String decision; // 'cho_chay', 'vao_xuong', 'cho_duyet'
  String? decisionBy;
  DateTime? decisionTime;

  BreakdownReport({
    required this.id,
    required this.timestamp,
    required this.vehiclePlate,
    required this.driverId,
    required this.category,
    required this.photoPath,
    required this.description,
    this.decision = 'cho_duyet',
    this.decisionBy,
    this.decisionTime,
  });
}
