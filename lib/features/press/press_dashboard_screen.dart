import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/sharing/artifact_downloader.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/auth_providers.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_stat_export_service.dart';
import '../public/public_player_detail_screen.dart';

class PressDashboardScreen extends ConsumerWidget {
  final ArtifactDownloader? downloader;

  const PressDashboardScreen({super.key, this.downloader});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Media Dashboard')),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: [
          const _PressCredentialCard(),
          const SizedBox(height: 20),
          const _RecentResultsSection(),
          const SizedBox(height: 20),
          const _TodaysGamesSection(),
          const SizedBox(height: 20),
          const _SeasonLeadersSection(),
          const SizedBox(height: 20),
          _SeasonExportSection(downloader: downloader),
          const SizedBox(height: 20),
          const _CompareButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A. Digital Press Credential Card
// ---------------------------------------------------------------------------

class _PressCredentialCard extends ConsumerWidget {
  const _PressCredentialCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final seasonName = ref
        .watch(publicLeagueSnapshotProvider)
        .value
        ?.seasonName;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // slate-800
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: badge + accredited label
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: const Icon(
                  Icons.sports_basketball,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACCREDITED MEDIA',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Jamaica Basketball Association',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 16),

          // Name
          Text(
            user?.displayName ?? 'Press Member',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (seasonName != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: Colors.white38,
                ),
                const SizedBox(width: 6),
                Text(
                  seasonName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// B. Recent Results Section
// ---------------------------------------------------------------------------

class _RecentResultsSection extends ConsumerWidget {
  const _RecentResultsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(publicLeagueSnapshotProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Results',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        resultsAsync.when(
          data: (snapshot) {
            if (snapshot == null ||
                snapshot.version.state != PublicReleaseState.published) {
              return const _MiniEmpty(
                icon: Icons.cloud_off_outlined,
                text: 'Published results unavailable',
              );
            }
            final results =
                snapshot.schedule
                    .where((game) => game.isFinal)
                    .toList(growable: false)
                  ..sort((a, b) => b.startTime.compareTo(a.startTime));
            final recent = results.take(5).toList(growable: false);
            if (recent.isEmpty) {
              return const _MiniEmpty(
                icon: Icons.scoreboard_outlined,
                text: 'No published results',
              );
            }
            return Column(
              children: recent
                  .map((game) => _RecentResultCard(game: game))
                  .toList(growable: false),
            );
          },
          loading: () => const _BoundedSkeleton(count: 3),
          error: (_, _) => const _MiniEmpty(
            icon: Icons.cloud_off_outlined,
            text: 'Could not load published results',
          ),
        ),
      ],
    );
  }
}

class _RecentResultCard extends StatelessWidget {
  final PublicGame game;

  const _RecentResultCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final dateStr = LeagueTime.formatJamaicaDate(
      game.startTime,
      pattern: 'MMM d, yyyy',
    );

    return GestureDetector(
      onTap: () => context.push('/press/summary/${game.gameId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          children: [
            // Teams & score
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.homeTeamName ?? 'Home team unavailable',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: game.homeScore! >= game.awayScore!
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${game.homeScore}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: game.homeScore! >= game.awayScore!
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.awayTeamName ?? 'Away team unavailable',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: game.awayScore! >= game.homeScore!
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${game.awayScore}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: game.awayScore! >= game.homeScore!
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Date + arrow
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'FINAL',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// C. Today's Schedule Section
// ---------------------------------------------------------------------------

class _TodaysGamesSection extends ConsumerWidget {
  const _TodaysGamesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Games",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        snapshotAsync.when(
          data: (snapshot) {
            if (snapshot == null || !snapshot.version.isPublished) {
              return const _MiniEmpty(
                icon: Icons.cloud_off_outlined,
                text: 'Published schedule unavailable',
              );
            }
            final today = LeagueTime.jamaicaDate(DateTime.now());
            final games =
                snapshot.schedule
                    .where((game) {
                      final date = LeagueTime.jamaicaDate(game.startTime);
                      return date == today;
                    })
                    .toList(growable: false)
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));
            if (games.isEmpty) {
              return const _MiniEmpty(
                icon: Icons.event_busy_outlined,
                text: 'No games scheduled today',
              );
            }
            return Column(
              children: games
                  .map((game) => _TodayGameCard(game: game))
                  .toList(),
            );
          },
          loading: () => const _BoundedSkeleton(count: 2),
          error: (_, _) => const _MiniEmpty(
            icon: Icons.cloud_off_outlined,
            text: 'Could not load the published schedule',
          ),
        ),
      ],
    );
  }
}

class _TodayGameCard extends StatelessWidget {
  final PublicGame game;

  const _TodayGameCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final timeStr = LeagueTime.formatJamaicaTime(game.startTime);

