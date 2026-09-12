import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post_model.dart';
import 'post_providers.dart';

/// Posts that require acknowledgment (for admin ack tracker).
///
/// Preserve loading and error states from the authoritative post stream so the
/// tracker never presents a failed load as an empty, completed inbox.
final postsRequiringAckProvider = Provider<AsyncValue<List<PostModel>>>((ref) {
  final allPosts = ref.watch(postsStreamProvider(null));
  return allPosts.whenData(
    (posts) => posts.where((post) => post.requiresAck).toList(),
  );
});
