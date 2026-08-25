// Smoke tests for the Hoppr escrow app under the real (backend-wired) auth flow.
// The session layer is faked via provider overrides so no network is needed.

import 'package:escrow/app.dart';
import 'package:escrow/core/network/connectivity.dart';
import 'package:escrow/core/providers.dart';
import 'package:escrow/data/app_state.dart';
import 'package:escrow/features/auth/application/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

Widget _app({FakeTokenStore? tokens, FakeAuthRepository? repo}) {
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokens ?? FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(repo ?? FakeAuthRepository()),
      biometricServiceProvider.overrideWithValue(FakeBiometricService()),
      // Avoid the connectivity_plus platform channel in tests.
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      // The home bell reads this; keep tests off the network.
      unreadNotificationsProvider.overrideWith((ref) => Future.value(0)),
    ],
    child: const HopprApp(),
  );
}

void main() {
  testWidgets('no session → onboarding, and can open sign up',
      (WidgetTester tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
  });

  testWidgets('restored session → routes past onboarding to the dashboard',
      (WidgetTester tester) async {
    final tokens = FakeTokenStore(access: 'a', refresh: 'r');
    await tester.pumpWidget(_app(tokens: tokens));
    await tester.pumpAndSettle();

    // AuthGate validated the token via /users/me and showed HomeShell.
    expect(find.text('Get started'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dead session discovered on biometric unlock clears the stack back to sign-in',
      (WidgetTester tester) async {
    final tokens = FakeTokenStore(access: 'a', refresh: 'r');
    final repo = FakeAuthRepository();
    final biometrics = FakeBiometricService();

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(repo),
        biometricServiceProvider.overrideWithValue(biometrics),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        unreadNotificationsProvider.overrideWith((ref) => Future.value(0)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const HopprApp()),
    );
    await tester.pumpAndSettle();

    // Cold boot with biometrics off resolves straight to the dashboard.
    expect(find.text('Get started'), findsNothing);

    // App backgrounds with biometric unlock now on, and — while it was away —
    // the server rejects the stored token (revoked/expired). This is the
    // exact real-world report: biometric prompt succeeds locally, but the
    // session underneath is dead.
    biometrics.enabled = true;
    repo.failMe = true;
    await container.read(authControllerProvider.notifier).relockIfBiometricEnabled();
    await tester.pumpAndSettle();

    // Must not get stuck on the pushed lock screen — it should clear the
    // whole stack and land back on sign-in/onboarding.
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('selected theme persists across launches',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'hoppr.limeTheme': true});
    final prefs = await SharedPreferences.getInstance();

    final state = AppState(prefs: prefs);
    expect(state.limeTheme, isTrue, reason: 'restored from storage');

    state.setLimeTheme(false);
    expect(prefs.getBool('hoppr.limeTheme'), isFalse);
  });
}
