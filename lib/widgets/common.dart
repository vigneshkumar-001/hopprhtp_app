import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';

/// The "Hoppr" word-mark used across onboarding / auth / home.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.onDark = false,
    this.fontSize = 24,
    this.withBadge = false,
    this.pill = false,
  });

  final bool onDark;
  final double fontSize;
  final bool withBadge;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? AppColors.textOnDark : AppColors.textPrimary;
    final word = Text(
      'Hoppr',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: pill ? AppColors.textOnDark : color,
      ),
    );

    if (pill) {
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.sm),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: AppRadii.md,
        ),
        child: word,
      );
    }

    if (!withBadge) return word;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        word,
        const SizedBox(width: AppSizes.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: onDark ? AppColors.textOnDarkMuted : AppColors.border,
              width: 1.2,
            ),
          ),
          child: Text(
            'HTP',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: onDark ? AppColors.textOnDarkMuted : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A rounded status / info pill (icon + label).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.border,
    this.letterSpacing,
    this.fontWeight,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? background;
  final Color? foreground;

  /// Optional hairline border colour. When null, the pill has no outline.
  final Color? border;

  /// Optional letter spacing — used by uppercase "tag" style pills.
  final double? letterSpacing;

  /// Optional font weight override (defaults to semibold).
  final FontWeight? fontWeight;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : AppSizes.md,
        vertical: dense ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: background ?? AppColors.surfaceMuted,
        borderRadius: AppRadii.pill,
        border: border != null ? Border.all(color: border!) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 13 : 15, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppText.caption.copyWith(
              color: fg,
              fontWeight: fontWeight ?? FontWeight.w600,
              fontSize: dense ? 11.5 : 12.5,
              letterSpacing: letterSpacing,
            ),
          ),
        ],
      ),
    );
  }
}

/// The verified check badge (small green tick).
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16, this.color = AppColors.success});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.verified_rounded, size: size, color: color);
  }
}

/// Circular avatar with initials.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.initials,
    this.size = 44,
    this.onDark = false,
    this.background,
  });

  final String initials;
  final double size;
  final bool onDark;

  /// Overrides the default tile colour (used to match a card's pastel tint).
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ??
            (onDark ? AppColors.surface : AppAccent.of(context).accentSoft),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// The multi-segment step progress bar used in sign-up.
class StepProgress extends StatelessWidget {
  const StepProgress({super.key, required this.step, required this.total});
  final int step; // 1-based
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final filled = i < step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            child: AnimatedContainer(
              duration: AppDurations.normal,
              curve: AppDurations.easeOut,
              height: 5,
              decoration: BoxDecoration(
                color: filled ? AppColors.ink : AppColors.border,
                borderRadius: AppRadii.pill,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Carousel page dots (onboarding).
class PageDots extends StatelessWidget {
  const PageDots({
    super.key,
    required this.count,
    required this.index,
    this.activeColor = AppColors.textOnDark,
    this.inactiveColor = AppColors.textOnDarkMuted,
  });

  final int count;
  final int index;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: AppDurations.normal,
          curve: AppDurations.easeOut,
          margin: const EdgeInsets.only(right: 6),
          height: 4,
          width: active ? 22 : 7,
          decoration: BoxDecoration(
            color: active ? activeColor : inactiveColor.withValues(alpha: 0.4),
            borderRadius: AppRadii.pill,
          ),
        );
      }),
    );
  }
}

/// A labelled menu row inside a card (Profile list, etc.).
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    // In the Lime theme the menu-row icon tiles use a soft lilac (per the
    // reference design); the Default theme keeps the neutral accent tile.
    final tileColor = accent.isLime ? AppColors.lilacTile : accent.accentSoft;
    final tileIconColor =
        accent.isLime ? AppColors.onLilacTile : accent.onAccentSoft;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm, vertical: AppSizes.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tileColor,
                  borderRadius: AppRadii.sm,
                ),
                child: Icon(icon, size: 20, color: tileIconColor),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.bodyStrong),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppText.caption),
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (showChevron)
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded box with a dashed border (image-upload placeholders).
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    this.active = false,
    this.fill,
  });

  final Widget child;
  final bool active;

  /// Optional solid fill override. When null, falls back to the default
  /// translucent muted / success tint.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: active ? AppColors.success : AppColors.border,
        radius: AppSizes.rMd,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.md,
        child: Container(
          color: fill ??
              (active
                  ? AppColors.successSoft.withValues(alpha: 0.5)
                  : AppColors.surfaceMuted.withValues(alpha: 0.4)),
          child: child,
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round // round caps → clean dots
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    // Tiny dash + round cap renders as a round dot.
    const dash = 0.5;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        canvas.drawPath(
          metric.extractPath(dist, dist + dash),
          paint,
        );
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Section label like "YOU'LL NEED".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppText.caption.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
      ),
    );
  }
}
