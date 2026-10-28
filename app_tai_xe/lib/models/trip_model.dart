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
  
  // Ảnh Phiếu cân (bước 2/4)
  // Ảnh Trước bơm (bước 1/4) do Tài xế chụp (kèm GPS)
  String? pumpBeforePhotoUrl;

  String? weighSlipPhotoUrl;
  double? weighTonnage;
  DateTime? weighTime;
  String? weighOrderStatus; // 'cho gui Zalo', 'da gui Zalo'

  // Ảnh ĐẾN ĐIỂM GIAO (Tài xế chụp kèm GPS, bước 3 trong luồng mới)
  String? arrivalPhotoUrl;
  DateTime? arrivalTime;

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
    this.weighSlipPhotoUrl,
    this.weighTonnage,
    this.weighTime,
    this.weighOrderStatus,
    this.arrivalPhotoUrl,
    this.arrivalTime,
    this.deliverySlipPhotoUrl,
    this.deliveryTime,
    this.deliveryZaloStatus,
  });

}
