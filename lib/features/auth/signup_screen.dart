import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/animations.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/boxed_code_input.dart';
import '../../widgets/common.dart';
import '../profile/identity_verification_screen.dart';
import '../home/home_shell.dart';
import 'signin_screen.dart';

/// Multi-step sign-up wizard (4 steps). Step 1 matches the mockup exactly;
/// the remaining steps (phone OTP, set PIN, done) complete the flow.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const int _totalSteps = 4;
  final PageController _pager = PageController();
  int _step = 0; // 0-based

  // Step 1
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  // Step 2 (OTP, 6 digits) & Step 3 (PIN, 6 digits)
  final _otp = TextEditingController();
  final _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _email, _otp, _pin]) {
      c.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _pager.dispose();
    for (final c in [_name, _phone, _email, _otp, _pin]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
        0 => _name.text.trim().isNotEmpty && _phone.text.trim().length >= 7,
        1 => _otp.text.length >= 4, // demo: 4–6 digits
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
      _pager.animateToPage(_step,
          duration: AppDurations.normal, curve: AppDurations.easeOut);
    }
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (_step < _totalSteps - 1) {
      // On the final form step, persist the account before the success page.
      if (_step == 2) {
        AppScope.read(context).signUp(
          fullName: _name.text,
          phone: _phone.text,
          email: _email.text,
        );
      }
      setState(() => _step++);
      _pager.animateToPage(_step,
          duration: AppDurations.normal, curve: AppDurations.easeOut);
    } else {
      AppNav.replaceAll(context, const HomeShell());
    }
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
                    AppSizes.md, AppSizes.sm, AppSizes.screenPad, AppSizes.sm),
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
                        child: Text('${_step + 1}/$_totalSteps',
                            style: AppText.label
                                .copyWith(color: AppColors.textTertiary)),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.screenPad, vertical: AppSizes.md),
                child: StepProgress(step: _step + 1, total: _totalSteps),
              ),
              Expanded(
                child: PageView(
                  controller: _pager,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _StepAccount(
                        name: _name, phone: _phone, email: _email),
                    _StepOtp(otp: _otp, phone: _phone.text),
                    _StepPin(pin: _pin),
                    _StepDone(
                      name: _name.text,
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
                      onPressed: _next,
                    ),
                    if (_step == 0) ...[
                      const SizedBox(height: AppSizes.md),
                      _SignInPrompt(),
                    ],
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
          onTap: () => Navigator.of(context).pushReplacement(
            AppNav.route(const SignInScreen()),
          ),
          child: Text('Sign in',
              style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800)),
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
    required this.name,
    required this.phone,
    required this.email,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPad, AppSizes.sm, AppSizes.screenPad, AppSizes.xxl),
      children: [
        Text('Create your account', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Tell us who you are. This name appears on your protected transactions.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxl),
        AppTextField(
          label: 'Full name',
          hint: 'Amara Okafor',
          icon: Icons.person_outline_rounded,
          controller: name,
          textInputAction: TextInputAction.next,
          autofocus: true,
        ),
        const SizedBox(height: AppSizes.lg),
        AppTextField(
          label: 'Phone number',
          hint: '+234 800 000 0000',
          icon: Icons.phone_outlined,
          controller: phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSizes.lg),
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
  const _StepOtp({required this.otp, required this.phone});
  final TextEditingController otp;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPad, AppSizes.sm, AppSizes.screenPad, AppSizes.xxl),
      children: [
        Text('Verify your number', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'We sent a 6-digit code to ${phone.isEmpty ? 'your phone' : phone}. Enter it to continue.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxl),
        BoxedCodeInput(controller: otp, length: 6, autofocus: false),
        const SizedBox(height: AppSizes.xl),
        Row(
          children: [
            Text("Didn't get it? ", style: AppText.body),
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Code resent')),
              ),
              child: Text('Resend code',
                  style:
                      AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.lg),
        const _DemoHint('demo · type any 4–6 digits'),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Secure your account (6-digit PIN)
// ---------------------------------------------------------------------------
class _StepPin extends StatelessWidget {
  const _StepPin({required this.pin});
  final TextEditingController pin;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPad, AppSizes.sm, AppSizes.screenPad, AppSizes.xxl),
      children: [
        Text('Secure your account', style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Set a 6-digit transaction PIN. You\'ll use it to release funds.',
          style: AppText.body,
        ),
        const SizedBox(height: AppSizes.xxl),
        BoxedCodeInput(controller: pin, length: 6, obscure: true, autofocus: false),
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
    // Land on the dashboard, then open the verification flow on top of it.
    final nav = Navigator.of(context);
    nav.pushAndRemoveUntil(AppNav.route(const HomeShell()), (r) => false);
    nav.push(AppNav.route(const IdentityVerificationScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPad, AppSizes.sm, AppSizes.screenPad, AppSizes.xxl),
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
            child: const Icon(Icons.check_rounded,
                color: AppColors.textOnDark, size: 44),
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
                    Text(name.trim().isEmpty ? 'Your name' : name.trim(),
                        style: AppText.bodyStrong,
                        overflow: TextOverflow.ellipsis),
                    if (contact.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(contact,
                          style: AppText.caption,
                          overflow: TextOverflow.ellipsis),
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
              horizontal: AppSizes.md, vertical: AppSizes.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.textTertiary),
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
