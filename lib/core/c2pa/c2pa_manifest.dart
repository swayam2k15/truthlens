import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import '../../models/capture_metadata.dart';
import '../../models/proof_record.dart';
import '../crypto/key_manager.dart';

/// C2PA (Coalition for Content Provenance and Authenticity) manifest builder.
///
/// Generates C2PA-compliant Content Credentials that can be embedded in
/// or sidecar-attached to media files. This allows TruthLens proofs to
/// be verified by any C2PA-compatible tool (Adobe Content Authenticity,
/// Truepic, etc.).
///
/// Spec reference: https://c2pa.org/specifications/
class C2PAManifestBuilder {
  C2PAManifestBuilder._();
  static final C2PAManifestBuilder instance = C2PAManifestBuilder._();

  static const String _c2paVersion = '2.0';
  static const String _claimGeneratorInfo = 'TruthLens/1.0.0';

  /// Build a C2PA manifest for a proof record.
  ///
  /// The manifest contains:
  /// - Claim: assertions about the content (who, when, where, how)
  /// - Assertions: individual metadata claims
  /// - Signature: cryptographic binding of claim to content
  Future<C2PAManifest> buildManifest({
    required ProofRecord proof,
    required Uint8List mediaBytes,
  }) async {
    final claimId = 'urn:uuid:${proof.id}';

    // Build assertions
    final assertions = <C2PAAssertion>[];

    // 1. Creative work assertion (authorship)
    assertions.add(C2PAAssertion(
      label: 'stds.schema-org.CreativeWork',
      data: {
        '@context': 'https://schema.org',
        '@type': 'CreativeWork',
        'author': [
          {
            '@type': 'Person',
            'credential': [
              {
                '@type': 'DigitalDocument',
                'identifier': proof.deviceId,
              }
            ],
          }
        ],
      },
    ));

    // 2. Actions assertion (capture action)
    assertions.add(C2PAAssertion(
      label: 'c2pa.actions',
      data: {
        'actions': [
          {
            'action': 'c2pa.created',
            'when': proof.captureMetadata.captureTime.toIso8601String(),
            'softwareAgent': _claimGeneratorInfo,
            'parameters': {
              'description': 'Original capture by TruthLens app',
            },
          }
        ],
      },
    ));

    // 3. EXIF metadata assertion
    assertions.add(C2PAAssertion(
      label: 'stds.exif',
      data: _buildExifAssertion(proof.captureMetadata),
    ));

    // 4. Geolocation assertion
    if (proof.captureMetadata.latitude != null) {
      assertions.add(C2PAAssertion(
        label: 'stds.schema-org.GeoCoordinates',
        data: {
          '@context': 'https://schema.org',
          '@type': 'GeoCoordinates',
          'latitude': proof.captureMetadata.latitude,
          'longitude': proof.captureMetadata.longitude,
          'altitude': proof.captureMetadata.altitude,
        },
      ));
    }

    // 5. TruthLens custom assertion (extended proof data)
    assertions.add(C2PAAssertion(
      label: 'com.truthlens.proof',
      data: {
        'proof_id': proof.id,
        'media_hash': proof.mediaHash,
        'trust_score': proof.trustScore,
        'device_signature': proof.signature,
        'public_key': proof.publicKey,
        'timestamp_token': proof.timestampToken?.toJson(),
        'blockchain_anchors':
            proof.blockchainAnchors.map((a) => a.toJson()).toList(),
        'sensor_snapshot': {
          'accelerometer': proof.captureMetadata.accelerometer,
          'gyroscope': proof.captureMetadata.gyroscope,
          'ntp_offset_ms': proof.captureMetadata.ntpOffsetMs,
        },
      },
    ));

    // Build the claim
    final claim = C2PAClaim(
      claimId: claimId,
      dcFormat: proof.mediaType == MediaType.photo
          ? 'image/jpeg'
          : 'video/mp4',
      instanceId: 'xmp:iid:${proof.id}',
      claimGenerator: _claimGeneratorInfo,
      claimGeneratorHints: {
        'platform': 'mobile',
        'app': 'TruthLens',
        'version': '1.0.0',
      },
      assertions: assertions,
      hashMethod: 'SHA-256',
    );

    // Compute claim hash for signing
    final claimJson = jsonEncode(claim.toJson());
    final claimHash = KeyManager.sha256Hash(
      Uint8List.fromList(utf8.encode(claimJson)),
    );

    // Sign the claim
    final signature = await KeyManager.instance.sign(claimHash);
    final publicKey = await KeyManager.instance.getPublicKeyBytes();

    return C2PAManifest(
      version: _c2paVersion,
      claim: claim,
      signatureBytes: signature,
      publicKeyBytes: publicKey,
      contentHash: base64Encode(KeyManager.sha256Hash(mediaBytes)),
    );
  }

  Map<String, dynamic> _buildExifAssertion(CaptureMetadata meta) {
    return {
      'EXIF': {
        'DateTimeOriginal': meta.captureTime.toIso8601String(),
        'Make': meta.manufacturer,
        'Model': meta.deviceModel,
        if (meta.focalLength != null) 'FocalLength': meta.focalLength,
        if (meta.aperture != null) 'FNumber': meta.aperture,
        if (meta.isoSpeed != null) 'ISOSpeedRatings': meta.isoSpeed,
        if (meta.exposureTime != null) 'ExposureTime': meta.exposureTime,
        if (meta.flashUsed != null) 'Flash': meta.flashUsed,
      },
      if (meta.latitude != null)
        'GPS': {
          'GPSLatitude': meta.latitude,
          'GPSLongitude': meta.longitude,
          'GPSAltitude': meta.altitude,
        },
    };
  }
}

class C2PAClaim {
  final String claimId;
  final String dcFormat;
  final String instanceId;
  final String claimGenerator;
  final Map<String, dynamic> claimGeneratorHints;
  final List<C2PAAssertion> assertions;
  final String hashMethod;

  const C2PAClaim({
    required this.claimId,
    required this.dcFormat,
    required this.instanceId,
    required this.claimGenerator,
    required this.claimGeneratorHints,
    required this.assertions,
    required this.hashMethod,
  });

  Map<String, dynamic> toJson() => {
        'dc:format': dcFormat,
        'instanceID': instanceId,
        'claim_generator': claimGenerator,
        'claim_generator_hints': claimGeneratorHints,
        'assertions': assertions.map((a) => a.toJson()).toList(),
        'alg': 'EdDSA',
        'hash_method': hashMethod,
      };
}

class C2PAAssertion {
  final String label;
  final Map<String, dynamic> data;

  const C2PAAssertion({required this.label, required this.data});

  Map<String, dynamic> toJson() => {
        'label': label,
        'data': data,
      };
}

class C2PAManifest {
  final String version;
  final C2PAClaim claim;
  final Uint8List signatureBytes;
  final Uint8List publicKeyBytes;
  final String contentHash;

  const C2PAManifest({
    required this.version,
    required this.claim,
    required this.signatureBytes,
    required this.publicKeyBytes,
    required this.contentHash,
  });

  Map<String, dynamic> toJson() => {
        'c2pa_version': version,
        'claim': claim.toJson(),
        'signature': base64Encode(signatureBytes),
        'public_key': base64Encode(publicKeyBytes),
        'content_hash': contentHash,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
