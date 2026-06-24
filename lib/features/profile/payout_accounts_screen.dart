import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/blur_sheet.dart';
import '../../widgets/common.dart';
import '../transaction/widgets/transaction_widgets.dart';

class PayoutAccountsScreen extends StatefulWidget {
  const PayoutAccountsScreen({super.key});

  @override
  State<PayoutAccountsScreen> createState() => _PayoutAccountsScreenState();
}

class _PayoutAccountsScreenState extends State<PayoutAccountsScreen> {
  int _default = 0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Payout Accounts',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text(
            'Where your settlements and withdrawals are paid. The default account receives seller payouts automatically.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          _AccountCard(
            bank: 'GTBank',
            account: '···· 6789',
            name: 'Amara Okafor',
            isDefault: _default == 0,
            onTap: () => setState(() => _default = 0),
          ),
          const SizedBox(height: AppSizes.md),
          _AccountCard(
            bank: 'Kuda Microfinance',
            account: '···· 2231',
            name: 'Amara Thrift',
            isDefault: _default == 1,
            onTap: () => setState(() => _default = 1),
          ),
          const SizedBox(height: AppSizes.md),
          _AddAccountButton(
            onTap: () => _showAddBankSheet(context),
          ),
          const SizedBox(height: AppSizes.lg),
          const NoteBanner(
            text:
                'Account names must match your verified identity. Payouts to mismatched names are held for review.',
          ),
        ],
      ),
    );
  }
}

/// Animated bottom sheet (blurred backdrop) to add a new payout bank account.
void _showAddBankSheet(BuildContext context) {
  showBlurredSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.xl, AppSizes.md, AppSizes.xl, AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add bank account', style: AppText.h2),
          const SizedBox(height: AppSizes.lg),
          const AppTextField(
            label: 'Bank',
            hint: 'Select bank',
            icon: Icons.account_balance_outlined,
          ),
          const SizedBox(height: AppSizes.md),
          const AppTextField(
            label: 'Account number',
            hint: '0000000000',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSizes.md),
          const AppTextField(
            label: 'Account name',
            hint: 'Auto-filled after verification',
            icon: Icons.verified_user_outlined,
          ),
          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: 'Verify & save',
            icon: Icons.check_rounded,
            variant: AppButtonVariant.outline,
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bank account added')),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.bank,
    required this.account,
    required this.name,
    required this.isDefault,
    required this.onTap,
  });

  final String bank;
  final String account;
  final String name;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      border: Border.all(
        color: isDefault ? AppColors.borderStrong : AppColors.border,
        width: isDefault ? 1.6 : 1.2,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: const Icon(Icons.account_balance_outlined, size: 20),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bank, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text('$account · $name',
                    style: AppText.caption.copyWith(fontFamily: 'monospace')),
              ],
            ),
          ),
          if (isDefault)
            const StatusPill(label: 'Default', dense: true)
          else
            const Icon(Icons.radio_button_unchecked_rounded,
                color: AppColors.textTertiary, size: 22),
        ],
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, size: 20),
              const SizedBox(width: AppSizes.sm),
              Text('Add bank account', style: AppText.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}
