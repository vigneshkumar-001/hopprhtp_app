import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT access + refresh tokens in the platform secure store
/// (Keychain / Keystore) — never in `shared_preferences`.
///
/// Tokens are mirrored in memory so request interceptors can read them
/// synchronously after [ensureLoaded] has run once.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _kAccess = 'hoppr.accessToken';
  static const String _kRefresh = 'hoppr.refreshToken';

  String? _access;
  String? _refresh;
  Future<void>? _loading;

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  /// Loads tokens into memory once; subsequent calls reuse the same Future.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _access = await _storage.read(key: _kAccess);
    _refresh = await _storage.read(key: _kRefresh);
  }

  Future<void> save({required String access, required String refresh}) async {
    _access = access;
    _refresh = refresh;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
