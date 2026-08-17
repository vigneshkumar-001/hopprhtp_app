import 'package:firebase_auth/firebase_auth.dart';

/// Friendly failure categories for the phone-verification screen — mirrors
/// this app's other OTP flows' error handling rather than surfacing raw
/// Firebase SDK error codes/messages.
enum PhoneAuthFailure { invalidPhone, invalidCode, timeout, unknown }

class PhoneAuthException implements Exception {
  const PhoneAuthException(this.failure, this.message);
  final PhoneAuthFailure failure;
  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper around `FirebaseAuth`'s phone-verification flow, scoped to
/// exactly what this app needs: obtain a Firebase ID token that proves the
/// user controls a phone number, then hand it to the backend once and
/// discard it. This is an ADDITIONAL, optional trust signal — never a
/// replacement for the app's own JWT session (see AuthRepository/TokenStore),
/// which stays authoritative throughout.
///
/// Firebase's own client-side sign-in (`signInWithCredential`) is used only
/// as the mechanism to mint that ID token — this service always signs back
/// out of Firebase immediately after reading the token, so a stray Firebase
/// session can never linger or be confused with this app's real session.
class FirebasePhoneAuthService {
  FirebasePhoneAuthService([FirebaseAuth? auth])
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  String? _verificationId;
  int? _resendToken;

  /// Starts (or resends) phone verification for [phoneNumber] (E.164, e.g.
  /// "+2347871223400"). [onCodeSent] fires once Firebase has dispatched (or,
  /// for a Firebase Console test number, simulated) the SMS code — pass its
  /// cooldown hint straight to the resend-cooldown timer. [onAutoVerified]
  /// fires only on Android's silent SMS auto-retrieval path; most users will
  /// still type the code manually via [confirmCode].
  Future<void> startVerification({
    required String phoneNumber,
    required void Function(int resendCooldownSeconds) onCodeSent,
    required void Function(PhoneAuthException error) onError,
    void Function(String idToken)? onAutoVerified,
    bool isResend = false,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: isResend ? _resendToken : null,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (onAutoVerified == null) return;
          try {
            final result = await _auth.signInWithCredential(credential);
            final idToken = await result.user?.getIdToken();
            await _auth.signOut();
            if (idToken != null) onAutoVerified(idToken);
          } catch (_) {
            // Auto-verification is a convenience only — the user can still
            // type the code manually if this silently fails.
          }
        },
        verificationFailed: (FirebaseAuthException e) => onError(_map(e)),
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          onCodeSent(60);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } on FirebaseAuthException catch (e) {
      onError(_map(e));
    }
  }

  /// Confirms the 6-digit code the user typed and returns a fresh Firebase ID
  /// token. Throws [PhoneAuthException] on a wrong/expired code or if
  /// [startVerification] was never called / has timed out.
  Future<String> confirmCode(String smsCode) async {
    final verificationId = _verificationId;
    if (verificationId == null) {
      throw const PhoneAuthException(
        PhoneAuthFailure.timeout,
        'Verification timed out. Please try again.',
      );
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final result = await _auth.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();
      if (idToken == null) {
        throw const PhoneAuthException(
          PhoneAuthFailure.unknown,
          'Unable to verify phone right now.',
        );
      }
      return idToken;
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    } finally {
      await _auth.signOut();
    }
  }

  PhoneAuthException _map(FirebaseAuthException e) => switch (e.code) {
    'invalid-phone-number' => const PhoneAuthException(
      PhoneAuthFailure.invalidPhone,
      'Invalid phone number.',
    ),
    'invalid-verification-code' ||
    'invalid-verification-id' => const PhoneAuthException(
      PhoneAuthFailure.invalidCode,
      'Verification code is incorrect.',
    ),
    'session-expired' ||
    'credential-already-in-use' => const PhoneAuthException(
      PhoneAuthFailure.timeout,
      'Verification timed out. Please try again.',
    ),
    'too-many-requests' => const PhoneAuthException(
      PhoneAuthFailure.unknown,
      'Too many attempts. Please try again later.',
    ),
    // The most common real cause of an otherwise-unlabelled Firebase failure
    // is a mismatched country code + number (e.g. an Indian number sent with
    // Nigeria's +234 still "looks" like a phone number to Firebase, so it
    // never surfaces as invalid-phone-number — it just fails later, deep in
    // the verification pipeline). Naming that guess beats a bare "try again".
    _ => const PhoneAuthException(
      PhoneAuthFailure.unknown,
      "We couldn't verify that number. Double-check the country code "
      'matches your number, then try again.',
    ),
  };
}
