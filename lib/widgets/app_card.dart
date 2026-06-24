import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';

/// The common card / container used across the app.
/// One place to control radius, padding, fill, border and (optional) tap.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.lg),
    this.color = AppColors.surface,
    this.gradient,
    this.radius,
    this.border,
    this.onTap,
    this.shadow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  /// Optional gradient fill (e.g. the pastel "bubble" on transaction cards).
  /// Takes precedence over [color].
  final Gradient? gradient;
  final BorderRadius? radius;
  final BoxBorder? border;
  final VoidCallback? onTap;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? AppRadii.card;

    // Elevation rules:
    //  - shadow:true      → pronounced floating card
    //  - light surface    → gentle soft shadow (the default "floating" look)
    //  - tinted/nested    → flat (avoids odd shadows on cards-inside-cards)
    final List<BoxShadow>? shadows;
    if (shadow) {
      shadows = const [
        BoxShadow(color: AppColors.shadow, blurRadius: 24, offset: Offset(0, 10)),
      ];
    } else if (gradient != null || color.computeLuminance() > 0.82) {
      shadows = const [
        BoxShadow(
            color: AppColors.shadowSoft, blurRadius: 14, offset: Offset(0, 6)),
      ];
    } else {
      shadows = null;
    }

    final content = AnimatedContainer(
      duration: AppDurations.fast,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: r,
        border: border,
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: r,
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        splashColor: AppColors.surfaceMuted,
        highlightColor: AppColors.surfaceMuted.withValues(alpha: 0.6),
        child: content,
      ),
    );
  }
}

/// A small dark gradient card (the "Protected in escrow" / profile header look).
class DarkCard extends StatelessWidget {
  const DarkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSizes.xl),
    this.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    // Top-right orb. Lime theme → an olive-green sphere with depth; Mono → a
    // soft white glow. A sphere-like radial gradient (offset highlight) gives
    // it dimension, and the card clips it to the rounded corner.
    final Gradient orb = accent.isLime
        ? const RadialGradient(
            // Center #A6D12D · Mid rgba(166,209,45,0.5) · Outer transparent
            colors: [
              Color(0xFFA6D12D),
              Color(0x80A6D12D),
              Color(0x00A6D12D),
            ],
            stops: [0.0, 0.5, 1.0],
          )
        : const RadialGradient(
            colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
          );
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias, // clip the orb to the rounded corner
      decoration: BoxDecoration(
        borderRadius: radius ?? AppRadii.xl,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.inkSoft, AppColors.ink],
        ),
      ),
      child: Stack(
        children: [
          // Large blurred glowing orb, partially clipped by the card edge.
          Positioned(
            top: -42,
            right: -34,
            child: Opacity(
              opacity: 0.85,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 30,
                  sigmaY: 30,
                  tileMode: TileMode.decal,
                ),
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: orb,
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
