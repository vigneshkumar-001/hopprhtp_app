import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/dispute_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../transaction/application/transactions_provider.dart';
import '../transaction/widgets/transaction_widgets.dart';
import '../wallet/wallet_screen.dart';

/// Dispute Status — real backend data (Phase 9). Shows the actual dispute
/// record end to end; the counter-party's response form is gated on the real
/// `raisedByRole` (backend re-enforces this on submit regardless).
class DisputeStatusScreen extends ConsumerStatefulWidget {
  const DisputeStatusScreen({super.key, this.disputeId});

  final String? disputeId;

  @override
  ConsumerState<DisputeStatusScreen> createState() =>
      _DisputeStatusScreenState();
}

class _DisputeStatusScreenState extends ConsumerState<DisputeStatusScreen> {
  final _responseController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _responseController.dispose();
    super.dispose();
  }

  Future<void> _submitResponse(Dispute dispute) async {
    if (_submitting) return;
    final message = _responseController.text.trim();
    if (message.length < 5) {
      AppSnackbar.error(
        context,
        'Please enter a response (at least 5 characters).',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(disputeRepositoryProvider).respond(dispute.id, message);
      if (!mounted) return;
      AppSnackbar.success(context, 'Response submitted.');
      ref.invalidate(disputeDetailProvider(dispute.id));
      ref.invalidate(transactionLedgerProvider(dispute.transactionId));
      // Also refresh what Dispute Center / Transaction Details show, so
      // backing out doesn't leave either on stale pre-response data.
      ref.invalidate(transactionDisputesProvider(dispute.transactionId));
      ref.invalidate(transactionDetailProvider(dispute.transactionId));
      ref.invalidate(transactionsProvider);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.disputeId;
    if (id == null) {
      return const AppScaffold(
        title: 'Dispute Status',
        body: ErrorRetryView(
          message:
              'Dispute reference is missing. Please go back and try again.',
        ),
      );
    }

    final disputeAsync = ref.watch(disputeDetailProvider(id));

    return AppScaffold(
      title: 'Dispute Status',
      scrollable: true,
      body: AsyncValueView(
        value: disputeAsync,
        onRetry: () => ref.invalidate(disputeDetailProvider(id)),
        data: (dispute) => _DisputeBody(
          dispute: dispute,
          responseController: _responseController,
          submitting: _submitting,
          onSubmitResponse: () => _submitResponse(dispute),
        ),
      ),
    );
  }
}

class _DisputeBody extends ConsumerWidget {
  const _DisputeBody({
    required this.dispute,
    required this.responseController,
    required this.submitting,
    required this.onSubmitResponse,
  });

  final Dispute dispute;
  final TextEditingController responseController;
  final bool submitting;
  final VoidCallback onSubmitResponse;

  String _escrowImpact(DisputeResolution r) => r.outcome == 'buyer_favored'
      ? 'Escrow refunded to the buyer.'
      : 'Escrow released to the seller.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(trackingProvider(dispute.transactionId));
    final myRole = trackingAsync.maybeWhen(
      data: (t) => t.isSeller ? 'seller' : 'buyer',
      orElse: () => null,
    );
    final canRespond =
        myRole != null &&
        myRole != dispute.raisedByRole &&
        !dispute.hasResponse &&
        !dispute.isResolved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.sm),
        AppCard(
          color: AppColors.surfaceMuted,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  dispute.isResolved
                      ? Icons.check_rounded
                      : Icons.flag_outlined,
                  color: AppColors.textOnDark,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dispute.displayStatus, style: AppText.h3),
                    const SizedBox(height: 2),
                    Text('Case ${dispute.code}', style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CardSectionLabel('Dispute details'),
              const SizedBox(height: AppSizes.md),
              SummaryRow(label: 'Category', value: dispute.categoryLabel),
              const SizedBox(height: AppSizes.sm),
              SummaryRow(
                label: 'Raised by',
                value: dispute.raisedByRole == 'buyer' ? 'Buyer' : 'Seller',
              ),
              const SizedBox(height: AppSizes.sm),
              SummaryRow(
                label: 'Raised',
                value: Dates.relative(dispute.createdAt),
              ),
              if ((dispute.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSizes.md),
                Text(dispute.reason!, style: AppText.body),
              ],
            ],
          ),
        ),
        if (dispute.evidence.isNotEmpty) ...[
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Evidence'),
                const SizedBox(height: AppSizes.md),
                for (final e in dispute.evidence)
                  if ((e.url ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: ClipRRect(
                        borderRadius: AppRadii.md,
                        child: Image.network(
                          e.url!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    )
                  else if ((e.note ?? '').isNotEmpty)
                    Text(e.note!, style: AppText.body),
              ],
            ),
          ),
        ],
        if (dispute.ai != null) ...[
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Automated first-pass review'),
                const SizedBox(height: AppSizes.sm),
                Text(
                  dispute.ai!.summary,
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'This is an automated pre-screen, not the final decision.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
        if (dispute.response != null) ...[
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardSectionLabel(
                  dispute.response!.respondedByRole == 'seller'
                      ? "Seller's response"
                      : "Buyer's response",
                ),
                const SizedBox(height: AppSizes.sm),
                Text(dispute.response!.message, style: AppText.body),
                if (dispute.response!.respondedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    Dates.relative(dispute.response!.respondedAt!),
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
        if (canRespond) ...[
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Submit your response'),
                const SizedBox(height: AppSizes.md),
                AppTextField(
                  controller: responseController,
                  hint: 'Share your side of the story',
                  maxLines: 4,
                ),
                const SizedBox(height: AppSizes.md),
                AppButton(
                  label: 'Submit Response',
                  loading: submitting,
                  enabled: !submitting,
                  onPressed: onSubmitResponse,
                ),
              ],
            ),
          ),
        ],
        if (dispute.resolution != null) ...[
          const SizedBox(height: AppSizes.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CardSectionLabel('Resolution'),
                const SizedBox(height: AppSizes.sm),
                Text(_escrowImpact(dispute.resolution!), style: AppText.body),
                if ((dispute.resolution!.note ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(dispute.resolution!.note!, style: AppText.caption),
                ],
                if (dispute.resolution!.at != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    Dates.relative(dispute.resolution!.at!),
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        AppButton(
          label: 'View in wallet',
          icon: Icons.account_balance_wallet_outlined,
          variant: AppButtonVariant.outline,
          onPressed: () => AppNav.push(context, const WalletScreen()),
        ),
        const SizedBox(height: AppSizes.lg),
      ],
    );
  }
}
