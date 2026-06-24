// Smoke tests for the Hoppr escrow app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:escrow/app.dart';
import 'package:escrow/data/app_state.dart';

void main() {
  testWidgets('Onboarding renders and can navigate to sign up',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HopprApp());
    await tester.pumpAndSettle();

    // Onboarding headline + primary CTA are present.
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);

    // Tapping "Get started" opens the sign-up flow.
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
  });

  testWidgets('Sign in flow lands on the home dashboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HopprApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '08012345678');
    // Completing the 4-digit PIN auto-submits and navigates to Home.
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pumpAndSettle();

    expect(find.text('Create Protected Transaction'), findsOneWidget);
  });

  testWidgets('Lime theme toggle works from Profile',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HopprApp());
    await tester.pumpAndSettle();

    // Sign in.
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '08012345678');
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.pumpAndSettle();

    // Open the "More" (profile) tab and switch to the Lime theme.
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Lime'));
    await tester.pumpAndSettle();

    // App still renders cleanly under the new theme.
    expect(find.text('Appearance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selected theme persists across launches',
      (WidgetTester tester) async {
    // Simulate a previous launch that saved the Lime theme.
    SharedPreferences.setMockInitialValues({'hoppr.limeTheme': true});
    final prefs = await SharedPreferences.getInstance();

    final state = AppState(prefs: prefs);
    expect(state.limeTheme, isTrue, reason: 'restored from storage');

    // Changing it writes back to storage for next time.
    state.setLimeTheme(false);
    expect(prefs.getBool('hoppr.limeTheme'), isFalse);
  });
}
