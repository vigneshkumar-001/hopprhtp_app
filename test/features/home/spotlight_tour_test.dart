// The onboarding spotlight tour — shown once for a brand-new account
// (tutorialSeenAt null), never for kTestUser (already-seen by default, see
// fakes.dart). Exercises the real HomeShell/bottom-nav measurement path,
// not a mock — this is the scenario no other widget test covers, since
// every other test deliberately uses the already-seen kTestUser fixture.
//
// Bounded `pump()` calls throughout, never `pumpAndSettle()` — the
// spotlight ring's glow pulse repeats forever by design (so it keeps
// drawing attention the whole time a step is shown), which pumpAndSettle
// would never consider "settled".

import 'package:escrow/app.dart';
import 'package:escrow/core/network/connectivity.dart';
import 'package:escrow/core/network/socket_service.dart';
import 'package:escrow/core/providers.dart';
import 'package:escrow/data/dto/user_dto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

final _newUser = ApiUser(
  id: 'u2',
  fullName: 'New Signup',
  phone: '+2348000000001',
  trustScore: 600,
  trustCategory: 'Fair',
  deals: 0,
  disputes: 0,
  verified: false,
  identityStatus: 'unverified',
  escrowBalanceKobo: 0,
  walletAvailableKobo: 0,
  walletCoolingKobo: 0,
  // The one thing that matters for this test — never seen the tour yet.
  tutorialSeenAt: null,
);

Future<void> _pumpNewUserToTour(WidgetTester tester) async {
  final repo = FakeAuthRepository()..meOverride = _newUser;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(
          FakeTokenStore(access: 'a', refresh: 'r'),
        ),
        authRepositoryProvider.overrideWithValue(repo),
        biometricServiceProvider.overrideWithValue(FakeBiometricService()),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        unreadNotificationsProvider.overrideWith((ref) => Future.value(0)),
        socketServiceProvider.overrideWithValue(FakeSocketService()),
      ],
      child: const HopprApp(),
    ),
  );
  // Carries through the 1200ms post-auth-check timer, then the tour
  // overlay's own post-frame measurement callback for the first step.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets(
    'a brand-new account sees the spotlight tour on Home; Skip dismisses it',
    (WidgetTester tester) async {
      await _pumpNewUserToTour(tester);

      expect(
        find.text('Protected in Escrow'),
        findsOneWidget,
      ); // tour card title
      expect(find.text('Skip'), findsOneWidget);
      expect(
        find.textContaining('money kept safe until each deal is complete'),
        findsOneWidget,
      );

      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Skip'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping Next walks through every step, ending back on real Home',
    (WidgetTester tester) async {
      await _pumpNewUserToTour(tester);

      // Balance card -> Active -> Cooling -> Trust Score -> Notifications ->
      // Create -> Enter Code -> Initiation -> Transit -> More -> "Got it"
      // (10 taps; some steps live inside Home's scrollable content, so each
      // pump also has to carry a real scroll-into-view animation, not just
      // the spotlight's own rect travel).
      for (final label in [
        'Next',
        'Next',
        'Next',
        'Next',
        'Next',
        'Next',
        'Next',
        'Next',
        'Next',
        'Got it',
      ]) {
        // find.text(...).first — the outgoing and incoming tour cards are
        // BOTH briefly mounted during the crossfade (AnimatedSwitcher), so
        // right after a tap there can legitimately be two "Next" widgets on
        // screen at once; a real single touch just hits whichever is on
        // top, but the test API needs an unambiguous target.
        await tester.tap(find.text(label).first);
        await tester.pump(); // step change
        // Comfortably covers the slowest step: scroll-into-view (~280ms) +
        // the card's own crossfade (~260ms), which run one after the other,
        // not simultaneously (the crossfade only starts once the async
        // measure/scroll resolves and setState runs).
        await tester.pump(const Duration(milliseconds: 700));
      }

      expect(find.text('Skip'), findsNothing);
      expect(find.text('Got it'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
