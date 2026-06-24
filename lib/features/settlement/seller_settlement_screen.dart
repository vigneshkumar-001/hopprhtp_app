import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../wallet/wallet_screen.dart';

/// Seller Settlement - payout released after a clean cooling period.
class SellerSettlementScreen extends StatelessWidget {
  const SellerSettlementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'Seller Settlement',
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'View in wallet',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () => AppNav.push(context, const WalletScreen()),
          ),
          const SizedBox(height: AppSizes.sm),
          GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Back to home',
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.lg),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color:
                    accent.isLime ? const Color(0xFF1F8A5B) : AppColors.ink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_rounded,
                color: AppColors.textOnDark,
                size: 32,
              ),
            ).popIn(),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Payout released', textAlign: TextAlign.center, style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text(
            'The cooling period ended with no dispute, so your settlement has been released.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          Center(
            child: AnimatedMoney(
              1230087,
              style: AppText.display.copyWith(fontSize: 34),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const Center(
            child: StatusPill(
              label: 'Sent to GTBank · ····6789',
              icon: Icons.account_balance_outlined,
              background: AppColors.surface,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SETTLEMENT SUMMARY',
                  style: AppText.caption.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3F4652),
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                _SettlementRow(
                  label: 'Item value',
                  value: Money.format(1230087),
                ),
                const SizedBox(height: AppSizes.sm),
                const _SettlementRow(
                  label: 'Delivery fee → dispatcher',
                  value: 'Paid on delivery',
                  mutedValue: true,
                ),
                const SizedBox(height: AppSizes.sm),
                const _SettlementRow(
                  label: 'Hoppr trust fee',
                  value: 'Retained',
                  mutedValue: true,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                _SettlementRow(
                  label: 'Released to you',
                  value: Money.format(1230087),
                  emphasized: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const _TrustScoreNote(),
        ],
      ),
    );
  }
}

class _SettlementRow extends StatelessWidget {
  const _SettlementRow({
    required this.label,
    required this.value,
    this.mutedValue = false,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool mutedValue;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final labelStyle = emphasized
        ? AppText.bodyStrong.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          )
        : AppText.body.copyWith(
            color: const Color(0xFF515866),
            fontWeight: FontWeight.w400,
          );
    final valueStyle = emphasized
        ? AppText.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          )
        : AppText.bodyStrong.copyWith(
            color: mutedValue ? AppColors.textTertiary : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          );

    return Row(
      children: [
        Expanded(child: Text(label, style: labelStyle)),
        const SizedBox(width: AppSizes.md),
        Text(value, style: valueStyle),
      ],
    );
  }
}

class _TrustScoreNote extends StatelessWidget {
  const _TrustScoreNote();

  @override
  Widget build(BuildContext context) {
    final isLime = AppAccent.of(context).isLime;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: isLime ? const Color(0xFFE4F3EA) : const Color(0xFFE9E9EA),
        borderRadius: AppRadii.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.caption.copyWith(
                  color: isLime
                      ? const Color(0xFF181A12)
                      : AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
                children: const [
                  TextSpan(text: 'Trust score '),
                  TextSpan(
                    text: '+2',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' · your HTP Verified standing improved with this clean transaction.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
