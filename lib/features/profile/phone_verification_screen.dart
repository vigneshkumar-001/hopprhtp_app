import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data/countries.dart';
import '../../core/native/firebase_phone_auth_service.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/boxed_code_input.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../auth/application/auth_controller.dart';

/// Optional Firebase Phone Auth verification — an additional trust signal
/// layered on top of (never a replacement for) the account's own session
/// auth and registration-time OTP. Two steps in one screen, mirroring the
/// sign-up wizard's own step pattern: phone entry, then a 6-digit code.
class PhoneVerificationScreen extends ConsumerStatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  ConsumerState<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState
    extends ConsumerState<PhoneVerificationScreen> {
  // `late` so FirebaseAuth.instance is only touched on first real use, not
  // the moment this screen is constructed (eager construction crashes
  // anywhere Firebase.initializeApp() hasn't run, e.g. widget tests).
  late final _phoneAuth = FirebasePhoneAuthService();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  int _step = 0; // 0 = phone entry, 1 = otp entry
  late Country _country = countryByIso2(kDefaultCountryIso2) ?? kCountries.first;
  bool _isSending = false;
  bool _isVerifying = false;
  String? _error;
  Timer? _cooldownTimer;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    final existingCountry =
        countryByIso2(ref.read(authControllerProvider).valueOrNull?.user?.phoneCountry);
    if (existingCountry != null) _country = existingCountry;
    _codeController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendCooldown <= 1) {
        t.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown -= 1);
      }
    });
  }

  Future<void> _pickCountry() async {
    final c = await showCountryPicker(context, selectedIso2: _country.iso2);
    if (c != null) setState(() => _country = c);
  }

  Future<void> _sendCode({bool isResend = false}) async {
    final digits = _phoneController.text.trim();
    if (digits.length < 6) {
      setState(() => _error = 'Invalid phone number.');
      return;
    }
    setState(() {
      _isSending = true;
      _error = null;
    });
    await _phoneAuth.startVerification(
      phoneNumber: '${_country.dialCode}$digits',
      isResend: isResend,
      onCodeSent: (cooldown) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _step = 1;
        });
        _startCooldown(cooldown);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _error = e.message;
        });
      },
      onAutoVerified: _submitToken,
    );
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      final idToken = await _phoneAuth.confirmCode(code);
      await _submitToken(idToken);
    } on PhoneAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _error = e.message;
      });
    }
  }

  Future<void> _submitToken(String idToken) async {
    if (!mounted) return;
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyPhoneWithFirebase(idToken);
      if (!mounted) return;
      AppSnackbar.success(context, 'Phone number verified successfully.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Verify Phone',
      bottomAction: _step == 0
          ? AppButton(
              label: 'Send Code',
              loading: _isSending,
              onPressed: _isSending ? null : () => _sendCode(),
            )
          : AppButton(
              label: 'Verify',
              loading: _isVerifying,
              enabled: _codeController.text.trim().length == 6,
              onPressed: _isVerifying ? null : _verifyCode,
            ),
      body: _step == 0 ? _buildPhoneStep() : _buildOtpStep(),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.lg),
        Text('Verify your phone number', style: AppText.h2),
        const SizedBox(height: AppSizes.sm),
        Text(
          "We'll send a 6-digit code to confirm you own this number.",
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSizes.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _CountryField(country: _country, onTap: _pickCountry)),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              flex: 5,
              child: AppTextField(
                controller: _phoneController,
                hint: 'Phone number',
                keyboardType: TextInputType.phone,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _sendCode(),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSizes.md),
          Text(_error!, style: AppText.body.copyWith(color: AppColors.danger)),
        ],
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSizes.lg),
        Text('Enter verification code', style: AppText.h2),
        const SizedBox(height: AppSizes.sm),
        Text(
          'Sent to ${_country.dialCode}${_phoneController.text.trim()}',
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSizes.xl),
        BoxedCodeInput(
          controller: _codeController,
          autofillHints: const [AutofillHints.oneTimeCode],
          onCompleted: (_) => _verifyCode(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSizes.md),
          Text(_error!, style: AppText.body.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSizes.lg),
        Center(
          child: TextButton(
            onPressed: _resendCooldown > 0 || _isSending
                ? null
                : () => _sendCode(isResend: true),
            child: Text(
              _resendCooldown > 0
                  ? 'Resend code in ${_resendCooldown}s'
                  : 'Resend code',
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryField extends StatelessWidget {
  const _CountryField({required this.country, required this.onTap});
  final Country country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppSizes.fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.md,
          border: Border.all(color: AppColors.border, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: AppSizes.sm),
            Text(country.dialCode, style: AppText.bodyStrong),
          ],
        ),
      ),
    );
  }
}
