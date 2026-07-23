import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/delivery_fee_estimator.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_state.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/pin_prompt.dart';
import 'application/transactions_provider.dart';
import 'payment_link_ready_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Payment Setup (seller) — delivery fee, then the payment link. Platform Fee
/// Payer is decided on Create Transaction and shown here read-only (see
/// [platformFeePayer]) — never re-asked or defaulted on this screen.
class PaymentSetupScreen extends ConsumerStatefulWidget {
  const PaymentSetupScreen({
    super.key,
    required this.consignments,
    required this.platformFeePayer,
    this.deliveryMethod = DeliveryMethod.sellerSelf,
  });
  final List<Consignment> consignments;

  /// Who pays Hoppr Platform Fee — chosen (required, no default) on Create
  /// Transaction. A separate decision from [deliveryMethod]: even
  /// self-delivery still incurs the fee.
  final PlatformFeePayer platformFeePayer;

  /// Delivery method chosen on the Create screen. The dispatcher's
  /// name/phone (only sent when this is [DeliveryMethod.requestDispatcher])
  /// live on the primary consignment itself — see [_buildBody] — never a
  /// separate/duplicate field here.
  final DeliveryMethod deliveryMethod;

  @override
  ConsumerState<PaymentSetupScreen> createState() => _PaymentSetupScreenState();
}

class _PaymentSetupScreenState extends ConsumerState<PaymentSetupScreen> {
  late final PaymentDraft _draft;

  /// The lead consignment — its dispatcher + delivery address head the summary.
  /// It's the same object held in [widget.consignments], so editing the address
  /// here flows straight through to [_buildBody] (and on to the backend).
  late final Consignment _primary;
  bool _busy = false;

  /// Whether the HTP Delivery Fee could actually be calculated — always true
  /// for Deliver Myself (nothing to calculate, always ₦0). For Hoppr
  /// Dispatcher, true only once distance (both addresses picked via the map)
  /// and a valid package weight are all present. False blocks Generate
  /// Payment Link with a clear message rather than ever falling back to a
  /// guessed number (client spec: "block payment until distance is
  /// available" — no manual-entry fallback is offered).
  late final bool _deliveryFeeCalculable;

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    final subtotal = widget.consignments.fold<double>(
      0,
      (sum, c) => sum + _parse(c.amount),
    );
    _primary = widget.consignments.isNotEmpty
        ? widget.consignments.first
        : Consignment(product: 'Item', amount: '0');
    final user = AppScope.read(context).user;
    _draft = PaymentDraft(
      productName: _primary.product.isEmpty ? 'Item' : _primary.product,
      sellerName: user?.fullName ?? 'Yemi Stores',
      sellerCode: 'HTP-LGS-8881',
      itemSubtotal: subtotal,
      variant: 'Yemi Stores',
      platformFeePayer: widget.platformFeePayer,
    );

