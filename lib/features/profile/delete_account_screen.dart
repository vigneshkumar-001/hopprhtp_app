import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/boxed_code_input.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../auth/application/auth_controller.dart';

/// Settings → Delete account. A deliberately two-step flow (notice, then PIN
/// confirmation) rather than a single tap — the action is irreversible from
/// the app. On success, [AuthController.deleteAccount] flips the session to
/// unauthenticated and [AuthGate] takes over: it clears the nav stack and
/// shows onboarding/sign-in on its own, so this screen never navigates
/// manually after a successful delete.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  static const int _totalSteps = 2;
  final _pin = TextEditingController();
  int _step = 0;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step = 0);
    }
  }

  Future<void> _confirmDelete() async {
    if (_busy || _pin.text.length != 6) return;
    if (!ref.isOnline) {
      // Deliberately no autoRetryOnReconnect here — this is account
      // deletion. Silently re-firing it the instant WiFi returns (possibly
      // while the person isn't even looking at the screen anymore) is
      // exactly the kind of irreversible action that must always wait for
      // an explicit tap, never fire on its own.
      AppSnackbar.error(
        context,
        'No internet connection. Please check your network and try again.',
        onRetry: _confirmDelete,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(pin: _pin.text);
      // No manual navigation — AuthGate resets the stack to onboarding the
      // moment the session flips to unauthenticated.
    } on ApiException catch (e) {
      if (!mounted) return;
      _pin.clear();
      AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.md,
                AppSizes.sm,
                AppSizes.screenPad,
                AppSizes.sm,
              ),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('Delete account', style: AppText.title),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _busy ? null : _back,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${_step + 1}/$_totalSteps',
                        style: AppText.label.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppDurations.normal,
                switchInCurve: AppDurations.easeOut,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0.06, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _step == 0
                    ? _NoticeStep(key: const ValueKey(0))
                    : _PinStep(key: const ValueKey(1), controller: _pin, onChanged: () => setState(() {}), onCompleted: _confirmDelete),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                AppSizes.screenPad,
                AppSizes.md,
                AppSizes.screenPad,
                AppSizes.lg + MediaQuery.of(context).padding.bottom,
              ),
              child: _step == 0
                  ? AppButton(
                      label: 'Continue',
                      trailingIcon: Icons.arrow_forward_rounded,
                      onPressed: () => setState(() => _step = 1),
                    )
                  : AppButton(
                      label: 'Delete my account',
                      icon: Icons.delete_outline_rounded,
                      enabled: _pin.text.length == 6,
                      loading: _busy,
                      onPressed: _confirmDelete,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeStep extends StatelessWidget {
  const _NoticeStep({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.lg,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.1),
            borderRadius: AppRadii.lg,
          ),
          child: const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.danger,
            size: 26,
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        Text('This will delete your account', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          "You're signed out of every device immediately, and this can't be "
          'undone from the app.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xl),
        _NoticeCard(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallet balance must be ₦0',
          subtitle: 'Withdraw or clear escrow/cooling funds first.',
        ),
        const SizedBox(height: AppSizes.sm),
        _NoticeCard(
          icon: Icons.sync_alt_rounded,
          title: 'No transaction in progress',
          subtitle: 'Complete or cancel any active deal first.',
        ),
        const SizedBox(height: AppSizes.sm),
        _NoticeCard(
          icon: Icons.description_outlined,
          title: 'Some records are retained',
          subtitle:
              'Completed transaction/dispute history stays for compliance — '
              "your profile itself won't be accessible again.",
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PinStep extends StatelessWidget {
  const _PinStep({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onCompleted,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.lg,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.1),
            borderRadius: AppRadii.lg,
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            color: AppColors.danger,
            size: 26,
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        Text('Confirm your PIN', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Enter your 6-digit PIN to permanently delete your account.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxl),
        BoxedCodeInput(
          controller: controller,
          length: 6,
          obscure: true,
          onChanged: (_) => onChanged(),
          onCompleted: (_) => onCompleted(),
        ),
      ],
    );
  }
}
