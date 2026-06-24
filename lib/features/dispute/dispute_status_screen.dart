import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/segmented_control.dart';
import '../transaction/widgets/transaction_widgets.dart';
import '../wallet/wallet_screen.dart';

class DisputeStatusScreen extends StatefulWidget {
  const DisputeStatusScreen({super.key});

  @override
  State<DisputeStatusScreen> createState() => _DisputeStatusScreenState();
}

class _DisputeStatusScreenState extends State<DisputeStatusScreen> {
  int _outcome = 0; // 0 buyer favoured, 1 seller favoured

  @override
  Widget build(BuildContext context) {
    final buyerFavoured = _outcome == 0;
    return AppScaffold(
      title: 'Dispute Status',
      bottomAction: AppButton(
        label: 'View in wallet',
        icon: Icons.account_balance_wallet_outlined,
        onPressed: () => AppNav.push(context, const WalletScreen()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            color: AppColors.surfaceMuted,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                      color: AppColors.ink, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      color: AppColors.textOnDark, size: 20),
                ),
                const SizedBox(width: AppSizes.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dispute resolved', style: AppText.h3),
                    const SizedBox(height: 2),
                    Text('Case #DSP-4471 · HTP-7Q2K', style: AppText.caption),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          ItemSummaryCard(
            product: 'MacBook Pro M2',
            subtitle: 'Category · Item not as described',
            amount: 0,
            trailing: const StatusPill(
              label: 'Closed',
              icon: Icons.check_rounded,
              dense: true,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Resolution timeline'),
                const SizedBox(height: AppSizes.md),
                const _TimelineRow(
                  icon: Icons.flag_outlined,
                  title: 'Dispute raised',
                  subtitle: 'Item not as described',
                ),
                const _TimelineRow(
                  icon: Icons.add_rounded,
                  title: 'Evidence under review',
                  subtitle: 'Hoppr Vision pre-screened · ops reviewing',
                ),
                _TimelineRow(
                  icon: Icons.verified_outlined,
                  title: 'Decision issued',
                  subtitle: buyerFavoured
                      ? 'Resolved in buyer\'s favour'
                      : 'Resolved in seller\'s favour',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          SegmentedControl(
            segments: const ['Buyer favoured', 'Seller favoured'],
            selected: _outcome,
            onChanged: (i) => setState(() => _outcome = i),
          ),
          const SizedBox(height: AppSizes.md),
          // Same premium dark card used on Home / Wallet / Profile.
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  buyerFavoured
                      ? 'Refunded to buyer wallet'
                      : 'Released to seller wallet',
                  style: AppText.caption
                      .copyWith(color: AppColors.textOnDarkMuted),
                ),
                const SizedBox(height: AppSizes.xs),
                AnimatedMoney(1237587, style: AppText.numeral),
                const SizedBox(height: AppSizes.sm),
                Text(
                  buyerFavoured
                      ? 'Escrow status FROZEN → SETTLED · item value + delivery returned to buyer'
                      : 'Escrow status FROZEN → SETTLED · funds released to the seller',
                  style: AppText.caption
                      .copyWith(color: AppColors.textOnDarkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                    color: AppColors.ink, shape: BoxShape.circle),
                child: Icon(icon, size: 15, color: AppColors.textOnDark),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: AppSizes.md),
          Padding(
            padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
