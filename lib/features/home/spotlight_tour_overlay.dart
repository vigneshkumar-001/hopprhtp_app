import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_accent.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';

/// One stop on the spotlight tour — [targetKey] must belong to a widget that
/// is already laid out on screen (measured via its [RenderBox]) at the
/// moment this step becomes active.
class TourStep {
  const TourStep({
    required this.targetKey,
    required this.title,
    required this.description,
  });
  final GlobalKey targetKey;
  final String title;
  final String description;
}

/// A real-UI "coach mark" tour: dims and lightly blurs the actual screen
/// behind it, cuts a sharp, glowing spotlight around one REAL widget at a
/// time (never an illustration standing in for it), and walks through
/// [steps] in order. Tapping the spotlighted element itself (or the
/// "Next"/"Got it" button) advances; "Skip" exits immediately. Meant to be
/// laid directly into the same [Stack] as the screen it's touring — see
/// [HomeShell] — so the measured positions are the exact same live widgets
/// the user will actually use afterwards.
class SpotlightTourOverlay extends StatefulWidget {
  const SpotlightTourOverlay({
    super.key,
    required this.steps,
    required this.onFinish,
    required this.onSkip,
  });

  final List<TourStep> steps;
  final VoidCallback onFinish;
  final VoidCallback onSkip;

  @override
  State<SpotlightTourOverlay> createState() => _SpotlightTourOverlayState();
}

