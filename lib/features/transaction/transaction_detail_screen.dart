import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/dispute_dto.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import 'application/transactions_provider.dart';
import 'widgets/transaction_widgets.dart';
import 'confirm_delivery_screen.dart';
import 'cooling_period_screen.dart';
import 'package_tracking_screen.dart';
import 'settlement_ledger_screen.dart';
import '../dispute/dispute_center_screen.dart';
import '../dispute/dispute_status_screen.dart';
import '../profile/merchant_profile_screen.dart';
import '../settlement/seller_settlement_screen.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.tx});
  final EscrowTransaction tx;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  EscrowTransaction get tx => widget.tx;

  /// Guards the "Track package" tap: prevents overlapping fetches and drives
  /// the button's loading/disabled state while the real transaction is
  /// re-fetched to check whether it actually has delivery coordinates.
  bool _checkingTracking = false;

  /// Guards the seller's Start Delivery / Out-for-delivery actions.
  bool _shipping = false;

  /// Re-fetches the real transaction (never trusts stale/legacy display data)
  /// and only opens tracking if the buyer's delivery address has real
  /// coordinates. Older transactions created before lat/lng existed — or a
  /// lookup failure — get a friendly message instead of a broken/empty map.
  Future<void> _onTrackPackage() async {
    if (_checkingTracking) return;
    setState(() => _checkingTracking = true);
    try {
      final fresh = await ref
          .read(transactionRepositoryProvider)
          .getById(tx.id);
      if (!mounted) return;
      if (fresh.hasDeliveryLocation) {
        AppNav.push(context, PackageTrackingScreen(tx: tx));
      } else {
        AppSnackbar.info(
          context,
          'Tracking location is not available for this transaction.',
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not check tracking availability. Please try again.',
          onRetry: _onTrackPackage,
        );
      }
    } finally {
      if (mounted) setState(() => _checkingTracking = false);
    }
  }

  /// Re-syncs everything a lifecycle action can have changed.
  void _invalidateTx() {
    ref.invalidate(transactionDetailProvider(tx.id));
    ref.invalidate(trackingProvider(tx.id));
    ref.invalidate(transactionsProvider);
  }

  /// Seller starts delivery (payment_received/awaiting_dispatch → in_transit).
  /// Offers an optional dispatch-proof photo first; on a real upload failure it
  /// never reports success. Buyer never reaches this (gated in the slot below).
  Future<void> _startDelivery() async {
    if (_shipping) return;
    final result = await showModalBottomSheet<_DispatchProofResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DispatchProofSheet(),
    );
    if (result == null || !mounted) return; // dismissed → cancel

    setState(() => _shipping = true);
    try {
      await ref
          .read(transactionRepositoryProvider)
          .ship(tx.id, dispatchProofUrl: result.url);
      if (!mounted) return;
      _invalidateTx();
      AppSnackbar.success(
        context,
        'Delivery started. Buyer has been notified.',
      );
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not start delivery. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _shipping = false);
    }
  }

  /// Seller marks the order out for delivery (in_transit → out_for_delivery).
  Future<void> _markOutForDelivery() async {
    if (_shipping) return;
    setState(() => _shipping = true);
    try {
      await ref.read(transactionRepositoryProvider).outForDelivery(tx.id);
      if (!mounted) return;
      _invalidateTx();
      AppSnackbar.success(context, 'Marked out for delivery.');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not update status. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _shipping = false);
    }
  }

  /// Seller-only primary action. Renders immediately from the role/status
  /// snapshot handed in by Home/History (`tx.myRole` + `tx.apiStatus`), then
  /// reconciles with the authoritative background refetch
  /// ([transactionDetailProvider]) — so a seller sees Verify Delivery right
  /// away instead of after a network round-trip, and a buyer never sees a
  /// seller button flash in. Shows nothing (never a wrong action) when the
  /// role/status is still unknown.
  /// Returns null (never an empty placeholder) when there's nothing to show,
  /// so the caller can collapse the whole bottom action bar instead of
  /// leaving dangling empty space.
  Widget? _buildSellerActionSlot(BuildContext context) {
    final detailAsync = ref.watch(transactionDetailProvider(tx.id));
    final isSeller = detailAsync.maybeWhen(
      data: (f) => f.isSeller,
      orElse: () => tx.myRole == 'seller',
    );
    if (!isSeller) return null;

    final status = detailAsync.maybeWhen(
      data: (f) => f.status,
      orElse: () => tx.apiStatus,
    );
    if (status == null) return null;

    switch (status) {
      case ApiTxStatus.paymentReceived:
      case ApiTxStatus.awaitingDispatch:
        return AppButton(
          label: 'Start delivery',
          trailingIcon: Icons.local_shipping_rounded,
          accentInLime: true,
          loading: _shipping,
          enabled: !_shipping,
          onPressed: _startDelivery,
        );
      case ApiTxStatus.inTransit:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: 'Verify delivery',
              trailingIcon: Icons.lock_open_rounded,
              accentInLime: true,
              onPressed: () =>
                  AppNav.push(context, ConfirmDeliveryScreen(draft: _draft)),
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Mark out for delivery',
              icon: Icons.moving_rounded,
              variant: AppButtonVariant.outline,
              loading: _shipping,
              enabled: !_shipping,
              onPressed: _markOutForDelivery,
            ),
          ],
        );
      case ApiTxStatus.outForDelivery:
        return AppButton(
          label: 'Verify delivery',
          trailingIcon: Icons.lock_open_rounded,
          accentInLime: true,
          onPressed: () =>
              AppNav.push(context, ConfirmDeliveryScreen(draft: _draft)),
        );
      default:
        return null;
    }
  }

  /// Statuses where checking the live map is actually meaningful — from
  /// funding through active delivery. Hidden once delivery is confirmed
  /// (cooling and beyond) or the transaction is disputed/terminated, where a
  /// map has nothing useful left to show (see [_buildCoolingSlot] instead).
  static const _trackableStatuses = {
    ApiTxStatus.paymentReceived,
    ApiTxStatus.awaitingDispatch,
    ApiTxStatus.inTransit,
    ApiTxStatus.outForDelivery,
  };

  /// Null status (still loading, no snapshot) defaults to showing the button
  /// — matches prior behaviour and avoids hiding it for a transaction we
  /// simply haven't classified yet.
  bool _isTrackableStatus(ApiTxStatus? status) =>
      status == null || _trackableStatuses.contains(status);

  /// Buyer-only: the delivery code to share with the seller once the product
  /// arrives. Role is resolved snapshot-first (so a buyer isn't briefly treated
  /// as a seller); silently hides on loading/error/already-confirmed/no-code.
  Widget _buildDeliveryCodeSlot(BuildContext context) {
    final isBuyer = ref
        .watch(transactionDetailProvider(tx.id))
        .maybeWhen(data: (f) => f.isBuyer, orElse: () => tx.myRole == 'buyer');
    if (!isBuyer) return const SizedBox.shrink();
    final codeAsync = ref.watch(deliveryCodeProvider(tx.id));
    return codeAsync.maybeWhen(
      data: (dc) {
        if (dc.alreadyConfirmed || dc.code == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSizes.md),
          child: _DeliveryCodeCard(code: dc.code!),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  /// Real cooling-period card, shown only once the transaction has actually
  /// reached a cooling-relevant status. Reuses [transactionDetailProvider]
  /// (the full `ApiTransaction`, with `coolingEndsAt`/`timeline`) rather than
  /// adding a new provider — [trackingProvider] above doesn't carry these
  /// fields, since that response is intentionally scoped to tracking only.
  Widget _buildCoolingSlot(BuildContext context) {
    final detailAsync = ref.watch(transactionDetailProvider(tx.id));
    // Same cached provider instance as _buildVerifyDeliverySlot — no extra fetch.
    final isSeller = ref
        .watch(trackingProvider(tx.id))
        .maybeWhen(data: (t) => t.isSeller, orElse: () => false);
    final disputes = ref
        .watch(transactionDisputesProvider(tx.id))
        .maybeWhen(data: (d) => d, orElse: () => const <Dispute>[]);
    return detailAsync.maybeWhen(
      data: (full) {
        const relevant = {
          ApiTxStatus.cooling,
          ApiTxStatus.released,
          ApiTxStatus.completed,
          ApiTxStatus.disputed,
        };
        if (!relevant.contains(full.status)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSizes.md),
          child: _CoolingPeriodCard(
            tx: full,
            isSeller: isSeller,
            disputes: disputes,
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  PaymentDraft get _draft => PaymentDraft(
    productName: tx.productName,
    sellerName: tx.merchantName,
    sellerCode: tx.code,
    itemSubtotal: tx.amount,
    variant: tx.variant,
    transactionId: tx.id,
  );

  // The transaction model doesn't carry seller reputation yet, so show
  // representative values until the merchant profile is wired to the API.
  String get _trustScore => 'A+';
  int get _successfulTx => 128;

  // Product category isn't on the model yet; keep the Escrow badge for now.
  String get _category => 'Escrow';

  void _copy(BuildContext context, String value, String message) {
    if (value.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    AppSnackbar.success(context, message);
  }

  String _joinNonEmpty(List<String?> values, {String separator = ' · '}) =>
      values
          .where((v) => (v ?? '').trim().isNotEmpty)
          .map((v) => v!.trim())
          .join(separator);

  @override
  Widget build(BuildContext context) {
    final buyerInfo = _joinNonEmpty([tx.buyerName, tx.buyerContact]);
    final deliveryEta = _joinNonEmpty([
      tx.estimatedDeliveryDate,
      tx.estimatedDeliveryTime,
    ]);
    final deliveryAddress = (tx.deliveryAddress ?? '').trim();
    final buyerContact = (tx.buyerContact ?? '').trim();
    final dispatcherLabel = buyerInfo.isNotEmpty ? buyerInfo : tx.merchantName;
    // Same cached provider instance _buildCoolingSlot already watches — no
    // extra fetch. Lets the escrow timeline reflect a mutation that happened
    // on another screen (confirm delivery / release / dispute) without
    // requiring the user to fully leave and re-enter this screen.
    final liveStatus = ref
        .watch(transactionDetailProvider(tx.id))
        .maybeWhen(data: (full) => full.status, orElse: () => null);

    // Snapshot-first (liveStatus while loading falls back to the list
    // snapshot) so Track Package doesn't flicker in/out while the live
    // status is still resolving.
    final sellerAction = _buildSellerActionSlot(context);
    final showTrackPackage = _isTrackableStatus(liveStatus ?? tx.apiStatus);
    final bottomChildren = <Widget>[
      ?sellerAction,
      if (sellerAction != null && showTrackPackage)
        const SizedBox(height: AppSizes.sm),
      if (showTrackPackage)
        AppButton(
          label: 'Track package',
          icon: Icons.local_shipping_outlined,
          variant: AppButtonVariant.soft,
          loading: _checkingTracking,
          enabled: !_checkingTracking,
          onPressed: _onTrackPackage,
        ),
    ];

    return AppScaffold(
      title: 'Transaction',
      trailing: const AppIconButton(icon: Icons.more_horiz_rounded),
      scrollable: true,
      // No dangling empty bottom bar once delivery is confirmed (cooling and
      // beyond) — both actions collapse cleanly instead of showing padding
      // with nothing in it.
      bottomAction: bottomChildren.isEmpty
          ? null
          : Column(mainAxisSize: MainAxisSize.min, children: bottomChildren),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.sm),
          _SellerCard(
            tx: tx,
            trustScore: _trustScore,
            successfulTx: _successfulTx,
            onTap: () => AppNav.push(context, const MerchantProfileScreen()),
          ),
          const SizedBox(height: AppSizes.md),
          _ProductCard(tx: tx, category: _category),
          const SizedBox(height: AppSizes.md),
          _BuyerInfoCard(
            buyerLabel: buyerInfo,
            buyerContact: buyerContact,
            deliveryAddress: deliveryAddress,
            eta: deliveryEta,
            onCopyAddress: () =>
                _copy(context, deliveryAddress, 'Delivery address copied'),
            onCopyContact: () =>
                _copy(context, buyerContact, 'Buyer contact copied'),
          ),
          const SizedBox(height: AppSizes.md),
          _buildDeliveryCodeSlot(context),
          _EscrowStatusCard(
            tx: tx,
            dispatcherLabel: dispatcherLabel,
            eta: deliveryEta,
            liveStatus: liveStatus,
          ),
          _buildCoolingSlot(context),
          const SizedBox(height: AppSizes.md),
          const _ReleaseBanner(),
          const SizedBox(height: AppSizes.md),
          _PaidCard(total: tx.amount),
          const SizedBox(height: AppSizes.md),
          _DeliveryDetailsCard(
            address: deliveryAddress.isEmpty ? 'Not provided' : deliveryAddress,
            dispatcher: dispatcherLabel.isEmpty
                ? 'Not provided'
                : dispatcherLabel,
            eta: deliveryEta.isEmpty ? 'Not available' : deliveryEta,
            onAddress: () =>
                _copy(context, deliveryAddress, 'Delivery address copied'),
            onDispatcher: () =>
                _copy(context, buyerContact, 'Buyer contact copied'),
            onEta: _onTrackPackage,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Buyer-only card showing the plaintext delivery code — the seller asks for
/// this in person and enters it themselves once within range; the seller
/// never sees this card or the code.
class _DeliveryCodeCard extends StatelessWidget {
  const _DeliveryCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('Delivery code'),
          const SizedBox(height: AppSizes.md),
          Center(
            child: Text(
              code,
              style: AppText.display.copyWith(fontSize: 34, letterSpacing: 8),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.info_outline_rounded,
            text: 'Share this code only after receiving the product.',
          ),
        ],
      ),
    );
  }
}

/// Real cooling-period summary — status, real coolingEndsAt-derived remaining
/// time note, escrow amount, and a link to the full [CoolingPeriodScreen].
/// Shows a safe fallback line rather than any countdown when coolingEndsAt is
/// missing (older transactions, or a transaction that never reached cooling).
class _CoolingPeriodCard extends StatelessWidget {
  const _CoolingPeriodCard({
    required this.tx,
    required this.isSeller,
    required this.disputes,
  });
  final ApiTransaction tx;
  final bool isSeller;
  final List<Dispute> disputes;

  DateTime? get _coolingStart {
    for (final e in tx.timeline) {
      if (e.event == 'cooling_started' && e.at != null) return e.at;
    }
    for (final e in tx.timeline) {
      if (e.event == 'delivered' && e.at != null) return e.at;
    }
    return null;
  }

  String _statusNote(DateTime? endsAt) {
    if (endsAt == null) return 'Cooling period details are not available yet.';
    switch (tx.status) {
      case ApiTxStatus.disputed:
        return 'This order is under dispute review. Payout is on hold until it is resolved.';
      case ApiTxStatus.released:
      case ApiTxStatus.completed:
        return 'Payout has been released to the seller.';
      default:
        if (endsAt.isAfter(DateTime.now())) {
          final remaining = endsAt.difference(DateTime.now());
          final hours = remaining.inHours;
          final minutes = remaining.inMinutes.remainder(60);
          return 'Cooling period active — about ${hours}h ${minutes}m remaining.';
        }
        return 'Cooling period completed. Seller payout is now eligible if there is no active dispute.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final endsAt = tx.coolingEndsAt;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: CardSectionLabel('Cooling period')),
              StatusPill(label: tx.status.label, dense: true),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          _InfoRow(
            icon: Icons.check_circle_outline,
            label: 'Delivery confirmed',
            value: _coolingStart != null
                ? Dates.relative(_coolingStart!)
                : 'Not available',
          ),
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Cooling ends',
            value: endsAt != null ? Dates.medium(endsAt) : 'Not available',
          ),
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Escrow amount',
            value: Money.format(tx.itemSubtotalNaira),
          ),
          const SizedBox(height: AppSizes.md),
          Text(_statusNote(endsAt), style: AppText.body),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.info_outline_rounded,
            text:
                'The buyer can raise a dispute during the cooling period. Seller payout unlocks after this period if no dispute is raised.',
          ),
          const SizedBox(height: AppSizes.md),
          // Full-width stacked actions — never side-by-side — so long labels
          // never overflow on small screens (works for buyer and seller).
          AppButton(
            label: 'View Cooling Period',
            variant: AppButtonVariant.outline,
            onPressed: () =>
                AppNav.push(context, CoolingPeriodScreen(transactionId: tx.id)),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Settlement Ledger',
            variant: AppButtonVariant.soft,
            onPressed: () => AppNav.push(
              context,
              SettlementLedgerScreen(transactionId: tx.id),
            ),
          ),
          if (isSeller) ...[
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Seller Settlement',
              icon: Icons.account_balance_outlined,
              variant: AppButtonVariant.outline,
              onPressed: () => AppNav.push(
                context,
                SellerSettlementScreen(transactionId: tx.id),
              ),
            ),
          ],
          if (disputes.isNotEmpty) ...[
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'View Dispute',
              icon: Icons.flag_outlined,
              variant: AppButtonVariant.soft,
              onPressed: () => AppNav.push(
                context,
                DisputeStatusScreen(disputeId: disputes.last.id),
              ),
            ),
          ] else if (!isSeller && tx.status == ApiTxStatus.cooling) ...[
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Raise Dispute',
              icon: Icons.flag_outlined,
              variant: AppButtonVariant.soft,
              onPressed: () => AppNav.push(
                context,
                DisputeCenterScreen(transactionId: tx.id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
                      child: Text(
                        tx.merchantName,
                        style: AppText.h3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(Icons.verified_rounded, size: 16, color: accent.ring),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
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
                      child: Text(
                        '· $successfulTx successful transactions',
                        style: AppText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
// class _SellerCard extends StatelessWidget {
//   const _SellerCard({required this.tx});
//   final EscrowTransaction tx;

//   @override
//   Widget build(BuildContext context) {
//     final accent = AppAccent.of(context);
//     return AppCard(
//       child: Row(
//         children: [
//           Hero(
//             tag: 'txn-avatar-${tx.id}',
//             child: InitialsAvatar(initials: tx.merchantInitials, size: 46),
//           ),
//           const SizedBox(width: AppSizes.md),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Row(
//                   children: [
//                     Flexible(
//                       child: Text(tx.merchantName, style: AppText.h3, overflow: TextOverflow.ellipsis),
//                     ),
//                     const SizedBox(width: 5),
//                     Icon(Icons.verified_rounded, size: 16, color: accent.ring),
//                   ],
//                 ),
//                 const SizedBox(height: 3),
//                 Text('HTP Verified Seller', style: AppText.caption),
//                 const SizedBox(height: 7),
//                 Text('Transaction ${tx.code}', style: AppText.caption),
//               ],
//             ),
//           ),
//           const SizedBox(width: AppSizes.sm),
//           const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
//         ],
//       ),
//     );
//   }
// }

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.tx, required this.category});

  final EscrowTransaction tx;
  final String category;

  /// Full-screen, pinch-to-zoom preview of the uploaded product photo.
  void _openPreview(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Selling/Buying badge for this transaction (from the snapshot role). Null
  /// when the role is unknown → no badge.
  Widget? _roleBadge() => switch (tx.myRole) {
    'seller' => const StatusPill(
      label: 'Selling',
      icon: Icons.sell_outlined,
      dense: true,
      background: AppColors.ink,
      foreground: AppColors.textOnDark,
    ),
    'buyer' => const StatusPill(
      label: 'Buying',
      icon: Icons.shopping_bag_outlined,
      dense: true,
      background: AppColors.successSoft,
      foreground: AppColors.success,
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final photoUrl = (tx.productPhotoUrl ?? '').trim();
    final roleBadge = _roleBadge();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductThumb(url: tx.productPhotoUrl, size: 88),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category + Selling/Buying role badge (Wrap → no overflow).
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusPill(
                          label: category,
                          dense: true,
                          background: accent.accentSoft,
                          foreground: accent.onAccentSoft,
                        ),
                        ?roleBadge,
                      ],
                    ),
                    const SizedBox(height: AppSizes.sm),
                    Text(tx.productName, style: AppText.h3),
                    const SizedBox(height: 3),
                    Text(
                      '${tx.variant ?? 'Standard'} · Qty 1',
                      style: AppText.caption,
                    ),
                    const SizedBox(height: 2),
                    Text('1 consignment · ${tx.code}', style: AppText.caption),
                    if (photoUrl.isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'No product photo uploaded.',
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
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
              // Only offer "View item" when there's a photo to preview.
              if (photoUrl.isNotEmpty)
                _ViewItemButton(onTap: () => _openPreview(context, photoUrl)),
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
            horizontal: AppSizes.md,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.md,
            border: Border.all(color: AppColors.border, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_outlined, size: 17, color: accent.ring),
              const SizedBox(width: 6),
              Text(
                'View item',
                style: AppText.bodyStrong.copyWith(color: accent.ring),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuyerInfoCard extends StatelessWidget {
  const _BuyerInfoCard({
    required this.buyerLabel,
    required this.buyerContact,
    required this.deliveryAddress,
    required this.eta,
    required this.onCopyAddress,
    required this.onCopyContact,
  });

  final String buyerLabel;
  final String buyerContact;
  final String deliveryAddress;
  final String eta;
  final VoidCallback onCopyAddress;
  final VoidCallback onCopyContact;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardSectionLabel('Buyer details'),
          const SizedBox(height: AppSizes.md),
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Buyer',
            value: buyerLabel.isEmpty ? 'Not provided' : buyerLabel,
            onTap: onCopyContact,
          ),
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Delivery address',
            value: deliveryAddress.isEmpty ? 'Not provided' : deliveryAddress,
            onTap: onCopyAddress,
          ),
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Estimated delivery',
            value: eta.isEmpty ? 'Not provided' : eta,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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

class _EscrowStatusCard extends StatelessWidget {
  const _EscrowStatusCard({
    required this.tx,
    required this.dispatcherLabel,
    required this.eta,
    this.liveStatus,
  });
  final EscrowTransaction tx;
  final String dispatcherLabel;
  final String eta;

  /// Real-time status from `transactionDetailProvider`, when available —
  /// takes priority over `tx`'s frozen snapshot so this timeline doesn't go
  /// stale after a mutation (confirm delivery / release / dispute) that
  /// happened on another screen while this one stayed mounted underneath.
  final ApiTxStatus? liveStatus;

  @override
  Widget build(BuildContext context) {
    final live = liveStatus;
    final bool done;
    final bool paid;
    final bool inTransit;
    final bool outForDelivery;
    if (live != null) {
      done = live == ApiTxStatus.released || live == ApiTxStatus.completed;
      paid =
          live != ApiTxStatus.draft &&
          live != ApiTxStatus.awaitingAgreement &&
          live != ApiTxStatus.awaitingPayment;
      inTransit =
          paid &&
          (live == ApiTxStatus.inTransit ||
              live == ApiTxStatus.outForDelivery ||
              live == ApiTxStatus.delivered ||
              live == ApiTxStatus.cooling ||
              done);
      outForDelivery =
          live == ApiTxStatus.outForDelivery ||
          live == ApiTxStatus.delivered ||
          live == ApiTxStatus.cooling ||
          done;
    } else {
      done = tx.stage == TxStage.done || tx.status == TxStatus.released;
      paid = tx.status != TxStatus.awaitingDispatch;
      inTransit =
          tx.status == TxStatus.inTransit ||
          tx.status == TxStatus.outForDelivery ||
          tx.status == TxStatus.delivered ||
          done;
      outForDelivery =
          tx.status == TxStatus.outForDelivery ||
          tx.status == TxStatus.delivered ||
          done;
    }

    final steps = <_StepData>[
      _StepData(
        state: paid ? _StepState.done : _StepState.current,
        icon: Icons.account_balance_wallet_outlined,
        title: 'Paid into escrow',
        lines: paid ? ['Payment secured'] : ['Awaiting buyer payment'],
      ),
      _StepData(
        state: inTransit ? _StepState.done : _StepState.current,
        icon: Icons.local_shipping_outlined,
        title: 'In transit',
        lines: inTransit ? ['Package is moving'] : ['Waiting for dispatch'],
      ),
      _StepData(
        state: outForDelivery ? _StepState.done : _StepState.current,
        icon: Icons.local_shipping_outlined,
        title: 'Out for delivery',
        lines: outForDelivery
            ? [dispatcherLabel, if (eta.isNotEmpty) eta]
            : ['Near destination'],
      ),
      _StepData(
        state: done ? _StepState.done : _StepState.pending,
        icon: Icons.inventory_2_outlined,
        title: 'Delivered & released',
        lines: done
            ? ['Funds released to seller']
            : ['Confirm delivery to release payment'],
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
    final done = step.state == _StepState.done;
    final current = step.state == _StepState.current;
    final filled = step.state != _StepState.pending;
    final circleColor = filled ? accent.accent : AppColors.surfaceMuted;
    final iconColor = filled ? accent.onAccent : AppColors.textTertiary;
    final glyph = done ? Icons.check_rounded : step.icon;
    final lineColor = done ? accent.accent : AppColors.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (current)
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.accent.withValues(alpha: 0.18),
                      ),
                    ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: filled ? accent.accent : AppColors.border,
                      ),
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
              padding: EdgeInsets.only(
                top: 5,
                bottom: isLast ? 0 : AppSizes.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: done
                        ? AppText.bodyStrong
                        : AppText.body.copyWith(fontWeight: FontWeight.w600),
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
          Icon(
            Icons.verified_user_outlined,
            size: 22,
            color: accent.onAccentSoft,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.caption.copyWith(height: 1.5),
                children: const [
                  TextSpan(
                    text:
                        'Payment will be released once delivery is verified.\n',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text:
                        'Your funds are held securely in escrow until delivery is verified.',
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

class _PaidCard extends StatelessWidget {
  const _PaidCard({required this.total});
  final double total;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.success),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paid into escrow', style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  'Funds are protected until delivery is confirmed.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          Text(Money.format(total), style: AppText.bodyStrong),
        ],
      ),
    );
  }
}

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardSectionLabel('Delivery details'),
          const SizedBox(height: AppSizes.md),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: address,
            onTap: onAddress,
          ),
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.person_pin_circle_outlined,
            label: 'Buyer contact',
            value: dispatcher,
            onTap: onDispatcher,
          ),
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'ETA',
            value: eta,
            onTap: onEta,
          ),
        ],
      ),
    );
  }
}

/// Result of the dispatch-proof sheet. A non-null return means the seller
/// confirmed Start Delivery; [url] is the uploaded proof (null when skipped —
/// the proof is optional). A null return means they dismissed/cancelled.
class _DispatchProofResult {
  const _DispatchProofResult(this.url);
  final String? url;
}

/// Optional dispatch-proof capture shown when the seller starts delivery. The
/// photo is uploaded via the existing upload service and stored separately from
/// the item's product photo. A failed upload never reports success.
class _DispatchProofSheet extends ConsumerStatefulWidget {
  const _DispatchProofSheet();

  @override
  ConsumerState<_DispatchProofSheet> createState() =>
      _DispatchProofSheetState();
}

class _DispatchProofSheetState extends ConsumerState<_DispatchProofSheet> {
  XFile? _file;
  String? _url;
  bool _uploading = false;

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    setState(() {
      _file = picked;
      _uploading = true;
    });
    try {
      final url = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(picked.path);
      if (!mounted) return;
      setState(() => _url = url);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _file = null;
        _url = null;
      });
      AppSnackbar.error(context, e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _file = null;
        _url = null;
      });
      AppSnackbar.error(context, 'Could not upload photo. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.rXl)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadii.pill,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text('Dispatch proof', style: AppText.h3),
          const SizedBox(height: 4),
          Text(
            'Upload parcel, packing, courier, or handover proof. Optional, but '
            'recommended as your evidence if a dispute is raised.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSizes.lg),
          if (_file == null)
            AppButton(
              label: 'Add dispatch photo',
              icon: Icons.add_a_photo_outlined,
              variant: AppButtonVariant.outline,
              enabled: !_uploading,
              onPressed: _pick,
            )
          else
            Container(
              padding: const EdgeInsets.all(AppSizes.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadii.md,
              ),
              child: Row(
                children: [
                  Icon(
                    _uploading
                        ? Icons.hourglass_top_rounded
                        : Icons.check_circle_rounded,
                    size: 20,
                    color: _uploading
                        ? AppColors.textSecondary
                        : AppColors.success,
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: Text(
                      _uploading ? 'Uploading…' : 'Dispatch photo attached',
                      style: AppText.bodyStrong,
                    ),
                  ),
                  if (!_uploading)
                    GestureDetector(
                      onTap: () => setState(() {
                        _file = null;
                        _url = null;
                      }),
                      child: Text(
                        'Remove',
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSizes.lg),
          AppButton(
            label: 'Start delivery',
            trailingIcon: Icons.local_shipping_rounded,
            accentInLime: true,
            loading: _uploading,
            enabled: !_uploading,
            onPressed: () =>
                Navigator.of(context).pop(_DispatchProofResult(_url)),
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.soft,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
