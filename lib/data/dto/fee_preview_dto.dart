import '../../core/network/json.dart';

/// Live fee breakdown for the Create Transaction screen, computed server-side
/// by the exact same formula a real transaction is charged under (see backend
/// feeSettingsService.preview()) — never estimated client-side, so this can
/// never drift from what actually gets charged at submit time.
class FeePreview {
  const FeePreview({
    required this.productAmountKobo,
    required this.platformFeeKobo,
    required this.deliveryFeeKobo,
    required this.buyerPayableKobo,
    required this.sellerReceivableKobo,
  });

  final int productAmountKobo;
  final int platformFeeKobo;
  final int deliveryFeeKobo;
  final int buyerPayableKobo;
  final int sellerReceivableKobo;

  factory FeePreview.fromJson(Map<String, dynamic> j) => FeePreview(
    productAmountKobo: asInt(j['productAmountKobo']),
    platformFeeKobo: asInt(j['platformFeeKobo']),
    deliveryFeeKobo: asInt(j['deliveryFeeKobo']),
    buyerPayableKobo: asInt(j['buyerPayableKobo']),
    sellerReceivableKobo: asInt(j['sellerReceivableKobo']),
  );
}
