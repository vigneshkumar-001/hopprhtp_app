import '../../core/network/json.dart';

/// One transaction chat message — buyer and seller only.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String senderRole; // 'buyer' | 'seller'
  final String text;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: asString(j['_id'] ?? j['id']),
    senderId: asString(j['senderId']),
    senderRole: asString(j['senderRole']),
    text: asString(j['text']),
    createdAt: asDateTime(j['createdAt']),
  );
}
