import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/constants/firestore_paths.dart';
import '../../models/inbox_notification.dart';

class InboxRepository {
  final FirebaseFirestore _db;

  InboxRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Stream<List<InboxNotification>> watchRecent(String userId) => _db
      .collection(FirestorePaths.userNotifications(userId))
      .withConverter<InboxNotification>(
        fromFirestore: (snapshot, _) =>
            InboxNotification.fromFirestore(snapshot),
        toFirestore: (_, _) => throw UnsupportedError('Inbox is server-owned'),
      )
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());

  Stream<int> watchUnreadCount(String userId) => _db
      .collection(FirestorePaths.userNotifications(userId))
      .where('readAt', isNull: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.size);

  Future<void> markRead(String userId, String notificationId) => _db
      .doc(FirestorePaths.userNotification(userId, notificationId))
      .update({'readAt': FieldValue.serverTimestamp()});
}
