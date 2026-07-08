import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/blur_sheet.dart';
import '../auth/application/auth_controller.dart';
import '../profile/identity_verification_screen.dart';
import 'create_transaction_screen.dart';

/// Identity-verification gate for Create Transaction. Call this from INSIDE
/// [CreateTransactionScreen] (e.g. a post-frame callback in `initState`) —
/// never before pushing the screen. The real screen must always open first;
/// an unverified user then sees it blurred behind a gate sheet, never a
/// blank/placeholder screen. The backend profile (`identityStatus`) is the
/// only source of truth here — nothing is faked client-side.
Future<void> runCreateTransactionVerificationGate(
  BuildContext context,
  WidgetRef ref,
) async {
  var status = await _resolveStatus(context, ref);
  if (status == null || status == 'verified') return; // already usable

  while (true) {
    if (!context.mounted) return;
    final wantsToVerify = await showBlurredSheet<bool>(
      context,
      builder: (ctx) => _VerificationGateSheet(state: _kycStateFrom(status!)),
    );
    if (!context.mounted) return;

    if (wantsToVerify == true) {
      await _runIdentityFlow(context, ref);
      if (!context.mounted) return; // this screen instance was replaced
      status = ref
          .read(authControllerProvider)
          .valueOrNull
          ?.user
          ?.identityStatus;
      if (status == 'verified') return; // gate satisfied — screen now usable
      status ??= 'unverified';
      continue; // re-show the sheet with the (possibly now "pending") status
    }

    // "Not Now" / backdrop tap / hardware back — all leave Create Transaction
    // rather than stranding the user on a screen they can't submit from.
    if (context.mounted) Navigator.of(context).maybePop();
    return;
  }
}

/// Re-reads the cached status, then refreshes from the backend once (unless
/// already verified) so a status that changed server-side is picked up.
Future<String?> _resolveStatus(BuildContext context, WidgetRef ref) async {
  var status =
      ref.read(authControllerProvider).valueOrNull?.user?.identityStatus ??
      'unverified';
  if (status == 'verified') return status;
  try {
    await ref.read(authControllerProvider.notifier).refreshProfile();
  } catch (_) {
    // Network hiccup — fall through with the cached status; the gate sheet
    // still renders correctly and the user can retry verification from it.
  }
  if (!context.mounted) return null;
  return ref.read(authControllerProvider).valueOrNull?.user?.identityStatus ??
      'unverified';
}

/// Runs the identity-verification flow. [IdentityVerificationScreen]'s own
/// completion step (`SubmittedForReviewScreen`) pops all the way back to the
/// app's first route (Home) — correct for its other entry point (Profile),
/// but that also collaterally removes this Create Transaction screen. We
/// detect that (`context` unmounted afterwards) and reopen a fresh Create
/// Transaction screen so the user still lands back where they intended; its
/// own gate re-check then shows the real (now likely "pending") status. If
/// the user instead just backs out of the KYC screens without submitting,
/// this screen was never removed and nothing extra is needed.
Future<void> _runIdentityFlow(BuildContext context, WidgetRef ref) async {
  final navigator = Navigator.of(context);
  await navigator.push(AppNav.route<void>(const IdentityVerificationScreen()));
  if (context.mounted || !navigator.mounted) return;
  navigator.push(AppNav.route(const CreateTransactionScreen()));
}

enum _KycState { unverified, pending, rejected }

_KycState _kycStateFrom(String status) => switch (status) {
  'pending' => _KycState.pending,
  'rejected' => _KycState.rejected,
  _ => _KycState.unverified,
};

class _VerificationGateSheet extends StatelessWidget {
  const _VerificationGateSheet({required this.state});
  final _KycState state;

  @override
  Widget build(BuildContext context) {
    final danger = state == _KycState.rejected;
    final (
      String title,
      String body,
      String primaryLabel,
      bool primaryVerifies,
    ) = switch (state) {
      _KycState.pending => (
        'Verification pending',
        'Your verification is under review.',
        'OK',
        false,
      ),
      _KycState.rejected => (
        'Verification rejected',
        'Verification was rejected. Please update your documents.',
        'Verify Now',
        true,
      ),
      _KycState.unverified => (
        'Verify your identity',
        'To create a transaction, please complete identity verification. '
            'This helps keep escrow payments and deliveries safe.',
        'Verify Now',
        true,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.sm,
        AppSizes.xl,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (danger ? AppColors.danger : AppColors.ink).withValues(
                  alpha: 0.10,
                ),
              ),
              child: Icon(
                danger
                    ? Icons.gpp_maybe_outlined
                    : Icons.verified_user_outlined,
                size: 30,
                color: danger ? AppColors.danger : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.lg),
          Text(title, textAlign: TextAlign.center, style: AppText.h3),
          const SizedBox(height: AppSizes.sm),
          Text(body, textAlign: TextAlign.center, style: AppText.body),
          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: primaryLabel,
            trailingIcon: primaryVerifies
                ? Icons.arrow_forward_rounded
                : Icons.check_rounded,
            onPressed: () => Navigator.of(context).pop(primaryVerifies),
          ),
          if (state != _KycState.pending) ...[
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Not Now',
              variant: AppButtonVariant.soft,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ],
      ),
    );
  }
}
