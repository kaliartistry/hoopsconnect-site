import 'package:cloud_firestore/cloud_firestore.dart';

class InboxNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final String? gameId;
  final DateTime? createdAt;
  final DateTime? readAt;

  const InboxNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.gameId,
    this.createdAt,
    this.readAt,
  });

  factory InboxNotification.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return InboxNotification(
      id: doc.id,
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? 'Team update',
      body: data['body'] as String? ?? '',
      gameId: data['gameId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }
}
