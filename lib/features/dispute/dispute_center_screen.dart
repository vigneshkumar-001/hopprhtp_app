import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/dispute_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../transaction/application/transactions_provider.dart';
import '../transaction/widgets/transaction_widgets.dart';
import 'dispute_status_screen.dart';

/// Raise Dispute — real backend flow (Phase 9). Eligibility (buyer-only,
/// cooling window, no existing active dispute) is read from real data before
/// the form is ever shown; the backend re-validates every rule again on submit.
class DisputeCenterScreen extends ConsumerStatefulWidget {
  const DisputeCenterScreen({super.key, this.transactionId});

  final String? transactionId;

  @override
  ConsumerState<DisputeCenterScreen> createState() =>
      _DisputeCenterScreenState();
}

class _DisputeCenterScreenState extends ConsumerState<DisputeCenterScreen> {
  static const _categories = [
    (
      Icons.inventory_2_outlined,
      'item_not_as_described',
      'Item Not As Described',
    ),
    (Icons.local_shipping_outlined, 'not_delivered', 'Not Delivered'),
    (Icons.broken_image_outlined, 'damaged_item', 'Damaged Item'),
    (Icons.gpp_maybe_outlined, 'fraud', 'Fraud'),
    (Icons.more_horiz_rounded, 'other', 'Other'),
  ];

