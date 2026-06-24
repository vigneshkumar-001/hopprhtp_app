import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import 'after_payment_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Buyer Review & Payment — the buyer confirms the breakdown and pays into escrow.
class BuyerReviewScreen extends StatelessWidget {
  const BuyerReviewScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Buyer Review & Payment',
      bottomAction: AppButton(
        label: 'Pay into Escrow · ${Money.format(draft.grandTotal)}',
        icon: Icons.lock_outline_rounded,
        onPressed: () =>
            AppNav.push(context, AfterPaymentScreen(draft: draft)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            child: Row(
              children: [
                InitialsAvatar(
                    initials: 'YS',
                    size: 42,
                    background: const Color(0xFFE1DCF8)),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(draft.sellerName, style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Row(
                        children: const [
                          VerifiedBadge(size: 14),
                          SizedBox(width: 4),
                          Text('HTP Verified', style: AppText.caption),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle_outline_rounded, size: 22),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ItemSummaryCard(
            product: draft.productName,
            subtitle: 'Example · 512GB · Space grey',
            amount: draft.itemSubtotal,
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Payment composition'),
                const SizedBox(height: AppSizes.md),
                SummaryRow(
                    label: 'Item subtotal',
                    value: Money.format(draft.itemSubtotal)),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                    label: 'Delivery fee',
                    value: Money.format(draft.deliveryFee)),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                  label: 'Trust protection fee',
                  value: Money.format(draft.trustFull),
                  badge: const StatusPill(label: '1.5%', dense: true),
                ),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                  label: 'Fee split · Shared ${draft.feeSplit.label}',
                  value: '− ${Money.format(draft.sellerTrustShare)}',
                  valueColor: AppColors.textTertiary,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                SummaryRow(
                  label: 'Grand total payable',
                  value: Money.format(draft.grandTotal),
                  emphasized: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.shield_outlined,
            color: Color(0xFFF7EFD6),
            text:
                'Funds are secured by Hoppr Trust Protocol and released only after delivery confirmation.',
          ),
        ],
      ),
    );
  }
}
