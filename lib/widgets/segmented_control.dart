import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';

/// Common segmented toggle (Buyer / 50:50 / Seller, Buyer-favoured / Seller…).
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<String> segments;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // Neutral grey track in every theme (no lime/green tint) so it never
        // clashes with the white selected pill or the card behind it.
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: Row(
        children: [
          for (int i = 0; i < segments.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  curve: AppDurations.easeOut,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.surface : Colors.transparent,
                    borderRadius: AppRadii.sm,
                    boxShadow: i == selected
                        ? const [
                            BoxShadow(
                                color: AppColors.shadowSoft,
                                blurRadius: 8,
                                offset: Offset(0, 2)),
                          ]
                        : null,
                  ),
                  child: Text(
                    segments[i],
                    style: AppText.label.copyWith(
                      color: i == selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A thin labelled progress bar (evidence completeness, fraud-risk score…).
class LabeledBar extends StatelessWidget {
  const LabeledBar({
    super.key,
    required this.label,
    required this.value, // 0..1
    this.trailing,
    this.color = AppColors.ink,
  });

  final String label;
  final double value;
  final String? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppText.bodyStrong),
            Text(trailing ?? '${(value * 100).round()}%',
                style: AppText.bodyStrong),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        ClipRRect(
          borderRadius: AppRadii.pill,
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 7,
            backgroundColor: AppColors.surfaceMuted,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// A simple stylised map backdrop with a dotted delivery route. Pure paint —
/// no map SDK / network needed.
class MapBackdrop extends StatefulWidget {
  const MapBackdrop({
    super.key,
    this.showGeofence = false,
    this.height = 280,
    this.animateRoute = false,
  });
  final bool showGeofence;
  final double height;

  /// When true, a pulse + marker animates along the dotted route.
  final bool animateRoute;

  @override
  State<MapBackdrop> createState() => _MapBackdropState();
}

class _MapBackdropState extends State<MapBackdrop>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animateRoute) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _c;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: controller == null
          ? CustomPaint(painter: _MapPainter(showGeofence: widget.showGeofence))
          : AnimatedBuilder(
              animation: controller,
              builder: (_, _) => CustomPaint(
                painter: _MapPainter(
                  showGeofence: widget.showGeofence,
                  progress: controller.value,
                ),
              ),
            ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.showGeofence, this.progress});
  final bool showGeofence;

  /// Head position (0–1) of the travelling pulse, or null when static.
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFEDEEEA);
    canvas.drawRect(Offset.zero & size, bg);

    // Faint road grid.
    final road = Paint()
      ..color = const Color(0xFFDFE0DB)
      ..strokeWidth = 10;
    for (double x = size.width * 0.2; x < size.width; x += size.width * 0.32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
    for (double y = size.height * 0.25; y < size.height; y += size.height * 0.3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
    // A green block (park).
    final park = Paint()..color = const Color(0xFFD8E6CC);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.55, size.height * 0.12,
            size.width * 0.3, size.height * 0.3),
        const Radius.circular(8),
      ),
      park,
    );

    // Dotted route from bottom-left to top-right.
    final dot = Paint()
      ..color = const Color(0xFF0B0B0C)
      ..style = PaintingStyle.fill;
    final start = Offset(size.width * 0.12, size.height * 0.9);
    final end = Offset(size.width * 0.9, size.height * 0.2);
    Offset routePoint(double t) => Offset(
          start.dx + (end.dx - start.dx) * t,
          start.dy + (end.dy - start.dy) * t - 30 * (t - t * t) * 4,
        );
    const steps = 22;
    final head = progress; // null when static
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      var radius = 3.2;
      if (head != null) {
        // Dots swell as the travelling pulse passes over them.
        final pulse = (1 - (t - head).abs() / 0.16).clamp(0.0, 1.0);
        radius = 3.2 + 3.2 * pulse;
      }
      canvas.drawCircle(routePoint(t), radius, dot);
    }
    // A marker rides at the head of the pulse (the dispatcher moving).
    if (head != null) {
      final hp = routePoint(head);
      canvas.drawCircle(hp, 9, Paint()..color = Colors.white);
      canvas.drawCircle(hp, 6.5, dot);
    }

    if (showGeofence) {
      final center = end;
      final ring = Paint()
        ..color = const Color(0xFF0B0B0C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      _dashedCircle(canvas, center, size.height * 0.22, ring);
      canvas.drawCircle(center, 5, dot);
    }
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dashCount = 40;
    for (int i = 0; i < dashCount; i++) {
      if (i.isEven) continue;
      final a1 = (i / dashCount) * 6.283185;
      final a2 = ((i + 1) / dashCount) * 6.283185;
      final path = Path()
        ..addArc(Rect.fromCircle(center: c, radius: r), a1, a2 - a1);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.showGeofence != showGeofence || old.progress != progress;
}