    // HTP Delivery Fee — never manual/static (see DeliveryFeeEstimator, a
    // 1:1 mirror of the backend formula). This is only ever a PREVIEW; the
    // authoritative figure is whatever the backend actually computes at
    // creation, synced onto _draft in _generate() once that response lands.
    if (widget.deliveryMethod == DeliveryMethod.sellerSelf) {
      _draft.deliveryFee = 0;
      _deliveryFeeCalculable = true;
    } else {
      final weightKg = DeliveryFeeEstimator.parseWeightKg(_primary.weight);
      final pickupLat = _primary.dispatcherLat;
      final pickupLng = _primary.dispatcherLng;
      final dropLat = _primary.deliveryLat;
      final dropLng = _primary.deliveryLng;
      if (weightKg != null &&
          pickupLat != null &&
          pickupLng != null &&
          dropLat != null &&
          dropLng != null) {
        final distanceKm = DeliveryFeeEstimator.distanceKm(
          pickupLat,
          pickupLng,
          dropLat,
          dropLng,
        );
        _draft.deliveryFee = DeliveryFeeEstimator.computeFee(
          distanceKm: distanceKm,
          weightKg: weightKg,
        );
        _deliveryFeeCalculable = true;
      } else {
        _draft.deliveryFee = 0;
        _deliveryFeeCalculable = false;
      }
    }
  }

  /// Edit the delivery address inline. Mutating [_primary] is enough — it's the
  /// same object [_buildBody] reads, so the new address is what gets sent.
  Future<void> _editDeliveryAddress() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (_) => _EditAddressSheet(initial: _primary.deliveryAddress),
    );
    if (result != null && result.isNotEmpty && mounted) {
      setState(() => _primary.deliveryAddress = result);
    }
  }

  /// Explainer for the "Protected by Hoppr Trust Protocol" banner.
  void _showTrustInfo() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.successSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Text('Hoppr Trust Protocol', style: AppText.h2),
                ),
              ],
            ),
            const SizedBox(height: AppSizes.lg),
            Text(
              'When the buyer pays, the funds are held securely in escrow — not '
              'released to you yet. They stay protected until the buyer confirms '
              'the item was delivered as described. Only then are funds released '
              'to your wallet and the courier is settled. If something goes '
              'wrong, the money is still safe and can be refunded or disputed.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Got it',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// Mirrors the backend's required-field rules (product, amount > 0, a buyer
  /// contact of ≥ 3 chars). Belt-and-braces: the Create screen already blocks
  /// incomplete consignments, so this only catches anything that slips past.
  bool _isIncomplete(Consignment c) =>
      c.product.trim().isEmpty ||
      _parse(c.amount) <= 0 ||
      c.buyerContact.trim().length < 3;

  /// Create the transaction on the backend, then open the payment-link screen.
  Future<void> _generate() async {
    if (_busy) return;
    if (widget.consignments.isEmpty || widget.consignments.any(_isIncomplete)) {
      AppSnackbar.error(
        context,
        'Some consignment details are missing. Go back and complete them first.',
      );
      return;
    }
    // Block rather than guess a delivery fee (client spec's chosen "safe
    // fallback") — the backend would reject this anyway (see
    // transaction.schema.ts's refine()s), but catching it here gives a
    // clearer, screen-specific message than a generic 422.
    if (widget.deliveryMethod == DeliveryMethod.requestDispatcher &&
        !_deliveryFeeCalculable) {
      AppSnackbar.error(
        context,
        'Delivery fee could not be calculated. Go back and re-select the '
        'Package Collection Address, Delivery Address, and package weight.',
      );
      return;
    }
    if (!ref.isOnline) {
      AppSnackbar.error(
        context,
        'No internet connection. Please check your network and try again.',
      );
      return;
    }
    // Confirm with the transaction PIN (verified server-side, never stored).
    final pin = await showPinSheet(
      context,
      subtitle: 'Confirm with your PIN to create this transaction.',
    );
    if (pin == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final tx = await ref
          .read(transactionRepositoryProvider)
          .create(_buildBody(pin));
      if (!mounted) return;
      // Backend is the authoritative source for the HTP Delivery Fee — sync
      // the preview to whatever it actually calculated (should match the
      // client-side estimate exactly, but this is never assumed).
      _draft.deliveryFee = tx.deliveryFeeNaira;
      // Land it on the dashboard (demo bridge) + refresh the provider-backed list.
      AppScope.read(context).addFromApi(tx);
      ref.invalidate(transactionsProvider);
      // Creation flow is done: clear Create Transaction + Payment Setup from the
      // stack so Back from Payment Link Ready (and the detail screen after it)
      // returns to Home, never back into the half-filled create form.
      AppNav.pushAndClearToFirst(
        context,
        PaymentLinkReadyScreen(draft: _draft, code: tx.code, tx: tx),
      );
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _buildBody(String pin) => {
    'pin': pin,
    // Explicit top-level buyer linking — backend falls back to the primary
    // consignment's buyerContact when buyerPhone is omitted, but sending it
    // explicitly keeps this request self-describing.
    if (_primary.buyerContact.trim().isNotEmpty)
      'buyerPhone': _primary.buyerContact.trim(),
    'consignments': [
      for (final c in widget.consignments)
        {
          'product': c.product,
          if (c.quantity.trim().isNotEmpty) 'quantity': c.quantity,
          if (c.weight.trim().isNotEmpty) 'weight': c.weight,
          'amountNaira': _parse(c.amount),
          if (c.buyerName.trim().isNotEmpty) 'buyerName': c.buyerName,
          'buyerContact': c.buyerContact,
          if (c.deliveryAddress.trim().isNotEmpty)
            'deliveryAddress': c.deliveryAddress,
          if (c.deliveryLat != null) 'deliveryLat': c.deliveryLat,
          if (c.deliveryLng != null) 'deliveryLng': c.deliveryLng,
          'estimatedDeliveryDate': c.estimatedDeliveryDate,
          if (c.estimatedDeliveryTime.trim().isNotEmpty)
            'estimatedDeliveryTime': c.estimatedDeliveryTime,
          if (c.waybillTrackingNumber.trim().isNotEmpty)
            'waybillTrackingNumber': c.waybillTrackingNumber,
          if (c.dispatcherAddress.trim().isNotEmpty)
            'dispatcherAddress': c.dispatcherAddress,
          if (c.dispatcherLat != null) 'dispatcherLat': c.dispatcherLat,
          if (c.dispatcherLng != null) 'dispatcherLng': c.dispatcherLng,
          if (c.specialInstructions.trim().isNotEmpty)
            'specialInstructions': c.specialInstructions,
          // Three independent, optional photos — each to its own backend field.
          if ((c.productPhotoUrl ?? '').trim().isNotEmpty)
            'productPhotoUrl': c.productPhotoUrl,
          if ((c.dispatchPhotoUrl ?? '').trim().isNotEmpty)
            'dispatchPhotoUrl': c.dispatchPhotoUrl,
          if ((c.waybillImageUrl ?? '').trim().isNotEmpty)
            'waybillImageUrl': c.waybillImageUrl,
        },
    ],
    'platformFeePayer': widget.platformFeePayer.wireValue,
    // No manual delivery fee sent — the backend always computes the HTP
    // Delivery Fee itself from distance + weight (or 0 for Deliver Myself).
    'dispatcherMode': widget.deliveryMethod.wireValue,
    // Sourced from the primary consignment's own Dispatcher Information
    // fields (Create Transaction) — never a separate/duplicate field here.
    if (widget.deliveryMethod == DeliveryMethod.requestDispatcher) ...{
      'dispatcherName': _primary.dispatcherName,
      'dispatcherPhone': _primary.dispatcherPhone,
    },
  };

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Payment Setup',
      bottomAction: AppButton(
        label: 'Generate Payment Link',
        trailingIcon: Icons.bolt_rounded,
        accentInLime: true,
        loading: _busy,
        onPressed: _generate,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          AppCard(
            color: AppColors.ink,
            shadow: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.lime,
                    borderRadius: AppRadii.md,
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment Setup',
                        style: AppText.h2.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Review the delivery fee, trust split, and buyer total before generating the link.',
                        style: AppText.body.copyWith(
                          color: AppColors.textOnDarkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text(
            'Set the delivery fee and confirm the trust protection fee. We\'ll total it up and create a payment link for the buyer.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          ItemSummaryCard(
            product: _draft.productName,
            subtitle: '${_draft.sellerName} · ${_draft.sellerCode}',
            amount: _draft.itemSubtotal,
            imageUrl: _primary.productPhotoUrl,
          ),
          const SizedBox(height: AppSizes.md),
          _DispatcherCard(
            name: _primary.dispatcherName,
            phone: _primary.dispatcherPhone,
          ),
          const SizedBox(height: AppSizes.md),
          _DeliveryAddressCard(
            address: _primary.deliveryAddress,
            onEdit: _editDeliveryAddress,
          ),
          const SizedBox(height: AppSizes.md),
          _DeliveryFeeCard(
            deliveryMethod: widget.deliveryMethod,
            deliveryFee: _draft.deliveryFee,
            calculable: _deliveryFeeCalculable,
          ),
          if (widget.deliveryMethod == DeliveryMethod.requestDispatcher &&
              _deliveryFeeCalculable &&
              _draft.deliveryFee > _draft.itemSubtotal) ...[
            const SizedBox(height: AppSizes.md),
            const _DeliveryFeeWarningBanner(),
          ],
          const SizedBox(height: AppSizes.md),
          _TrustProtocolBanner(onTap: _showTrustInfo),
          const SizedBox(height: AppSizes.md),
          _BuyerBreakdownCard(draft: _draft),
          const SizedBox(height: AppSizes.md),
          // The dark "grand total" hero card kept at the very bottom.
          GrandTotalCard(draft: _draft),
        ],
      ),
    );
  }
}

/// Courier the package is dispatched to — name + phone, headed by an avatar
/// tile. Read-only here (captured on the Create screen).
class _DispatcherCard extends StatelessWidget {
  const _DispatcherCard({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.accentSoft,
              borderRadius: AppRadii.md,
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: 22,
              color: accent.onAccentSoft,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dispatcher', style: AppText.caption),
                const SizedBox(height: 3),
                Text(
                  name.isEmpty ? 'Not provided' : name,
                  style: AppText.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(phone, style: AppText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the courier should deliver. The "Edit" link opens an inline sheet so
/// the seller can correct the address before generating the payment link.
class _DeliveryAddressCard extends StatelessWidget {
  const _DeliveryAddressCard({required this.address, required this.onEdit});

  final String address;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    // A strong accent that stays legible on white (ink in Mono, deep-lime in
    // the Lime theme) — used for the link + pin, mirroring the design.
    final linkColor = accent.ring;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Delivery address', style: AppText.bodyStrong),
              ),
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'Edit',
                  style: AppText.bodyStrong.copyWith(color: linkColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: linkColor),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Text(
                  address.isEmpty
                      ? 'No address added yet — tap Edit to add one'
                      : address,
                  style: AppText.body,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The green "Protected by Hoppr Trust Protocol" reassurance banner.
class _TrustProtocolBanner extends StatelessWidget {
  const _TrustProtocolBanner({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.successSoft,
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 24,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protected by Hoppr Trust Protocol',
                  style: AppText.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  'Funds are securely held in escrow until delivery '
                  'verification.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSizes.sm),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Payment breakdown, shaped by the Platform Fee Payer chosen (required, no
/// default) on Create Transaction — never re-decided here, only reflected:
///   Buyer pays   → Product Amount, Hoppr Platform Fee, Buyer Pays Total, Seller Receives
///   Seller pays  → Product Amount, Hoppr Platform Fee, Buyer Pays Total, Seller Receives (after fee deduction)
///   Split 50:50  → Product Amount, Hoppr Platform Fee, Buyer Fee Share, Seller Fee Share, Buyer Pays Total, Seller Receives (after fee deduction)
/// Delivery fee is also shown (real money the buyer pays) even though it
/// isn't part of the platform-fee split. This is a client-side PREVIEW — the
/// backend recomputes and returns the authoritative figures once the
/// transaction is created.
class _BuyerBreakdownCard extends StatelessWidget {
  const _BuyerBreakdownCard({required this.draft});

  final PaymentDraft draft;

  bool get _sellerBearsFee => draft.platformFeePayer != PlatformFeePayer.buyer;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    final isSplit = draft.platformFeePayer == PlatformFeePayer.split50;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Payment breakdown', style: AppText.h3),
              const SizedBox(width: 6),
              Text('(${draft.platformFeePayer.label})', style: AppText.caption),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          SummaryRow(
            label: 'Product Amount',
            value: Money.format(draft.itemSubtotal),
          ),
          const SizedBox(height: AppSizes.md),
          SummaryRow(
            label: 'Delivery fee',
            value: Money.format(draft.deliveryFee),
          ),
          const SizedBox(height: AppSizes.md),
          SummaryRow(
            label: 'Hoppr Platform Fee',
            value: Money.format(draft.trustFull),
          ),
          if (isSplit) ...[
            const SizedBox(height: AppSizes.md),
            SummaryRow(
              label: 'Buyer Fee Share',
              value: Money.format(draft.buyerTrustShare),
            ),
            const SizedBox(height: AppSizes.md),
            SummaryRow(
              label: 'Seller Fee Share',
              value: Money.format(draft.sellerTrustShare),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: Text('Buyer Pays Total', style: AppText.bodyStrong),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(
                Money.format(draft.grandTotal),
                style: AppText.h2.copyWith(color: accent.ring),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  _sellerBearsFee
                      ? 'Seller Receives (after fee deduction)'
                      : 'Seller Receives',
                  style: AppText.bodyStrong,
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(
                Money.format(draft.sellerReceivable),
                style: AppText.bodyStrong,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline editor for the delivery address (owns its controller's lifecycle).
class _EditAddressSheet extends StatefulWidget {
  const _EditAddressSheet({required this.initial});

  final String initial;

  @override
  State<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends State<_EditAddressSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSizes.xl,
        right: AppSizes.xl,
        top: AppSizes.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit delivery address', style: AppText.h2),
          const SizedBox(height: AppSizes.sm),
          Text(
            'Where should the courier deliver this order?',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          AppTextField(
            label: 'Delivery address',
            icon: Icons.location_on_outlined,
            controller: _ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: 'Save address',
            icon: Icons.check_rounded,
            onPressed: _save,
          ),
          const SizedBox(height: AppSizes.sm),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.soft,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Read-only — the HTP Delivery Fee is always backend-calculated from
/// distance + weight (Hoppr Dispatcher) or simply ₦0 (Deliver Myself). The
/// seller can no longer type in an arbitrary amount here: the client spec's
/// only sanctioned fallback for a missing calculation is to block Generate
/// Payment Link (see PaymentSetupScreen._generate()), never a manual-entry
/// substitute.
class _DeliveryFeeCard extends StatelessWidget {
  const _DeliveryFeeCard({
    required this.deliveryMethod,
    required this.deliveryFee,
    required this.calculable,
  });

  final DeliveryMethod deliveryMethod;
  final double deliveryFee;
  final bool calculable;

  @override
  Widget build(BuildContext context) {
    final isSelfDelivery = deliveryMethod == DeliveryMethod.sellerSelf;
    final showsAmount = isSelfDelivery || calculable;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: Text('Delivery fee', style: AppText.h3)),
              Text(
                showsAmount ? Money.format(deliveryFee) : '—',
                style: AppText.h3,
              ),
            ],
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            isSelfDelivery
                ? 'No delivery fee applied because seller is handling delivery.'
                : calculable
                ? 'Delivery fee is calculated from distance and package weight.'
                : 'Delivery fee will be confirmed before payment — go back '
                      'and select the Package Collection Address, Delivery '
                      'Address, and package weight.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// Non-blocking notice — shown only when the (real, backend-shaped) delivery
/// fee preview exceeds the item value, per client spec. Never prevents
/// Generate Payment Link on its own.
class _DeliveryFeeWarningBanner extends StatelessWidget {
  const _DeliveryFeeWarningBanner();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              'Delivery fee is higher than item value because of distance '
              'or weight. Please review before continuing.',
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
