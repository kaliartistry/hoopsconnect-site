import 'package:cloud_firestore/cloud_firestore.dart';

enum PostType { announcement, refRequest, gymAvailable, general }

/// Who can see a post on the board. Wireframe §02 A5.
/// `public` is the default — fans + media + reps + admin all see it.
/// `internal` hides the post from fans (admin-internal communications).
enum PostVisibility { public, internal }

PostVisibility _visibilityFromString(String? raw) {
  if (raw == null) return PostVisibility.public;
  return PostVisibility.values.firstWhere(
    (v) => v.name == raw,
    orElse: () => PostVisibility.public,
  );
}

class AckExpectedEntry {
  final String name;
  final String teamName;
  final String? phone;

  const AckExpectedEntry({
    required this.name,
    required this.teamName,
    this.phone,
  });

  factory AckExpectedEntry.fromMap(Map<String, dynamic> map) {
    return AckExpectedEntry(
      name: map['name'] as String,
      teamName: map['teamName'] as String,
      phone: map['phone'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'teamName': teamName,
        'phone': phone,
      };
}

class AckStatusEntry {
  final DateTime ackedAt;
  final String name;
  final String teamName;

  const AckStatusEntry({
    required this.ackedAt,
    required this.name,
    required this.teamName,
  });

  factory AckStatusEntry.fromMap(Map<String, dynamic> map) {
    return AckStatusEntry(
      ackedAt: (map['ackedAt'] as Timestamp).toDate(),
      name: map['name'] as String,
      teamName: map['teamName'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'ackedAt': Timestamp.fromDate(ackedAt),
        'name': name,
        'teamName': teamName,
      };
}

class PostModel {
  final String id;
  final String authorId;
  final String authorName;
  final String authorRole;
  final String? teamId;
  final String? teamName;
  final PostType type;
  final String title;
  final String body;
  final String? imageUrl;
  final String? divisionFilter;
  final bool pinned;
  final bool urgent;
  final PostVisibility visibility;
  final DateTime createdAt;
  final Map<String, int> reactions;

  /// Set by Cloud Function `onAckWrite` once all expected acks have landed.
  /// Archived ack-required posts drop off the tracker and the rep board feed.
  final bool archived;

  // Acknowledgment fields
  final bool requiresAck;
  final DateTime? ackDeadline;
  final String? ackTargetScope;
  final Map<String, AckExpectedEntry> expectedAcks;
  final Map<String, AckStatusEntry> ackStatus;
  final int ackRemindersSent;

  const PostModel({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorRole,
    this.teamId,
    this.teamName,
    required this.type,
    required this.title,
    required this.body,
    this.imageUrl,
    this.divisionFilter,
    this.pinned = false,
    this.urgent = false,
    this.visibility = PostVisibility.public,
    this.archived = false,
    required this.createdAt,
    this.reactions = const {},
    this.requiresAck = false,
    this.ackDeadline,
    this.ackTargetScope,
    this.expectedAcks = const {},
    this.ackStatus = const {},
    this.ackRemindersSent = 0,
  });

  factory PostModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    final expectedAcksRaw =
        data['expectedAcks'] as Map<String, dynamic>? ?? {};
    final ackStatusRaw = data['ackStatus'] as Map<String, dynamic>? ?? {};

    return PostModel(
      id: doc.id,
      authorId: data['authorId'] as String,
      authorName: data['authorName'] as String,
      authorRole: data['authorRole'] as String,
      teamId: data['teamId'] as String?,
      teamName: data['teamName'] as String?,
      type: PostType.values.byName(
        (data['type'] as String).replaceAll('-', ''),
      ),
      title: data['title'] as String,
      body: data['body'] as String,
      imageUrl: data['imageUrl'] as String?,
      divisionFilter: data['divisionFilter'] as String?,
      pinned: data['pinned'] as bool? ?? false,
      urgent: data['urgent'] as bool? ?? false,
      visibility: _visibilityFromString(data['visibility'] as String?),
      archived: data['archived'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      reactions: Map<String, int>.from(data['reactions'] ?? {}),
      requiresAck: data['requiresAck'] as bool? ?? false,
      ackDeadline: data['ackDeadline'] != null
          ? (data['ackDeadline'] as Timestamp).toDate()
          : null,
      ackTargetScope: data['ackTargetScope'] as String?,
      expectedAcks: expectedAcksRaw.map(
        (k, v) =>
            MapEntry(k, AckExpectedEntry.fromMap(v as Map<String, dynamic>)),
      ),
      ackStatus: ackStatusRaw.map(
        (k, v) =>
            MapEntry(k, AckStatusEntry.fromMap(v as Map<String, dynamic>)),
      ),
      ackRemindersSent: data['ackRemindersSent'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'authorRole': authorRole,
      'teamId': teamId,
      'teamName': teamName,
      'type': type.name,
      'title': title,
      'body': body,
      'imageUrl': imageUrl,
      'divisionFilter': divisionFilter,
      'pinned': pinned,
      'urgent': urgent,
      'visibility': visibility.name,
      'archived': archived,
      'createdAt': Timestamp.fromDate(createdAt),
      'reactions': reactions,
      'requiresAck': requiresAck,
      'ackDeadline':
          ackDeadline != null ? Timestamp.fromDate(ackDeadline!) : null,
      'ackTargetScope': ackTargetScope,
      'expectedAcks':
          expectedAcks.map((k, v) => MapEntry(k, v.toMap())),
      'ackStatus': ackStatus.map((k, v) => MapEntry(k, v.toMap())),
      'ackRemindersSent': ackRemindersSent,
    };
  }

  bool get isAssociationPost => teamId == null;
  int get ackCount => ackStatus.length;
  int get expectedAckCount => expectedAcks.length;
  double get ackProgress =>
      expectedAckCount > 0 ? ackCount / expectedAckCount : 0;
  bool hasUserAcked(String userId) => ackStatus.containsKey(userId);
  bool isAckOverdue() =>
      requiresAck && ackDeadline != null && DateTime.now().isAfter(ackDeadline!);
}
