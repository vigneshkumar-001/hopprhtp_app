import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/common.dart';
import 'application/auth_controller.dart';

/// Shown when a stored session is gated behind biometric unlock. Auto-prompts
/// on open and offers a PIN fallback (which clears the local session so the user
/// can re-enter their phone + PIN).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() =>
      ref.read(authControllerProvider.notifier).unlock();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.screenPad),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(pill: true),
              const SizedBox(height: AppSizes.xxl),
              const Icon(Icons.lock_outline_rounded,
                  size: 40, color: AppColors.textSecondary),
              const SizedBox(height: AppSizes.lg),
              Text('Locked', style: AppText.h1, textAlign: TextAlign.center),
              const SizedBox(height: AppSizes.sm),
              Text('Unlock with biometrics to continue.',
                  style: AppText.body, textAlign: TextAlign.center),
              const Spacer(),
              AppButton(
                label: 'Unlock',
                icon: Icons.fingerprint_rounded,
                onPressed: _unlock,
              ),
              const SizedBox(height: AppSizes.md),
              AppButton(
                label: 'Sign in with PIN instead',
                variant: AppButtonVariant.soft,
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).forceLogout(),
              ),
              const SizedBox(height: AppSizes.lg),
            ],
          ),
        ),
      ),
    );
  }
}
