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
      builder: (_) => _ForgotPinSheet(),
    );
  }
}

class _ForgotPinSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ForgotPinSheet> createState() => _ForgotPinSheetState();
}

class _ForgotPinSheetState extends ConsumerState<_ForgotPinSheet> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  bool get _canSend => _phone.text.trim().isNotEmpty;
  bool get _canConfirm =>
      _phone.text.trim().isNotEmpty &&
      _otp.text.trim().length == 6 &&
      _newPin.text.length == 6 &&
      _confirmPin.text.length == 6 &&
      _newPin.text == _confirmPin.text;

  @override
  void initState() {
    super.initState();
    for (final c in [_phone, _otp, _newPin, _confirmPin]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canSend) return;
    if (!context.mounted) return;
    final phone = _phone.text.trim();
    setState(() => _busy = true);
    try {
      final devOtp =
          await ref.read(authControllerProvider.notifier).requestPinReset(phone: phone);
      if (!mounted) return;
      setState(() => _sent = true);
      AppSnackbar.success(
        context,
        devOtp == null
            ? 'If the number exists, a PIN reset code has been sent.'
            : 'Dev OTP: $devOtp',
      );
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReset() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canConfirm) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).confirmPinReset(
            phone: _phone.text.trim(),
            otp: _otp.text.trim(),
            newPin: _newPin.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      AppSnackbar.success(context, 'Your PIN has been reset. You can sign in now.');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.xl,
        AppSizes.xl,
        AppSizes.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reset your PIN', style: AppText.h2),
          const SizedBox(height: AppSizes.sm),
          Text(
            _sent
                ? 'Enter the code we sent to your registered phone number, then choose a new 6-digit PIN.'
                : 'We will send a one-time code to your registered phone number to verify the reset.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          AppTextField(
            label: 'Phone number',
            hint: 'Enter your registered phone number',
            icon: Icons.phone_outlined,
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
          if (_sent) ...[
            const SizedBox(height: AppSizes.lg),
            AppTextField(
              label: 'Verification code',
              hint: '6-digit code',
              icon: Icons.verified_outlined,
              controller: _otp,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSizes.lg),
            Text('New PIN', style: AppText.label),
            const SizedBox(height: AppSizes.sm),
            AppTextField(
              hint: 'Enter new 6-digit PIN',
              icon: Icons.lock_outline,
              controller: _newPin,
              keyboardType: TextInputType.number,
              obscure: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: AppSizes.lg),
            AppTextField(
              label: 'Confirm PIN',
              hint: 'Re-enter new 6-digit PIN',
              icon: Icons.lock_outline,
              controller: _confirmPin,
              keyboardType: TextInputType.number,
              obscure: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: _sent ? 'Reset PIN' : 'Send code',
            loading: _busy,
            enabled: _sent ? _canConfirm : _canSend,
            onPressed: _sent ? _confirmReset : _sendOtp,
          ),
        ],
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
