import '../../core/network/json.dart';

/// Wallet balances (kobo), split across the three buckets.
class WalletBalance {
  const WalletBalance({
    required this.availableKobo,
    required this.coolingKobo,
    required this.escrowKobo,
  });

  final int availableKobo; // withdrawable
  final int coolingKobo; // pending cooling release
  final int escrowKobo; // locked in active escrows

  double get availableNaira => availableKobo / 100;
  double get coolingNaira => coolingKobo / 100;
  double get escrowNaira => escrowKobo / 100;

  factory WalletBalance.fromJson(Map<String, dynamic> m) => WalletBalance(
    availableKobo: asInt(m['availableKobo']),
    coolingKobo: asInt(m['coolingKobo']),
    escrowKobo: asInt(m['escrowKobo']),
  );
}

/// One append-only ledger entry (a single money movement), enriched by the
/// backend with a plain-language explanation so the Wallet screen never has
/// to guess what a raw type/amount means.
class WalletLedgerEntry {
  const WalletLedgerEntry({
    required this.id,
    required this.type,
    required this.amountKobo,
    required this.bucket,
    required this.description,
    this.createdAt,
    this.title,
    this.sourceLabel,
    this.destinationLabel,
    this.status = 'completed',
    this.reference,
    this.transactionId,
    this.productName,
    this.productAmountKobo,
    this.platformFeeKobo,
    this.buyerFeeShareKobo,
    this.sellerFeeShareKobo,
    this.buyerPayableAmountKobo,
    this.sellerReceivableAmountKobo,
  });

  final String id;
  final String type; // escrow_funded | seller_payout | withdrawal | ...
  final int amountKobo; // signed
  final String bucket;
  final String description;
  final DateTime? createdAt;

  /// Backend-computed friendly title (e.g. "Seller Payout", "Delivery Fee
  /// Deducted", "Escrow Payment") — always populated by the current API;
  /// null only guards a response shape from before this field existed, in
  /// which case screens fall back to a generic label rather than guessing.
  final String? title;

  /// Where the money came from / went, in plain language (e.g. "Hoppr
  /// Escrow", "Seller Wallet", "Your Payout Account") — never a raw bucket
  /// name or internal identifier.
  final String? sourceLabel;
  final String? destinationLabel;

  /// Always 'completed' today — no ledger entry is ever written in a
  /// pending/failed state (a move() call either fully succeeds or throws).
  final String status;

  /// The transaction's short code (e.g. "HTP-7Q2K"), not the internal
  /// ledger entry id or the escrow provider's own reference.
  final String? reference;
  final String? transactionId;
  final String? productName;

  /// Fee breakdown for the linked transaction, when there is one — null for
  /// entries with no [transactionId] (e.g. a withdrawal or an admin
  /// adjustment) or for a legacy entry predating this enrichment.
  final int? productAmountKobo;
  final int? platformFeeKobo;
  final int? buyerFeeShareKobo;
  final int? sellerFeeShareKobo;
  final int? buyerPayableAmountKobo;
  final int? sellerReceivableAmountKobo;

  bool get isCredit => amountKobo >= 0;
  double get amountNaira => amountKobo.abs() / 100;
  double? get productAmountNaira =>
      productAmountKobo == null ? null : productAmountKobo! / 100;
  double? get platformFeeNaira =>
      platformFeeKobo == null ? null : platformFeeKobo! / 100;
  double? get buyerFeeShareNaira =>
      buyerFeeShareKobo == null ? null : buyerFeeShareKobo! / 100;
  double? get sellerFeeShareNaira =>
      sellerFeeShareKobo == null ? null : sellerFeeShareKobo! / 100;
  double? get buyerPayableAmountNaira =>
      buyerPayableAmountKobo == null ? null : buyerPayableAmountKobo! / 100;
  double? get sellerReceivableAmountNaira => sellerReceivableAmountKobo == null
      ? null
      : sellerReceivableAmountKobo! / 100;

