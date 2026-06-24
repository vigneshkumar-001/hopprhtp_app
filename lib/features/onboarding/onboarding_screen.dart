import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/common.dart';
import '../auth/signin_screen.dart';
import '../auth/signup_screen.dart';

class _Slide {
  const _Slide({required this.chip, required this.title, required this.body});
  final String chip;
  final String title;
  final String body;
}

const List<_Slide> _slides = [
  _Slide(
    chip: 'Funds secured in escrow',
    title: 'Buy & sell\nwithout the\ntrust fall.',
    body:
        'Your funds are protected in escrow until delivery is verified within the designated geofence.',
  ),
  _Slide(
    chip: 'Verified merchants',
    title: 'Deal only\nwith trusted\nsellers.',
    body:
        'Every HTP-verified merchant passes ID and payout checks before they can receive a naira.',
  ),
  _Slide(
    chip: 'Geofenced delivery',
    title: 'Released on\nproof, not\npromises.',
    body:
        'Couriers confirm hand-off inside the agreed geofence — funds release the moment it lands.',
  ),
  _Slide(
    chip: 'Disputes, handled',
    title: 'Fair\nresolution,\nevery time.',
    body:
        'If something goes wrong, your money stays put while Hoppr mediates a fair outcome.',
  ),
];

/// The first screen — dark, full-bleed marketing carousel.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _getStarted() => AppNav.push(context, const SignUpScreen());
  void _signIn() => AppNav.push(context, const SignInScreen());

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSizes.md),
                const BrandMark(onDark: true, withBadge: true),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                PageDots(count: _slides.length, index: _index),
                const SizedBox(height: AppSizes.xl),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Get started',
                        trailingIcon: Icons.arrow_forward_rounded,
                        variant: AppButtonVariant.outline,
                        accentInLime: true,
                        onPressed: _getStarted,
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    _BoltButton(onTap: _getStarted),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                Center(
                  child: GestureDetector(
                    onTap: _signIn,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'I already have an account',
                        style: AppText.bodyStrong.copyWith(
                          color: AppAccent.of(context).isLime
                              ? AppAccent.of(context).highlight
                              : AppColors.textOnDarkMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    // Highlight the last line of the headline with the accent.
    final lines = slide.title.split('\n');
    final head = lines.length > 1
        ? '${lines.sublist(0, lines.length - 1).join('\n')}\n'
        : '';
    final tail = lines.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md, vertical: AppSizes.sm),
          decoration: BoxDecoration(
            color: AppColors.inkSoft,
            borderRadius: AppRadii.pill,
            border: Border.all(color: AppColors.divider, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.isLime ? accent.accent : AppColors.inkSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 13,
                    color: accent.isLime
                        ? accent.onAccent
                        : AppColors.textOnDark),
              ),
              const SizedBox(width: 8),
              Text(slide.chip,
                  style: AppText.label.copyWith(
                      color: AppColors.textOnDark, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.lg),
        Text.rich(
          TextSpan(
            style: AppText.display.copyWith(color: AppColors.textOnDark),
            children: [
              TextSpan(text: head),
              TextSpan(text: tail, style: TextStyle(color: accent.highlight)),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.md),
        Text('Hoppr secures your money',
            style: AppText.h3.copyWith(color: AppColors.textOnDark)),
        const SizedBox(height: AppSizes.sm),
        Text(slide.body,
            style: AppText.body.copyWith(color: AppColors.textOnDarkMuted)),
        const SizedBox(height: AppSizes.xl),
      ],
    );
  }
}

class _BoltButton extends StatelessWidget {
  const _BoltButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inkSoft,
      borderRadius: AppRadii.btn,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: AppSizes.buttonHeight,
          height: AppSizes.buttonHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadii.btn,
            border: Border.all(color: AppColors.divider, width: 1),
          ),
          child: const Icon(Icons.bolt_rounded,
              color: AppColors.textOnDark, size: 24),
        ),
      ),
    );
  }
}
