import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/blur_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/premium_card.dart';
import '../profile/payout_accounts_screen.dart';
import '../transaction/transaction_outcome_screen.dart';

/// Wallet — balance, cooling settlement, recent ledger activity.
class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Wallet',
      trailing: const AppIconButton(icon: Icons.more_horiz_rounded),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          const _WalletBalanceCard(),
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
          AppCard(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.lg, vertical: AppSizes.xs),
            child: Column(
              children: [
                const _ActivityRow(
                  icon: Icons.account_balance_outlined,
                  title: 'Seller payout received',
                  subtitle: 'Yemi Stores · HTP-LGS-8881 · Today, 2:14 PM',
                  amount: '+₦1,230,087.00',
                  positive: true,
                ),
                const Divider(height: 1),
                _ActivityRow(
                  icon: Icons.shield_outlined,
                  title: 'Buyer refund',
                  subtitle: 'Order expired · HTP-7Q2K · Yesterday',
                  amount: '+₦51,220.00',
                  positive: true,
                  onTap: () => AppNav.push(
                      context, const TransactionOutcomeScreen()),
                ),
                const Divider(height: 1),
                const _ActivityRow(
                  icon: Icons.south_rounded,
                  title: 'Withdrawal to GTBank',
                  subtitle: '···· 6789 · 12 May 2025',
                  amount: '−₦500,000.00',
                  positive: false,
                ),
                const Divider(height: 1),
                const _ActivityRow(
                  icon: Icons.shield_outlined,
                  title: 'Hoppr trust fee',
                  subtitle: 'Retained · HTP-3M8X · 10 May 2025',
                  amount: '−₦18,451.31',
                  positive: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Text('Wallet ledger · escrow, payouts & refunds',
                style: AppText.caption),
          ),
        ],
      ),
    );
  }
}

class _WalletBalanceCard extends StatelessWidget {
  const _WalletBalanceCard();

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
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: muted,
                  ),
                  children: [
                    const TextSpan(text: 'Available '),
                    TextSpan(
                      text: 'balance',
                      // style: TextStyle(color: hi),
                    ),
                  ],
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              1212985.26,
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
                        text: Money.format(1230087),
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
                  onPressed: () => _showWithdrawSheet(context),
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

/// Animated bottom sheet (blurred backdrop) to withdraw to the default bank.
void _showWithdrawSheet(BuildContext context) {
  showBlurredSheet(
    context,
    builder: (ctx) => _WithdrawSheet(rootContext: context),
  );
}

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.rootContext});

  /// The screen context — used for the snackbar after the sheet is dismissed.
  final BuildContext rootContext;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amount = TextEditingController(text: '500,000.00');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _confirm() {
    Navigator.of(context).pop();
    final value = _amount.text.trim();
    ScaffoldMessenger.of(widget.rootContext).showSnackBar(
      SnackBar(
        content: Text(value.isEmpty
            ? 'Withdrawal started'
            : 'Withdrawal of ${Money.naira}$value started'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.xl, AppSizes.md, AppSizes.xl, AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Withdraw funds', style: AppText.h2),
          const SizedBox(height: AppSizes.sm),
          Text('Move money from your Hoppr wallet to your bank account.',
              style: AppText.body),
          const SizedBox(height: AppSizes.xl),
          // Default bank account.
          Container(
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
                      Text('GTBank · •••• 6789', style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text('Amara Okafor · Default', style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                const StatusPill(label: 'Default', dense: true),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          // Editable amount.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.lg, vertical: AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.card,
              border: Border.all(color: AppColors.border, width: 1.3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount',
                    style:
                        AppText.label.copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                        controller: _amount,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsFormatter()],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _confirm(),
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
          ),
          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: 'Confirm withdrawal',
            icon: Icons.check_rounded,
            variant: AppButtonVariant.outline,
            onPressed: _confirm,
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
    // Filled action (Withdraw) is lime in the Lime theme, white in Mono.
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
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.positive,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;
  final bool positive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                Text(subtitle,
                    style: AppText.caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(amount,
              style: AppText.bodyStrong.copyWith(
                  color: positive ? AppColors.success : AppColors.textPrimary)),
        ],
      ),
      ),
    );
  }
}
