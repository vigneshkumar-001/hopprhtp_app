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
import '../../core/utils/formatters.dart';
import '../../data/app_state.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/pin_prompt.dart';
import '../../widgets/segmented_control.dart';
import 'application/transactions_provider.dart';
import 'payment_link_ready_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Payment Setup (seller) — delivery fee + trust-fee split, then a payment link.
class PaymentSetupScreen extends ConsumerStatefulWidget {
  const PaymentSetupScreen({
    super.key,
    required this.consignments,
    this.feeSplit = FeeSplit.split,
  });
  final List<Consignment> consignments;

  /// Initial fee split chosen on the Create screen.
  final FeeSplit feeSplit;

  @override
  ConsumerState<PaymentSetupScreen> createState() => _PaymentSetupScreenState();
}

class _PaymentSetupScreenState extends ConsumerState<PaymentSetupScreen> {
  late final PaymentDraft _draft;

  /// The lead consignment — its dispatcher + delivery address head the summary.
  /// It's the same object held in [widget.consignments], so editing the address
  /// here flows straight through to [_buildBody] (and on to the backend).
  late final Consignment _primary;
  late final TextEditingController _deliveryCtrl;
  bool _busy = false;

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    final subtotal = widget.consignments
        .fold<double>(0, (sum, c) => sum + _parse(c.amount));
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
      feeSplit: widget.feeSplit,
    );
    _deliveryCtrl = TextEditingController(text: Money.format(_draft.deliveryFee, symbol: false));
  }

  @override
  void dispose() {
    _deliveryCtrl.dispose();
    super.dispose();
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
            AppSizes.xl, AppSizes.xl, AppSizes.xl, AppSizes.xl),
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
                  child: const Icon(Icons.verified_user_outlined,
                      color: AppColors.success),
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
    if (widget.consignments.isEmpty ||
        widget.consignments.any(_isIncomplete)) {
      AppSnackbar.error(context,
          'Some consignment details are missing. Go back and complete them first.');
      return;
    }
    if (!ref.isOnline) {
      AppSnackbar.error(context,
          'No internet connection. Please check your network and try again.');
      return;
    }
    // Confirm with the transaction PIN (verified server-side, never stored).
    final pin = await showPinSheet(context,
        subtitle: 'Confirm with your PIN to create this transaction.');
    if (pin == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final tx =
          await ref.read(transactionRepositoryProvider).create(_buildBody(pin));
      if (!mounted) return;
      // Land it on the dashboard (demo bridge) + refresh the provider-backed list.
      AppScope.read(context).addFromApi(tx);
      ref.invalidate(transactionsProvider);
      AppNav.push(
          context, PaymentLinkReadyScreen(draft: _draft, code: tx.code));
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _buildBody(String pin) => {
        'pin': pin,
        'consignments': [
          for (final c in widget.consignments)
            {
              'product': c.product,
              if (c.quantity.trim().isNotEmpty) 'quantity': c.quantity,
              if (c.weight.trim().isNotEmpty) 'weight': c.weight,
              'amountNaira': _parse(c.amount),
              if (c.buyerName.trim().isNotEmpty) 'buyerName': c.buyerName,
              'buyerContact': c.buyerContact,
              if (c.deliveryAddress.trim().isNotEmpty) 'deliveryAddress': c.deliveryAddress,
              if (c.waybillTrackingNumber.trim().isNotEmpty)
                'waybillTrackingNumber': c.waybillTrackingNumber,
              if (c.payout.isComplete)
                'payout': {
                  'dispatcherName': c.payout.dispatcherName,
                  'dispatcherPhone': c.payout.dispatcherPhone,
                  'bank': c.payout.bank,
                  'accountNumber': c.payout.accountNumber,
                  'accountName': c.payout.accountName,
                },
              if (c.dispatcherAddress.trim().isNotEmpty)
                'dispatcherAddress': c.dispatcherAddress,
              if (c.specialInstructions.trim().isNotEmpty)
                'specialInstructions': c.specialInstructions,
              'dispatchPhotoUrl': ?c.dispatchPhotoUrl,
              'waybillImageUrl': ?c.waybillImageUrl,
            },
        ],
        'feeSplit': _draft.feeSplit.name,
        'deliveryFeeNaira': _draft.deliveryFee,
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
          Text(
            'Set the delivery fee and confirm the trust protection fee. We\'ll total it up and create a payment link for the buyer.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.lg),
          ItemSummaryCard(
            product: _draft.productName,
            subtitle: '${_draft.sellerName} · ${_draft.sellerCode}',
            amount: _draft.itemSubtotal,
          ),
          const SizedBox(height: AppSizes.md),
          _DispatcherCard(
            name: _primary.payout.dispatcherName,
            phone: _primary.payout.dispatcherPhone,
          ),
          const SizedBox(height: AppSizes.md),
          _DeliveryAddressCard(
            address: _primary.deliveryAddress,
            onEdit: _editDeliveryAddress,
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery fee', style: AppText.h3),
                const SizedBox(height: AppSizes.md),
                _AmountField(controller: _deliveryCtrl, onChanged: (v) {
                  setState(() => _draft.deliveryFee = _parse(v));
                }),
                const SizedBox(height: AppSizes.sm),
                Text('Enter any amount — up to ${Money.format(999999)}',
                    style: AppText.caption),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Who pays the trust fee?', style: AppText.h3),
                const SizedBox(height: AppSizes.md),
                SegmentedControl(
                  segments: const ['Buyer', '50 : 50', 'Seller'],
                  selected: _draft.feeSplit.index,
                  onChanged: (i) =>
                      setState(() => _draft.feeSplit = FeeSplit.values[i]),
                ),
              ],
            ),
          ),
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
            child: Icon(Icons.person_outline_rounded,
                size: 22, color: accent.onAccentSoft),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dispatcher', style: AppText.caption),
                const SizedBox(height: 3),
                Text(name.isEmpty ? 'Not provided' : name,
                    style: AppText.bodyStrong, overflow: TextOverflow.ellipsis),
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
                child: Text('Edit',
                    style: AppText.bodyStrong.copyWith(color: linkColor)),
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
          const Icon(Icons.verified_user_outlined,
              size: 24, color: AppColors.success),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protected by Hoppr Trust Protocol',
                    style: AppText.bodyStrong),
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
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary),
          ],
        ],
      ),
    );
  }
}

