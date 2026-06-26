import 'package:escrow/core/auth/biometric_service.dart';
import 'package:escrow/core/network/api_exception.dart';
import 'package:escrow/core/storage/token_store.dart';
import 'package:escrow/data/dto/auth_dto.dart';
import 'package:escrow/data/dto/user_dto.dart';
import 'package:escrow/data/repositories/auth_repository.dart';

/// A canned authenticated user used across tests.
const kTestUser = ApiUser(
  id: 'u1',
  fullName: 'Amara Okafor',
  phone: '+2348000000000',
  email: null,
  trustScore: 80,
  trustGrade: 'A',
  deals: 0,
  disputes: 0,
  verified: false,
  identityStatus: 'unverified',
  escrowBalanceKobo: 0,
  walletAvailableKobo: 0,
  walletCoolingKobo: 0,
);

/// In-memory token store — no platform secure-storage channel in tests. Pass
/// [access]/[refresh] to simulate a previously-signed-in session.
class FakeTokenStore implements TokenStore {
  FakeTokenStore({String? access, String? refresh})
      : _a = access,
        _r = refresh;

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

/// Configurable fake of the auth API. Set [failLogin] to simulate bad creds.
class FakeAuthRepository implements AuthRepository {
  bool failLogin = false;

  @override
  Future<AuthSession> login({required String identifier, required String pin}) async {
    if (failLogin) {
      throw ApiException(
          code: 'UNAUTHORIZED', message: 'Invalid credentials', statusCode: 401);
    }
    return const AuthSession(user: kTestUser, accessToken: 'a', refreshToken: 'r');
  }

  @override
  Future<ApiUser> me() async => kTestUser;

  @override
  Future<ApiUser> updateProfile(Map<String, dynamic> body) async => kTestUser;

  @override
  Future<ApiUser> submitIdentity({
    required String docType,
    required String documentFrontUrl,
    String? documentBackUrl,
    required String selfieUrl,
  }) async =>
      kTestUser;

  @override
  Future<AuthSession> confirmRegister(
          {required String phone, required String otp, required String pin}) async =>
      const AuthSession(user: kTestUser, accessToken: 'a', refreshToken: 'r');

  @override
  Future<String?> requestOtp(
          {required String fullName, required String phone, String? email}) async =>
      '123456';

  @override
  Future<String?> resendOtp({required String phone}) async => '123456';

  @override
  Future<void> verifyOtp({required String phone, required String otp}) async {}

  @override
  Future<void> logoutAll() async {}

  @override
  Future<void> changePin(
      {required String currentPin, required String newPin}) async {}

  @override
  Future<void> verifyPin({required String pin}) async {}

  @override
  Future<String?> requestPinReset({required String phone}) async => '123456';

  @override
  Future<void> confirmPinReset({
    required String phone,
    required String otp,
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
