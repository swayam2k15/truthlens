import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proof_record.dart';
import '../services/proof_storage_service.dart';
import '../services/attestation_service.dart';
import '../services/capture_service.dart';
import '../core/crypto/key_manager.dart';

/// ─── Service Providers ───────────────────────────────────────────

final proofStorageProvider = Provider<ProofStorageService>((ref) {
  return ProofStorageService.instance;
});

final attestationServiceProvider = Provider<AttestationService>((ref) {
  return AttestationService.instance;
});

final captureServiceProvider = Provider<CaptureService>((ref) {
  return CaptureService();
});

final keyManagerProvider = Provider<KeyManager>((ref) {
  return KeyManager.instance;
});

/// ─── State Providers ─────────────────────────────────────────────

/// All stored proof records, sorted newest-first.
/// Invalidated whenever a new proof is created.
final allProofsProvider = StateNotifierProvider<ProofListNotifier, List<ProofRecord>>((ref) {
  return ProofListNotifier(ref.read(proofStorageProvider));
});

class ProofListNotifier extends StateNotifier<List<ProofRecord>> {
  final ProofStorageService _storage;

  ProofListNotifier(this._storage) : super([]) {
    refresh();
  }

  void refresh() {
    state = _storage.getAllProofs();
  }

  Future<void> addProof(ProofRecord proof) async {
    await _storage.saveProof(proof);
    refresh();
  }

  Future<void> removeProof(String id) async {
    await _storage.deleteProof(id);
    refresh();
  }
}

/// Currently active proof being viewed in detail.
final selectedProofProvider = StateProvider<ProofRecord?>((ref) => null);

/// Whether the camera is currently capturing.
final isCapturingProvider = StateProvider<bool>((ref) => false);

/// Whether a video recording is in progress.
final isRecordingVideoProvider = StateProvider<bool>((ref) => false);

/// Current attestation pipeline progress (0.0 to 1.0).
final attestationProgressProvider = StateProvider<double>((ref) => 0.0);

/// Pipeline status message during attestation.
final attestationStatusProvider = StateProvider<String>((ref) => '');

/// ─── Verification Provider ───────────────────────────────────────

/// Runs full independent verification on a proof record.
final verifyProofProvider =
    FutureProvider.family<VerificationResult, ProofRecord>((ref, proof) async {
  final attestation = ref.read(attestationServiceProvider);
  return attestation.verifyProof(proof);
});

/// ─── Statistics Providers ────────────────────────────────────────

final proofCountProvider = Provider<int>((ref) {
  return ref.watch(allProofsProvider).length;
});

final averageTrustScoreProvider = Provider<double>((ref) {
  final proofs = ref.watch(allProofsProvider);
  if (proofs.isEmpty) return 0;
  final total = proofs.fold<int>(0, (sum, p) => sum + p.trustScore);
  return total / proofs.length;
});

final proofsByTypeProvider = Provider<Map<MediaType, int>>((ref) {
  final proofs = ref.watch(allProofsProvider);
  return {
    MediaType.photo: proofs.where((p) => p.mediaType == MediaType.photo).length,
    MediaType.video: proofs.where((p) => p.mediaType == MediaType.video).length,
  };
});
