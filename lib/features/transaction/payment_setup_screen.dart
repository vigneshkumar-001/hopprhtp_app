import 'package:flutter/material.dart';
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
import '../../widgets/segmented_control.dart';
import 'payment_link_ready_screen.dart';
import 'widgets/transaction_widgets.dart';

/// Payment Setup (seller) — delivery fee + trust-fee split, then a payment link.
class PaymentSetupScreen extends StatefulWidget {
  const PaymentSetupScreen({
    super.key,
    required this.consignments,
    this.feeSplit = FeeSplit.split,
  });
  final List<Consignment> consignments;

  /// Initial fee split chosen on the Create screen.
  final FeeSplit feeSplit;

  @override
  State<PaymentSetupScreen> createState() => _PaymentSetupScreenState();
}

class _PaymentSetupScreenState extends State<PaymentSetupScreen> {
  late final PaymentDraft _draft;
  late final TextEditingController _deliveryCtrl;

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

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Payment Setup',
      bottomAction: AppButton(
        label: 'Generate Payment Link',
        trailingIcon: Icons.bolt_rounded,
        accentInLime: true,
        onPressed: () => AppNav.push(
            context, PaymentLinkReadyScreen(draft: _draft)),
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
