import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/merchant_dto.dart';

/// Wraps the `/merchant/:id` endpoint — a public-safe profile (identity +
/// real stats + redacted recent activity) viewable by any signed-in user.
class MerchantRepository {
  MerchantRepository(this._dio);

  final Dio _dio;

  Future<MerchantProfile> getProfile(String merchantId) => apiCall(
    () => _dio.get('/merchant/$merchantId'),
    (d) => MerchantProfile.fromJson(asMap(d)),
  );
}
