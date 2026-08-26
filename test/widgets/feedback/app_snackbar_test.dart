// AppSnackbar.error's autoRetryOnReconnect is the mechanism behind "the app
// should recover automatically once WiFi/data comes back".
//
// The actual offline->online decision (isReconnectTransition) is tested
// directly here as a pure function — no widget, SnackBar, or stream
// involved — specifically because a SnackBar carries its own real internal
// auto-dismiss Timer, and driving that through full widget pumps in every
// "must NOT fire" scenario turned out to hang the test runner for the
// full default 10-minute budget (neither pumpAndSettle() nor bounded
// tester.pump() calls nor a @Timeout override stopped it). One widget test
// below exercises the full integration for the case that IS safe to fully
// settle: the fired retry explicitly closes the snackbar itself, so
// nothing is left waiting on that Timer.

import 'dart:async';

import 'package:escrow/core/network/connectivity.dart';
import 'package:escrow/widgets/feedback/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isReconnectTransition — the decision behind auto-retry firing', () {
    test('offline -> online is a reconnect', () {
      expect(
        isReconnectTransition(
          const AsyncData(false),
          const AsyncData(true),
        ),
        isTrue,
      );
    });

    test('already online -> still online is not a transition', () {
      expect(
        isReconnectTransition(
          const AsyncData(true),
          const AsyncData(true),
        ),
        isFalse,
        reason: 'nothing changed — must not fire again for the same state',
      );
    });

    test('still offline -> still offline is not a transition', () {
      expect(
        isReconnectTransition(
          const AsyncData(false),
          const AsyncData(false),
        ),
        isFalse,
      );
    });

    test('online -> offline is not a reconnect (the opposite direction)', () {
      expect(
        isReconnectTransition(
          const AsyncData(true),
          const AsyncData(false),
        ),
        isFalse,
      );
    });

    test('no previous reading (cold start) is never treated as a reconnect', () {
      expect(
        isReconnectTransition(null, const AsyncData(true)),
        isFalse,
        reason: "there's nothing to have transitioned FROM yet",
      );
    });

    test('a loading previous state is not treated as "was offline"', () {
      expect(
        isReconnectTransition(
          const AsyncLoading<bool>(),
          const AsyncData(true),
        ),
        isFalse,
      );
    });

    test('a loading next state is not treated as "now online"', () {
      expect(
        isReconnectTransition(
          const AsyncData(false),
          const AsyncLoading<bool>(),
        ),
        isFalse,
        reason: 'no confirmed online reading yet — nothing to act on',
      );
    });
  });

  testWidgets(
      'autoRetryOnReconnect: true fires onRetry the moment connectivity '
      'goes offline -> online, and dismisses the stale snackbar',
      (WidgetTester tester) async {
    final controller = StreamController<bool>();
    addTearDown(controller.close);
    var retries = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectivityProvider.overrideWith((ref) => controller.stream)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AppSnackbar.error(
                  context,
                  "Can't reach our servers right now.",
                  onRetry: () => retries++,
                  autoRetryOnReconnect: true,
                ),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ),
    );

    controller.add(false); // offline
    await tester.pump();

    await tester.tap(find.text('trigger'));
    await tester.pump();
    expect(find.text("Can't reach our servers right now."), findsOneWidget);
    expect(retries, 0, reason: 'still offline — must not fire yet');

    controller.add(true); // reconnect
    // Safe to fully settle here — the fired retry explicitly closes the
    // snackbar (AppSnackbar._retryOnReconnect), so nothing is left relying
    // on the SnackBar's own real dismiss Timer.
    await tester.pumpAndSettle();

    expect(retries, 1);
    expect(
      find.text("Can't reach our servers right now."),
      findsNothing,
      reason: 'the stale offline error should be dismissed once retried',
    );
  });
}
