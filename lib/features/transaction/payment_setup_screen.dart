import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_state.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
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
  late final TextEditingController _deliveryCtrl;
  bool _busy = false;

  double _parse(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  @override
  void initState() {
    super.initState();
    final subtotal = widget.consignments
        .fold<double>(0, (sum, c) => sum + _parse(c.amount));
    final first = widget.consignments.isNotEmpty
        ? widget.consignments.first
        : Consignment(product: 'Item', amount: '0');
    final user = AppScope.read(context).user;
    _draft = PaymentDraft(
      productName: first.product.isEmpty ? 'Item' : first.product,
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

  /// Create the transaction on the backend, then open the payment-link screen.
  Future<void> _generate() async {
    if (_busy) return;
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
              'amountNaira': _parse(c.amount),
              'buyerContact': c.buyerContact,
              if (c.payout.isComplete)
                'payout': {
                  'dispatcherName': c.payout.dispatcherName,
                  'dispatcherPhone': c.payout.dispatcherPhone,
                  'bank': c.payout.bank,
                  'accountNumber': c.payout.accountNumber,
                  'accountName': c.payout.accountName,
                },
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
          AppCard(
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, size: 20),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Trust protection fee', style: AppText.bodyStrong),
                          const SizedBox(height: 2),
                          Text('Auto-calculated · 1.5% of item value',
                              style: AppText.caption),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(Money.format(_draft.buyerTrustShare),
                            style: AppText.h3),
                        Text("buyer's share", style: AppText.caption),
                      ],
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSizes.md),
                  child: Divider(height: 1),
                ),
                SummaryRow(
                    label: 'Full protection fee',
                    value: Money.format(_draft.trustFull)),
                const SizedBox(height: AppSizes.sm),
                SummaryRow(
                  label: "Seller's half · ${_draft.feeSplit.label}",
                  value: '− ${Money.format(_draft.sellerTrustShare)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          GrandTotalCard(draft: _draft),
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
