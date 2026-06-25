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

/// One append-only ledger entry (a single money movement).
class WalletLedgerEntry {
  const WalletLedgerEntry({
    required this.id,
    required this.type,
    required this.amountKobo,
    required this.bucket,
    required this.description,
    this.createdAt,
  });

  final String id;
  final String type; // escrow_funded | seller_payout | withdrawal | ...
  final int amountKobo; // signed
  final String bucket;
  final String description;
  final DateTime? createdAt;

  bool get isCredit => amountKobo >= 0;
  double get amountNaira => amountKobo.abs() / 100;

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> m) =>
      WalletLedgerEntry(
        id: asId(m['id'] ?? m['_id']),
        type: asString(m['type']),
        amountKobo: asInt(m['amountKobo']),
        bucket: asString(m['bucket']),
        description: asString(m['description']),
        createdAt: asDateTime(m['createdAt']),
      );
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
