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

/// Courier payout details captured while creating a transaction.
class CourierPayout {
  CourierPayout({
    this.dispatcherName = '',
    this.dispatcherPhone = '',
    this.bank = '',
    this.accountNumber = '',
    this.accountName = '',
  });

  String dispatcherName;
  String dispatcherPhone;
  String bank;
  String accountNumber;
  String accountName;

  bool get isComplete =>
      dispatcherName.isNotEmpty &&
      dispatcherPhone.isNotEmpty &&
      bank.isNotEmpty &&
      accountNumber.isNotEmpty &&
      accountName.isNotEmpty;

  String get summary =>
      isComplete ? '$dispatcherName · $bank ${_maskedAccount()}' : 'Not added';

  String _maskedAccount() {
    if (accountNumber.length <= 4) return accountNumber;
    return '${accountNumber.substring(0, 4)}…';
  }
}

/// Who covers the Hoppr trust-protection fee.
enum FeeSplit { buyer, split, seller }

extension FeeSplitX on FeeSplit {
  String get label => switch (this) {
    FeeSplit.buyer => 'Buyer',
    FeeSplit.split => '50 : 50',
    FeeSplit.seller => 'Seller',
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
    this.deliveryFee = 7500,
    this.feeSplit = FeeSplit.split,
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
  FeeSplit feeSplit;

  static const double trustRate = 0.015;

  double get trustFull => _round2(itemSubtotal * trustRate);

  double get buyerTrustShare => switch (feeSplit) {
    FeeSplit.buyer => trustFull,
    FeeSplit.split => _round2(trustFull / 2),
    FeeSplit.seller => 0,
  };

  double get sellerTrustShare => _round2(trustFull - buyerTrustShare);

  double get grandTotal => itemSubtotal + deliveryFee + buyerTrustShare;
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
    this.dispatcherAddress = '',
    this.specialInstructions = '',
    CourierPayout? payout,
    this.hasDispatchPhoto = false,
    this.hasWaybillImage = false,
    this.productPhotoUrl,
    this.dispatchPhotoUrl,
    this.waybillImageUrl,
  }) : payout = payout ?? CourierPayout();

  String product;
  String amount; // kept as text while editing
  String quantity;
  String weight;
  String buyerName;
  String buyerContact;
  String deliveryAddress;

  /// Delivery address coordinates from the map picker. Null when the address
  /// text was picked before this field existed, or picked without a map.
  double? deliveryLat;
  double? deliveryLng;
  String estimatedDeliveryDate;
  String estimatedDeliveryTime;
  String waybillTrackingNumber;
  String dispatcherAddress;
  String specialInstructions;
  CourierPayout payout;
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
      deliveryAddress.isNotEmpty &&
      payout.isComplete;
}
