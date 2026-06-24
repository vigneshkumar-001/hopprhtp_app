import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/models.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/premium_card.dart';

/// A label/value row used in every money breakdown across the flow.
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
    this.badge,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: emphasized ? AppText.bodyStrong : AppText.body),
        if (badge != null) ...[const SizedBox(width: 6), badge!],
        const Spacer(),
        Text(
          value,
          style: (emphasized ? AppText.h3 : AppText.bodyStrong)
              .copyWith(color: valueColor),
        ),
      ],
    );
  }
}

/// Hatched image placeholder (the "device" / "product" thumbnails).
class ThumbPlaceholder extends StatelessWidget {
  const ThumbPlaceholder({super.key, this.label = 'product', this.size = 56});
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadii.sm,
      child: CustomPaint(
        painter: _HatchPainter(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(label,
                style: AppText.caption.copyWith(
                    color: AppColors.textTertiary, fontSize: 9)),
          ),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.surfaceMuted);
    final line = Paint()
      ..color = const Color(0x11000000)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Item row card: thumbnail + product/subtitle + amount (used widely).
class ItemSummaryCard extends StatelessWidget {
  const ItemSummaryCard({
    super.key,
    required this.product,
    required this.subtitle,
    required this.amount,
    this.thumbLabel = 'device',
    this.trailing,
    this.color = AppColors.surface,
  });

  final String product;
  final String subtitle;
  final double amount;
  final String thumbLabel;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: color,
      child: Row(
        children: [
          ThumbPlaceholder(label: thumbLabel),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product,
                    style: AppText.bodyStrong,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppText.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          trailing ?? Text(Money.format(amount), style: AppText.bodyStrong),
        ],
      ),
    );
  }
}

/// The "grand total" summary card with a one-line cost breakdown
/// (item · delivery · trust + fee split). Uses the same premium dark card /
/// glowing-sphere design as the Home balance card, sized to its content.
/// Shared across the payment flow.
class GrandTotalCard extends StatelessWidget {
  const GrandTotalCard({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  Widget build(BuildContext context) {
    final muted = AppText.caption.copyWith(color: AppColors.textOnDarkMuted);
    return PremiumCard(
      height: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grand total payable by buyer', style: muted),
          const SizedBox(height: AppSizes.xs),
          Text(Money.format(draft.grandTotal), style: AppText.numeral),
          const SizedBox(height: AppSizes.sm),
          Text(
            '${Money.format(draft.itemSubtotal)} item · '
            '${Money.format(draft.deliveryFee)} delivery · '
            '${Money.format(draft.buyerTrustShare)} trust '
            '(${draft.feeSplit.label})',
            style: muted,
          ),
        ],
      ),
    );
  }
}

/// Section header label inside cards ("PAYMENT COMPOSITION", "BREAKDOWN…").
class CardSectionLabel extends StatelessWidget {
  const CardSectionLabel(this.text, {super.key});
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

/// A small info banner (lock/shield note) used across the flow.
class NoteBanner extends StatelessWidget {
  const NoteBanner({
    super.key,
    required this.text,
    this.icon = Icons.lock_outline_rounded,
    this.color,
    this.textColor,
    this.highlight,
    this.highlightColor,
  });
  final String text;
  final IconData icon;

  /// Optional background fill. Defaults to the neutral muted surface.
  final Color? color;

  /// Optional body text + icon colour. Defaults to [AppColors.textSecondary].
  final Color? textColor;

  /// Optional substring rendered bold in [highlightColor] (first match only).
  final String? highlight;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final base = textColor ?? AppColors.textSecondary;
    final baseStyle = AppText.caption.copyWith(color: base);

    Widget body;
    final h = highlight;
    if (h != null && h.isNotEmpty && text.contains(h)) {
      final i = text.indexOf(h);
      body = Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: text.substring(0, i)),
            TextSpan(
              text: h,
              style: TextStyle(
                color: highlightColor ?? base,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: text.substring(i + h.length)),
          ],
        ),
      );
    } else {
      body = Text(text, style: baseStyle);
    }

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon shares the body colour so the note reads as one unit.
          Icon(icon, size: 18, color: base),
          const SizedBox(width: AppSizes.sm),
          Expanded(child: body),
        ],
      ),
    );
  }
}
