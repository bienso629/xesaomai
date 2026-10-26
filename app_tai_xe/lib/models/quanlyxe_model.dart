class QuanLyXeInfo {
  final int id;
  final String plate;
  final String actualPlate;
  final String vehicleTypeName;
  final String? brandName;

  QuanLyXeInfo({
    required this.id,
    required this.plate,
    required this.actualPlate,
    required this.vehicleTypeName,
    this.brandName,
  });

  factory QuanLyXeInfo.fromJson(Map<String, dynamic> json) {
    return QuanLyXeInfo(
      id: json['Id'] as int? ?? 0,
      plate: json['Plate'] as String? ?? '',
      actualPlate: json['ActualPlate'] as String? ?? '',
      vehicleTypeName: json['VehicleTypeName'] as String? ?? '',
      brandName: json['BrandName'] as String?,
    );
  }
}

class QuanLyXeStatus {
  final int id;
  final String plate;
  final double latitude;
  final double longitude;
  final double speed;
  final String driverName;
  final String address;
  final bool isAccOn;
  final int odoKm;
  final DateTime? gpsTime;
  final double heading;
  final int status;
  final int satellite;
  final String gpsProvider;
  final String? stateLabel;

  QuanLyXeStatus({
    required this.id,
    required this.plate,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.driverName,
    required this.address,
    required this.isAccOn,
    required this.odoKm,
    this.gpsTime,
    this.heading = 0.0,
    this.status = 0,
    this.satellite = 0,
    this.gpsProvider = 'vietmap',
    this.stateLabel,
  });

  String get providerDisplayName {
    final p = gpsProvider.toLowerCase();
    if (p == 'binhanh') return 'Bình Anh';
    if (p == 'vietmap') return 'Vietmap';
    return gpsProvider.toUpperCase();
  }

  factory QuanLyXeStatus.fromJson(Map<String, dynamic> json) {
    final double lat = (json['Y'] as num?)?.toDouble() ?? 0.0;
    final double lng = (json['X'] as num?)?.toDouble() ?? 0.0;
    final double spd = (json['Speed'] as num?)?.toDouble() ?? 0.0;
    final int odo = (json['LastOdoMile'] as num?)?.toInt() ?? 0;
    final double hdg = (json['Heading'] as num?)?.toDouble() ?? 0.0;
    final int st = (json['Status'] as num?)?.toInt() ?? 0;
    final int sat = (json['Satellite'] as num?)?.toInt() ?? 0;
    DateTime? time;
    if (json['GpsTime'] != null) {
      time = DateTime.tryParse(json['GpsTime'].toString());
    }

    return QuanLyXeStatus(
      id: json['Id'] as int? ?? 0,
      plate: json['Plate'] as String? ?? '',
      latitude: lat,
      longitude: lng,
      speed: spd,
      driverName: json['Driver'] as String? ?? 'Chưa gắn thẻ',
      address: json['Address'] as String? ?? '',
      isAccOn: json['IsAccOn'] as bool? ?? false,
      odoKm: odo,
      gpsTime: time,
      heading: hdg,
      status: st,
      satellite: sat,
      gpsProvider: (json['GpsProvider'] ?? json['gps_provider'] ?? 'vietmap').toString(),
      stateLabel: json['StateLabel'] as String?,
    );
  }
}
