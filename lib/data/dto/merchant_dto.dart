import '../../core/network/json.dart';

/// One row in a merchant's redacted recent-activity feed — never carries
/// buyer contact/address (this is shown to any viewer, not just the
/// merchant's own counterparties).
class MerchantRecentTransaction {
  const MerchantRecentTransaction({
    required this.id,
    required this.code,
    required this.productName,
    required this.amountKobo,
    required this.status,
    required this.createdAt,
    this.productPhotoUrl,
  });

  final String id;
  final String code;
  final String productName;
  final int amountKobo;
  final String status; // raw backend TxStatus string
  final DateTime? createdAt;
  final String? productPhotoUrl;

  double get amountNaira => amountKobo / 100;

  factory MerchantRecentTransaction.fromJson(Map<String, dynamic> j) =>
      MerchantRecentTransaction(
        id: asId(j['id'] ?? j['_id']),
        code: asString(j['code']),
        productName: asString(j['productName']),
        amountKobo: asInt(j['amountKobo']),
        status: asString(j['status']),
        createdAt: asDateTime(j['createdAt']),
        productPhotoUrl: asStringOrNull(j['productPhotoUrl']),
      );
}

/// Real (never fabricated) merchant stats — `completedTransactions`/
/// `trustScore` mirror the backend's own running counters (bumped on
/// release()), the rest are live counts scoped to this merchant's sales.
class MerchantStats {
  const MerchantStats({
    required this.completedTransactions,
    required this.activeTransactions,
    required this.coolingTransactions,
    required this.disputeCount,
    required this.trustScore,
    required this.trustGrade,
  });

  final int completedTransactions;
  final int activeTransactions;
  final int coolingTransactions;
  final int disputeCount;
  final int trustScore;
  final String trustGrade;

  /// "New" until the merchant has at least one completed deal — mirrors
  /// `trustScoreLabel()` in `features/home/dashboard_stats.dart` exactly, so
  /// the label never disagrees between Profile and Merchant Profile.
  String get trustLabel => completedTransactions > 0 ? trustGrade : 'New';

  factory MerchantStats.fromJson(Map<String, dynamic> j) => MerchantStats(
    completedTransactions: asInt(j['completedTransactions']),
    activeTransactions: asInt(j['activeTransactions']),
    coolingTransactions: asInt(j['coolingTransactions']),
    disputeCount: asInt(j['disputeCount']),
    trustScore: asInt(j['trustScore']),
    trustGrade: asString(j['trustGrade'], 'D'),
  );
}

/// A merchant's public-safe profile — identity, real stats, and a redacted
/// recent-activity feed. Backend is the sole source of truth; never patch in
/// placeholder values here.
class MerchantProfile {
  const MerchantProfile({
    required this.id,
    required this.name,
    required this.verificationStatus,
    this.joinedAt,
    required this.isOwner,
    required this.stats,
    this.recentTransactions = const [],
  });

  final String id;
  final String name;
  final String verificationStatus; // unverified | pending | verified | rejected
  final DateTime? joinedAt;
  final bool isOwner;
  final MerchantStats stats;
  final List<MerchantRecentTransaction> recentTransactions;

  bool get isVerified => verificationStatus == 'verified';

  factory MerchantProfile.fromJson(Map<String, dynamic> j) {
    final merchant = asMap(j['merchant']);
    return MerchantProfile(
      id: asId(merchant['id'] ?? merchant['_id']),
      name: asString(merchant['name'], 'Merchant'),
      verificationStatus: asString(
        merchant['verificationStatus'],
        'unverified',
      ),
      joinedAt: asDateTime(merchant['joinedAt']),
      isOwner: asBool(merchant['isOwner']),
      stats: MerchantStats.fromJson(asMap(j['stats'])),
      recentTransactions: asList(j['recentTransactions'])
          .map((e) => MerchantRecentTransaction.fromJson(asMap(e)))
          .toList(growable: false),
    );
  }
}
