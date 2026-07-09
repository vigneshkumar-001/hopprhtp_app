import '../../core/network/json.dart';

/// Home-tab bucket, derived server-side from [ApiTxStatus].
enum ApiTxStage {
  active,
  cooling,
  done;

  static ApiTxStage fromApi(String? s) => switch (s) {
    'cooling' => ApiTxStage.cooling,
    'done' => ApiTxStage.done,
    _ => ApiTxStage.active,
  };

  String get label => switch (this) {
    ApiTxStage.active => 'Active',
    ApiTxStage.cooling => 'Cooling',
    ApiTxStage.done => 'Done',
  };
}

/// The canonical 16-state lifecycle status — a 1:1 mirror of the backend
/// `TX_STATUSES`. [unknown] guards against a future server status the app
/// hasn't shipped support for yet.
enum ApiTxStatus {
  draft,
  awaitingAgreement,
  awaitingPayment,
  paymentReceived,
  awaitingDispatch,
  inTransit,
  outForDelivery,
  delivered,
  cooling,
  released,
  completed,
  disputed,
  refunded,
  returned,
  cancelled,
  undeliverable,
  unknown;

  static ApiTxStatus fromApi(String? s) => switch (s) {
    'draft' => ApiTxStatus.draft,
    'awaiting_agreement' => ApiTxStatus.awaitingAgreement,
    'awaiting_payment' => ApiTxStatus.awaitingPayment,
    'payment_received' => ApiTxStatus.paymentReceived,
    'awaiting_dispatch' => ApiTxStatus.awaitingDispatch,
    'in_transit' => ApiTxStatus.inTransit,
    'out_for_delivery' => ApiTxStatus.outForDelivery,
    'delivered' => ApiTxStatus.delivered,
    'cooling' => ApiTxStatus.cooling,
    'released' => ApiTxStatus.released,
    'completed' => ApiTxStatus.completed,
    'disputed' => ApiTxStatus.disputed,
    'refunded' => ApiTxStatus.refunded,
    'returned' => ApiTxStatus.returned,
    'cancelled' => ApiTxStatus.cancelled,
    'undeliverable' => ApiTxStatus.undeliverable,
    _ => ApiTxStatus.unknown,
  };

  String get label => switch (this) {
    ApiTxStatus.draft => 'Draft',
    ApiTxStatus.awaitingAgreement => 'Awaiting agreement',
    ApiTxStatus.awaitingPayment => 'Awaiting payment',
    ApiTxStatus.paymentReceived => 'Payment received',
    ApiTxStatus.awaitingDispatch => 'Awaiting dispatch',
    ApiTxStatus.inTransit => 'In transit',
    ApiTxStatus.outForDelivery => 'Out for delivery',
    ApiTxStatus.delivered => 'Delivered',
    ApiTxStatus.cooling => 'Cooling',
    ApiTxStatus.released => 'Funds released',
    ApiTxStatus.completed => 'Completed',
    ApiTxStatus.disputed => 'In dispute',
    ApiTxStatus.refunded => 'Refunded',
    ApiTxStatus.returned => 'Returned',
    ApiTxStatus.cancelled => 'Cancelled',
    ApiTxStatus.undeliverable => 'Undeliverable',
    ApiTxStatus.unknown => 'Unknown',
  };
}

/// A page of transactions for the infinite-scroll history.
class TxPage {
  const TxPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<ApiTransaction> items;
  final int page;
  final bool hasMore;

  factory TxPage.fromJson(Map<String, dynamic> j) => TxPage(
    items: asList(
      j['items'],
    ).map((e) => ApiTransaction.fromJson(asMap(e))).toList(growable: false),
    page: asInt(j['page'], 1),
    hasMore: asBool(j['hasMore']),
  );
}

/// One entry from a transaction's audit timeline.
class TxTimelineEvent {
  const TxTimelineEvent({required this.event, this.at});

  final String event;
  final DateTime? at;

  factory TxTimelineEvent.fromJson(Map<String, dynamic> j) =>
      TxTimelineEvent(event: asString(j['event']), at: asDateTime(j['at']));
}

