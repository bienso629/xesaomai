enum TripStatus {
  assigned,
  drivingToPickup,
  arrived,
  pumping,
  pumped,
  completed,
}

class TripMilestone {
  int? orderId;
  final String orderCode;
  bool hasBreakdown;
  String? breakdownReason;
  String? breakdownPhotoUrl;
  final String vehiclePlate;
  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  
  DateTime? arrivedTime;
  double? arrivedLat;
  double? arrivedLng;
  String? arrivedSource; // 'app', 'GPS', 'tay'
  
  DateTime? pumpedTime;
  double? pumpedLat;
  double? pumpedLng;
  String? pumpedSource;
  String? waitingReason; // 1 trong 11 muc khi > 120 phut

  String? weighSlipPhotoUrl;
  double? weighTonnage;
  DateTime? weighTime;
  String? weighOrderStatus; // 'cho gui Zalo', 'da gui Zalo'

  String? deliverySlipPhotoUrl;
  DateTime? deliveryTime;
  String? deliveryZaloStatus;

  TripMilestone({
    this.orderId,
    required this.orderCode,
    this.hasBreakdown = false,
    this.breakdownReason,
    this.breakdownPhotoUrl,
    required this.vehiclePlate,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    this.arrivedTime,
    this.arrivedLat,
    this.arrivedLng,
    this.arrivedSource,
    this.pumpedTime,
    this.pumpedLat,
    this.pumpedLng,
    this.pumpedSource,
    this.waitingReason,
    this.weighSlipPhotoUrl,
    this.weighTonnage,
    this.weighTime,
    this.weighOrderStatus,
    this.deliverySlipPhotoUrl,
    this.deliveryTime,
    this.deliveryZaloStatus,
  });

  int get waitDurationMinutes {
    if (arrivedTime != null && pumpedTime != null) {
      return pumpedTime!.difference(arrivedTime!).inMinutes;
    } else if (arrivedTime != null) {
      return DateTime.now().difference(arrivedTime!).inMinutes;
    }
    return 0;
  }
}
