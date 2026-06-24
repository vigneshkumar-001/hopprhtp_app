import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import 'app_card.dart';
import 'common.dart';

/// Soft pastel tints — each card is a uniform wash of one of these in the Lime
/// theme (light version → tint, same colour family).
const List<Color> _cardTints = [
  Color(0xFFE6DEF6), // lavender
  Color(0xFFD9E6F7), // blue
  Color(0xFFDCEFE1), // mint
  Color(0xFFF6E6D4), // peach
];

/// Common transaction list card used on Home / Initiation / Transit.
class TransactionCard extends StatelessWidget {
  const TransactionCard({
    super.key,
    required this.tx,
    this.onTap,
    this.colorIndex = 0,
  });

  final EscrowTransaction tx;
  final VoidCallback? onTap;

  /// Position-based index so each card gets a consistent pastel tint.
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final tint = _cardTints[colorIndex % _cardTints.length];
    // Lime: a soft pastel wash. Mono: a subtle light → grey wash.
    final gradient = accent.isLime
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(tint, Colors.white, 0.5)!, tint],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF1F1F3), Color(0xFFE6E6E9)],
          );

    return AppCard(
      onTap: onTap,
      color: accent.card,
      gradient: gradient,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadii.card,
        child: Stack(
          children: [
            // Soft highlight "bubble" in the top-right corner.
            Positioned(
              top: -48,
              right: -38,
              child: Container(
                width: 130,
                height: 130,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSizes.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Row(
            children: [
              Hero(
                tag: 'txn-avatar-${tx.id}',
                child: InitialsAvatar(
                  initials: tx.merchantInitials,
                  size: 38,
                  // White tile pops on the grey/pastel card in both themes.
                  background: AppColors.surface,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(tx.merchantName,
                              style: AppText.bodyStrong,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (tx.merchantVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 15),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(tx.code, style: AppText.caption),
                  ],
                ),
              ),
              StatusPill(
                label: tx.status.label,
                icon: tx.status.icon,
                background: AppColors.surface,
                foreground: tx.status.color,
                dense: true,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.productName,
                        style: AppText.title, overflow: TextOverflow.ellipsis),
                    if (tx.variant != null) ...[
                      const SizedBox(height: 2),
                      Text(tx.variant!, style: AppText.caption),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Money.format(tx.amount), style: AppText.title),
                  const SizedBox(height: 2),
                  Text('in escrow', style: AppText.caption),
                ],
              ),
            ],
          ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