/// Itemised "Buyer will pay" summary: item value, delivery, the buyer's share
/// of the trust fee (with who-pays note), and the grand total. Reflects the
/// live delivery-fee and fee-split selections above.
class _BuyerBreakdownCard extends StatelessWidget {
  const _BuyerBreakdownCard({required this.draft});

  final PaymentDraft draft;

  String get _trustNote => switch (draft.feeSplit) {
        FeeSplit.buyer => 'Buyer pays',
        FeeSplit.split => 'Split 50 : 50',
        FeeSplit.seller => 'Seller pays',
      };

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Buyer will pay', style: AppText.h3),
              const SizedBox(width: 6),
              Text('(breakdown)', style: AppText.caption),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          SummaryRow(
              label: 'Item value', value: Money.format(draft.itemSubtotal)),
          const SizedBox(height: AppSizes.md),
          SummaryRow(
              label: 'Delivery fee', value: Money.format(draft.deliveryFee)),
          const SizedBox(height: AppSizes.md),
          // Trust line: label + a lighter "(who pays)" note, then the value.
          Row(
            children: [
              Text('Trust protection fee', style: AppText.body),
              const SizedBox(width: 6),
              Flexible(
                child: Text('($_trustNote)',
                    style: AppText.caption, overflow: TextOverflow.ellipsis),
              ),
              const Spacer(),
              Text(Money.format(draft.buyerTrustShare),
                  style: AppText.bodyStrong),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.lg),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: Text('Grand total payable by buyer',
                    style: AppText.bodyStrong),
              ),
              const SizedBox(width: AppSizes.sm),
              Text(Money.format(draft.grandTotal),
                  style: AppText.h2.copyWith(color: accent.ring)),
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
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);

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
          Text('Where should the courier deliver this order?',
              style: AppText.body),
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

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.md,
        border: Border.all(color: AppColors.border, width: 1.2),
      ),
      child: Row(
        children: [
          Text(Money.naira, style: AppText.h3),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsFormatter()],
              onChanged: onChanged,
              style: AppText.h3,
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '0',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
