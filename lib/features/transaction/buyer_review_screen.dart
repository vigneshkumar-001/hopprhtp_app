import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import 'after_payment_screen.dart';
import 'checkout_webview_screen.dart';
import 'transaction_detail_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Buyer Review & Payment — the buyer reviews the real, already-fetched
/// transaction and pays into escrow. Reached from [JoinTransactionScreen]
/// after a successful `getByCode` lookup, so no second fetch happens here
/// (and none could: an unpaid transaction isn't yet owned by this user, so
/// the authed detail endpoint would reject it — see [ApiTransaction.isBuyer]).
///
/// This screen owns every outcome a fetched code can produce — seller viewing
/// their own link, an already-paid transaction, one paid by someone else, a
/// dead transaction, and the real unpaid review+pay flow — so the caller only
/// needs to route here once.
class BuyerReviewScreen extends ConsumerStatefulWidget {
  const BuyerReviewScreen({super.key, required this.tx});
  final ApiTransaction tx;

  @override
  ConsumerState<BuyerReviewScreen> createState() => _BuyerReviewScreenState();
}

class _BuyerReviewScreenState extends ConsumerState<BuyerReviewScreen> {
  /// Guards "Pay into Escrow" — prevents opening two checkout screens at once.
  bool _opening = false;

  ApiTransaction get tx => widget.tx;

  static const _unpaidStatuses = {
    ApiTxStatus.draft,
    ApiTxStatus.awaitingAgreement,
    ApiTxStatus.awaitingPayment,
  };

  /// Statuses where the transaction is permanently done for — never payable,
  /// never viewable as an active order.
  static const _deadStatuses = {
    ApiTxStatus.cancelled,
    ApiTxStatus.refunded,
    ApiTxStatus.returned,
    ApiTxStatus.undeliverable,
    ApiTxStatus.unknown,
  };

  void _backToHome() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  void _openDetail() {
    // Drops Join/Review (and anything above) from the stack — Back from the
    // detail goes straight Home, never back through this flow.
    AppNav.pushAndClearToFirst(
      context,
      TransactionDetailScreen(tx: EscrowTransaction.fromApi(tx)),
    );
  }

  Future<void> _payIntoEscrow() async {
    if (_opening) return;
    setState(() => _opening = true);
    final result = await AppNav.push<CheckoutResult>(
      context,
      CheckoutWebViewScreen(code: tx.code, lime: AppAccent.of(context).isLime),
    );
    if (!mounted) return;
    setState(() => _opening = false);
    // A null result means the route was popped some other way (shouldn't
    // happen — CheckoutWebViewScreen always pops a CheckoutResult) — treat it
    // as a cancel rather than silently doing nothing.
    final outcome = result?.outcome ?? PaymentOutcome.cancelled;
    AppNav.push(
      context,
      AfterPaymentScreen(
        outcome: outcome,
        tx: tx,
        failureReason: result?.message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Seller opened their own payment link — never payable by them.
    if (tx.isSeller) {
      return _InfoScaffold(
        icon: Icons.info_outline_rounded,
        iconColor: AppColors.textSecondary,
        title: 'This payment link is for the buyer.',
        message:
            'You created this transaction, so you can review it — but only '
            'the buyer can pay into escrow.',
        buttonLabel: 'View Transaction',
        onPressed: _openDetail,
      );
    }

    // Dead-ended — nothing left to pay or view as an active order.
    if (_deadStatuses.contains(tx.status)) {
      return _InfoScaffold(
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.danger,
        title: 'This transaction is no longer available.',
        message:
            'It was ${tx.status.label.toLowerCase()} and can no longer '
            'be joined or paid.',
        buttonLabel: 'Back to Home',
        onPressed: _backToHome,
      );
    }

    final unpaid = _unpaidStatuses.contains(tx.status);

    if (!unpaid) {
      // Already paid — either by this signed-in buyer, or by someone else.
      if (tx.isBuyer) {
        return _InfoScaffold(
          icon: Icons.check_circle_outline_rounded,
          iconColor: AppColors.success,
          title: 'Payment already completed',
          message: 'This transaction is already paid and in progress.',
          buttonLabel: 'View Transaction',
          onPressed: _openDetail,
        );
      }
      return _InfoScaffold(
        icon: Icons.lock_outline_rounded,
        iconColor: AppColors.textSecondary,
        title:
            'This transaction already has a buyer and can no longer be '
            'joined.',
        buttonLabel: 'Back to Home',
        onPressed: _backToHome,
      );
    }

    // The real review + pay flow.
    return AppScaffold(
      title: 'Buyer Review & Payment',
      bottomAction: AppButton(
        label: 'Pay into Escrow · ${Money.format(tx.grandTotalNaira)}',
        icon: Icons.lock_outline_rounded,
        loading: _opening,
        enabled: !_opening,
        onPressed: _payIntoEscrow,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  tx.code,
                  style: AppText.bodyStrong.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ),
              StatusPill(label: tx.status.label, dense: true),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          _ProductCard(tx: tx),
          const SizedBox(height: AppSizes.md),
          _SellerCard(tx: tx),
          if ((tx.deliveryAddress ?? '').trim().isNotEmpty ||
              (tx.estimatedDeliveryDate ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: AppSizes.md),
            _DeliveryCard(tx: tx),
          ],
          const SizedBox(height: AppSizes.md),
          _EscrowSummaryCard(tx: tx),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.shield_outlined,
            color: Color(0xFFF7EFD6),
            text:
                'Funds are held securely in escrow and released to the '
                'seller only after you confirm delivery.',
          ),
        ],
      ),
    );
  }
}

