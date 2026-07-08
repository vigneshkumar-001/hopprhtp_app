import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animated_refresh_icon_button.dart';
import '../../widgets/animations.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/transaction_card.dart';
import '../auth/application/auth_controller.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/transaction_history_screen.dart';
import '../transaction/create_transaction_screen.dart';
import '../transaction/application/transactions_provider.dart';
import '../transaction/join_transaction_screen.dart';
import '../transaction/transaction_detail_screen.dart';
import '../wallet/wallet_screen.dart';
import 'dashboard_stats.dart';

/// The Home dashboard (mockup 5).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onOpenProfile});

  /// Lets the bottom-nav switch to the profile tab instead of pushing a route.
  final VoidCallback? onOpenProfile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isRefreshing = false;

  /// Which Home transaction tab is selected — purely a client-side filter
  /// over the already-fetched [transactionsProvider] list (see [ApiTxStage]),
  /// so switching tabs is instant and never triggers an extra fetch.
  ApiTxStage _txTab = ApiTxStage.active;

  // Last real values seen, kept only so a transient reload/error never blanks
  // the stat cards to zero — always overwritten by fresh data the moment it
  // arrives. Never seeded with fake numbers; starts null (→ zero-state).
  DashboardStats? _lastStats;
  String? _lastTrustLabel;

  /// Pull-to-refresh: reloads the real transaction list (cached data stays
  /// visible while the request is in flight, no skeleton flicker — see
  /// [TransactionsNotifier.refresh]) and opportunistically refreshes other
  /// home-dashboard data if it's cached elsewhere in the app. Guarded against
  /// overlapping pulls; shows a retry snackbar only if the reload fails.
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await ref.read(transactionsProvider.notifier).refresh();
      if (!mounted) return;
      if (ref.read(transactionsProvider).hasError) {
        AppSnackbar.error(
          context,
          'Could not refresh transactions. Please try again.',
          onRetry: _onRefresh,
        );
      } else {
        // Best-effort: these are auto-dispose and safe to invalidate even when
        // nothing is currently watching them.
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(unreadNotificationsProvider);
      }
      // Trust score / deals / disputes live on the user profile, not the
      // transaction list — refresh it too so a just-completed deal's trust
      // bump shows up here without a full app restart.
      try {
        await ref.read(authControllerProvider.notifier).refreshProfile();
      } catch (_) {
        // Best-effort — the stat card just keeps showing the last known value.
      }
    } finally {
      _isRefreshing = false;
    }
  }

  // Always opens for real — the identity-verification gate runs INSIDE
  // CreateTransactionScreen itself (once it's actually on screen) so an
  // unverified user still sees the real screen first, blurred behind the
  // gate sheet, rather than being blocked before it even opens.
  void _createTransaction() =>
      AppNav.push(context, const CreateTransactionScreen());

  void _joinTransaction() =>
      AppNav.push(context, const JoinTransactionScreen());

  void _openWallet() => AppNav.push(context, const WalletScreen());
  void _openAlerts() => AppNav.push(context, const NotificationsScreen());
  void _openHistory() => AppNav.push(context, const TransactionHistoryScreen());

  /// "View All" from the Recent Transactions section — opens History
  /// pre-filtered to whichever tab (Active/Cooling/Done) is selected here.
  void _openHistoryForTab() =>
      AppNav.push(context, TransactionHistoryScreen(initialStage: _txTab));

  void _openProfile() {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
    } else {
      AppNav.push(context, const ProfileScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull?.user;
    final txs = ref.watch(transactionsProvider);

    // Real numbers only — computed from the same live transaction list
    // rendered below, so the cards never disagree with it. A transient
    // reload/error keeps showing the last real value instead of flashing to
    // zero; there is never a fabricated placeholder number.
    final freshStats = txs.valueOrNull == null
        ? null
        : DashboardStats.fromTransactions(txs.valueOrNull!);
    if (freshStats != null) _lastStats = freshStats;
    final stats = freshStats ?? _lastStats ?? DashboardStats.zero;

    final freshTrustLabel = user == null
        ? null
        : trustScoreLabel(deals: user.deals, trustScore: user.trustScore);
    if (freshTrustLabel != null) _lastTrustLabel = freshTrustLabel;
    final trustLabel = freshTrustLabel ?? _lastTrustLabel ?? 'New';

    // First load only — once any real data has ever arrived, refreshes never
    // show a skeleton again (matches the transaction list's own behaviour).
    final statsLoading = txs.isLoading && _lastStats == null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.ink,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPad,
              AppSizes.sm,
              AppSizes.screenPad,
              112,
            ),
            children: [
              _TopBar(
                firstName: user?.displayFirstName,
                onScan: _joinTransaction,
                onNotifications: _openAlerts,
              ),
              const SizedBox(height: AppSizes.lg),
              _BalanceCard(
                balance: stats.protectedNaira,
                active: stats.active,
                cooling: stats.cooling,
                trustScore: trustLabel,
                loading: statsLoading,
                hasError: txs.hasError,
                refreshing: txs.isLoading,
                onRetry: () => ref.invalidate(transactionsProvider),
              ),
              const SizedBox(height: AppSizes.lg),
              AppButton(
                label: 'Create Protected Transaction',
                icon: Icons.shield_outlined,
                onPressed: _createTransaction,
              ),
              const SizedBox(height: AppSizes.md),
              AppButton(
                label: 'Enter Transaction Code',
                icon: Icons.qr_code_scanner_rounded,
                variant: AppButtonVariant.soft,
                onPressed: _joinTransaction,
              ),
              const SizedBox(height: AppSizes.xl),
              _QuickActions(
                onMyTxns: _openHistory,
                onWallet: _openWallet,
                onProfile: _openProfile,
                onAlerts: _openAlerts,
              ),
              const SizedBox(height: AppSizes.xl),
              Row(
                children: [
                  Expanded(child: Text('Transactions', style: AppText.h3)),
                  GestureDetector(
                    onTap: _openHistoryForTab,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: AppText.bodyStrong.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.md),
              _TxTabBar(
                selected: _txTab,
                counts: {
                  for (final s in ApiTxStage.values)
                    s: (txs.valueOrNull ?? const [])
                        .where((t) => t.stage == s)
                        .length,
                },
                onSelect: (s) => setState(() => _txTab = s),
              ),
              const SizedBox(height: AppSizes.md),
              txs.when(
                loading: () => const _TransactionListSkeleton(),
                error: (e, _) => _ErrorState(
                  message: 'Could not load live transactions.',
                  onRetry: () => ref.invalidate(transactionsProvider),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return _EmptyState(onCreate: _createTransaction);
                  }
                  // Backend already sorts createdAt desc — the latest 10 for
                  // this tab are simply the first 10 that match its stage.
                  // Filters the already-fetched list (also used for the
                  // dashboard stat cards above) rather than a separate
                  // per-tab network call.
                  final tabItems = list
                      .where((t) => t.stage == _txTab)
                      .take(10)
                      .toList(growable: false);
                  if (tabItems.isEmpty) {
                    return _TabEmptyState(message: _emptyMessageFor(_txTab));
                  }
                  return Column(
                    children: tabItems
                        .asMap()
                        .entries
                        .map((e) {
                          final tx = EscrowTransaction.fromApi(e.value);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: AppSizes.md),
                            child: TransactionCard(
                              tx: tx,
                              colorIndex: e.key,
                              onTap: () => _openTx(context, tx),
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

  void _openTx(BuildContext context, EscrowTransaction tx) {
    AppNav.push(context, TransactionDetailScreen(tx: tx));
  }

  static String _emptyMessageFor(ApiTxStage stage) => switch (stage) {
    ApiTxStage.active => 'No active transactions',
    ApiTxStage.cooling => 'No cooling transactions',
    ApiTxStage.done => 'No completed transactions',
  };
}

/// Active / Cooling / Done tabs for the Home transaction section — a chip per
/// [ApiTxStage] with a live count badge, driving [_HomeScreenState._txTab].
class _TxTabBar extends StatelessWidget {
  const _TxTabBar({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final ApiTxStage selected;
  final Map<ApiTxStage, int> counts;
  final ValueChanged<ApiTxStage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final stage in ApiTxStage.values) ...[
          Expanded(
            child: _TxTabChip(
              label: stage.label,
              count: counts[stage] ?? 0,
              selected: stage == selected,
              onTap: () => onSelect(stage),
            ),
          ),
          if (stage != ApiTxStage.values.last)
            const SizedBox(width: AppSizes.sm),
        ],
      ],
    );
  }
}

class _TxTabChip extends StatelessWidget {
  const _TxTabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        curve: AppDurations.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surfaceMuted,
          borderRadius: AppRadii.pill,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(
                  color: selected
                      ? AppColors.textOnDark
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : AppColors.surface,
                borderRadius: AppRadii.pill,
              ),
              child: Text(
                '$count',
                style: AppText.caption.copyWith(
                  color: selected
                      ? AppColors.textOnDark
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.firstName,
    required this.onScan,
    required this.onNotifications,
  });

  /// Null while the profile hasn't loaded yet — shows the bare time-of-day
  /// greeting with no name, never a fake placeholder name.
  final String? firstName;
  final VoidCallback onScan;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final name = firstName;
    final greeting = greetingWordFor(DateTime.now());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name == null ? greeting : '$greeting,', style: AppText.body),
              if (name != null) ...[
                const SizedBox(height: 2),
                Text(name, style: AppText.h2),
              ],
            ],
          ),
        ),
        AppIconButton(icon: FeatherIcons.maximize, onTap: onScan),
        const SizedBox(width: AppSizes.sm),
        NotificationBell(onTap: onNotifications),
      ],
    );
  }
}

