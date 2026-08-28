import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_button.dart';
import '../../widgets/common.dart';
import '../auth/application/auth_controller.dart';

class _TourSlide {
  const _TourSlide({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _TourSlide(
    icon: Icons.lock_outline_rounded,
    title: 'Your money, held safe',
    body:
        'Every payment sits in escrow the moment it\'s made — it only reaches '
        'the seller once delivery is actually confirmed, never on trust alone.',
  ),
  _TourSlide(
    icon: Icons.send_rounded,
    title: 'Send a payment link in seconds',
    body:
        'Create a transaction, share the link, and get paid the moment your '
        'buyer funds escrow — no back-and-forth required.',
  ),
  _TourSlide(
    icon: Icons.local_shipping_outlined,
    title: 'Track every delivery live',
    body:
        'Follow your package on the map in real time, right up to the '
        'geofenced hand-off that releases the funds.',
  ),
  _TourSlide(
    icon: Icons.gavel_rounded,
    title: 'Covered if something goes wrong',
    body:
        'Raise a dispute any time before release — your funds stay frozen '
        'and protected until Hoppr helps reach a fair outcome.',
  ),
  _TourSlide(
    icon: Icons.celebration_rounded,
    title: "You're all set",
    body:
        'Start your first protected transaction whenever you\'re ready — '
        'we\'ll be right here if you need anything.',
  ),
];

/// A one-time, animated walkthrough of what Hoppr actually does — shown
/// exactly once per account, gated by [ApiUser.hasSeenTutorial] (server-side
/// truth, see userService.migrateTutorialSeenForExistingUsers so an existing
/// user is never shown this). Skippable at any point; both Skip and
/// finishing the last slide mark it seen the same way.
class AppTutorialScreen extends ConsumerStatefulWidget {
  const AppTutorialScreen({super.key});

  @override
  ConsumerState<AppTutorialScreen> createState() => _AppTutorialScreenState();
}

class _AppTutorialScreenState extends ConsumerState<AppTutorialScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    HapticFeedback.selectionClick();
    _controller.nextPage(
      duration: AppDurations.normal,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    // Best-effort: never trap the user on this screen behind a network
    // call — if marking it seen fails (offline, timeout), they still move
    // on, and the next successful `/users/me` fetch will just try again on
    // its own next app open rather than blocking here.
    try {
      await ref.read(authControllerProvider.notifier).markTutorialSeen();
    } catch (_) {
      // Swallowed deliberately — see comment above.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return PopScope(
      // Back gesture behaves exactly like Skip — never a dead end, and it
      // still marks the tutorial seen so it doesn't reappear.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.screenPad,
            ),
            child: Column(
              children: [
                const SizedBox(height: AppSizes.sm),
                Row(
                  children: [
                    const BrandMark(),
                    const Spacer(),
                    if (!_finishing)
                      TextButton(
                        onPressed: _finish,
                        child: Text(
                          'Skip',
                          style: AppText.bodyStrong.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                    },
                    itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                PageDots(
                  count: _slides.length,
                  index: _index,
                  activeColor: accent.accent,
                  inactiveColor: AppColors.border,
                ),
                const SizedBox(height: AppSizes.xl),
                AppButton(
                  label: _isLast ? 'Get started' : 'Next',
                  trailingIcon: _isLast ? null : Icons.arrow_forward_rounded,
                  accentInLime: true,
                  loading: _finishing,
                  onPressed: _next,
                ),
                const SizedBox(height: AppSizes.lg),
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
  final _TourSlide slide;

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: accent.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(slide.icon, size: 42, color: accent.onAccentSoft),
            )
            .animate()
            .scale(
              duration: 480.ms,
              curve: Curves.easeOutBack,
              begin: const Offset(0.55, 0.55),
              end: const Offset(1, 1),
            )
            .fadeIn(duration: 320.ms),
        const SizedBox(height: AppSizes.xxl),
        Text(
              slide.title,
              textAlign: TextAlign.center,
              style: AppText.h1,
            )
            .animate()
            .fadeIn(delay: 140.ms, duration: 340.ms)
            .slideY(
              begin: 0.2,
              end: 0,
              delay: 140.ms,
              duration: 340.ms,
              curve: Curves.easeOut,
            ),
        const SizedBox(height: AppSizes.md),
        Text(
              slide.body,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            )
            .animate()
            .fadeIn(delay: 220.ms, duration: 340.ms)
            .slideY(
              begin: 0.2,
              end: 0,
              delay: 220.ms,
              duration: 340.ms,
              curve: Curves.easeOut,
            ),
      ],
    );
  }
}
