import '../../data/dto/transaction_dto.dart';

/// Real, backend-derived Home/Profile dashboard numbers — computed directly
/// from the user's already-fetched live transaction list, never a separate
/// cached/fake aggregate. This guarantees the stat cards always agree with
/// the transaction list rendered on the same screen.
class DashboardStats {
  const DashboardStats({
    required this.protectedNaira,
    required this.active,
    required this.cooling,
  });

  final double protectedNaira;
  final int active;
  final int cooling;

  static const zero = DashboardStats(protectedNaira: 0, active: 0, cooling: 0);

  /// Money still locked in escrow for this transaction — funded through
  /// cooling/dispute, before it's released or refunded. Included regardless
  /// of the signed-in user's role (buyer or seller) on each transaction, so
  /// this reflects total exposure, not just seller-side holdings.
  static const _protectedStatuses = {
    ApiTxStatus.paymentReceived,
    ApiTxStatus.inTransit,
    ApiTxStatus.outForDelivery,
    ApiTxStatus.cooling,
    ApiTxStatus.disputed,
  };

  /// "Active" = paid and moving toward delivery, not yet in cooling.
  static const _activeStatuses = {
    ApiTxStatus.paymentReceived,
    ApiTxStatus.inTransit,
    ApiTxStatus.outForDelivery,
  };

  factory DashboardStats.fromTransactions(List<ApiTransaction> list) {
    var protectedNaira = 0.0;
    var active = 0;
    var cooling = 0;
    for (final t in list) {
      if (_protectedStatuses.contains(t.status)) {
        protectedNaira += t.grandTotalNaira;
      }
      if (_activeStatuses.contains(t.status)) active++;
      if (t.status == ApiTxStatus.cooling) cooling++;
    }
    return DashboardStats(
      protectedNaira: protectedNaira,
      active: active,
      cooling: cooling,
    );
  }
}

/// Letter grade from a raw 0–100 trust score. Mirrors the backend's own
/// `trustGradeFor` thresholds (user.model.ts) exactly — computed here rather
/// than trusting the backend's separately-*stored* `trustGrade` string, which
/// can go stale (it's only recalculated on a full document `.save()`, but
/// `release()` bumps `trustScore` via a raw `$inc` that bypasses that hook).
/// The raw `trustScore` number itself is always live.
String trustGradeFor(int score) {
  if (score >= 95) return 'A+';
  if (score >= 85) return 'A';
  if (score >= 70) return 'B';
  if (score >= 50) return 'C';
  return 'D';
}

/// Real trust-score label: a letter grade once the user has at least one
/// completed deal to base it on; otherwise "New" rather than a
/// fabricated-looking default grade for a brand-new account (the backend's
/// default `trustScore` is 80 → grade "B" — misleading with zero history).
String trustScoreLabel({required int deals, required int trustScore}) =>
    deals > 0 ? trustGradeFor(trustScore) : 'New';

/// Time-of-day greeting word (no name attached — the caller adds that).
/// 05:00–11:59 Morning · 12:00–16:59 Afternoon · 17:00–20:59 Evening ·
/// 21:00–04:59 Night.
String greetingWordFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 17) return 'Good Afternoon';
  if (hour >= 17 && hour < 21) return 'Good Evening';
  return 'Good Night';
}