  int _selected = 0;
  final _reasonController = TextEditingController();
  XFile? _evidenceImage;
  String? _evidenceUrl;
  bool _uploadingEvidence = false;
  bool _submitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _evidenceImage = picked;
      _uploadingEvidence = true;
      _evidenceUrl = null;
    });
    try {
      final url = await ref
          .read(uploadRepositoryProvider)
          .uploadImage(picked.path);
      if (mounted) setState(() => _evidenceUrl = url);
    } on ApiException catch (e) {
      // Also clear the picked file — leaving it set would show "Photo
      // attached" for an upload that actually failed.
      if (mounted) setState(() => _evidenceImage = null);
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _uploadingEvidence = false);
    }
  }

  Future<void> _submit(String transactionId) async {
    if (_submitting || _uploadingEvidence) return;
    final reason = _reasonController.text.trim();
    if (reason.length < 10) {
      AppSnackbar.error(
        context,
        'Please describe the issue in at least 10 characters.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final category = _categories[_selected].$2;
      final dispute = await ref
          .read(disputeRepositoryProvider)
          .raise(
            transactionId: transactionId,
            category: category,
            reason: reason,
            evidence: _evidenceUrl != null
                ? [DisputeEvidence(type: 'image', url: _evidenceUrl)]
                : const [],
          );
      if (!mounted) return;
      AppSnackbar.success(context, 'Dispute submitted.');
      // Real state changed (status → disputed) — refresh everything that
      // could be showing stale data now.
      ref.invalidate(transactionDetailProvider(transactionId));
      ref.invalidate(transactionsProvider);
      ref.invalidate(transactionLedgerProvider(transactionId));
      ref.invalidate(trackingProvider(transactionId));
      ref.invalidate(transactionDisputesProvider(transactionId));
      AppNav.push(context, DisputeStatusScreen(disputeId: dispute.id));
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.transactionId;
    if (id == null) {
      return const AppScaffold(
        title: 'Dispute Center',
        body: ErrorRetryView(
          message:
              'Transaction reference is missing. Please go back and try again.',
        ),
      );
    }

    final trackingAsync = ref.watch(trackingProvider(id));
    final disputesAsync = ref.watch(transactionDisputesProvider(id));

    void retry() {
      ref.invalidate(trackingProvider(id));
      ref.invalidate(transactionDisputesProvider(id));
    }

    return AppScaffold(
      title: 'Dispute Center',
      scrollable: true,
      body: trackingAsync.when(
        loading: () => const _Loading(),
        error: (e, _) =>
            ErrorRetryView(message: friendlyError(e), onRetry: retry),
        data: (tracking) => disputesAsync.when(
          loading: () => const _Loading(),
          error: (e, _) =>
              ErrorRetryView(message: friendlyError(e), onRetry: retry),
          data: (disputes) {
            if (tracking.isSeller) {
              return const _MessageCard(
                icon: Icons.info_outline_rounded,
                message:
                    'Only the buyer can raise a dispute for this transaction.',
              );
            }

            final activeDispute = disputes.where((d) => !d.isResolved).toList();
            if (activeDispute.isNotEmpty) {
              return _MessageCard(
                icon: Icons.flag_outlined,
                message:
                    'A dispute has already been raised for this transaction.',
                action: AppButton(
                  label: 'View Dispute',
                  trailingIcon: Icons.arrow_forward_rounded,
                  expand: false,
                  onPressed: () => AppNav.push(
                    context,
                    DisputeStatusScreen(disputeId: activeDispute.last.id),
                  ),
                ),
              );
            }

            final eligible = tracking.status == 'cooling';
            return _RaiseForm(
              categories: _categories,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
              reasonController: _reasonController,
              eligible: eligible,
              submitting: _submitting,
              evidenceImage: _evidenceImage,
              uploadingEvidence: _uploadingEvidence,
              onPickEvidence: _pickEvidence,
              onSubmit: () => _submit(id),
            );
          },
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 320,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: AppSizes.sm),
                Expanded(child: Text(message, style: AppText.body)),
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: AppSizes.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _RaiseForm extends StatelessWidget {
  const _RaiseForm({
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.reasonController,
    required this.eligible,
    required this.submitting,
    required this.evidenceImage,
    required this.uploadingEvidence,
    required this.onPickEvidence,
    required this.onSubmit,
  });

  final List<(IconData, String, String)> categories;
  final int selected;
  final ValueChanged<int> onSelect;
  final TextEditingController reasonController;
  final bool eligible;
  final bool submitting;
  final XFile? evidenceImage;
  final bool uploadingEvidence;
  final VoidCallback onPickEvidence;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.sm),
        NoteBanner(
          icon: Icons.info_outline_rounded,
          text: eligible
              ? 'Raising a dispute holds the escrow and pauses seller payout until it is reviewed.'
              : 'Dispute can be raised during the cooling period before seller payout is released.',
        ),
        const SizedBox(height: AppSizes.xl),
        Opacity(
          opacity: eligible ? 1 : 0.4,
          child: IgnorePointer(
            ignoring: !eligible,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Dispute category'),
                const SizedBox(height: AppSizes.md),
                for (int i = 0; i < categories.length; i++) ...[
                  _CategoryCard(
                    icon: categories[i].$1,
                    label: categories[i].$3,
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
                  if (i != categories.length - 1)
                    const SizedBox(height: AppSizes.md),
                ],
                const SizedBox(height: AppSizes.xl),
                const SectionLabel('Describe the issue'),
                const SizedBox(height: AppSizes.md),
                AppTextField(
                  controller: reasonController,
                  hint: 'Explain what went wrong (at least 10 characters)',
                  maxLines: 4,
                ),
                const SizedBox(height: AppSizes.xl),
                const SectionLabel('Evidence (optional)'),
                const SizedBox(height: AppSizes.md),
                _EvidencePicker(
                  image: evidenceImage,
                  uploading: uploadingEvidence,
                  onTap: onPickEvidence,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSizes.xxl),
        AppButton(
          label: 'Submit Dispute',
          icon: Icons.flag_outlined,
          enabled: eligible && !submitting,
          loading: submitting,
          onPressed: onSubmit,
        ),
        const SizedBox(height: AppSizes.lg),
      ],
    );
  }
}

class _EvidencePicker extends StatelessWidget {
  const _EvidencePicker({
    required this.image,
    required this.uploading,
    required this.onTap,
  });
  final XFile? image;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: uploading ? null : onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(
              image != null
                  ? Icons.check_circle_outline
                  : Icons.add_photo_alternate_outlined,
              size: 20,
              color: image != null
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text(
              uploading
                  ? 'Uploading photo…'
                  : image != null
                  ? 'Photo attached — tap to replace'
                  : 'Add a photo to support your dispute',
              style: AppText.bodyStrong,
            ),
          ),
          if (uploading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      border: Border.all(
        color: selected ? AppColors.borderStrong : AppColors.border,
        width: selected ? 1.6 : 1.2,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(child: Text(label, style: AppText.bodyStrong)),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.ink : AppColors.textTertiary,
            size: 22,
          ),
        ],
      ),
    );
  }
}
