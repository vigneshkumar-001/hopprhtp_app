// Smoke tests for the Hoppr escrow app under the real (backend-wired) auth flow.
// The session layer is faked via provider overrides so no network is needed.

import 'package:escrow/app.dart';
import 'package:escrow/core/network/connectivity.dart';
import 'package:escrow/core/network/socket_service.dart';
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
      // Avoid a real socket_io_client connection (real Timers) — HopprApp
      // connects/disconnects on every auth transition.
      socketServiceProvider.overrideWithValue(FakeSocketService()),
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
        socketServiceProvider.overrideWithValue(FakeSocketService()),
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

  testWidgets(
      'successful relock/unlock returns to the exact same screen, not the stack root',
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
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const HopprApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsNothing);

    // Simulate the user being a couple of screens deep, not sitting at Home.
    final homeContext = tester.element(find.byType(Scaffold).first);
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Deep screen marker')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Deep screen marker'), findsOneWidget);

    // App backgrounds with biometric unlock on, comes back, and this time the
    // stored session is still perfectly valid (repo.failMe stays false) — a
    // routine, successful unlock.
    biometrics.enabled = true;
    await container.read(authControllerProvider.notifier).relockIfBiometricEnabled();
    await tester.pumpAndSettle();

    // Must land back on the exact screen the person was on — not get bounced
    // to the navigation stack's root the instant the unlock attempt starts
    // (a bug where the cleanup fired on the transient "still checking"
    // loading tick instead of waiting for the real outcome).
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Deep screen marker'), findsOneWidget);
  });

  testWidgets(
      're-lock overlay looks like the sign-in screen, not a bare "Locked" placeholder',
      (WidgetTester tester) async {
    final tokens = FakeTokenStore(access: 'a', refresh: 'r');
    final repo = FakeAuthRepository();
    // Never resolves — freezes the overlay in the "still waiting on the OS
    // biometric sheet" state so it can be inspected.
    final biometrics = HangingBiometricService();

    final container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(repo),
        biometricServiceProvider.overrideWithValue(biometrics),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        unreadNotificationsProvider.overrideWith((ref) => Future.value(0)),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const HopprApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsNothing);

    await container.read(authControllerProvider.notifier).relockIfBiometricEnabled();
    await tester.pumpAndSettle();

    // The old dedicated lock screen showed only a bare "Locked" placeholder
    // with an icon and two buttons. It's gone — the same branded sign-in
    // screen used for a cold-boot session now covers this too, complete
    // with its own phone/PIN fields as a fallback, not just a lone button.
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Unlock with biometrics'), findsOneWidget);
    // Label + hint both read "Phone number" by design (see AppTextField) —
    // findsWidgets just confirms the field itself is there, not a count.
    expect(find.text('Phone number'), findsWidgets);
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
