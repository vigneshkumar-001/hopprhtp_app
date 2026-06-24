import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/models.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../profile/merchant_profile_screen.dart';
import 'confirm_delivery_screen.dart';
import 'package_tracking_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Transaction detail (mockup 14) — escrow status timeline + breakdown.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.tx});
  final EscrowTransaction tx;

  PaymentDraft get _draft => PaymentDraft(
        productName: tx.productName,
        sellerName: tx.merchantName,
        sellerCode: tx.code,
        itemSubtotal: tx.amount,
        variant: tx.variant,
      );

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Transaction',
      trailing: const AppIconButton(icon: Icons.more_horiz_rounded),
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Verify delivery',
            trailingIcon: Icons.lock_outline_rounded,
            variant: AppButtonVariant.outline,
            accentInLime: true,
            onPressed: () =>
                AppNav.push(context, ConfirmDeliveryScreen(draft: _draft)),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Track package',
            icon: Icons.local_shipping_outlined,
            variant: AppButtonVariant.soft,
            onPressed: () =>
                AppNav.push(context, PackageTrackingScreen(draft: _draft)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            onTap: () =>
                AppNav.push(context, const MerchantProfileScreen()),
            child: Row(
              children: [
                Hero(
                  tag: 'txn-avatar-${tx.id}',
                  child:
                      InitialsAvatar(initials: tx.merchantInitials, size: 42),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tx.merchantName, style: AppText.bodyStrong),
                      const SizedBox(height: 2),
                      Row(
                        children: const [
                          VerifiedBadge(size: 14),
                          SizedBox(width: 4),
                          Text('HTP Verified', style: AppText.caption),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('96', style: AppText.h3),
                    Text('trust', style: AppText.caption),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Row(
              children: [
                const ThumbPlaceholder(label: 'product', size: 64),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StatusPill(label: 'Fashion', dense: true),
                      const SizedBox(height: AppSizes.sm),
                      Text(tx.productName, style: AppText.h3),
                      const SizedBox(height: 2),
                      Text('${tx.variant ?? 'Standard'} · Qty 1',
                          style: AppText.caption),
                      const SizedBox(height: AppSizes.sm),
                      Text(Money.format(tx.amount), style: AppText.bodyStrong),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Escrow status'),
                const SizedBox(height: AppSizes.lg),
                _EscrowTimeline(stage: tx.stage, status: tx.status),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          _PaidCard(total: tx.amount),
          const SizedBox(height: AppSizes.md),
          const _ProtectedNote(),
        ],
      ),
    );
  }
}

/// "YOU PAID" breakdown — derives item / delivery / 1.5% trust fee from total.
class _PaidCard extends StatelessWidget {
  const _PaidCard({required this.total});
  final double total;

  @override
  Widget build(BuildContext context) {
    const delivery = 2500.0;
    final item = ((total - delivery) / 1.015).roundToDouble();
    final trust = total - delivery - item;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('You paid'),
          const SizedBox(height: AppSizes.md),
          SummaryRow(label: 'Item subtotal', value: Money.format(item)),
          const SizedBox(height: AppSizes.sm),
          SummaryRow(label: 'Delivery fee', value: Money.format(delivery)),
          const SizedBox(height: AppSizes.sm),
          SummaryRow(
            label: 'Trust protection fee',
            value: Money.format(trust),
            badge: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: AppColors.textTertiary),
                SizedBox(width: 6),
                StatusPill(label: '1.5%', dense: true),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1),
          ),
          SummaryRow(
              label: 'Total in escrow',
              value: Money.format(total),
              emphasized: true),
        ],
      ),
    );
  }
}

/// "Protected by Hoppr Trust Protocol" reassurance note.
class _ProtectedNote extends StatelessWidget {
  const _ProtectedNote();

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      // Left → right gradient.
      gradient: accent.isLime
          ? const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFF4FAE3), Color(0xFFDCE8B8)],
            )
          : const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xFFE8E8E8), Color(0xFFD8D8D8)],
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: AppRadii.md,
            ),
            child: const Icon(Icons.shield_outlined,
                size: 22, color: AppColors.textOnDark),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.caption.copyWith(height: 1.45),
                children: const [
                  TextSpan(
                      text: 'Protected by Hoppr Trust Protocol. ',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  TextSpan(
                      text:
                          'Funds release only after you confirm delivery at the right place with the dispatcher\'s code.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EscrowTimeline extends StatelessWidget {
  const _EscrowTimeline({required this.stage, required this.status});
  final TxStage stage;
  final TxStatus status;

  @override
  Widget build(BuildContext context) {
    final outForDelivery = status == TxStatus.outForDelivery;
    final done = stage == TxStage.done;
    final inTransitDone = status == TxStatus.outForDelivery ||
        status == TxStatus.delivered ||
        done;

    final steps = <(_StepState, String, String?)>[
      (_StepState.done, 'Paid into escrow', null),
      (
        inTransitDone ? _StepState.done : _StepState.current,
        'In transit',
        null
      ),
      (
        done
            ? _StepState.done
            : (outForDelivery ? _StepState.current : _StepState.pending),
        'Out for delivery',
        outForDelivery ? 'Dispatcher arriving — ETA 10:00' : null,
      ),
      (
        done ? _StepState.done : _StepState.pending,
        'Delivered & released',
        null
      ),
    ];

    return Column(
      children: [
        for (int i = 0; i < steps.length; i++)
          _TimelineNode(
            state: steps[i].$1,
            title: steps[i].$2,
            subtitle: steps[i].$3,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

enum _StepState { done, current, pending }

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.state,
    required this.title,
    required this.isLast,
    this.subtitle,
  });

  final _StepState state;
  final String title;
  final String? subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final filled = state != _StepState.pending;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Small unique pulse on the active step.
                  if (state == _StepState.current)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.ink.withValues(alpha: 0.30),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .scaleXY(
                            begin: 1,
                            end: 2.1,
                            duration: 1500.ms,
                            curve: Curves.easeOut)
                        .fadeOut(duration: 1500.ms),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: filled ? AppColors.ink : AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: filled ? AppColors.ink : AppColors.border),
                    ),
                    // Done & pending both show a tick; current shows the pin.
                    child: Icon(
                      state == _StepState.current
                          ? Icons.location_on
                          : Icons.check_rounded,
                      size: 15,
                      color: filled
                          ? AppColors.textOnDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: filled ? AppColors.ink : AppColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSizes.md),
          Padding(
            padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: state == _StepState.pending
                        ? AppText.body
                        : AppText.bodyStrong),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
