import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/merchant_dto.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/state_views.dart';
import '../../widgets/trust_gauge.dart';
import '../transaction/widgets/transaction_widgets.dart';

/// Merchant Profile — exact same layout as the original design (header card ·
/// trust gauge · two stat tiles · transaction history), now fed by
/// `GET /merchant/:id` instead of hardcoded demo values.
class MerchantProfileScreen extends ConsumerWidget {
  const MerchantProfileScreen({super.key, required this.merchantId});
  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantProfileProvider(merchantId));

    return AppScaffold(
      title: 'Merchant Profile',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AsyncValueView(
            value: async,
            onRetry: () => ref.invalidate(merchantProfileProvider(merchantId)),
            data: (profile) => _MerchantProfileBody(profile: profile),
          ),
        ],
      ),
    );
  }
}

class _MerchantProfileBody extends StatelessWidget {
  const _MerchantProfileBody({required this.profile});
  final MerchantProfile profile;

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  String get _verificationLabel => switch (profile.verificationStatus) {
    'verified' => 'Verified',
    'pending' => 'Pending review',
    'rejected' => 'Rejected',
    _ => 'Not verified',
  };

  IconData get _verificationIcon => switch (profile.verificationStatus) {
    'verified' => Icons.verified_outlined,
    'pending' => Icons.schedule_rounded,
    'rejected' => Icons.error_outline_rounded,
    _ => Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            children: [
              InitialsAvatar(initials: _initialsFor(profile.name), size: 46),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: AppText.h3),
                    const SizedBox(height: 2),
                    Text(
                      profile.joinedAt != null
                          ? 'Joined ${Dates.medium(profile.joinedAt!)}'
                          : 'Joined date not provided',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: _verificationLabel,
                icon: _verificationIcon,
                dense: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        AppCard(
          child: Column(
            children: [
              Text('Trust Score', style: AppText.caption),
              const SizedBox(height: AppSizes.sm),
              Center(child: TrustGauge(score: stats.trustScore)),
              const SizedBox(height: AppSizes.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Grade ${stats.trustGrade}', style: AppText.caption),
                  const SizedBox(width: AppSizes.lg),
                  Text(
                    '${stats.completedTransactions} completed',
                    style: AppText.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                icon: _verificationIcon,
                value: _verificationLabel,
                label: 'Verification',
              ),
            ),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: _MiniStatCard(
                icon: Icons.show_chart_rounded,
                value: '${stats.activeTransactions}',
                label: 'Active',
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
                    child: CardSectionLabel('Transaction history'),
                  ),
                  Text(
                    '${stats.completedTransactions} completed',
                    style: AppText.caption,
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              if (profile.recentTransactions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: EmptyStateView(
                    icon: Icons.receipt_long_rounded,
                    title: 'No completed transactions yet',
                  ),
                )
              else
                for (int i = 0; i < profile.recentTransactions.length; i++) ...[
                  if (i != 0) const Divider(height: AppSizes.xl),
                  _TxnRow(
                    _initialsFor(profile.recentTransactions[i].productName),
                    profile.recentTransactions[i].productName,
                    profile.recentTransactions[i].code,
                    Money.format(profile.recentTransactions[i].amountNaira),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.icon,
    required this.value,
    required this.label,
  });
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
              Text(
                code,
                style: AppText.caption.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        Text(amount, style: AppText.bodyStrong),
      ],
    );
  }
}
