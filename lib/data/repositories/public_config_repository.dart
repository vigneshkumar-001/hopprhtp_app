import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

class PublicConfigRepository {
  PublicConfigRepository(this._dio);

  final Dio _dio;

  Future<String?> googleApiKey() => apiCall(
        () => _dio.get('/public-config'),
        (d) => asStringOrNull(asMap(d)['googleApiKey']),
      );
}
