import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../services/capture_service.dart';
import '../../services/attestation_service.dart';
import '../../models/proof_record.dart';
import '../../widgets/trust_badge.dart';
import '../../widgets/proof_card.dart';

/// Main camera capture screen.
///
/// Shows a live camera preview with real-time overlay of:
/// - Current UTC timestamp (ticking)
/// - GPS coordinates
/// - Device attestation status
/// - Trust score indicator
///
/// The timestamp overlay is purely informational — the actual
/// cryptographic proof is generated at capture time, not from the overlay.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  final _captureService = CaptureService();
  CameraController? _controller;
  bool _isCapturing = false;
  bool _isRecording = false;
  ProofRecord? _lastProof;
  Timer? _clockTimer;
  DateTime _currentTime = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _startClock();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() => _currentTime = DateTime.now().toUtc());
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      _controller = await _captureService.initializeCamera();
      if (mounted) setState(() {});
    } catch (e) {
      _showError('Camera initialization failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _captureService.disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _takePhoto() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final capture = await _captureService.capturePhoto();

      final proof = await AttestationService.instance.attestCapture(
        capture: capture,
        mediaType: MediaType.photo,
      );

      setState(() => _lastProof = proof);

      if (mounted) {
        _showProofSheet(proof);
      }
    } catch (e) {
      _showError('Capture failed: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _toggleVideoRecording() async {
    if (_isRecording) {
      // Stop recording
      try {
        final capture = await _captureService.stopVideoRecording();
        final proof = await AttestationService.instance.attestCapture(
          capture: capture,
          mediaType: MediaType.video,
        );
        setState(() {
          _isRecording = false;
          _lastProof = proof;
        });
        if (mounted) _showProofSheet(proof);
      } catch (e) {
        _showError('Stop recording failed: $e');
        setState(() => _isRecording = false);
      }
    } else {
      // Start recording
      try {
        await _captureService.startVideoRecording();
        setState(() => _isRecording = true);
      } catch (e) {
        _showError('Start recording failed: $e');
      }
    }
  }

  void _showProofSheet(ProofRecord proof) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
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
              Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'Proof Created',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ProofCard(proof: proof),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[700]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!)
          else
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // Top overlay — live timestamp + status
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isRecording ? Colors.red : Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'TRUTHLENS',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _isRecording ? 'REC' : 'READY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _isRecording ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Live UTC timestamp
                  Text(
                    '${timeFormat.format(_currentTime)} UTC',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Epoch: ${_currentTime.millisecondsSinceEpoch}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Switch camera
                  _ControlButton(
                    icon: Icons.flip_camera_ios,
                    label: 'Flip',
                    onTap: () async {
                      await _captureService.switchCamera();
                      _controller =
                          await _captureService.initializeCamera();
                      setState(() {});
                    },
                  ),

                  // Capture button
                  GestureDetector(
                    onTap: _isCapturing ? null : _takePhoto,
                    onLongPress: _toggleVideoRecording,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: _isRecording
                            ? Colors.red
                            : _isCapturing
                                ? Colors.grey
                                : Colors.white.withValues(alpha: 0.3),
                      ),
                      child: _isCapturing
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : _isRecording
                              ? const Icon(
                                  Icons.stop,
                                  color: Colors.white,
                                  size: 32,
                                )
                              : null,
                    ),
                  ),

                  // Video mode toggle
                  _ControlButton(
                    icon: _isRecording ? Icons.stop : Icons.videocam,
                    label: _isRecording ? 'Stop' : 'Video',
                    onTap: _toggleVideoRecording,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _captureService.disposeCamera();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
