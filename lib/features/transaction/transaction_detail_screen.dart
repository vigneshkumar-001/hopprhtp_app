import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../../widgets/feedback/app_snackbar.dart';
import '../profile/merchant_profile_screen.dart';
import 'confirm_delivery_screen.dart';
import 'package_tracking_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Transaction detail — seller, item, the escrow-status timeline, the release
/// note and the delivery details. Accent-driven chrome follows the theme
/// (Mono / Lime). Several fields below are still sample data (this screen reads
/// the demo [EscrowTransaction]); they're wired to real values when the detail
/// screen moves onto `ApiTransaction`.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.tx});
  final EscrowTransaction tx;

  // ── Sample details (pending real ApiTransaction wiring) ───────────────────
  static const String _category = 'Fashion';
  static const String _trustScore = '96/100';
  static const int _successfulTx = 127;
  static const String _dispatcherName = 'Tunde Bello';
  static const String _dispatcherPhone = '+234 706 740 8881';
  static const String _deliveryAddress = '14 Admiralty Way, Lekki Phase 1, Lagos';
  static const String _eta = 'Today, 10:00 AM – 12:00 PM';

  PaymentDraft get _draft => PaymentDraft(
        productName: tx.productName,
        sellerName: tx.merchantName,
        sellerCode: tx.code,
        itemSubtotal: tx.amount,
        variant: tx.variant,
      );

  void _copy(BuildContext context, String value, String message) {
    Clipboard.setData(ClipboardData(text: value));
    AppSnackbar.success(context, message);
  }

  void _viewItem(BuildContext context) {
    final accent = AppAccent.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ThumbPlaceholder(label: 'product', size: 84),
                  const SizedBox(width: AppSizes.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusPill(
                          label: _category,
                          dense: true,
                          background: accent.accentSoft,
                          foreground: accent.onAccentSoft,
                        ),
                        const SizedBox(height: AppSizes.sm),
                        Text(tx.productName, style: AppText.h3),
                        const SizedBox(height: 2),
                        Text('${tx.variant ?? 'Standard'} · Qty 1',
                            style: AppText.caption),
                        const SizedBox(height: 2),
                        Text('1 consignment · ${tx.code}',
                            style: AppText.caption),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
                child: Divider(height: 1),
              ),
              SummaryRow(
                  label: 'Item value',
                  value: Money.format(tx.amount),
                  emphasized: true),
              const SizedBox(height: AppSizes.xl),
              AppButton(
                label: 'Close',
                variant: AppButtonVariant.soft,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          _SellerCard(
            tx: tx,
            trustScore: _trustScore,
            successfulTx: _successfulTx,
            onTap: () => AppNav.push(context, const MerchantProfileScreen()),
          ),
          const SizedBox(height: AppSizes.md),
          _ProductCard(
            tx: tx,
            category: _category,
            onViewItem: () => _viewItem(context),
          ),
          const SizedBox(height: AppSizes.md),
          _EscrowStatusCard(
            stage: tx.stage,
            status: tx.status,
            dispatcherName: _dispatcherName,
            eta: _eta,
          ),
          const SizedBox(height: AppSizes.md),
          const _ReleaseBanner(),
          const SizedBox(height: AppSizes.md),
          _PaidCard(total: tx.amount),
          const SizedBox(height: AppSizes.md),
          _DeliveryDetailsCard(
            address: _deliveryAddress,
            dispatcher: '$_dispatcherName · $_dispatcherPhone',
            eta: _eta,
            onAddress: () =>
                _copy(context, _deliveryAddress, 'Delivery address copied'),
            onDispatcher: () =>
                _copy(context, _dispatcherPhone, 'Dispatcher phone copied'),
            onEta: () =>
                AppNav.push(context, PackageTrackingScreen(draft: _draft)),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
/// Verified seller header — avatar, name + badge, trust score and a chevron
/// into the full merchant profile.
class _SellerCard extends StatelessWidget {
  const _SellerCard({
    required this.tx,
    required this.trustScore,
    required this.successfulTx,
    required this.onTap,
  });

  final EscrowTransaction tx;
  final String trustScore;
  final int successfulTx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Hero(
            tag: 'txn-avatar-${tx.id}',
            child: InitialsAvatar(initials: tx.merchantInitials, size: 46),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(tx.merchantName,
                          style: AppText.h3, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 5),
                    Icon(Icons.verified_rounded, size: 16, color: accent.ring),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined,
                        size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text('HTP Verified Seller', style: AppText.caption),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text('Trust score', style: AppText.caption),
                    const SizedBox(width: 6),
                    StatusPill(
                      label: trustScore,
                      dense: true,
                      background: AppColors.successSoft,
                      foreground: AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('· $successfulTx successful transactions',
                          style: AppText.caption,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

/// Item card — thumbnail, category, name, variant, consignment + a "View item".
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.tx,
    required this.category,
    required this.onViewItem,
  });

  final EscrowTransaction tx;
  final String category;
  final VoidCallback onViewItem;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ThumbPlaceholder(label: 'product', size: 78),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(
                      label: category,
                      dense: true,
                      background: accent.accentSoft,
                      foreground: accent.onAccentSoft,
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(tx.productName, style: AppText.h3),
                    const SizedBox(height: 3),
                    Text('${tx.variant ?? 'Standard'} · Qty 1',
                        style: AppText.caption),
                    const SizedBox(height: 2),
                    Text('1 consignment · ${tx.code}', style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(Money.format(tx.amount), style: AppText.h3),
              const Spacer(),
              _ViewItemButton(onTap: onViewItem),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewItemButton extends StatelessWidget {
  const _ViewItemButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadii.md,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: AppRadii.md,
            border: Border.all(color: AppColors.border, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, size: 17, color: accent.ring),
              const SizedBox(width: 6),
              Text('View item',
                  style: AppText.bodyStrong.copyWith(color: accent.ring)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Escrow-status card — header + "Your money is safe" pill + the timeline.
class _EscrowStatusCard extends StatelessWidget {
  const _EscrowStatusCard({
    required this.stage,
    required this.status,
    required this.dispatcherName,
    required this.eta,
  });

  final TxStage stage;
  final TxStatus status;
  final String dispatcherName;
  final String eta;

  @override
  Widget build(BuildContext context) {
    final outForDelivery = status == TxStatus.outForDelivery;
    final done = stage == TxStage.done;
    final inTransitDone =
        outForDelivery || status == TxStatus.delivered || done;

    final now = DateTime.now();
    final paidAt = DateTime(now.year, now.month, now.day, 10, 32);
    final transitAt = DateTime(now.year, now.month, now.day, 14, 15);

    final steps = <_StepData>[
      _StepData(
        state: _StepState.done,
        icon: Icons.account_balance_wallet_outlined,
        title: 'Paid into escrow',
        lines: [_fmtStamp(paidAt)],
      ),
      _StepData(
        state: inTransitDone ? _StepState.done : _StepState.current,
        icon: Icons.local_shipping_outlined,
        title: 'In transit',
        lines:
            inTransitDone ? [_fmtStamp(transitAt)] : ['Your item is on the way'],
      ),
      _StepData(
        state: done
            ? _StepState.done
            : (outForDelivery ? _StepState.current : _StepState.pending),
        icon: Icons.local_shipping_outlined,
        title: 'Out for delivery',
        lines: outForDelivery
            ? ['Dispatcher: $dispatcherName', 'ETA: $eta']
            : (done ? ['Delivered'] : ['Awaiting dispatch']),
      ),
      _StepData(
        state: done ? _StepState.done : _StepState.pending,
        icon: Icons.inventory_2_outlined,
        title: 'Delivered & released',
        lines: done
            ? ['Funds released to seller']
            : ['Confirm delivery with OTP to release payment'],
      ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CardSectionLabel('Escrow status')),
              const SizedBox(width: AppSizes.sm),
              StatusPill(
                label: 'Your money is safe',
                icon: Icons.verified_user_rounded,
                dense: true,
                background: AppColors.successSoft,
                foreground: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          for (int i = 0; i < steps.length; i++)
            _TimelineNode(step: steps[i], isLast: i == steps.length - 1),
        ],
      ),
    );
  }
}

enum _StepState { done, current, pending }

class _StepData {
  const _StepData({
    required this.state,
    required this.icon,
    required this.title,
    required this.lines,
  });
  final _StepState state;
  final IconData icon;
  final String title;
  final List<String> lines;
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({required this.step, required this.isLast});
  final _StepData step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final state = step.state;
    final done = state == _StepState.done;
    final current = state == _StepState.current;
    final filled = state != _StepState.pending;

    final circleColor = filled ? accent.accent : AppColors.surfaceMuted;
    final iconColor = filled ? accent.onAccent : AppColors.textTertiary;
    final glyph = done ? Icons.check_rounded : step.icon;
    // The connector fills only once we've moved PAST this node (state done).
    final lineColor = done ? accent.accent : AppColors.border;

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
                  if (current)
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.accent.withValues(alpha: 0.28),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat())
                        .scaleXY(
                            begin: 1,
                            end: 2.0,
                            duration: 1500.ms,
                            curve: Curves.easeOut)
                        .fadeOut(duration: 1500.ms),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: filled ? accent.accent : AppColors.border),
                    ),
                    child: Icon(glyph, size: 17, color: iconColor),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: lineColor)),
            ],
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: isLast ? 0 : AppSizes.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(step.title,
                            style: state == _StepState.pending
                                ? AppText.body.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600)
                                : AppText.bodyStrong),
                      ),
                      const SizedBox(width: AppSizes.sm),
                      _StatusChip(state: state),
                    ],
                  ),
                  for (final line in step.lines) ...[
                    const SizedBox(height: 2),
                    Text(line, style: AppText.caption),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return switch (state) {
      _StepState.done => const StatusPill(
          label: 'Completed',
          dense: true,
          background: AppColors.successSoft,
          foreground: AppColors.success,
        ),
      _StepState.current => StatusPill(
          label: 'Current',
          dense: true,
          background: accent.accent,
          foreground: accent.onAccent,
        ),
      _StepState.pending => const StatusPill(
          label: 'Pending',
          dense: true,
          background: AppColors.surfaceMuted,
          foreground: AppColors.textTertiary,
        ),
    };
  }
}

