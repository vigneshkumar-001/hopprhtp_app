import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/support_dto.dart';

/// Wraps the `/support` endpoints (Help centre content + support requests).
class SupportRepository {
  SupportRepository(this._dio);

  final Dio _dio;

  /// Contact channels + curated FAQs for the Help centre.
  Future<SupportOverview> overview() => apiCall(
        () => _dio.get('/support/overview'),
        (d) => SupportOverview.fromJson(asMap(d)),
      );

  /// Opens a support request and returns it (with its `SUP-xxxx` code).
  Future<SupportTicket> createTicket({
    required String category,
    required String subject,
    required String message,
  }) =>
      apiCall(
        () => _dio.post('/support/tickets', data: {
          'category': category,
          'subject': subject,
          'message': message,
        }),
        (d) => SupportTicket.fromJson(asMap(d)),
      );

  /// The signed-in user's recent requests.
  Future<List<SupportTicket>> listTickets() => apiCall(
        () => _dio.get('/support/tickets'),
        (d) => asList(d)
            .map((e) => SupportTicket.fromJson(asMap(e)))
            .toList(growable: false),
      );
}
