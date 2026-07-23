import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../dto/transaction_dto.dart'
    show ApiTransaction, ApiTxStage, ApiTxStatus;

/// Which lifecycle bucket a transaction sits in (drives the Home tabs).
enum TxStage { active, cooling, done }

extension TxStageX on TxStage {
  String get label => switch (this) {
    TxStage.active => 'Active',
    TxStage.cooling => 'Cooling',
    TxStage.done => 'Done',
  };
}

/// A delivery/escrow status shown as a pill on each transaction card.
enum TxStatus {
  outForDelivery,
  inTransit,
  awaitingDispatch,
  delivered,
  released,
  disputed,
}

extension TxStatusX on TxStatus {
  String get label => switch (this) {
    TxStatus.outForDelivery => 'Out for delivery',
    TxStatus.inTransit => 'In transit',
    TxStatus.awaitingDispatch => 'Awaiting dispatch',
    TxStatus.delivered => 'Delivered',
    TxStatus.released => 'Funds released',
    TxStatus.disputed => 'In dispute',
  };

  IconData get icon => switch (this) {
    TxStatus.outForDelivery => Icons.local_shipping_outlined,
    TxStatus.inTransit => Icons.local_shipping_outlined,
    TxStatus.awaitingDispatch => Icons.inventory_2_outlined,
    TxStatus.delivered => Icons.check_circle_outline,
    TxStatus.released => Icons.verified_outlined,
    TxStatus.disputed => Icons.gpp_maybe_outlined,
  };

  Color get color => switch (this) {
    TxStatus.disputed => AppColors.danger,
    TxStatus.delivered || TxStatus.released => AppColors.success,
    _ => AppColors.textSecondary,
  };
}

/// A protected (escrow) transaction.
class EscrowTransaction {
  EscrowTransaction({
    required this.id,
    required this.code,
    required this.merchantName,
    required this.productName,
    this.buyerName,
    this.buyerContact,
    this.deliveryAddress,
    this.estimatedDeliveryDate,
    this.estimatedDeliveryTime,
    this.dispatcherName,
    this.dispatcherPhone,
    required this.amount,
    required this.stage,
    required this.status,
    this.variant,
    this.merchantVerified = true,
    this.myRole,
    this.apiStatus,
    this.productPhotoUrl,
    this.createdAt,
  });

  /// Full-fidelity snapshot from a backend [ApiTransaction] — carries the real
  /// id, per-transaction role, precise status and product photo so Transaction
  /// Details can render immediately from the list data, then refresh live.
  /// Shared by Home and Transaction History so every list produces the same
  /// complete snapshot (no partial/missing-field conversions).
  factory EscrowTransaction.fromApi(ApiTransaction t) => EscrowTransaction(
    id: t.id,
    code: t.code,
    merchantName: t.merchantName,
    productName: t.productName,
    buyerName: t.buyerName,
    buyerContact: t.buyerContact,
    deliveryAddress: t.deliveryAddress,
    estimatedDeliveryDate: t.estimatedDeliveryDate,
    estimatedDeliveryTime: t.estimatedDeliveryTime,
    dispatcherName: t.dispatcherName,
    dispatcherPhone: t.dispatcherPhone,
    variant: t.variant,
    amount: t.grandTotalNaira,
    stage: switch (t.stage) {
      ApiTxStage.cooling => TxStage.cooling,
      ApiTxStage.done => TxStage.done,
      ApiTxStage.active => TxStage.active,
    },
    status: switch (t.status) {
      ApiTxStatus.outForDelivery => TxStatus.outForDelivery,
      ApiTxStatus.inTransit => TxStatus.inTransit,
      ApiTxStatus.delivered => TxStatus.delivered,
      ApiTxStatus.released || ApiTxStatus.completed => TxStatus.released,
      ApiTxStatus.disputed => TxStatus.disputed,
      _ => TxStatus.awaitingDispatch,
    },
    myRole: t.myRole,
    apiStatus: t.status,
    productPhotoUrl: t.productPhotoUrl,
    createdAt: t.createdAt,
  );

  final String id;
  final String code; // e.g. HTP-7Q2K
  final String merchantName;
  final String productName;
  final String? buyerName;
  final String? buyerContact;
  final String? deliveryAddress;
  final String? estimatedDeliveryDate;
  final String? estimatedDeliveryTime;

  /// The courier arranged by the seller — distinct from the buyer/seller
  /// themselves. Null until a dispatcher has actually been assigned.
  final String? dispatcherName;
  final String? dispatcherPhone;
  final String? variant; // "Size M · Sand beige"
  final double amount;
  final TxStage stage;
  final TxStatus status;
  final bool merchantVerified;

