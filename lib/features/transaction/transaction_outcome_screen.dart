import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
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
import 'widgets/transaction_widgets.dart';

/// Transaction Outcome — the delivery window expired and escrow auto-liquidated.
class TransactionOutcomeScreen extends StatelessWidget {
  const TransactionOutcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Transaction Outcome',
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'View refund in wallet',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () => AppNav.push(context, const WalletScreen()),
          ),
          const SizedBox(height: AppSizes.sm),
          GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Back to home',
                  style: AppText.bodyStrong
                      .copyWith(color: AppColors.textSecondary)),
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
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.schedule_rounded, size: 32),
            ).popIn(),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Delivery window expired',
              textAlign: TextAlign.center, style: AppText.h1),
          const SizedBox(height: AppSizes.md),
          const Center(
            child: StatusPill(
              label: 'UNDELIVERABLE',
              icon: Icons.info_outline_rounded,
              dense: true,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            'The delivery OTP stayed valid for 7 days and expired without a confirmed delivery. Hoppr safely liquidated the escrow and refunded you automatically.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          ItemSummaryCard(
            product: 'MacBook Pro M2',
            subtitle: 'Yemi Stores · HTP-LGS-8881',
            amount: 0,
            trailing: const StatusPill(
              label: 'Expired',
              icon: Icons.schedule_rounded,
              dense: true,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Escrow liquidation'),
                const SizedBox(height: AppSizes.md),
                SummaryRow(label: 'Escrow held', value: Money.format(1256038.31)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                _LiqRow(
                  icon: Icons.shield_outlined,
                  title: 'Hoppr Trust Protection Fee',
                  subtitle: 'Permanently retained',
                  amount: '− ${Money.format(18451.31)}',
                ),
                const SizedBox(height: AppSizes.md),
                _LiqRow(
                  icon: Icons.account_balance_outlined,
                  title: 'Seller Inconvenience Fee',
                  subtitle: 'Rule-based · credited to seller',
                  amount: '− ${Money.format(24601.74)}',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                SummaryRow(
                  label: 'Refunded to you',
                  value: Money.format(1256038.31 - 18451.31 - 24601.74),
                  emphasized: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiqRow extends StatelessWidget {
  const _LiqRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadii.sm,
          ),
          child: Icon(icon, size: 18),
        ),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(subtitle, style: AppText.caption),
            ],
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Text(amount, style: AppText.bodyStrong),
      ],
    );
  }
}
