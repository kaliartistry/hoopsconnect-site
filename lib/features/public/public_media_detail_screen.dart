import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../core/widgets/app_state_message.dart';
import '../../core/widgets/public_brand_context.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_artifact_release_validator.dart';

/// A stable public destination for a single story, readable with or without
/// an account. Only items from the public release are shown or shared.
class PublicMediaDetailRouteScreen extends ConsumerWidget {
  const PublicMediaDetailRouteScreen({
    super.key,
    required this.mediaId,
    this.canonicalUri,
  });

  final String mediaId;
  final Uri? canonicalUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final release = ref.watch(publicLeagueSnapshotProvider);
    return release.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const Scaffold(
        body: Center(
          child: AppStateMessage(
            title: 'Media unavailable',
            message: 'The public feed could not be loaded. Try again later.',
          ),
        ),
      ),
      data: (snapshot) {
        final item = snapshot?.media
            .where((entry) => entry.mediaId == mediaId)
            .firstOrNull;
        if (snapshot == null || !snapshot.version.isPublished || item == null) {
          return const Scaffold(
            body: Center(
              child: AppStateMessage(
                title: 'Story unavailable',
                message: 'This story is not in the current public feed.',
              ),
            ),
          );
        }
        return PublicMediaDetailScreen(
          snapshot: snapshot,
          item: item,
          canonicalUri: canonicalUri,
        );
      },
    );
  }
}

class PublicMediaDetailScreen extends ConsumerStatefulWidget {
  const PublicMediaDetailScreen({
    super.key,
    required this.snapshot,
    required this.item,
    this.canonicalUri,
    this.releaseValidator,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicMediaItem item;
  final Uri? canonicalUri;
  final PublicArtifactReleaseValidator? releaseValidator;

  @override
  ConsumerState<PublicMediaDetailScreen> createState() =>
      _PublicMediaDetailScreenState();
}

class _PublicMediaDetailScreenState
    extends ConsumerState<PublicMediaDetailScreen> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final league = widget.snapshot.leagueForDivision(widget.item.divisionId);
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFF4F5F6)
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(PublicRoutePaths.media),
          tooltip: 'Back to media',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Media'),
        actions: [
          if (widget.snapshot.canCreatePublishedArtifacts)
            IconButton(
              key: const Key('public-media-detail-share'),
              onPressed: _sharing ? null : _share,
              tooltip: 'Share this story',
              icon: const Icon(Icons.ios_share_outlined),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 36),
            children: [
              PublicBrandContext(snapshot: widget.snapshot, league: league),
              const SizedBox(height: 18),
              Card(
                elevation: 3,
                shadowColor: const Color(0x330B1A31),
                surfaceTintColor: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.item.imageUrl != null)
                      Image.network(
                        widget.item.imageUrl!,
                        height: 260,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.item.typeLabel.toUpperCase()} · ${DateFormat('MMM d, y').format(widget.item.publishedAt.toLocal())}',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.item.title,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 3,
                            width: 68,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            widget.item.summary,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 28),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilledButton.icon(
                                key: const Key('public-media-share-button'),
                                onPressed:
                                    widget
                                            .snapshot
                                            .canCreatePublishedArtifacts &&
                                        !_sharing
                                    ? _share
                                    : null,
                                icon: const Icon(Icons.ios_share_outlined),
                                label: const Text('Share this story'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.go(PublicRoutePaths.games),
                                icon: const Icon(
                                  Icons.sports_basketball_outlined,
                                ),
                                label: const Text('See games'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    if (_sharing || !widget.snapshot.canCreatePublishedArtifacts) return;
    setState(() => _sharing = true);
    try {
      final binding = PublicArtifactBinding.snapshot(widget.snapshot);
      final PublicArtifactReleaseValidator validator =
          widget.releaseValidator ??
          ref.read(publicArtifactReleaseValidatorProvider);
      final current = await validator.requireCurrent(binding);
      final item = current.snapshot.media
          .where((entry) => entry.mediaId == widget.item.mediaId)
          .firstOrNull;
      if (item == null) {
        throw const PublicArtifactReleaseException(
          'This story was removed from the public feed.',
        );
      }
      if (!mounted) return;
      final league = current.snapshot.leagueForDivision(item.divisionId);
      final branding = publicShareBranding(current.snapshot, league);
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload.publicMedia(
          snapshot: current.snapshot,
          item: item,
          branding: branding,
          canonicalUri: widget.canonicalUri,
        ),
        validateCurrent: () async {
          await validator.requireCurrent(binding);
        },
      );
    } on PublicArtifactReleaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${error.message} Refresh before sharing.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
