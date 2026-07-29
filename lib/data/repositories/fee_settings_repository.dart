import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Mirrors the backend's public, unauthenticated
/// `GET /fee-settings/public` response — only the fields this app's local
/// preview estimators (`DeliveryFeeEstimator`, `PaymentDraft.trustRate`)
/// know how to represent. Money fields arrive in kobo and are converted to
/// naira here, matching this app's on-screen-money convention.
class PublicFeeSettings {
  const PublicFeeSettings({
    required this.platformFeeMode,
    required this.platformFeePercentage,
    required this.deliveryBaseFee,
    required this.deliveryPerKmFee,
    required this.deliveryFreeWeightKg,
    required this.deliveryExtraWeightFee,
    required this.deliveryMinimumFee,
  });

  factory PublicFeeSettings.fromJson(Map<String, dynamic> json) {
    final platform = asMap(json['platformFee']);
    final logistics = asMap(json['logisticsFee']);
    return PublicFeeSettings(
      platformFeeMode: asString(platform['mode'], 'percentage'),
      platformFeePercentage: asDouble(platform['percentage'], 1.5),
      deliveryBaseFee: asDouble(logistics['baseFeeKobo'], 50000) / 100,
      deliveryPerKmFee: asDouble(logistics['perKmFeeKobo'], 15000) / 100,
      deliveryFreeWeightKg: asDouble(logistics['freeWeightKg'], 2),
      deliveryExtraWeightFee:
          asDouble(logistics['extraWeightFeeKobo'], 20000) / 100,
      deliveryMinimumFee: asDouble(logistics['minFeeKobo'], 50000) / 100,
    );
  }

  /// 'percentage' | 'fixed' | 'percentage_plus_fixed' — only 'percentage'
  /// maps onto [PaymentDraft.trustRate]; the other modes have no local
  /// preview representation, so callers should leave trustRate untouched
  /// rather than sync a number that would misrepresent them.
  final String platformFeeMode;
  final double platformFeePercentage;
  final double deliveryBaseFee;
  final double deliveryPerKmFee;
  final double deliveryFreeWeightKg;
  final double deliveryExtraWeightFee;
  final double deliveryMinimumFee;
}

class FeeSettingsRepository {
  FeeSettingsRepository(this._dio);

  final Dio _dio;

  Future<PublicFeeSettings> fetch() => apiCall(
        () => _dio.get('/fee-settings/public'),
        (d) => PublicFeeSettings.fromJson(asMap(d)),
      );
}
