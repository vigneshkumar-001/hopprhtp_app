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
  readyForPickup,
  dispatcherGoingToPickup,
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
    'ready_for_pickup' => ApiTxStatus.readyForPickup,
    'dispatcher_going_to_pickup' => ApiTxStatus.dispatcherGoingToPickup,
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
    ApiTxStatus.readyForPickup => 'Ready for pickup',
    ApiTxStatus.dispatcherGoingToPickup =>
      'Dispatcher going to collection point',
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
    this.sellerTrustShareKobo,
    this.sellerReceivableKobo,
    required this.feeSplit,
    this.platformFeePayer = 'split_50_50',
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
    this.dispatcherName,
    this.dispatcherPhone,
    this.productPhotoUrl,
    this.weight,
    this.waybillTrackingNumber,
    this.myRole,
    this.isSeller = false,
    this.isBuyer = false,
    this.isDispatcher = false,
    this.sellerId,
    this.buyerId,
    this.dispatcherAccountId,
    this.dispatcherAccountName,
    this.dispatcherAccountPhone,
    this.dispatcherAccountStatus,
    this.dispatcherMode,
    this.pickupConfirmedAt,
    this.nearBuyerAt,
    this.deliveryConfirmedAt,
    this.dispatcherAddress,
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

  /// The buyer's share of the platform fee (may be less than [trustFullKobo]
  /// when the seller absorbs part of it — see [platformFeePayer]). Null on
  /// older/legacy records; callers should fall back to [trustFullKobo].
  final int? buyerTrustShareKobo;

  /// The seller's share of the platform fee. Null on older/legacy records.
  final int? sellerTrustShareKobo;

  /// What the seller actually receives once released — itemSubtotalKobo net
  /// of [sellerTrustShareKobo]. Backend-computed (see transactionService's
  /// feeView()), never re-derived client-side once a real transaction
  /// exists. Null on older/legacy records.
  final int? sellerReceivableKobo;

  /// Internal storage value — 'buyer' | 'split' | 'seller'. Prefer
  /// [platformFeePayer] (the same decision, public-API naming) for display.
  final String feeSplit;

  /// Who pays the Hoppr Platform Fee — 'buyer' | 'seller' | 'split_50_50'.
  /// A decision entirely separate from delivery method/dispatcherMode.
  final String platformFeePayer;
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

  /// The courier arranged by the seller (entered at Create Transaction, from
  /// `consignments[].payout`) — distinct from the buyer/seller themselves.
  /// Null until a dispatcher has actually been assigned.
  final String? dispatcherName;
  final String? dispatcherPhone;

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
  final String? myRole; // 'seller' | 'buyer' | 'dispatcher' | null
  final bool isSeller;
  final bool isBuyer;
  final bool isDispatcher;

  /// The transaction creator's user id — lets the buyer's side navigate to a
  /// real Merchant Profile. Null on shapes that don't carry it (defensive
  /// only; every live transaction has a sellerId).
  final String? sellerId;

  /// The linked buyer account id, once a real Hoppr user has been matched by
  /// phone (see backend transaction.service.ts create()/attachBuyerToPendingByPhone).
  /// Null until then — screens show a professional fallback, never a guess.
  final String? buyerId;

  /// The assigned Hoppr dispatcher ACCOUNT id/phone/status — entirely
  /// distinct from [dispatcherName]/[dispatcherPhone] above, which are the
  /// courier's free-text payout contact and never imply a real account.
  /// Null [dispatcherAccountId] means no dispatcher account is linked yet
  /// (either none was assigned, or the phone hasn't registered on Hoppr).
  final String? dispatcherAccountId;

  /// Seller-entered dispatcher name (request_hoppr_dispatcher only) — shown
  /// as a fallback ("[name] — not registered yet") before the account links.
  final String? dispatcherAccountName;
  final String? dispatcherAccountPhone;
  final String? dispatcherAccountStatus; // 'assigned' | 'pending_registration'

  /// 'seller_self_delivery' | 'request_hoppr_dispatcher'. Null on
  /// legacy/lean-list shapes that don't carry it — treat as self-delivery.
  final String? dispatcherMode;
  bool get isSelfDelivery => dispatcherMode != 'request_hoppr_dispatcher';

  /// True only for the seller on a 'seller_self_delivery' transaction — a
  /// Hoppr-Dispatcher-mode seller is NOT this, even though they're still
  /// [isSeller]. Distinguishes the two so seller-only UI (pickup code share)
  /// never gets confused with dispatcher-only UI (pickup OTP entry).
  bool get isSelfDeliverySeller => isSeller && isSelfDelivery;

  /// Seller → dispatcher pickup handoff timestamp — null until confirmed,
  /// always null for self-delivery (no pickup step).
  final DateTime? pickupConfirmedAt;

  /// First time the dispatcher entered the buyer's delivery geofence.
  final DateTime? nearBuyerAt;

  /// Dispatcher/seller → buyer delivery handoff timestamp.
  final DateTime? deliveryConfirmedAt;

  /// Where the dispatcher collects the package from — from
  /// `consignments[].dispatcherAddress`, entered by the seller at creation.
  /// There is no separate "pickup address" concept in this app; only this
  /// and [deliveryAddress] exist. Shown in the UI as "Package Collection
  /// Address" — never "Dispatcher Address" or "Pickup Address".
  final String? dispatcherAddress;

  /// Whoever actually handles pickup + delivery for this transaction — the
  /// self-delivering seller, or the assigned Hoppr dispatcher. Screens
  /// driving pickup/delivery actions should gate on this instead of
  /// [isSeller] alone: in Hoppr-Dispatcher mode the seller is NOT the
  /// delivery actor (the dispatcher is), so `isSeller || isDispatcher` was
  /// wrong here — it made every seller a delivery actor regardless of mode,
  /// which is exactly what let a Hoppr-Dispatcher-mode seller see the
  /// dispatcher's "Heading to pickup" / "Enter pickup code" controls.
  bool get isDeliveryActor => isDispatcher || isSelfDeliverySeller;

  double get itemSubtotalNaira => itemSubtotalKobo / 100;
  double get deliveryFeeNaira => deliveryFeeKobo / 100;
  double get grandTotalNaira => grandTotalKobo / 100;
  double get trustFullNaira => trustFullKobo / 100;

  /// The platform fee actually payable by the buyer — [buyerTrustShareKobo]
  /// when the backend provided it, else the full fee (older records /
  /// seller-paid split where the buyer's share equals the full amount shown).
  double get buyerTrustShareNaira =>
      (buyerTrustShareKobo ?? trustFullKobo) / 100;

  double? get sellerTrustShareNaira =>
      sellerTrustShareKobo == null ? null : sellerTrustShareKobo! / 100;

  /// What the seller actually receives once released. Falls back to
  /// itemSubtotal net of [sellerTrustShareKobo] if the backend-computed
  /// value is ever absent (defensive only — feeView() always returns it).
  double get sellerReceivableNaira =>
      (sellerReceivableKobo ??
          (itemSubtotalKobo - (sellerTrustShareKobo ?? 0))) /
      100;

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
      sellerTrustShareKobo: j['sellerTrustShareKobo'] == null
          ? null
          : asInt(j['sellerTrustShareKobo']),
      sellerReceivableKobo: j['sellerReceivableKobo'] == null
          ? null
          : asInt(j['sellerReceivableKobo']),
      feeSplit: asString(j['feeSplit'], 'split'),
      platformFeePayer: asString(j['platformFeePayer'], 'split_50_50'),
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
      // Older records carry the courier's contact inside consignments[].payout
      // (captured alongside now-removed bank details); Create Transaction no
      // longer collects payout at all, so new records fall back to the
      // top-level dispatcherName/dispatcherPhone (the same Hoppr dispatcher
      // link parsed separately below into dispatcherAccountName/Phone).
      dispatcherName:
          asStringOrNull(asMap(firstConsignment['payout'])['dispatcherName']) ??
          asStringOrNull(j['dispatcherName']),
      dispatcherPhone:
          asStringOrNull(
            asMap(firstConsignment['payout'])['dispatcherPhone'],
          ) ??
          asStringOrNull(j['dispatcherPhone']),
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
      isDispatcher: j['isDispatcher'] != null
          ? asBool(j['isDispatcher'])
          : asStringOrNull(j['myRole']) == 'dispatcher',
      sellerId: j['sellerId'] == null ? null : asId(j['sellerId']),
      buyerId: j['buyerId'] == null ? null : asId(j['buyerId']),
      dispatcherAccountId: j['dispatcherId'] == null
          ? null
          : asId(j['dispatcherId']),
      // Top-level `dispatcherPhone` (the assigned Hoppr account's phone) —
      // never confused with `consignments[].payout.dispatcherPhone` above,
      // which is parsed separately into [dispatcherPhone].
      dispatcherAccountPhone: asStringOrNull(j['dispatcherPhone']),
      dispatcherAccountName: asStringOrNull(j['dispatcherName']),
      dispatcherAccountStatus: asStringOrNull(j['dispatcherStatus']),
      dispatcherMode: asStringOrNull(j['dispatcherMode']),
      pickupConfirmedAt: asDateTime(asMap(j['pickup'])['confirmedAt']),
      nearBuyerAt: asDateTime(delivery['nearBuyerAt']),
      deliveryConfirmedAt: asDateTime(delivery['confirmedAt']),
      dispatcherAddress: asStringOrNull(firstConsignment['dispatcherAddress']),
    );
  }
}
