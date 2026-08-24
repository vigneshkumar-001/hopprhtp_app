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
    test('regression: forceUpdate must NOT trigger when the installed build already matches latestBuildNumber', () {
      // The exact real-world requirement this guards against: an admin sets
      // forceUpdate: true on the build number that's already installed —
      // there is nothing to update to, so the sheet must stay hidden even
      // with Force Update switched on.
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: true), 16), isFalse);
    });

    test('forceUpdate must NOT trigger when the installed build is already newer than latestBuildNumber', () {
      expect(UpdateGate.shouldPrompt(info(latestBuildNumber: 16, forceUpdate: true), 20), isFalse);
    });

    test('forceUpdate triggers for a genuinely older installed build', () {
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
