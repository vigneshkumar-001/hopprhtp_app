import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/auth_dto.dart';
import '../dto/user_dto.dart';

/// Thin wrapper over the `/auth` and `/users/me` endpoints. Returns DTOs or
/// throws [ApiException]; performs no token storage itself (the controller owns
/// that, so this stays a pure data source).
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// Step 1 of sign-up. Returns the dev OTP in non-prod (server echoes it),
  /// `null` in production.
  Future<String?> requestOtp({
    required String fullName,
    required String phone,
    String? email,
  }) {
    return apiCall(
      () => _dio.post(
        '/auth/register/request-otp',
        data: {
          'fullName': fullName,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
        },
      ),
      (d) => asStringOrNull(asMap(d)['devOtp']),
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

  /// Re-send the registration OTP for a pending sign-up (server enforces cooldown).
  Future<String?> resendOtp({required String phone}) {
    return apiCall(
      () => _dio.post('/auth/resend-otp', data: {'phone': phone}),
      (d) => asStringOrNull(asMap(d)['devOtp']),
    );
  }

  /// Verify the OTP at the Verify-Your-Number step (does not consume it; the
  /// account is created at confirm). Throws [ApiException] on a wrong/expired code.
  Future<void> verifyOtp({required String phone, required String otp}) {
    return apiCall<void>(
      () => _dio.post('/auth/verify-otp', data: {'phone': phone, 'otp': otp}),
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
