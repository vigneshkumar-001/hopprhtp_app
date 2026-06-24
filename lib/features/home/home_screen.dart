import 'package:flutter/material.dart';
import 'package:flutter_feather_icons/flutter_feather_icons.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/animations.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/premium_card.dart';
import '../../widgets/transaction_card.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/transaction_history_screen.dart';
import '../transaction/create_transaction_screen.dart';
import '../transaction/enter_transaction_code_screen.dart';
import '../transaction/transaction_detail_screen.dart';
import '../wallet/wallet_screen.dart';

/// The Home dashboard (mockup 5).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onOpenProfile});

  /// Lets the bottom-nav switch to the profile tab instead of pushing a route.
  final VoidCallback? onOpenProfile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TxStage _tab = TxStage.active;

  void _createTransaction() =>
      AppNav.push(context, const CreateTransactionScreen());

  void _enterTransactionCode() =>
      AppNav.push(context, const EnterTransactionCodeScreen());

  void _openWallet() => AppNav.push(context, const WalletScreen());
  void _openAlerts() => AppNav.push(context, const NotificationsScreen());
  void _openHistory() =>
      AppNav.push(context, const TransactionHistoryScreen());

  void _openProfile() {
    if (widget.onOpenProfile != null) {
      widget.onOpenProfile!();
    } else {
      AppNav.push(context, const ProfileScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final user = state.user;
    final list = state.byStage(_tab);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(
              AppSizes.screenPad, AppSizes.sm, AppSizes.screenPad, 112),
          children: [
            _TopBar(
              name: user?.firstName ?? 'there',
              onScan: _enterTransactionCode,
              onNotifications: _openAlerts,
            ),
            const SizedBox(height: AppSizes.lg),
            _BalanceCard(
              balance: user?.escrowBalance ?? 0,
              active: state.activeCount,
              cooling: state.coolingCount,
              trustScore: user?.trustScore ?? 'A+',
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
              onPressed: _enterTransactionCode,
            ),
            const SizedBox(height: AppSizes.xl),
            _QuickActions(
              onMyTxns: _openHistory,
              onWallet: _openWallet,
              onProfile: _openProfile,
              onAlerts: _openAlerts,
            ),
            const SizedBox(height: AppSizes.xl),
            _StageTabs(
              selected: _tab,
              onChanged: (s) => setState(() => _tab = s),
            ),
            const SizedBox(height: AppSizes.lg),
            if (list.isEmpty)
              _EmptyState(stage: _tab)
            else
              // Cards stagger in — and replay each time you switch the tab.
              ...list
                  .asMap()
                  .entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSizes.md),
                        child: TransactionCard(
                          tx: e.value,
                          colorIndex: e.key,
                          onTap: () => _openTx(context, e.value),
                        ),
                      ))
                  .toList()
                  .staggerEnter(),
          ],
        ),
      ),
    );
  }

  void _openTx(BuildContext context, EscrowTransaction tx) {
    AppNav.push(context, TransactionDetailScreen(tx: tx));
  }
}

// ---------------------------------------------------------------------------
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.name,
    required this.onScan,
    required this.onNotifications,
  });
  final String name;
  final VoidCallback onScan;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Good morning,', style: AppText.body),
              const SizedBox(height: 2),
              Text(name, style: AppText.h2),
            ],
          ),
        ),
        AppIconButton(icon: FeatherIcons.maximize, onTap: onScan),
        const SizedBox(width: AppSizes.sm),
        AppIconButton(icon: FeatherIcons.bell, onTap: onNotifications),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.active,
    required this.cooling,
    required this.trustScore,
  });

  final double balance;
  final int active;
  final int cooling;
  final String trustScore;

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
              Icon(Icons.shield_outlined,
                  size: 15, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 7),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  children: [
                    const TextSpan(text: 'Protected in '),
                    TextSpan(text: 'escrow', style: TextStyle(color: hi)),
                  ],
                ),
              ),
            ],
          ),
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
              CardStat(value: '$active', label: 'Active'),
              const CardStatDivider(),
              CardStat(value: '$cooling', label: 'Cooling'),
              const CardStatDivider(),
              CardStat(value: trustScore, label: 'Trust score', valueColor: hi),
            ],
          ),
        ],
      ),
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

class _StageTabs extends StatelessWidget {
  const _StageTabs({required this.selected, required this.onChanged});
  final TxStage selected;
  final ValueChanged<TxStage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final stage in TxStage.values)
          Padding(
            padding: const EdgeInsets.only(right: AppSizes.sm),
            child: _TabChip(
              label: stage.label,
              selected: stage == selected,
              onTap: () => onChanged(stage),
            ),
          ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg, vertical: AppSizes.sm),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppAccent.of(context).muted,
          borderRadius: AppRadii.pill,
        ),
        child: Text(
          label,
          style: AppText.label.copyWith(
            color: selected ? AppColors.textOnDark : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.stage});
  final TxStage stage;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg, vertical: AppSizes.xxl),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined,
              size: 36, color: AppColors.textTertiary),
          const SizedBox(height: AppSizes.md),
          Text('No ${stage.label.toLowerCase()} transactions',
              style: AppText.bodyStrong),
          const SizedBox(height: 4),
          Text('They\'ll show up here once you have some.',
              style: AppText.caption),
        ],
      ),
    );
  }
}

