import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Pretty-prints every Dio request / response / error using the `logger`
/// package. Logs **Method, URL, Token, Body** on the way out and the **Response**
/// (with timing) on the way back.
///
/// Security:
///  • The Authorization token is printed in FULL only in debug builds; in
///    release it is masked to `Bearer …<last6>`.
///  • Sensitive request fields ([_redactKeys]) are always redacted so a PIN or
///    password can never reach the logs.
///  • Disabled in release by default (pass [enabled] to force it on).
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({bool? enabled}) : enabled = enabled ?? kDebugMode;

  final bool enabled;

  static final Logger _log = Logger(
    printer: PrettyPrinter(methodCount: 0, errorMethodCount: 8, lineLength: 100),
  );

  static const Set<String> _redactKeys = {'pin', 'password', 'newPin'};
  static const String _stopwatchKey = 'log_sw';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (enabled) {
      options.extra[_stopwatchKey] = Stopwatch()..start();
      final token = options.headers['Authorization']?.toString();
      _log.i(
        '--> ${options.method} ${options.uri}\n'
        'Token: ${_token(token)}\n'
        'Body : ${_body(options.data)}',
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    if (enabled) {
      final o = response.requestOptions;
      _log.i(
        '<-- ${response.statusCode} ${o.method} ${o.uri}${_elapsed(o)}\n'
        'Response: ${_body(response.data)}',
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (enabled) {
      final o = err.requestOptions;
      _log.e(
        'xxx ${err.response?.statusCode ?? '-'} ${o.method} ${o.uri}${_elapsed(o)}\n'
        'Error: ${_body(err.response?.data ?? err.message)}',
      );
    }
    handler.next(err);
  }

  String _elapsed(RequestOptions o) {
    final sw = o.extra[_stopwatchKey];
    return sw is Stopwatch ? ' (${sw.elapsedMilliseconds}ms)' : '';
  }

  String _token(String? header) {
    if (header == null || header.isEmpty) return '(none)';
    if (kDebugMode) return header; // full token — debug builds only
    final raw = header.startsWith('Bearer ') ? header.substring(7) : header;
    final tail = raw.length > 6 ? raw.substring(raw.length - 6) : raw;
    return 'Bearer …$tail';
  }

  String _body(Object? data) {
    if (data == null || (data is String && data.isEmpty)) return '(empty)';
    try {
      final decoded = data is String ? jsonDecode(data) : data;
      return const JsonEncoder.withIndent('  ').convert(_redact(decoded));
    } catch (_) {
      return data.toString();
    }
  }

  /// Recursively replaces sensitive values with `***`.
  Object? _redact(Object? value) {
    if (value is Map) {
      return value.map((k, v) =>
          MapEntry(k, _redactKeys.contains(k) ? '***' : _redact(v)));
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }
}
