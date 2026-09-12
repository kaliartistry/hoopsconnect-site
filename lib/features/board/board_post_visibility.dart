import '../../models/post_model.dart';
import '../../models/user_model.dart';

/// Applies role-preview visibility to already-authorized Board data.
///
/// Repository and route authorization continue to use the real membership.
bool postIsVisibleInBoardPresentation(PostModel post, UserModel? user) {
  if (user?.isFan != true) return true;
  return post.visibility == PostVisibility.public && !post.requiresAck;
}
