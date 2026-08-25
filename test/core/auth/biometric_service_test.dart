// A hung native authenticate() call must not leave callers waiting forever
// — see BiometricService.authenticate's doc comment for why this can
// genuinely happen on-device (a known local_auth/stickyAuth interaction).

import 'dart:async';

import 'package:escrow/core/auth/biometric_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:local_auth_windows/local_auth_windows.dart';

/// Simulates the native plugin call that never resolves — no result, no
/// error, exactly the failure mode a hung authenticate() has in the wild.
class _HangingLocalAuth extends LocalAuthentication {
  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[
      IOSAuthMessages(),
      AndroidAuthMessages(),
      WindowsAuthMessages(),
    ],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) {
    return Completer<bool>().future;
  }
}

/// Resolves immediately with a fixed result — for asserting what happens
/// once an outcome (not a hang) is known.
class _ScriptedLocalAuth extends LocalAuthentication {
  _ScriptedLocalAuth(this.result);
  final bool result;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const <AuthMessages>[
      IOSAuthMessages(),
      AndroidAuthMessages(),
      WindowsAuthMessages(),
    ],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async => result;
}

void main() {
  // authenticate() now fires HapticFeedback on the result, which needs a
  // real platform-channel binding — without this, the plain `test()` below
  // has none and HapticFeedback throws "Binding has not yet been
  // initialized."
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'authenticate() resolves to false instead of hanging forever when the '
      'native call never completes', () {
    fakeAsync((async) {
      final service = BiometricService(auth: _HangingLocalAuth());

      bool? result;
      unawaited(service.authenticate('Unlock Hoppr').then((r) => result = r));

      async.elapse(const Duration(seconds: 24));
      expect(result, isNull, reason: 'still within the timeout window');

      async.elapse(const Duration(seconds: 2));
      expect(result, isFalse, reason: 'timed out and resolved to false');
    });
  });

  test(
      'authenticate() fires a distinct haptic pattern for a match vs a miss',
      () async {
    final calls = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String?);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final matched = await BiometricService(
      auth: _ScriptedLocalAuth(true),
    ).authenticate('Unlock Hoppr');
    final missed = await BiometricService(
      auth: _ScriptedLocalAuth(false),
    ).authenticate('Unlock Hoppr');

    expect(matched, isTrue);
    expect(missed, isFalse);
    expect(calls, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });
}
