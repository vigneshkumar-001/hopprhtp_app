import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../dispute/dispute_center_screen.dart';
import '../settlement/seller_settlement_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Settlement & Resolution Ledger — the full money + status picture.
class SettlementLedgerScreen extends StatelessWidget {
  const SettlementLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Settlement & Resolution Ledger',
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'View seller settlement',
            icon: Icons.account_balance_outlined,
            onPressed: () =>
                AppNav.push(context, const SellerSettlementScreen()),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Open Dispute Center',
            icon: Icons.flag_outlined,
            variant: AppButtonVariant.soft,
            onPressed: () =>
                AppNav.push(context, const DisputeCenterScreen()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            color: AppColors.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.lg,
              vertical: AppSizes.md,
            ),
            child: const SizedBox(
              width: double.infinity,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, size: 22),
                  SizedBox(width: AppSizes.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top Status', style: AppText.caption),
                      SizedBox(height: 1),
                      Text(
                        'FUNDS_RELEASED',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Breakdown of payout'),
                const SizedBox(height: AppSizes.md),
                SummaryRow(
                    label: 'Item value → seller',
                    value: Money.format(1230087)),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                    label: 'Delivery fee → dispatcher',
                    value: Money.format(7500)),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                  label: 'Hoppr trust fee',
                  value: Money.format(18451.31),
                  badge: const StatusPill(
                    label: 'retained',
                    dense: true,
                    background: AppColors.surfaceMuted,
                    foreground: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PERSONALIZATION',
                  style: AppText.caption.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3F4652),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                _IconRow(
                  icon: Icons.verified_outlined,
                  label: 'HTP Verified badge',
                  trailing: const StatusPill(
                    label: 'Updated',
                    dense: true,
                    background: AppColors.surfaceMuted,
                    foreground: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                _IconRow(
                  icon: Icons.show_chart_rounded,
                  label: 'Trust score adjustment',
                  trailing: const StatusPill(
                    label: '+2 points',
                    dense: true,
                    background: AppColors.surfaceMuted,
                    foreground: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CardSectionLabel('Disputed'),
                  const SizedBox(height: AppSizes.sm),
                  Text(
                    'No active dispute',
                    style: AppText.body.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LEDGER FEED',
                  style: AppText.caption.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3F4652),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                _FeedRow(
                    label: 'Escrow funded', value: Money.format(1246812.66)),
                const SizedBox(height: AppSizes.md),
                const _FeedRow(label: 'Delivery confirmed'),
                const SizedBox(height: AppSizes.md),
                _FeedRow(
                    label: 'Funds released', value: Money.format(1230087)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow({required this.icon, required this.label, this.trailing});
  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textPrimary),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(
            label,
            style: AppText.bodyStrong.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.label, this.value});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFEDEDEE),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 14,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Text(
            label,
            style: AppText.bodyStrong.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (value != null)
          Text(
            value!,
            style: AppText.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
      ],
    );
  }
}
