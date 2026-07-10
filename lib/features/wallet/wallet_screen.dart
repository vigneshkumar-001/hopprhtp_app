import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/user_dto.dart';
import '../../data/dto/wallet_dto.dart';
import '../../widgets/animated_refresh_icon_button.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/blur_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../../widgets/premium_card.dart';
import '../auth/application/auth_controller.dart';
import '../profile/payout_accounts_screen.dart';
import '../transaction/widgets/transaction_widgets.dart';

/// Wallet — live balance, cooling settlement, and the recent ledger activity,
/// all from the `/wallet` API.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  // Recent Activity opens on the current month by default — the most useful
  // default for most users, rather than an unbounded "All" fetch.
  WalletActivityFilter _filter = WalletActivityFilter.thisMonth();

  Future<void> _openFilterSheet() async {
    final picked = await showBlurredSheet<WalletActivityFilter>(
      context,
      builder: (ctx) => _ActivityFilterSheet(selected: _filter),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    // A fetch failure goes to the shared snackbar, never an inline page
    // block — fires once per new error, not on every rebuild.
    ref.listen(walletBalanceProvider, (previous, next) {
      final err = next.error;
      if (err != null) {
        AppSnackbar.error(
          context,
          friendlyError(err),
          onRetry: () => ref.invalidate(walletBalanceProvider),
        );
      }
    });

    return AppScaffold(
      title: 'Wallet',
      // Spins only while the balance is actually refetching; taps are ignored
      // mid-fetch so a refresh can't be queued twice. The `.when` below keeps
      // showing the cached balance during the reload (skipLoadingOnRefresh),
      // so there's no full-page loader flicker on manual refresh.
      trailing: AnimatedRefreshIconButton(
        isLoading: balanceAsync.isLoading,
        onPressed: () {
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(walletLedgerProvider);
        },
      ),
      body: balanceAsync.when(
        loading: () => const SizedBox(
          height: 360,
          child: Center(child: AppCircularLoader()),
        ),
        error: (_, _) => const SizedBox.shrink(),
        data: (balance) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSizes.sm),
            _WalletBalanceCard(balance: balance),
            const SizedBox(height: AppSizes.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RECENT ACTIVITY',
                  style: AppText.caption.copyWith(
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3F4652),
                  ),
                ),
                _ActivityFilterButton(
                  selected: _filter,
                  onTap: _openFilterSheet,
                ),
              ],
            ),
            const SizedBox(height: AppSizes.md),
            _LedgerSection(filter: _filter),
            const SizedBox(height: AppSizes.xl),
            Center(
              child: Text(
                'Wallet ledger · escrow, payouts & refunds',
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact pill button showing the active Recent Activity filter — tapping it
/// opens [_ActivityFilterSheet]. Replaces the old always-visible chip/tab row
/// with a single, clear "this is what you're looking at" affordance.
class _ActivityFilterButton extends StatelessWidget {
  const _ActivityFilterButton({required this.selected, required this.onTap});

  final WalletActivityFilter selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = selected.label == 'Custom'
        ? '${Dates.short(selected.from!)} – ${Dates.short(selected.to!)}'
        : selected.label;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 8, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadii.pill,
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.tune_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppText.label.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing every Recent Activity date filter — Today, Yesterday,
/// Last week, This month (the default) and a Custom range. Purely a
/// client-side selector; the actual filtering happens server-side (see
/// [walletLedgerProvider]), so the list is never fetched then re-filtered.
/// Pops with the chosen [WalletActivityFilter], or null if dismissed.
class _ActivityFilterSheet extends StatelessWidget {
  const _ActivityFilterSheet({required this.selected});

  final WalletActivityFilter selected;

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 6)),
        end: now,
      ),
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(
      context,
    ).pop(WalletActivityFilter.range(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = selected.label == 'Custom';
    final options = <(IconData, WalletActivityFilter)>[
      (Icons.today_rounded, WalletActivityFilter.today()),
      (Icons.event_outlined, WalletActivityFilter.yesterday()),
      (Icons.date_range_rounded, WalletActivityFilter.lastWeek()),
      (Icons.calendar_view_month_rounded, WalletActivityFilter.thisMonth()),
      (Icons.all_inclusive_rounded, WalletActivityFilter.all),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter by date', style: AppText.h2),
          const SizedBox(height: 4),
          Text(
            'Choose a range to narrow down your wallet activity.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          for (final (icon, filter) in options)
            _FilterOptionTile(
              icon: icon,
              label: filter.label,
              selected: !isCustom && selected == filter,
              onTap: () => Navigator.of(context).pop(filter),
            ),
          _FilterOptionTile(
            icon: Icons.calendar_today_outlined,
            label: isCustom
                ? '${Dates.short(selected.from!)} – ${Dates.short(selected.to!)}'
                : 'Custom date range',
            selected: isCustom,
            trailing: const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
            onTap: () => _pickCustomRange(context),
          ),
        ],
      ),
    );
  }
}

