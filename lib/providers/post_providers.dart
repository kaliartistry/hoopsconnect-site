import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post_model.dart';
import '../services/repositories/post_repository.dart';
import 'auth_providers.dart';

final postRepositoryProvider = Provider((ref) => PostRepository());

/// Stream of board posts, optionally filtered by division.
/// Fans get only public posts — admin-internal communications are hidden.
final postsStreamProvider =
    StreamProvider.family<List<PostModel>, String?>((ref, divisionFilter) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value([]);

  final user = ref.watch(currentUserProvider).valueOrNull;
  final includeInternal = !(user?.isFan ?? true);

  return ref.watch(postRepositoryProvider).watchPosts(
        assocId,
        divisionFilter: divisionFilter,
        includeInternal: includeInternal,
      );
});

/// Watch a single post by ID (for ack detail screen).
final postDetailProvider =
    StreamProvider.family<PostModel?, String>((ref, postId) {
  final assocId = ref.watch(currentAssociationIdProvider);
  if (assocId == null) return Stream.value(null);

  return ref.watch(postRepositoryProvider).watchPost(assocId, postId);
});
