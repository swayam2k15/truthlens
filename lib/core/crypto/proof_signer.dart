import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'key_manager.dart';
import 'timestamp_authority.dart';
import '../../models/capture_metadata.dart';
import '../../models/proof_record.dart';

/// Orchestrates the full proof-of-life signing pipeline.
///
/// Pipeline:
/// 1. Hash the raw media bytes (SHA-256)
/// 2. Collect device/sensor metadata
/// 3. Create a canonical proof payload combining hash + metadata
/// 4. Sign the payload with the device's Ed25519 private key
/// 5. Request an RFC 3161 trusted timestamp for the signed hash
/// 6. Package everything into a verifiable [ProofRecord]
class ProofSigner {
  ProofSigner._();
  static final ProofSigner instance = ProofSigner._();

  final _keyManager = KeyManager.instance;
  final _tsa = TimestampAuthority.instance;

  /// Create a complete, signed proof for captured media.
  Future<ProofRecord> createProof({
    required Uint8List mediaBytes,
    required CaptureMetadata metadata,
    required MediaType mediaType,
  }) async {
    // Step 1: Hash the raw media
    final mediaHash = KeyManager.sha256Hash(mediaBytes);
    final contentId = KeyManager.contentId(mediaBytes);

    // Step 2: Build the canonical proof payload
    final payload = _buildCanonicalPayload(
      mediaHash: mediaHash,
      metadata: metadata,
      contentId: contentId,
    );
    final payloadBytes = Uint8List.fromList(utf8.encode(payload));

    // Step 3: Sign the payload
    final signature = await _keyManager.sign(payloadBytes);
    final publicKey = await _keyManager.getPublicKeyBytes();

    // Step 4: Request RFC 3161 trusted timestamp
    final payloadHash = KeyManager.sha256Hash(payloadBytes);
    final timestampToken = await _tsa.requestTimestamp(payloadHash);

    // Step 5: Package into ProofRecord
    return ProofRecord(
      id: contentId,
      mediaHash: base64Encode(mediaHash),
      mediaType: mediaType,
      captureMetadata: metadata,
      signature: base64Encode(signature),
      publicKey: base64Encode(publicKey),
      deviceId: _keyManager.deviceId,
      timestampToken: timestampToken,
      canonicalPayload: payload,
      createdAt: DateTime.now().toUtc(),
      verificationStatus: VerificationStatus.signed,
      blockchainAnchors: [],
    );
  }

  /// Build a deterministic, canonical JSON payload for signing.
  ///
  /// The payload is sorted alphabetically by key to ensure
  /// the same data always produces the same bytes for signing.
  String _buildCanonicalPayload({
    required Uint8List mediaHash,
    required CaptureMetadata metadata,
    required String contentId,
  }) {
    final payload = <String, dynamic>{
      'content_id': contentId,
      'capture_time': metadata.captureTime.toIso8601String(),
      'device_id': _keyManager.deviceId,
      'latitude': metadata.latitude,
      'longitude': metadata.longitude,
      'altitude': metadata.altitude,
      'gps_accuracy': metadata.gpsAccuracy,
      'device_model': metadata.deviceModel,
      'os_version': metadata.osVersion,
      'app_version': metadata.appVersion,
      'media_hash_sha256': base64Encode(mediaHash),
      'sensor_data': {
        'accelerometer': metadata.accelerometer,
        'gyroscope': metadata.gyroscope,
        'magnetometer': metadata.magnetometer,
        'light_level': metadata.lightLevel,
        'battery_level': metadata.batteryLevel,
      },
      'network_info': {
        'ip_hash': metadata.networkIpHash,
        'connection_type': metadata.connectionType,
      },
      'ntp_offset_ms': metadata.ntpOffsetMs,
      'truthlens_version': '1.0.0',
      'proof_schema_version': 1,
    };

    // Sort keys recursively for canonical form
    return _canonicalJson(payload);
  }

  /// Recursively sort JSON keys for deterministic serialization.
  String _canonicalJson(dynamic value) {
    if (value is Map) {
      final sorted = Map.fromEntries(
        value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      final entries = sorted.entries
          .map((e) => '"${e.key}":${_canonicalJson(e.value)}')
          .join(',');
      return '{$entries}';
    } else if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    } else if (value is String) {
      return jsonEncode(value);
    } else if (value == null) {
      return 'null';
    } else {
      return value.toString();
    }
  }

  /// Verify an existing proof record's signature integrity.
  Future<bool> verifyProof(ProofRecord proof) async {
    final payloadBytes = Uint8List.fromList(utf8.encode(proof.canonicalPayload));
    final signature = base64Decode(proof.signature);
    final publicKey = base64Decode(proof.publicKey);

    return _keyManager.verify(payloadBytes, signature, publicKey);
  }
}
