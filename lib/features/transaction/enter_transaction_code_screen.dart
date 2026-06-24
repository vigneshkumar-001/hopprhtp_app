import 'package:flutter/material.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/number_keypad.dart';
import 'buyer_review_screen.dart';

/// Enter Transaction Code — buyer types the HTP code shared by the seller.
class EnterTransactionCodeScreen extends StatefulWidget {
  const EnterTransactionCodeScreen({super.key});

  @override
  State<EnterTransactionCodeScreen> createState() =>
      _EnterTransactionCodeScreenState();
}

class _EnterTransactionCodeScreenState
    extends State<EnterTransactionCodeScreen> {
  String _code = '';
  static const _len = 4;

  void _digit(String d) {
    if (_code.length >= _len) return;
    setState(() => _code += d);
  }

  void _back() {
    if (_code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final complete = _code.length == _len;
    return AppScaffold(
      title: 'Enter Transaction Code',
      scrollable: false,
      bottomAction: AppButton(
        label: 'Find transaction',
        trailingIcon: Icons.arrow_forward_rounded,
        enabled: complete,
        onPressed: () => AppNav.push(
          context,
          BuyerReviewScreen(
            draft: PaymentDraft(
              productName: 'MacBook Pro M2',
              sellerName: 'Yemi Stores',
              sellerCode: 'HTP-LGS-8881',
              itemSubtotal: 1230087,
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text(
            'Enter the protected transaction code your seller shared with you.',
            textAlign: TextAlign.center,
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.md,
              border: Border.all(color: AppColors.border, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('HTP', style: AppText.h2.copyWith(letterSpacing: 4)),
                const SizedBox(width: AppSizes.sm),
                Text('–', style: AppText.h2),
                const SizedBox(width: AppSizes.sm),
                for (int i = 0; i < _len; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: i < _code.length
                        ? Text(_code[i], style: AppText.h2)
                        : Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.textTertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Text('e.g. HTP-LGS-8795',
              textAlign: TextAlign.center, style: AppText.caption),
          const Spacer(),
          NumberKeypad(onDigit: _digit, onBackspace: _back),
          const SizedBox(height: AppSizes.lg),
        ],
      ),
    );
  }
}
