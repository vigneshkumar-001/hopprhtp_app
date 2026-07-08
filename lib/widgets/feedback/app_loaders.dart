import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';

/// Premium custom circular loader — a smoothly rotating arc with a soft gradient
/// tail. Replaces the default Material `CircularProgressIndicator` app-wide.
class AppCircularLoader extends StatefulWidget {
  const AppCircularLoader({
    super.key,
    this.size = 28,
    this.strokeWidth = 3,
    this.color,
  });

  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  State<AppCircularLoader> createState() => _AppCircularLoaderState();
}

class _AppCircularLoaderState extends State<AppCircularLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.ink;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => CustomPaint(
          painter: _ArcPainter(
            progress: _c.value,
            color: color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final startAngle = progress * 2 * math.pi;
    const sweep = math.pi * 1.5; // 270° comet arc

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0), color],
        transform: GradientRotation(startAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress || old.color != color;
}

/// The app's standard "this whole area is loading" placeholder: a centered
/// [AppCircularLoader] with an optional caption underneath. Use this instead of
/// a bare Material `CircularProgressIndicator` so first-load states feel
/// premium and on-brand. Fills and centers within its parent.
class AppCenteredLoader extends StatelessWidget {
  const AppCenteredLoader({super.key, this.message, this.size = 30});

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppCircularLoader(size: size),
          if (message != null) ...[
            const SizedBox(height: AppSizes.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 160.ms);
  }
}

/// Button-sized loader (used inside [AppButton] while an action is in flight).
class AppButtonLoader extends StatelessWidget {
  const AppButtonLoader({
    super.key,
    this.color = AppColors.textOnDark,
    this.size = 22,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      AppCircularLoader(size: size, strokeWidth: 2.4, color: color);
}

/// Full-screen blocking loader for long operations. Show/hide imperatively:
///
/// ```dart
/// AppLoadingOverlay.show(context, message: 'Securing your account…');
/// try { ... } finally { AppLoadingOverlay.hide(); }
/// ```
class AppLoadingOverlay {
  AppLoadingOverlay._();

  static OverlayEntry? _entry;

  static void show(BuildContext context, {String? message}) {
    if (_entry != null) return; // already visible
    final entry = OverlayEntry(builder: (_) => _OverlayBody(message: message));
    Overlay.of(context, rootOverlay: true).insert(entry);
    _entry = entry;
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

class _OverlayBody extends StatelessWidget {
  const _OverlayBody({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(dismissible: false, color: AppColors.scrim),
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSizes.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.card,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppCircularLoader(),
                if (message != null) ...[
                  const SizedBox(height: AppSizes.md),
                  Text(message!, style: AppText.body),
                ],
              ],
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 160.ms);
  }
}
