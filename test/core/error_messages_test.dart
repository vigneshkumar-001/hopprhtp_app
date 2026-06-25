import 'package:escrow/core/network/api_exception.dart';
import 'package:escrow/core/network/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiException.userMessage', () {
    test('timeout → friendly "timed out" copy (not "no internet")', () {
      final e = ApiException(code: 'TIMEOUT', message: 'Request timed out');
      expect(e.userMessage, contains('timed out'));
      expect(e.userMessage, isNot(contains('No internet')));
    });

    test('connection error → server-unreachable copy', () {
      final e = ApiException(code: 'NETWORK', message: 'whatever');
      expect(e.userMessage, contains('reach our servers'));
    });

    test('5xx → generic service copy (never leaks raw message)', () {
      final e = ApiException(
          code: 'INTERNAL_ERROR', message: 'NullPointer at line 9', statusCode: 500);
      expect(e.userMessage, contains('trouble reaching'));
      expect(e.userMessage, isNot(contains('NullPointer')));
    });

    test('429 → rate-limit copy', () {
      final e = ApiException(code: 'RATE_LIMITED', message: 'x', statusCode: 429);
      expect(e.userMessage, contains('Too many attempts'));
    });

    test('4xx → surfaces the friendly server message', () {
      final e = ApiException(
          code: 'UNAUTHORIZED', message: 'Invalid credentials', statusCode: 401);
      expect(e.userMessage, 'Invalid credentials');
    });

    test('friendlyError handles non-ApiException objects', () {
      expect(friendlyError(StateError('boom')), contains('Something went wrong'));
    });
  });
}