    return Semantics(
      button: true,
      label: 'Open published game ${game.title}',
      child: InkWell(
        onTap: () => context.push('/press/summary/${game.gameId}'),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: const Icon(
                  Icons.sports_basketball,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 13,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (game.venue != null) ...[
                          const SizedBox(width: 12),
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              game.venue!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// D. Quick Stats / Season Leaders Section
// ---------------------------------------------------------------------------

class _SeasonLeadersSection extends ConsumerWidget {
  const _SeasonLeadersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Season Leaders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        snapshotAsync.when(
          loading: () => const _BoundedSkeleton(count: 3),
          error: (_, _) => const _MiniEmpty(
            icon: Icons.cloud_off_outlined,
            text: 'Could not load published leaders',
          ),
          data: (snapshot) {
            if (snapshot == null || !snapshot.version.isPublished) {
              return const _MiniEmpty(
                icon: Icons.cloud_off_outlined,
                text: 'Published leaders unavailable',
              );
            }
            return Column(
              children: [
                _LeaderRow(
                  snapshot: snapshot,
                  category: 'ppg',
                  label: 'TOP SCORER',
                  icon: Icons.whatshot,
                  iconColor: AppColors.urgent,
                  unit: 'PTS',
                ),
                const SizedBox(height: 8),
                _LeaderRow(
                  snapshot: snapshot,
                  category: 'rpg',
                  label: 'TOP REBOUNDER',
                  icon: Icons.sports_handball,
                  iconColor: AppColors.info,
                  unit: 'REB',
                ),
                const SizedBox(height: 8),
                _LeaderRow(
                  snapshot: snapshot,
                  category: 'apg',
                  label: 'TOP ASSISTS',
                  icon: Icons.handshake_outlined,
                  iconColor: AppColors.success,
                  unit: 'AST',
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final String category;
  final String label;
  final IconData icon;
  final Color iconColor;
  final String unit;

  const _LeaderRow({
    required this.snapshot,
    required this.category,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    PublicLeaderboard? selectedBoard;
    for (final board in snapshot.leaderboards) {
      if (board.category.toLowerCase() != category || board.rankings.isEmpty) {
        continue;
      }
      selectedBoard ??= board;
      if (board.divisionId == null) {
        selectedBoard = board;
        break;
      }
    }
    final leader = selectedBoard?.rankings.first;
    if (leader == null) return _miniLeaderPlaceholder(label);
    final detail = leader.playerId == null
        ? null
        : snapshot.playerDetail(leader.playerId!);

    return InkWell(
      onTap: detail == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PublicPlayerDetailScreen(
                  snapshot: snapshot,
                  detail: detail,
                ),
              ),
            ),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedBoard!.divisionId == null
                        ? label
                        : '$label · ${snapshot.divisionName(selectedBoard.divisionId)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    leader.displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    leader.teamName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  leader.value?.toStringAsFixed(1) ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.statHighlight,
                  ),
                ),
                Text(
                  unit,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniLeaderPlaceholder(String lbl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor.withValues(alpha: 0.4), size: 22),
          const SizedBox(width: 10),
          Text(
            lbl,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const Spacer(),
          const Text(
            'Unavailable',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// E. Version-bound media export
// ---------------------------------------------------------------------------

class _SeasonExportSection extends ConsumerStatefulWidget {
  final ArtifactDownloader? downloader;

  const _SeasonExportSection({this.downloader});

  @override
  ConsumerState<_SeasonExportSection> createState() =>
      _SeasonExportSectionState();
}

class _SeasonExportSectionState extends ConsumerState<_SeasonExportSection> {
  late final ArtifactDownloader _downloader;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _downloader = widget.downloader ?? createArtifactDownloader();
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(publicLeagueSnapshotProvider);
    final canExport =
        ref.watch(currentUserProvider).valueOrNull?.canExportStats ?? false;
    final snapshot = snapshotAsync.valueOrNull;
    final available =
        canExport &&
        _downloader.isSupported &&
        snapshot != null &&
        snapshot.canCreatePublishedArtifacts;

    final message = !canExport
        ? 'Your current role does not include the stats.export capability.'
        : snapshotAsync.isLoading
        ? 'Checking the current public publication version.'
        : snapshotAsync.hasError
        ? 'The published data could not be loaded. No private stats were used.'
        : snapshot == null
        ? 'There is no public snapshot available for export.'
        : !snapshot.version.isPublished
        ? 'The public release is unavailable or withdrawn.'
        : !snapshot.version.isVersioned
        ? 'This legacy snapshot has no verifiable publication version.'
        : !snapshot.version.isCompatibilityArtifactEligible
        ? 'This publication has not passed the compatibility export check.'
        : !_downloader.isSupported
        ? 'Downloads are not supported on this platform. Use the public result views and their Copy option instead.'
        : 'Includes games, results, standings, and cleared leader/player fields from publication ${snapshot.version.shortLabel}.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Media Export',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(message),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: available && !_downloading
                      ? () => _download(snapshot)
                      : null,
                  icon: _downloading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(
                    _downloading ? 'Saving season CSV…' : 'Download season CSV',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _download(PublicLeagueSnapshot snapshot) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final csv = PublicStatExportService.seasonCsv(
        snapshot: snapshot,
        grant: PublicExportGrant.media,
      );
      if (!_downloader.isSupported) {
        throw UnsupportedError('Downloads are unavailable.');
      }
      final fileName =
          '${_fileSlug(snapshot.leagueShortName)}-${_fileSlug(snapshot.seasonId)}-${snapshot.version.shortLabel}.csv';
      final destination = await _downloader.download(
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Season CSV download started for $destination')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the season CSV. No file was downloaded.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// F. Head-to-Head Compare Button
// ---------------------------------------------------------------------------

class _CompareButton extends StatelessWidget {
  const _CompareButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => context.push('/press/head-to-head'),
        icon: const Icon(Icons.compare_arrows, size: 22),
        label: const Text(
          'Head-to-Head Compare',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small empty state widget
// ---------------------------------------------------------------------------

class _MiniEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MiniEmpty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoundedSkeleton extends StatelessWidget {
  final int count;

  const _BoundedSkeleton({required this.count});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: count * 72,
    child: SkeletonListTileList(count: count),
  );
}

String _fileSlug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'hoopsconnect' : slug;
}
