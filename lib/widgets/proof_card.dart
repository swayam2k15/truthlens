import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/proof_record.dart';
import 'trust_badge.dart';

/// Detailed proof card showing all attestation layers.
class ProofCard extends StatelessWidget {
  final ProofRecord proof;

  const ProofCard({super.key, required this.proof});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trust score header
        Row(
          children: [
            TrustBadge(score: proof.trustScore, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${proof.trustLevel} Trust',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    proof.mediaType == MediaType.photo
                        ? 'Photo Proof'
                        : 'Video Proof',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                Share.share(
                  'TruthLens Proof\n'
                  'ID: ${proof.id}\n'
                  'Score: ${proof.trustScore}/100\n'
                  'Time: ${proof.captureMetadata.captureTime.toIso8601String()}\n'
                  'Hash: ${proof.mediaHash}',
                  subject: 'TruthLens Proof',
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Attestation layers
        _LayerCard(
          icon: Icons.edit,
          title: 'Digital Signature',
          subtitle: 'Ed25519 device key',
          detail: 'Sig: ${proof.signature.substring(0, 24)}...',
          isComplete: true,
        ),

        _LayerCard(
          icon: Icons.access_time,
          title: 'Trusted Timestamp',
          subtitle: proof.timestampToken != null
              ? 'RFC 3161 — ${proof.timestampToken!.tsaUrl}'
              : 'Not available',
          detail: dateFormat
              .format(proof.captureMetadata.captureTime.toLocal()),
          isComplete: proof.timestampToken != null,
        ),

        _LayerCard(
          icon: Icons.link,
          title: 'Blockchain Anchor',
          subtitle: proof.blockchainAnchors.isNotEmpty
              ? proof.blockchainAnchors
                  .map((a) => a.chain)
                  .join(', ')
              : 'Not anchored',
          detail: proof.blockchainAnchors.isNotEmpty
              ? 'TX: ${proof.blockchainAnchors.first.transactionHash.substring(0, 20)}...'
              : 'Tap to anchor now',
          isComplete: proof.blockchainAnchors.isNotEmpty,
        ),

        _LayerCard(
          icon: Icons.description,
          title: 'C2PA Content Credentials',
          subtitle: proof.c2paManifestRef != null
              ? 'Manifest attached'
              : 'Not generated',
          detail: 'Interoperable with Adobe, Truepic, etc.',
          isComplete: proof.c2paManifestRef != null,
        ),

        if (proof.captureMetadata.latitude != null)
          _LayerCard(
            icon: Icons.location_on,
            title: 'Geolocation',
            subtitle:
                '${proof.captureMetadata.latitude!.toStringAsFixed(6)}, '
                '${proof.captureMetadata.longitude!.toStringAsFixed(6)}',
            detail:
                'Accuracy: ${proof.captureMetadata.gpsAccuracy?.toStringAsFixed(1) ?? "?"} m',
            isComplete: true,
          ),

        const SizedBox(height: 16),

        // Content hash
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CONTENT HASH (SHA-256)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: proof.mediaHash));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hash copied')),
                  );
                },
                child: Text(
                  proof.mediaHash,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LayerCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String detail;
  final bool isComplete;

  const _LayerCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isComplete
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isComplete ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isComplete ? Colors.green : Colors.grey[400],
            size: 20,
          ),
        ],
      ),
    );
  }
}
