// A hung native authenticate() call must not leave callers waiting forever
// — see BiometricService.authenticate's doc comment for why this can
// genuinely happen on-device (a known local_auth/stickyAuth interaction).

import 'dart:async';

import 'package:escrow/core/auth/biometric_service.dart';
import 'package:fake_async/fake_async.dart';
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

void main() {
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
}
