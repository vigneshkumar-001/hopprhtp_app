import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/common.dart';
import 'application/auth_controller.dart';

/// Shown by [AuthGate] in place of the usual sign-in/onboarding flow when a
/// stored session turns out to belong to a frozen or deleted account
/// (`ACCOUNT_SUSPENDED` / `ACCOUNT_DELETED` from the backend). Replaces the
/// previous behaviour of silently clearing the session and dropping the
/// person onto onboarding with no explanation.
class AccountBlockedScreen extends ConsumerWidget {
  const AccountBlockedScreen({
    super.key,
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  bool get _isDeleted => code == 'ACCOUNT_DELETED';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandMark(pill: true),
              const Spacer(),
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isDeleted
                      ? Icons.person_off_rounded
                      : Icons.lock_person_rounded,
                  size: 36,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: AppSizes.xl),
              Text(
                _isDeleted ? 'Account no longer available' : 'Account frozen',
                textAlign: TextAlign.center,
                style: AppText.h2,
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              AppButton(
                label: 'Back to sign in',
                onPressed: () => ref
                    .read(authControllerProvider.notifier)
                    .acknowledgeBlocked(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
