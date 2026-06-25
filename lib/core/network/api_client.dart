import 'package:dio/dio.dart';
import 'api_exception.dart';

/// Sends a request, unwraps the standard `{ success:true, data }` envelope, and
/// maps any failure to an [ApiException]. Every repository method funnels
/// through this so error handling and envelope-unwrapping live in one place.
///
/// ```dart
/// Future<ApiUser> me() =>
///     apiCall(() => _dio.get('/users/me'), (d) => ApiUser.fromJson(asMap(d)));
/// ```
Future<T> apiCall<T>(
  Future<Response<dynamic>> Function() request,
  T Function(dynamic data) parse,
) async {
  try {
    final res = await request();
    final body = res.data;
    if (body is Map && body['success'] == true) return parse(body['data']);
    throw ApiException(
      code: 'BAD_RESPONSE',
      message: 'Unexpected server response',
      statusCode: res.statusCode,
    );
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
}
