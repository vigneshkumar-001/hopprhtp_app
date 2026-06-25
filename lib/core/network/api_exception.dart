import 'package:dio/dio.dart';

/// A typed error mapped from the backend's `{ success:false, error:{...} }`
/// envelope (or from a transport-level Dio failure). UI code should catch this
/// and show [message]; branch on [code] / [isNetwork] / [isUnauthorized].
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Object? details;

  bool get isNetwork => code == 'NETWORK';
  bool get isTimeout => code == 'TIMEOUT';

  /// Any transport-level failure: offline, server unreachable, or timed out.
  bool get isConnectionIssue => isNetwork || isTimeout;
  bool get isUnauthorized => statusCode == 401;

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    // Server error envelope: { success:false, error:{ code, message, details? } }
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        code: (err['code'] ?? 'ERROR').toString(),
        message: (err['message'] ?? 'Something went wrong').toString(),
        statusCode: e.response?.statusCode,
        details: err['details'],
      );
    }

    // Reached the network but the server took too long to respond.
    final timedOut = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
    if (timedOut) {
      return ApiException(
        code: 'TIMEOUT',
        message: 'Request timed out',
        statusCode: e.response?.statusCode,
      );
    }

    // Couldn't establish a connection at all (server down / refused / TLS).
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.badCertificate) {
      return ApiException(
        code: 'NETWORK',
        message: 'Cannot reach the server',
        statusCode: e.response?.statusCode,
      );
    }

    return ApiException(
      code: 'ERROR',
      message: e.message ?? 'Unexpected error',
      statusCode: e.response?.statusCode,
    );
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
