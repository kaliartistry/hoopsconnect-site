import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/post_model.dart';

class PostRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<PostModel> _postsRef(String assocId) {
    return _db
        .collection(FirestorePaths.posts(assocId))
        .withConverter<PostModel>(
          fromFirestore: (snap, _) => PostModel.fromFirestore(snap),
          toFirestore: (model, _) => model.toFirestore(),
        );
  }

  /// Watch posts with optional division filter, ordered by pinned then date.
  ///
  /// [includeInternal] should be `false` for fans — admin-internal posts are
  /// hidden from public surfaces (wireframe §02 A5).
  Stream<List<PostModel>> watchPosts(
    String assocId, {
    String? divisionFilter,
    int limit = 20,
    bool includeInternal = true,
  }) {
    Query<PostModel> query = _postsRef(assocId);
    if (!includeInternal) {
      // Firestore rules cannot rely on client-side filtering. Fan queries must
      // prove that every returned document is public and carries no ack PII.
      query = query
          .where('visibility', isEqualTo: PostVisibility.public.name)
          .where('requiresAck', isEqualTo: false);
    }
    query = query
        .orderBy('pinned', descending: true)
        .orderBy('createdAt', descending: true);

    return query.snapshots().map((snap) {
      final posts = snap.docs.map((d) => d.data());

      final visiblePosts = posts
          .where((post) {
            // Drop posts that have completed their ack lifecycle.
            if (post.archived) return false;
            if (!includeInternal &&
                post.visibility == PostVisibility.internal) {
              return false;
            }
            if (divisionFilter == null) return true;

            final postScope = post.divisionFilter;
            return postScope == null ||
                postScope.isEmpty ||
                postScope == divisionFilter;
          })
          .take(limit)
          .toList();

      return visiblePosts;
    });
  }

  /// Watch a single post (for ack detail screen).
  Stream<PostModel?> watchPost(String assocId, String postId) {
    return _postsRef(
      assocId,
    ).doc(postId).snapshots().map((snap) => snap.exists ? snap.data() : null);
  }

  Future<void> createPost(String assocId, PostModel post) {
    if (post.id.isEmpty) {
      return _postsRef(assocId).add(post);
    }
    return _postsRef(assocId).doc(post.id).set(post);
  }

  Future<void> updatePost(
    String assocId,
    String postId,
    Map<String, dynamic> data,
  ) {
    return _db.doc(FirestorePaths.post(assocId, postId)).update(data);
  }

  Future<void> deletePost(String assocId, String postId) {
    return _db.doc(FirestorePaths.post(assocId, postId)).delete();
  }

  /// Record an acknowledgment from a user.
  Future<void> acknowledge(String assocId, String postId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw StateError('Sign in before acknowledging a post.');
    }
    final postRef = _db.doc(FirestorePaths.post(assocId, postId));
    await _db.runTransaction((transaction) async {
      final snap = await transaction.get(postRef);
      final data = snap.data();
      final expected = data?['expectedAcks'] as Map<String, dynamic>?;
      final entry = expected?[userId] as Map<String, dynamic>?;
      if (entry == null) {
        throw StateError('This acknowledgment is not assigned to you.');
      }
      final current = data?['ackStatus'] as Map<String, dynamic>? ?? {};
      if (current.containsKey(userId)) return;
      transaction.update(postRef, {
        'ackStatus.$userId': {
          'ackedAt': FieldValue.serverTimestamp(),
          'name': entry['name'],
          'teamName': entry['teamName'],
        },
      });
    });
  }

  /// Mark a manual reminder request on a post. The scheduled cloud function
  /// `ackDeadlineChecker` will re-send FCM to all pending reps on its next run.
  /// Wireframe §02 A1 — admin bulk-remind action.
  Future<void> requestManualAckReminder(String assocId, String postId) {
    return _db.doc(FirestorePaths.post(assocId, postId)).update({
      'lastManualReminderAt': Timestamp.now(),
      'ackRemindersSent': FieldValue.increment(1),
    });
  }

  /// Toggle a reaction on a post.
  Future<void> toggleReaction(
    String assocId,
    String postId,
    String emoji,
    int delta,
  ) {
    return _db.doc(FirestorePaths.post(assocId, postId)).update({
      'reactions.$emoji': FieldValue.increment(delta),
    });
  }
}
