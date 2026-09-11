import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../models/game_stats_model.dart';
import '../../models/player_season_stats_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/error_display.dart';
import '../../core/utils/error_mapper.dart';
import 'stats_validator.dart';

class StatEntryScreen extends ConsumerStatefulWidget {
  final String eventId;
  const StatEntryScreen({super.key, required this.eventId});

  @override
  ConsumerState<StatEntryScreen> createState() => _StatEntryScreenState();
}

class _StatEntryScreenState extends ConsumerState<StatEntryScreen> {
  GameStatsModel? _localStats;
  bool _isSaving = false;
  bool _isInitializing = false;
  final _nameController = TextEditingController();

  static const _statColumns = [
    'MIN',
    'PTS',
    'OREB',
    'DREB',
    'AST',
    'STL',
    'BLK',
    'FLS',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _initLocalStats(GameStatsModel? stats) {
    if (_localStats == null && stats != null) {
      _localStats = stats;
      // When opening post-game entry for existing live stats, switch the
      // entry mode so correction saves are tagged correctly.
      if (_localStats!.entryMode == GameStatsEntryMode.live) {
        _localStats = GameStatsModel(
          id: _localStats!.id,
          eventId: _localStats!.eventId,
          seasonId: _localStats!.seasonId,
          divisionId: _localStats!.divisionId,
          homeTeamId: _localStats!.homeTeamId,
          awayTeamId: _localStats!.awayTeamId,
          homeTeamName: _localStats!.homeTeamName,
          awayTeamName: _localStats!.awayTeamName,
          homeScore: _localStats!.homeScore,
          awayScore: _localStats!.awayScore,
          status: _localStats!.status,
          entryMode: GameStatsEntryMode.postGame,
          playerLines: _localStats!.playerLines,
          homeQuarterScores: _localStats!.homeQuarterScores,
          awayQuarterScores: _localStats!.awayQuarterScores,
          playerQuarterStats: _localStats!.playerQuarterStats,
        );
      }
    }
  }

  /// Submitted-but-not-yet-approved stats. Editable by admin (correction).
  bool get _isCorrectionMode =>
      _localStats?.status == GameStatsStatus.submitted;

  /// Approved stats are locked. Read-only view.
  bool get _isReadOnly => _localStats?.status == GameStatsStatus.approved;

  /// Stats sent back to the statistician with a note.
  bool get _isRejected => _localStats?.status == GameStatsStatus.rejected;

  ({String homeTeamName, String awayTeamName}) _parseTeamNames(String title) {
    final parts = title.split(' vs ');
    if (parts.length == 2) {
      return (homeTeamName: parts[0].trim(), awayTeamName: parts[1].trim());
    }

    return (homeTeamName: 'Home', awayTeamName: 'Away');
  }

  /// Auto-create a GameStatsModel from event data and save to Firestore.
  Future<void> _initializeFromEvent({
    required String seasonId,
    required String homeTeamId,
    required String awayTeamId,
    required String homeTeamName,
    required String awayTeamName,
    required List<PlayerSeasonStatsModel> homeRoster,
    required List<PlayerSeasonStatsModel> awayRoster,
  }) async {
    setState(() => _isInitializing = true);
    try {
      final assocId = ref.read(currentAssociationIdProvider);
      final event = ref.read(eventDetailProvider(widget.eventId)).value;

      if (assocId == null || event == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Missing association or event data')),
          );
        }
        return;
      }

      // Pre-populate with roster players from both teams
      final Map<String, PlayerStatLine> playerLines = {};

      for (final player in homeRoster) {
        playerLines[player.playerId] = PlayerStatLine(
          name: player.playerName,
          teamId: homeTeamId,
        );
      }

      for (final player in awayRoster) {
        playerLines[player.playerId] = PlayerStatLine(
          name: player.playerName,
          teamId: awayTeamId,
        );
      }

      final newStats = GameStatsModel(
        id: widget.eventId,
        eventId: widget.eventId,
        seasonId: seasonId,
        divisionId: event.divisionId ?? '',
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
        homeTeamName: homeTeamName,
        awayTeamName: awayTeamName,
        entryMode: GameStatsEntryMode.postGame,
        playerLines: playerLines,
      );

      // Save to Firestore so the stream picks it up
      await ref.read(statsRepositoryProvider).saveGameStats(assocId, newStats);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stats record initialized')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error initializing: $e')));
      }
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  void _updateStat(String playerId, String stat, int value) {
    if (_localStats == null) return;
    final line = _localStats!.playerLines[playerId];
    if (line == null) return;

    PlayerStatLine updated;
    switch (stat) {
      case 'MIN':
        updated = line.copyWith(min: value);
      case 'PTS':
        updated = line.copyWith(pts: value);
      case 'OREB':
        updated = line.copyWith(oreb: value);
      case 'DREB':
        updated = line.copyWith(dreb: value);
      case 'AST':
        updated = line.copyWith(ast: value);
      case 'STL':
        updated = line.copyWith(stl: value);
      case 'BLK':
        updated = line.copyWith(blk: value);
      case 'FLS':
        updated = line.copyWith(fls: value);
      default:
        return;
    }

    setState(() {
      final newLines = Map<String, PlayerStatLine>.from(
        _localStats!.playerLines,
      );
      newLines[playerId] = updated;

      // Recalculate team scores
      int homeScore = 0;
      int awayScore = 0;
      for (final entry in newLines.entries) {
        if (entry.value.teamId == _localStats!.homeTeamId) {
          homeScore += entry.value.pts;
        } else {
          awayScore += entry.value.pts;
        }
      }

      _localStats = GameStatsModel(
        id: _localStats!.id,
        eventId: _localStats!.eventId,
        seasonId: _localStats!.seasonId,
        divisionId: _localStats!.divisionId,
        homeTeamId: _localStats!.homeTeamId,
        awayTeamId: _localStats!.awayTeamId,
        homeTeamName: _localStats!.homeTeamName,
        awayTeamName: _localStats!.awayTeamName,
        homeScore: homeScore,
        awayScore: awayScore,
        status: _localStats!.status,
        entryMode: _localStats!.entryMode,
        playerLines: newLines,
      );
    });
  }

  int _getStatValue(PlayerStatLine line, String stat) {
    switch (stat) {
      case 'MIN':
        return line.min;
      case 'PTS':
        return line.pts;
      case 'OREB':
        return line.oreb;
      case 'DREB':
        return line.dreb;
      case 'AST':
        return line.ast;
      case 'STL':
        return line.stl;
      case 'BLK':
        return line.blk;
      case 'FLS':
        return line.fls;
      default:
        return 0;
    }
  }

  void _addPlayer(String teamId) {
    showDialog(
      context: context,
      builder: (ctx) {
        _nameController.clear();
        return AlertDialog(
          title: const Text('Add Player'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Player Name',
              hintText: 'Enter name...',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = _nameController.text.trim();
                if (name.isEmpty) return;
                final playerId = 'p_${DateTime.now().millisecondsSinceEpoch}';
                setState(() {
                  final newLines = Map<String, PlayerStatLine>.from(
                    _localStats!.playerLines,
                  );
                  newLines[playerId] = PlayerStatLine(
                    name: name,
                    teamId: teamId,
                  );
                  _localStats = GameStatsModel(
                    id: _localStats!.id,
                    eventId: _localStats!.eventId,
                    seasonId: _localStats!.seasonId,
                    divisionId: _localStats!.divisionId,
                    homeTeamId: _localStats!.homeTeamId,
                    awayTeamId: _localStats!.awayTeamId,
                    homeTeamName: _localStats!.homeTeamName,
                    awayTeamName: _localStats!.awayTeamName,
                    homeScore: _localStats!.homeScore,
                    awayScore: _localStats!.awayScore,
                    status: _localStats!.status,
                    entryMode: _localStats!.entryMode,
                    playerLines: newLines,
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveDraft() async {
    if (_localStats == null) return;
    setState(() => _isSaving = true);
    try {
      final assocId = ref.read(currentAssociationIdProvider);
      if (assocId == null) return;
      await ref
          .read(statsRepositoryProvider)
          .saveGameStats(assocId, _localStats!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Draft saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _approve() async {
    if (_localStats == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve stats?'),
        content: const Text(
          'Approving will lock these stats and rebuild standings + leaderboards. '
          'Use Send Back if anything is off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      final assocId = ref.read(currentAssociationIdProvider);
      final userId = ref.read(authStateProvider).value?.uid;
      if (assocId == null) return;

      // Persist any pending edits before approval.
      await ref
          .read(statsRepositoryProvider)
          .saveGameStats(assocId, _localStats!);
      await ref.read(statsRepositoryProvider).updateGameStatsStatus(
            assocId,
            widget.eventId,
            GameStatsStatus.approved,
            userId: userId,
          );
      await ref.read(eventRepositoryProvider).updateEvent(
        assocId,
        widget.eventId,
        {'statsStatus': 'approved'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stats approved')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendBack() async {
    if (_localStats == null) return;
    final controller = TextEditingController();
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send back to statistician'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'e.g. "Player #12 PTS looks off — please verify."',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Send back'),
          ),
        ],
      ),
    );
    if (note == null) return;
    if (note.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A note is required when sending back')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final assocId = ref.read(currentAssociationIdProvider);
      final userId = ref.read(authStateProvider).value?.uid;
      if (assocId == null) return;

      await ref.read(statsRepositoryProvider).updateGameStatsStatus(
            assocId,
            widget.eventId,
            GameStatsStatus.rejected,
            userId: userId,
            rejectionNote: note,
          );
      await ref.read(eventRepositoryProvider).updateEvent(
        assocId,
        widget.eventId,
        {'statsStatus': 'pending'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent back to statistician')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submit() async {
    if (_localStats == null) return;

    final validationError = _validateStats();
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final assocId = ref.read(currentAssociationIdProvider);
      final userId = ref.read(authStateProvider).value?.uid;
      if (assocId == null) return;

      await ref
          .read(statsRepositoryProvider)
          .saveGameStats(assocId, _localStats!);
      await ref
          .read(statsRepositoryProvider)
          .updateGameStatsStatus(
            assocId,
            widget.eventId,
            GameStatsStatus.submitted,
            userId: userId,
          );

      // Also update the event's statsStatus so it no longer shows as needing stats
      await ref.read(eventRepositoryProvider).updateEvent(
        assocId,
        widget.eventId,
        {'statsStatus': 'submitted'},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stats submitted for approval')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(e))));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Returns the first validation error, or null if clean.
  /// Source of truth lives in [StatsValidator] so live + post-game share rules.
  String? _validateStats() {
    if (_localStats == null) return 'No stats to validate';
    final errors = StatsValidator.validate(
      _localStats!,
      rulesProfile: StatsValidationRulesProfile.pendingJbaAdoption,
    );
    return errors.isEmpty ? null : errors.first;
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(gameStatsProvider(widget.eventId));
    // Also watch the event so we can auto-create stats from it
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(_isCorrectionMode ? 'Correct Stats' : 'Post-Game Stats'),
        actions: [
          if (_localStats != null)
            TextButton(
              onPressed: _isSaving ? null : _saveDraft,
              child: const Text('Save'),
            ),
        ],
      ),
      body: statsAsync.when(
        data: (stats) {
          if (stats == null) {
            // No GameStatsModel exists yet — offer to create one from the event
            return eventAsync.when(
              data: (event) {
                if (event == null) {
                  return const Center(
                    child: Text(
                      'Event not found',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  );
                }

                if (event.teamIds.length < 2) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 56,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'This game is missing one or both teams.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Assign both teams to the scheduled game before starting post-game stat entry.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final assocId = ref.watch(currentAssociationIdProvider);
                final seasonAsync = ref.watch(activeSeasonIdProvider);
                final names = _parseTeamNames(event.title);
                final homeTeamId = event.teamIds[0];
                final awayTeamId = event.teamIds[1];
                final homeRosterAsync = ref.watch(
                  teamRosterProvider(homeTeamId),
                );
                final awayRosterAsync = ref.watch(
                  teamRosterProvider(awayTeamId),
                );
                final seasonId = seasonAsync.valueOrNull;
                final homeRoster =
                    homeRosterAsync.valueOrNull ??
                    const <PlayerSeasonStatsModel>[];
                final awayRoster =
                    awayRosterAsync.valueOrNull ??
                    const <PlayerSeasonStatsModel>[];
                final isLoading =
                    seasonAsync.isLoading ||
                    homeRosterAsync.isLoading ||
                    awayRosterAsync.isLoading;
                final hasRosterError =
                    homeRosterAsync.hasError || awayRosterAsync.hasError;
                final canInitialize =
                    assocId != null &&
                    seasonId != null &&
                    !isLoading &&
                    !hasRosterError;

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.edit_note,
                          size: 56,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Post-game entry is totals-based. Use Live Stats for courtside play-by-play.\nRosters load first so the stat grid starts with real players.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        _RosterLoadStatusCard(
                          teamName: names.homeTeamName,
                          count: homeRoster.length,
                          isLoading:
                              seasonAsync.isLoading ||
                              homeRosterAsync.isLoading,
                          isError: homeRosterAsync.hasError,
                          emptyStateMessage:
                              'No roster loaded. You can still start and add players manually.',
                        ),
                        const SizedBox(height: 12),
                        _RosterLoadStatusCard(
                          teamName: names.awayTeamName,
                          count: awayRoster.length,
                          isLoading:
                              seasonAsync.isLoading ||
                              awayRosterAsync.isLoading,
                          isError: awayRosterAsync.hasError,
                          emptyStateMessage:
                              'No roster loaded. You can still start and add players manually.',
                        ),
                        if (assocId == null ||
                            (!seasonAsync.isLoading && seasonId == null) ||
                            hasRosterError) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFFED7AA),
                              ),
                            ),
                            child: Text(
                              assocId == null
                                  ? 'Association data is still loading. Wait a moment and try again.'
                                  : seasonId == null
                                  ? 'No active season is set, so rosters cannot load yet.'
                                  : 'One or both rosters could not be loaded. Retry before starting.',
                              style: const TextStyle(
                                color: Color(0xFF9A3412),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 200,
                          child: ElevatedButton.icon(
                            onPressed: !canInitialize || _isInitializing
                                ? null
                                : () => _initializeFromEvent(
                                    seasonId: seasonId,
                                    homeTeamId: homeTeamId,
                                    awayTeamId: awayTeamId,
                                    homeTeamName: names.homeTeamName,
                                    awayTeamName: names.awayTeamName,
                                    homeRoster: homeRoster,
                                    awayRoster: awayRoster,
                                  ),
                            icon: _isInitializing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(
                              _isInitializing
                                  ? 'Initializing...'
                                  : isLoading
                                  ? 'Loading Rosters...'
                                  : 'Start Post-Game Entry',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () {
                            ref.invalidate(eventDetailProvider(widget.eventId));
                            ref.invalidate(activeSeasonIdProvider);
                            ref.invalidate(teamRosterProvider(homeTeamId));
                            ref.invalidate(teamRosterProvider(awayTeamId));
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry roster load'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const SkeletonStatGrid(),
              error: (e, _) => ErrorDisplay(
                error: e,
                onRetry: () =>
                    ref.invalidate(eventDetailProvider(widget.eventId)),
              ),
            );
          }

          _initLocalStats(stats);
          final s = _localStats!;

          final homePlayers = s.playerLines.entries
              .where((e) => e.value.teamId == s.homeTeamId)
              .toList();
          final awayPlayers = s.playerLines.entries
              .where((e) => e.value.teamId == s.awayTeamId)
              .toList();

          return Column(
            children: [
              // Score header
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                color: AppColors.darkBg,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          s.homeTeamName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${s.homeScore}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          s.awayTeamName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${s.awayScore}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Stats tables
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_isReadOnly) ...[
                      _StatusBanner(
                        bg: AppColors.successBg,
                        border: AppColors.success,
                        fg: const Color(0xFF14532D),
                        icon: Icons.lock_outline,
                        text: 'Approved · stats are locked. Standings + leaderboards rebuilt.',
                      ),
                      const SizedBox(height: 12),
                    ] else if (_isRejected) ...[
                      _StatusBanner(
                        bg: AppColors.urgentBg,
                        border: AppColors.urgent,
                        fg: const Color(0xFF7F1D1D),
                        icon: Icons.assignment_late_outlined,
                        text: s.rejectionNote?.isNotEmpty == true
                            ? 'Sent back: ${s.rejectionNote}'
                            : 'Sent back by admin — please review and re-submit.',
                      ),
                      const SizedBox(height: 12),
                    ] else if (_isCorrectionMode) ...[
                      const _StatusBanner(
                        bg: Color(0xFFEFF6FF),
                        border: Color(0xFF93C5FD),
                        fg: Color(0xFF1E40AF),
                        icon: Icons.info_outline,
                        text:
                            'Reviewing submitted stats. Edit any cell, then approve or send back.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildTeamSection(
                      s.homeTeamName,
                      s.homeTeamId,
                      homePlayers,
                    ),
                    const SizedBox(height: 16),
                    _buildTeamSection(
                      s.awayTeamName,
                      s.awayTeamId,
                      awayPlayers,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // Bottom action bar — adapts to lifecycle state + role.
              _buildActionBar(),
            ],
          );
        },
        loading: () => const SkeletonStatGrid(),
        error: (e, _) => ErrorDisplay(
          error: e,
          onRetry: () => ref.invalidate(gameStatsProvider(widget.eventId)),
        ),
      ),
    );
  }

  Widget _buildTeamSection(
    String teamName,
    String teamId,
    List<MapEntry<String, PlayerStatLine>> players,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              teamName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: () => _addPlayer(teamId),
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Horizontally scrollable stat grid for mobile
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 380),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  color: AppColors.surface,
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 90,
                        child: Text(
                          'Player',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      ..._statColumns.map(
                        (col) => SizedBox(
                          width: 40,
                          child: Text(
                            col,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Player rows
                if (players.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No players added yet',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...players.map(
                    (entry) => _buildPlayerRow(entry.key, entry.value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerRow(String playerId, PlayerStatLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              line.name,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ..._statColumns.map(
            (col) => SizedBox(
              width: 40,
              child: _StatInput(
                value: _getStatValue(line, col),
                enabled: !_isReadOnly,
                onChanged: (v) => _updateStat(playerId, col, v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final canApprove =
        ref.read(currentUserProvider).valueOrNull?.canApproveStats ?? false;

    // Approved → "Done" button just closes the screen.
    if (_isReadOnly) {
      return _ActionBarShell(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ),
        ],
      );
    }

    // Submitted, viewed by admin → Approve / Send Back. Save lets admin
    // persist intermediate corrections without flipping state.
    if (_isCorrectionMode && canApprove) {
      return _ActionBarShell(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isSaving ? null : _sendBack,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.urgent,
                side: const BorderSide(color: AppColors.urgent),
              ),
              child: const Text('Send back'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextButton(
              onPressed: _isSaving ? null : _saveDraft,
              child: const Text('Save edits'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: _isSaving ? null : _approve,
              child: const Text('Approve'),
            ),
          ),
        ],
      );
    }

    // Default: statistician composing or revising after rejection → Save / Submit.
    return _ActionBarShell(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : _saveDraft,
            child: const Text('Save Draft'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _submit,
            child: Text(_isRejected ? 'Re-submit' : 'Submit'),
          ),
        ),
      ],
    );
  }
}

class _StatInput extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _StatInput({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: TextField(
        controller: TextEditingController(text: value == 0 ? '' : '$value'),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        enabled: enabled,
        style: const TextStyle(fontSize: 12),
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
      ),
    );
  }
}

class _ActionBarShell extends StatelessWidget {
  final List<Widget> children;
  const _ActionBarShell({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: children),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
  final String text;

  const _StatusBanner({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _RosterLoadStatusCard extends StatelessWidget {
  final String teamName;
  final int count;
  final bool isLoading;
  final bool isError;
  final String emptyStateMessage;

  const _RosterLoadStatusCard({
    required this.teamName,
    required this.count,
    required this.isLoading,
    required this.isError,
    required this.emptyStateMessage,
  });

  @override
  Widget build(BuildContext context) {
    late final Color borderColor;
    late final Color bgColor;
    late final IconData icon;
    late final String message;

    if (isError) {
      borderColor = const Color(0xFFFCA5A5);
      bgColor = const Color(0xFFFEF2F2);
      icon = Icons.error_outline;
      message = 'Roster failed to load';
    } else if (isLoading) {
      borderColor = const Color(0xFFCBD5F5);
      bgColor = const Color(0xFFF8FAFC);
      icon = Icons.sync;
      message = 'Loading roster...';
    } else if (count == 0) {
      borderColor = const Color(0xFFFED7AA);
      bgColor = const Color(0xFFFFFBEB);
      icon = Icons.person_add_alt_1;
      message = emptyStateMessage;
    } else {
      borderColor = const Color(0xFFBBF7D0);
      bgColor = const Color(0xFFF0FDF4);
      icon = Icons.check_circle_outline;
      message = '$count players ready';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textPrimary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teamName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
