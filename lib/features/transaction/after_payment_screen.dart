import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import 'package_tracking_screen.dart';
import 'widgets/transaction_widgets.dart';

/// After Payment Confirmation — funds locked, OTP issued to dispatcher.
EscrowTransaction _draftToTx(PaymentDraft draft) => EscrowTransaction(
      id: draft.sellerCode,
      code: draft.sellerCode,
      merchantName: draft.sellerName,
      productName: draft.productName,
      amount: draft.grandTotal,
      stage: TxStage.active,
      status: TxStatus.awaitingDispatch,
    );

class AfterPaymentScreen extends StatelessWidget {
  const AfterPaymentScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  Widget build(BuildContext context) {
    // Lime-theme accent tints for the info tiles on this screen.
    final accent = AppAccent.of(context);
    return AppScaffold(
      title: 'After Payment Confirmation',
      bottomAction: AppButton(
        label: 'Track delivery',
        trailingIcon: Icons.location_on_outlined,
        variant: AppButtonVariant.outline,
        accentInLime: true,
        onPressed: () =>
            AppNav.push(context, PackageTrackingScreen(tx: _draftToTx(draft))),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.lg),
          Center(
            child: Column(
              children: [
                Text('Payment Secured',
                    style: AppText.body
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSizes.xs),
                AnimatedMoney(draft.grandTotal,
                    style: AppText.display.copyWith(fontSize: 34)),
                const SizedBox(height: AppSizes.md),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StatusPill(
                      label: 'LOCKED',
                      icon: Icons.lock_outline_rounded,
                      background: AppColors.ink,
                      foreground: AppColors.textOnDark,
                      dense: true,
                    ),
                    const SizedBox(width: AppSizes.sm),
                    StatusPill(
                      label: 'Protected',
                      icon: Icons.shield_outlined,
                      background:
                          accent.isLime ? const Color(0xFFF7EFD6) : null,
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          ItemSummaryCard(
            product: draft.productName,
            subtitle: '${draft.sellerName} · ${draft.sellerCode}',
            amount: draft.itemSubtotal,
            trailing: const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSizes.lg),
          const SectionLabel('Delivery OTP'),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.isLime
                        ? const Color(0xFFF4E7A4)
                        : AppColors.surfaceMuted,
                    borderRadius: AppRadii.sm,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sent to your dispatcher',
                          style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Text('via SMS / WhatsApp · valid for 7 days',
                          style: AppText.caption),
                    ],
                  ),
                ),
                const StatusPill(
                  label: 'Sent',
                  icon: Icons.check_rounded,
                  dense: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          NoteBanner(
            color: accent.isLime ? const Color(0xFFEAF7C2) : null,
            textColor: accent.isLime ? const Color(0xFF5C1A12) : null,
            highlight: accent.isLime ? 'dispatcher' : null,
            highlightColor: accent.isLime ? const Color(0xFF181A12) : null,
            text:
                'For your security, the 6-digit code goes to the dispatcher — not to you. They\'ll read it out at the door, and you enter it in the app once you\'re inside the delivery zone.',
          ),
        ],
      ),
    );
  }
}









