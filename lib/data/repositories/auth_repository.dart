import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/auth_dto.dart';
import '../dto/user_dto.dart';

/// One government ID document within a KYC submission — see
/// [AuthRepository.submitIdentity]. Mirrors the backend's
/// identityDocumentSchema (user.schema.ts).
class KycDocumentPayload {
  const KycDocumentPayload({
    required this.docType,
    required this.documentFrontUrl,
    this.documentBackUrl,
  });

  final String docType;
  final String documentFrontUrl;
  final String? documentBackUrl;

  Map<String, dynamic> toJson() => {
    'docType': docType,
    'documentFrontUrl': documentFrontUrl,
    'documentBackUrl': ?documentBackUrl,
  };
}

/// Thin wrapper over the `/auth` and `/users/me` endpoints. Returns DTOs or
/// throws [ApiException]; performs no token storage itself (the controller owns
/// that, so this stays a pure data source).
class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// Pre-flight check before starting Firebase phone verification on
  /// sign-up — lets the UI reject an already-registered number immediately
  /// instead of only after a real SMS OTP has already been sent and
  /// confirmed. Read-only, no side effects.
  Future<bool> isPhoneAvailable(String phone) => apiCall(
    () => _dio.post('/auth/register/check-phone', data: {'phone': phone}),
    (d) => asBool(asMap(d)['available']),
  );

  /// Firebase Phone Auth registration — call after Firebase has already
  /// verified the phone client-side (FirebasePhoneAuthService.confirmCode())
  /// and returned an ID token. Creates the account and signs the user in
  /// (same session shape as [confirmRegister]). The backend derives the
  /// real, stored phone from the verified token itself — [phone] here is
  /// informational only, never trusted on its own.
  Future<AuthSession> confirmRegisterWithFirebase({
    required String firstName,
    required String lastName,
    required String phone,
    String? email,
    required String pin,
    required String firebaseIdToken,
  }) {
    return apiCall(
      () => _dio.post(
        '/auth/register/firebase',
        data: {
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
          if (email != null && email.isNotEmpty) 'email': email,
          'pin': pin,
          'firebaseIdToken': firebaseIdToken,
        },
      ),
      (d) => AuthSession.fromJson(asMap(d)),
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

  /// Confirm the forgot-PIN flow with a Firebase phone-verification ID token
  /// (the client already verified phone ownership itself — see
  /// FirebasePhoneAuthService) plus the new 6-digit PIN. No separate
  /// "request OTP" call exists — Firebase sends the SMS directly.
  Future<void> confirmPinResetWithFirebase({
    required String firebaseIdToken,
    required String newPin,
  }) {
    return apiCall<void>(
      () => _dio.post(
        '/auth/pin-reset/confirm-firebase',
        data: {'firebaseIdToken': firebaseIdToken, 'newPin': newPin},
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

  /// Marks the in-app onboarding tutorial as seen — called once the user
  /// finishes it or taps Skip, so it never shows again for this account.
  Future<ApiUser> markTutorialSeen() => apiCall(
    () => _dio.post('/users/me/tutorial-seen'),
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

  /// Submit KYC documents for review. Exactly 2 of different
  /// nin|drivers_license|passport types are required (server-enforced by
  /// identityVerifySchema — see backend user.schema.ts). Returns the saved
  /// user (identity now `pending`).
  Future<ApiUser> submitIdentity({
    required List<KycDocumentPayload> documents,
    required String selfieUrl,
  }) => apiCall(
    () => _dio.post(
      '/users/me/identity',
      data: {
        'documents': documents.map((d) => d.toJson()).toList(),
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

  /// Self-service account deletion (Settings → Delete account). Throws
  /// [ApiException] with a friendly message if the PIN is wrong, or if the
  /// account still has a wallet/escrow balance or an in-flight transaction
  /// (server-enforced — see backend userService.deleteAccount).
  Future<void> deleteAccount({required String pin}) => apiCall<void>(
    () => _dio.post('/users/me/delete', data: {'pin': pin}),
    (_) {},
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
