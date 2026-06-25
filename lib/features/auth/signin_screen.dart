import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/pin_field.dart';
import 'application/auth_controller.dart';
import 'signup_screen.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _identifier = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _biometricSession = false; // a biometric-protected session is remembered

  @override
  void initState() {
    super.initState();
    _identifier.addListener(_refresh);
    _pin.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeBiometricPrompt());
  }

  /// On open, if a biometric-protected session is remembered, make biometrics
  /// the primary action and auto-prompt once. (No-op for a fresh sign-in.)
  Future<void> _maybeBiometricPrompt() async {
    final tokens = ref.read(tokenStoreProvider);
    await tokens.ensureLoaded();
    final notifier = ref.read(authControllerProvider.notifier);
    final remembered = tokens.hasSession && await notifier.isBiometricEnabled();
    if (!mounted || !remembered) return;
    setState(() => _biometricSession = true);
    await notifier.unlock(); // auto-prompt the OS biometric sheet
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _identifier.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _identifier.text.trim().isNotEmpty && _pin.text.length == 6;

  /// Biometric unlock for a returning user who enabled it. (When there's no
  /// stored session — the usual case on this screen — guide them to set it up.)
  Future<void> _biometricSignIn() async {
    final tokens = ref.read(tokenStoreProvider);
    await tokens.ensureLoaded();
    final notifier = ref.read(authControllerProvider.notifier);
    if (tokens.hasSession && await notifier.isBiometricEnabled()) {
      await notifier.unlock();
    } else if (mounted) {
      AppSnackbar.info(context,
          'Sign in with your PIN, then turn on biometrics in More → Security.');
    }
  }

  Future<void> _enter() async {
    FocusScope.of(context).unfocus();
    final identifier = _identifier.text.trim();
    if (identifier.isEmpty || _pin.text.length != 6 || _busy) return;

    // Pre-flight offline check — fail fast with a clear, actionable message.
    if (!ref.isOnline) {
      AppSnackbar.error(
        context,
        'No internet connection. Please check your network and try again.',
        onRetry: _enter,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(identifier: identifier, pin: _pin.text);
      // Success: AuthGate has swapped the root to HomeShell — clear this pushed
      // route to reveal it (no manual navigation to a screen).
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage, onRetry: _enter);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: AppScaffold(
        title: 'Sign in',
        // No back button when this is the biometric lock entry (it's the root).
        showBack: !_biometricSession,
        bottomAction: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_biometricSession) ...[
              AppButton(
                label: 'Unlock with biometrics',
                icon: Icons.fingerprint_rounded,
                onPressed: _biometricSignIn,
              ),
              const SizedBox(height: AppSizes.md),
              AppButton(
                label: 'Sign in with PIN',
                enabled: _canSubmit,
                loading: _busy,
                variant: AppButtonVariant.outline,
                onPressed: _enter,
              ),
            ] else ...[
              AppButton(
                label: 'Sign in',
                trailingIcon: Icons.arrow_forward_rounded,
                enabled: _canSubmit,
                loading: _busy,
                onPressed: _enter,
              ),
              const SizedBox(height: AppSizes.md),
              AppButton(
                label: 'Use biometrics',
                icon: Icons.fingerprint_rounded,
                variant: AppButtonVariant.outline,
                onPressed: _biometricSignIn,
              ),
            ],
            const SizedBox(height: AppSizes.md),
            _CreateAccountPrompt(),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSizes.sm),
            const BrandMark(pill: true),
            const SizedBox(height: AppSizes.xl),
            Text('Welcome back', style: AppText.h1),
            const SizedBox(height: AppSizes.sm),
            Text('Sign in to manage your protected transactions.',
                style: AppText.body),
            const SizedBox(height: AppSizes.xxl),
            AppTextField(
              label: 'Phone number',
              hint: 'Phone or email',
              icon: Icons.phone_outlined,
              controller: _identifier,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSizes.lg),
            Text('Transaction PIN', style: AppText.label),
            const SizedBox(height: AppSizes.sm),
            PinField(
              controller: _pin,
              length: 6,
              onCompleted: (_) {
                if (_canSubmit) _enter();
              },
            ),
            const SizedBox(height: AppSizes.md),
            GestureDetector(
              onTap: () => _showForgotPin(context),
              child: Text('Forgot PIN?',
                  style:
                      AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showForgotPin(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.xl, AppSizes.xl, AppSizes.xl, AppSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reset your PIN', style: AppText.h2),
            const SizedBox(height: AppSizes.sm),
            Text(
              'We\'ll send a reset link to your registered phone number and email.',
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Send reset link',
              onPressed: () {
                Navigator.of(context).pop();
                AppSnackbar.info(
                    context, 'Reset link sent to your phone and email.');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateAccountPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('New to Hoppr?', style: AppText.body),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => Navigator.of(context)
              .pushReplacement(AppNav.route(const SignUpScreen())),
          child: Text('Create account',
              style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
