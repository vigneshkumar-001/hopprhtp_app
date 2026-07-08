import 'package:flutter/material.dart';
import '../theme/app_sizes.dart';

/// A lightweight "shared axis" style transition (fade-through + small slide).
///
/// Used as the common transition for *every* route so navigation feels uniform
/// and smooth without pulling in extra packages. Kept cheap (opacity + a tiny
/// translate) so it stays buttery even on low-end devices.
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SharedAxis(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _SharedAxis extends StatelessWidget {
  const _SharedAxis({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Incoming page: fade in + slide from the right a touch.
    final inCurve = CurvedAnimation(
      parent: animation,
      curve: AppDurations.emphasized,
      reverseCurve: AppDurations.easeOut,
    );
    // Outgoing page: fade out + slide left a touch.
    final outCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppDurations.easeOut,
    );

    return FadeTransition(
      opacity: inCurve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(inCurve),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.04, 0),
          ).animate(outCurve),
          child: child,
        ),
      ),
    );
  }
}

/// Convenience navigation helpers that always use the shared transition and the
/// app's page duration.
class AppNav {
  AppNav._();

  static Route<T> route<T>(Widget page, {RouteSettings? settings}) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: AppDurations.page,
      reverseTransitionDuration: AppDurations.normal,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (context, animation, secondary, child) => _SharedAxis(
        animation: animation,
        secondaryAnimation: secondary,
        child: child,
      ),
    );
  }

  static Future<T?> push<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(route<T>(page));
  }

  /// Replace the whole stack — used for auth → home and log out.
  static Future<T?> replaceAll<T>(BuildContext context, Widget page) {
    return Navigator.of(
      context,
    ).pushAndRemoveUntil<T>(route<T>(page), (r) => false);
  }

  /// Push [page], removing every route above the first (e.g. Home) so back
  /// navigation from it goes straight to Home instead of back through
  /// whatever flow led here. Used after a terminal step (e.g. delivery
  /// confirmation) whose intermediate screens should never be reachable again.
  static Future<T?> pushAndClearToFirst<T>(BuildContext context, Widget page) {
    return Navigator.of(
      context,
    ).pushAndRemoveUntil<T>(route<T>(page), (r) => r.isFirst);
  }
}
