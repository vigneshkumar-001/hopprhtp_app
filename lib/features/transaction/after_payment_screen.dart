import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
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
import '../../widgets/feedback/app_snackbar.dart';
import 'checkout_webview_screen.dart';
import 'transaction_detail_screen.dart';

/// After Payment Confirmation — the single screen for every checkout outcome
/// ([PaymentOutcome.success]/[failed]/[cancelled]/[pending]). Retrying updates
/// this screen in place (never stacks a second confirmation screen), so
/// repeated failed attempts don't pile up the navigation stack.
///
/// [PaymentOutcome.pending] is implemented for completeness (the spec calls
/// for it) but is never reached today: the hosted checkout's payment endpoint
/// is synchronous — it always resolves to paid or failed, there is no
/// async/gateway-pending step in this system.
class AfterPaymentScreen extends ConsumerStatefulWidget {
  const AfterPaymentScreen({
    super.key,
    required this.outcome,
    required this.tx,
    this.failureReason,
  });

  final PaymentOutcome outcome;

  /// The transaction as reviewed pre-payment — used for code/product/amount
  /// context in every state, and as the retry target.
  final ApiTransaction tx;
  final String? failureReason;

  @override
  ConsumerState<AfterPaymentScreen> createState() => _AfterPaymentScreenState();
}

class _AfterPaymentScreenState extends ConsumerState<AfterPaymentScreen> {
  late PaymentOutcome _outcome = widget.outcome;
  late ApiTransaction _tx = widget.tx;
  late String? _failureReason = widget.failureReason;

  bool _retrying = false;
  bool _refreshing = false;
  bool _viewingDetail = false;

  /// Re-opens the real hosted checkout for another attempt. Updates this same
  /// screen in place on any outcome — never pushes a second confirmation
  /// screen, so retries never stack.
  Future<void> _retryCheckout() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final result = await AppNav.push<CheckoutResult>(
      context,
      CheckoutWebViewScreen(code: _tx.code, lime: AppAccent.of(context).isLime),
    );
    if (!mounted) return;
    setState(() {
      _retrying = false;
      _outcome = result?.outcome ?? PaymentOutcome.cancelled;
      _failureReason = result?.message;
    });
  }

  /// Re-fetches the real transaction and opens Transaction Details, clearing
  /// the whole join/review/checkout/confirmation stack down to Home first.
  Future<void> _viewDetails({bool clearStack = true}) async {
    if (_viewingDetail) return;
    setState(() => _viewingDetail = true);
    try {
      final fresh = await ref
          .read(transactionRepositoryProvider)
          .getByCode(_tx.code);
      if (!mounted) return;
      final screen = TransactionDetailScreen(
        tx: EscrowTransaction.fromApi(fresh),
      );
      if (clearStack) {
        AppNav.pushAndClearToFirst(context, screen);
      } else {
        AppNav.push(context, screen);
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppSnackbar.error(
          context,
          e.userMessage,
          onRetry: () => _viewDetails(clearStack: clearStack),
        );
      }
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not open the transaction. Please try again.',
          onRetry: () => _viewDetails(clearStack: clearStack),
        );
      }
    } finally {
      if (mounted) setState(() => _viewingDetail = false);
    }
  }

  /// Re-checks whether the (supposedly pending) payment has actually landed.
  Future<void> _refreshStatus() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final fresh = await ref
          .read(transactionRepositoryProvider)
          .getByCode(_tx.code);
      if (!mounted) return;
      const unpaidStatuses = {
        ApiTxStatus.draft,
        ApiTxStatus.awaitingAgreement,
        ApiTxStatus.awaitingPayment,
      };
      setState(() {
        _tx = fresh;
        if (!unpaidStatuses.contains(fresh.status)) {
          _outcome = PaymentOutcome.success;
        }
      });
      if (_outcome != PaymentOutcome.success) {
        AppSnackbar.info(context, 'Still pending — check back shortly.');
      }
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(context, 'Could not refresh status right now.');
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _backToHome() =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    return switch (_outcome) {
      PaymentOutcome.success => _SuccessBody(
        tx: _tx,
        loading: _viewingDetail,
        onViewDetails: () => _viewDetails(),
      ),
      PaymentOutcome.failed => _FailedBody(
        reason: _failureReason,
        retrying: _retrying,
        onRetry: _retryCheckout,
        onBackToReview: () => Navigator.of(context).pop(),
      ),
      PaymentOutcome.cancelled => _CancelledBody(
        retrying: _retrying,
        onTryAgain: _retryCheckout,
        onBackToHome: _backToHome,
      ),
      PaymentOutcome.pending => _PendingBody(
        viewingDetail: _viewingDetail,
        refreshing: _refreshing,
        onViewDetails: () => _viewDetails(clearStack: false),
        onRefresh: _refreshStatus,
      ),
    };
  }
}