/// An escrow transaction. Parses both the lean list shape (`_id`, no `id`
/// virtual) and the full detail shape (`id`, timeline, delivery). Money is in
/// kobo; the `*Naira` getters are display conveniences only.
class ApiTransaction {
  const ApiTransaction({
    required this.id,
    required this.code,
    required this.reference,
    required this.merchantName,
    required this.productName,
    this.variant,
    required this.status,
    required this.stage,
    required this.itemSubtotalKobo,
    required this.deliveryFeeKobo,
    required this.grandTotalKobo,
    required this.trustFullKobo,
    this.buyerTrustShareKobo,
    required this.feeSplit,
    required this.currency,
    required this.inspectionPeriodSeconds,
    this.coolingEndsAt,
    required this.createdAt,
    this.updatedAt,
    this.timeline = const [],
    this.trackingCarrier,
    this.trackingNumber,
    this.buyerContact,
    this.buyerName,
    this.deliveryAddress,
    this.deliveryLat,
    this.deliveryLng,
    this.estimatedDeliveryDate,
    this.estimatedDeliveryTime,
    this.productPhotoUrl,
    this.weight,
    this.waybillTrackingNumber,
    this.myRole,
    this.isSeller = false,
    this.isBuyer = false,
    this.sellerId,
  });

  final String id;
  final String code; // e.g. HTP-7Q2K
  final String reference;
  final String merchantName;
  final String productName;
  final String? variant;

  final ApiTxStatus status;
  final ApiTxStage stage;

  final int itemSubtotalKobo;
  final int deliveryFeeKobo;
  final int grandTotalKobo;
  final int trustFullKobo;

  /// The buyer's share of the trust/protection fee (may be less than
  /// [trustFullKobo] when the seller absorbs part of it — see [feeSplit]).
  /// Null on older/legacy records; callers should fall back to [trustFullKobo].
  final int? buyerTrustShareKobo;
  final String feeSplit; // buyer | split | seller
  final String currency;

  final int inspectionPeriodSeconds;
  final DateTime? coolingEndsAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  final List<TxTimelineEvent> timeline;
  final String? trackingCarrier;
  final String? trackingNumber;
  final String? buyerContact;
  final String? buyerName;
  final String? deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? estimatedDeliveryDate;
  final String? estimatedDeliveryTime;

  /// The product photo (the item being sold), from `consignments[].productPhotoUrl`.
  /// For older records created before that field existed, it falls back to the
  /// dispatch/waybill photo — new records always carry `productPhotoUrl`, so
  /// those three remain separate fields and are never conflated going forward.
  final String? productPhotoUrl;

  /// Package weight as entered by the seller at creation (freeform, e.g.
  /// "2.5kg") — from `consignments[].weight`. Null when not provided.
  final String? weight;

  /// Courier/waybill tracking number captured at creation — from
  /// `consignments[].waybillTrackingNumber`. Distinct from [trackingNumber]
  /// (set later, on dispatch). Null when not provided.
  final String? waybillTrackingNumber;

  /// Per-transaction role of the signed-in user, computed by the backend from
  /// this transaction only (there is no global buyer/seller account type). The
  /// same user can be seller on one transaction and buyer on another.
  final String? myRole; // 'seller' | 'buyer' | null
  final bool isSeller;
  final bool isBuyer;

  /// The transaction creator's user id — lets the buyer's side navigate to a
  /// real Merchant Profile. Null on shapes that don't carry it (defensive
  /// only; every live transaction has a sellerId).
  final String? sellerId;

  double get itemSubtotalNaira => itemSubtotalKobo / 100;
  double get deliveryFeeNaira => deliveryFeeKobo / 100;
  double get grandTotalNaira => grandTotalKobo / 100;
  double get trustFullNaira => trustFullKobo / 100;

  /// The trust fee actually payable by the buyer — [buyerTrustShareKobo] when
  /// the backend provided it, else the full fee (older records / seller-paid
  /// split where the buyer's share equals the full amount shown).
  double get buyerTrustShareNaira =>
      (buyerTrustShareKobo ?? trustFullKobo) / 100;