class _SpotlightTourOverlayState extends State<SpotlightTourOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rectController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  int _index = 0;
  Rect? _fromRect;
  Rect? _toRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToStep(0));
  }

  @override
  void dispose() {
    _rectController.dispose();
    super.dispose();
  }

  /// Scrolls the target into view first (several steps live inside Home's
  /// scrollable content, not just the always-visible bottom nav — a target
  /// currently off-screen must never be "spotlighted" somewhere invisible)
  /// and only then measures its real, on-screen position.
  Future<Rect?> _measure(GlobalKey key) async {
    final beforeScroll = key.currentContext;
    if (beforeScroll == null) return null;
    if (Scrollable.maybeOf(beforeScroll) != null) {
      await Scrollable.ensureVisible(
        beforeScroll,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: 0.25,
      );
    }
    // Re-read the context after the await rather than reusing the one
    // captured before it — the scroll animation is real elapsed time, so
    // this key's element could in principle have been unmounted mid-flight.
    final afterScroll = key.currentContext;
    if (afterScroll == null) return null;
    final box = afterScroll.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// First paint only — shows the very first spotlight with no travel
  /// animation (nothing to travel FROM yet), just the entrance fade below.
  Future<void> _jumpToStep(int index) async {
    final rect = await _measure(widget.steps[index].targetKey);
    if (!mounted) return;
    setState(() {
      _index = index;
      _fromRect = rect;
      _toRect = rect;
    });
    _rectController.value = 1;
  }

  Future<void> _advance() async {
    HapticFeedback.selectionClick();
    final next = _index + 1;
    if (next >= widget.steps.length) {
      widget.onFinish();
      return;
    }
    final fromRect = _currentRect();
    final newRect = await _measure(widget.steps[next].targetKey);
    if (!mounted) return;
    setState(() {
      _fromRect = fromRect;
      _toRect = newRect;
      _index = next;
    });
    _rectController
      ..value = 0
      ..forward();
  }

  Rect? _currentRect() {
    if (_fromRect == null || _toRect == null) return _toRect;
    return RectTween(
      begin: _fromRect,
      end: _toRect,
    ).evaluate(CurvedAnimation(parent: _rectController, curve: Curves.easeInOutCubic));
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_index];
    return AnimatedBuilder(
      animation: _rectController,
      builder: (context, _) {
        final rect = _currentRect();
        if (rect == null) return const SizedBox.shrink();
        final hole = rect.inflate(8);
        return Stack(
          children: [
            // Absorbs every tap on the dimmed area — the real screen
            // underneath must not respond while the tour is active.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
              ),
            ),
            // Dim + light blur, everywhere EXCEPT the spotlight hole — a
            // touch darker than before so the lit-up hole pops harder by
            // contrast, not just on its own brightness.
            Positioned.fill(
              child: ClipPath(
                clipper: _OutsideHoleClipper(hole),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ),
            // A soft white wash directly over the spotlighted area itself —
            // the real button doesn't just sit in a hole in the dark, it
            // actually looks lit, like a stage spotlight rather than a cutout.
            Positioned.fromRect(
              rect: hole,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The glowing focus ring — pulses to draw the eye, brighter and
            // thicker than a subtle outline so it reads as unmistakably "the
            // thing to look at". Uses `highlight`, not `accent`: `accent` is
            // ink (near-black) in the Mono theme — great for a button on a
            // light surface, but an invisible glow against both the dark
            // dimmed scrim AND dark targets like the balance card. `highlight`
            // is the token already defined for "accent colour on DARK
            // backgrounds" (white in Mono, lime in Lime) — exactly the
            // surface every spotlighted hole sits on.
            Positioned.fromRect(
              rect: hole,
              child:
                  IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppAccent.of(context).highlight,
                          width: 3.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppAccent.of(
                              context,
                            ).highlight.withValues(alpha: 0.85),
                            blurRadius: 30,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: AppAccent.of(
                              context,
                            ).highlight.withValues(alpha: 0.5),
                            blurRadius: 50,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ).animate(
                    onPlay: (c) => c.repeat(reverse: true),
                  ).scale(
                    duration: 900.ms,
                    curve: Curves.easeInOut,
                    begin: const Offset(1, 1),
                    end: const Offset(1.05, 1.05),
                  ),
            ),
            // Tapping the spotlighted target itself also advances — feels
            // like "tap here to continue", not just a passive highlight.
            Positioned.fromRect(
              rect: hole,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _advance,
              ),
            ),
            _TourCard(
              step: step,
              index: _index,
              count: widget.steps.length,
              onSkip: widget.onSkip,
              onNext: _advance,
            ),
          ],
        );
      },
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.index,
    required this.count,
    required this.onSkip,
    required this.onNext,
  });

  final TourStep step;
  final int index;
  final int count;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  bool get _isLast => index == count - 1;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: AppSizes.lg,
      right: AppSizes.lg,
      bottom: 150,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: Container(
          key: ValueKey(index),
          padding: const EdgeInsets.all(AppSizes.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.card,
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(step.title, style: AppText.h3)),
                  TextButton(
                    onPressed: onSkip,
                    child: Text(
                      'Skip',
                      style: AppText.bodyStrong.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                step.description,
                style: AppText.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSizes.md),
              Row(
                children: [
                  Row(
                    children: [
                      for (int i = 0; i < count; i++)
                        Container(
                          margin: const EdgeInsets.only(right: 5),
                          width: i == index ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == index
                                ? AppAccent.of(context).accent
                                : AppColors.border,
                            borderRadius: AppRadii.pill,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onNext,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.lg,
                        vertical: AppSizes.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: AppRadii.pill,
                      ),
                      child: Text(
                        _isLast ? 'Got it' : 'Next',
                        style: AppText.bodyStrong.copyWith(
                          color: AppColors.textOnDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Clips to everything EXCEPT a rounded-rect hole — used so the dim+blur
/// layer never touches the spotlighted area, keeping it sharp rather than
/// just "less dark".
class _OutsideHoleClipper extends CustomClipper<Path> {
  const _OutsideHoleClipper(this.hole);
  final Rect hole;

  @override
  Path getClip(Size size) {
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18)));
    return Path.combine(PathOperation.difference, full, holePath);
  }

  @override
  bool shouldReclip(covariant _OutsideHoleClipper oldClipper) =>
      oldClipper.hole != hole;
}
