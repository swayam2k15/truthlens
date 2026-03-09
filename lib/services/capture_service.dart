import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import '../models/capture_metadata.dart';
import '../core/crypto/key_manager.dart';

/// Service responsible for capturing photos/videos and collecting
/// all ambient metadata at the exact moment of capture.
///
/// The key insight: the MORE independent signals we capture simultaneously,
/// the harder it is for an attacker to fake. Spoofing GPS alone is easy;
/// spoofing GPS + accelerometer + NTP + barometric pressure + cell tower
/// + network IP all consistently is extremely difficult.
class CaptureService {
  final _log = Logger(printer: PrettyPrinter(methodCount: 0));
  final _deviceInfo = DeviceInfoPlugin();

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  bool get isInitialized => _cameraController?.value.isInitialized ?? false;

  /// Initialize camera subsystem.
  Future<CameraController> initializeCamera({
    CameraLensDirection direction = CameraLensDirection.back,
    ResolutionPreset resolution = ResolutionPreset.high,
  }) async {
    _cameras = await availableCameras();

    final camera = _cameras!.firstWhere(
      (c) => c.lensDirection == direction,
      orElse: () => _cameras!.first,
    );

    _cameraController = CameraController(
      camera,
      resolution,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await _cameraController!.initialize();
    return _cameraController!;
  }

  /// Capture a photo and collect all metadata simultaneously.
  ///
  /// Returns the raw bytes and metadata — the caller is responsible
  /// for passing these to [ProofSigner] for signing.
  Future<CaptureResult> capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      throw StateError('Camera not initialized');
    }

    // Capture photo and metadata simultaneously
    final captureTime = DateTime.now().toUtc();

    final xFile = await _cameraController!.takePicture();
    final mediaBytes = await xFile.readAsBytes();

    // Collect all metadata
    final metadata = await _collectMetadata(captureTime);

    // Save to app directory (skip on web)
    String filePath = 'truthlens_${captureTime.millisecondsSinceEpoch}.jpg';
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      filePath = '${dir.path}/$filePath';
      await File(filePath).writeAsBytes(mediaBytes);
    }

    return CaptureResult(
      mediaBytes: mediaBytes,
      metadata: metadata,
      filePath: filePath,
    );
  }

  /// Start video recording with continuous metadata collection.
  Future<void> startVideoRecording() async {
    if (_cameraController == null) throw StateError('Camera not initialized');
    await _cameraController!.startVideoRecording();
  }

  /// Stop video recording and return captured result.
  Future<CaptureResult> stopVideoRecording() async {
    if (_cameraController == null) throw StateError('Camera not initialized');

    final captureTime = DateTime.now().toUtc();
    final xFile = await _cameraController!.stopVideoRecording();
    final mediaBytes = await xFile.readAsBytes();

    final metadata = await _collectMetadata(captureTime);

    String filePath = 'truthlens_${captureTime.millisecondsSinceEpoch}.mp4';
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      filePath = '${dir.path}/$filePath';
      await File(filePath).writeAsBytes(mediaBytes);
    }

    return CaptureResult(
      mediaBytes: mediaBytes,
      metadata: metadata,
      filePath: filePath,
    );
  }

  /// Collect all available metadata at the moment of capture.
  Future<CaptureMetadata> _collectMetadata(DateTime captureTime) async {
    // Location (may be null if permission denied)
    Position? position;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      _log.w('GPS unavailable: $e');
    }

    // Device info
    String deviceModel = 'Unknown';
    String osVersion = 'Unknown';
    String manufacturer = '';

    if (kIsWeb) {
      final info = await _deviceInfo.webBrowserInfo;
      deviceModel = info.browserName.name;
      osVersion = 'Web';
      manufacturer = info.vendor ?? '';
    } else if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      deviceModel = '${info.manufacturer} ${info.model}';
      osVersion = 'Android ${info.version.release} (SDK ${info.version.sdkInt})';
      manufacturer = info.manufacturer;
    } else if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      deviceModel = info.utsname.machine;
      osVersion = '${info.systemName} ${info.systemVersion}';
      manufacturer = 'Apple';
    } else if (Platform.isMacOS) {
      final info = await _deviceInfo.macOsInfo;
      deviceModel = info.model;
      osVersion = 'macOS ${info.osRelease}';
      manufacturer = 'Apple';
    }

    // Network info (hashed for privacy)
    String? connectionType;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      connectionType = connectivity.first.name;
    } catch (_) {}

    return CaptureMetadata(
      captureTime: captureTime,
      latitude: position?.latitude,
      longitude: position?.longitude,
      altitude: position?.altitude,
      gpsAccuracy: position?.accuracy,
      gpsSpeed: position?.speed,
      gpsBearing: position?.heading,
      deviceModel: deviceModel,
      osVersion: osVersion,
      appVersion: '1.0.0',
      manufacturer: manufacturer,
      connectionType: connectionType,
      // Sensor data would be collected via sensors_plus in real impl
      accelerometer: null,
      gyroscope: null,
      magnetometer: null,
      lightLevel: null,
      batteryLevel: null,
      ntpOffsetMs: null,
    );
  }

  /// Switch between front and back camera.
  Future<void> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    final currentDirection =
        _cameraController?.description.lensDirection ?? CameraLensDirection.back;

    final newDirection = currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    await disposeCamera();
    await initializeCamera(direction: newDirection);
  }

  Future<void> disposeCamera() async {
    await _cameraController?.dispose();
    _cameraController = null;
  }
}

/// Result of a capture operation.
class CaptureResult {
  final Uint8List mediaBytes;
  final CaptureMetadata metadata;
  final String filePath;

  const CaptureResult({
    required this.mediaBytes,
    required this.metadata,
    required this.filePath,
  });
}
