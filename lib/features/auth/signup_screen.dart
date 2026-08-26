import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data/countries.dart';
import '../../core/native/firebase_phone_auth_service.dart';
import '../../core/native/phone_hint_service.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/providers.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/boxed_code_input.dart';
import '../../widgets/common.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../profile/identity_verification_screen.dart';
import 'application/auth_controller.dart';
import 'signin_screen.dart';

/// Multi-step sign-up wizard (4 steps). Step 1 matches the mockup exactly;
/// the remaining steps (phone OTP via Firebase, set PIN, done) complete the flow.
/// Phone verification uses Firebase Phone Auth client-side with server-side
/// verification — see `FirebasePhoneAuthService` and `confirmRegisterWithFirebase`.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  static const int _totalSteps = 4;
  final PageController _pager = PageController();
  late final _phoneAuth = FirebasePhoneAuthService();
  int _step = 0; // 0-based
  bool _busy = false;

  Timer? _resendTimer;
  int _resendIn = 0;
  String? _firebaseIdToken;

  // Step 1
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  Country _phoneCountry =
      countryByIso2(kDefaultCountryIso2) ?? kCountries.first;

  // Step 2 (OTP, 6 digits) & Step 3 (PIN, 6 digits)
  final _otp = TextEditingController();
  final _pin = TextEditingController();
  // Focus nodes so the OTP / PIN field auto-focuses (and the keyboard opens)
  // when its step becomes active — autofocus can't do this inside a PageView.
  final _otpFocus = FocusNode();
  final _pinFocus = FocusNode();
  final _phoneFocus = FocusNode();
  bool _phoneHintOffered = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_firstName, _lastName, _phone, _email, _otp, _pin]) {
      c.addListener(_refresh);
    }
    // Offer the OS phone-number picker the moment the field is first
    // focused, rather than requiring a separate tap on the "Google" chip —
    // still fully ignorable: dismissing it (or just typing) leaves the field
    // free to fill in manually.
    _phoneFocus.addListener(() {
      if (_phoneFocus.hasFocus) _maybeOfferPhoneHint();
    });
  }

  void _refresh() => setState(() {});

  Future<void> _maybeOfferPhoneHint() async {
    if (_phoneHintOffered || _phone.text.trim().isNotEmpty) return;
    _phoneHintOffered = true;
    final picked = await PhoneHintService.pickPhoneNumber();
    if (!mounted || picked == null || picked.trim().isEmpty) return;
    setState(() {
      _phone.text = picked.trim();
      _phone.selection = TextSelection.collapsed(offset: _phone.text.length);
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _pager.dispose();
    _otpFocus.dispose();
    _pinFocus.dispose();
    _phoneFocus.dispose();
    for (final c in [_firstName, _lastName, _phone, _email, _otp, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
    0 =>
      _firstName.text.trim().length >= 2 &&
          _firstName.text.trim().length <= 50 &&
          _lastName.text.trim().length >= 2 &&
          _lastName.text.trim().length <= 50 &&
          _phone.text.trim().length >= 7,
    1 => _otp.text.length == 6,
    2 => _pin.text.length == 6,
    _ => true,
  };

  String get _ctaLabel =>
      _step == _totalSteps - 1 ? 'Go to my dashboard' : 'Continue';

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
      _pager.animateToPage(
        _step,
        duration: AppDurations.normal,
        curve: AppDurations.easeOut,
      );
    }
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pager
        .animateToPage(
          step,
          duration: AppDurations.normal,
          curve: AppDurations.easeOut,
        )
        .then((_) {
          if (!mounted) return;
          // Auto-focus the field of the step we just landed on so its keyboard
          // opens without an extra tap.
          if (step == 1) {
            _otpFocus.requestFocus();
          } else if (step == 2) {
            _pinFocus.requestFocus();
          }
        });
  }

  void _advance() => _goToStep(_step + 1);

  /// Starts/restarts the resend countdown shown on the Verify step, using
  /// the cooldown the backend actually enforced.
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

  Future<void> _pickPhoneCountry() async {
    final c = await showCountryPicker(
      context,
      selectedIso2: _phoneCountry.iso2,
    );
    if (c != null) setState(() => _phoneCountry = c);
  }

  /// E.164-ish phone sent to the backend. A Google-picked number often already
  /// arrives with a "+" country code — used as-is in that case; otherwise
  /// the selected country's dial code is prepended to the typed digits.
  String _buildE164Phone() {
    final raw = _phone.text.trim();
    if (raw.startsWith('+')) return raw.replaceAll(RegExp(r'[\s()-]'), '');
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return '${_phoneCountry.dialCode}$digits';
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    final notifier = ref.read(authControllerProvider.notifier);

    switch (_step) {
      // Step 1 → start Firebase phone verification (SMS sent by Firebase).
      case 0:
        if (!ref.isOnline) {
          AppSnackbar.error(
            context,
            'No internet connection. Please check your network and try again.',
            onRetry: _next,
            autoRetryOnReconnect: true,
          );
          return;
        }
        final rawDigits = _phone.text.trim();
        if (rawDigits.startsWith('+') &&
            rawDigits.replaceAll(RegExp(r'\D'), '').length < 8) {
          AppSnackbar.error(context, 'Please include country code.');
          return;
        }
        final e164Phone = _buildE164Phone();
        if (e164Phone.replaceAll(RegExp(r'\D'), '').length < 8) {
          AppSnackbar.error(context, 'Invalid phone number.');
          return;
        }
        setState(() => _busy = true);
        try {
          // Reject an already-registered number immediately, before Firebase
          // ever sends a real SMS for it — the backend's own conflict check
          // at the final confirm step still guards this too, but only after
          // the person has already gone through the whole OTP flow.
          final available = await notifier.isPhoneAvailable(e164Phone);
          if (!available) {
            if (!mounted) return;
            setState(() => _busy = false);
            AppSnackbar.error(
              context,
              'An account with this phone number already exists. Try '
              'signing in instead.',
            );
            return;
          }
        } on ApiException catch (_) {
          // Fail open on a transient check failure — Firebase verification
          // and the backend's confirm-time conflict check still guard
          // against duplicates either way, so this never risks a double
          // account; it just skips the early, friendlier rejection.
        }
        try {
          await _phoneAuth.startVerification(
            phoneNumber: e164Phone,
            onCodeSent: (cooldown) {
              if (!mounted) return;
              setState(() => _busy = false);
              // Firebase can silently re-send a fresh SMS on its own (e.g.
              // falling back from Play Integrity to reCAPTCHA) — codeSent
              // fires again with a NEW verificationId even though the user
              // never tapped resend. If we're already past the phone-entry
              // step, re-advancing would yank them straight to the PIN step
              // with no code entered yet. Only advance the first time; a
              // later re-fire just restarts the cooldown and tells the user
              // a newer code is now the one that'll work.
              if (_step == 0) {
                _advance();
              } else {
                AppSnackbar.info(
                  context,
                  'A new code was just sent — use the latest SMS.',
                );
              }
              _startResendCountdown(cooldown);
            },
            onError: (e) {
              if (!mounted) return;
              setState(() => _busy = false);
              AppSnackbar.error(context, e.message);
            },
            onAutoVerified: (idToken) {
              // Firebase's own SMS Retriever can silently verify the code
              // the instant the SMS arrives — natively, independent of the
              // visible OTP box. That auto-verification CONSUMES the
              // verification session (it signs in + back out to mint the
              // token). Discarding this token used to be a real bug: the
              // same SMS also lands in the OTP field via Android's own
              // autofill, so the user's manual confirm would fire moments
              // later against an already-consumed session and fail with
              // "session-expired" ("Verification timed out") — even though
              // a perfectly valid token had already been minted right here.
              // Using it and jumping straight to the PIN step is both the
              // fix and a nicer flow — no retyping needed.
              if (!mounted) return;
              setState(() => _firebaseIdToken = idToken);
              _goToStep(2);
            },
          );
        } catch (e) {
          if (mounted) {
            setState(() => _busy = false);
            AppSnackbar.error(context, 'Failed to start phone verification.');
          }
        }

      // Step 2 → verify the Firebase OTP code. The idToken is then used
      // to create the account at step 3.
      case 1:
        if (!ref.isOnline) {
          AppSnackbar.error(
            context,
            'No internet connection. Please check your network and try again.',
            onRetry: _next,
            autoRetryOnReconnect: true,
          );
          return;
        }
        setState(() => _busy = true);
        try {
          final idToken = await _phoneAuth.confirmCode(_otp.text.trim());
          if (!mounted) return;
          setState(() => _firebaseIdToken = idToken);
          _advance();
        } on PhoneAuthException catch (e) {
          if (!mounted) return;
          // Android's silent SMS-Retriever auto-verify can win the race and
          // consume the verification session a moment before this manual
          // submit lands — that's a success already in hand, not a failure.
          if (_firebaseIdToken != null) {
            _advance();
          } else {
            AppSnackbar.error(context, e.message);
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }

      // Step 3 → create the account using the Firebase ID token plus
      // the PIN just set.
      case 2:
        if (!ref.isOnline) {
          AppSnackbar.error(
            context,
            'No internet connection. Please check your network and try again.',
            onRetry: _next,
            autoRetryOnReconnect: true,
          );
          return;
        }
        if (_firebaseIdToken == null) {
          AppSnackbar.error(
            context,
            'Phone verification failed. Please try again.',
          );
          return;
        }
        setState(() => _busy = true);
        try {
          final email = _email.text.trim();
          await notifier.confirmRegisterWithFirebase(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            phone: _buildE164Phone(),
            email: email.isEmpty ? null : email,
            pin: _pin.text,
            firebaseIdToken: _firebaseIdToken!,
          );
          // Session is now authenticated; HomeShell is live under this route.
          if (mounted) _advance();
        } on ApiException catch (e) {
          if (!mounted) return;
          AppSnackbar.error(context, e.userMessage);
        } finally {
          if (mounted) setState(() => _busy = false);
        }

      // Final step → reveal the dashboard AuthGate is already showing.
      default:
        Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  /// Re-request the code from Firebase (isResend=true).
  Future<void> _resendOtp() async {
    if (_busy || _resendIn > 0) return;
    if (!ref.isOnline) {
      AppSnackbar.error(
        context,
        'No internet connection. Please check your network and try again.',
        onRetry: _resendOtp,
        autoRetryOnReconnect: true,
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
        // Same fix as the initial send above — use the auto-verified token
        // instead of discarding it (see that comment for why discarding it
        // actually broke the manual-entry path too).
        onAutoVerified: (idToken) {
          if (!mounted) return;
          setState(() {
            _busy = false;
            _firebaseIdToken = idToken;
          });
          _goToStep(2);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnackbar.error(context, 'Failed to resend code.');
      }
    }
  }

  /// Lets the user back out of the OTP step to fix a mistyped number.
  /// Cancels the resend countdown and clears the code field — both are
  /// meaningless once the phone number changes, since a new OTP will need
  /// to be requested for the corrected number.
  void _changePhone() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 0);
    _otp.clear();
    _goToStep(0);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Header: back, title, step counter
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
                      Text('Sign up', style: AppText.title),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppIconButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: _back,
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.screenPad,
                  vertical: AppSizes.md,
                ),
                child: StepProgress(step: _step + 1, total: _totalSteps),
              ),
              Expanded(
                child: PageView(
                  controller: _pager,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _StepAccount(
                      firstName: _firstName,
                      lastName: _lastName,
                      phone: _phone,
                      phoneFocus: _phoneFocus,
                      email: _email,
                      country: _phoneCountry,
                      onPickCountry: _pickPhoneCountry,
                    ),
                    _StepOtp(
                      otp: _otp,
                      phone: _buildE164Phone(),
                      onResend: _resendOtp,
                      onChangePhone: _changePhone,
                      onCompleted: _next,
                      resendIn: _resendIn,
                      focusNode: _otpFocus,
                    ),
                    _StepPin(pin: _pin, focusNode: _pinFocus),
                    _StepDone(
                      name: '${_firstName.text.trim()} ${_lastName.text.trim()}'
                          .trim(),
                      contact: _email.text.trim().isNotEmpty
                          ? _email.text.trim()
                          : _phone.text.trim(),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  AppSizes.screenPad,
                  AppSizes.md,
                  AppSizes.screenPad,
                  AppSizes.lg + MediaQuery.of(context).padding.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      label: _ctaLabel,
                      trailingIcon: Icons.arrow_forward_rounded,
                      enabled: _canContinue,
                      loading: _busy,
                      onPressed: _next,
                    ),
                    if (_step == 0) ...[
                      const SizedBox(height: AppSizes.md),
                      _SignInPrompt(),
                    ],
                    const SizedBox(height: AppSizes.xs),
                    Center(
                      child: Text(
                        ref.watch(appVersionProvider).valueOrNull ?? '',
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Already have an account?', style: AppText.body),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => Navigator.of(
            context,
          ).pushReplacement(AppNav.route(const SignInScreen())),
          child: Text(
            'Sign in',
            style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Create your account
// ---------------------------------------------------------------------------
class _StepAccount extends StatelessWidget {
  const _StepAccount({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.phoneFocus,
    required this.email,
    required this.country,
    required this.onPickCountry,
  });

  final TextEditingController firstName;
  final TextEditingController lastName;
  final TextEditingController phone;
  final FocusNode phoneFocus;
  final TextEditingController email;
  final Country country;
  final VoidCallback onPickCountry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.sm,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Text('Create your account', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Tell us who you are. This name appears on your protected transactions.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.lg),
        AppTextField(
          label: 'First name',
          hint: 'Amara',
          icon: Icons.person_outline_rounded,
          controller: firstName,
          textInputAction: TextInputAction.next,
          autofocus: true,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z '-]")),
            LengthLimitingTextInputFormatter(50),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        AppTextField(
          label: 'Last name',
          hint: 'Okafor',
          icon: Icons.person_outline_rounded,
          controller: lastName,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z '-]")),
            LengthLimitingTextInputFormatter(50),
          ],
        ),
        const SizedBox(height: AppSizes.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 96,
              child: _CountryPickerField(
                country: country,
                onTap: onPickCountry,
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: AppTextField(
                label: 'Phone number',
                hint: '800 000 0000',
                icon: Icons.phone_outlined,
                controller: phone,
                focusNode: phoneFocus,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                // Field is freely editable (tap → keyboard) — focusing it
                // offers the OS phone-number picker (see
                // _maybeOfferPhoneHint) with no visible chip needed;
                // dismissing that popup or just typing never blocks manual
                // entry.
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.xs),
        Text(
          'We\'ll text a verification code to this number.',
          style: AppText.caption.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: AppSizes.md),
        AppTextField(
          label: 'Email (optional)',
          hint: 'you@email.com',
          icon: Icons.chat_bubble_outline_rounded,
          controller: email,
          keyboardType: TextInputType.emailAddress,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Verify your number (6-digit OTP)
// ---------------------------------------------------------------------------
class _StepOtp extends StatelessWidget {
  const _StepOtp({
    required this.otp,
    required this.phone,
    required this.onResend,
    required this.onChangePhone,
    required this.onCompleted,
    required this.resendIn,
    this.focusNode,
  });
  final TextEditingController otp;
  final String phone;
  final VoidCallback onResend;
  final VoidCallback onChangePhone;
  final VoidCallback onCompleted;
  final int resendIn;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.sm,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Text('Verify your number', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'We sent a 6-digit code to ${phone.isEmpty ? 'your phone' : phone}. Enter it to continue.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxl),
        BoxedCodeInput(
          controller: otp,
          length: 6,
          autofocus: false,
          focusNode: focusNode,
          autofillHints: const [AutofillHints.oneTimeCode],
          onCompleted: (_) => onCompleted(),
        ),
        const SizedBox(height: AppSizes.xl),
        Row(
          children: [
            Text("Didn't get it? ", style: AppText.body),
            if (resendIn > 0)
              Text(
                'Resend in ${resendIn}s',
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              GestureDetector(
                onTap: onResend,
                child: Text(
                  'Resend code',
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        GestureDetector(
          onTap: onChangePhone,
          child: Text(
            'Change phone number',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        const _DemoHint('6-digit code · check your SMS'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Secure your account (6-digit PIN)
// ---------------------------------------------------------------------------
class _StepPin extends StatelessWidget {
  const _StepPin({required this.pin, this.focusNode});
  final TextEditingController pin;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.sm,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Text('Secure your account', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Set a 6-digit transaction PIN. You\'ll use it to release funds.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxl),
        BoxedCodeInput(
          controller: pin,
          length: 6,
          obscure: true,
          autofocus: false,
          focusNode: focusNode,
        ),
        const SizedBox(height: AppSizes.lg),
        _NoteBanner(
          icon: Icons.lock_outline_rounded,
          text:
              'Never share your PIN. Hoppr will never ask for it by call or message.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — You're all set
// ---------------------------------------------------------------------------
class _StepDone extends StatelessWidget {
  const _StepDone({required this.name, required this.contact});
  final String name;
  final String contact;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'H';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }

  void _verifyNow(BuildContext context) {
    // Reveal the dashboard (AuthGate already shows it), then open verification.
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    nav.push(AppNav.route(const IdentityVerificationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.screenPad,
        AppSizes.sm,
        AppSizes.screenPad,
        AppSizes.xxl,
      ),
      children: [
        Text('You\'re all set', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Your Hoppr account is ready. Verify your identity anytime to earn the HTP badge.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxxl),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.textOnDark,
              size: 44,
            ),
          ).popIn(),
        ),
        const SizedBox(height: AppSizes.xxl),
        AppCard(
          child: Row(
            children: [
              InitialsAvatar(initials: _initials, size: 44),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.trim().isEmpty ? 'Your name' : name.trim(),
                      style: AppText.bodyStrong,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contact,
                        style: AppText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const StatusPill(
                label: 'Unverified',
                icon: Icons.info_outline_rounded,
                dense: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        AppButton(
          label: 'Verify identity now (optional)',
          icon: Icons.verified_outlined,
          variant: AppButtonVariant.outline,
          onPressed: () => _verifyNow(context),
        ),
      ],
    );
  }
}

/// Country dial-code picker beside the phone field — matches the field's own
/// label-above-box structure (AppTextField) so the two sit flush together.
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

/// Dashed "demo" hint pill (monospace) shown on the OTP step.
class _DemoHint extends StatelessWidget {
  const _DemoHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DottedBorderBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.md,
            vertical: AppSizes.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                text,
                style: AppText.caption.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft info banner (lock note on the PIN step).
class _NoteBanner extends StatelessWidget {
  const _NoteBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

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
          Expanded(child: Text(text, style: AppText.caption)),
        ],
      ),
    );
  }
}
