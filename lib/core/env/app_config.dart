/// Static app configuration — the API base URL.
///
/// Resolution order:
///   1. `--dart-define=API_BASE_URL=...` (highest priority — use for staging/prod)
///   2. The [_default] below.
///
/// The base URL MUST include the server's `/api/v1` prefix.
class AppConfig {
  AppConfig._();

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Hosted backend (Heroku). Reachable from a real device, emulator and web
  /// alike. Override per-build with `--dart-define=API_BASE_URL=...` (e.g. a
  /// local dev tunnel) without touching this file.
  static const String _default =
      'https://hoppr-htp-ccf74f30631f.herokuapp.com/api/v1';

  static String get apiBaseUrl => _override.isNotEmpty ? _override : _default;

  /// Web origin (no `/api/v1`) — used to build the hosted checkout link
  /// `<webBaseUrl>/pay/<code>` shared with buyers.
  static String get webBaseUrl {
    const suffix = '/api/v1';
    final base = apiBaseUrl;
    return base.endsWith(suffix)
        ? base.substring(0, base.length - suffix.length)
        : base;
  }
}

// ── Local-only alternative (no tunnel) ──────────────────────────────────────
// If you go back to running the backend locally, replace `_default`/`apiBaseUrl`
// above with this (and add `import 'package:flutter/foundation.dart';`):
//
//   static String get apiBaseUrl {
//     if (_override.isNotEmpty) return _override;
//     final host =
//         defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
//     return 'http://$host:4000/api/v1';
//   }
