enum VehicleType {
  howo,
  shacman,
  daewoo,
}

enum InspectionStep {
  frontUndercarriage, // Gầm trước
  rearUndercarriage,  // Gầm sau
  leftFlank,          // Hông trái
  rightFlank,         // Hông phải
  dashboard,          // Táp lô
}

class PhotoMetadata {
  final String stepName;
  final String imagePath;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double accuracy;
  final String vehiclePlate;
  final String driverId;
  final String deviceId;
  final bool hasFlash;
  final bool flagAnomaly;
  final String? anomalyReason;

  PhotoMetadata({
    required this.stepName,
    required this.imagePath,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.vehiclePlate,
    required this.driverId,
    required this.deviceId,
    this.hasFlash = false,
    this.flagAnomaly = false,
    this.anomalyReason,
  });

  Map<String, dynamic> toJson() => {
        'stepName': stepName,
        'imagePath': imagePath,
        'timestamp': timestamp.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'vehiclePlate': vehiclePlate,
        'driverId': driverId,
        'deviceId': deviceId,
        'hasFlash': hasFlash,
        'flagAnomaly': flagAnomaly,
        'anomalyReason': anomalyReason,
      };
}

class DailyInspectionRecord {
  final String id;
  final DateTime date;
  final String vehiclePlate;
  final String driverId;
  final VehicleType vehicleType;
  final List<PhotoMetadata> photos;
  final double ocrKm;
  final double confirmedKm;
  final bool isKmFlagged; // Lệch > 20 km
  final bool isCompleted;
  final String flagStatus; // 'None', 'Theo doi', 'Dua vao xuong', 'Bo qua'
  final String? flagHandler;

  DailyInspectionRecord({
    required this.id,
    required this.date,
    required this.vehiclePlate,
    required this.driverId,
    required this.vehicleType,
    required this.photos,
    required this.ocrKm,
    required this.confirmedKm,
    this.isKmFlagged = false,
    this.isCompleted = false,
    this.flagStatus = 'None',
    this.flagHandler,
  });
}
