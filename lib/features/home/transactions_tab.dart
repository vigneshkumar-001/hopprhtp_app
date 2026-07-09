import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_messages.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../../widgets/transaction_card.dart';
import '../transaction/application/transactions_provider.dart';
import '../transaction/join_transaction_screen.dart';
import '../transaction/transaction_detail_screen.dart';

/// Reusable live list tab (used for Initiation & Transit in the bottom nav).
/// Filters the real, already-fetched [transactionsProvider] list down to the
/// given [statuses] — never demo/static data. Card tap always opens
/// [TransactionDetailScreen] with the real transaction id.
class TransactionsTab extends ConsumerWidget {
  const TransactionsTab({
    super.key,
    required this.title,
    required this.subtitle,
    required this.statuses,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.showJoinAction = false,
  });

  final String title;
  final String subtitle;
  final Set<ApiTxStatus> statuses;
  final String emptyTitle;
  final String emptySubtitle;

  /// Shows the "Enter Transaction Code" top action (buyer-side join flow).
  /// Only the Initiation tab passes this — Send now opens Create Transaction
  /// (seller-side) instead.
  final bool showJoinAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionsProvider);
    // A fetch failure goes to the shared snackbar, never an inline page
    // block — fires once per new error, not on every rebuild.
    ref.listen(transactionsProvider, (previous, next) {
      final err = next.error;
      if (err != null) {
        AppSnackbar.error(
          context,
          friendlyError(err),
          onRetry: () => ref.invalidate(transactionsProvider),
        );
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(transactionsProvider.notifier).refresh(),
          color: AppColors.ink,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPad,
              AppSizes.lg,
              AppSizes.screenPad,
              112,
            ),
            children: [
              Text(title, style: AppText.h1),
              const SizedBox(height: 4),
              Text(subtitle, style: AppText.body),
              const SizedBox(height: AppSizes.xl),
              if (showJoinAction) ...[
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: AppSizes.xs,
                  ),
                  child: MenuRow(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Enter Transaction Code',
                    subtitle: 'Enter the code shared by the seller.',
                    onTap: () =>
                        AppNav.push(context, const JoinTransactionScreen()),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
              ],
              txs.when(
                loading: () => const _TabListSkeleton(),
                error: (_, _) => const SizedBox.shrink(),
                data: (list) {
                  final filtered = list
                      .where((t) => statuses.contains(t.status))
                      .toList(growable: false);
                  if (filtered.isEmpty) {
                    return _TabEmptyState(
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                    );
                  }
                  return Column(
                    children: filtered
                        .asMap()
                        .entries
                        .map((e) {
                          final tx = EscrowTransaction.fromApi(e.value);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSizes.md),
                            child: TransactionCard(
                              tx: tx,
                              colorIndex: e.key,
                              productFirstLayout: true,
                              onTap: () => AppNav.push(
                                context,
                                TransactionDetailScreen(tx: tx),
                              ),
                            ),
                          );
                        })
                        .toList()
                        .staggerEnter(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.xxxl,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSizes.md),
          Text(title, style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text(subtitle, style: AppText.caption, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Three shimmer bones shaped like [TransactionCard] while the real list loads.
class _TabListSkeleton extends StatelessWidget {
  const _TabListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: AppSizes.md),
          child: _TabCardSkeleton(),
        ),
      ),
    );
  }
}

class _TabCardSkeleton extends StatelessWidget {
  const _TabCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppShimmerBox(width: 44, height: 44, radius: AppRadii.md),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppShimmerBox(width: 120, height: 14),
                    const SizedBox(height: 8),
                    AppShimmerBox(width: 72, height: 11, radius: AppRadii.sm),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              AppShimmerBox(width: 64, height: 22, radius: AppRadii.pill),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          AppShimmerBox(width: 96, height: 11, radius: AppRadii.sm),
        ],
      ),
    );
  }
}
