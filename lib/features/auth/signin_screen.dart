import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data/countries.dart';
import '../../core/native/firebase_phone_auth_service.dart';
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
import '../../widgets/country_picker_sheet.dart';
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
  // Same default + picker as sign-up's phone step — sign-in is phone-only
  // now (see [_buildIdentifier]/the identifier field's digitsOnly formatter
  // below), so this always applies.
  Country _phoneCountry = countryByIso2(kDefaultCountryIso2) ?? kCountries.first;

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

  Future<void> _pickPhoneCountry() async {
    final c = await showCountryPicker(context, selectedIso2: _phoneCountry.iso2);
    if (c != null) setState(() => _phoneCountry = c);
  }

  /// The same 10 digits can be a real number in more than one supported
  /// country (e.g. +91 7904005315 vs +234 7904005315), so a bare number
  /// typed here is genuinely ambiguous without the country picker — this
  /// prepends the selected dial code exactly like sign-up's phone step.
  /// Left untouched for email (contains '@') or an already-"+"-prefixed
  /// number (e.g. pasted from the Google number picker).
  String _buildIdentifier() {
    final digits = _identifier.text.trim();
    if (digits.isEmpty) return digits;
    return '${_phoneCountry.dialCode}$digits';
  }

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
    final identifier = _buildIdentifier();
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
      if (!mounted) return;
      if (isAccountBlockedCode(e.code)) {
        unawaited(_showBlockedDialog(code: e.code, message: e.userMessage));
      } else {
        AppSnackbar.error(context, e.userMessage, onRetry: _enter);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A frozen/deleted account gets a deliberate modal instead of a snackbar
  /// that could be missed or swiped away — same messaging as
  /// [AccountBlockedScreen], just as a dialog since sign-in is already the
  /// right place to land (no navigation needed).
  Future<void> _showBlockedDialog({
    required String code,
    required String message,
  }) {
    final isDeleted = code == 'ACCOUNT_DELETED';
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          isDeleted ? Icons.person_off_rounded : Icons.lock_person_rounded,
          color: AppColors.danger,
          size: 32,
        ),
        title: Text(isDeleted ? 'Account no longer available' : 'Account frozen'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
            ] else
              AppButton(
                label: 'Sign in',
                trailingIcon: Icons.arrow_forward_rounded,
                enabled: _canSubmit,
                loading: _busy,
                onPressed: _enter,
              ),
            const SizedBox(height: AppSizes.md),
            _CreateAccountPrompt(),
            const SizedBox(height: AppSizes.sm),
            Center(
              child: Text(
                ref.watch(appVersionProvider).valueOrNull ?? '',
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 96,
                  child: _CountryPickerField(
                    country: _phoneCountry,
                    onTap: _pickPhoneCountry,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: AppTextField(
                    label: 'Phone number',
                    hint: 'Phone number',
                    icon: Icons.phone_outlined,
                    controller: _identifier,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
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
    final identifier = _identifier.text.trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      // Carry over whatever the person already typed on the sign-in field —
      // only if it looks like a phone (not an email), so they don't have to
      // retype it. Still freely editable in the sheet if it's wrong.
      builder: (_) => _ForgotPinSheet(
        initialPhone: identifier.contains('@') ? null : identifier,
        initialCountry: _phoneCountry,
      ),
    );
  }
}

class _ForgotPinSheet extends ConsumerStatefulWidget {
  const _ForgotPinSheet({this.initialPhone, this.initialCountry});

  /// Whatever the person already typed in the sign-in identifier field —
  /// prefilled here so they don't retype it, but still freely editable.
  final String? initialPhone;
  final Country? initialCountry;

  @override
  ConsumerState<_ForgotPinSheet> createState() => _ForgotPinSheetState();
}

class _ForgotPinSheetState extends ConsumerState<_ForgotPinSheet> {
  late final _phone = TextEditingController(text: widget.initialPhone ?? '');
  final _otp = TextEditingController();
  final _newPin = TextEditingController();
  final _confirmPin = TextEditingController();
  late final _phoneAuth = FirebasePhoneAuthService();
  // Same default + picker as sign-up's phone step — a bare number is
  // ambiguous between supported countries without it (see signin_screen's
  // own phone field for the login-time version of this fix).
  late Country _phoneCountry =
      widget.initialCountry ?? countryByIso2(kDefaultCountryIso2) ?? kCountries.first;

  int _stage = 0; // 0 phone · 1 OTP · 2 new PIN
  bool _busy = false;
  Timer? _resendTimer;
  int _resendIn = 0;
  String? _firebaseIdToken;

  bool get _canSend => _phone.text.trim().isNotEmpty;
  bool get _canConfirmCode => _otp.text.trim().length == 6;
  bool get _canReset =>
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
    _resendTimer?.cancel();
    _phone.dispose();
    _otp.dispose();
    _newPin.dispose();
    _confirmPin.dispose();
    super.dispose();
  }

  Future<void> _pickPhoneCountry() async {
    final c = await showCountryPicker(context, selectedIso2: _phoneCountry.iso2);
    if (c != null) setState(() => _phoneCountry = c);
  }

  /// Same E.164-building rule as sign-up's phone step.
  String _buildE164Phone() {
    final raw = _phone.text.trim();
    if (raw.startsWith('+')) return raw.replaceAll(RegExp(r'[\s()-]'), '');
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return '${_phoneCountry.dialCode}$digits';
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  /// Step 1 — Firebase sends the SMS directly; no backend call needed here.
  Future<void> _sendCode() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canSend) return;
    if (!ref.isOnline) {
      AppSnackbar.error(
        context,
        'No internet connection. Please check your network and try again.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _phoneAuth.startVerification(
        phoneNumber: _buildE164Phone(),
        onCodeSent: (cooldown) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _stage = 1;
          });
          _startResendCountdown(cooldown);
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _busy = false);
          AppSnackbar.error(context, e.message);
        },
        onAutoVerified: (idToken) {
          if (!mounted) return;
          setState(() {
            _firebaseIdToken = idToken;
            _stage = 2;
          });
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(context, 'Failed to send verification code.');
      }
    }
  }

  Future<void> _resendCode() async {
    if (_busy || _resendIn > 0) return;
    if (!ref.isOnline) {
      AppSnackbar.error(
        context,
        'No internet connection. Please check your network and try again.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _phoneAuth.startVerification(
        phoneNumber: _buildE164Phone(),
        isResend: true,
        onCodeSent: (cooldown) {
          if (!mounted) return;
          setState(() => _busy = false);
          _startResendCountdown(cooldown);
          AppSnackbar.success(context, 'A new code has been sent.');
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _busy = false);
          AppSnackbar.error(context, e.message);
        },
        onAutoVerified: (idToken) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _firebaseIdToken = idToken;
            _stage = 2;
          });
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(context, 'Failed to resend code.');
      }
    }
  }

  /// Step 2 — confirm the Firebase code to get an ID token proving phone
  /// ownership; that token (not the phone number itself) is what the
  /// backend trusts to reset the PIN.
  Future<void> _confirmCode() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canConfirmCode) return;
    setState(() => _busy = true);
    try {
      final idToken = await _phoneAuth.confirmCode(_otp.text.trim());
      if (!mounted) return;
      setState(() {
        _firebaseIdToken = idToken;
        _stage = 2;
      });
    } on PhoneAuthException catch (e) {
      if (!mounted) return;
      // Android's silent SMS-Retriever auto-verify can win the race and
      // consume the verification session a moment before the user's manual
      // tap lands — that's a success, not a failure. Only surface the error
      // if auto-verify hasn't already gotten us a usable token.
      if (_firebaseIdToken != null) {
        setState(() => _stage = 2);
      } else {
        AppSnackbar.error(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Step 3 — set the new PIN using the already-verified Firebase token.
  Future<void> _resetPin() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canReset || _firebaseIdToken == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).confirmPinResetWithFirebase(
            firebaseIdToken: _firebaseIdToken!,
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
    // Belt-and-braces bottom padding: viewInsets.bottom clears the keyboard,
    // viewPadding.bottom clears the gesture-nav bar even if the modal's own
    // useSafeArea wrapping doesn't (some OEM nav-bar heights render inside a
    // ClipRRect'd bottom sheet without it, clipping the button).
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.xl,
        AppSizes.xl,
        AppSizes.lg +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reset your PIN', style: AppText.h2),
          const SizedBox(height: AppSizes.sm),
          Text(
            switch (_stage) {
              1 => 'Enter the 6-digit code we sent to your phone.',
              2 => 'Choose a new 6-digit PIN.',
              _ => "Enter your registered phone number — we'll text you a "
                  'verification code.',
            },
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          if (_stage == 0)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 96,
                  child: _CountryPickerField(
                    country: _phoneCountry,
                    onTap: _pickPhoneCountry,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  child: AppTextField(
                    label: 'Phone number',
                    hint: 'Enter your registered phone number',
                    icon: Icons.phone_outlined,
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    autofillHints: const [AutofillHints.telephoneNumber],
                  ),
                ),
              ],
            ),
          if (_stage == 1) ...[
            AppTextField(
              label: 'Verification code',
              hint: '6-digit code',
              icon: Icons.verified_outlined,
              controller: _otp,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSizes.sm),
            GestureDetector(
              onTap: _resendIn > 0 ? null : _resendCode,
              child: Text(
                _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
                style: AppText.bodyStrong.copyWith(
                  color: _resendIn > 0 ? AppColors.textTertiary : null,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          if (_stage == 2) ...[
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
            label: switch (_stage) {
              1 => 'Verify code',
              2 => 'Reset PIN',
              _ => 'Send code',
            },
            loading: _busy,
            enabled: switch (_stage) {
              1 => _canConfirmCode,
              2 => _canReset,
              _ => _canSend,
            },
            onPressed: switch (_stage) {
              1 => _confirmCode,
              2 => _resetPin,
              _ => _sendCode,
            },
          ),
        ],
      ),
    );
  }
}

class _CountryPickerField extends StatelessWidget {
  const _CountryPickerField({required this.country, required this.onTap});
  final Country country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Code', style: AppText.label),
        const SizedBox(height: AppSizes.sm),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: AppSizes.fieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadii.md,
              border: Border.all(color: AppColors.border, width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(country.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    country.dialCode,
                    style: AppText.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
