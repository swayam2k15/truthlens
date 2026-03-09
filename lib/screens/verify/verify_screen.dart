import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/attestation_service.dart';
import '../../services/proof_storage_service.dart';
import '../../models/proof_record.dart';
import '../../widgets/trust_badge.dart';

/// Verification screen.
///
/// Allows users to:
/// 1. Verify their own proofs from local storage
/// 2. Import and verify proofs from others (via QR code or file)
/// 3. See a detailed breakdown of each verification layer
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key});

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  VerificationResult? _result;
  ProofRecord? _selectedProof;
  bool _isVerifying = false;

  Future<void> _verifyLatestProof() async {
    final proofs = ProofStorageService.instance.getAllProofs();
    if (proofs.isEmpty) {
      _showMessage('No proofs found. Capture something first!');
      return;
    }

    setState(() {
      _isVerifying = true;
      _selectedProof = proofs.first;
    });

    try {
      final result = await AttestationService.instance.verifyProof(proofs.first);
      setState(() => _result = result);
    } catch (e) {
      _showMessage('Verification failed: $e');
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Proof'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              // TODO: Implement QR code scanner for importing proofs
              _showMessage('QR scanner coming soon');
            },
            tooltip: 'Scan QR Code',
          ),
        ],
      ),
      body: _result == null
          ? _buildEmptyState(theme)
          : _buildVerificationResult(theme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isVerifying ? null : _verifyLatestProof,
        icon: _isVerifying
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.verified_user),
        label: Text(_isVerifying ? 'Verifying...' : 'Verify Latest'),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 24),
            Text(
              'Verify Authenticity',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Tap "Verify Latest" to check the integrity of your most recent capture, or scan a QR code to verify someone else\'s proof.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationResult(ThemeData theme) {
    final result = _result!;
    final proof = _selectedProof!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Trust score hero
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: result.isValid
                  ? [Colors.green.shade700, Colors.green.shade500]
                  : [Colors.orange.shade700, Colors.orange.shade500],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              TrustBadge(score: result.trustScore, size: 80),
              const SizedBox(height: 12),
              Text(
                '${result.trustLevel} Trust',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                result.isValid
                    ? 'All verification checks passed'
                    : 'Some checks need attention',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Verification checks
        Text(
          'Verification Details',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...result.checks.map((check) => _CheckTile(check: check)),

        const SizedBox(height: 20),

        // Proof metadata
        Text(
          'Proof Metadata',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        _MetadataRow('Content ID', proof.id.substring(0, 16) + '...'),
        _MetadataRow('Media Hash', proof.mediaHash.substring(0, 20) + '...'),
        _MetadataRow('Capture Time',
            proof.captureMetadata.captureTime.toIso8601String()),
        _MetadataRow('Device', proof.captureMetadata.deviceModel),
        if (proof.captureMetadata.latitude != null)
          _MetadataRow(
            'Location',
            '${proof.captureMetadata.latitude!.toStringAsFixed(6)}, '
                '${proof.captureMetadata.longitude!.toStringAsFixed(6)}',
          ),
        _MetadataRow('Device ID', proof.deviceId.substring(0, 12) + '...'),
      ],
    );
  }
}

class _CheckTile extends StatelessWidget {
  final VerificationCheck check;
  const _CheckTile({required this.check});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          check.passed ? Icons.check_circle : Icons.warning,
          color: check.passed ? Colors.green : Colors.orange,
        ),
        title: Text(check.name),
        subtitle: Text(
          check.detail,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetadataRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
