import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/utils/formatters.dart';

export 'package:flutter_animate/flutter_animate.dart';

/// Shared animation tokens so every motion in the app feels consistent.
class Motion {
  Motion._();

  static const Duration enter = Duration(milliseconds: 360);
  static const Duration quick = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
  static const Curve pop = Curves.easeOutBack;

  /// Stagger gap between successive list items.
  static const Duration stagger = Duration(milliseconds: 55);
}

/// Reusable entrance effects for single widgets and (staggered) lists.
extension AppEntrance on Widget {
  /// Fade + gentle slide-up. Use for hero blocks / section headers.
  Widget enter({Duration delay = Duration.zero, double dy = 0.08}) {
    return animate()
        .fadeIn(duration: Motion.enter, delay: delay, curve: Motion.curve)
        .slideY(
            begin: dy,
            end: 0,
            duration: Motion.enter,
            delay: delay,
            curve: Motion.curve);
  }

  /// Scale + fade "pop" — for success icons / badges.
  Widget popIn({Duration delay = Duration.zero}) {
    return animate()
        .fadeIn(duration: Motion.quick, delay: delay)
        .scaleXY(
            begin: 0.6,
            end: 1,
            duration: const Duration(milliseconds: 520),
            delay: delay,
            curve: Motion.pop);
  }
}

/// Staggered entrance for a list of children (used as Column/ListView children).
extension AppStagger on List<Widget> {
  List<Widget> staggerEnter({double dy = 0.1}) {
    return animate(interval: Motion.stagger)
        .fadeIn(duration: Motion.enter, curve: Motion.curve)
        .slideY(begin: dy, end: 0, duration: Motion.enter, curve: Motion.curve);
  }
}

/// A money figure that counts up from zero on first build.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(
    this.value, {
    super.key,
    this.style,
    this.symbol = true,
    this.duration = const Duration(milliseconds: 850),
  });

  final double value;
  final TextStyle? style;
  final bool symbol;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) =>
          Text(Money.format(v, symbol: symbol), style: style),
    );
  }
}
