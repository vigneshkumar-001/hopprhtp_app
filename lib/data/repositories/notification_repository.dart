import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../../core/network/json.dart';
import '../dto/notification_dto.dart';

/// Wraps the `/notifications` endpoints (list, unread count, mark read).
class NotificationRepository {
  NotificationRepository(this._dio);

  final Dio _dio;

  Future<NotificationPage> listPage({required int page, int limit = 20}) =>
      apiCall(
        () => _dio.get('/notifications',
            queryParameters: {'page': page, 'limit': limit}),
        (d) => NotificationPage.fromJson(asMap(d)),
      );

  Future<int> unreadCount() => apiCall(
        () => _dio.get('/notifications/unread-count'),
        (d) => asInt(asMap(d)['unread']),
      );

  Future<void> markRead(String id) => apiCall(
        () => _dio.post('/notifications/$id/read'),
        (_) {},
      );

  Future<void> markAllRead() => apiCall(
        () => _dio.post('/notifications/read-all'),
        (_) {},
      );
}
