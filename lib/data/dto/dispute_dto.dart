import '../../core/network/json.dart';

class DisputeEvidence {
  const DisputeEvidence({required this.type, this.url, this.note});

  final String type; // 'image' | 'document' | 'text'
  final String? url;
  final String? note;

  factory DisputeEvidence.fromJson(Map<String, dynamic> j) => DisputeEvidence(
    type: asString(j['type']),
    url: asStringOrNull(j['url']),
    note: asStringOrNull(j['note']),
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    if (url != null) 'url': url,
    if (note != null) 'note': note,
  };
}

/// Deterministic first-pass evidence pre-screen ("Hoppr Vision") — a real,
/// backend-persisted heuristic, not a Flutter-side fabrication. Presented to
/// the user as an automated first pass, not a final decision.
class DisputeAiAssessment {
  const DisputeAiAssessment({
    required this.evidenceCompleteness,
    required this.fraudRiskScore,
    required this.summary,
    this.assessedAt,
  });

  final double evidenceCompleteness;
  final double fraudRiskScore;
  final String summary;
  final DateTime? assessedAt;

  static DisputeAiAssessment? fromJsonOrNull(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    return DisputeAiAssessment(
      evidenceCompleteness: asDouble(m['evidenceCompleteness']),
      fraudRiskScore: asDouble(m['fraudRiskScore']),
      summary: asString(m['summary']),
      assessedAt: asDateTime(m['assessedAt']),
    );
  }
}

class DisputeResponse {
  const DisputeResponse({
    required this.respondedByRole,
    required this.message,
    this.respondedAt,
  });

  final String respondedByRole; // 'buyer' | 'seller'
  final String message;
  final DateTime? respondedAt;

  static DisputeResponse? fromJsonOrNull(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    return DisputeResponse(
      respondedByRole: asString(m['respondedByRole']),
      message: asString(m['message']),
      respondedAt: asDateTime(m['respondedAt']),
    );
  }
}

class DisputeResolution {
  const DisputeResolution({required this.outcome, this.note, this.at});

  final String outcome; // 'buyer_favored' | 'seller_favored'
  final String? note;
  final DateTime? at;

  static DisputeResolution? fromJsonOrNull(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    return DisputeResolution(
      outcome: asString(m['outcome']),
      note: asStringOrNull(m['note']),
      at: asDateTime(m['at']),
    );
  }
}

/// A real dispute record. Every field traces to the backend `Dispute` model —
/// display-only labels (e.g. [displayStatus]) are derived here rather than
/// the backend inventing new persisted status values it doesn't otherwise need.
class Dispute {
  const Dispute({
    required this.id,
    required this.code,
    required this.transactionId,
    required this.raisedByRole,
    required this.category,
    this.reason,
    required this.status,
    this.evidence = const [],
    this.ai,
    this.response,
    this.resolution,
    required this.createdAt,
  });

  final String id;
  final String code;
  final String transactionId;
  final String raisedByRole; // 'buyer' | 'seller'
  final String category;
  final String? reason;
  final String status; // 'raised' | 'under_review' | 'frozen' | 'resolved'
  final List<DisputeEvidence> evidence;
  final DisputeAiAssessment? ai;
  final DisputeResponse? response;
  final DisputeResolution? resolution;
  final DateTime createdAt;

  bool get isResolved => status == 'resolved';
  bool get hasResponse => response != null;

  /// A friendly, human label derived from the real status/response/resolution
  /// — not a new backend enum value.
  String get displayStatus {
    if (isResolved && resolution != null) {
      return resolution!.outcome == 'buyer_favored'
          ? 'Resolved — refunded to buyer'
          : 'Resolved — released to seller';
    }
    if (isResolved) return 'Resolved';
    if (hasResponse) return 'Responded — under review';
    return 'Under review';
  }

  static const _categoryLabels = {
    'item_not_as_described': 'Item not as described',
    'not_delivered': 'Not delivered',
    'damaged_item': 'Damaged item',
    'fraud': 'Fraud',
    'other': 'Other',
  };

  String get categoryLabel => _categoryLabels[category] ?? category;

  factory Dispute.fromJson(Map<String, dynamic> j) => Dispute(
    id: asId(j['id'] ?? j['_id']),
    code: asString(j['code']),
    transactionId: asId(j['transactionId']),
    raisedByRole: asString(j['raisedByRole']),
    category: asString(j['category']),
    reason: asStringOrNull(j['reason']),
    status: asString(j['status']),
    evidence: asList(
      j['evidence'],
    ).map((e) => DisputeEvidence.fromJson(asMap(e))).toList(growable: false),
    ai: DisputeAiAssessment.fromJsonOrNull(j['ai']),
    response: DisputeResponse.fromJsonOrNull(j['response']),
    resolution: DisputeResolution.fromJsonOrNull(j['resolution']),
    createdAt:
        asDateTime(j['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}