  /// Per-transaction role for the signed-in user: 'seller' | 'buyer' | null.
  /// Drives the Selling/Buying badge on list cards. Null when unknown (e.g.
  /// legacy seeded/demo rows) → no badge shown.
  final String? myRole;

  /// Precise backend status snapshot from the list/Home data, used by
  /// Transaction Details to render the first role action immediately (before
  /// its own refetch resolves). Null for legacy/demo rows → detail waits for
  /// the refetch instead of guessing.
  final ApiTxStatus? apiStatus;

  /// Uploaded product photo URL (item being sold) — shown on the product/details
  /// cards. Null → a clean placeholder is shown.
  final String? productPhotoUrl;

  /// When the transaction was created. Null (or the epoch-0 sentinel a failed
  /// backend date parse falls back to) → cards show "Date not available"
  /// rather than a fabricated date.
  final DateTime? createdAt;

  String get merchantInitials {
    final parts = merchantName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}

/// The signed-in user / profile.
class HopprUser {
  HopprUser({
    required this.fullName,
    required this.phone,
    this.email,
    this.trustScore = 'A+',
    this.deals = 42,
    this.disputes = 0,
    this.verified = true,
    this.escrowBalance = 137428,
  });

  String fullName;
  String phone;
  String? email;
  String trustScore;
  int deals;
  int disputes;
  bool verified;
  double escrowBalance;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}

/// Who pays the Hoppr Platform Fee — a decision entirely independent of
/// [DeliveryMethod] (who delivers). Even "Deliver myself" still incurs the
/// fee: Hoppr provides the payment link, escrow protection, buyer payment
/// holding, delivery confirmation, dispute safety and seller wallet release
/// regardless of who physically carries the package.
// Declared in the same order the Create Transaction segmented control
// displays them (Buyer, 50:50, Seller) — `_platformFeePayer =
// PlatformFeePayer.values[i]` maps the tapped segment index straight onto
// this enum, so the declaration order must track the UI order exactly.
enum PlatformFeePayer { buyer, split50, seller }

extension PlatformFeePayerX on PlatformFeePayer {
  String get label => switch (this) {
    PlatformFeePayer.buyer => 'Buyer pays',
    PlatformFeePayer.seller => 'Seller pays',
    PlatformFeePayer.split50 => 'Split 50:50',
  };

  String get wireValue => switch (this) {
    PlatformFeePayer.buyer => 'buyer',
    PlatformFeePayer.seller => 'seller',
    PlatformFeePayer.split50 => 'split_50_50',
  };

  /// Parses the backend's `platformFeePayer` wire value — an unrecognised or
  /// missing value (only possible for pre-migration records) falls back to
  /// [split50], matching [ApiTransaction.platformFeePayer]'s own fallback.
  static PlatformFeePayer fromWireValue(String v) => switch (v) {
    'buyer' => PlatformFeePayer.buyer,
    'seller' => PlatformFeePayer.seller,
    _ => PlatformFeePayer.split50,
  };
}

/// Who physically handles pickup + delivery — chosen once per transaction
/// (mirrors the backend's `dispatcherMode`). `requestDispatcher` is the only
/// case that asks for a dispatcher name/phone.
enum DeliveryMethod { sellerSelf, requestDispatcher }

extension DeliveryMethodX on DeliveryMethod {
  String get label => switch (this) {
    DeliveryMethod.sellerSelf => 'I will deliver myself',
    DeliveryMethod.requestDispatcher => 'Request Hoppr Dispatcher',
  };

  String get wireValue => switch (this) {
    DeliveryMethod.sellerSelf => 'seller_self_delivery',
    DeliveryMethod.requestDispatcher => 'request_hoppr_dispatcher',
  };
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// Carries the computed money breakdown from Payment Setup → Buyer Review →
/// payment, so every screen shows identical figures.
class PaymentDraft {
  PaymentDraft({
    required this.productName,
    required this.sellerName,
    required this.sellerCode,
    required this.itemSubtotal,
    required this.platformFeePayer,
    // Never a hardcoded/manual starting value — Payment Setup immediately
    // overwrites this with either 0 (Deliver Myself) or a real distance +
    // weight preview (Hoppr Dispatcher, see DeliveryFeeEstimator), and it's
    // overwritten again with the authoritative backend figure once the
    // transaction is actually created.
    this.deliveryFee = 0,
    this.variant,
    this.transactionId,
  });

