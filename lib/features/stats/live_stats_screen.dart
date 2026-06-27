import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../models/game_stats_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/live_stats_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';
import 'live_stats_notifier.dart';
import 'live_stats_state.dart';
import 'stats_validator.dart';
import 'widgets/action_panel.dart';
import 'widgets/foul_out_dialog.dart';
import 'widgets/game_clock.dart';
import 'widgets/live_box_score.dart';
import 'widgets/play_log.dart';
import 'widgets/roster_panel.dart';

/// Live stat-taking screen.
/// Two phases: setup (team selection + pick starters) and game (3-column layout).
class LiveStatsScreen extends ConsumerStatefulWidget {
  final String? eventId;

  const LiveStatsScreen({super.key, this.eventId});

  @override
  ConsumerState<LiveStatsScreen> createState() => _LiveStatsScreenState();
}

class _LiveStatsScreenState extends ConsumerState<LiveStatsScreen> {
  // ── Setup phase state ──
  bool _inSetupPhase = true;
  String? _homeTeamId;
  String? _awayTeamId;
  final Set<String> _homeStarters = {};
  final Set<String> _awayStarters = {};
  bool _eventLoaded = false;
  ClockMode _clockMode = ClockMode.statsOnly;

  // ── Game phase bottom tab ──
  int _bottomTabIndex = 0; // 0 = play-by-play, 1 = box score

  // ── Mobile roster tab (0 = home, 1 = away) ──
  int _mobileRosterTab = 0;

  // ── Sync status ──
  _SyncStatus _syncStatus = _SyncStatus.idle;

  /// LocalIds of plays already written to the events subcollection. Used to
  /// diff incoming state changes and emit append / tombstone calls.
  final Set<String> _persistedEventIds = {};

  // ── Keyboard shortcut state ──
  String _jerseyBuffer = '';
  Timer? _jerseyTimer;
  bool _showShortcutOverlay = false;
  final FocusNode _keyboardFocusNode = FocusNode();

