import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/models.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common.dart';
import '../../widgets/number_keypad.dart';
import '../../widgets/segmented_control.dart' show MapBackdrop;
import 'delivery_confirmed_screen.dart';

enum _Phase { locked, locating, inZone }

/// Confirm delivery — locked → locating → inside-zone. The keypad only unlocks
/// once the buyer is confirmed inside the delivery geofence (simulated).
class ConfirmDeliveryScreen extends StatefulWidget {
  const ConfirmDeliveryScreen({super.key, required this.draft});
  final PaymentDraft draft;

  @override
  State<ConfirmDeliveryScreen> createState() => _ConfirmDeliveryScreenState();
}

class _ConfirmDeliveryScreenState extends State<ConfirmDeliveryScreen> {
  _Phase _phase = _Phase.locked;
  String _otp = '';
  static const _len = 6;
  static const _code = '482917';

  Future<void> _simulate() async {
    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.locating);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _phase = _Phase.inZone);
  }

  void _digit(String d) {
    if (_phase != _Phase.inZone || _otp.length >= _len) return;
    setState(() => _otp += d);
    if (_otp.length == _len) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) {
          AppNav.push(context, DeliveryConfirmedScreen(draft: widget.draft));
        }
      });
    }
  }

  void _back() {
    if (_otp.isEmpty) return;
    setState(() => _otp = _otp.substring(0, _otp.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final inZone = _phase == _Phase.inZone;
    final locating = _phase == _Phase.locating;

    return AppScaffold(
      title: 'Confirm delivery',
      scrollable: false,
      padding: EdgeInsets.zero,
      // Non-scrolling: the body fills a bounded Expanded, so a Spacer anchors
      // the keypad to the bottom (no IntrinsicHeight/GridView intrinsics).
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSizes.screenPad,
          AppSizes.sm,
          AppSizes.screenPad,
          AppSizes.lg + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                      ClipRRect(
                        borderRadius: AppRadii.lg,
                        child: Stack(
                          children: [
                            MapBackdrop(showGeofence: true, height: 128),
                            Positioned(
                              left: AppSizes.md,
                              bottom: AppSizes.md,
                              child: _MapPill(phase: _phase),
                            ),
                            const Positioned(
                              right: AppSizes.md,
                              top: AppSizes.md,
                              child: StatusPill(
                                  label: 'geofence · 200m', dense: true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSizes.md),
                      Text(
                        inZone
                            ? 'Enter the dispatcher\'s code'
                            : locating
                                ? 'Locating you…'
                                : 'Move into the delivery zone',
                        style: AppText.h1.copyWith(fontSize: 21),
                      ),
                      const SizedBox(height: AppSizes.xs),
                      _Subtitle(phase: _phase),
                      const SizedBox(height: AppSizes.lg),
                      _OtpRow(otp: _otp, length: _len, locked: !inZone),
                      const SizedBox(height: AppSizes.md),
                      // Demo hint only before typing; lock note while outside.
                      if (inZone && _otp.isEmpty)
                        const _DemoHint(code: _code)
                      else if (!inZone)
                        _LockNote(),
                      // Spacer pushes the keypad down to the bottom.
                      const Spacer(),
                      const SizedBox(height: AppSizes.lg),
                      // Keypad — crisp & active inside the zone, blurred
                      // otherwise with the current action floating over it.
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (inZone)
                            NumberKeypad(
                                enabled: true,
                                onDigit: _digit,
                                onBackspace: _back)
                          else
                            ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                  sigmaX: 2.6, sigmaY: 2.6),
                              child: NumberKeypad(
                                  enabled: false,
                                  onDigit: _digit,
                                  onBackspace: _back),
                            ),
                          if (locating)
                            const _LoadingPill(label: 'Locating you…')
                          else if (!inZone)
                            AppButton(
                              label: 'Simulate moving into the zone',
                              icon: Icons.my_location_rounded,
                              expand: false,
                              onPressed: _simulate,
                            ),
                        ],
                      ),
          ],
        ),
      ),
    );
  }
}

