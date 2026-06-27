import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post_model.dart';
import 'post_providers.dart';

/// Posts that require acknowledgment (for admin ack tracker).
final postsRequiringAckProvider = StreamProvider<List<PostModel>>((ref) {
  // Filter from the "all posts" stream for posts requiring ack
  final allPosts = ref.watch(postsStreamProvider(null));
  return allPosts.when(
    data: (posts) => Stream.value(posts.where((p) => p.requiresAck).toList()),
    loading: () => Stream.value([]),
    error: (_, _) => Stream.value([]),
  );
});
