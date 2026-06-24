import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/common.dart';
import '../../widgets/pin_field.dart';
import '../home/home_shell.dart';
import 'signup_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _identifier = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _identifier.addListener(_refresh);
    _pin.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _identifier.dispose();
    _pin.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _identifier.text.trim().isNotEmpty && _pin.text.length == 4;

  Future<void> _enter({bool biometric = false}) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await Future<void>.delayed(AppDurations.normal);
    if (!mounted) return;
    AppScope.read(context).signIn(
      identifier: _identifier.text.trim().isEmpty
          ? 'amara@hoppr.app'
          : _identifier.text.trim(),
    );
    AppNav.replaceAll(context, const HomeShell());
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: AppScaffold(
        title: 'Sign in',
        bottomAction: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              onPressed: () => _enter(biometric: true),
            ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reset link sent')),
                );
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
