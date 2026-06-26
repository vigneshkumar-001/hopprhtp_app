import 'package:dio/dio.dart';
import '../storage/token_store.dart';

/// Attaches the access token to every request and, on a `401`, transparently
/// refreshes it once and replays the original request.
///
/// The refresh call goes through a *separate* bare [Dio] ([refreshDio]) that has
/// no interceptor, so it can never recurse. Concurrent 401s share a single
/// in-flight refresh via [_refreshing]. If the refresh itself fails (refresh
/// token revoked / expired), [onSessionExpired] fires so the app can log out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokens,
    required this.refreshDio,
    required this.onSessionExpired,
  });

  final TokenStore tokens;
  final Dio refreshDio;
  final void Function() onSessionExpired;

  Future<void>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    await tokens.ensureLoaded();
    final access = tokens.accessToken;
    if (access != null) options.headers['Authorization'] = 'Bearer $access';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final path = err.requestOptions.path;
    final isNonRetryAuthEndpoint = path.contains('/auth/login') ||
        path.contains('/auth/register/') ||
        path.contains('/auth/refresh') ||
        path.contains('/auth/pin-reset/');
    final alreadyRetried = err.requestOptions.extra['retried'] == true;

    if (err.response?.statusCode != 401 ||
        isNonRetryAuthEndpoint ||
        alreadyRetried ||
        tokens.refreshToken == null) {
      return handler.next(err);
    }

    try {
      await _performRefresh();
    } catch (_) {
      onSessionExpired();
      return handler.next(err);
    }

    // Replay the original request once with the fresh token.
    final req = err.requestOptions;
    req.extra['retried'] = true;
    req.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    try {
      final response = await refreshDio.fetch<dynamic>(req);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  Future<void> _performRefresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<void> _doRefresh() async {
    final res = await refreshDio.post<dynamic>(
      '/auth/refresh',
      data: {'refreshToken': tokens.refreshToken},
    );
    final data = (res.data as Map)['data'] as Map;
    await tokens.save(
      access: data['accessToken'].toString(),
      refresh: data['refreshToken'].toString(),
    );
  }
}
