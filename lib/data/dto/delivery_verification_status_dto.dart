import '../../core/network/json.dart';
import 'tracking_dto.dart';

/// Real-time eligibility snapshot for `POST /transactions/:id/confirm-delivery`
/// from `GET /transactions/:id/delivery-verification-status`. This only drives
/// the UI — the backend independently re-checks every one of these conditions
/// again inside confirm-delivery itself, and is the final authority.
class DeliveryVerificationStatus {
  const DeliveryVerificationStatus({
    required this.canVerify,
    this.reason,
    this.distanceMeters,
    required this.thresholdMeters,
    required this.transactionStatus,
    required this.locationAvailable,
    this.buyerLocation,
    this.sellerCurrentLocation,
    required this.codeRequired,
    required this.alreadyVerified,
  });

  final bool canVerify;
  final String? reason;
  final double? distanceMeters;
  final double thresholdMeters;
  final String
  transactionStatus; // raw backend status — pair with ApiTxStatus.fromApi
  final bool locationAvailable;
  final TrackingLocation? buyerLocation;
  final TrackingLocation? sellerCurrentLocation;
  final bool codeRequired;
  final bool alreadyVerified;

  factory DeliveryVerificationStatus.fromJson(Map<String, dynamic> j) =>
      DeliveryVerificationStatus(
        canVerify: asBool(j['canVerify']),
        reason: asStringOrNull(j['reason']),
        distanceMeters: j['distanceMeters'] == null
            ? null
            : asDouble(j['distanceMeters']),
        thresholdMeters: asDouble(j['thresholdMeters'], 200),
        transactionStatus: asString(j['transactionStatus']),
        locationAvailable: asBool(j['locationAvailable']),
        buyerLocation: TrackingLocation.fromJsonOrNull(j['buyerLocation']),
        sellerCurrentLocation: TrackingLocation.fromJsonOrNull(
          j['sellerCurrentLocation'],
        ),
        codeRequired: asBool(j['codeRequired'], true),
        alreadyVerified: asBool(j['alreadyVerified']),
      );
}
