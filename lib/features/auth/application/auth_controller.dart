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

  /// Pre-flight check before starting Firebase phone verification on
  /// sign-up — see [AuthRepository.isPhoneAvailable].
  Future<bool> isPhoneAvailable(String phone) => _repo.isPhoneAvailable(phone);

  /// Firebase Phone Auth registration — creates the account and signs the
  /// user in. Throws [ApiException] on failure (duplicate phone/email,
  /// invalid token).
  Future<void> confirmRegisterWithFirebase({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    required String pin,
    required String firebaseIdToken,
  }) async {
    final session = await _repo.confirmRegisterWithFirebase(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      email: email,
      pin: pin,
      firebaseIdToken: firebaseIdToken,
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

  /// Marks the onboarding tutorial as seen; updates the session user so
  /// [ApiUser.hasSeenTutorial] flips to true immediately — no separate
  /// refetch needed for HomeShell's own check to stop firing again.
  Future<void> markTutorialSeen() async {
    final user = await _repo.markTutorialSeen();
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Submit identity documents for review; updates the session user on success.
  Future<void> submitIdentity({
    required List<KycDocumentPayload> documents,
    required String selfieUrl,
  }) async {
    final user = await _repo.submitIdentity(
      documents: documents,
      selfieUrl: selfieUrl,
    );
    state = AsyncData(AuthState.authenticated(user));
  }

  /// Submit a Firebase Phone Auth ID token for server-side verification;
  /// updates the session user (`phoneVerified` now true) on success. Throws
  /// [ApiException] on failure (e.g. the phone is already linked elsewhere).
  Future<void> verifyPhoneWithFirebase(String idToken) async {
    final user = await _repo.verifyPhoneWithFirebase(idToken: idToken);
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
    // Clear the local session first so the UI navigates to the login screen
    // instantly; revoke tokens server-side best-effort in the background
    // (we sign out locally regardless of whether this succeeds).
    unawaited(_repo.logoutAll().catchError((_) {}));
    await _tokens.clear();
    resetUserScopedProviders(ref);
    state = const AsyncData(AuthState.unauthenticated());
  }

  /// Self-service account deletion (Settings → Delete account). Unlike
  /// [logout], the local session is only cleared AFTER the server confirms
  /// deletion — a wrong PIN or an unresolved balance/transaction must leave
  /// the caller still signed in so the screen can show the error and let
  /// them correct it, not silently sign them out first.
  Future<void> deleteAccount({required String pin}) async {
    await _repo.deleteAccount(pin: pin);
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

  /// Snapshotted by [relockIfBiometricEnabled] right before it clears [state]
  /// down to [AuthState.locked] (whose `user` is always null) — [unlock]
  /// uses this to reveal the app instantly on the (overwhelmingly common)
  /// case that the token is still fine, instead of always waiting on a
  /// network round-trip first. Null for a cold-boot-locked session, since
  /// there's nothing to have cached yet.
  ApiUser? _cachedUser;

  /// Prompt for biometrics and, on success, restore the locked session.
  /// Returns whether the biometric check itself succeeded — not whether the
  /// session behind it later turns out to still be valid (see
  /// [_revalidateAfterUnlock]) — so callers can show clear feedback on a
  /// failed/cancelled scan instead of leaving the person guessing why
  /// nothing happened.
  Future<bool> unlock() async {
    final ok = await _biometrics.authenticate('Unlock Hoppr');
    if (!ok) return false; // stay locked — user can retry or sign in with their PIN

    final cached = _cachedUser;
    if (cached != null) {
      // A warm re-lock: reveal the app immediately using the session
      // already held — nothing about it changed while locked, and the
      // person just proved it's them. Waiting on a network round-trip here
      // only makes the unlock feel slow for no visible benefit in the
      // common case where the token is still perfectly fine.
      state = AsyncData(AuthState.authenticated(cached));
      unawaited(_revalidateAfterUnlock());
    } else {
      // Cold-boot-locked — nothing cached to fall back on yet, so this is
      // the one case that has to wait on the network regardless.
      state = const AsyncLoading();
      state = AsyncData(await _loadSession());
    }
    return true;
  }

  /// Confirms the token [unlock] just trusted optimistically is genuinely
  /// still good, in the background — the person is already back in the app
  /// by the time this runs. A revoked/expired/frozen-account token drops
  /// them back to sign-in the normal way (AuthGate's own session-ended
  /// listener reacts to the state change); a transient network hiccup is
  /// left as "still fine" rather than signing someone out over a blip — the
  /// auth interceptor's own 401 handling on the next real API call is the
  /// backstop regardless.
  Future<void> _revalidateAfterUnlock() async {
    try {
      final user = await _repo.me();
      if (state.valueOrNull?.isAuthenticated == true) {
        state = AsyncData(AuthState.authenticated(user));
      }
    } on ApiException catch (e) {
      if (state.valueOrNull?.isAuthenticated != true) return;
      await _tokens.clear();
      state = isAccountBlockedCode(e.code)
          ? AsyncData(AuthState.blocked(code: e.code, message: e.userMessage))
          : const AsyncData(AuthState.unauthenticated());
    } catch (_) {
      // Offline/timeout — leave the optimistic authenticated state as-is.
    }
  }

  /// Re-locks an already-authenticated session the moment biometric unlock
  /// is on — called from [HopprApp]'s app-lifecycle observer when the app is
  /// backgrounded, so returning to it always demands a fresh biometric (or
  /// PIN, via [unlock]'s sign-in fallback) check instead of resuming straight
  /// to the dashboard. A no-op when biometric is off (the default: the
  /// session just resumes normally) or when there's no live session to lock.
  Future<void> relockIfBiometricEnabled() async {
    final current = state.valueOrNull;
    if (current?.isAuthenticated != true) return;
    if (!await _biometrics.isEnabled()) return;
    _cachedUser = current!.user;
    state = const AsyncData(AuthState.locked());
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

  /// Confirm the forgot-PIN flow with a Firebase phone-verification ID token
  /// plus the new PIN — see [AuthRepository.confirmPinResetWithFirebase].
  Future<void> confirmPinResetWithFirebase({
    required String firebaseIdToken,
    required String newPin,
  }) => _repo.confirmPinResetWithFirebase(
    firebaseIdToken: firebaseIdToken,
    newPin: newPin,
  );
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