/// Shimmer tone tuned for the dark [PremiumCard] surface — a light card's
/// [AppShimmerBox] defaults (grey bone, white sweep) would barely read
/// against white text on ink, so the balance card passes these explicitly.
const Color _darkBoneColor = Color(0x26FFFFFF); // white @ 15%
const Color _darkBoneHighlight = Color(0x59FFFFFF); // white @ 35%

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.active,
    required this.cooling,
    required this.trustScore,
    this.loading = false,
    this.hasError = false,
    this.refreshing = false,
    this.onRetry,
  });

  final double balance;
  final int active;
  final int cooling;
  final String trustScore;

  /// First-load only (see `statsLoading` in `HomeScreen.build`). The card's
  /// premium chrome — dark gradient, glossy orb, "Protected in escrow" label
  /// — renders immediately either way; only the numbers that aren't known
  /// yet shimmer in place. Previously the whole card was wrapped in a
  /// generic Skeletonizer, which flattened the gradient into a plain grey
  /// box while leaving the decorative orb un-boned on top of it — these
  /// bones are shaped for this card specifically, so nothing looks broken.
  final bool loading;

  /// True when the underlying transaction fetch failed — the figures shown
  /// are still the last real values seen (never zeroed out), but a small
  /// refresh affordance lets the user retry without a full pull-to-refresh.
  final bool hasError;

  /// True while a reload is in flight — spins the inline Refresh glyph so the
  /// error-recovery tap reads as "fetching" rather than doing nothing.
  final bool refreshing;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Accent: lime in the Lime theme, white in Mono.
    final hi = AppAccent.of(context).highlight;
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 15,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.0,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    children: [
                      const TextSpan(text: 'Protected in '),
                      TextSpan(
                        text: 'escrow',
                        style: TextStyle(color: hi),
                      ),
                    ],
                  ),
                ),
              ),
              if (!loading && hasError && onRetry != null)
                GestureDetector(
                  onTap: refreshing ? null : onRetry,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRefreshIcon(
                        isLoading: refreshing,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        refreshing ? 'Refreshing…' : 'Refresh',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (loading)
            const AppShimmerBox(
              width: 168,
              height: 38,
              radius: BorderRadius.all(Radius.circular(10)),
              color: _darkBoneColor,
              highlightColor: _darkBoneHighlight,
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedMoney(
                balance,
                style: const TextStyle(
                  fontSize: 40,
                  height: 1.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.4,
                  color: Colors.white,
                ),
              ),
            ),
          Row(
            children: [
              loading
                  ? const _CardStatSkeleton()
                  : CardStat(value: '$active', label: 'Active'),
              const CardStatDivider(),
              loading
                  ? const _CardStatSkeleton()
                  : CardStat(value: '$cooling', label: 'Cooling'),
              const CardStatDivider(),
              loading
                  ? const _CardStatSkeleton()
                  : CardStat(
                      value: trustScore,
                      label: 'Trust score',
                      valueColor: hi,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mirrors [CardStat]'s two-line shape (value + label) with shimmer bones, so
/// the row's height never jumps once the real numbers land.
class _CardStatSkeleton extends StatelessWidget {
  const _CardStatSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppShimmerBox(
          width: 26,
          height: 20,
          radius: BorderRadius.all(Radius.circular(6)),
          color: _darkBoneColor,
          highlightColor: _darkBoneHighlight,
        ),
        SizedBox(height: 6),
        AppShimmerBox(
          width: 50,
          height: 11,
          radius: BorderRadius.all(Radius.circular(4)),
          color: _darkBoneColor,
          highlightColor: _darkBoneHighlight,
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onMyTxns,
    required this.onWallet,
    required this.onProfile,
    required this.onAlerts,
  });
  final VoidCallback onMyTxns;
  final VoidCallback onWallet;
  final VoidCallback onProfile;
  final VoidCallback onAlerts;

  @override
  Widget build(BuildContext context) {
    final items = [
      (FeatherIcons.activity, 'My Txns', onMyTxns),
      (FeatherIcons.creditCard, 'Wallet', onWallet),
      (FeatherIcons.user, 'Profile', onProfile),
      (FeatherIcons.bell, 'Alerts', onAlerts),
    ];
    return Row(
      children: [
        for (final (icon, label, onTap) in items)
          Expanded(
            child: _QuickAction(icon: icon, label: label, onTap: onTap),
          ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.accentSoft,
              borderRadius: AppRadii.md,
            ),
            child: Icon(icon, size: 22, color: accent.onAccentSoft),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppText.caption),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.xl),
      child: Column(
        children: [
          Text(message, style: AppText.body),
          const SizedBox(height: AppSizes.md),
          AppButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.xxl,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 36,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSizes.md),
          Text('No transactions yet', style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text(
            'Create your first secure escrow transaction.',
            style: AppText.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: 'Create Transaction',
            icon: Icons.shield_outlined,
            expand: false,
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

/// Shown when the overall transaction list has data but the selected tab
/// (Active/Cooling/Done) has none — a lighter message than [_EmptyState],
/// with no create-transaction call to action since the user already has deals.
class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.xxl,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.inbox_outlined,
            size: 36,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSizes.md),
          Text(message, style: AppText.bodyStrong),
        ],
      ),
    );
  }
}

/// Placeholder shown while live transactions load — three cards shaped like
/// the real [TransactionCard] layout, built from plain shimmer bones rather
/// than handing the real (pastel-gradient + blurred-orb) card to Skeletonizer
/// to auto-bone, which used to leave the decorative bubble showing through
/// un-shimmered next to flattened grey text blocks.
class _TransactionListSkeleton extends StatelessWidget {
  const _TransactionListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: AppSizes.md),
          child: _TransactionCardSkeleton(),
        ),
      ),
    );
  }
}

class _TransactionCardSkeleton extends StatelessWidget {
  const _TransactionCardSkeleton();

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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppShimmerBox(width: 140, height: 16),
                    const SizedBox(height: 6),
                    AppShimmerBox(width: 80, height: 11, radius: AppRadii.sm),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const AppShimmerBox(width: 70, height: 16),
                  const SizedBox(height: 6),
                  AppShimmerBox(width: 50, height: 11, radius: AppRadii.sm),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
