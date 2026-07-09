import 'package:flutter/material.dart';
import '../core/theme/app_accent.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/formatters.dart';
import '../data/models/models.dart';
import '../features/transaction/widgets/transaction_widgets.dart'
    show ProductThumb;
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
    this.productFirstLayout = false,
  });

  final EscrowTransaction tx;
  final VoidCallback? onTap;

  /// Position-based index so each card gets a consistent pastel tint.
  final int colorIndex;

  /// Alternate layout used on Home and Transaction History (Initiation /
  /// Transit keep the original layout unchanged):
  ///  - product name (bold) sits where the created-date used to be, and the
  ///    created-date moves down to where the product name used to be.
  ///  - the product photo is replaced by an initials avatar (no photo shown).
  final bool productFirstLayout;

  /// Selling/Buying chip driven by the per-transaction role. Null → no chip
  /// (legacy/demo rows with unknown role).
  Widget? _roleChip() => switch (tx.myRole) {
    'seller' => const StatusPill(
      label: 'Selling',
      icon: Icons.sell_outlined,
      dense: true,
      background: AppColors.ink,
      foreground: AppColors.textOnDark,
    ),
    'buyer' => const StatusPill(
      label: 'Buying',
      icon: Icons.shopping_bag_outlined,
      dense: true,
      background: AppColors.successSoft,
      foreground: AppColors.success,
    ),
    _ => null,
  };

  /// Buyer's short display text — shown only to the seller. The buyer's own
  /// counterpart (the seller) is already the card's prominent top line, so
  /// showing it again for the buyer would just be redundant clutter. Falls
  /// back to a masked phone, then a generic label — never blank.
  String? _buyerLine() {
    if (tx.myRole != 'seller') return null;
    final name = tx.buyerName?.trim();
    if (name != null && name.isNotEmpty) return 'Buyer: $name';
    final contact = tx.buyerContact?.trim();
    if (contact != null && contact.isNotEmpty) {
      return 'Buyer: ${_maskPhone(contact)}';
    }
    return 'Buyer: User';
  }

  static String _maskPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\s+'), '');
    if (digits.length <= 6) return digits;
    final middle = '*' * (digits.length - 7);
    return '${digits.substring(0, 4)}$middle${digits.substring(digits.length - 3)}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final tint = _cardTints[colorIndex % _cardTints.length];
    final roleChip = _roleChip();
    final buyerLine = _buyerLine();
    // Its own dedicated, full-width line — never sharing a line (and its
    // ellipsis budget) with the buyer text, so a long buyer name can never
    // push the date off and truncate it into "...".
    final dateLine = Dates.createdLabel(tx.createdAt);
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Normally the product being sold, not a generic
                      // merchant avatar — placeholder handled by ProductThumb
                      // itself when there's no photo. A dedicated tag (not
                      // shared with Transaction Details' seller-identity
                      // avatar) so no Hero flight tries to morph a photo into
                      // initials. The alternate layout instead shows the
                      // merchant's initials (no photo), and skips the Hero
                      // entirely so it never tries to fly between an
                      // initials tile here and a real photo on the Details
                      // screen.
                      if (productFirstLayout)
                        InitialsAvatar(
                          initials: InitialsAvatar.initialsFor(tx.merchantName),
                          size: 44,
                        )
                      else
                        Hero(
                          tag: 'txn-thumb-${tx.id}',
                          child: ProductThumb(
                            url: tx.productPhotoUrl,
                            size: 44,
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
                                  child: Text(
                                    tx.merchantName,
                                    style: AppText.bodyStrong,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (tx.merchantVerified) ...[
                                  const SizedBox(width: 4),
                                  const VerifiedBadge(size: 15),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(tx.code, style: AppText.caption),
                            if (buyerLine != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                buyerLine,
                                style: AppText.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          StatusPill(
                            label: tx.status.label,
                            icon: tx.status.icon,
                            background: AppColors.surface,
                            foreground: tx.status.color,
                            dense: true,
                          ),
                          if (roleChip != null) ...[
                            const SizedBox(height: 6),
                            roleChip,
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSizes.sm),
                  // Full card width to itself so it's always fully visible —
                  // never squeezed/ellipsized by the header row above.
                  // Swaps places with the product name below: here it shows
                  // the (bold) product name instead of the created date.
                  if (productFirstLayout)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.productName,
                          style: AppText.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (tx.variant != null) ...[
                          const SizedBox(height: 2),
                          Text(tx.variant!, style: AppText.caption),
                        ],
                      ],
                    )
                  else
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(dateLine, style: AppText.caption),
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
                        // Swapped with the row above: shows the created date
                        // here instead of the product name.
                        child: productFirstLayout
                            ? Row(
                                children: [
                                  const Icon(
                                    Icons.schedule_rounded,
                                    size: 13,
                                    color: AppColors.textTertiary,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      dateLine,
                                      style: AppText.caption,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tx.productName,
                                    style: AppText.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('in escrow', style: AppText.caption),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 14,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
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