  /// Whether we should show keyboard hints (web/desktop only).
  bool get _isDesktopOrWeb {
    if (kIsWeb) return true;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      default:
        return false;
    }
  }

  bool get _canStartGame =>
      _homeTeamId != null &&
      _awayTeamId != null &&
      _homeTeamId != _awayTeamId &&
      _homeStarters.length == 5 &&
      _awayStarters.length == 5;

  @override
  void initState() {
    super.initState();
    // If we have an eventId, we'll load from Firestore in the build
  }

  @override
  void dispose() {
    _jerseyTimer?.cancel();
    _keyboardFocusNode.dispose();
    // Always restore the device defaults — even if the user back-buttoned out
    // mid-game without ending it cleanly.
    _restoreSystemChrome();
    // Clean up live game state so the next session starts fresh.
    ref.invalidate(liveGameProvider);
    super.dispose();
  }

  /// Lock landscape + hide system chrome for court-side mode (wireframe §04 L1).
  /// Mobile only — tablet/desktop/web don't need orientation locks.
  void _enterCourtSideMode() {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        break;
      default:
        // Desktop / web: don't fight the user's window manager.
        break;
    }
  }

  void _restoreSystemChrome() {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        break;
      default:
        break;
    }
  }

  // ── Keyboard handling ──

  void _handleKeyEvent(KeyEvent event) {
    // Only handle key-down events.
    if (event is! KeyDownEvent) return;

    final gameState = ref.read(liveGameProvider);
    final notifier = ref.read(liveGameProvider.notifier);
    final hasSelection = gameState.selectedPlayerId != null;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final logicalKey = event.logicalKey;

    // ── Escape: deselect player ──
    if (logicalKey == LogicalKeyboardKey.escape) {
      notifier.clearSelection();
      _clearJerseyBuffer();
      return;
    }

    // ── Space: toggle clock ──
    if (logicalKey == LogicalKeyboardKey.space) {
      if (gameState.clockMode == ClockMode.withClock) {
        notifier.toggleClock();
      }
      return;
    }

    // ── Q: next quarter ──
    if (logicalKey == LogicalKeyboardKey.keyQ && !isShift) {
      notifier.nextQuarter();
      return;
    }

    // ── Z: undo ──
    if (logicalKey == LogicalKeyboardKey.keyZ && !isShift) {
      notifier.undo();
      return;
    }

    // ── Stat keys (only when a player is selected) ──
    if (hasSelection) {
      // 2 and 3 keys are dual-purpose: stat entry when player selected
      if (logicalKey == LogicalKeyboardKey.digit2) {
        final action = isShift ? '2PT_MISS' : '2PT_MAKE';
        final result = notifier.recordStat(action);
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.digit3) {
        final action = isShift ? '3PT_MISS' : '3PT_MAKE';
        final result = notifier.recordStat(action);
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyF) {
        final action = isShift ? 'FT_MISS' : 'FT_MAKE';
        final result = notifier.recordStat(action);
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyR) {
        final action = isShift ? 'OREB' : 'DREB';
        final result = notifier.recordStat(action);
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyA && !isShift) {
        final result = notifier.recordStat('AST');
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyS && !isShift) {
        final result = notifier.recordStat('STL');
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyB && !isShift) {
        final result = notifier.recordStat('BLK');
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyT && !isShift) {
        final result = notifier.recordStat('TO');
        if (result != null) _handleActionAlert(result);
        return;
      }
      if (logicalKey == LogicalKeyboardKey.keyX && !isShift) {
        final result = notifier.recordStat('FLS');
        if (result != null) _handleActionAlert(result);
        return;
      }
    }

    // ── Digit keys: jersey number selection ──
    final digit = _digitFromKey(logicalKey);
    if (digit != null) {
      // When a player is selected, digits other than 2/3 (handled above)
      // deselect and enter jersey mode.
      if (hasSelection) {
        notifier.clearSelection();
      }
      _appendJerseyDigit(digit);
      return;
    }
  }

  int? _digitFromKey(LogicalKeyboardKey key) {
    final digitKeys = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit0: 0,
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad0: 0,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    return digitKeys[key];
  }

  void _appendJerseyDigit(int digit) {
    _jerseyTimer?.cancel();
    _jerseyBuffer += digit.toString();

    if (_jerseyBuffer.length >= 2) {
      // Two digits entered — try to match immediately.
      _tryMatchJersey();
    } else {
      // Single digit — wait 1 second for a possible second digit.
      _jerseyTimer = Timer(const Duration(seconds: 1), _tryMatchJersey);
    }
  }

  void _tryMatchJersey() {
    _jerseyTimer?.cancel();
    final targetNum = int.tryParse(_jerseyBuffer);
    _jerseyBuffer = '';
    if (targetNum == null) return;

    final gameState = ref.read(liveGameProvider);
    final notifier = ref.read(liveGameProvider.notifier);

    // Search all players for matching jersey number.
    for (final player in gameState.players.values) {
      if (player.num == targetNum) {
        notifier.selectPlayer(player.id);
        return;
      }
    }

    // No match found — show brief feedback.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No player with jersey #$targetNum'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _clearJerseyBuffer() {
    _jerseyTimer?.cancel();
    _jerseyBuffer = '';
  }

  /// Load event data from Firestore when eventId is provided.
  void _tryLoadEventData() {
    if (_eventLoaded || widget.eventId == null) return;

    final eventAsync = ref.read(eventDetailProvider(widget.eventId!));
    eventAsync.whenData((event) {
      if (event == null || _eventLoaded) return;

      setState(() {
        _eventLoaded = true;

        // Auto-set teams from event
        if (event.teamIds.length >= 2) {
          _homeTeamId = event.teamIds[0];
          _awayTeamId = event.teamIds[1];

          // Auto-select starters for both teams
          _homeStarters.clear();
          _awayStarters.clear();
        }
      });
    });
  }

  void _startGame() {
    if (!_canStartGame) return;

    final homeTeam = ref.read(teamDetailProvider(_homeTeamId!)).value;
    final awayTeam = ref.read(teamDetailProvider(_awayTeamId!)).value;
    if (homeTeam == null || awayTeam == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Teams are still loading.')));
      return;
    }

    final homeRosterAsync = ref.read(teamRosterProvider(_homeTeamId!));
    final awayRosterAsync = ref.read(teamRosterProvider(_awayTeamId!));
    final seasonId = ref.read(activeSeasonIdProvider).value;
    if (seasonId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an active season before starting live stats.'),
        ),
      );
      return;
    }
    if (homeRosterAsync.isLoading || awayRosterAsync.isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rosters are still loading.')),
      );
      return;
    }
    if (homeRosterAsync.hasError || awayRosterAsync.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not load one or both rosters. Retry before starting live stats.',
          ),
        ),
      );
      return;
    }

    final homeRoster = homeRosterAsync.valueOrNull;
    final awayRoster = awayRosterAsync.valueOrNull;
    if (homeRoster == null || awayRoster == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rosters are not ready yet.')),
      );
      return;
    }
    if (homeRoster.isEmpty || awayRoster.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Live stats requires both team rosters to be loaded first.',
          ),
        ),
      );
      return;
    }

    // Look up division from event if available
    String? divisionId;
    if (widget.eventId != null) {
      final event = ref.read(eventDetailProvider(widget.eventId!)).value;
      divisionId = event?.divisionId;
    }

    // Build player map.
    final Map<String, LivePlayerStats> players = {};

    for (final p in homeRoster) {
      final isStarter = _homeStarters.contains(p.playerId);
      players[p.playerId] = LivePlayerStats(
        id: p.playerId,
        name: p.playerName,
        teamId: _homeTeamId!,
        num: _extractJerseyNumber(p.playerName, p.playerId),
        onCourt: isStarter,
        minutesEnteredAt: isStarter ? 600 : null,
      );
    }
    for (final p in awayRoster) {
      final isStarter = _awayStarters.contains(p.playerId);
      players[p.playerId] = LivePlayerStats(
        id: p.playerId,
        name: p.playerName,
        teamId: _awayTeamId!,
        num: _extractJerseyNumber(p.playerName, p.playerId),
        onCourt: isStarter,
        minutesEnteredAt: isStarter ? 600 : null,
      );
    }

    // Initialise the notifier with the real game state.
    ref
        .read(liveGameProvider.notifier)
        .initGame(
          homeTeamId: _homeTeamId!,
          awayTeamId: _awayTeamId!,
          homeTeamName: homeTeam.name,
          awayTeamName: awayTeam.name,
          players: players,
          seasonId: seasonId,
          eventId: widget.eventId,
          divisionId: divisionId,
          clockMode: _clockMode,
        );
    setState(() => _inSetupPhase = false);
    // Court-side mode: lock landscape, hide chrome.
    _enterCourtSideMode();
  }

  int _extractJerseyNumber(String name, String id) {
    // Try to parse a number from the player ID suffix (e.g. "p_123" -> 23).
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) {
      final num = int.tryParse(digits);
      if (num != null) return num % 100; // keep last 2 digits
    }
    // Fallback: hash the name.
    return name.hashCode.abs() % 100;
  }

  void _handleActionAlert(String message) {
    if (message.startsWith('FOUL_OUT:')) {
      final pid = message.substring('FOUL_OUT:'.length);
      final player = ref.read(liveGameProvider).players[pid];
      if (player != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => FoulOutDialog(
            player: player,
            onSubOut: () {
              ref.read(liveGameProvider.notifier).startFoulOutSub(pid);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Tap a bench player to sub in for ${player.name}',
                  ),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  void _showEndGameConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Game?'),
        content: const Text(
          'This will finalize all player minutes and generate the stat sheet for syncing.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _endGame();
            },
            child: const Text('End Game'),
          ),
        ],
      ),
    );
  }

  Future<void> _endGame() async {
    final model = ref.read(liveGameProvider.notifier).endGame();
    _showEndGameOverlay(model);
  }

  void _showEndGameOverlay(GameStatsModel model) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Game Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Final score
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text(
                      model.homeTeamName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${model.homeScore}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '\u2014',
                    style: TextStyle(fontSize: 24, color: AppColors.textMuted),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      model.awayTeamName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${model.awayScore}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _syncToFirestore(model);
            },
            child: const Text('Sync to HoopsConnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _showValidationErrors(List<String> errors) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fix before submit'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'These issues block submission. Correct them and try again.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: AppColors.urgent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(e, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncToFirestore(GameStatsModel model) async {
    setState(() => _syncStatus = _SyncStatus.saving);

    try {
      final assocId = ref.read(currentAssociationIdProvider);
      if (assocId == null) {
        if (mounted) {
          setState(() => _syncStatus = _SyncStatus.error);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Missing association')));
        }
        return;
      }

      final userId = ref.read(authStateProvider).value?.uid;

      // 1. Validate before submit — wireframe §02-A2.
      final errors = StatsValidator.validate(model);
      if (errors.isNotEmpty) {
        if (mounted) {
          setState(() => _syncStatus = _SyncStatus.idle);
          await _showValidationErrors(errors);
        }
        return;
      }

      // 2. Save game stats with submitted status
      final submittedModel = GameStatsModel(
        id: model.id,
        eventId: model.eventId,
        seasonId: model.seasonId,
        divisionId: model.divisionId,
        homeTeamId: model.homeTeamId,
        awayTeamId: model.awayTeamId,
        homeTeamName: model.homeTeamName,
        awayTeamName: model.awayTeamName,
        homeScore: model.homeScore,
        awayScore: model.awayScore,
        status: GameStatsStatus.submitted,
        submittedBy: userId,
        submittedAt: DateTime.now(),
        entryMode: GameStatsEntryMode.live,
        playerLines: model.playerLines,
        homeQuarterScores: model.homeQuarterScores,
        awayQuarterScores: model.awayQuarterScores,
        playerQuarterStats: model.playerQuarterStats,
      );

      await ref
          .read(statsRepositoryProvider)
          .saveGameStats(assocId, submittedModel);

      // 2. Update the event's statsStatus to submitted (if linked to an event)
      if (model.eventId.isNotEmpty && !model.eventId.startsWith('live_')) {
        await ref.read(eventRepositoryProvider).updateEvent(
          assocId,
          model.eventId,
          {'statsStatus': 'submitted'},
        );
      }

      // 3. Listen for server confirmation via SnapshotMetadata
      _listenForSyncConfirmation(assocId, submittedModel.id);

      if (mounted) {
        setState(() => _syncStatus = _SyncStatus.pendingSync);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stats synced! Pending admin approval.'),
          ),
        );

        // 4. Navigate to box score view
        context.go('/box-score/${submittedModel.eventId}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _syncStatus = _SyncStatus.error);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error syncing: $e')));
      }
    }
  }

  /// Listen to Firestore snapshot metadata to determine sync status.
  void _listenForSyncConfirmation(String assocId, String docId) {
    final docRef = FirebaseFirestore.instance.doc(
      'associations/$assocId/gameStats/$docId',
    );

    docRef.snapshots(includeMetadataChanges: true).listen((snap) {
      if (!mounted) return;
      if (snap.exists) {
        if (snap.metadata.hasPendingWrites) {
          setState(() => _syncStatus = _SyncStatus.pendingSync);
        } else {
          setState(() => _syncStatus = _SyncStatus.synced);
        }
      }
    });
  }

  // ═══════════════════════════════ BUILD ════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    // Attempt to load event data if eventId was provided
    if (widget.eventId != null && !_eventLoaded) {
      // Watch the event provider so we react when it loads
      ref.watch(eventDetailProvider(widget.eventId!));
      _tryLoadEventData();
    }

    // Stream every play change to the events subcollection — wireframe §04 L4.
    ref.listen<LiveGameState>(liveGameProvider, (prev, next) {
      _syncEventsToFirestore(prev, next);
    });

    if (_inSetupPhase) {
      return _buildSetupScreen();
    }
    return _buildGameScreen();
  }

  /// Diffs play lists and writes appends / tombstones for the events
  /// subcollection. Skipped for ephemeral games (no eventId).
  void _syncEventsToFirestore(LiveGameState? prev, LiveGameState next) {
    final eventId = next.eventId;
    if (eventId == null || eventId.isEmpty || eventId.startsWith('live_')) {
      return; // No backing event doc — nothing to attach events to.
    }
    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) return;

    final repo = ref.read(statsRepositoryProvider);
    final currentIds = next.plays.map((p) => p.localId).toSet();

    // Append plays we haven't persisted yet.
    for (final play in next.plays) {
      if (_persistedEventIds.add(play.localId)) {
        repo
            .appendLiveEvent(assocId, eventId, play.localId, play.toEventMap())
            .catchError((Object err) {
              debugPrint('appendLiveEvent failed for ${play.localId}: $err');
              // On failure, allow retry on next state change.
              _persistedEventIds.remove(play.localId);
            });
      }
    }

    // Tombstone any persisted plays that disappeared (undo / sub cancel).
    final removed = _persistedEventIds.difference(currentIds);
    for (final id in removed) {
      repo.tombstoneLiveEvent(assocId, eventId, id).catchError((Object err) {
        debugPrint('tombstoneLiveEvent failed for $id: $err');
      });
      _persistedEventIds.remove(id);
    }
  }

  // ──────────────────────────── SETUP SCREEN ───────────────────────────────

  Widget _buildSetupScreen() {
    final teamsAsync = ref.watch(teamsStreamProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Live Stats Setup'),
        backgroundColor: const Color(0xFFEA580C),
        foregroundColor: Colors.white,
      ),
      body: teamsAsync.when(
        data: (teams) {
          if (teams.isEmpty) {
            return const Center(
              child: Text('No teams found. Add teams first.'),
            );
          }

          return SingleChildScrollView(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 500;
                  return Container(
                    constraints: const BoxConstraints(maxWidth: 700),
                    margin: EdgeInsets.all(isNarrow ? 12 : 24),
                    padding: EdgeInsets.all(isNarrow ? 16 : 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HoopsConnect Live Stats',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.eventId != null
                              ? 'Pre-loaded from scheduled game'
                              : 'Courtside stat-taking system',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),

                        // Show event info if loaded from Firestore
                        if (widget.eventId != null) ...[
                          const SizedBox(height: 12),
                          _buildEventInfoBanner(),
                        ],

                        const SizedBox(height: 24),

                        // Home Team selector
                        _SectionHeader('Home Team'),
                        const SizedBox(height: 8),
                        _teamDropdown(teams, _homeTeamId, (val) {
                          setState(() {
                            _homeTeamId = val;
                            _homeStarters.clear();
                          });
                        }),
                        const SizedBox(height: 24),

                        // Away Team selector
                        _SectionHeader('Away Team'),
                        const SizedBox(height: 8),
                        _teamDropdown(teams, _awayTeamId, (val) {
                          setState(() {
                            _awayTeamId = val;
                            _awayStarters.clear();
                          });
                        }),
                        const SizedBox(height: 24),

                        if (_homeTeamId != null &&
                            _awayTeamId != null &&
                            _homeTeamId != _awayTeamId) ...[
                          _SectionHeader('Select Starters (5 per team)'),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 400) {
                                // Stack on narrow mobile
                                return Column(
                                  children: [
                                    _rosterColumn(
                                      _homeTeamId!,
                                      _homeStarters,
                                      isHome: true,
                                    ),
                                    const SizedBox(height: 16),
                                    _rosterColumn(
                                      _awayTeamId!,
                                      _awayStarters,
                                      isHome: false,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _rosterColumn(
                                      _homeTeamId!,
                                      _homeStarters,
                                      isHome: true,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _rosterColumn(
                                      _awayTeamId!,
                                      _awayStarters,
                                      isHome: false,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Clock mode selector
                        _SectionHeader('Clock Mode'),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ClockMode>(
                            segments: const [
                              ButtonSegment(
                                value: ClockMode.statsOnly,
                                label: Text('Stats Only'),
                                icon: Icon(Icons.bar_chart),
                              ),
                              ButtonSegment(
                                value: ClockMode.withClock,
                                label: Text('With Clock'),
                                icon: Icon(Icons.timer),
                              ),
                            ],
                            selected: {_clockMode},
                            onSelectionChanged: (selected) {
                              setState(() => _clockMode = selected.first);
                            },
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.selected)) {
                                  return const Color(0xFFEA580C);
                                }
                                return null;
                              }),
                              foregroundColor: WidgetStateProperty.resolveWith((
                                states,
                              ) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.white;
                                }
                                return null;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _clockMode == ClockMode.statsOnly
                              ? 'Stats Only: Track quarter-by-quarter without managing a clock.'
                              : 'With Clock: Full countdown timer with start/stop.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Start button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _canStartGame ? _startGame : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEA580C),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFFCBD5E1),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Start Game'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFFEA580C)),
        ),
        error: (e, _) => Center(child: Text('Error loading teams: $e')),
      ),
    );
  }

  Widget _buildEventInfoBanner() {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId!));

    return eventAsync.when(
      data: (event) {
        if (event == null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            border: Border.all(color: const Color(0xFFFDBA74)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.event, color: Color(0xFFEA580C), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFC2410C),
                      ),
                    ),
                    if (event.location != null)
                      Text(
                        event.location!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LINKED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const LinearProgressIndicator(color: Color(0xFFEA580C)),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _teamDropdown(
    List teams,
    String? selectedId,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          isExpanded: true,
          hint: const Text('Select team...'),
          items: teams
              .map<DropdownMenuItem<String>>(
                (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _rosterColumn(
    String teamId,
    Set<String> starters, {
    required bool isHome,
  }) {
    final rosterAsync = ref.watch(teamRosterProvider(teamId));
    final teamAsync = ref.watch(teamDetailProvider(teamId));
    final teamName = teamAsync.valueOrNull?.name ?? 'Team';

    return rosterAsync.when(
      data: (roster) {
        final count = starters.length;
        final countColor = count == 5
            ? const Color(0xFF16A34A)
            : (count > 5 ? const Color(0xFFDC2626) : AppColors.textMuted);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: isHome
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      teamName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isHome
                            ? const Color(0xFFC2410C)
                            : const Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                  Text(
                    '($count/5)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: count == 5
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: countColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (roster.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No players in roster',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              )
            else
              ...roster.map((p) {
                final isStarter = starters.contains(p.playerId);
                return _SetupPlayerRow(
                  name: p.playerName,
                  isStarter: isStarter,
                  isHome: isHome,
                  onTap: () {
                    setState(() {
                      if (isStarter) {
                        starters.remove(p.playerId);
                      } else {
                        starters.add(p.playerId);
                      }
                    });
                  },
                );
              }),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Text('Error: $e'),
    );
  }

  // ──────────────────────────── GAME SCREEN ────────────────────────────────

  Widget _buildGameScreen() {
    final gameState = ref.watch(liveGameProvider);

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
        return KeyEventResult.handled;
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            body: Column(
              children: [
                // Score header
                _buildScoreHeader(gameState),

                // Game content: use vertical layout on narrow screens
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // On narrow screens (phones), stack rosters + action panel vertically
                      if (constraints.maxWidth < 700) {
                        return _buildMobileGameLayout(gameState);
                      }
                      // On wide screens (tablets/desktop), use 3-column layout
                      return Row(
                        children: [
                          Expanded(
                            child: RosterPanel(
                              teamId: gameState.homeTeamId,
                              teamName: gameState.homeTeamName,
                              isHome: true,
                            ),
                          ),
                          ActionPanel(
                            onAlert: _handleActionAlert,
                            showKeyHints: _isDesktopOrWeb,
                          ),
                          Expanded(
                            child: RosterPanel(
                              teamId: gameState.awayTeamId,
                              teamName: gameState.awayTeamName,
                              isHome: false,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Bottom panel (play log / box score)
                _buildBottomPanel(),
              ],
            ),
          ),

          // Shortcut reference overlay
          if (_showShortcutOverlay) _buildShortcutOverlay(),
        ],
      ),
    );
  }

  // ──────────────────────────── MOBILE GAME LAYOUT ────────────────────────

  Widget _buildMobileGameLayout(LiveGameState gameState) {
    final notifier = ref.read(liveGameProvider.notifier);
    final homeTeamName = gameState.homeTeamName;
    final awayTeamName = gameState.awayTeamName;

    return Column(
      children: [
        // Roster selector tabs + compact roster strip
        Container(
          color: Colors.white,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Team tabs
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _mobileRosterTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _mobileRosterTab == 0
                                  ? const Color(0xFFEA580C)
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          homeTeamName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _mobileRosterTab == 0
                                ? const Color(0xFFEA580C)
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _mobileRosterTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _mobileRosterTab == 1
                                  ? const Color(0xFF2563EB)
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Text(
                          awayTeamName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _mobileRosterTab == 1
                                ? const Color(0xFF2563EB)
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Horizontal scrollable player chips
              SizedBox(
                height: 90,
                child: _mobileRosterTab == 0
                    ? _buildMobileRosterStrip(
                        gameState,
                        gameState.homeTeamId,
                        true,
                        notifier,
                      )
                    : _buildMobileRosterStrip(
                        gameState,
                        gameState.awayTeamId,
                        false,
                        notifier,
                      ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: AppColors.border),

        // Action panel (full width, scrollable)
        Expanded(
          child: ActionPanel(
            onAlert: _handleActionAlert,
            showKeyHints: _isDesktopOrWeb,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileRosterStrip(
    LiveGameState gameState,
    String teamId,
    bool isHome,
    LiveStatsNotifier notifier,
  ) {
    final allPlayers = gameState.players.values
        .where((p) => p.teamId == teamId)
        .toList();
    final onCourt = allPlayers.where((p) => p.onCourt).toList();
    final bench = allPlayers.where((p) => !p.onCourt).toList();
    final players = [...onCourt, ...bench];

    final accentColor = isHome
        ? const Color(0xFFEA580C)
        : const Color(0xFF2563EB);

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final p = players[index];
        final isSelected = gameState.selectedPlayerId == p.id;
        final isSubTarget =
            gameState.subMode &&
            gameState.subOutPlayerId != null &&
            gameState.players[gameState.subOutPlayerId]?.teamId == teamId &&
            !p.onCourt &&
            !p.isFouledOut;

        return GestureDetector(
          onTap: () {
            if (isSubTarget) {
              notifier.completeSub(p.id);
            } else if (!p.isFouledOut || isSubTarget) {
              notifier.selectPlayer(p.id);
            }
          },
          child: Container(
            width: 72,
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white
                  : isSubTarget
                  ? const Color(0xFFF0FDF4)
                  : (p.onCourt
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? accentColor
                    : isSubTarget
                    ? const Color(0xFF16A34A)
                    : (p.onCourt ? AppColors.border : Colors.transparent),
                width: isSelected || isSubTarget ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.2),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: Opacity(
              opacity: p.isFouledOut
                  ? 0.35
                  : (!p.onCourt && !isSubTarget ? 0.6 : 1.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Jersey number
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: p.onCourt ? accentColor : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${p.num}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: p.onCourt
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Name
                  Text(
                    p.name.split(' ').last,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      decoration: p.isFouledOut
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  // Points
                  if (p.onCourt || p.pts > 0)
                    Text(
                      '${p.pts}pts',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.textMuted,
                      ),
                    ),
                  // Bench label
                  if (!p.onCourt && p.pts == 0)
                    const Text(
                      'bench',
                      style: TextStyle(
                        fontSize: 8,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScoreHeader(LiveGameState gameState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1E293B),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;

            if (isNarrow) {
              // Mobile: two-row header — scores on top, controls below
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Score row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          gameState.homeTeamName,
                          style: const TextStyle(
                            color: Color(0xFFFDBA74),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${gameState.homeScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '\u2014',
                          style: TextStyle(color: Colors.white38, fontSize: 18),
                        ),
                      ),
                      Text(
                        '${gameState.awayScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          gameState.awayTeamName,
                          style: const TextStyle(
                            color: Color(0xFF93C5FD),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Controls row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSyncIndicator(),
                      GameClock(clockMode: gameState.clockMode),
                      GestureDetector(
                        onTap: _showEndGameConfirm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFDC2626)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'End',
                            style: TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }

            // Desktop/tablet: single-row header
            return Row(
              children: [
                // Score display
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gameState.homeTeamName,
                            style: const TextStyle(
                              color: Color(0xFFFDBA74),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${gameState.homeScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          '\u2014',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 20,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                      Text(
                        '${gameState.awayScore}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gameState.awayTeamName,
                            style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Keyboard shortcut toggle (web/desktop only)
                if (_isDesktopOrWeb) ...[
                  GestureDetector(
                    onTap: () => setState(
                      () => _showShortcutOverlay = !_showShortcutOverlay,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _showShortcutOverlay
                            ? const Color(0xFFEA580C)
                            : Colors.transparent,
                        border: Border.all(
                          color: _showShortcutOverlay
                              ? const Color(0xFFEA580C)
                              : Colors.white24,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard, color: Colors.white70, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Keys',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                _buildSyncIndicator(),
                const SizedBox(width: 8),
                GameClock(clockMode: gameState.clockMode),
                const SizedBox(width: 10),

                GestureDetector(
                  onTap: _showEndGameConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFDC2626)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'End Game',
                      style: TextStyle(
                        color: Color(0xFFFCA5A5),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSyncIndicator() {
    IconData icon;
    Color color;
    String tooltip;

    switch (_syncStatus) {
      case _SyncStatus.idle:
        icon = Icons.circle_outlined;
        color = Colors.white30;
        tooltip = 'Not yet saved';
      case _SyncStatus.saving:
        icon = Icons.hourglass_top;
        color = const Color(0xFFFBBF24);
        tooltip = 'Saving...';
      case _SyncStatus.pendingSync:
        icon = Icons.cloud_upload_outlined;
        color = const Color(0xFFFBBF24);
        tooltip = 'Saved locally';
      case _SyncStatus.synced:
        icon = Icons.cloud_done_outlined;
        color = const Color(0xFF4ADE80);
        tooltip = 'Synced';
      case _SyncStatus.error:
        icon = Icons.cloud_off_outlined;
        color = const Color(0xFFFCA5A5);
        tooltip = 'Sync error';
    }

    return Tooltip(
      message: tooltip,
      child: Icon(icon, color: color, size: 18),
    );
  }

  Widget _buildShortcutOverlay() {
    return Positioned(
      top: 80,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF1E293B),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.keyboard, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Keyboard Shortcuts',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showShortcutOverlay = false),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 20),
              const _ShortcutSection(
                title: 'PLAYER SELECT',
                items: [
                  ('0-9', 'Type jersey number'),
                  ('Esc', 'Deselect player'),
                ],
              ),
              const SizedBox(height: 10),
              const _ShortcutSection(
                title: 'SCORING (player selected)',
                items: [
                  ('2', '2PT Make'),
                  ('\u21e7+2', '2PT Miss'),
                  ('3', '3PT Make'),
                  ('\u21e7+3', '3PT Miss'),
                  ('F', 'FT Make'),
                  ('\u21e7+F', 'FT Miss'),
                ],
              ),
              const SizedBox(height: 10),
              const _ShortcutSection(
                title: 'STATS (player selected)',
                items: [
                  ('R', 'Def. Rebound'),
                  ('\u21e7+R', 'Off. Rebound'),
                  ('A', 'Assist'),
                  ('S', 'Steal'),
                  ('B', 'Block'),
                  ('T', 'Turnover'),
                  ('X', 'Foul'),
                ],
              ),
              const SizedBox(height: 10),
              const _ShortcutSection(
                title: 'CONTROLS',
                items: [
                  ('Space', 'Start/Stop Clock'),
                  ('Q', 'Next Quarter'),
                  ('Z', 'Undo'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      height: 200,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border, width: 2)),
      ),
      child: Column(
        children: [
          // Tabs
          Row(
            children: [
              _BottomTab(
                label: 'Play-by-Play',
                isActive: _bottomTabIndex == 0,
                onTap: () => setState(() => _bottomTabIndex = 0),
              ),
              _BottomTab(
                label: 'Box Score',
                isActive: _bottomTabIndex == 1,
                onTap: () => setState(() => _bottomTabIndex = 1),
              ),
            ],
          ),
          // Content
          Expanded(
            child: _bottomTabIndex == 0
                ? const PlayLog()
                : const LiveBoxScore(),
          ),
        ],
      ),
    );
  }
}

// ── Sync status enum ──

enum _SyncStatus {
  idle,
  saving,
  pendingSync, // hasPendingWrites == true
  synced, // confirmed on server
  error,
}

// ════════════════════════════ HELPER WIDGETS ═════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _SetupPlayerRow extends StatelessWidget {
  final String name;
  final bool isStarter;
  final bool isHome;
  final VoidCallback onTap;

  const _SetupPlayerRow({
    required this.name,
    required this.isStarter,
    required this.isHome,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final starterBorder = isHome
        ? const Color(0xFFEA580C)
        : const Color(0xFF3B82F6);
    final starterBg = isHome
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFEFF6FF);
    final starterStarColor = isHome
        ? const Color(0xFFEA580C)
        : const Color(0xFF3B82F6);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isStarter ? starterBg : null,
          border: Border.all(
            color: isStarter ? starterBorder : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: Text(
                isStarter ? '\u2605' : '\u2606',
                style: TextStyle(
                  fontSize: 14,
                  color: isStarter ? starterStarColor : AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isStarter ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutSection extends StatelessWidget {
  final String title;
  final List<(String, String)> items;

  const _ShortcutSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    item.$1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFFEA580C) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive
                  ? const Color(0xFFEA580C)
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
