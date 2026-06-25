import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/transaction_dto.dart';

/// Wraps the `/transactions` endpoints. Lifecycle actions return the updated
/// [ApiTransaction] so callers can refresh local state from the server's truth.
class TransactionRepository {
  TransactionRepository(this._dio);

  final Dio _dio;

  /// List the signed-in user's transactions. Optional server-side filters:
  /// [stage] (active|cooling|done), [status], [role] (seller|buyer).
  Future<List<ApiTransaction>> list({
    String? stage,
    String? status,
    String? role,
  }) {
    return apiCall(
      () => _dio.get('/transactions', queryParameters: {
        'stage': ?stage,
        'status': ?status,
        'role': ?role,
      }),
      // Response is now a page envelope `{ items, page, hasMore, ... }`; with no
      // page/limit the server returns a single large page (dashboard use).
      (d) => asList(asMap(d)['items'])
          .map((e) => ApiTransaction.fromJson(asMap(e)))
          .toList(growable: false),
    );
  }

  /// One page of the user's transactions for infinite-scroll history.
  Future<TxPage> listPage({
    required int page,
    int limit = 15,
    String? stage,
    String? status,
    String? role,
  }) {
    return apiCall(
      () => _dio.get('/transactions', queryParameters: {
        'page': page,
        'limit': limit,
        'stage': ?stage,
        'status': ?status,
        'role': ?role,
      }),
      (d) => TxPage.fromJson(asMap(d)),
    );
  }

  Future<ApiTransaction> getById(String id) => apiCall(
        () => _dio.get('/transactions/$id'),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );

  /// Lookup by public code (e.g. scanned from a QR / shared link).
  Future<ApiTransaction> getByCode(String code) => apiCall(
        () => _dio.get('/transactions/code/$code'),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );

  // ── Lifecycle actions (each enforced by the server-side state machine) ─────

  Future<ApiTransaction> agree(String id) => _action(id, 'agree');

  /// Buyer funds escrow. Returns the tx plus the dev delivery OTP (non-prod).
  Future<({ApiTransaction tx, String? devOtp})> fund(String id) => apiCall(
        () => _dio.post('/transactions/$id/fund'),
        (d) {
          final m = asMap(d);
          return (
            tx: ApiTransaction.fromJson(asMap(m['transaction'])),
            devOtp: asStringOrNull(m['devOtp']),
          );
        },
      );

  Future<ApiTransaction> ship(String id, {String? carrier, String? trackingNumber}) =>
      apiCall(
        () => _dio.post('/transactions/$id/ship', data: {
          'carrier': ?carrier,
          'trackingNumber': ?trackingNumber,
        }),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );

  Future<ApiTransaction> outForDelivery(String id) =>
      _action(id, 'out-for-delivery');

  Future<ApiTransaction> confirmDelivery(
    String id, {
    required String otp,
    double? lat,
    double? lng,
  }) =>
      apiCall(
        () => _dio.post('/transactions/$id/confirm-delivery', data: {
          'otp': otp,
          'lat': ?lat,
          'lng': ?lng,
        }),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );

  Future<ApiTransaction> release(String id) => _action(id, 'release');

  Future<ApiTransaction> cancel(String id, {String? reason}) => apiCall(
        () => _dio.post('/transactions/$id/cancel', data: {'reason': ?reason}),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );

  /// Create a transaction (seller). [body] follows the create schema:
  /// `{ consignments:[{product, amountNaira, buyerContact, payout{...},
  /// dispatchPhotoUrl?, waybillImageUrl?}], feeSplit, deliveryFeeNaira?,
  /// variant?, inspectionPeriodSeconds?, buyerEmail?, sellerEmail? }`.
  Future<ApiTransaction> create(Map<String, dynamic> body) => apiCall(
        () => _dio.post('/transactions', data: body),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );

  Future<ApiTransaction> _action(String id, String path) => apiCall(
        () => _dio.post('/transactions/$id/$path'),
        (d) => ApiTransaction.fromJson(asMap(d)),
      );
}
