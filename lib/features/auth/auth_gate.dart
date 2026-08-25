import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import '../onboarding/onboarding_screen.dart';
import 'account_blocked_screen.dart';
import 'application/auth_controller.dart';
import 'signin_screen.dart';

/// The app's permanent root route. It:
///  • shows a splash while the session is being restored on launch,
///  • routes to [HomeShell] when authenticated, [OnboardingScreen] otherwise,
///  • bridges the authenticated user into the legacy [AppState], and
///  • resets the navigation stack to onboarding when the session ends
///    (explicit logout or a refresh-token expiry signalled by the interceptor).
///
/// Because it stays mounted as the first route, session changes are handled
/// globally — sign-in/out screens never navigate manually.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (prev, next) {
      final wasAuthed = prev?.valueOrNull?.isAuthenticated ?? false;
      final isAuthed = next.valueOrNull?.isAuthenticated ?? false;
      final user = next.valueOrNull?.user;

      // Keep the legacy dashboard state in sync with the live session.
      if (user != null) AppScope.read(context).hydrateFromApi(user);

      // Session genuinely ended (explicit sign-out, forced logout, account
      // blocked) → clear the stack and reset local state to onboarding.
      // Deliberately excludes a transition to `locked`: that's a biometric
      // re-lock on an otherwise still-valid session (see HopprApp's own
      // listener, which pushes/pops an overlay SignInScreen for that case
      // instead) — the user's place in the app must survive it, not get
      // wiped back to Home.
      final isNowLocked = next.valueOrNull?.isLocked ?? false;
      if (wasAuthed && !isAuthed && !isNowLocked) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        AppScope.read(context).signOut();
      }
    });

    final auth = ref.watch(authControllerProvider);
    return auth.maybeWhen(
      loading: () => const _SplashView(),
      orElse: () {
        final state = auth.valueOrNull;
        if (state?.isAuthenticated ?? false) return const HomeShell();
        // A biometric-protected session shows the sign-in screen, which surfaces
        // biometrics as the primary action (with PIN as the fallback).
        if (state?.isLocked ?? false) return const SignInScreen();
        // A stored session belonged to a now frozen/deleted account — explain
        // why, instead of silently dropping to onboarding.
        if (state?.isBlocked ?? false) {
          return AccountBlockedScreen(
            code: state!.blockedCode!,
            message: state.blockedMessage!,
          );
        }
        return const OnboardingScreen();
      },
    );
  }
}

class _SplashView extends ConsumerWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).valueOrNull;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(pill: true),
                SizedBox(height: AppSizes.xl),
                SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(AppColors.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          if (version != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSizes.xl,
              child: Center(
                child: Text(
                  version,
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
