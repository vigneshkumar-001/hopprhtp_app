import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/number_keypad.dart';
import 'application/transactions_provider.dart';

/// Dispatcher-only: verifies the seller's Pickup OTP at the pickup address —
/// a separate code from the buyer-facing Delivery OTP, never mixed with it or
/// the Transaction Code. No geofence gating here (unlike Confirm Delivery):
/// the seller reads the code out to the dispatcher in person, so the code
/// itself is the proof of presence. Pops `true` on success.
class EnterPickupCodeScreen extends ConsumerStatefulWidget {
  const EnterPickupCodeScreen({super.key, required this.transactionId});
  final String transactionId;

  @override
  ConsumerState<EnterPickupCodeScreen> createState() =>
      _EnterPickupCodeScreenState();
}

class _EnterPickupCodeScreenState extends ConsumerState<EnterPickupCodeScreen> {
  static const _len = 6;
  String _otp = '';
  bool _submitting = false;

  void _digit(String d) {
    if (_submitting || _otp.length >= _len) return;
    setState(() => _otp += d);
    if (_otp.length == _len) _submit();
  }

  void _back() {
    if (_otp.isEmpty || _submitting) return;
    setState(() => _otp = _otp.substring(0, _otp.length - 1));
  }

  Future<void> _submit() async {
    if (_submitting || _otp.length < _len) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(transactionRepositoryProvider)
          .confirmPickup(widget.transactionId, otp: _otp);
      if (!mounted) return;
      ref.invalidate(transactionDetailProvider(widget.transactionId));
      ref.invalidate(transactionsProvider);
      ref.invalidate(trackingProvider(widget.transactionId));
      AppSnackbar.success(
        context,
        'Pickup confirmed. The seller and buyer have been notified.',
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, e.userMessage);
      setState(() => _otp = '');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Enter pickup code',
      scrollable: false,
      padding: EdgeInsets.zero,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.screenPad,
          AppSizes.lg,
          AppSizes.screenPad,
          AppSizes.lg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask the seller for the pickup code',
              style: AppText.h1.copyWith(fontSize: 21),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              'The seller sees this 6-digit code in their app once you hand '
              'over the package. Never the Transaction Code or Delivery Code.',
              style: AppText.body.copyWith(fontSize: 11.5, height: 1.5),
            ),
            const SizedBox(height: AppSizes.lg),
            _OtpRow(otp: _otp, length: _len),
            const Spacer(),
            const SizedBox(height: AppSizes.lg),
            Stack(
              alignment: Alignment.center,
              children: [
                NumberKeypad(
                  enabled: !_submitting,
                  onDigit: _digit,
                  onBackspace: _back,
                ),
                if (_submitting)
                  Container(
                    height: AppSizes.buttonHeight,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.xl,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF55585E),
                      borderRadius: AppRadii.btn,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(
                              AppColors.textOnDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSizes.sm),
                        Text(
                          'Confirming pickup…',
                          style: AppText.button.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OtpRow extends StatelessWidget {
  const _OtpRow({required this.otp, required this.length});
  final String otp;
  final int length;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: i == length - 1 ? 0 : AppSizes.sm,
              ),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadii.md,
                  border: Border.all(
                    color: i == otp.length
                        ? AppColors.borderStrong
                        : AppColors.border,
                    width: i == otp.length ? 1.6 : 1.2,
                  ),
                ),
                child: i < otp.length
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
