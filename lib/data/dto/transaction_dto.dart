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
  const TxPage({required this.items, required this.page, required this.hasMore});

  final List<ApiTransaction> items;
  final int page;
  final bool hasMore;

  factory TxPage.fromJson(Map<String, dynamic> j) => TxPage(
        items: asList(j['items'])
            .map((e) => ApiTransaction.fromJson(asMap(e)))
            .toList(growable: false),
        page: asInt(j['page'], 1),
        hasMore: asBool(j['hasMore']),
      );
}

/// One entry from a transaction's audit timeline.
class TxTimelineEvent {
  const TxTimelineEvent({required this.event, this.at});

  final String event;
  final DateTime? at;

  factory TxTimelineEvent.fromJson(Map<String, dynamic> j) => TxTimelineEvent(
        event: asString(j['event']),
        at: asDateTime(j['at']),
      );
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
    required this.feeSplit,
    required this.currency,
    required this.inspectionPeriodSeconds,
    this.coolingEndsAt,
    required this.createdAt,
    this.updatedAt,
    this.timeline = const [],
    this.trackingCarrier,
    this.trackingNumber,
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
  final String feeSplit; // buyer | split | seller
  final String currency;

  final int inspectionPeriodSeconds;
  final DateTime? coolingEndsAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  final List<TxTimelineEvent> timeline;
  final String? trackingCarrier;
  final String? trackingNumber;

  double get itemSubtotalNaira => itemSubtotalKobo / 100;
  double get deliveryFeeNaira => deliveryFeeKobo / 100;
  double get grandTotalNaira => grandTotalKobo / 100;

  factory ApiTransaction.fromJson(Map<String, dynamic> j) {
    final delivery = asMap(j['delivery']);
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
      feeSplit: asString(j['feeSplit'], 'split'),
      currency: asString(j['currency'], 'NGN'),
      inspectionPeriodSeconds: asInt(j['inspectionPeriodSeconds'], 86400),
      coolingEndsAt: asDateTime(j['coolingEndsAt']),
      createdAt: asDateTime(j['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: asDateTime(j['updatedAt']),
      timeline: asList(j['timeline'])
          .map((e) => TxTimelineEvent.fromJson(asMap(e)))
          .toList(growable: false),
      trackingCarrier: asStringOrNull(delivery['trackingCarrier']),
      trackingNumber: asStringOrNull(delivery['trackingNumber']),
    );
  }
}
