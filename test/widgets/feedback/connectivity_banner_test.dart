// The banner is the "real world app" always-visible offline indicator
// (WhatsApp/Instagram-style) — these tests drive connectivityProvider
// directly to prove it actually reacts, not just that it compiles.
//
// The banner widget stays mounted at all times (it animates opacity/slide
// rather than being added/removed), so presence-based finders can't tell
// "visible" from "animated out" — these tests read the target
// opacity/offset the implicit animation widgets were just told to reach
// instead.

import 'dart:async';

import 'package:escrow/core/network/connectivity.dart';
import 'package:escrow/widgets/feedback/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double opacityOf(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  Offset offsetOf(WidgetTester tester) =>
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;

  testWidgets(
      'slides in and becomes opaque while offline, slides away and fades '
      'once back online', (WidgetTester tester) async {
    final controller = StreamController<bool>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectivityProvider.overrideWith((ref) => controller.stream)],
        child: const MaterialApp(
          home: Scaffold(body: ConnectivityBanner()),
        ),
      ),
    );

    // Before the stream's first emission, valueOrNull is null — the banner
    // treats that as online (see its own doc comment), same optimistic
    // default ConnectivityRef.isOnline uses elsewhere.
    await tester.pump();
    expect(opacityOf(tester), 0.0);
    expect(offsetOf(tester), const Offset(0, -1));
    expect(find.text('No internet connection'), findsOneWidget);

    controller.add(false);
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1.0);
    expect(offsetOf(tester), Offset.zero);

    controller.add(true);
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 0.0);
    expect(offsetOf(tester), const Offset(0, -1));
  });
}
