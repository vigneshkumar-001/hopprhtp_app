import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/delivery_code_dto.dart';
import '../dto/delivery_verification_status_dto.dart';
import '../dto/dispute_dto.dart';
import '../dto/tracking_dto.dart';
import '../dto/transaction_dto.dart';
import '../dto/transaction_ledger_dto.dart';

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
      () => _dio.get(
        '/transactions',
        queryParameters: {'stage': ?stage, 'status': ?status, 'role': ?role},
      ),
      // Response is now a page envelope `{ items, page, hasMore, ... }`; with no
      // page/limit the server returns a single large page (dashboard use).
      (d) => asList(
        asMap(d)['items'],
      ).map((e) => ApiTransaction.fromJson(asMap(e))).toList(growable: false),
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
      () => _dio.get(
        '/transactions',
        queryParameters: {
          'page': page,
          'limit': limit,
          'stage': ?stage,
          'status': ?status,
          'role': ?role,
        },
      ),
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
  Future<({ApiTransaction tx, String? devOtp})> fund(String id) =>
      apiCall(() => _dio.post('/transactions/$id/fund'), (d) {
        final m = asMap(d);
        return (
          tx: ApiTransaction.fromJson(asMap(m['transaction'])),
          devOtp: asStringOrNull(m['devOtp']),
        );
      });

  /// Seller marks the order shipped (payment_received/awaiting_dispatch →
  /// in_transit). Optional [dispatchProofUrl] is stored as seller-side
  /// packing/courier evidence, separate from the item's product photo.
  Future<ApiTransaction> ship(
    String id, {
    String? carrier,
    String? trackingNumber,
    String? dispatchProofUrl,
  }) => apiCall(
    () => _dio.post(
      '/transactions/$id/ship',
      data: {
        'carrier': ?carrier,
        'trackingNumber': ?trackingNumber,
        'dispatchProofUrl': ?dispatchProofUrl,
      },
    ),
    (d) => ApiTransaction.fromJson(asMap(d)),
  );

  Future<ApiTransaction> outForDelivery(String id) =>
      _action(id, 'out-for-delivery');

  /// Seller-only: confirms delivery with the code the buyer gives them.
  Future<ApiTransaction> confirmDelivery(
    String id, {
    required String otp,
    double? lat,
    double? lng,
  }) => apiCall(
    () => _dio.post(
      '/transactions/$id/confirm-delivery',
      data: {'otp': otp, 'lat': ?lat, 'lng': ?lng},
    ),
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

  /// Real tracking snapshot (buyer destination, seller's last reported
  /// position, and a route only when both exist) — no client-side fallback.
  Future<TransactionTracking> getTracking(String id) => apiCall(
    () => _dio.get('/transactions/$id/tracking'),
    (d) => TransactionTracking.fromJson(asMap(d)),
  );

  /// Seller-only: reports the seller's current device position while a
  /// delivery is in transit. Server enforces ownership + status eligibility.
  Future<void> updateDeliveryLocation(
    String id, {
    required double latitude,
    required double longitude,
  }) => apiCall(
    () => _dio.post(
      '/transactions/$id/delivery-location',
      data: {'latitude': latitude, 'longitude': longitude},
    ),
    (_) {},
  );

  /// Seller-only real-time eligibility check for [confirmDelivery] — the
  /// backend re-validates all of this again on submit; this is UI-only.
  Future<DeliveryVerificationStatus> getDeliveryVerificationStatus(String id) =>
      apiCall(
        () => _dio.get('/transactions/$id/delivery-verification-status'),
        (d) => DeliveryVerificationStatus.fromJson(asMap(d)),
      );

  /// Buyer-only: the plaintext delivery code to share with the seller in
  /// person, once they've received the product.
  Future<DeliveryCode> getDeliveryCode(String id) => apiCall(
    () => _dio.get('/transactions/$id/delivery-code'),
    (d) => DeliveryCode.fromJson(asMap(d)),
  );

  /// Settlement/resolution ledger for either party — real LedgerEntry records
  /// merged with the transaction's own lifecycle timeline; never fabricated.
  Future<TransactionLedger> getTransactionLedger(String id) => apiCall(
    () => _dio.get('/transactions/$id/ledger'),
    (d) => TransactionLedger.fromJson(asMap(d)),
  );

  /// Every dispute raised against this transaction, oldest first.
  Future<List<Dispute>> getTransactionDisputes(String id) => apiCall(
    () => _dio.get('/transactions/$id/disputes'),
    (d) => asList(
      d,
    ).map((e) => Dispute.fromJson(asMap(e))).toList(growable: false),
  );
}
