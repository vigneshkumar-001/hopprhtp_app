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

/// Wallet — live balance, cooling settlement, and the recent ledger activity,
/// all from the `/wallet` API.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(walletBalanceProvider);

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
        error: (e, _) => SizedBox(
          height: 360,
          child: ErrorRetryView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(walletBalanceProvider),
          ),
        ),
        data: (balance) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSizes.sm),
            _WalletBalanceCard(balance: balance),
            const SizedBox(height: AppSizes.xxl),
            Text(
              'RECENT ACTIVITY',
              style: AppText.caption.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3F4652),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            const _LedgerSection(),
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

class _LedgerSection extends ConsumerWidget {
  const _LedgerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(walletLedgerProvider);
    return ledgerAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSizes.xxl),
        child: Center(child: AppCircularLoader(size: 24, strokeWidth: 2.5)),
      ),
      error: (e, _) => ErrorRetryView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(walletLedgerProvider),
      ),
      data: (page) {
        if (page.entries.isEmpty) {
          return const EmptyStateView(
            icon: Icons.account_balance_wallet_outlined,
            title: 'No activity yet',
            subtitle: 'Escrow funding, payouts and refunds will show up here.',
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

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});
  final WalletLedgerEntry entry;

  static (IconData, String) _meta(String type) => switch (type) {
    'escrow_funded' => (Icons.lock_outline_rounded, 'Secured in escrow'),
    'seller_payout' => (Icons.account_balance_outlined, 'Seller payout'),
    'delivery_payout' => (Icons.local_shipping_outlined, 'Delivery payout'),
    'buyer_refund' => (Icons.shield_outlined, 'Buyer refund'),
    'trust_fee' => (Icons.verified_user_outlined, 'Hoppr trust fee'),
    'withdrawal' => (Icons.south_rounded, 'Withdrawal'),
    'adjustment' => (Icons.tune_rounded, 'Adjustment'),
    _ => (Icons.receipt_long_outlined, 'Transaction'),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, title) = _meta(entry.type);
    final positive = entry.isCredit;
    final amount = '${positive ? '+' : '−'}${Money.format(entry.amountNaira)}';
    final subtitle = entry.createdAt != null
        ? '${entry.description} · ${Dates.relative(entry.createdAt!)}'
        : entry.description;

    return Padding(
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
        ],
      ),
    );
  }
}
