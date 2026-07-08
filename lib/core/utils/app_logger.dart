import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:logger/logger.dart';

/// Single shared debug logger for the whole app — the same `logger` package
/// and style already used by `LoggingInterceptor` (Dio request/response
/// logging) and the public-config fetch in `core/providers.dart`, just
/// centralized into one reusable instance instead of each call site creating
/// its own `Logger()`.
///
/// `Logger`'s default filter only ever evaluates inside an `assert` block,
/// which Dart strips entirely from release builds — so nothing here can
/// print in production even without the explicit `kDebugMode` check below.
/// That check is kept anyway (matching `LoggingInterceptor`'s `enabled`
/// pattern) so a release/profile build never even formats the log string.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(methodCount: 0, lineLength: 100),
  );

  /// Debug-level log line — silently dropped outside debug builds.
  static void debug(String message) {
    if (kDebugMode) _logger.i(message);
  }
}
