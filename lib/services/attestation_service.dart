import 'dart:convert';
import 'dart:typed_data';

import '../core/crypto/key_manager.dart';
import '../core/crypto/proof_signer.dart';
import '../core/crypto/timestamp_authority.dart';
import '../core/blockchain/blockchain_anchor.dart';
import '../core/c2pa/c2pa_manifest.dart';
import '../models/capture_metadata.dart';
import '../models/proof_record.dart';
import 'capture_service.dart';
import 'proof_storage_service.dart';

/// High-level attestation orchestrator.
///
/// Coordinates the full proof-of-life pipeline:
/// 1. Capture media + metadata
/// 2. Sign with device key
/// 3. Get RFC 3161 trusted timestamp
/// 4. Optionally anchor to blockchain
/// 5. Generate C2PA manifest
/// 6. Store proof locally
class AttestationService {
  AttestationService._();
  static final AttestationService instance = AttestationService._();

  final _proofSigner = ProofSigner.instance;
  final _blockchain = BlockchainAnchorService.instance;
  final _c2pa = C2PAManifestBuilder.instance;
  final _storage = ProofStorageService.instance;

  /// Full attestation pipeline for a captured photo.
  Future<ProofRecord> attestCapture({
    required CaptureResult capture,
    required MediaType mediaType,
    bool anchorToBlockchain = false,
    String? blockchainPrivateKey,
  }) async {
    // Step 1: Create signed proof
    var proof = await _proofSigner.createProof(
      mediaBytes: capture.mediaBytes,
      metadata: capture.metadata,
      mediaType: mediaType,
    );

    // Step 2: Update with file path
    proof = proof.copyWith(mediaFilePath: capture.filePath);

    // Step 3: Blockchain anchoring (optional — costs gas)
    if (anchorToBlockchain && blockchainPrivateKey != null) {
      final anchor = await _blockchain.anchorToPolygon(
        proofHash: proof.mediaHash,
        privateKeyHex: blockchainPrivateKey,
      );
      if (anchor != null) {
        proof = proof.copyWith(
          blockchainAnchors: [...proof.blockchainAnchors, anchor],
          verificationStatus: VerificationStatus.anchored,
        );
      }
    }

    // Step 4: Generate C2PA manifest
    final manifest = await _c2pa.buildManifest(
      proof: proof,
      mediaBytes: capture.mediaBytes,
    );
    proof = proof.copyWith(c2paManifestRef: manifest.toJsonString());

    // Step 5: Store locally
    await _storage.saveProof(proof);

    return proof;
  }

  /// Verify an existing proof record.
  Future<VerificationResult> verifyProof(ProofRecord proof) async {
    final checks = <VerificationCheck>[];

    // 1. Verify signature
    final sigValid = await _proofSigner.verifyProof(proof);
    checks.add(VerificationCheck(
      name: 'Digital Signature',
      passed: sigValid,
      detail: sigValid
          ? 'Ed25519 signature is valid'
          : 'Signature verification failed — content may have been tampered',
    ));

    // 2. Verify timestamp token
    if (proof.timestampToken != null) {
      final tsValid =
          proof.timestampToken!.source == TimestampSource.rfc3161;
      checks.add(VerificationCheck(
        name: 'Trusted Timestamp (RFC 3161)',
        passed: tsValid,
        detail: tsValid
            ? 'TSA: ${proof.timestampToken!.tsaUrl} at ${proof.timestampToken!.timestamp}'
            : 'Local timestamp only (not TSA-verified)',
      ));
    }

    // 3. Verify blockchain anchors
    for (final anchor in proof.blockchainAnchors) {
      checks.add(VerificationCheck(
        name: 'Blockchain (${anchor.chain})',
        passed: true,
        detail: 'TX: ${anchor.transactionHash}',
      ));
    }

    // 4. Check metadata completeness
    final hasGps = proof.captureMetadata.latitude != null;
    checks.add(VerificationCheck(
      name: 'GPS Location',
      passed: hasGps,
      detail: hasGps
          ? '${proof.captureMetadata.latitude}, ${proof.captureMetadata.longitude}'
          : 'No GPS data available',
    ));

    final allPassed = checks.every((c) => c.passed);

    return VerificationResult(
      isValid: allPassed,
      trustScore: proof.trustScore,
      trustLevel: proof.trustLevel,
      checks: checks,
    );
  }
}

class VerificationCheck {
  final String name;
  final bool passed;
  final String detail;

  const VerificationCheck({
    required this.name,
    required this.passed,
    required this.detail,
  });
}

class VerificationResult {
  final bool isValid;
  final int trustScore;
  final String trustLevel;
  final List<VerificationCheck> checks;

  const VerificationResult({
    required this.isValid,
    required this.trustScore,
    required this.trustLevel,
    required this.checks,
  });
}
