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
    final isNewMerchant = stats.completedTransactions == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            children: [
              InitialsAvatar(
                initials: InitialsAvatar.initialsFor(profile.name),
                size: 46,
              ),
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
              Center(child: TrustGauge(score: stats.trustScore, max: 1000)),
              const SizedBox(height: AppSizes.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    // Real backend score + category, always — plus a "New
                    // merchant" qualifier (there's room for it here) rather
                    // than ever hiding the number behind "New".
                    isNewMerchant
                        ? '${stats.trustScore} ${stats.trustCategory} · New merchant'
                        : '${stats.trustScore} ${stats.trustCategory}',
                    style: AppText.caption,
                  ),
                  const SizedBox(width: AppSizes.lg),
                  Text(
                    '${stats.completedTransactions} completed',
                    style: AppText.caption,
                  ),
                ],
              ),
              if (isNewMerchant) ...[
                const SizedBox(height: AppSizes.md),
                _NewMerchantNote(isOwner: profile.isOwner),
              ],
            ],
          ),
        ),
        if (profile.isOwner) ...[
          const SizedBox(height: AppSizes.md),
          const _ImproveScoreCard(),
          const SizedBox(height: AppSizes.md),
          const _ScoreHistoryCard(),
        ],
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
                    InitialsAvatar.initialsFor(
                      profile.recentTransactions[i].productName,
                    ),
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

/// Context for a still-at-default (600) score — different copy depending on
/// who's looking. Never shown once the merchant has any completed deal, since
/// the score is no longer just the registration default at that point.
class _NewMerchantNote extends StatelessWidget {
  const _NewMerchantNote({required this.isOwner});
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: isOwner
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StatusPill(
                  label: 'New merchant starting score',
                  icon: Icons.info_outline_rounded,
                  dense: true,
                ),
                const SizedBox(height: AppSizes.sm),
                Text(
                  'Newly registered merchants start at 600. The score '
                  'improves as secure transactions are completed successfully.',
                  style: AppText.caption,
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, size: 16),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'This seller is new on Hoppr. Escrow protection helps '
                    'keep the transaction secure.',
                    style: AppText.caption,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Merchant-facing only (see [MerchantProfile.isOwner]) — generic, always-true
/// guidance, not tied to the current score value.
class _ImproveScoreCard extends StatelessWidget {
  const _ImproveScoreCard();

  static const _tips = [
    'Complete escrow transactions successfully',
    'Deliver on time',
    'Avoid disputes',
    'Complete verification',
    'Upload delivery proof when required',
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('How to improve your score'),
          const SizedBox(height: AppSizes.md),
          for (final tip in _tips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(child: Text(tip, style: AppText.body)),
              ],
            ),
            if (tip != _tips.last) const SizedBox(height: AppSizes.sm),
          ],
        ],
      ),
    );
  }
}

/// Merchant-facing only. The backend has no score-history log today — only a
/// single live `trustScore` number (see common/utils/trustScore.ts) — so this
/// always renders an honest empty state rather than a fabricated breakdown or
/// timeline. Swap in a real list here if/when the backend ever persists one.
class _ScoreHistoryCard extends StatelessWidget {
  const _ScoreHistoryCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('Score history'),
          const SizedBox(height: AppSizes.md),
          const EmptyStateView(
            icon: Icons.history_rounded,
            title: 'No score history yet',
            subtitle:
                'This will appear here as you complete more transactions.',
          ),
        ],
      ),
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
