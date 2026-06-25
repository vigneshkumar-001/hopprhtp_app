import '../../core/network/json.dart';

/// A single in-app notification.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.code,
    required this.read,
    this.createdAt,
  });

  final String id;
  final String type; // transaction | payment | delivery | dispute | payout | system
  final String title;
  final String body;
  final String? code;
  final bool read;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: asId(j['id'] ?? j['_id']),
        type: asString(j['type'], 'system'),
        title: asString(j['title']),
        body: asString(j['body']),
        code: asStringOrNull(j['code']),
        read: asBool(j['read']),
        createdAt: asDateTime(j['createdAt']),
      );
}

/// A page of notifications, with the current unread total for the badge.
class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.unread,
  });

  final List<AppNotification> items;
  final int page;
  final bool hasMore;
  final int unread;

  factory NotificationPage.fromJson(Map<String, dynamic> j) => NotificationPage(
        items: asList(j['items'])
            .map((e) => AppNotification.fromJson(asMap(e)))
            .toList(growable: false),
        page: asInt(j['page'], 1),
        hasMore: asBool(j['hasMore']),
        unread: asInt(j['unread']),
      );
}
