import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/biometric_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/error_messages.dart';
import '../../../core/providers.dart';
import '../../../data/dto/user_dto.dart';
import '../../../data/repositories/auth_repository.dart';

enum AuthStatus { unauthenticated, locked, authenticated, blocked }

/// Immutable session snapshot exposed to the UI.
class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.blockedCode,
    this.blockedMessage,
  });

  const AuthState.unauthenticated()
    : status = AuthStatus.unauthenticated,
      user = null,
      blockedCode = null,
      blockedMessage = null;

  /// A stored session exists but is gated behind a biometric unlock.
  const AuthState.locked()
    : status = AuthStatus.locked,
      user = null,
      blockedCode = null,
      blockedMessage = null;

  const AuthState.authenticated(ApiUser this.user)
    : status = AuthStatus.authenticated,
      blockedCode = null,
      blockedMessage = null;

  /// The account was frozen or deleted server-side (an admin action) —
  /// discovered while restoring a stored session. The session is already
  /// dead (tokens cleared by the caller); this just carries what to tell
  /// the person before they land back on sign-in. See [AccountBlockedScreen].
  const AuthState.blocked({required String code, required String message})
    : status = AuthStatus.blocked,
      user = null,
      blockedCode = code,
      blockedMessage = message;

  final AuthStatus status;
  final ApiUser? user;

  /// 'ACCOUNT_SUSPENDED' | 'ACCOUNT_DELETED', set only when [status] is
  /// [AuthStatus.blocked].
  final String? blockedCode;

  /// The backend's human-friendly explanation, set only when [status] is
  /// [AuthStatus.blocked].
  final String? blockedMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLocked => status == AuthStatus.locked;
  bool get isBlocked => status == AuthStatus.blocked;
}

/// Error codes the backend returns (403) when an account is frozen or
/// soft-deleted — checked wherever a stored session is restored or a login
/// attempt fails, so the person sees a clear, branded explanation instead of
/// a silent logout or a generic error.
const _accountSuspendedCode = 'ACCOUNT_SUSPENDED';
const _accountDeletedCode = 'ACCOUNT_DELETED';

/// True for the two account-blocked error codes above.
bool isAccountBlockedCode(String code) =>
    code == _accountSuspendedCode || code == _accountDeletedCode;