  final String productName;
  final String sellerName;
  final String sellerCode;
  final String? variant;

  /// The real backend transaction id — set only when this draft was built
  /// from a live [ApiTransaction]/[EscrowTransaction]. Screens that need to
  /// call a real transaction endpoint (e.g. confirm-delivery) must check this
  /// is non-null before doing so; older/demo call sites leave it null.
  final String? transactionId;
  final double itemSubtotal;
  double deliveryFee;

  /// Chosen once, required, on Create Transaction — never defaulted or
  /// re-asked here. This is only a client-side PREVIEW of the backend's own
  /// computation (see computeFees() in transaction.service.ts); the
  /// authoritative amounts are whatever the backend returns once the
  /// transaction actually exists.
  PlatformFeePayer platformFeePayer;

  static const double trustRate = 0.015;

  double get trustFull => _round2(itemSubtotal * trustRate);

  double get buyerTrustShare => switch (platformFeePayer) {
    PlatformFeePayer.buyer => trustFull,
    PlatformFeePayer.split50 => _round2(trustFull / 2),
    PlatformFeePayer.seller => 0,
  };

  double get sellerTrustShare => _round2(trustFull - buyerTrustShare);

  double get grandTotal => itemSubtotal + deliveryFee + buyerTrustShare;

  /// What the seller actually receives once released — item value net of
  /// their fee share. Mirrors the backend's sellerReceivableKobo.
  double get sellerReceivable => _round2(itemSubtotal - sellerTrustShare);
}

/// A single consignment within a (multi-item) transaction draft.
class Consignment {
  Consignment({
    this.product = '',
    this.amount = '',
    this.quantity = '',
    this.weight = '',
    this.buyerName = '',
    this.buyerContact = '',
    this.deliveryAddress = '',
    this.deliveryLat,
    this.deliveryLng,
    this.estimatedDeliveryDate = '',
    this.estimatedDeliveryTime = '',
    this.waybillTrackingNumber = '',
    this.dispatcherName = '',
    this.dispatcherPhone = '',
    this.dispatcherAddress = '',
    this.dispatcherLat,
    this.dispatcherLng,
    this.specialInstructions = '',
    this.hasDispatchPhoto = false,
    this.hasWaybillImage = false,
    this.productPhotoUrl,
    this.dispatchPhotoUrl,
    this.waybillImageUrl,
  });

  String product;
  String amount; // kept as text while editing
  String quantity;
  String weight;
  String buyerName;
  String buyerContact;

  /// Buyer delivery location — where the dispatcher (or self-delivering
  /// seller) hands the package to the buyer. There is no separate "pickup
  /// address" in this app; only this and [dispatcherAddress] exist.
  String deliveryAddress;

  /// Delivery address coordinates from the map picker. Null when the address
  /// text was picked before this field existed, or picked without a map.
  double? deliveryLat;
  double? deliveryLng;
  String estimatedDeliveryDate;
  String estimatedDeliveryTime;
  String waybillTrackingNumber;

  /// Dispatcher's name/phone — sent as the top-level Hoppr dispatcher
  /// ACCOUNT link (request_hoppr_dispatcher only) *and* shown in the
  /// Dispatcher Information section; a single pair of fields serves both,
  /// never a duplicate. No payout/bank details are collected here — the
  /// dispatcher is settled later via Dispatcher Wallet / Admin Settlement,
  /// never at Create Transaction.
  String dispatcherName;
  String dispatcherPhone;

  /// Where the dispatcher collects the product from the seller — the
  /// collection/pickup point. Shown in the UI as "Package Collection
  /// Address" — never "Dispatcher Address" (reads like the dispatcher's own
  /// address) or "Pickup Address" (not a concept this app uses).
  String dispatcherAddress;

  /// Package Collection Address coordinates from the map picker — required
  /// for the backend to calculate the HTP Delivery Fee (distance between
  /// this and [deliveryLat]/[deliveryLng]) for a Hoppr Dispatcher delivery.
  /// Null when the address hasn't been picked via the map yet.
  double? dispatcherLat;
  double? dispatcherLng;
  String specialInstructions;
  bool hasDispatchPhoto;
  bool hasWaybillImage;
  String? productPhotoUrl; // backend URL after upload
  String? dispatchPhotoUrl;
  String? waybillImageUrl;

  bool get isComplete =>
      product.isNotEmpty &&
      amount.isNotEmpty &&
      quantity.isNotEmpty &&
      buyerName.isNotEmpty &&
      buyerContact.isNotEmpty &&
      deliveryAddress.isNotEmpty;
}