/// Common shell every outcome state uses — centered icon, title, body copy,
/// and up to two stacked full-width actions.
class _OutcomeScaffold extends StatelessWidget {
  const _OutcomeScaffold({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.headline,
    this.body,
    this.child,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String headline;
  final String? body;

  /// Optional extra content shown between the headline/body and the actions
  /// (e.g. the success state's transaction summary card).
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: title,
      showBack: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSizes.xl),
          Center(
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: iconColor),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text(headline, textAlign: TextAlign.center, style: AppText.h2),
          if (body != null) ...[
            const SizedBox(height: AppSizes.sm),
            Text(body!, textAlign: TextAlign.center, style: AppText.body),
          ],
          if (child != null) ...[const SizedBox(height: AppSizes.xl), child!],
          const SizedBox(height: AppSizes.xl),
          for (final action in actions) ...[
            action,
            if (action != actions.last) const SizedBox(height: AppSizes.sm),
          ],
        ],
      ),
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({
    required this.tx,
    required this.loading,
    required this.onViewDetails,
  });

  final ApiTransaction tx;
  final bool loading;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final summary = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.productName, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(tx.code, style: AppText.caption),
                  ],
                ),
              ),
              Text(Money.format(tx.grandTotalNaira), style: AppText.h3),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The seller can now start delivery.',
                  style: AppText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return _OutcomeScaffold(
      title: 'Payment Confirmed',
      icon: Icons.check_rounded,
      iconColor: AppColors.success,
      headline: 'Payment secured in escrow',
      body: 'Your payment is protected until delivery is confirmed.',
      actions: [
        AppButton(
          label: 'View Transaction Details',
          trailingIcon: Icons.arrow_forward_rounded,
          loading: loading,
          enabled: !loading,
          onPressed: onViewDetails,
        ),
      ],
      child: summary,
    );
  }
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({
    required this.reason,
    required this.retrying,
    required this.onRetry,
    required this.onBackToReview,
  });

  final String? reason;
  final bool retrying;
  final VoidCallback onRetry;
  final VoidCallback onBackToReview;

  @override
  Widget build(BuildContext context) {
    return _OutcomeScaffold(
      title: 'Payment Failed',
      icon: Icons.close_rounded,
      iconColor: AppColors.danger,
      headline: 'We couldn’t complete your payment',
      body: (reason ?? '').trim().isNotEmpty
          ? reason!.trim()
          : 'Something went wrong while processing your payment.',
      actions: [
        AppButton(
          label: 'Retry Payment',
          icon: Icons.refresh_rounded,
          loading: retrying,
          enabled: !retrying,
          onPressed: onRetry,
        ),
        AppButton(
          label: 'Back to Review',
          variant: AppButtonVariant.outline,
          enabled: !retrying,
          onPressed: onBackToReview,
        ),
      ],
    );
  }
}

class _CancelledBody extends StatelessWidget {
  const _CancelledBody({
    required this.retrying,
    required this.onTryAgain,
    required this.onBackToHome,
  });

  final bool retrying;
  final VoidCallback onTryAgain;
  final VoidCallback onBackToHome;

  @override
  Widget build(BuildContext context) {
    return _OutcomeScaffold(
      title: 'Payment Cancelled',
      icon: Icons.remove_circle_outline_rounded,
      iconColor: AppColors.textSecondary,
      headline: 'Payment Cancelled',
      body: 'Your payment was not completed.',
      actions: [
        AppButton(
          label: 'Try Again',
          loading: retrying,
          enabled: !retrying,
          onPressed: onTryAgain,
        ),
        AppButton(
          label: 'Back to Home',
          variant: AppButtonVariant.outline,
          enabled: !retrying,
          onPressed: onBackToHome,
        ),
      ],
    );
  }
}

class _PendingBody extends StatelessWidget {
  const _PendingBody({
    required this.viewingDetail,
    required this.refreshing,
    required this.onViewDetails,
    required this.onRefresh,
  });

  final bool viewingDetail;
  final bool refreshing;
  final VoidCallback onViewDetails;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _OutcomeScaffold(
      title: 'Payment Pending',
      icon: Icons.hourglass_top_rounded,
      iconColor: AppColors.warning,
      headline: 'Payment Pending',
      body: 'We are verifying your payment. This may take a few minutes.',
      actions: [
        AppButton(
          label: 'View Transaction Details',
          loading: viewingDetail,
          enabled: !viewingDetail && !refreshing,
          onPressed: onViewDetails,
        ),
        AppButton(
          label: 'Refresh Status',
          icon: Icons.refresh_rounded,
          variant: AppButtonVariant.outline,
          loading: refreshing,
          enabled: !refreshing && !viewingDetail,
          onPressed: onRefresh,
        ),
      ],
    );
  }
}
