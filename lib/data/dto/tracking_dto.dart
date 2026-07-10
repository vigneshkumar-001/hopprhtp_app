import '../../core/network/json.dart';

/// A single point in a tracking snapshot (buyer destination or seller's last
/// self-reported position). [address]/[updatedAt] are populated depending on
/// which side this came from.
class TrackingLocation {
  const TrackingLocation({
    required this.latitude,
    required this.longitude,
    this.address,
    this.updatedAt,
  });

  final double latitude;
  final double longitude;
  final String? address;
  final DateTime? updatedAt;

  static TrackingLocation? fromJsonOrNull(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    if (m['latitude'] == null || m['longitude'] == null) return null;
    return TrackingLocation(
      latitude: asDouble(m['latitude']),
      longitude: asDouble(m['longitude']),
      address: asStringOrNull(m['address']),
      updatedAt: asDateTime(m['updatedAt']),
    );
  }
}

/// A real, backend-computed route between the seller's last position and the
/// buyer's destination. Only ever present when the backend actually returned
/// one — never synthesised client-side.
class TrackingRoute {
  const TrackingRoute({
    required this.polyline,
    required this.distanceText,
    required this.durationText,
  });

  final String polyline;
  final String distanceText;
  final String durationText;

  static TrackingRoute? fromJsonOrNull(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    final polyline = asString(m['polyline']);
    if (polyline.isEmpty) return null;
    return TrackingRoute(
      polyline: polyline,
      distanceText: asString(m['distanceText']),
      durationText: asString(m['durationText']),
    );
  }
}

/// A tracking snapshot for one transaction, from `GET /transactions/:id/tracking`.
class TransactionTracking {
  const TransactionTracking({
    required this.transactionId,
    required this.status,
    this.buyerLocation,
    this.sellerCurrentLocation,
    this.route,
    this.lastUpdatedAt,
    required this.isSeller,
    this.isDeliveryActor = false,
    this.pickupConfirmedAt,
    this.nearBuyerAt,
  });

  final String transactionId;
  final String status; // raw backend status — pair with ApiTxStatus.fromApi
  final TrackingLocation? buyerLocation;
  final TrackingLocation? sellerCurrentLocation;
  final TrackingRoute? route;
  final DateTime? lastUpdatedAt;

  /// Whether the signed-in user is the seller on this transaction — decided
  /// server-side, so the client never needs its own "who am I" lookup.
  final bool isSeller;

  /// Whether the signed-in user is the party who actually handles pickup +
  /// delivery — the self-delivering seller, or the assigned Hoppr dispatcher.
  /// Screens driving pickup/delivery actions (e.g. Confirm Delivery) should
  /// gate on this instead of [isSeller], so a real dispatcher can use them.
  final bool isDeliveryActor;

  /// When the seller → dispatcher pickup handoff was confirmed — null until
  /// then, and always null for self-delivery (no pickup step).
  final DateTime? pickupConfirmedAt;

  /// When the dispatcher first entered the buyer's delivery geofence — null
  /// until then. Drives the "nearby" step on the Track Package timeline.
  final DateTime? nearBuyerAt;

  bool get hasBuyerLocation => buyerLocation != null;
  bool get hasSellerLocation => sellerCurrentLocation != null;
  bool get hasRoute => route != null;

  factory TransactionTracking.fromJson(Map<String, dynamic> j) =>
      TransactionTracking(
        transactionId: asString(j['transactionId']),
        status: asString(j['status']),
        buyerLocation: TrackingLocation.fromJsonOrNull(j['buyerLocation']),
        sellerCurrentLocation: TrackingLocation.fromJsonOrNull(
          j['sellerCurrentLocation'],
        ),
        route: TrackingRoute.fromJsonOrNull(j['route']),
        lastUpdatedAt: asDateTime(j['lastUpdatedAt']),
        isSeller: asBool(j['isSeller']),
        isDeliveryActor: asBool(j['isDeliveryActor']),
        pickupConfirmedAt: asDateTime(j['pickupConfirmedAt']),
        nearBuyerAt: asDateTime(j['nearBuyerAt']),
      );
}