/// Owns the session lifecycle: restores it on launch, runs sign-in / sign-up,
/// and reacts to the interceptor signalling an expired refresh token.
///
/// Watch `authControllerProvider` for the `AsyncValue<AuthState>` (loading while
/// bootstrapping); read `.notifier` to call the actions.
class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);
  BiometricService get _biometrics => ref.read(biometricServiceProvider);

  @override
  Future<AuthState> build() async {
    await _tokens.ensureLoaded();
    if (!_tokens.hasSession) return const AuthState.unauthenticated();
    // A session the user protected with biometrics stays locked until they pass
    // the prompt (see [unlock]).
    if (await _biometrics.isEnabled()) return const AuthState.locked();
    return _loadSession();
  }

  /// Loads the profile for a stored session; clears + logs out if invalid.
  /// A frozen/deleted account surfaces as [AuthState.blocked] with the
  /// backend's explanation rather than silently dropping to sign-in — every
  /// other failure (expired session, offline) keeps the previous silent
  /// behaviour.
  Future<AuthState> _loadSession() async {
    try {
      final user = await _repo.me();
      return AuthState.authenticated(user);
    } on ApiException catch (e) {
      await _tokens.clear();
      if (isAccountBlockedCode(e.code)) {
        return AuthState.blocked(code: e.code, message: e.userMessage);
      }
      return const AuthState.unauthenticated();
    }
  }

  /// Dismiss the [AuthStatus.blocked] screen and return to sign-in. The
  /// session is already cleared (see [_loadSession]) — this only resets the
  /// in-memory state that's keeping [AccountBlockedScreen] on screen.
  void acknowledgeBlocked() {
    state = const AsyncData(AuthState.unauthenticated());
  }

  /// Throws [ApiException] on failure (invalid PIN, locked, network) so the
  /// calling screen can show a snackbar; only mutates session state on success.
  Future<void> login({required String identifier, required String pin}) async {
    final session = await _repo.login(identifier: identifier, pin: pin);
    await _tokens.save(
      access: session.accessToken,
      refresh: session.refreshToken,
    );
    // Drop any cached data from a previous session before the new one's screens
    // mount, so they fetch fresh with the new token (no flash of stale data).
    resetUserScopedProviders(ref);
    state = AsyncData(AuthState.authenticated(session.user));
  }

  /// Sign-up step 1 — does not change session state; returns the dev OTP (non-prod).
  Future<String?> requestOtp({
    required String fullName,
    required String phone,
    String? email,
  }) => _repo.requestOtp(fullName: fullName, phone: phone, email: email);

  /// Re-send the registration OTP (server enforces the resend cooldown).
  Future<String?> resendOtp({required String phone}) =>
      _repo.resendOtp(phone: phone);

  /// Verify the OTP on the Verify screen (throws [ApiException] on a wrong code).
  Future<void> verifyOtp({required String phone, required String otp}) =>
      _repo.verifyOtp(phone: phone, otp: otp);

  /// Sign-up steps 2 + 3 — verifies OTP, sets PIN, and signs the user in.
  /// Throws [ApiException] on failure (wrong OTP, rate-limited).
  Future<void> confirmRegister({
    required String phone,
    required String otp,
    required String pin,
  }) async {
    final session = await _repo.confirmRegister(
      phone: phone,
      otp: otp,
      pin: pin,
    );
    await _tokens.save(
      access: session.accessToken,
      refresh: session.refreshToken,
    );
    resetUserScopedProviders(ref);
    state = AsyncData(AuthState.authenticated(session.user));
  }

  /// Re-fetch the profile (e.g. after KYC or a balance change) without a reload flash.
  Future<void> refreshProfile() async {
    final user = await _repo.me();
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Save Edit Profile changes; updates the session user on success.
  /// Throws [ApiException] on failure so the screen can show a snackbar.
  Future<void> updateProfile(Map<String, dynamic> body) async {
    final user = await _repo.updateProfile(body);
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Submit identity documents for review; updates the session user on success.
  Future<void> submitIdentity({
    required String docType,
    required String documentFrontUrl,
    String? documentBackUrl,
    required String selfieUrl,
  }) async {
    final user = await _repo.submitIdentity(
      docType: docType,
      documentFrontUrl: documentFrontUrl,
      documentBackUrl: documentBackUrl,
      selfieUrl: selfieUrl,
    );
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Add a payout account; updates the session user (so every screen reading
  /// `user.payoutAccounts` sees it immediately, no separate refetch).
  Future<void> addPayoutAccount({
    required String bank,
    required String accountNumber,
    required String accountName,
    bool makeDefault = false,
  }) async {
    final user = await _repo.addPayoutAccount(
      bank: bank,
      accountNumber: accountNumber,
      accountName: accountName,
      makeDefault: makeDefault,
    );
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Update a saved payout account's bank/account number/account name.
  Future<void> updatePayoutAccount(
    String accountId, {
    String? bank,
    String? accountNumber,
    String? accountName,
  }) async {
    final user = await _repo.updatePayoutAccount(
      accountId,
      bank: bank,
      accountNumber: accountNumber,
      accountName: accountName,
    );
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Disable (soft-remove) a saved payout account.
  Future<void> removePayoutAccount(String accountId) async {
    final user = await _repo.removePayoutAccount(accountId);
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Set a saved payout account as the default (used for wallet withdrawal).
  Future<void> setDefaultPayoutAccount(String accountId) async {
    final user = await _repo.setDefaultPayoutAccount(accountId);
    state = AsyncData(AuthState.authenticated(user));
  }

  Future<void> logout() async {
    try {
      await _repo.logoutAll();
    } on ApiException {
      // Best-effort; we sign out locally regardless.
    }
    await _tokens.clear();
    resetUserScopedProviders(ref);
    state = const AsyncData(AuthState.unauthenticated());
  }

  /// Invoked by the auth interceptor when a refresh fails — drop the session.
  void forceLogout() {
    unawaited(_tokens.clear());
    resetUserScopedProviders(ref);
    state = const AsyncData(AuthState.unauthenticated());
  }

  // ── Biometric unlock + PIN ────────────────────────────────────────────────

  /// Prompt for biometrics and, on success, restore the locked session.
  Future<void> unlock() async {
    final ok = await _biometrics.authenticate('Unlock Hoppr');
    if (!ok) return; // stay locked — user can retry or sign in with their PIN
    state = const AsyncLoading();
    state = AsyncData(await _loadSession());
  }

  /// Turn biometric unlock on — requires a successful biometric check first.
  Future<bool> enableBiometric() async {
    if (!await _biometrics.isAvailable()) return false;
    final ok = await _biometrics.authenticate(
      'Confirm to enable biometric unlock',
    );
    if (!ok) return false;
    await _biometrics.setEnabled(true);
    return true;
  }

  Future<void> disableBiometric() => _biometrics.setEnabled(false);
  Future<bool> isBiometricEnabled() => _biometrics.isEnabled();
  Future<bool> isBiometricAvailable() => _biometrics.isAvailable();

  /// Change the 6-digit PIN. Throws [ApiException] on failure.
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) => _repo.changePin(currentPin: currentPin, newPin: newPin);

  /// Verify the account PIN (Change-PIN flow). Throws on a wrong PIN.
  Future<void> verifyAccountPin(String pin) => _repo.verifyPin(pin: pin);

  /// Start the forgot-PIN flow by sending a reset OTP to the registered phone.
  Future<String?> requestPinReset({required String phone}) =>
      _repo.requestPinReset(phone: phone);

  /// Confirm the forgot-PIN flow by verifying the OTP and setting the new PIN.
  Future<void> confirmPinReset({
    required String phone,
    required String otp,
    required String newPin,
  }) => _repo.confirmPinReset(phone: phone, otp: otp, newPin: newPin);
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