  /// True once the entry carries enough enrichment to render the details
  /// sheet without a further fetch — true for every entry the current API
  /// returns; false only guards an older cached/legacy response shape.
  bool get hasFullDetails => title != null;

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> m) =>
      WalletLedgerEntry(
        id: asId(m['id'] ?? m['_id']),
        type: asString(m['type']),
        amountKobo: asInt(m['amountKobo']),
        bucket: asString(m['bucket']),
        description: asString(m['description']),
        createdAt: asDateTime(m['createdAt']),
        title: asStringOrNull(m['title']),
        sourceLabel: asStringOrNull(m['sourceLabel']),
        destinationLabel: asStringOrNull(m['destinationLabel']),
        status: asString(m['status'], 'completed'),
        reference: asStringOrNull(m['reference']),
        transactionId: asStringOrNull(m['transactionId']),
        productName: asStringOrNull(m['productName']),
        productAmountKobo: m['productAmountKobo'] == null
            ? null
            : asInt(m['productAmountKobo']),
        platformFeeKobo: m['platformFeeKobo'] == null
            ? null
            : asInt(m['platformFeeKobo']),
        buyerFeeShareKobo: m['buyerFeeShareKobo'] == null
            ? null
            : asInt(m['buyerFeeShareKobo']),
        sellerFeeShareKobo: m['sellerFeeShareKobo'] == null
            ? null
            : asInt(m['sellerFeeShareKobo']),
        buyerPayableAmountKobo: m['buyerPayableAmountKobo'] == null
            ? null
            : asInt(m['buyerPayableAmountKobo']),
        sellerReceivableAmountKobo: m['sellerReceivableAmountKobo'] == null
            ? null
            : asInt(m['sellerReceivableAmountKobo']),
      );
}

/// One withdrawal (payout) request and its admin-review status — from
/// `GET /wallet/withdrawals`. Deliberately a narrower field set than the
/// admin panel's own withdrawal row: no admin-only fields (reviewedBy,
/// payoutAccountId, metadata), and the account number is always pre-masked
/// by the backend, never the full number.
class WithdrawalRequest {
  const WithdrawalRequest({
    required this.id,
    required this.amountKobo,
    required this.currency,
    required this.status,
    required this.requestedAt,
    required this.updatedAt,
    this.reviewedAt,
    this.approvedAt,
    this.processingAt,
    this.paidAt,
    this.rejectedAt,
    this.failedAt,
    this.cancelledAt,
    this.rejectionReason,
    this.failureReason,
    this.adminNote,
    required this.payoutAccountMasked,
    required this.bankName,
    this.accountHolderName,
    this.payoutMethod,
  });

  final String id;
  final int amountKobo;
  final String currency;

  /// pending | under_review | approved | processing | paid | rejected |
  /// failed | cancelled — the same WithdrawalStatus enum the backend model
  /// uses; never re-derived client-side.
  final String status;
  final DateTime? requestedAt;
  final DateTime? updatedAt;

  /// Real per-stage timestamps, null until that stage is actually reached —
  /// power the Withdrawal History detail sheet's timeline. Never fabricated:
  /// a step with a null timestamp simply hasn't happened yet.
  final DateTime? reviewedAt;
  final DateTime? approvedAt;
  final DateTime? processingAt;
  final DateTime? paidAt;
  final DateTime? rejectedAt;
  final DateTime? failedAt;
  final DateTime? cancelledAt;

  final String? rejectionReason;
  final String? failureReason;

  /// Admin's payment note, only ever set once paid — never the admin's
  /// internal review/audit notes.
  final String? adminNote;
  final String payoutAccountMasked;
  final String bankName;
  final String? accountHolderName;

  /// Always 'bank_transfer' today — the only payout method this platform
  /// supports. Null only guards a response predating this field.
  final String? payoutMethod;

  double get amountNaira => amountKobo / 100;

  bool get isRejected => status == 'rejected';
  bool get isFailed => status == 'failed';
  bool get isPaid => status == 'paid';
  bool get isTerminal => isRejected || isFailed || isPaid || status == 'cancelled';

  /// Last 6 characters of the real backend id, uppercased — a short,
  /// presentational reference (matching the app's "HTP-XXXX" style
  /// transaction codes) rather than showing the full Mongo ObjectId.
  String get shortId =>
      id.length >= 6 ? id.substring(id.length - 6).toUpperCase() : id.toUpperCase();

  String get payoutMethodLabel => switch (payoutMethod) {
    'bank_transfer' || null => 'Bank Transfer',
    _ => payoutMethod!,
  };