class _FilterOptionTile extends StatelessWidget {
  const _FilterOptionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Material(
        color: selected ? AppColors.ink : AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.md,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.bodyStrong.copyWith(
                      color: selected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerSection extends ConsumerWidget {
  const _LedgerSection({required this.filter});
  final WalletActivityFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(walletLedgerProvider(filter));
    // A fetch failure goes to the shared snackbar, never an inline page
    // block — fires once per new error, not on every rebuild.
    ref.listen(walletLedgerProvider(filter), (previous, next) {
      final err = next.error;
      if (err != null) {
        AppSnackbar.error(
          context,
          friendlyError(err),
          onRetry: () => ref.invalidate(walletLedgerProvider(filter)),
        );
      }
    });
    return ledgerAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.xxl),
        child: Center(child: AppCircularLoader(size: 24, strokeWidth: 2.5)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (page) {
        if (page.entries.isEmpty) {
          return EmptyStateView(
            icon: Icons.account_balance_wallet_outlined,
            title: filter.isAll
                ? 'No activity yet'
                : 'No activity in this range',
            subtitle: filter.isAll
                ? 'Escrow funding, payouts and refunds will show up here.'
                : 'Try a different date range, or switch back to All.',
          );
        }
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.lg,
            vertical: AppSizes.xs,
          ),
          child: Column(
            children: [
              for (int i = 0; i < page.entries.length; i++) ...[
                _ActivityRow(entry: page.entries[i]),
                if (i != page.entries.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard({required this.balance});
  final WalletBalance balance;

  @override
  Widget build(BuildContext context) {
    final hi = AppAccent.of(context).highlight;
    final muted = Colors.white.withValues(alpha: 0.68);

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: muted,
              ),
              const SizedBox(width: 7),
              Text(
                'Available balance',
                style: TextStyle(
                  fontSize: 14,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: muted,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              balance.availableNaira,
              style: const TextStyle(
                fontSize: 35,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.3,
                color: Colors.white,
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14, color: muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                    children: [
                      TextSpan(
                        text: Money.format(balance.coolingNaira),
                        style: TextStyle(
                          color: hi,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' in cooling settlement'),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _WalletCardAction(
                  label: 'Withdraw',
                  icon: Icons.file_download_outlined,
                  filled: true,
                  onPressed: () => _showWithdrawSheet(context, balance),
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _WalletCardAction(
                  label: 'Accounts',
                  icon: Icons.account_balance_outlined,
                  onPressed: () =>
                      AppNav.push(context, const PayoutAccountsScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void _showWithdrawSheet(BuildContext context, WalletBalance balance) {
  showBlurredSheet(
    context,
    builder: (ctx) => _WithdrawSheet(rootContext: context, balance: balance),
  );
}

class _WithdrawSheet extends ConsumerStatefulWidget {
  const _WithdrawSheet({required this.rootContext, required this.balance});

  final BuildContext rootContext;
  final WalletBalance balance;

  @override
  ConsumerState<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<_WithdrawSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: Money.format(widget.balance.availableNaira, symbol: false),
  );
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm(PayoutAccount account) async {
    final raw = _amount.text.replaceAll(',', '').trim();
    final value = double.tryParse(raw) ?? 0;
    if (value <= 0) {
      AppSnackbar.error(widget.rootContext, 'Enter an amount to withdraw.');
      return;
    }
    if (value > widget.balance.availableNaira) {
      AppSnackbar.error(widget.rootContext, 'Amount exceeds your balance.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(walletRepositoryProvider)
          .withdraw(amountNaira: value, accountId: account.id);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletLedgerProvider);
      if (mounted) Navigator.of(context).pop();
      if (widget.rootContext.mounted) {
        AppSnackbar.success(
          widget.rootContext,
          'Withdrawal of ${Money.format(value)} started to ${account.bank}.',
        );
      }
    } on ApiException catch (e) {
      if (widget.rootContext.mounted) {
        AppSnackbar.error(widget.rootContext, e.userMessage);
      }
    } catch (_) {
      if (widget.rootContext.mounted) {
        AppSnackbar.error(
          widget.rootContext,
          'Could not start the withdrawal. Please try again.',
        );
      }
    } finally {
      // Unconditional — without this, any non-ApiException failure left the
      // button spinning forever with no way to retry.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref
        .watch(authControllerProvider)
        .valueOrNull
        ?.user
        ?.defaultPayoutAccount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Withdraw funds', style: AppText.h2),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Move money from your Hoppr wallet to your bank account.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          if (account == null)
            _NoAccount(rootContext: widget.rootContext)
          else ...[
            _AccountTile(account: account),
            const SizedBox(height: AppSizes.md),
            _AmountField(
              controller: _amount,
              onSubmit: () => _confirm(account),
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Confirm withdrawal',
              icon: Icons.check_rounded,
              loading: _busy,
              onPressed: () => _confirm(account),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoAccount extends StatelessWidget {
  const _NoAccount({required this.rootContext});
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: AppRadii.card,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_outlined,
                size: 22,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Text(
                  'Add a payout account to withdraw your funds.',
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        AppButton(
          label: 'Add payout account',
          icon: Icons.add_rounded,
          onPressed: () {
            Navigator.of(context).pop();
            AppNav.push(rootContext, const PayoutAccountsScreen());
          },
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});
  final PayoutAccount account;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.card,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.md,
            ),
            child: const Icon(Icons.account_balance_outlined, size: 20),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${account.bank} · •••• ${account.accountNumberLast4}',
                  style: AppText.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(account.accountName, style: AppText.caption),
              ],
            ),
          ),
          if (account.isDefault) ...[
            const SizedBox(width: AppSizes.sm),
            const StatusPill(label: 'Default', dense: true),
          ],
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.lg,
        vertical: AppSizes.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style: AppText.label.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                Money.naira,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsFormatter()],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '0',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletCardAction extends StatelessWidget {
  const _WalletCardAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.textPrimary : AppColors.textOnDark;
    final filledBg = AppAccent.of(context).isLime
        ? const Color(0xFFCBF24A)
        : AppColors.surface;

    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? filledBg : Colors.white.withValues(alpha: 0.07),
          borderRadius: AppRadii.md,
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppText.button.copyWith(
                color: fg,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Recent Activity row — tappable (ripple feedback) to open
/// [_ActivityDetailsSheet] with the full plain-language explanation.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final WalletLedgerEntry entry;

  /// Icon only — the title/description are backend-enriched (see
  /// [WalletLedgerEntry.title]) and never re-derived here. Direction-aware
  /// where the same [type] means something different as a credit vs a debit
  /// (e.g. delivery_payout: dispatcher earning vs a fee deducted from a
  /// seller's payout).
  static IconData _icon(String type, bool credit) => switch (type) {
    'escrow_funded' =>
      credit ? Icons.lock_outline_rounded : Icons.lock_open_outlined,
    'seller_payout' => Icons.account_balance_outlined,
    'delivery_payout' => Icons.local_shipping_outlined,
    'buyer_refund' => Icons.shield_outlined,
    'trust_fee' => Icons.verified_user_outlined,
    'withdrawal' => Icons.south_rounded,
    'adjustment' => Icons.tune_rounded,
    _ => Icons.receipt_long_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final positive = entry.isCredit;
    final icon = _icon(entry.type, positive);
    final title = entry.title ?? entry.description;
    final amount = '${positive ? '+' : '−'}${Money.format(entry.amountNaira)}';
    final subtitle = entry.createdAt != null
        ? '${entry.description} · ${Dates.relative(entry.createdAt!)}'
        : entry.description;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showActivityDetailsSheet(context, entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
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
                    Text(
                      subtitle,
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(
                amount,
                style: AppText.bodyStrong.copyWith(
                  color: positive ? AppColors.success : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the Activity Details bottom sheet for [entry]. Opens instantly from
/// already-fetched list data when it's fully enriched (the common case —
/// every current API response is); only falls back to a fetch (with a brief
/// loading state) for a legacy/partial shape.
void showActivityDetailsSheet(BuildContext context, WalletLedgerEntry entry) {
  showBlurredSheet(
    context,
    builder: (ctx) => _ActivityDetailsSheet(entry: entry),
  );
}

class _ActivityDetailsSheet extends ConsumerStatefulWidget {
  const _ActivityDetailsSheet({required this.entry});
  final WalletLedgerEntry entry;

  @override
  ConsumerState<_ActivityDetailsSheet> createState() =>
      _ActivityDetailsSheetState();
}

class _ActivityDetailsSheetState extends ConsumerState<_ActivityDetailsSheet> {
  late WalletLedgerEntry _entry = widget.entry;
  bool _loading = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // Only the rare partial/legacy shape needs a fetch — every entry the
    // current API returns already has everything this sheet shows.
    if (!_entry.hasFullDetails) _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() => _loading = true);
    try {
      final full = await ref
          .read(walletRepositoryProvider)
          .ledgerEntry(_entry.id);
      if (mounted) setState(() => _entry = full);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.xxl * 2),
        child: Center(child: AppCircularLoader()),
      );
    }

    final e = _entry;
    final positive = e.isCredit;
    final amount = '${positive ? '+' : '−'}${Money.format(e.amountNaira)}';
    final hasBreakdown = e.platformFeeKobo != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(e.title ?? e.description, style: AppText.h2),
              ),
              StatusPill(
                label: _statusLabel(e.status),
                background: AppColors.successSoft,
                foreground: AppColors.success,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            amount,
            style: AppText.h1.copyWith(
              color: positive ? AppColors.success : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          if (e.createdAt != null)
            _DetailRow(
              icon: Icons.schedule_rounded,
              label: 'Date & time',
              value: Dates.createdLabel(e.createdAt),
            ),
          if (e.reference != null)
            _DetailRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Transaction reference',
              value: e.reference!,
            ),
          if (e.productName != null)
            _DetailRow(
              icon: Icons.inventory_2_outlined,
              label: 'Product',
              value: e.productName!,
            ),
          if (e.sourceLabel != null)
            _DetailRow(
              icon: Icons.call_made_rounded,
              label: 'Source',
              value: e.sourceLabel!,
            ),
          if (e.destinationLabel != null)
            _DetailRow(
              icon: Icons.call_received_rounded,
              label: 'Destination',
              value: e.destinationLabel!,
            ),
          const SizedBox(height: AppSizes.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSizes.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why this happened', style: AppText.bodyStrong),
                const SizedBox(height: 6),
                Text(
                  _loadFailed
                      ? 'Details are not available for this activity yet.'
                      : e.description.isEmpty
                      ? 'Details are not available for this activity yet.'
                      : e.description,
                  style: AppText.body,
                ),
              ],
            ),
          ),
          if (hasBreakdown) ...[
            const SizedBox(height: AppSizes.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSizes.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadii.card,
                border: Border.all(color: AppColors.border, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Breakdown', style: AppText.bodyStrong),
                  const SizedBox(height: AppSizes.md),
                  if (e.productAmountKobo != null)
                    SummaryRow(
                      label: 'Product Amount',
                      value: Money.format(e.productAmountNaira ?? 0),
                    ),
                  const SizedBox(height: AppSizes.sm),
                  SummaryRow(
                    label: 'Platform Fee',
                    value: Money.format(e.platformFeeNaira ?? 0),
                  ),
                  if (e.sellerReceivableAmountNaira != null) ...[
                    const SizedBox(height: AppSizes.sm),
                    SummaryRow(
                      label: 'Seller Receives',
                      value: Money.format(e.sellerReceivableAmountNaira!),
                      emphasized: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) => status.isEmpty
      ? 'Completed'
      : status[0].toUpperCase() + status.substring(1);
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.caption),
                const SizedBox(height: 2),
                Text(value, style: AppText.bodyStrong),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
