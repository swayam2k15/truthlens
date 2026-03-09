import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/proof_storage_service.dart';
import '../../models/proof_record.dart';
import '../../widgets/trust_badge.dart';
import '../../widgets/proof_card.dart';

/// History screen showing all captured proofs with their trust scores.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<ProofRecord> _proofs = [];

  @override
  void initState() {
    super.initState();
    _loadProofs();
  }

  void _loadProofs() {
    setState(() {
      _proofs = ProofStorageService.instance.getAllProofs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Proof History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _proofs.isEmpty
                ? null
                : () {
                    final json =
                        ProofStorageService.instance.exportAllProofs();
                    Share.share(json, subject: 'TruthLens Proof Export');
                  },
            tooltip: 'Export All',
          ),
        ],
      ),
      body: _proofs.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 64,
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No proofs yet',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Capture your first photo or video\nto create a proof-of-life record.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _loadProofs(),
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _proofs.length,
                itemBuilder: (ctx, i) => _ProofListItem(
                  proof: _proofs[i],
                  onTap: () => _showProofDetail(_proofs[i]),
                ),
              ),
            ),
    );
  }

  void _showProofDetail(ProofRecord proof) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ProofCard(proof: proof),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProofListItem extends StatelessWidget {
  final ProofRecord proof;
  final VoidCallback onTap;

  const _ProofListItem({required this.proof, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy HH:mm:ss');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail or icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: proof.mediaFilePath != null &&
                        File(proof.mediaFilePath!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(proof.mediaFilePath!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(
                        proof.mediaType == MediaType.photo
                            ? Icons.image
                            : Icons.videocam,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proof.mediaType == MediaType.photo ? 'Photo' : 'Video',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateFormat.format(proof.createdAt.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusChip(
                          label: proof.verificationStatus.name,
                          color: _statusColor(proof.verificationStatus),
                        ),
                        if (proof.captureMetadata.latitude != null) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.location_on,
                              size: 14, color: Colors.grey[500]),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Trust score
              TrustBadge(score: proof.trustScore, size: 40),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.signed:
        return Colors.blue;
      case VerificationStatus.timestamped:
        return Colors.teal;
      case VerificationStatus.anchored:
        return Colors.green;
      case VerificationStatus.c2paCertified:
        return Colors.purple;
      case VerificationStatus.thirdPartyVerified:
        return Colors.amber;
    }
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
