import '../../core/network/json.dart';

/// Buyer-only response from `GET /transactions/:id/delivery-code` — the
/// plaintext code to share with the seller in person. `code` is null once
/// delivery is already confirmed (the code has been consumed and cleared).
class DeliveryCode {
  const DeliveryCode({
    required this.code,
    required this.alreadyConfirmed,
    this.expiresAt,
  });

  final String? code;
  final bool alreadyConfirmed;
  final DateTime? expiresAt;

  factory DeliveryCode.fromJson(Map<String, dynamic> j) => DeliveryCode(
    code: asStringOrNull(j['code']),
    alreadyConfirmed: asBool(j['alreadyConfirmed']),
    expiresAt: asDateTime(j['expiresAt']),
  );
}
