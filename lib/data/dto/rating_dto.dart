import '../../core/network/json.dart';

/// The signed-in user's own rating of the other party on one transaction —
/// null (via nullable factory usage at the call site) means "not rated yet".
class TransactionRating {
  const TransactionRating({
    required this.id,
    required this.stars,
    this.comment,
    required this.createdAt,
  });

  final String id;
  final int stars;
  final String? comment;
  final DateTime? createdAt;

  factory TransactionRating.fromJson(Map<String, dynamic> j) =>
      TransactionRating(
        id: asId(j['id'] ?? j['_id']),
        stars: asInt(j['stars']),
        comment: asStringOrNull(j['comment']),
        createdAt: asDateTime(j['createdAt']),
      );
}

/// One review row on a profile's "Ratings & Reviews" section.
class RatingItem {
  const RatingItem({
    required this.id,
    required this.stars,
    this.comment,
    required this.raterName,
    required this.createdAt,
  });

  final String id;
  final int stars;
  final String? comment;
  final String raterName;
  final DateTime? createdAt;

  factory RatingItem.fromJson(Map<String, dynamic> j) => RatingItem(
    id: asId(j['id'] ?? j['_id']),
    stars: asInt(j['stars']),
    comment: asStringOrNull(j['comment']),
    raterName: asString(j['raterName'], 'A Hoppr user'),
    createdAt: asDateTime(j['createdAt']),
  );
}

/// Aggregate + a page of reviews for one user, as shown on the Merchant
/// Profile screen. `average` is null (never 0) when nobody has rated this
/// user yet — the two states must never be confused.
class RatingSummary {
  const RatingSummary({
    required this.average,
    required this.count,
    required this.items,
    required this.page,
    required this.limit,
    required this.hasMore,
  });

  final double? average;
  final int count;
  final List<RatingItem> items;
  final int page;
  final int limit;
  final bool hasMore;

  static const empty = RatingSummary(
    average: null,
    count: 0,
    items: [],
    page: 1,
    limit: 5,
    hasMore: false,
  );

  factory RatingSummary.fromJson(Map<String, dynamic> j) => RatingSummary(
    average: j['average'] == null ? null : asDouble(j['average']),
    count: asInt(j['count']),
    items: asList(
      j['items'],
    ).map((e) => RatingItem.fromJson(asMap(e))).toList(growable: false),
    page: asInt(j['page'], 1),
    limit: asInt(j['limit'], 5),
    hasMore: asBool(j['hasMore']),
  );
}
