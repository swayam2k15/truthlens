import 'capture_metadata.dart';
import '../core/crypto/timestamp_authority.dart';

enum MediaType { photo, video }

enum VerificationStatus {
  /// Media has been captured and signed locally
  signed,

  /// RFC 3161 timestamp obtained from TSA
  timestamped,

  /// Hash anchored to at least one blockchain
  anchored,

  /// Full C2PA manifest attached
  c2paCertified,

  /// Independently verified by a third party
  thirdPartyVerified,
}

/// A blockchain anchor record.
class BlockchainAnchor {
  final String chain;         // e.g., "ethereum", "polygon", "solana"
  final String transactionHash;
  final int? blockNumber;
  final DateTime anchoredAt;
  final String? explorerUrl;

  const BlockchainAnchor({
    required this.chain,
    required this.transactionHash,
    this.blockNumber,
    required this.anchoredAt,
    this.explorerUrl,
  });

  Map<String, dynamic> toJson() => {
        'chain': chain,
        'transaction_hash': transactionHash,
        'block_number': blockNumber,
        'anchored_at': anchoredAt.toIso8601String(),
        'explorer_url': explorerUrl,
      };

  factory BlockchainAnchor.fromJson(Map<String, dynamic> json) {
    return BlockchainAnchor(
      chain: json['chain'] as String,
      transactionHash: json['transaction_hash'] as String,
      blockNumber: json['block_number'] as int?,
      anchoredAt: DateTime.parse(json['anchored_at'] as String),
      explorerUrl: json['explorer_url'] as String?,
    );
  }
}

/// Complete proof-of-life record for a captured media item.
///
/// This is the central data structure of TruthLens. It packages:
/// - The content hash (proving what was captured)
/// - Device/sensor metadata (proving where/how it was captured)
/// - Ed25519 signature (proving who captured it)
/// - RFC 3161 timestamp (proving when it was captured)
/// - Blockchain anchors (immutable public proof)
/// - C2PA manifest reference (industry-standard interoperability)
class ProofRecord {
  final String id;
  final String mediaHash;
  final MediaType mediaType;
  final CaptureMetadata captureMetadata;
  final String signature;
  final String publicKey;
  final String deviceId;
  final TimestampToken? timestampToken;
  final String canonicalPayload;
  final DateTime createdAt;
  final VerificationStatus verificationStatus;
  final List<BlockchainAnchor> blockchainAnchors;
  final String? c2paManifestRef;
  final String? mediaFilePath;
  final String? thumbnailPath;

  const ProofRecord({
    required this.id,
    required this.mediaHash,
    required this.mediaType,
    required this.captureMetadata,
    required this.signature,
    required this.publicKey,
    required this.deviceId,
    this.timestampToken,
    required this.canonicalPayload,
    required this.createdAt,
    required this.verificationStatus,
    required this.blockchainAnchors,
    this.c2paManifestRef,
    this.mediaFilePath,
    this.thumbnailPath,
  });

  /// Trust score from 0-100 based on verification layers completed.
  int get trustScore {
    int score = 0;
    score += 20; // Base: locally signed
    if (timestampToken != null) {
      score += timestampToken!.source == TimestampSource.rfc3161 ? 25 : 10;
    }
    if (blockchainAnchors.isNotEmpty) score += 25;
    if (c2paManifestRef != null) score += 15;
    if (captureMetadata.latitude != null) score += 10;
    if (captureMetadata.ntpOffsetMs != null) score += 5;
    return score.clamp(0, 100);
  }

  /// Human-readable trust level.
  String get trustLevel {
    final s = trustScore;
    if (s >= 90) return 'Maximum';
    if (s >= 70) return 'High';
    if (s >= 45) return 'Moderate';
    return 'Basic';
  }

  ProofRecord copyWith({
    VerificationStatus? verificationStatus,
    List<BlockchainAnchor>? blockchainAnchors,
    String? c2paManifestRef,
    String? mediaFilePath,
    String? thumbnailPath,
  }) {
    return ProofRecord(
      id: id,
      mediaHash: mediaHash,
      mediaType: mediaType,
      captureMetadata: captureMetadata,
      signature: signature,
      publicKey: publicKey,
      deviceId: deviceId,
      timestampToken: timestampToken,
      canonicalPayload: canonicalPayload,
      createdAt: createdAt,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      blockchainAnchors: blockchainAnchors ?? this.blockchainAnchors,
      c2paManifestRef: c2paManifestRef ?? this.c2paManifestRef,
      mediaFilePath: mediaFilePath ?? this.mediaFilePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'media_hash': mediaHash,
        'media_type': mediaType.name,
        'capture_metadata': captureMetadata.toJson(),
        'signature': signature,
        'public_key': publicKey,
        'device_id': deviceId,
        'timestamp_token': timestampToken?.toJson(),
        'canonical_payload': canonicalPayload,
        'created_at': createdAt.toIso8601String(),
        'verification_status': verificationStatus.name,
        'blockchain_anchors':
            blockchainAnchors.map((a) => a.toJson()).toList(),
        'c2pa_manifest_ref': c2paManifestRef,
        'media_file_path': mediaFilePath,
        'thumbnail_path': thumbnailPath,
        'trust_score': trustScore,
      };
}
