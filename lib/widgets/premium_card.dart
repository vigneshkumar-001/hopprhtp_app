import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';
import '../core/theme/app_sizes.dart';

/// The shared "ultra-premium" dark card used for the Home balance and the
/// Profile header. Provides the dark gradient, 38px radius, padding and the
/// themed glowing sphere (green in the Lime theme, grey in the Mono theme),
/// clipped to the rounded corner. Pass the card's content as [child].
class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.height = 206,
    this.padding = const EdgeInsets.all(28),
  });

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);

    final List<Color> bg = accent.isLime
        ? const [Color(0xFF0B140A), Color(0xFF050805)]
        : const [Color(0xFF15171B), Color(0xFF060708)];

    final Gradient orb = accent.isLime
        ? const RadialGradient(
            center: Alignment(-0.3, -0.3),
            colors: [
              Color(0xFFB9D657), // bright highlight
              Color(0xFF7E9A33), // green body
              Color(0xFF44531D), // defined darker rim
            ],
            stops: [0.0, 0.55, 1.0],
          )
        : const RadialGradient(
            center: Alignment(-0.3, -0.3),
            colors: [
              Color(0xFF44474C), // light-grey highlight
              Color(0xFF2A2C30), // grey body
              Color(0xFF141519), // defined darker rim
            ],
            stops: [0.0, 0.55, 1.0],
          );

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: bg,
                  ),
                ),
              ),
            ),
            // Defined glossy sphere, partially clipped by the corner.
            Positioned(
              top: -26,
              right: -34,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                    sigmaX: 4, sigmaY: 4, tileMode: TileMode.decal),
                child: Container(
                  width: 152,
                  height: 152,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: orb),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// A value + label metric used inside [PremiumCard] (e.g. "2 / Active").
class CardStat extends StatelessWidget {
  const CardStat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
  });

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
              fontSize: 22,
              height: 1.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: valueColor ?? Colors.white,
            )),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.55),
            )),
      ],
    );
  }
}

/// Thin vertical divider between [CardStat]s.
class CardStatDivider extends StatelessWidget {
  const CardStatDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
      color: Colors.white.withValues(alpha: 0.12),
    );
  }
}
