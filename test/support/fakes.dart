import 'dart:async';

import 'package:escrow/core/auth/biometric_service.dart';
import 'package:escrow/core/network/api_exception.dart';
import 'package:escrow/core/network/socket_service.dart';
import 'package:escrow/core/storage/token_store.dart';
import 'package:escrow/data/dto/auth_dto.dart';
import 'package:escrow/data/dto/user_dto.dart';
import 'package:escrow/data/repositories/auth_repository.dart';

/// A canned authenticated user used across tests. Not `const` — [DateTime]
/// has no const constructor, and [tutorialSeenAt] needs a real one so this
/// fixture reads as an already-onboarded existing user by default (matching
/// what most tests actually want: reaching Home without the onboarding
/// tutorial popping up uninvited). A test that specifically wants a
/// brand-new, never-onboarded user should build its own `ApiUser` with
/// `tutorialSeenAt: null` instead of reusing this one.
final kTestUser = ApiUser(
  id: 'u1',
  fullName: 'Amara Okafor',
  phone: '+2348000000000',
  email: null,
  trustScore: 600,
  trustCategory: 'Fair',
  deals: 0,
  disputes: 0,
  verified: false,
  identityStatus: 'unverified',
  escrowBalanceKobo: 0,
  walletAvailableKobo: 0,
  walletCoolingKobo: 0,
  tutorialSeenAt: DateTime.utc(2020, 1, 1),
);

/// In-memory token store — no platform secure-storage channel in tests. Pass
/// [access]/[refresh] to simulate a previously-signed-in session.
class FakeTokenStore implements TokenStore {
  FakeTokenStore({String? access, String? refresh}) : _a = access, _r = refresh;

  String? _a;
  String? _r;

  @override
  String? get accessToken => _a;
  @override
  String? get refreshToken => _r;
  @override
  bool get hasSession => _r != null;
  @override
  Future<void> ensureLoaded() async {}
  @override
  Future<void> save({required String access, required String refresh}) async {
    _a = access;
    _r = refresh;
  }

  @override
  Future<void> clear() async {
    _a = null;
    _r = null;
  }
}

/// Configurable fake of the auth API. Set [failLogin] to simulate bad creds,
/// or [failMe] to simulate a stored session the backend no longer accepts
/// (e.g. a token revoked/expired while the app was backgrounded).
class FakeAuthRepository implements AuthRepository {
  bool failLogin = false;
  bool failMe = false;

  /// When set, me() waits on this before resolving/throwing — lets a test
  /// prove something did (or deliberately didn't) block on it finishing.
  Completer<void>? meGate;

  /// Overrides what `me()` returns — defaults to [kTestUser] (an
  /// already-onboarded existing user). Set this to a user with
  /// `tutorialSeenAt: null` to test the brand-new-signup path (the
  /// onboarding tour) without changing the shared default fixture every
  /// other test relies on staying "already seen".
  ApiUser? meOverride;

  @override
  Future<AuthSession> login({
    required String identifier,
    required String pin,
  }) async {
    if (failLogin) {
      throw ApiException(
        code: 'UNAUTHORIZED',
        message: 'Invalid credentials',
        statusCode: 401,
      );
    }
    return AuthSession(user: kTestUser, accessToken: 'a', refreshToken: 'r');
  }

  @override
  Future<ApiUser> me() async {
    final gate = meGate;
    if (gate != null) await gate.future;
    if (failMe) {
      throw ApiException(
        code: 'UNAUTHORIZED',
        message: 'Authentication required',
        statusCode: 401,
      );
    }
    return meOverride ?? kTestUser;
  }

  @override
  Future<ApiUser> updateProfile(Map<String, dynamic> body) async => kTestUser;

  @override
  Future<ApiUser> markTutorialSeen() async => kTestUser;

  @override
  Future<void> updateFcmToken({
    required String fcmToken,
    String? platform,
  }) async {}

  @override
  Future<ApiUser> submitIdentity({
    required List<KycDocumentPayload> documents,
    required String selfieUrl,
  }) async => kTestUser;

  @override
  Future<ApiUser> verifyPhoneWithFirebase({required String idToken}) async =>
      kTestUser;

  @override
  Future<void> deleteAccount({required String pin}) async {}

  @override
  Future<bool> isPhoneAvailable(String phone) async => true;

  @override
  Future<ApiUser> addPayoutAccount({
    required String bank,
    required String accountNumber,
    required String accountName,
    bool makeDefault = false,
  }) async => kTestUser;

  @override
  Future<ApiUser> updatePayoutAccount(
    String accountId, {
    String? bank,
    String? accountNumber,
    String? accountName,
  }) async => kTestUser;

  @override
  Future<ApiUser> removePayoutAccount(String accountId) async => kTestUser;

  @override
  Future<ApiUser> setDefaultPayoutAccount(String accountId) async => kTestUser;

  @override
  Future<AuthSession> confirmRegisterWithFirebase({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    required String pin,
    required String firebaseIdToken,
  }) async => AuthSession(user: kTestUser, accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logoutAll() async {}

  @override
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {}

  @override
  Future<void> verifyPin({required String pin}) async {}

  @override
  Future<void> confirmPinResetWithFirebase({
    required String firebaseIdToken,
    required String newPin,
  }) async {}
}

/// Biometrics off + unavailable by default — keeps tests deterministic and the
/// session unlocked.
class FakeBiometricService implements BiometricService {
  bool enabled = false;
  bool available = false;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async => enabled = value;
  @override
  Future<bool> authenticate(String reason) async => true;
}

/// Never resolves — freezes the caller mid-prompt, for asserting what's on
/// screen while a biometric decision is still pending (the OS sheet is up).
class HangingBiometricService implements BiometricService {
  bool enabled = true;
  bool available = true;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<void> setEnabled(bool value) async => enabled = value;
  @override
  Future<bool> authenticate(String reason) => Completer<bool>().future;
}

/// A no-op socket — avoids opening a real socket_io_client connection (which
/// schedules real reconnection-backoff Timers) in widget tests that only
/// care about auth/navigation state, not realtime delivery. HopprApp calls
/// connect()/disconnect() on every auth-state transition, so any test that
/// crosses the authenticated boundary more than once (e.g. login, then
/// relock, then unlock again) needs this override or it leaks a pending
/// Timer that fails the test on teardown.
class FakeSocketService extends SocketService {
  FakeSocketService() : super(FakeTokenStore());

  @override
  void connect() {}

  @override
  void disconnect() {}

  @override
  void ensureConnected() {}
}
