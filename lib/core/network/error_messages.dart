import 'api_exception.dart';

/// Maps a raw [ApiException] to a calm, user-facing sentence. The backend
/// already returns friendly 4xx messages, so we surface those and only override
/// for network / 5xx / rate-limit cases where the raw text is unhelpful.
extension ApiExceptionMessage on ApiException {
  String get userMessage {
    if (isTimeout) {
      return 'Connection timed out. Please check your internet and try again.';
    }
    if (isNetwork) {
      return "Can't reach our servers right now. Please check your connection and try again.";
    }
    final status = statusCode ?? 0;
    if (status >= 500 || status == 0) {
      return "We're having trouble reaching our services. Please try again shortly.";
    }
    if (code == 'RATE_LIMITED' || status == 429) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (status == 401) {
      return message.isNotEmpty
          ? message
          : 'Your session has expired. Please sign in again.';
    }
    // Surface the first field-level validation message (e.g. "Account number
    // must be 10 digits") instead of the generic "Request validation failed".
    if (code == 'VALIDATION_ERROR') {
      final d = details;
      if (d is List && d.isNotEmpty) {
        final first = d.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
    }
    return message.isNotEmpty ? message : 'Something went wrong. Please try again.';
  }
}

/// Turn any caught object into a friendly message (non-[ApiException] included).
String friendlyError(Object error) => error is ApiException
    ? error.userMessage
    : 'Something went wrong. Please try again.';
