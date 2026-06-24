import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import 'widgets/transaction_widgets.dart';

/// Link transaction — a web-checkout payment is matched to the account.
class LinkTransactionScreen extends StatelessWidget {
  const LinkTransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Link transaction',
      bottomAction: AppButton(
        label: 'Add to my account',
        trailingIcon: Icons.arrow_forward_rounded,
        variant: AppButtonVariant.outline,
        accentInLime: true,
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaction linked to your account')),
          );
          AppNav.replaceAll(context, const HomeShell());
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              const BrandMark(pill: true, fontSize: 16),
              const SizedBox(width: AppSizes.sm),
              Text('WELCOME BACK',
                  style: AppText.caption.copyWith(
                      letterSpacing: 1.2, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          Text('We found your paid\ntransaction', style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text(
            'A transaction you paid through web checkout is ready to be linked to your Hoppr account.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          DarkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Secured in escrow',
                        style: AppText.caption
                            .copyWith(color: AppColors.textOnDarkMuted)),
                    const StatusPill(
                      label: 'LOCKED',
                      icon: Icons.lock_outline_rounded,
                      background: AppColors.inkSoft,
                      foreground: AppColors.textOnDark,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.sm),
                Text(Money.format(1256038.31), style: AppText.numeral),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(color: AppColors.divider, height: 1),
                ),
                Row(
                  children: [
                    InitialsAvatar(initials: 'YS', size: 36, onDark: true),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Yemi Stores',
                              style: AppText.bodyStrong
                                  .copyWith(color: AppColors.textOnDark)),
                          const SizedBox(height: 2),
                          Text('HTP-LGS-8881 · MacBook Pro M2',
                              style: AppText.caption.copyWith(
                                  color: AppColors.textOnDarkMuted,
                                  fontFamily: 'monospace')),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle_outline_rounded,
                        color: AppColors.textOnDark, size: 20),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Matched to your account by'),
                const SizedBox(height: AppSizes.md),
                _MatchRow(
                  icon: Icons.phone_outlined,
                  title: 'Phone number',
                  value: '+234 803 ·· 98',
                ),
                const Divider(height: AppSizes.xl),
                _MatchRow(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Transaction token',
                  value: 'HTP-LGS-8881',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.shield_outlined,
            text:
                'Once linked, you can verify delivery, enter the dispatcher\'s OTP, track the package, and raise disputes — all from the app.',
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow(
      {required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
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
              Text(value,
                  style: AppText.caption.copyWith(fontFamily: 'monospace')),
            ],
          ),
        ),
        const Icon(Icons.check_circle_outline_rounded,
            color: AppColors.textSecondary, size: 20),
      ],
    );
  }
}
