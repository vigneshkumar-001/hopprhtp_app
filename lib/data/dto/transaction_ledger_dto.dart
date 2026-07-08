import '../../core/network/json.dart';

/// One line in the settlement ledger — either a non-monetary lifecycle event
/// (`type == 'lifecycle'`, `amountKobo == null`) or a real ledger movement
/// (a signed kobo amount, mirroring the backend's LedgerEntry). Never fabricated
/// client-side — both sources are real records read from the backend.
class LedgerFeedItem {
  const LedgerFeedItem({
    required this.id,
    required this.title,
    required this.type,
    this.amountKobo,
    required this.status,
    this.actor,
    required this.timestamp,
    this.referenceId,
    this.remarks,
  });

  final String id;
  final String title;
  final String type;
  final int? amountKobo;
  final String status;
  final String? actor; // 'buyer' | 'seller' | null
  final DateTime timestamp;
  final String? referenceId;
  final String? remarks;

  bool get isMonetary => amountKobo != null;
  double? get amountNaira => amountKobo == null ? null : amountKobo! / 100;

  factory LedgerFeedItem.fromJson(Map<String, dynamic> j) => LedgerFeedItem(
    id: asString(j['id']),
    title: asString(j['title']),
    type: asString(j['type']),
    amountKobo: j['amount'] == null ? null : asInt(j['amount']),
    status: asString(j['status']),
    actor: asStringOrNull(j['actor']),
    timestamp:
        asDateTime(j['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    referenceId: asStringOrNull(j['referenceId']),
    remarks: asStringOrNull(j['remarks']),
  );
}

class CoolingPeriodSummary {
  const CoolingPeriodSummary({
    this.startedAt,
    this.endsAt,
    required this.status,
  });
  final DateTime? startedAt;
  final DateTime? endsAt;
  final String status;

  static CoolingPeriodSummary? fromJsonOrNull(dynamic v) {
    if (v == null) return null;
    final m = asMap(v);
    return CoolingPeriodSummary(
      startedAt: asDateTime(m['startedAt']),
      endsAt: asDateTime(m['endsAt']),
      status: asString(m['status']),
    );
  }
}

/// `GET /transactions/:id/ledger` — the full money + status picture for one
/// transaction. Amounts are always real (derived from the transaction's own
/// fields); `refundAmountKobo` is null unless an actual refund ledger entry
/// exists — never a guessed/fake value.
class TransactionLedger {
  const TransactionLedger({
    required this.transactionId,
    required this.status,
    required this.escrowAmountKobo,
    required this.platformFeeKobo,
    required this.sellerPayoutKobo,
    this.refundAmountKobo,
    required this.escrowStatus,
    required this.settlementStatus,
    this.coolingPeriod,
    this.ledger = const [],
  });

  final String transactionId;
  final String status; // raw backend status — pair with ApiTxStatus.fromApi
  final int escrowAmountKobo;
  final int platformFeeKobo;
  final int sellerPayoutKobo;
  final int? refundAmountKobo;
  final String escrowStatus;
  final String settlementStatus;
  final CoolingPeriodSummary? coolingPeriod;
  final List<LedgerFeedItem> ledger;

  double get escrowAmountNaira => escrowAmountKobo / 100;
  double get platformFeeNaira => platformFeeKobo / 100;
  double get sellerPayoutNaira => sellerPayoutKobo / 100;
  double? get refundAmountNaira =>
      refundAmountKobo == null ? null : refundAmountKobo! / 100;

  factory TransactionLedger.fromJson(Map<String, dynamic> j) =>
      TransactionLedger(
        transactionId: asString(j['transactionId']),
        status: asString(j['status']),
        escrowAmountKobo: asInt(j['escrowAmountKobo']),
        platformFeeKobo: asInt(j['platformFeeKobo']),
        sellerPayoutKobo: asInt(j['sellerPayoutKobo']),
        refundAmountKobo: j['refundAmountKobo'] == null
            ? null
            : asInt(j['refundAmountKobo']),
        escrowStatus: asString(j['escrowStatus']),
        settlementStatus: asString(j['settlementStatus']),
        coolingPeriod: CoolingPeriodSummary.fromJsonOrNull(j['coolingPeriod']),
        ledger: asList(
          j['ledger'],
        ).map((e) => LedgerFeedItem.fromJson(asMap(e))).toList(growable: false),
      );
}