  /// Presentational only — matches wallet_screen.dart's own per-status
  /// labels so "Pending" etc. never drifts between the two places it's shown.
  String get statusLabel => switch (status) {
    'pending' => 'Pending',
    'under_review' => 'Under Review',
    'approved' => 'Approved',
    'processing' => 'Processing',
    'paid' => 'Paid',
    'rejected' => 'Rejected',
    'failed' => 'Failed',
    'cancelled' => 'Cancelled',
    _ => status,
  };

  factory WithdrawalRequest.fromJson(Map<String, dynamic> m) =>
      WithdrawalRequest(
        id: asId(m['id'] ?? m['_id']),
        amountKobo: asInt(m['amountKobo']),
        currency: asString(m['currency'], 'NGN'),
        status: asString(m['status'], 'pending'),
        requestedAt: asDateTime(m['requestedAt']),
        updatedAt: asDateTime(m['updatedAt']),
        reviewedAt: asDateTime(m['reviewedAt']),
        approvedAt: asDateTime(m['approvedAt']),
        processingAt: asDateTime(m['processingAt']),
        paidAt: asDateTime(m['paidAt']),
        rejectedAt: asDateTime(m['rejectedAt']),
        failedAt: asDateTime(m['failedAt']),
        cancelledAt: asDateTime(m['cancelledAt']),
        rejectionReason: asStringOrNull(m['rejectionReason']),
        failureReason: asStringOrNull(m['failureReason']),
        adminNote: asStringOrNull(m['adminNote']),
        payoutAccountMasked: asString(m['payoutAccountMasked']),
        bankName: asString(m['bankName']),
        accountHolderName: asStringOrNull(m['accountHolderName']),
        payoutMethod: asStringOrNull(m['payoutMethod']),
      );
}

/// A Recent Activity date filter — Today / Yesterday / a custom range / all
/// time. [from]/[to] are inclusive local-day bounds sent straight to the
/// backend's `createdAt` range query; null on either side means unbounded.
class WalletActivityFilter {
  const WalletActivityFilter({this.from, this.to, this.label = 'All'});

  final DateTime? from;
  final DateTime? to;
  final String label;

  static const all = WalletActivityFilter();

  factory WalletActivityFilter.today() {
    final now = DateTime.now();
    return WalletActivityFilter(
      from: DateTime(now.year, now.month, now.day),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
      label: 'Today',
    );
  }

  factory WalletActivityFilter.yesterday() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return WalletActivityFilter(
      from: DateTime(y.year, y.month, y.day),
      to: DateTime(y.year, y.month, y.day, 23, 59, 59, 999),
      label: 'Yesterday',
    );
  }

  /// The 7 days up to and including today.
  factory WalletActivityFilter.lastWeek() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    return WalletActivityFilter(
      from: DateTime(start.year, start.month, start.day),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
      label: 'Last week',
    );
  }

  /// The default Recent Activity view — the 1st of this month through today.
  factory WalletActivityFilter.thisMonth() {
    final now = DateTime.now();
    return WalletActivityFilter(
      from: DateTime(now.year, now.month, 1),
      to: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
      label: 'This month',
    );
  }

  factory WalletActivityFilter.range(DateTime from, DateTime to) {
    return WalletActivityFilter(
      from: DateTime(from.year, from.month, from.day),
      to: DateTime(to.year, to.month, to.day, 23, 59, 59, 999),
      label: 'Custom',
    );
  }

  bool get isAll => from == null && to == null;

  @override
  bool operator ==(Object other) =>
      other is WalletActivityFilter && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// A page of ledger entries.
class WalletLedgerPage {
  const WalletLedgerPage({
    required this.entries,
    required this.page,
    required this.total,
    required this.hasMore,
  });

  final List<WalletLedgerEntry> entries;
  final int page;
  final int total;
  final bool hasMore;

  factory WalletLedgerPage.fromJson(Map<String, dynamic> m) {
    final page = asInt(m['page'], 1);
    final perPage = asInt(m['perPage'], 50);
    final total = asInt(m['total']);
    return WalletLedgerPage(
      entries: asList(m['entries'])
          .map((e) => WalletLedgerEntry.fromJson(asMap(e)))
          .toList(growable: false),
      page: page,
      total: total,
      hasMore: page * perPage < total,
    );
  }
}
