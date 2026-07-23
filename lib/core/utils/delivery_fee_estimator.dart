import 'dart:math';

/// Client-side PREVIEW of the HTP Delivery Fee — mirrors the backend's
/// formula/weight-parser exactly (see backend
/// `common/utils/deliveryFee.ts` + `modules/transaction/deliveryFee.service.ts`)
/// so Payment Setup can show a number before the transaction exists. This is
/// only ever a preview: the backend recomputes and is the authoritative
/// source once the transaction is actually created (see
/// PaymentSetupScreen._generate(), which overwrites the draft with the real
/// backend figure). Never trust this value for money movement.
class DeliveryFeeEstimator {
  DeliveryFeeEstimator._();

  // ── Tunable rates (naira) — MUST stay in sync with the backend constants
  // in common/utils/deliveryFee.ts. Kept in naira here (not kobo) to match
  // this app's existing convention of doing money math in naira on-screen
  // (see PaymentDraft) and converting to kobo only at the network boundary.
  static const double baseFee = 500; // ₦500
  static const double perKmFee = 150; // ₦150/km
  static const double freeWeightKg = 2;
  static const double extraWeightFeePerKg = 200; // ₦200/kg
  static const double minimumFee = 500; // ₦500

  /// Great-circle distance between two coordinates, in kilometres — same
  /// haversine math as the backend's common/utils/geo.ts.
  static double distanceKm(double aLat, double aLng, double bLat, double bLng) {
    const r = 6371.0; // km
    double toRad(double d) => d * pi / 180;
    final dLat = toRad(bLat - aLat);
    final dLng = toRad(bLng - aLng);
    final lat1 = toRad(aLat);
    final lat2 = toRad(bLat);
    final h =
        pow(sin(dLat / 2), 2) + pow(sin(dLng / 2), 2) * cos(lat1) * cos(lat2);
    return 2 * r * asin(sqrt(h));
  }

  /// Recommended MVP formula (client-approved), identical to the backend:
  ///   distanceFee = ceil(distanceKm) * perKmFee
  ///   extraWeightKg = max(0, ceil(weightKg - freeWeightKg))
  ///   weightFee = extraWeightKg * extraWeightFeePerKg
  ///   deliveryFee = max(minimumFee, baseFee + distanceFee + weightFee)
  static double computeFee({
    required double distanceKm,
    required double weightKg,
  }) {
    final dKm = distanceKm < 0 ? 0.0 : distanceKm;
    final wKg = weightKg < 0 ? 0.0 : weightKg;
    final distanceFee = dKm.ceil() * perKmFee;
    final extraWeightKg = max(0, (wKg - freeWeightKg).ceil());
    final weightFee = extraWeightKg * extraWeightFeePerKg;
    return max(minimumFee, baseFee + distanceFee + weightFee);
  }

  /// Parses a freeform package-weight string into kilograms:
  ///   "1 kg" -> 1, "1.5kg" -> 1.5, "500 g" -> 0.5, "2" -> 2 (bare = kg)
  /// Returns null for missing/invalid/non-positive input — same contract as
  /// the backend's parseWeightKg.
  static double? parseWeightKg(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(kg|g)?$').firstMatch(trimmed);
    if (match == null) return null;
    final value = double.tryParse(match.group(1)!);
    if (value == null || value <= 0) return null;
    return match.group(2) == 'g' ? value / 1000 : value;
  }
}
