import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Wraps device biometric authentication (fingerprint / face) and remembers
/// whether the user opted in. The preference lives in secure storage; all calls
/// are defensive so a missing sensor / plugin never throws into the UI.
class BiometricService {
  BiometricService({LocalAuthentication? auth, FlutterSecureStorage? storage})
      : _auth = auth ?? LocalAuthentication(),
        _storage = storage ?? const FlutterSecureStorage();

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const String _kEnabled = 'hoppr.biometricEnabled';

  /// True when the device has biometrics enrolled and usable.
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// True when the user has turned biometric unlock on.
  Future<bool> isEnabled() async {
    try {
      return (await _storage.read(key: _kEnabled)) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    try {
      await _storage.write(key: _kEnabled, value: value ? 'true' : 'false');
    } catch (_) {
      // best-effort
    }
  }

  /// Prompts the OS biometric sheet. Returns true only on a successful scan.
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
