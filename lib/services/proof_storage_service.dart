import 'dart:convert';
import 'package:hive/hive.dart';

import '../models/capture_metadata.dart';
import '../models/proof_record.dart';

/// Persistent local storage for proof records.
///
/// Uses Hive (lightweight, fast, no native deps) for offline-first storage.
/// Proofs are stored as JSON in a Hive box keyed by content ID.
class ProofStorageService {
  ProofStorageService._();
  static final ProofStorageService instance = ProofStorageService._();

  Box get _box => Hive.box('truthlens_proofs');

  /// Save a proof record.
  Future<void> saveProof(ProofRecord proof) async {
    await _box.put(proof.id, jsonEncode(proof.toJson()));
  }

  /// Get a proof by ID.
  ProofRecord? getProof(String id) {
    final json = _box.get(id) as String?;
    if (json == null) return null;
    return _deserialize(json);
  }

  /// Get all stored proofs, sorted by creation date (newest first).
  List<ProofRecord> getAllProofs() {
    final proofs = <ProofRecord>[];
    for (final key in _box.keys) {
      final json = _box.get(key) as String?;
      if (json != null) {
        try {
          proofs.add(_deserialize(json));
        } catch (_) {}
      }
    }
    proofs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return proofs;
  }

  /// Delete a proof by ID.
  Future<void> deleteProof(String id) async {
    await _box.delete(id);
  }

  /// Get count of stored proofs.
  int get proofCount => _box.length;

  /// Export all proofs as JSON string (for backup).
  String exportAllProofs() {
    final proofs = getAllProofs();
    return const JsonEncoder.withIndent('  ')
        .convert(proofs.map((p) => p.toJson()).toList());
  }

  ProofRecord _deserialize(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    // Simplified deserialization — production would use freezed/json_serializable
    return ProofRecord(
      id: map['id'] as String,
      mediaHash: map['media_hash'] as String,
      mediaType: MediaType.values.byName(map['media_type'] as String),
      captureMetadata: _deserializeMetadata(map['capture_metadata']),
      signature: map['signature'] as String,
      publicKey: map['public_key'] as String,
      deviceId: map['device_id'] as String,
      canonicalPayload: map['canonical_payload'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      verificationStatus:
          VerificationStatus.values.byName(map['verification_status'] as String),
      blockchainAnchors: (map['blockchain_anchors'] as List?)
              ?.map((a) => BlockchainAnchor.fromJson(a))
              .toList() ??
          [],
      c2paManifestRef: map['c2pa_manifest_ref'] as String?,
      mediaFilePath: map['media_file_path'] as String?,
    );
  }

  CaptureMetadata _deserializeMetadata(dynamic map) {
    return CaptureMetadata.fromJson(map as Map<String, dynamic>);
  }
}
