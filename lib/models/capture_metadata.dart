/// Metadata collected at the moment of capture.
///
/// Includes GPS, device sensors, network info, and NTP time offset —
/// all factors that make spoofing exponentially harder because an attacker
/// would need to fake every dimension simultaneously.
class CaptureMetadata {
  final DateTime captureTime;

  // Location
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? gpsAccuracy;
  final double? gpsSpeed;
  final double? gpsBearing;

  // Device Info
  final String deviceModel;
  final String osVersion;
  final String appVersion;
  final String manufacturer;

  // Sensor snapshots at capture instant
  final List<double>? accelerometer; // [x, y, z]
  final List<double>? gyroscope;     // [x, y, z]
  final List<double>? magnetometer;  // [x, y, z]
  final double? lightLevel;
  final double? batteryLevel;
  final double? pressure;           // barometric pressure

  // Network context (hashed for privacy)
  final String? networkIpHash;
  final String? connectionType;     // wifi, cellular, none
  final String? cellTowerId;        // hashed

  // Time verification
  final int? ntpOffsetMs;           // Offset from NTP server time
  final String? ntpServer;

  // Camera metadata
  final double? focalLength;
  final double? aperture;
  final int? isoSpeed;
  final double? exposureTime;
  final bool? flashUsed;
  final String? lensModel;

  const CaptureMetadata({
    required this.captureTime,
    this.latitude,
    this.longitude,
    this.altitude,
    this.gpsAccuracy,
    this.gpsSpeed,
    this.gpsBearing,
    required this.deviceModel,
    required this.osVersion,
    required this.appVersion,
    this.manufacturer = '',
    this.accelerometer,
    this.gyroscope,
    this.magnetometer,
    this.lightLevel,
    this.batteryLevel,
    this.pressure,
    this.networkIpHash,
    this.connectionType,
    this.cellTowerId,
    this.ntpOffsetMs,
    this.ntpServer,
    this.focalLength,
    this.aperture,
    this.isoSpeed,
    this.exposureTime,
    this.flashUsed,
    this.lensModel,
  });

  Map<String, dynamic> toJson() => {
        'capture_time': captureTime.toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'gps_accuracy': gpsAccuracy,
        'gps_speed': gpsSpeed,
        'gps_bearing': gpsBearing,
        'device_model': deviceModel,
        'os_version': osVersion,
        'app_version': appVersion,
        'manufacturer': manufacturer,
        'accelerometer': accelerometer,
        'gyroscope': gyroscope,
        'magnetometer': magnetometer,
        'light_level': lightLevel,
        'battery_level': batteryLevel,
        'pressure': pressure,
        'network_ip_hash': networkIpHash,
        'connection_type': connectionType,
        'cell_tower_id': cellTowerId,
        'ntp_offset_ms': ntpOffsetMs,
        'ntp_server': ntpServer,
        'focal_length': focalLength,
        'aperture': aperture,
        'iso_speed': isoSpeed,
        'exposure_time': exposureTime,
        'flash_used': flashUsed,
        'lens_model': lensModel,
      };

  factory CaptureMetadata.fromJson(Map<String, dynamic> json) {
    return CaptureMetadata(
      captureTime: DateTime.parse(json['capture_time'] as String),
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
      altitude: json['altitude'] as double?,
      gpsAccuracy: json['gps_accuracy'] as double?,
      gpsSpeed: json['gps_speed'] as double?,
      gpsBearing: json['gps_bearing'] as double?,
      deviceModel: json['device_model'] as String,
      osVersion: json['os_version'] as String,
      appVersion: json['app_version'] as String,
      manufacturer: json['manufacturer'] as String? ?? '',
      accelerometer: (json['accelerometer'] as List?)?.cast<double>(),
      gyroscope: (json['gyroscope'] as List?)?.cast<double>(),
      magnetometer: (json['magnetometer'] as List?)?.cast<double>(),
      lightLevel: json['light_level'] as double?,
      batteryLevel: json['battery_level'] as double?,
      pressure: json['pressure'] as double?,
      networkIpHash: json['network_ip_hash'] as String?,
      connectionType: json['connection_type'] as String?,
      cellTowerId: json['cell_tower_id'] as String?,
      ntpOffsetMs: json['ntp_offset_ms'] as int?,
      ntpServer: json['ntp_server'] as String?,
      focalLength: json['focal_length'] as double?,
      aperture: json['aperture'] as double?,
      isoSpeed: json['iso_speed'] as int?,
      exposureTime: json['exposure_time'] as double?,
      flashUsed: json['flash_used'] as bool?,
      lensModel: json['lens_model'] as String?,
    );
  }
}
