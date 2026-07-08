import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/dispute_dto.dart';

/// Wraps the `/disputes` endpoints (a distinct resource from `/transactions` —
/// see [TransactionRepository.getTransactionDisputes] for the transaction-
/// scoped list). Backend is the final authority on every rule; this repository
/// only shapes requests/responses.
class DisputeRepository {
  DisputeRepository(this._dio);

  final Dio _dio;

  /// Raise a dispute. Backend enforces ownership, the cooling-window rule,
  /// and duplicate-active-dispute prevention.
  Future<Dispute> raise({
    required String transactionId,
    required String category,
    String? reason,
    List<DisputeEvidence> evidence = const [],
  }) => apiCall(
    () => _dio.post(
      '/disputes',
      data: {
        'transactionId': transactionId,
        'category': category,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'evidence': evidence.map((e) => e.toJson()).toList(),
      },
    ),
    (d) => Dispute.fromJson(asMap(d)),
  );

  Future<Dispute> getById(String id) => apiCall(
    () => _dio.get('/disputes/$id'),
    (d) => Dispute.fromJson(asMap(d)),
  );

  /// The counter-party's response — backend rejects if the caller isn't the
  /// other side of [Dispute.raisedByRole], or if one was already submitted.
  Future<Dispute> respond(String id, String message) => apiCall(
    () => _dio.post('/disputes/$id/respond', data: {'message': message}),
    (d) => Dispute.fromJson(asMap(d)),
  );
}
