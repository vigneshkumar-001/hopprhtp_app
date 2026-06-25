import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../data/app_state.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import '../onboarding/onboarding_screen.dart';
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

      // Session ended → clear the stack and reset local state to onboarding.
      if (wasAuthed && !isAuthed) {
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
        return const OnboardingScreen();
      },
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
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
    );
  }
}