/// "Payment will be released after you confirm delivery" reassurance banner.
class _ReleaseBanner extends StatelessWidget {
  const _ReleaseBanner();

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      color: accent.accentSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined,
              size: 22, color: accent.onAccentSoft),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.caption.copyWith(height: 1.5),
                children: const [
                  TextSpan(
                    text: 'Payment will be released after you confirm '
                        'delivery.\n',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  TextSpan(
                    text: 'Your funds are held securely in escrow until '
                        'delivery is verified.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Delivery details — address, dispatcher and ETA rows (each tappable).
class _DeliveryDetailsCard extends StatelessWidget {
  const _DeliveryDetailsCard({
    required this.address,
    required this.dispatcher,
    required this.eta,
    required this.onAddress,
    required this.onDispatcher,
    required this.onEta,
  });

  final String address;
  final String dispatcher;
  final String eta;
  final VoidCallback onAddress;
  final VoidCallback onDispatcher;
  final VoidCallback onEta;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.lg, vertical: AppSizes.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          const CardSectionLabel('Delivery details'),
          const SizedBox(height: AppSizes.xs),
          _DetailRow(
            icon: Icons.location_on_outlined,
            label: 'Delivery address',
            value: address,
            onTap: onAddress,
          ),
          const Divider(height: 1),
          _DetailRow(
            icon: Icons.local_shipping_outlined,
            label: 'Dispatcher',
            value: dispatcher,
            onTap: onDispatcher,
          ),
          const Divider(height: 1),
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Estimated delivery',
            value: eta,
            onTap: onEta,
          ),
          const SizedBox(height: AppSizes.sm),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.sm,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 19, color: AppColors.textPrimary),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(value,
                        style: AppText.caption, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary),
            ],
          ),
        ),
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
            badge: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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

/// "30 Jun 2026 · 10:32 AM".
String _fmtStamp(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${Dates.medium(d)} · ${h.toString().padLeft(2, '0')}:$m $ap';
}
