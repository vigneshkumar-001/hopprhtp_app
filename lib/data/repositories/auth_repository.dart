import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/auth_dto.dart';
import '../dto/user_dto.dart';

/// Result of requesting/resending the registration phone OTP: the resend
/// cooldown the server actually enforced (so the UI's countdown always
/// matches reality), the dev-only echoed code in non-prod, and whether the
/// Admin Panel currently has Test Mode on for phone verification — when it
/// is, [testCode] carries the actual admin-configured code to enter (never
/// a secret; only present while test mode is on) for signup_screen.dart's
/// dev-only hint.
typedef OtpRequestResult = ({String? devOtp, int cooldownSeconds, bool testMode, String? testCode});

/// Thin wrapper over the `/auth` and `/users/me` endpoints. Returns DTOs or
/// throws [ApiException]; performs no token storage itself (the controller owns
/// that, so this stays a pure data source).
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// Step 1 of sign-up — sends a backend-generated OTP via Termii (see
  /// backend `auth.service.ts` deliverOtp()/termii.client.ts).
  Future<OtpRequestResult> requestOtp({
    required String fullName,
    required String phone,
    String? email,
  }) {
    return apiCall(
      () => _dio.post(
        '/auth/register/request-phone-otp',
        data: {
          'fullName': fullName,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
        },
      ),
      (d) {
        final m = asMap(d);
        return (
          devOtp: asStringOrNull(m['devOtp']),
          cooldownSeconds: asInt(m['cooldownSeconds'], 30),
          testMode: asBool(m['testMode']),
          testCode: asStringOrNull(m['testCode']),
        );
      },
    );
  }

  /// Steps 2 + 3: verify OTP and set the PIN — creates the account, returns a session.
  Future<AuthSession> confirmRegister({
    required String phone,
    required String otp,
    required String pin,
  }) {
    return apiCall(
      () => _dio.post(
        '/auth/register/confirm',
        data: {'phone': phone, 'otp': otp, 'pin': pin},
      ),
      (d) => AuthSession.fromJson(asMap(d)),
    );
  }

  /// Firebase Phone Auth registration — call after Firebase has already
  /// verified the phone client-side (FirebasePhoneAuthService.confirmCode())
  /// and returned an ID token. Creates the account and signs the user in
  /// (same session shape as [confirmRegister]). The backend derives the
  /// real, stored phone from the verified token itself — [phone] here is
  /// informational only, never trusted on its own.
  Future<AuthSession> confirmRegisterWithFirebase({
    required String fullName,
    required String phone,
    String? email,
    required String pin,
    required String firebaseIdToken,
  }) {
    return apiCall(
      () => _dio.post(
        '/auth/register/firebase',
        data: {
          'fullName': fullName,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          'pin': pin,
          'firebaseIdToken': firebaseIdToken,
        },
      ),
      (d) => AuthSession.fromJson(asMap(d)),
    );
  }

  /// Re-send the registration OTP for a pending sign-up (server enforces cooldown).
  Future<OtpRequestResult> resendOtp({required String phone}) {
    return apiCall(
      () => _dio.post('/auth/resend-otp', data: {'phone': phone}),
      (d) {
        final m = asMap(d);
        return (
          devOtp: asStringOrNull(m['devOtp']),
          cooldownSeconds: asInt(m['cooldownSeconds'], 30),
          testMode: asBool(m['testMode']),
          testCode: asStringOrNull(m['testCode']),
        );
      },
    );
  }

  /// Verify the OTP at the Verify-Your-Number step (does not consume it; the
  /// account is created at confirm). Throws [ApiException] on a wrong/expired code.
  Future<void> verifyOtp({required String phone, required String otp}) {
    return apiCall<void>(
      () => _dio.post('/auth/register/verify-phone-otp', data: {'phone': phone, 'otp': otp}),
      (_) {},
    );
  }

  /// Sign in with phone-or-email plus the 6-digit PIN.
  Future<AuthSession> login({required String identifier, required String pin}) {
    return apiCall(
      () => _dio.post(
        '/auth/login',
        data: {'identifier': identifier, 'pin': pin},
      ),
      (d) => AuthSession.fromJson(asMap(d)),
    );
  }

  /// Revoke every issued token for this account (logout everywhere).
  Future<void> logoutAll() =>
      apiCall<void>(() => _dio.post('/auth/logout-all'), (_) {});

  /// Change the 6-digit PIN (verifies the current one server-side).
  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) => apiCall<void>(
    () => _dio.post(
      '/auth/change-pin',
      data: {'currentPin': currentPin, 'newPin': newPin},
    ),
    (_) {},
  );

  /// Verify the account PIN (e.g. the current PIN in the Change-PIN flow).
  /// Throws [ApiException] ('Incorrect PIN') on a wrong PIN.
  Future<void> verifyPin({required String pin}) => apiCall<void>(
    () => _dio.post('/auth/verify-pin', data: {'pin': pin}),
    (_) {},
  );

  /// Start the PIN reset flow by sending an OTP to the registered phone.
  Future<String?> requestPinReset({required String phone}) {
    return apiCall(
      () => _dio.post('/auth/pin-reset/request-otp', data: {'phone': phone}),
      (d) => asStringOrNull(asMap(d)['devOtp']),
    );
  }

  /// Confirm the PIN reset with the OTP and the new 6-digit PIN.
  Future<void> confirmPinReset({
    required String phone,
    required String otp,
    required String newPin,
  }) {
    return apiCall<void>(
      () => _dio.post(
        '/auth/pin-reset/confirm',
        data: {'phone': phone, 'otp': otp, 'newPin': newPin},
      ),
      (_) {},
    );
  }

  /// Fetch the current user profile (also used to validate a restored session).
  Future<ApiUser> me() =>
      apiCall(() => _dio.get('/users/me'), (d) => ApiUser.fromJson(asMap(d)));

  /// Update the profile (Edit Profile screen). Returns the saved user.
  Future<ApiUser> updateProfile(Map<String, dynamic> body) => apiCall(
    () => _dio.patch('/users/me', data: body),
    (d) => ApiUser.fromJson(asMap(d)),
  );

  /// Register (or refresh) this device's FCM push token. [platform] is
  /// 'android' | 'ios'; omit when unknown. Best-effort from the caller's side
  /// — [PushNotificationService] already never lets a failure here propagate.
  Future<void> updateFcmToken({required String fcmToken, String? platform}) =>
      apiCall<void>(
        () => _dio.post(
          '/users/me/fcm-token',
          data: {'fcmToken': fcmToken, 'platform': ?platform},
        ),
        (_) {},
      );

  /// Submit KYC documents for review. [docType] is nin|drivers_license|passport.
  /// Returns the saved user (identity now `pending`).
  Future<ApiUser> submitIdentity({
    required String docType,
    required String documentFrontUrl,
    String? documentBackUrl,
    required String selfieUrl,
  }) => apiCall(
    () => _dio.post(
      '/users/me/identity',
      data: {
        'docType': docType,
        'documentFrontUrl': documentFrontUrl,
        'documentBackUrl': ?documentBackUrl,
        'selfieUrl': selfieUrl,
      },
    ),
    (d) => ApiUser.fromJson(asMap(d)),
  );

  /// Submit a Firebase Phone Auth ID token for server-side verification
  /// (POST /users/me/phone-verification/firebase). The backend verifies the
  /// token itself via the Firebase Admin SDK — this call never sends a raw
  /// phone number, only the token proving the user already confirmed it
  /// with Firebase. Returns the saved user (`phoneVerified` now true) on
  /// success; throws [ApiException] with a friendly message otherwise (e.g.
  /// "This phone number is already linked to another account.").
  Future<ApiUser> verifyPhoneWithFirebase({required String idToken}) =>
      apiCall(
        () => _dio.post(
          '/users/me/phone-verification/firebase',
          data: {'idToken': idToken},
        ),
        (d) => ApiUser.fromJson(asMap(d)),
      );

  /// Add a payout account (Payout Accounts / Wallet settings only — never
  /// part of Create Transaction). Returns the full saved user.
  Future<ApiUser> addPayoutAccount({
    required String bank,
    required String accountNumber,
    required String accountName,
    bool makeDefault = false,
  }) => apiCall(
    () => _dio.post(
      '/users/me/payout-accounts',
      data: {
        'bank': bank,
        'accountNumber': accountNumber,
        'accountName': accountName,
        'makeDefault': makeDefault,
      },
    ),
    (d) => ApiUser.fromJson(asMap(d)),
  );

  /// Update a saved payout account's bank/account number/account name
  /// (partial — only the fields passed are changed).
  Future<ApiUser> updatePayoutAccount(
    String accountId, {
    String? bank,
    String? accountNumber,
    String? accountName,
  }) => apiCall(
    () => _dio.patch(
      '/users/me/payout-accounts/$accountId',
      data: {
        'bank': ?bank,
        'accountNumber': ?accountNumber,
        'accountName': ?accountName,
      },
    ),
    (d) => ApiUser.fromJson(asMap(d)),
  );

  /// Disable (soft-remove) a saved payout account. Never hard-deletes.
  Future<ApiUser> removePayoutAccount(String accountId) => apiCall(
    () => _dio.delete('/users/me/payout-accounts/$accountId'),
    (d) => ApiUser.fromJson(asMap(d)),
  );

  /// Set a saved payout account as the default (used for wallet withdrawal).
  Future<ApiUser> setDefaultPayoutAccount(String accountId) => apiCall(
    () => _dio.patch('/users/me/payout-accounts/$accountId/default'),
    (d) => ApiUser.fromJson(asMap(d)),
  );
}
