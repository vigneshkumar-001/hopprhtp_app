import 'package:escrow/data/repositories/public_config_repository.dart';
import 'package:escrow/features/update/update_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUpdateInfo info({
    int latestBuildNumber = 16,
    bool forceUpdate = false,
    String latestVersion = '1.0.1',
  }) => AppUpdateInfo(
    latestVersion: latestVersion,
    latestBuildNumber: latestBuildNumber,
    forceUpdate: forceUpdate,
    updateMessage: '',
    storeUrl: '',
  );

  group('UpdateGate.shouldPrompt', () {
    test('regression: forceUpdate must trigger even when the installed build already equals latestBuildNumber', () {
      // The exact real-world report this guards against: admin sets
      // forceUpdate: true on the build number that's already installed
      // (e.g. to lock everyone out immediately, before a fixed build
      // exists) — this must never be silently unreachable.
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: true), 16), isTrue);
    });

    test('forceUpdate triggers even when the installed build is already newer than latestBuildNumber', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: true), 20), isTrue);
    });

    test('forceUpdate triggers for a genuinely older installed build too', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: true), 10), isTrue);
    });

    test('a non-forced nudge shows only when a genuinely newer build is available', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: false), 10), isTrue);
    });

    test('a non-forced nudge never shows when already on the latest build', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: false), 16), isFalse);
    });

    test('a non-forced nudge never shows when already ahead of the latest build', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: false), 20), isFalse);
    });

    test('never prompts when the platform is unconfigured (latestBuildNumber <= 0), even with forceUpdate true', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 0, forceUpdate: true), 16), isFalse);
    });
  });
}