class _MapPill extends StatelessWidget {
  const _MapPill({required this.phase});
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case _Phase.inZone:
        return const StatusPill(
          label: 'Inside delivery zone',
          icon: Icons.check_circle,
          background: AppColors.surface,
          foreground: AppColors.success,
        );
      case _Phase.locating:
        // Lime circle with a continuously spinning sync icon while locating.
        final isLime = AppAccent.of(context).isLime;
        final ring = isLime ? const Color(0xFFCBF24A) : AppColors.ink;
        final onRing = isLime ? AppColors.textPrimary : AppColors.textOnDark;
        return Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
                child: _SpinningIcon(color: onRing),
              ),
              const SizedBox(width: 8),
              Text('Checking your location…',
                  style: AppText.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
            ],
          ),
        );
      case _Phase.locked:
        // Leading circular icon badge — orange-red in the Lime theme, ink in
        // Mono — on a white pill.
        final badge =
            AppAccent.of(context).isLime ? const Color(0xFFD9532F) : AppColors.ink;
        return Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                child: const Icon(Icons.location_on_outlined,
                    size: 16, color: AppColors.textOnDark),
              ),
              const SizedBox(width: 8),
              Text('Outside delivery zone',
                  style: AppText.caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
            ],
          ),
        );
    }
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.phase});
  final _Phase phase;

  @override
  Widget build(BuildContext context) {
    final style = AppText.body.copyWith(fontSize: 11.5, height: 1.5);
    switch (phase) {
      case _Phase.inZone:
        return Text.rich(
          TextSpan(style: style, children: const [
            TextSpan(text: 'Ask '),
            TextSpan(
                text: 'Tunde Bello',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            TextSpan(
                text:
                    ' to read you the 6-digit code, then type it below to release the parcel.'),
          ]),
        );
      case _Phase.locating:
        return Text(
          'Checking that you\'re at the delivery point before unlocking the code field.',
          style: style,
        );
      case _Phase.locked:
        return Text.rich(
          TextSpan(style: style, children: const [
            TextSpan(text: 'The OTP field stays locked until you\'re inside the '),
            TextSpan(
                text:
                    '200 m geofence at 14 Admiralty Way, Lekki Phase 1, Lagos. ',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            TextSpan(text: 'Move to the location to unlock it.'),
          ]),
        );
    }
  }
}

class _OtpRow extends StatelessWidget {
  const _OtpRow({required this.otp, required this.length, required this.locked});
  final String otp;
  final int length;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < length; i++)
          Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(right: i == length - 1 ? 0 : AppSizes.sm),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: locked ? AppColors.surfaceMuted : AppColors.surface,
                  borderRadius: AppRadii.md,
                  border: Border.all(
                    color: (!locked && i == otp.length)
                        ? AppColors.borderStrong
                        : AppColors.border,
                    width: (!locked && i == otp.length) ? 1.6 : 1.2,
                  ),
                ),
                // Masked: a filled dot for each entered digit.
                child: i < otp.length
                    ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Dotted hint that reveals the demo dispatcher's code.
class _DemoHint extends StatelessWidget {
  const _DemoHint({required this.code});
  final String code;

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
                'demo · dispatcher\'s code is ${code.split('').join(' ')}',
                style: AppText.caption.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "OTP field locked" note — text with a black lock-icon tile on the left.
class _LockNote extends StatelessWidget {
  const _LockNote();

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadii.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.isLime ? const Color(0xFFD9532F) : AppColors.ink,
              borderRadius: AppRadii.sm,
            ),
            child: const Icon(Icons.lock_outline_rounded,
                size: 20, color: AppColors.textOnDark),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.caption.copyWith(height: 1.4),
                children: const [
                  TextSpan(
                      text: 'OTP field locked. ',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  TextSpan(
                      text:
                          'Move inside the delivery geofence to unlock it — the code can\'t be entered from outside.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sync icon that spins continuously (used in the "locating" map pill).
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.color});
  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _c,
      child: Icon(Icons.sync_rounded, size: 16, color: widget.color),
    );
  }
}

/// Disabled-looking pill with a spinner, shown while "locating".
class _LoadingPill extends StatelessWidget {
  const _LoadingPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSizes.buttonHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
      decoration: BoxDecoration(
        color: const Color(0xFF55585E),
        borderRadius: AppRadii.btn,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(AppColors.textOnDark),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(label,
              style: AppText.button.copyWith(fontSize: 14)),
        ],
      ),
    );
  }
}
