import 'dart:math';
import 'package:flutter/material.dart';

/// Circular trust score badge with animated ring.
class TrustBadge extends StatelessWidget {
  final int score;
  final double size;

  const TrustBadge({super.key, required this.score, this.size = 60});

  Color get _color {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.teal;
    if (score >= 45) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TrustRingPainter(
          progress: score / 100,
          color: _color,
        ),
        child: Center(
          child: Text(
            '$score',
            style: TextStyle(
              fontSize: size * 0.3,
              fontWeight: FontWeight.bold,
              color: _color,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _TrustRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 4;

    // Background ring
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      2 * pi * progress,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TrustRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
