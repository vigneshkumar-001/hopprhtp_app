import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../app_button.dart';
import '../app_text_field.dart';
import '../star_rating.dart';
import 'app_snackbar.dart';

/// Prompts for a star rating (+ optional comment) of the counterparty on a
/// completed transaction. Returns true once actually submitted — the caller
/// uses that to stop showing the "Rate your experience" prompt without a
/// separate refetch.
Future<bool> showRatingSheet(
  BuildContext context, {
  required String transactionId,
  required String counterpartyLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.rXl)),
    ),
    builder: (_) => _RatingSheet(
      transactionId: transactionId,
      counterpartyLabel: counterpartyLabel,
    ),
  );
  return result ?? false;
}

class _RatingSheet extends ConsumerStatefulWidget {
  const _RatingSheet({
    required this.transactionId,
    required this.counterpartyLabel,
  });

  final String transactionId;
  final String counterpartyLabel;

  @override
  ConsumerState<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<_RatingSheet> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(transactionRepositoryProvider)
          .submitRating(
            widget.transactionId,
            stars: _stars,
            comment: _comment.text.trim().isEmpty
                ? null
                : _comment.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.xl,
          AppSizes.lg,
          AppSizes.xl,
          AppSizes.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Text('Rate your experience', style: AppText.h2),
            const SizedBox(height: AppSizes.sm),
            Text(
              'How was your deal with ${widget.counterpartyLabel}?',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSizes.xl),
            Center(
              child: StarRating(
                value: _stars.toDouble(),
                size: 36,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _stars = v),
              ),
            ),
            const SizedBox(height: AppSizes.xl),
            AppTextField(
              controller: _comment,
              hint: 'Add a comment (optional)',
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Submit rating',
              enabled: _stars > 0,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