/// Shared full-screen state for every non-payable outcome (seller viewing
/// their own link, already paid, dead transaction, blocked) — one message,
/// one action, no clutter.
class _InfoScaffold extends StatelessWidget {
  const _InfoScaffold({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Buyer Review & Payment',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: iconColor),
              const SizedBox(height: AppSizes.md),
              Text(title, textAlign: TextAlign.center, style: AppText.h3),
              if (message != null) ...[
                const SizedBox(height: AppSizes.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppText.body,
                ),
              ],
              const SizedBox(height: AppSizes.lg),
              AppButton(
                label: buttonLabel,
                expand: false,
                onPressed: onPressed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.tx});
  final ApiTransaction tx;

  @override
  Widget build(BuildContext context) {
    final weight = (tx.weight ?? '').trim();
    final waybill = (tx.waybillTrackingNumber ?? '').trim();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('Product details'),
          const SizedBox(height: AppSizes.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumb(url: tx.productPhotoUrl, size: 72),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.productName, style: AppText.bodyStrong),
                    if ((tx.variant ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(tx.variant!.trim(), style: AppText.caption),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      Money.format(tx.itemSubtotalNaira),
                      style: AppText.bodyStrong,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (weight.isNotEmpty || waybill.isNotEmpty) ...[
            const SizedBox(height: AppSizes.md),
            const Divider(height: 1),
            const SizedBox(height: AppSizes.md),
            if (weight.isNotEmpty)
              _MetaRow(
                icon: Icons.scale_outlined,
                label: 'Weight',
                value: weight,
              ),
            if (weight.isNotEmpty && waybill.isNotEmpty)
              const SizedBox(height: AppSizes.sm),
            if (waybill.isNotEmpty)
              _MetaRow(
                icon: Icons.local_shipping_outlined,
                label: 'Waybill / tracking no.',
                value: waybill,
              ),
          ],
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.tx});
  final ApiTransaction tx;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          InitialsAvatar(initials: _initialsOf(tx.merchantName), size: 42),
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
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.tx});
  final ApiTransaction tx;

  @override
  Widget build(BuildContext context) {
    final address = (tx.deliveryAddress ?? '').trim();
    final eta = [
      tx.estimatedDeliveryDate,
      tx.estimatedDeliveryTime,
    ].where((v) => (v ?? '').trim().isNotEmpty).join(' · ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('Delivery details'),
          const SizedBox(height: AppSizes.md),
          if (address.isNotEmpty)
            _MetaRow(
              icon: Icons.location_on_outlined,
              label: 'Delivery address',
              value: address,
            ),
          if (address.isNotEmpty && eta.isNotEmpty)
            const SizedBox(height: AppSizes.sm),
          if (eta.isNotEmpty)
            _MetaRow(
              icon: Icons.schedule_rounded,
              label: 'Estimated delivery',
              value: eta,
            ),
        ],
      ),
    );
  }
}

class _EscrowSummaryCard extends StatelessWidget {
  const _EscrowSummaryCard({required this.tx});
  final ApiTransaction tx;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('Escrow payment summary'),
          const SizedBox(height: AppSizes.md),
          SummaryRow(
            label: 'Item subtotal',
            value: Money.format(tx.itemSubtotalNaira),
          ),
          const SizedBox(height: AppSizes.sm),
          SummaryRow(
            label: 'Delivery fee',
            value: Money.format(tx.deliveryFeeNaira),
          ),
          const SizedBox(height: AppSizes.sm),
          SummaryRow(
            label: 'Trust protection fee',
            value: Money.format(tx.buyerTrustShareNaira),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1),
          ),
          SummaryRow(
            label: 'Grand total payable',
            value: Money.format(tx.grandTotalNaira),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

/// First + first-of-second-word initials, upper-cased — same convention used
/// for transaction-list avatars elsewhere in the app.
String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.take(2).toString().toUpperCase();
  }
  return (parts.first.characters.first + parts[1].characters.first)
      .toUpperCase();
}
