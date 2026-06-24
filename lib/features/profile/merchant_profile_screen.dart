import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/trust_gauge.dart';
import '../transaction/widgets/transaction_widgets.dart';

class MerchantProfileScreen extends StatelessWidget {
  const MerchantProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Merchant Profile',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            child: Row(
              children: [
                InitialsAvatar(initials: 'YS', size: 46),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yemi Stores', style: AppText.h3),
                      const SizedBox(height: 2),
                      Text('HTP-LGS-8881',
                          style: AppText.caption
                              .copyWith(fontFamily: 'monospace')),
                    ],
                  ),
                ),
                const StatusPill(
                  label: 'Verified',
                  icon: Icons.verified_outlined,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              children: [
                Text('Clean Trust Score', style: AppText.caption),
                const SizedBox(height: AppSizes.sm),
                const Center(child: TrustGauge(score: 91)),
                const SizedBox(height: AppSizes.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Metadata +${Money.format(217100)}',
                        style: AppText.caption),
                    const SizedBox(width: AppSizes.lg),
                    Text('Gauges Healthy', style: AppText.caption),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: const [
              Expanded(
                child: _MiniStatCard(
                  icon: Icons.verified_outlined,
                  value: 'Verified',
                  label: 'Verification',
                ),
              ),
              SizedBox(width: AppSizes.md),
              Expanded(
                child: _MiniStatCard(
                  icon: Icons.show_chart_rounded,
                  value: '4.8 / 5',
                  label: 'Review score',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: CardSectionLabel('Transaction history')),
                    Text('128 completed', style: AppText.caption),
                  ],
                ),
                const SizedBox(height: AppSizes.md),
                const _TxnRow('MA', 'Linen Two-Piece Set', 'HTP-7Q2K', '₦51,220'),
                const Divider(height: AppSizes.xl),
                const _TxnRow(
                    'TH', 'Wireless Earbuds Pro', 'HTP-3M8X', '₦68,975'),
                const Divider(height: AppSizes.xl),
                const _TxnRow('BF', 'Fresh Rose Bouquet', 'HTP-9F4L', '₦17,233'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
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
          const SizedBox(height: AppSizes.md),
          Text(value, style: AppText.h3),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption),
        ],
      ),
    );
  }
}

class _TxnRow extends StatelessWidget {
  const _TxnRow(this.initials, this.product, this.code, this.amount);
  final String initials;
  final String product;
  final String code;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InitialsAvatar(initials: initials, size: 38),
        const SizedBox(width: AppSizes.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(code,
                  style: AppText.caption.copyWith(fontFamily: 'monospace')),
            ],
          ),
        ),
        Text(amount, style: AppText.bodyStrong),
      ],
    );
  }
}
