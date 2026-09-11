import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/widgets/responsive_layout.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_display.dart';
import '../../core/widgets/empty_state.dart';
import '../../models/post_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/role_preview_provider.dart';
import '../../providers/post_providers.dart';
import 'board_post_visibility.dart';
import 'widgets/post_card.dart';
import 'widgets/post_detail_panel.dart';

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  String? _selectedFilter;

  /// Selected post ID for the desktop 2-column detail panel.
  String? _selectedPostId;

  void _confirmDeletePost(BuildContext context, WidgetRef ref, String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.urgent),
            onPressed: () async {
              final assocId = ref.read(currentAssociationIdProvider);
              final actingUser = ref.read(currentUserProvider).valueOrNull;
              if (assocId != null && actingUser?.canEditAnyPost == true) {
                await ref
                    .read(postRepositoryProvider)
                    .deletePost(assocId, postId);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDivisionName = ref.watch(selectedDivisionNameProvider);
    final postsAsync = ref.watch(postsStreamProvider(selectedDivisionName));
    // Preview capabilities control presentation only. Every repository action
    // below rechecks the real membership-backed user.
    final currentUser = ref.watch(effectiveUserProvider);
    final assocId = ref.watch(currentAssociationIdProvider);
    final desktop = isDesktop(context);
    var selectedPostIdForDisplay = _selectedPostId;

    // Local board filters are post-type filters. League scope is handled globally.
    final filters = <String?>[null, 'announcements'];
    final filterLabels = <String>['All Posts', 'Announcements'];

    final filterBar = SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final isSelected = _selectedFilter == filters[i];
          return FilterChip(
            label: Text(filterLabels[i]),
            selected: isSelected,
            onSelected: (_) {
              setState(() => _selectedFilter = filters[i]);
            },
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            showCheckmark: false,
            side: BorderSide.none,
          );
        },
      ),
    );

    // Show clear message if user's association isn't loaded
    if (assocId == null && currentUser == null) {
      return Scaffold(
        appBar: _buildAppBar(currentUser),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (assocId == null) {
      return Scaffold(
        appBar: _buildAppBar(currentUser),
        body: const ErrorDisplay(
          error:
              'Unable to load your league data. Please sign out and sign back in.',
        ),
      );
    }

    Widget postList = postsAsync.when(
      data: (posts) {
        final roleVisiblePosts = posts
            .where(
              (post) => postIsVisibleInBoardPresentation(post, currentUser),
            )
            .toList();
        final visiblePosts = _selectedFilter == 'announcements'
            ? roleVisiblePosts
                  .where((post) => post.type == PostType.announcement)
                  .toList()
            : roleVisiblePosts;

        if (desktop) {
          final selectionIsVisible = visiblePosts.any(
            (post) => post.id == _selectedPostId,
          );
          selectedPostIdForDisplay = selectionIsVisible
              ? _selectedPostId
              : visiblePosts.isEmpty
              ? null
              : visiblePosts.first.id;
          if (_selectedPostId != selectedPostIdForDisplay) {
            final nextSelection = selectedPostIdForDisplay;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedPostId != nextSelection) {
                setState(() => _selectedPostId = nextSelection);
              }
            });
          }
        }

        if (visiblePosts.isEmpty) {
          return EmptyState(
            icon: Icons.dashboard_outlined,
            title: 'No posts yet',
            subtitle: selectedDivisionName == null
                ? 'Posts from your league will appear here'
                : 'Posts for $selectedDivisionName will appear here',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(postsStreamProvider(selectedDivisionName));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: visiblePosts.length,
            itemBuilder: (context, i) {
              final post = visiblePosts[i];
              final canEdit = currentUser?.canEditAnyPost ?? false;
              final canAcknowledge =
                  currentUser?.hasCapability('posts.acknowledge') ?? false;
              final isSelected = desktop && selectedPostIdForDisplay == post.id;
              return Container(
                decoration: isSelected
                    ? BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 2),
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                      )
                    : null,
                child: PostCard(
                  post: post,
                  currentUserId: currentUser?.id,
                  canEditDelete: canEdit,
                  onTap: () {
                    if (desktop) {
                      setState(() => _selectedPostId = post.id);
                    } else {
                      context.push('/board/post/${post.id}');
                    }
                  },
                  onEdit: canEdit
                      ? () => context.push('/board/edit/${post.id}')
                      : null,
                  onDelete: canEdit
                      ? () => _confirmDeletePost(context, ref, post.id)
                      : null,
                  onAcknowledge: !canAcknowledge
                      ? null
                      : () {
                          final actingUser = ref
                              .read(currentUserProvider)
                              .valueOrNull;
                          if (actingUser != null &&
                              actingUser.hasCapability('posts.acknowledge')) {
                            ref
                                .read(postRepositoryProvider)
                                .acknowledge(assocId, post.id);
                          }
                        },
                ),
              );
            },
          ),
        );
      },
      loading: () => const SkeletonCardList(),
      error: (e, _) => ErrorDisplay(
        error: e,
        onRetry: () =>
            ref.invalidate(postsStreamProvider(selectedDivisionName)),
      ),
    );

    final body = Column(
      children: [
        filterBar,
        Expanded(child: postList),
      ],
    );

    if (desktop) {
      return Scaffold(
        appBar: _buildAppBar(currentUser),
        body: Row(
          children: [
            // Left: post list
            SizedBox(width: 420, child: body),
            const VerticalDivider(thickness: 1, width: 1),
            // Right: post detail
            Expanded(
              child: selectedPostIdForDisplay != null
                  ? PostDetailPanel(
                      key: ValueKey(selectedPostIdForDisplay),
                      postId: selectedPostIdForDisplay!,
                    )
                  : const EmptyState(
                      icon: Icons.article_outlined,
                      title: 'Select a post',
                      subtitle: 'Choose a post from the list to view details',
                    ),
            ),
          ],
        ),
      );
    }

    // Mobile / tablet: single column
    return Scaffold(appBar: _buildAppBar(currentUser), body: body);
  }

  PreferredSizeWidget _buildAppBar(UserModel? currentUser) {
    return AppBar(
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/images/jba_logo.png',
              width: 28,
              height: 28,
            ),
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text('JA HoopsConnect', overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        // Role badge
        if (currentUser != null)
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                currentUser.isSuperAdmin
                    ? 'SUPER ADMIN'
                    : currentUser.role.name.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        if (currentUser != null && currentUser.canCreatePost)
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => context.push('/board/create'),
          ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: () => context.push('/about'),
        ),
        GestureDetector(
          onTap: () => context.push('/profile'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: Text(
                currentUser != null && currentUser.displayName.isNotEmpty
                    ? currentUser.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
