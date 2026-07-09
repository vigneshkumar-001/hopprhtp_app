import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Half-circle trust-score gauge (Merchant Profile).
class TrustGauge extends StatelessWidget {
  const TrustGauge({super.key, required this.score, this.max = 1000});
  final int score;
  final int max;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      width: 220,
      child: CustomPaint(
        painter: _GaugePainter(value: score / max),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$score',
                  style: AppText.display.copyWith(fontSize: 40, height: 1),
                ),
                Text('/ $max', style: AppText.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value});
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = AppColors.surfaceMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi, false, track);
    canvas.drawArc(rect, math.pi, math.pi * value.clamp(0, 1), false, progress);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}
