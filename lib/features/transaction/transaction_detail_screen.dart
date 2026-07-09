import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/env/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/network/socket_service.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/dispute_dto.dart';
import '../../data/dto/merchant_dto.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
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

/// Statuses where Track Package is actually meaningful — from funding through
/// active delivery. Shared with the push-tap router in `app.dart` (a
/// `dispatcher_nearby` tap should only open Track Package when it's actually
/// showable; otherwise it falls back to Transaction Details) so both agree on
/// when navigating there makes sense. Null status (no snapshot yet) defaults
/// to true, matching this screen's own prior behaviour.
bool isTrackableTransactionStatus(ApiTxStatus? status) =>
    status == null ||
    const {
      ApiTxStatus.paymentReceived,
      ApiTxStatus.awaitingDispatch,
      ApiTxStatus.inTransit,
      ApiTxStatus.outForDelivery,
    }.contains(status);

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.tx});
  final EscrowTransaction tx;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen>
    with WidgetsBindingObserver {
  EscrowTransaction get tx => widget.tx;

  /// Guards the "Track package" tap: prevents overlapping fetches and drives
  /// the button's loading/disabled state while the real transaction is
  /// re-fetched to check whether it actually has delivery coordinates.
  bool _checkingTracking = false;

  /// Guards the seller's Start Delivery / Out-for-delivery actions.
  bool _shipping = false;

  StreamSubscription<TransactionSocketEvent>? _socketSub;

  /// Cached at [initState] and reused in [dispose] — `ref.read` is not safe
  /// to call inside `dispose()`: when an element is torn down via Flutter's
  /// deferred/batched unmount path (multiple screens popping in one frame,
  /// a Navigator replace, etc.) rather than a synchronous `deactivate()`,
  /// Riverpod may have already flagged its `ref` disposed by the time
  /// `dispose()` runs, and `ref.read` throws `StateError: Cannot use "ref"
  /// after the widget was disposed`. The service itself never changes for
  /// the life of this screen, so grabbing it once up front sidesteps that
  /// entirely.
  late final SocketService _socket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _socket = ref.read(socketServiceProvider);
    _socket.joinTransaction(tx.id);
    // Realtime — instant update the moment the other party changes this
    // exact transaction (seller confirms delivery, payout releases, a
    // dispute is raised…) while this screen is open. Filtered to this
    // transaction's id: the same event stream also carries every OTHER
    // transaction the user is a party to (for the app-wide Home/History
    // refresh in app.dart), which this screen has no reason to react to.
    _socketSub = _socket.events.where((e) => e.transactionId == tx.id).listen((
      event,
    ) {
      AppLogger.debug(
        '[socket] provider invalidation triggered: tx=${tx.id} '
        'type=${event.type} status=${event.status}',
      );
      _invalidateTx();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _socketSub?.cancel();
    _socket.leaveTransaction(tx.id);
    super.dispose();
  }

  /// No socket/live-update service exists in this app yet, so the app-resume
  /// lifecycle event is the substitute "live update" signal: if the buyer or
  /// seller backgrounds the app while the other side changes the transaction
  /// (pays, ships, confirms delivery…), coming back to the foreground
  /// re-syncs instead of showing whatever was cached when they left.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invalidateTx();
  }

  /// Pull-to-refresh: re-syncs and waits for the transaction detail fetch to
  /// land before the indicator releases (so a fast pull still shows the
  /// spinner for a beat instead of resolving before anything changed).
  Future<void> _refresh() async {
    _invalidateTx();
    await ref.read(transactionDetailProvider(tx.id).future);
  }

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

  /// Re-syncs everything this screen reads that a lifecycle action (ship,
  /// confirm delivery elsewhere, resume from background, pull-to-refresh)
  /// could have changed. Single source of truth for what to invalidate, so
  /// every trigger (action success, app resume, pull-to-refresh) refreshes
  /// the same set — never a partial refresh that leaves one card stale.
  void _invalidateTx() {
    ref.invalidate(transactionDetailProvider(tx.id));
    ref.invalidate(deliveryCodeProvider(tx.id));
    ref.invalidate(trackingProvider(tx.id));
    ref.invalidate(transactionLedgerProvider(tx.id));
    ref.invalidate(transactionDisputesProvider(tx.id));
    ref.invalidate(transactionsProvider);
    // The seller's stats (completed/active/cooling/disputes) can shift on
    // any lifecycle event on this transaction — keep the whole merchant
    // profile family fresh rather than tracking which merchantId to target.
    ref.invalidate(merchantProfileProvider);
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

  /// Seller-only primary action — always driven by the fresh
  /// [transactionDetailProvider] fetch, never the frozen Home/History
  /// snapshot: a wrong action button (e.g. Start Delivery lingering after the
  /// backend already moved to in_transit) is worse than a brief skeleton.
  /// While the first fetch for this transaction hasn't resolved at all yet
  /// (`!hasValue` — true first paint only, not a later background refetch,
  /// which keeps its previous value via Riverpod's automatic
  /// `copyWithPrevious`), this returns null and lets the caller's own
  /// role-agnostic skeleton (see `showInitialActionSkeleton` in `build()`)
  /// reserve the space instead — a buyer's Track Package button needs the
  /// exact same first-load placeholder, not just the seller's actions.
  /// Returns null (never an empty placeholder) when there's nothing to show,
  /// so the caller can collapse the whole bottom action bar instead of
  /// leaving dangling empty space.
  Widget? _buildSellerActionSlot(BuildContext context) {
    final detailAsync = ref.watch(transactionDetailProvider(tx.id));
    if (!detailAsync.hasValue) return null;
    final full = detailAsync.value!;
    if (!full.isSeller) return null;
    // A background refetch is in flight (e.g. after app resume / pull to
    // refresh) but we still have the last-known-good status — keep showing
    // it (no layout jump) but block the irreversible actions until the fresh
    // status is confirmed, so a stale "Start delivery" can't be double-fired
    // against a transaction that already moved on.
    final refreshing = detailAsync.isLoading;

    switch (full.status) {
      case ApiTxStatus.paymentReceived:
      case ApiTxStatus.awaitingDispatch:
        return AppButton(
          label: 'Start delivery',
          trailingIcon: Icons.local_shipping_rounded,
          accentInLime: true,
          loading: _shipping,
          enabled: !_shipping && !refreshing,
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
              enabled: !refreshing,
              onPressed: () =>
                  AppNav.push(context, ConfirmDeliveryScreen(draft: _draft)),
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Mark out for delivery',
              icon: Icons.moving_rounded,
              variant: AppButtonVariant.outline,
              loading: _shipping,
              enabled: !_shipping && !refreshing,
              onPressed: _markOutForDelivery,
            ),
          ],
        );
      case ApiTxStatus.outForDelivery:
        return AppButton(
          label: 'Verify delivery',
          trailingIcon: Icons.lock_open_rounded,
          accentInLime: true,
          enabled: !refreshing,
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
      isTrackableTransactionStatus(status);

  /// Buyer-only: the delivery code to share with the seller once the product
  /// arrives. Gated on the FRESH transaction status (never the snapshot) so
  /// it can't keep showing after the seller has already confirmed delivery
  /// elsewhere — that's the whole card, hidden the moment status moves past
  /// "in delivery" (see [_trackableStatuses]: paid/in_transit/out_for_delivery
  /// only). `deliveryCodeProvider` is the second, independent confirmation —
  /// its own `alreadyConfirmed`/`code == null` also hides the card, using
  /// whatever value it has (fresh or still-cached-during-refetch) rather than
  /// falling back to nothing while a background refresh is in flight.
  Widget _buildDeliveryCodeSlot(BuildContext context) {
    final detailAsync = ref.watch(transactionDetailProvider(tx.id));
    if (!detailAsync.hasValue) {
      // Only reserve the delivery-code space on first load when the frozen
      // snapshot already puts us in a delivery phase where a buyer would
      // actually see the code. Reserving it for every buyer (then collapsing it
      // for non-delivery statuses once fresh data lands) jumped the layout — and
      // a shaped skeleton matches the real card so nothing shifts when it fills.
      final expectCode =
          tx.myRole == 'buyer' && _trackableStatuses.contains(tx.apiStatus);
      return expectCode
          ? const Padding(
              padding: EdgeInsets.only(bottom: AppSizes.md),
              child: _DeliveryCodeSkeleton(),
            )
          : const SizedBox.shrink();
    }
    final full = detailAsync.value!;
    if (!full.isBuyer || !_trackableStatuses.contains(full.status)) {
      return const SizedBox.shrink();
    }
    final dc = ref.watch(deliveryCodeProvider(tx.id)).valueOrNull;
    if (dc == null || dc.alreadyConfirmed || dc.code == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: _DeliveryCodeCard(code: dc.code!),
    );
  }

  /// Real cooling-period card, shown only once the transaction has actually
  /// reached a cooling-relevant status. Reuses [transactionDetailProvider]
  /// (the full `ApiTransaction`, with `coolingEndsAt`/`timeline`) rather than
  /// adding a new provider. Uses whatever value the providers currently have
  /// (fresh or cached-during-refetch via `valueOrNull`) instead of collapsing
  /// to nothing on every background refresh — that was hiding/re-showing this
  /// card on every invalidate even though nothing actually changed.
  Widget _buildCoolingSlot(BuildContext context) {
    final full = ref.watch(transactionDetailProvider(tx.id)).valueOrNull;
    if (full == null) return const SizedBox.shrink();
    // Includes `delivered` (not just `cooling` and beyond) so there's no dead
    // zone right after the seller confirms delivery: Delivery Code is already
    // hidden by then (it's not in `_trackableStatuses`), and this card must
    // be showing by the same moment — never a gap where neither is visible.
    const relevant = {
      ApiTxStatus.delivered,
      ApiTxStatus.cooling,
      ApiTxStatus.released,
      ApiTxStatus.completed,
      ApiTxStatus.disputed,
    };
    if (!relevant.contains(full.status)) return const SizedBox.shrink();
    // trackingProvider is the pre-existing source for isSeller here; fall
    // back to the detail fetch's own isSeller (same field, same backend
    // truth) rather than a hardcoded `false` while tracking hasn't resolved.
    final isSeller =
        ref.watch(trackingProvider(tx.id)).valueOrNull?.isSeller ??
        full.isSeller;
    final disputes =
        ref.watch(transactionDisputesProvider(tx.id)).valueOrNull ??
        const <Dispute>[];
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.md),
      child: _CoolingPeriodCard(
        tx: full,
        isSeller: isSeller,
        disputes: disputes,
      ),
    );
  }

  /// Prominent card whenever an unresolved dispute exists on this transaction,
  /// for either party. The counter-party (the side that didn't raise it) also
  /// gets a Respond action; both open the full [DisputeStatusScreen], which
  /// re-checks eligibility and hosts the response form. Uses whatever value the
  /// provider currently has (fresh or cached-during-refetch) so it doesn't
  /// flicker away on every background refresh.
  Widget _buildDisputeSlot(BuildContext context) {
    final disputes =
        ref.watch(transactionDisputesProvider(tx.id)).valueOrNull ??
        const <Dispute>[];
    if (disputes.isEmpty) return const SizedBox.shrink();
    final dispute = disputes.lastWhere(
      (d) => !d.isResolved,
      orElse: () => disputes.last,
    );
    if (dispute.isResolved) return const SizedBox.shrink();

    final detail = ref.watch(transactionDetailProvider(tx.id)).valueOrNull;
    final myRole = detail?.isSeller == true
        ? 'seller'
        : detail?.isBuyer == true
        ? 'buyer'
        : tx.myRole;
    // Only the OTHER party can respond, and only once, before resolution.
    final canRespond =
        myRole != null &&
        myRole != dispute.raisedByRole &&
        !dispute.hasResponse;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: _DisputeCard(dispute: dispute, canRespond: canRespond),
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
    final buyerName = (tx.buyerName ?? '').trim();
    final deliveryEta = _joinNonEmpty([
      tx.estimatedDeliveryDate,
      tx.estimatedDeliveryTime,
    ]);
    final deliveryAddress = (tx.deliveryAddress ?? '').trim();
    final buyerContact = (tx.buyerContact ?? '').trim();
    // The courier arranged by the seller at Create Transaction — never the
    // buyer/seller themselves. Empty until one has actually been assigned;
    // the card shows a professional fallback rather than guessing.
    final dispatcherName = (tx.dispatcherName ?? '').trim();
    final dispatcherPhone = (tx.dispatcherPhone ?? '').trim();
    // Same cached provider instance _buildCoolingSlot/_buildSellerActionSlot
    // already watch — no extra fetch. `.valueOrNull` (not `.maybeWhen(data:)`)
    // so this keeps the last-known status during a background refetch
    // instead of reverting to nothing/stale mid-screen.
    final detailAsync = ref.watch(transactionDetailProvider(tx.id));
    final liveStatus = detailAsync.valueOrNull?.status;
    // The real seller identity only exists on the live detail (never the
    // demo/legacy tx snapshot) — the Seller Card's trust badge and the
    // Merchant Profile navigation both wait on this instead of showing a
    // placeholder trust score.
    final sellerId = detailAsync.valueOrNull?.sellerId;
    final merchantAsync = sellerId == null
        ? null
        : ref.watch(merchantProfileProvider(sellerId));
    // A refetch is in flight but we still have a previous value — surface the
    // small "Updating…" indicator rather than silently swapping data under
    // the user, or blocking the screen with a full-page spinner.
    final isUpdating = detailAsync.isLoading && detailAsync.hasValue;

    // Seller + still-unpaid → surface the re-shareable Buyer Payment Link card
    // (and hide the "money is in escrow" banners that would contradict it).
    // Falls back to the frozen snapshot's role/status on first paint. The
    // seller can never pay it — the card offers copy/share only.
    final isSellerView =
        detailAsync.valueOrNull?.isSeller ?? (tx.myRole == 'seller');
    final effStatus = liveStatus ?? tx.apiStatus;
    const unpaidStatuses = {
      ApiTxStatus.draft,
      ApiTxStatus.awaitingAgreement,
      ApiTxStatus.awaitingPayment,
    };
    final showPaymentLink =
        isSellerView && effStatus != null && unpaidStatuses.contains(effStatus);

    // Track Package waits for the fresh fetch too (Issue 1/4) — the seller
    // action slot and delivery-code slot already gate themselves the same way.
    final sellerAction = _buildSellerActionSlot(context);
    final showTrackPackage =
        detailAsync.hasValue && _isTrackableStatus(liveStatus);
    // First paint only (never a background refetch — `hasValue` covers
    // that): we know a role from the snapshot, so SOMETHING plausible could
    // land in the bottom bar (seller actions or Track Package) — reserve a
    // skeleton instead of leaving it empty and then popping content in once
    // the fetch resolves. A transaction with no known role yet shows nothing,
    // same as before — never a guess.
    final showInitialActionSkeleton =
        !detailAsync.hasValue && tx.myRole != null;
    final bottomChildren = <Widget>[
      if (showInitialActionSkeleton) const _ActionBarSkeleton(),
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
      // Scrolling/padding is built by hand below (RefreshIndicator needs to
      // be the ancestor of the actual Scrollable — AppScaffold's own
      // `scrollable: true` would put it the wrong way round).
      scrollable: false,
      padding: EdgeInsets.zero,
      // No dangling empty bottom bar once delivery is confirmed (cooling and
      // beyond) — both actions collapse cleanly instead of showing padding
      // with nothing in it. When there IS something to show, AnimatedSwitcher
      // fades between skeleton / one action set / another instead of an
      // abrupt swap, keyed on a signature so it only transitions when the
      // content actually changes.
      bottomAction: bottomChildren.isEmpty
          ? null
          : AnimatedSwitcher(
              duration: AppDurations.normal,
              child: Column(
                key: ValueKey('${liveStatus?.name}-${detailAsync.hasValue}'),
                mainAxisSize: MainAxisSize.min,
                children: bottomChildren,
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.ink,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: AppSizes.xxl),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSizes.sm),
                AnimatedSize(
                  duration: AppDurations.normal,
                  alignment: Alignment.topCenter,
                  child: isUpdating
                      ? const _UpdatingBanner()
                      : const SizedBox(width: double.infinity),
                ),
                _SellerCard(
                  tx: tx,
                  merchantAsync: merchantAsync,
                  onTap: sellerId == null
                      ? () {}
                      : () => AppNav.push(
                          context,
                          MerchantProfileScreen(merchantId: sellerId),
                        ),
                ),
                const SizedBox(height: AppSizes.md),
                _ProductCard(tx: tx, category: _category),
                const SizedBox(height: AppSizes.md),
                // Prominent dispute banner (either party) when one is active.
                _buildDisputeSlot(context),
                _BuyerInfoCard(
                  buyerName: buyerName,
                  buyerPhone: buyerContact,
                  deliveryAddress: deliveryAddress,
                  eta: deliveryEta,
                  onCopyAddress: () => _copy(
                    context,
                    deliveryAddress,
                    'Delivery address copied',
                  ),
                  onCopyName: () =>
                      _copy(context, buyerName, 'Buyer name copied'),
                ),
                const SizedBox(height: AppSizes.md),
                if (showPaymentLink) ...[
                  _PaymentLinkCard(code: tx.code, amount: tx.amount),
                  const SizedBox(height: AppSizes.md),
                ],
                _buildDeliveryCodeSlot(context),
                _EscrowStatusCard(
                  tx: tx,
                  dispatcherLabel: dispatcherName.isEmpty
                      ? 'Dispatcher not assigned yet'
                      : dispatcherName,
                  eta: deliveryEta,
                  liveStatus: liveStatus,
                ),
                _buildCoolingSlot(context),
                // "Funds held in escrow" banners only make sense once the buyer
                // has actually paid — hidden while the seller still sees the
                // Buyer Payment Link (awaiting payment) card above.
                if (!showPaymentLink) ...[
                  const SizedBox(height: AppSizes.md),
                  const _ReleaseBanner(),
                  const SizedBox(height: AppSizes.md),
                  _PaidCard(total: tx.amount),
                ],
                const SizedBox(height: AppSizes.md),
                _DeliveryDetailsCard(
                  address: deliveryAddress.isEmpty
                      ? 'Not provided'
                      : deliveryAddress,
                  dispatcherName: dispatcherName,
                  dispatcherPhone: dispatcherPhone,
                  eta: deliveryEta.isEmpty ? 'Not available' : deliveryEta,
                  onAddress: () => _copy(
                    context,
                    deliveryAddress,
                    'Delivery address copied',
                  ),
                  onCopyDispatcher: () =>
                      _copy(context, dispatcherName, 'Dispatcher name copied'),
                  onEta: _onTrackPackage,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Button-height shimmer placeholder shown in the bottom action bar until the
/// first fresh [transactionDetailProvider] fetch resolves — never a guessed
/// action button from the frozen list/history snapshot.
class _ActionBarSkeleton extends StatelessWidget {
  const _ActionBarSkeleton();

  @override
  Widget build(BuildContext context) => const AppShimmerBox(
    width: double.infinity,
    height: AppSizes.buttonHeight,
  );
}

/// Small top-of-screen indicator shown while a background refetch is in
/// flight but the screen still has data to show (app resume, pull-to-refresh,
/// or right after a lifecycle action) — makes it clear the visible data is
/// being reconciled instead of silently swapping it under the user.
class _UpdatingBanner extends StatelessWidget {
  const _UpdatingBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSizes.sm),
          Text('Updating transaction…', style: AppText.caption),
        ],
      ),
    ).animate().fadeIn(duration: 160.ms);
  }
}

