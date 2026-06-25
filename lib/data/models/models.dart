import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

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
    required this.amount,
    required this.stage,
    required this.status,
    this.variant,
    this.merchantVerified = true,
  });

  final String id;
  final String code; // e.g. HTP-7Q2K
  final String merchantName;
  final String productName;
  final String? variant; // "Size M · Sand beige"
  final double amount;
  final TxStage stage;
  final TxStatus status;
  final bool merchantVerified;

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
  });

  final String productName;
  final String sellerName;
  final String sellerCode;
  final String? variant;
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
    this.buyerContact = '',
    CourierPayout? payout,
    this.hasDispatchPhoto = false,
    this.hasWaybillImage = false,
    this.dispatchPhotoUrl,
    this.waybillImageUrl,
  }) : payout = payout ?? CourierPayout();

  String product;
  String amount; // kept as text while editing
  String buyerContact;
  CourierPayout payout;
  bool hasDispatchPhoto;
  bool hasWaybillImage;
  String? dispatchPhotoUrl; // backend URL after upload
  String? waybillImageUrl;

  bool get isComplete =>
      product.isNotEmpty && amount.isNotEmpty && buyerContact.isNotEmpty;
}
