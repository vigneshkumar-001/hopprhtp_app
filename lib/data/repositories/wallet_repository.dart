import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/wallet_dto.dart';

/// Wraps the `/wallet` endpoints (balance, ledger, withdraw).
class WalletRepository {
  WalletRepository(this._dio);

  final Dio _dio;

  Future<WalletBalance> balance() => apiCall(
    () => _dio.get('/wallet/balance'),
    (d) => WalletBalance.fromJson(asMap(d)),
  );

  Future<WalletLedgerPage> ledger({
    int page = 1,
    int perPage = 30,
    DateTime? from,
    DateTime? to,
  }) => apiCall(
    () => _dio.get(
      '/wallet/ledger',
      queryParameters: {
        'page': page,
        'perPage': perPage,
        if (from != null) 'from': from.toIso8601String(),
        if (to != null) 'to': to.toIso8601String(),
      },
    ),
    (d) => WalletLedgerPage.fromJson(asMap(d)),
  );

  /// Fallback single-entry fetch for the details sheet — the list response
  /// already carries everything needed, so this is only used when an entry
  /// arrives without full enrichment (see [WalletLedgerEntry.hasFullDetails]).
  Future<WalletLedgerEntry> ledgerEntry(String id) => apiCall(
    () => _dio.get('/wallet/ledger/$id'),
    (d) => WalletLedgerEntry.fromJson(asMap(d)),
  );

  /// Withdraw available funds to a saved payout account. Returns the new balance.
  Future<WalletBalance> withdraw({
    required double amountNaira,
    required String accountId,
  }) => apiCall(
    () => _dio.post(
      '/wallet/withdraw',
      data: {'amountNaira': amountNaira, 'accountId': accountId},
    ),
    (d) => WalletBalance.fromJson(asMap(d)),
  );
}
