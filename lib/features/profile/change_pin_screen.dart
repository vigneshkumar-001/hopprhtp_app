import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/boxed_code_input.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../auth/application/auth_controller.dart';

/// Change PIN — a modern 3-step flow: verify the current PIN, choose a new one,
/// then confirm it. One field per step (not all three on one screen).
class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  static const int _total = 3;

  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  int _step = 0;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  TextEditingController get _active =>
      [_current, _next, _confirm][_step];

  bool get _canContinue => _active.text.length == 6;

  void _goTo(int step) => setState(() => _step = step);

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      _goTo(_step - 1);
    }
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canContinue) return;

    switch (_step) {
      // Step 1 → verify the current PIN before letting them choose a new one.
      case 0:
        if (!ref.isOnline) return _offline();
        setState(() => _busy = true);
        try {
          await ref
              .read(authControllerProvider.notifier)
              .verifyAccountPin(_current.text);
          if (mounted) _goTo(1);
        } on ApiException catch (e) {
          if (mounted) AppSnackbar.error(context, e.userMessage);
        } finally {
          if (mounted) setState(() => _busy = false);
        }

      // Step 2 → choose a new PIN (must differ from the current one).
      case 1:
        if (_next.text == _current.text) {
          AppSnackbar.error(
              context, 'Your new PIN must be different from the current one.');
          return;
        }
        _goTo(2);

      // Step 3 → confirm + save.
      case 2:
        if (_confirm.text != _next.text) {
          AppSnackbar.error(context, "Those PINs don't match. Try again.");
          _confirm.clear();
          return;
        }
        if (!ref.isOnline) return _offline();
        setState(() => _busy = true);
        try {
          await ref
              .read(authControllerProvider.notifier)
              .changePin(currentPin: _current.text, newPin: _next.text);
          if (!mounted) return;
          AppSnackbar.success(context, 'Your PIN has been updated.');
          Navigator.of(context).pop();
        } on ApiException catch (e) {
          if (!mounted) return;
          // Current PIN rejected at save (rare) → restart from step 1.
          if (e.message.toLowerCase().contains('current pin')) {
            _current.clear();
            _goTo(0);
          }
          AppSnackbar.error(context, e.userMessage);
        } finally {
          if (mounted) setState(() => _busy = false);
        }
    }
  }

  void _offline() => AppSnackbar.error(context,
      'No internet connection. Please check your network and try again.');

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.md, AppSizes.sm, AppSizes.screenPad, AppSizes.sm),
              child: SizedBox(
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text('Change PIN', style: AppText.title),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: _busy ? null : _back,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('${_step + 1}/$_total',
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
              child: StepProgress(step: _step + 1, total: _total),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppDurations.normal,
                switchInCurve: AppDurations.easeOut,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0.06, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: _PinStep(
                  key: ValueKey(_step),
                  data: step,
                  controller: _active,
                  onChanged: () => setState(() {}),
                  onCompleted: _continue,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                AppSizes.screenPad,
                AppSizes.md,
                AppSizes.screenPad,
                AppSizes.lg + MediaQuery.of(context).padding.bottom,
              ),
              child: AppButton(
                label: _step == _total - 1 ? 'Update PIN' : 'Continue',
                trailingIcon: Icons.arrow_forward_rounded,
                enabled: _canContinue,
                loading: _busy,
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<_StepData> _steps = [
    _StepData(
      icon: Icons.lock_outline_rounded,
      title: 'Enter your current PIN',
      subtitle: "Confirm it's you before setting a new PIN.",
      note: 'Hoppr will never ask for your PIN by call or message.',
    ),
    _StepData(
      icon: Icons.pin_outlined,
      title: 'Set a new PIN',
      subtitle: 'Choose a new 6-digit transaction PIN.',
      note: 'Avoid easy guesses like 123456 or your year of birth.',
    ),
    _StepData(
      icon: Icons.verified_user_outlined,
      title: 'Confirm your new PIN',
      subtitle: 'Re-enter your new PIN to finish.',
      note: null,
    ),
  ];
}

class _StepData {
  const _StepData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.note,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? note;
}

class _PinStep extends StatelessWidget {
  const _PinStep({
    super.key,
    required this.data,
    required this.controller,
    required this.onChanged,
    required this.onCompleted,
  });

  final _StepData data;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSizes.screenPad, AppSizes.lg, AppSizes.screenPad, AppSizes.xxl),
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: accent.accentSoft,
            borderRadius: AppRadii.lg,
          ),
          child: Icon(data.icon, color: accent.onAccentSoft, size: 26),
        ),
        const SizedBox(height: AppSizes.lg),
        Text(data.title, style: AppText.h1),
        const SizedBox(height: AppSizes.sm),
        Text(data.subtitle, style: AppText.body),
        const SizedBox(height: AppSizes.xxl),
        BoxedCodeInput(
          controller: controller,
          length: 6,
          obscure: true,
          onChanged: (_) => onChanged(),
          onCompleted: (_) => onCompleted(),
        ),
        if (data.note != null) ...[
          const SizedBox(height: AppSizes.lg),
          Container(
            padding: const EdgeInsets.all(AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: AppSizes.sm),
                Expanded(child: Text(data.note!, style: AppText.caption)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