/// First-load shimmer shaped like [_DeliveryCodeCard] (label · code · note) so
/// the real card slots in without a layout jump. Blocks only, no fake values.
class _DeliveryCodeSkeleton extends StatelessWidget {
  const _DeliveryCodeSkeleton();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppShimmerBox(width: 96, height: 12, radius: AppRadii.sm),
          const SizedBox(height: AppSizes.lg),
          Center(
            child: AppShimmerBox(width: 180, height: 40, radius: AppRadii.md),
          ),
          const SizedBox(height: AppSizes.lg),
          AppShimmerBox(
            width: double.infinity,
            height: 40,
            radius: AppRadii.md,
          ),
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
    required this.merchantAsync,
    required this.onTap,
  });

  final EscrowTransaction tx;
  // Null while the sellerId isn't known yet (first paint, before the live
  // transaction detail resolves) — never a fabricated trust/verified value.
  final AsyncValue<MerchantProfile>? merchantAsync;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final profile = merchantAsync?.valueOrNull;
    final verified = profile?.isVerified ?? false;
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
                    if (verified) ...[
                      const SizedBox(width: 5),
                      const VerifiedBadge(size: 16),
                    ],
                  ],
                ),
                if (verified) ...[
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
                ],
                const SizedBox(height: 7),
                if (profile == null)
                  const AppShimmerBox(width: 140, height: 14)
                else
                  Row(
                    children: [
                      Text('Trust score', style: AppText.caption),
                      const SizedBox(width: 6),
                      StatusPill(
                        label: profile.stats.trustLabel,
                        dense: true,
                        background: AppColors.successSoft,
                        foreground: AppColors.success,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '· ${profile.stats.completedTransactions} successful transactions',
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
    required this.buyerName,
    required this.buyerPhone,
    required this.deliveryAddress,
    required this.eta,
    required this.onCopyAddress,
    required this.onCopyName,
  });

  final String buyerName;
  final String buyerPhone;
  final String deliveryAddress;
  final String eta;
  final VoidCallback onCopyAddress;
  final VoidCallback onCopyName;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardSectionLabel('Buyer details'),
          const SizedBox(height: AppSizes.md),
          _ContactInfoRow(
            icon: Icons.person_outline_rounded,
            label: 'Buyer',
            name: buyerName.isEmpty ? 'Not provided' : buyerName,
            phone: buyerPhone,
            onTap: onCopyName,
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

/// Contact row shared by Buyer and Dispatcher details — same layout as
/// [_InfoRow] plus a call action on the right. Never renders [phone] as
/// visible text; tapping the row copies [name] instead.
class _ContactInfoRow extends StatelessWidget {
  const _ContactInfoRow({
    required this.icon,
    required this.label,
    required this.name,
    required this.phone,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String name;
  final String phone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: InkWell(
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
                      Text(name, style: AppText.bodyStrong),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        _CallIconButton(phone: phone),
      ],
    );
  }
}

/// Round call button — enabled (and actually dials via the device's phone
/// app) only when a real number is available; otherwise a neutral, disabled
/// icon rather than hiding the action entirely. Never shows the number itself.
class _CallIconButton extends StatelessWidget {
  const _CallIconButton({required this.phone});
  final String phone;

  Future<void> _call(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        AppSnackbar.error(context, 'Could not start a call.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, 'Could not start a call.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = phone.trim().isNotEmpty;
    return Material(
      color: enabled ? AppColors.surfaceMuted : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => _call(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            Icons.call_rounded,
            size: 18,
            color: enabled ? AppColors.ink : AppColors.textTertiary,
          ),
        ),
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
    // A dead-ended transaction (cancelled/refunded/returned/undeliverable, or
    // a status this app build doesn't recognise) has nothing "actively
    // happening right now" — never fabricate an in-progress step for it.
    final bool terminated;
    if (live != null) {
      done = live == ApiTxStatus.released || live == ApiTxStatus.completed;
      paid =
          live != ApiTxStatus.draft &&
          live != ApiTxStatus.awaitingAgreement &&
          live != ApiTxStatus.awaitingPayment;
      // Disputes are raised during/after cooling — i.e. strictly after
      // delivery — so a disputed transaction has already passed through
      // transit/out-for-delivery/delivered; only the release stays open
      // pending resolution. Without this, `disputed` fell through every
      // check below and its whole timeline collapsed back to "pending".
      final pastDelivery =
          live == ApiTxStatus.delivered ||
          live == ApiTxStatus.cooling ||
          live == ApiTxStatus.disputed ||
          done;
      inTransit =
          paid &&
          (live == ApiTxStatus.inTransit ||
              live == ApiTxStatus.outForDelivery ||
              pastDelivery);
      outForDelivery = live == ApiTxStatus.outForDelivery || pastDelivery;
      terminated =
          live == ApiTxStatus.cancelled ||
          live == ApiTxStatus.refunded ||
          live == ApiTxStatus.returned ||
          live == ApiTxStatus.undeliverable ||
          live == ApiTxStatus.unknown;
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
      // The coarse list/history snapshot enum has no cancelled/refunded
      // value — nothing to flag as terminated before the fresh fetch lands.
      terminated = false;
    }

    // Each flag means "this stage has been reached (or passed)" and is
    // monotonic — once true for a stage it stays true for every later
    // status. So the first `false` in order is the ONE step genuinely in
    // progress right now; every flag after it is also false and hasn't
    // started yet (pending) — never "current" just because it isn't done.
    final reached = [paid, inTransit, outForDelivery, done];
    final activeIndex = reached.indexWhere((r) => !r);

    _StepState stateFor(int index) {
      if (reached[index]) return _StepState.done;
      if (index == activeIndex && !terminated) return _StepState.current;
      return _StepState.pending;
    }

    final steps = <_StepData>[
      _StepData(
        state: stateFor(0),
        icon: Icons.account_balance_wallet_outlined,
        title: 'Paid into escrow',
        lines: paid ? ['Payment secured'] : ['Awaiting buyer payment'],
        stopped: terminated && activeIndex == 0,
      ),
      _StepData(
        state: stateFor(1),
        icon: Icons.local_shipping_outlined,
        title: 'In transit',
        lines: inTransit ? ['Package is moving'] : ['Waiting for dispatch'],
        stopped: terminated && activeIndex == 1,
      ),
      _StepData(
        state: stateFor(2),
        icon: Icons.local_shipping_outlined,
        title: 'Out for delivery',
        lines: outForDelivery
            ? [dispatcherLabel, if (eta.isNotEmpty) eta]
            : ['Near destination'],
        stopped: terminated && activeIndex == 2,
      ),
      _StepData(
        state: stateFor(3),
        icon: Icons.inventory_2_outlined,
        title: 'Delivered & released',
        lines: done
            ? ['Funds released to seller']
            : ['Confirm delivery to release payment'],
        stopped: terminated && activeIndex == 3,
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
    this.stopped = false,
  });
  final _StepState state;
  final IconData icon;
  final String title;
  final List<String> lines;

  /// True for the one step where a dead-ended transaction (cancelled /
  /// refunded / returned / undeliverable) stopped — rendered as a distinct
  /// "stopped" style rather than pending grey or a fabricated current step.
  /// Meaningless when [state] is already `done`.
  final bool stopped;
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
    final stopped = !done && step.stopped;

    // Completed keeps the existing brand/accent tick untouched (already the
    // correct, approved look). Current gets its own distinct "in progress"
    // treatment — never the same solid fill as done, and never black even in
    // the Mono theme (where accent.accent is ink). Stopped marks the one
    // step a dead-ended transaction halted at. Anything else is plain
    // pending grey.
    final Color circleColor;
    final Color iconColor;
    final Color borderColor;
    if (done) {
      circleColor = accent.accent;
      iconColor = accent.onAccent;
      borderColor = accent.accent;
    } else if (current) {
      circleColor = AppColors.warning.withValues(alpha: 0.14);
      iconColor = AppColors.warning;
      borderColor = AppColors.warning;
    } else if (stopped) {
      circleColor = AppColors.danger.withValues(alpha: 0.10);
      iconColor = AppColors.danger;
      borderColor = AppColors.danger.withValues(alpha: 0.4);
    } else {
      circleColor = AppColors.surfaceMuted;
      iconColor = AppColors.textTertiary;
      borderColor = AppColors.border;
    }

    final glyph = done
        ? Icons.check_rounded
        : stopped
        ? Icons.close_rounded
        : step.icon;
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
                        color: AppColors.warning.withValues(alpha: 0.18),
                      ),
                    ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: circleColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor),
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

/// Dispatcher details — same professional row styling as [_BuyerInfoCard].
/// The dispatcher is the courier the seller arranged at Create Transaction
/// (`consignments[].payout`); until one is entered, this shows a plain
/// fallback line rather than a broken/empty row.
class _DeliveryDetailsCard extends StatelessWidget {
  const _DeliveryDetailsCard({
    required this.address,
    required this.dispatcherName,
    required this.dispatcherPhone,
    required this.eta,
    required this.onAddress,
    required this.onCopyDispatcher,
    required this.onEta,
  });

  final String address;
  final String dispatcherName;
  final String dispatcherPhone;
  final String eta;
  final VoidCallback onAddress;
  final VoidCallback onCopyDispatcher;
  final VoidCallback onEta;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardSectionLabel('Dispatcher details'),
          const SizedBox(height: AppSizes.md),
          _InfoRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: address,
            onTap: onAddress,
          ),
          const SizedBox(height: AppSizes.sm),
          if (dispatcherName.isEmpty)
            Text(
              'Dispatcher not assigned yet',
              style: AppText.caption.copyWith(color: AppColors.textTertiary),
            )
          else
            _ContactInfoRow(
              icon: Icons.local_shipping_outlined,
              label: 'Dispatcher',
              name: dispatcherName,
              phone: dispatcherPhone,
              onTap: onCopyDispatcher,
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

/// Seller-only, shown while the transaction is still unpaid: a re-shareable
/// Buyer Payment Link so a seller who returns later can copy/share it again.
/// Copy/share only — the seller can never pay their own transaction, and an
/// explicit note says so. Removed the moment the buyer pays (status leaves the
/// unpaid set), replaced by the "Paid into escrow" banner.
class _PaymentLinkCard extends StatelessWidget {
  const _PaymentLinkCard({required this.code, required this.amount});
  final String code;
  final double amount;

  String get _link => '${AppConfig.webBaseUrl}/pay/$code';
  String get _linkDisplay => _link.replaceFirst(RegExp(r'^https?://'), '');
  String get _shareMessage =>
      'Pay securely for your order via Hoppr escrow.\n'
      'Amount: ${Money.format(amount)}\n'
      'Pay here: $_link';

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _link));
    AppSnackbar.success(context, 'Payment link copied');
  }

  Future<void> _shareLink(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(_shareMessage)}',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        AppSnackbar.error(context, 'Could not open a share app.');
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackbar.error(context, 'Could not open a share app.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardSectionLabel('Buyer payment link'),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Share this link with the buyer to collect escrow payment securely.',
            style: AppText.caption,
          ),
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.cardSoft,
              borderRadius: AppRadii.md,
              border: Border.all(color: AppColors.border, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18, color: accent.ring),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    _linkDisplay,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accent.ring,
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                GestureDetector(
                  onTap: () => _copyLink(context),
                  behavior: HitTestBehavior.opaque,
                  child: const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.md,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFCF4E5),
              borderRadius: AppRadii.md,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: Text(
                    'Waiting for buyer payment',
                    style: AppText.bodyStrong.copyWith(
                      color: const Color(0xFF9A6B14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Copy Link',
                  icon: Icons.copy_rounded,
                  variant: AppButtonVariant.outline,
                  onPressed: () => _copyLink(context),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: AppButton(
                  label: 'Share Link',
                  icon: Icons.ios_share_rounded,
                  variant: AppButtonVariant.soft,
                  onPressed: () => _shareLink(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          const NoteBanner(
            icon: Icons.info_outline_rounded,
            text:
                'Only the buyer can pay this link. You can’t pay your own '
                'transaction.',
          ),
        ],
      ),
    );
  }
}

/// Prominent dispute banner for either party while a dispute is unresolved.
/// Shows reason, who raised it, when, and the live status. "View Dispute"
/// always; the counter-party (the side that didn't raise it) additionally
/// gets "Respond". Both open [DisputeStatusScreen], which hosts the response
/// form and re-checks eligibility on submit — payout stays blocked meanwhile
/// (enforced server-side by the escrow state machine).
class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.dispute, required this.canRespond});
  final Dispute dispute;
  final bool canRespond;

  @override
  Widget build(BuildContext context) {
    final raiser = dispute.raisedByRole == 'buyer' ? 'The buyer' : 'The seller';
    void openDispute() =>
        AppNav.push(context, DisputeStatusScreen(disputeId: dispute.id));
    return AppCard(
      color: const Color(0xFFFCF4E5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.warning,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dispute raised', style: AppText.h3),
                    const SizedBox(height: 2),
                    Text(
                      '$raiser has raised a dispute for this transaction.',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          _InfoRow(
            icon: Icons.category_outlined,
            label: 'Reason',
            value: dispute.categoryLabel,
          ),
          if ((dispute.reason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: AppSizes.sm),
            Text(dispute.reason!.trim(), style: AppText.body),
          ],
          const SizedBox(height: AppSizes.sm),
          _InfoRow(
            icon: Icons.schedule_rounded,
            label: 'Raised',
            value: Dates.relative(dispute.createdAt),
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Text('Status', style: AppText.caption),
              const SizedBox(width: 8),
              StatusPill(label: dispute.displayStatus, dense: true),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          if (canRespond) ...[
            AppButton(
              label: 'Respond',
              icon: Icons.reply_rounded,
              onPressed: openDispute,
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'View Dispute',
              variant: AppButtonVariant.outline,
              onPressed: openDispute,
            ),
          ] else
            AppButton(
              label: 'View Dispute',
              icon: Icons.flag_outlined,
              variant: AppButtonVariant.outline,
              onPressed: openDispute,
            ),
        ],
      ),
    );
  }
}