  /// True once the buyer's delivery address has real coordinates (set from the
  /// map picker at creation). Screens must gate any map/tracking UI on this —
  /// older transactions created before this field existed will have neither.
  bool get hasDeliveryLocation => deliveryLat != null && deliveryLng != null;

  factory ApiTransaction.fromJson(Map<String, dynamic> j) {
    final delivery = asMap(j['delivery']);
    final consignments = asList(j['consignments']);
    final firstConsignment = consignments.isNotEmpty
        ? asMap(consignments.first)
        : const <String, dynamic>{};
    return ApiTransaction(
      id: asId(j['id'] ?? j['_id']),
      code: asString(j['code']),
      reference: asString(j['reference']),
      merchantName: asString(j['merchantName']),
      productName: asString(j['productName']),
      variant: asStringOrNull(j['variant']),
      status: ApiTxStatus.fromApi(asStringOrNull(j['status'])),
      stage: ApiTxStage.fromApi(asStringOrNull(j['stage'])),
      itemSubtotalKobo: asInt(j['itemSubtotalKobo']),
      deliveryFeeKobo: asInt(j['deliveryFeeKobo']),
      grandTotalKobo: asInt(j['grandTotalKobo']),
      trustFullKobo: asInt(j['trustFullKobo']),
      buyerTrustShareKobo: j['buyerTrustShareKobo'] == null
          ? null
          : asInt(j['buyerTrustShareKobo']),
      feeSplit: asString(j['feeSplit'], 'split'),
      currency: asString(j['currency'], 'NGN'),
      inspectionPeriodSeconds: asInt(j['inspectionPeriodSeconds'], 86400),
      coolingEndsAt: asDateTime(j['coolingEndsAt']),
      createdAt:
          asDateTime(j['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: asDateTime(j['updatedAt']),
      timeline: asList(
        j['timeline'],
      ).map((e) => TxTimelineEvent.fromJson(asMap(e))).toList(growable: false),
      trackingCarrier: asStringOrNull(delivery['trackingCarrier']),
      trackingNumber: asStringOrNull(delivery['trackingNumber']),
      buyerContact:
          asStringOrNull(j['buyerContact']) ??
          asStringOrNull(firstConsignment['buyerContact']),
      buyerName: asStringOrNull(firstConsignment['buyerName']),
      deliveryAddress: asStringOrNull(firstConsignment['deliveryAddress']),
      deliveryLat: firstConsignment['deliveryLat'] == null
          ? null
          : asDouble(firstConsignment['deliveryLat']),
      deliveryLng: firstConsignment['deliveryLng'] == null
          ? null
          : asDouble(firstConsignment['deliveryLng']),
      estimatedDeliveryDate: asStringOrNull(
        firstConsignment['estimatedDeliveryDate'],
      ),
      estimatedDeliveryTime: asStringOrNull(
        firstConsignment['estimatedDeliveryTime'],
      ),
      // New records use productPhotoUrl; dispatch/waybill are only a fallback
      // for older records that predate the dedicated product-photo field.
      productPhotoUrl:
          asStringOrNull(firstConsignment['productPhotoUrl']) ??
          asStringOrNull(firstConsignment['dispatchPhotoUrl']) ??
          asStringOrNull(firstConsignment['waybillImageUrl']),
      weight: asStringOrNull(firstConsignment['weight']),
      waybillTrackingNumber: asStringOrNull(
        firstConsignment['waybillTrackingNumber'],
      ),
      myRole: asStringOrNull(j['myRole']),
      // Prefer explicit booleans; fall back to deriving them from myRole so the
      // DTO is correct whichever shape the backend sends.
      isSeller: j['isSeller'] != null
          ? asBool(j['isSeller'])
          : asStringOrNull(j['myRole']) == 'seller',
      isBuyer: j['isBuyer'] != null
          ? asBool(j['isBuyer'])
          : asStringOrNull(j['myRole']) == 'buyer',
      sellerId: j['sellerId'] == null ? null : asId(j['sellerId']),
    );
  }
}
