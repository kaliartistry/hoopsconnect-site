import 'dart:convert';

import 'package:flutter/material.dart';
import 'complete_game_example.dart';
import 'jbl_presentation_game.dart';
import 'public_team_identity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/constants/app_constants.dart';
import '../../core/sharing/artifact_downloader.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_state_message.dart';
import '../../core/widgets/public_brand_context.dart';
import '../../models/association_branding_model.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_artifact_release_validator.dart';
import '../../services/public_stat_export_service.dart';

class PublicGameDetailScreen extends ConsumerStatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGameDetail detail;
  final bool canExportStats;
  final Uri? canonicalUri;
  final ArtifactDownloader? downloader;
  final PublicArtifactReleaseValidator? releaseValidator;
  final PublicLegacyGameShareValidator? legacyShareValidator;
  final Future<void> Function(String text)? clipboardWriter;

  const PublicGameDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
    this.canExportStats = false,
    this.canonicalUri,
    this.downloader,
    this.releaseValidator,
    this.legacyShareValidator,
    this.clipboardWriter,
  });

  @override
  ConsumerState<PublicGameDetailScreen> createState() =>
      _PublicGameDetailScreenState();
}

class _PublicGameDetailScreenState
    extends ConsumerState<PublicGameDetailScreen> {
  late final ArtifactDownloader _downloader;
  late _GameDetailSection _section;
  bool _downloadingCsv = false;
  bool _artifactActionPending = false;
  bool _artifactInvalidated = false;

  @override
  void initState() {
    super.initState();
    _downloader = widget.downloader ?? createArtifactDownloader();
    _section = game.playerLines.isEmpty
        ? _GameDetailSection.summary
        : _GameDetailSection.boxScore;
  }

  bool get _presentation =>
      widget.detail.game.gameId.startsWith('jbl-2025-') &&
      widget.snapshot
          .leagueForDivision(widget.detail.game.divisionId)
          .historicalStatistics &&
      (widget.detail.game.recap?.startsWith('Recorded final result.') ?? false);
  PublicGame get game => _presentation
      ? completeJblPresentationGame(widget.detail.game, widget.snapshot)
      : widget.detail.game;
  PublicLeagueDefinition get league =>
      widget.snapshot.leagueForDivision(game.divisionId);

  PublicArtifactReleaseValidator get _releaseValidator =>
      widget.releaseValidator ??
      ref.read(publicArtifactReleaseValidatorProvider);

  PublicArtifactBinding get _artifactBinding =>
      PublicArtifactBinding.game(widget.snapshot, widget.detail.game);

  AssociationBrandingModel get branding =>
      publicShareBranding(widget.snapshot, league);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: publicSportsCanvas,
      appBar: AppBar(
        backgroundColor: const Color(0xFF234EBD),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: publicRoyalGradient),
        ),
        leading: IconButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(PublicRoutePaths.games),
          tooltip: 'Back to public games',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Game details'),
        actions: [
          if (_canShareAnything)
            IconButton(
              onPressed: _artifactActionPending ? null : _share,
              tooltip: _shareLabel,
              icon: const Icon(Icons.ios_share_outlined),
            ),
        ],
      ),
      body: Theme(
        data: publicSportsTheme(context),
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          children: [
            if (!_canShareAnything) ...[
              AppStateMessage(
                title: 'Sharing and exports unavailable',
                message: _artifactUnavailableMessage,
                tone: AppStateTone.warning,
              ),
              const SizedBox(height: 16),
            ],
            PublicBrandContext(
              snapshot: widget.snapshot,
              league: league,
              divisionName: widget.detail.divisionName,
              showSponsorText: true,
            ),
            const SizedBox(height: 12),
            _ScoreCard(snapshot: widget.snapshot, game: game),
            const SizedBox(height: 12),
            _GameDetailTabs(
              selected: _section,
              boxScoreAvailable: game.playerLines.isNotEmpty,
              onSelected: (value) => setState(() => _section = value),
            ),
            const SizedBox(height: 16),
            switch (_section) {
              _GameDetailSection.summary => _SummarySection(
                snapshot: widget.snapshot,
                detail: widget.detail,
                game: game,
                presentation: _presentation,
              ),
              _GameDetailSection.boxScore =>
                game.playerLines.isEmpty
                    ? const AppStateMessage(
                        title: 'Player box score unavailable',
                        message:
                            'Player stats have not been posted for this game yet.',
                        icon: Icons.people_outline,
                      )
                    : _PlayerLineTable(snapshot: widget.snapshot, game: game),
              _GameDetailSection.teamStats =>
                game.playerLines.isEmpty
                    ? const AppStateMessage(
                        title: 'Team statistics unavailable',
                        message:
                            'Team totals will appear after player statistics are published.',
                        icon: Icons.analytics_outlined,
                      )
                    : _TeamComparison(game: game),
            },
            const SizedBox(height: 20),
            _ArtifactActions(
              canShare: _canShareAnything,
              canCopy: _canShare,
              shareLabel: _shareLabel,
              canShareBoxScore: _canShare && game.playerLines.isNotEmpty,
              canExport: widget.canExportStats && _canShare && !_presentation,
              downloadSupported: _downloader.isSupported,
              downloadingCsv: _downloadingCsv,
              actionPending: _artifactActionPending,
              onShare: _share,
              onShareBoxScore: _shareBoxScore,
              onCopy: _copy,
              onDownloadCsv: _downloadCsv,
            ),
            if (widget.snapshot.version.isVersioned) ...[
              const SizedBox(height: 12),
              Text(
                'Publication ${widget.snapshot.version.shortLabel} · Result ${_short(game.resultVersion)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _canShare =>
      !_artifactInvalidated &&
      widget.snapshot.canCreatePublishedArtifacts &&
      game.hasVersionedResult;

  bool get _canShareFixture =>
      !_artifactInvalidated &&
      widget.snapshot.canCreatePublishedArtifacts &&
      game.status == PublicGameStatus.scheduled;

  bool get _canShareLegacy =>
      !_artifactInvalidated &&
      isLegacyPublicScoreShareEligible(widget.snapshot, game);

  bool get _canShareAnything =>
      _canShare || _canShareFixture || _canShareLegacy;

  String get _shareLabel => _canShareLegacy
      ? 'Share final score'
      : game.isFinal
      ? 'Share published result'
      : 'Share upcoming game';

  String get _artifactUnavailableMessage {
    if (_artifactInvalidated) {
      return 'The public release changed or could not be reverified. Refresh this view before sharing or exporting.';
    }
    if (!widget.snapshot.version.isVersioned) {
      return 'Sharing is not available for this result yet.';
    }
    if (!widget.snapshot.version.isCompatibilityArtifactEligible) {
      return 'Sharing is not available for this result yet.';
    }
    return 'Sharing is not available for this game yet.';
  }

  Future<void> _share() async {
    if (!_beginArtifactAction()) return;
    try {
      if (_canShareLegacy) {
        final validator =
            widget.legacyShareValidator ??
            PublicLegacyGameShareValidator(
              ref.read(publicLeagueRepositoryProvider),
            );
        final current = await validator.requireCurrent(
          displayed: widget.snapshot,
          displayedGame: game,
        );
        if (!mounted) return;
        final currentBranding = publicShareBranding(
          current.snapshot,
          current.snapshot.leagueForDivision(current.game!.divisionId),
        );
        await showBrandedShareSheet(
          context: context,
          branding: currentBranding,
          payload: BrandedSharePayload.legacyPublicGame(
            snapshot: current.snapshot,
            game: current.game!,
            branding: currentBranding,
          ),
          validateCurrent: () async {
            await validator.requireCurrent(
              displayed: widget.snapshot,
              displayedGame: game,
            );
          },
        );
        return;
      }
      final binding = game.isFinal
          ? _artifactBinding
          : PublicArtifactBinding.snapshot(widget.snapshot);
      final current = await _releaseValidator.requireCurrent(binding);
      if (!mounted) return;
      final currentGame =
          current.game ?? current.snapshot.gameDetail(game.gameId)?.game;
      if (currentGame == null || currentGame.isFinal != game.isFinal) {
        throw const PublicArtifactReleaseException(
          'The game changed after this view was opened.',
        );
      }
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: game.isFinal
            ? BrandedSharePayload.publicGame(
                snapshot: current.snapshot,
                game: _presentation ? game : currentGame,
                presentation: _presentation,
                branding: branding,
                canonicalUri: widget.canonicalUri,
              )
            : BrandedSharePayload.publicFixture(
                snapshot: current.snapshot,
                game: currentGame,
                branding: branding,
                canonicalUri: widget.canonicalUri,
              ),
        validateCurrent: () async {
          await _releaseValidator.requireCurrent(binding);
        },
      );
    } on PublicArtifactReleaseException catch (error) {
      _handleArtifactValidationError(error);
    } finally {
      _endArtifactAction();
    }
  }

  Future<void> _shareBoxScore() async {
    if (game.playerLines.isEmpty || !_beginArtifactAction()) return;
    try {
      final current = await _releaseValidator.requireCurrent(_artifactBinding);
      if (!mounted) return;
      final currentGame = current.game!;
      await showBrandedShareSheet(
        context: context,
        branding: branding,
        payload: BrandedSharePayload.publicBoxScore(
          snapshot: current.snapshot,
          game: _presentation ? game : currentGame,
          presentation: _presentation,
          branding: branding,
          canonicalUri: widget.canonicalUri,
        ),
        validateCurrent: _validateShareSheetRelease,
      );
    } on PublicArtifactReleaseException catch (error) {
      _handleArtifactValidationError(error);
    } finally {
      _endArtifactAction();
    }
  }

  Future<void> _copy() async {
    if (!_canShare) return;
    if (!_beginArtifactAction()) return;
    var copied = false;
    try {
      final current = await _releaseValidator.requireCurrent(_artifactBinding);
      final text = _presentation
          ? BrandedSharePayload.publicBoxScore(
              snapshot: current.snapshot,
              game: game,
              branding: branding,
              presentation: true,
            ).shareText
          : PublicStatExportService.gameSummaryText(
              snapshot: current.snapshot,
              gameId: game.gameId,
            );
      await (widget.clipboardWriter ?? _writeClipboard)(text);
      copied = true;
      await _releaseValidator.requireCurrent(_artifactBinding);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    } on PublicArtifactReleaseException catch (error) {
      _handleArtifactValidationError(
        error,
        actionMayHaveCompleted: copied,
        definitiveMessage: copied
            ? 'The publication changed while copying. The clipboard may contain an older result; do not distribute it.'
            : error.message,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy. Clipboard access was denied.'),
        ),
      );
    } finally {
      _endArtifactAction();
    }
  }

  Future<void> _downloadCsv() async {
    if (!widget.canExportStats || !_canShare || !_beginArtifactAction()) return;
    setState(() => _downloadingCsv = true);
    var platformAccepted = false;
    try {
      final current = await _releaseValidator.requireCurrent(_artifactBinding);
      final csv = PublicStatExportService.gameCsv(
        snapshot: current.snapshot,
        gameId: game.gameId,
        grant: PublicExportGrant.media,
      );
      if (!_downloader.isSupported) {
        throw UnsupportedError('Downloads are unavailable.');
      }
      final fileName =
          '${_fileSlug(current.snapshot.leagueShortName)}-${_fileSlug(game.gameId)}-${current.snapshot.version.shortLabel}.csv';
      await _releaseValidator.requireCurrent(_artifactBinding);
      final destination = await _downloader.download(
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
      );
      platformAccepted = true;
      await _releaseValidator.requireCurrent(_artifactBinding);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV download started for $destination')),
      );
    } on PublicArtifactReleaseException catch (error) {
      _handleArtifactValidationError(
        error,
        actionMayHaveCompleted: platformAccepted,
        definitiveMessage: platformAccepted
            ? 'The publication changed while the CSV was saving. The downloaded file may be outdated; do not distribute it.'
            : error.message,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save the CSV. No file was downloaded.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingCsv = false);
      _endArtifactAction();
    }
  }

  bool _beginArtifactAction() {
    if (!_canShareAnything || _artifactActionPending) return false;
    setState(() => _artifactActionPending = true);
    return true;
  }

  void _endArtifactAction() {
    if (mounted && _artifactActionPending) {
      setState(() => _artifactActionPending = false);
    }
  }

  void _invalidateArtifact(String message) {
    if (!mounted) return;
    setState(() => _artifactInvalidated = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$message Refresh this view before continuing.')),
    );
  }

  void _handleArtifactValidationError(
    PublicArtifactReleaseException error, {
    bool actionMayHaveCompleted = false,
    String? definitiveMessage,
  }) {
    if (!error.retryable) {
      _invalidateArtifact(definitiveMessage ?? error.message);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          actionMayHaveCompleted
              ? 'The server check failed after the action. The older item may be on your device; do not distribute it yet. Reconnect and try again.'
              : 'The server check failed. Reconnect and try Share again.',
        ),
      ),
    );
  }

  Future<void> _writeClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> _validateShareSheetRelease() async {
    try {
      await _releaseValidator.requireCurrent(_artifactBinding);
    } on PublicArtifactReleaseException catch (error) {
      if (!error.retryable && mounted) {
        setState(() => _artifactInvalidated = true);
      }
      rethrow;
    }
  }
}

enum _GameDetailSection { summary, boxScore, teamStats }

class _GameDetailTabs extends StatelessWidget {
  const _GameDetailTabs({
    required this.selected,
    required this.boxScoreAvailable,
    required this.onSelected,
  });

  final _GameDetailSection selected;
  final bool boxScoreAvailable;
  final ValueChanged<_GameDetailSection> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (_GameDetailSection.summary, Icons.summarize_outlined, 'Summary'),
      (_GameDetailSection.boxScore, Icons.table_chart_outlined, 'Box score'),
      (_GameDetailSection.teamStats, Icons.analytics_outlined, 'Team stats'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: const Color(0xFFE3E8F0)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100B1D3A),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _GameDetailTab(
                icon: item.$2,
                label: item.$3,
                selected: selected == item.$1,
                enabled:
                    item.$1 == _GameDetailSection.summary || boxScoreAvailable,
                onTap: () => onSelected(item.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _GameDetailTab extends StatelessWidget {
  const _GameDetailTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const royal = Color(0xFF184A9E);
    const gold = Color(0xFFE7BC5A);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          border: selected
              ? const Border(bottom: BorderSide(color: gold, width: 3))
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: !enabled
                  ? Theme.of(context).disabledColor
                  : selected
                  ? royal
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: !enabled
                    ? Theme.of(context).disabledColor
                    : selected
                    ? royal
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGame game;

  const _ScoreCard({required this.snapshot, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: publicRoyalGradient,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260B1D3A),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7BC5A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(game.status),
                  style: const TextStyle(
                    color: Color(0xFF0B1D3A),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              if (game.isFinal)
                const Text(
                  'OFFICIAL RESULT',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _TeamScore(
            snapshot: snapshot,
            teamId: game.homeTeamId,
            name: game.homeTeamName ?? 'Home',
            score: game.homeScore,
            winner: _isWinner(game.homeScore, game.awayScore),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: Color(0x55E7BC5A), height: 1),
          ),
          _TeamScore(
            snapshot: snapshot,
            teamId: game.awayTeamId,
            name: game.awayTeamName ?? 'Away',
            score: game.awayScore,
            winner: _isWinner(game.awayScore, game.homeScore),
          ),
        ],
      ),
    );
  }

  bool _isWinner(int? score, int? otherScore) =>
      game.isFinal && score != null && otherScore != null && score > otherScore;
}

class _TeamScore extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final String? teamId;
  final String name;
  final int? score;
  final bool winner;

  const _TeamScore({
    required this.snapshot,
    required this.teamId,
    required this.name,
    required this.score,
    required this.winner,
  });

  @override
  Widget build(BuildContext context) => _TeamProfileLink(
    snapshot: snapshot,
    teamId: teamId,
    teamName: name,
    interactionKey: Key('game-score-team-${teamId ?? name}'),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          PublicTeamMark(
            snapshot: snapshot,
            teamId: teamId,
            name: name,
            size: 60,
            onDarkSurface: true,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              compactTeamName(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
            ),
          ),
          if (winner)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(
                Icons.arrow_drop_up,
                color: Color(0xFFE7BC5A),
                size: 24,
              ),
            ),
          Text(
            score?.toString() ?? '—',
            style: TextStyle(
              color: winner ? const Color(0xFFE7BC5A) : Colors.white70,
              fontFamily: 'BarlowCondensed',
              fontSize: 38,
              height: 0.95,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (_publishedTeamId(snapshot, teamId) != null) ...[
            const SizedBox(width: 3),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
          ],
        ],
      ),
    ),
  );
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.snapshot,
    required this.detail,
    required this.game,
    required this.presentation,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicGameDetail detail;
  final PublicGame game;
  final bool presentation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _MetadataCard(snapshot: snapshot, detail: detail),
      const SizedBox(height: 20),
      Text('Recap', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      game.recap == null
          ? const AppStateMessage(
              title: 'Recap unavailable',
              message: 'A recap has not been posted for this game yet.',
              icon: Icons.article_outlined,
            )
          : Text(game.recap!, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 20),
      Text('Period scores', style: Theme.of(context).textTheme.titleLarge),
      if (!presentation && presentationQuarterScores(game).isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.table_rows_outlined),
            label: const Text('View quarter breakdown'),
            onPressed: () => showPresentationQuarters(context, game),
          ),
        ),
      const SizedBox(height: 8),
      game.periodScores.isEmpty
          ? const AppStateMessage(
              title: 'Period breakdown unavailable',
              message: 'Period-by-period scores have not been posted yet.',
              icon: Icons.table_rows_outlined,
            )
          : _PeriodTable(game: game),
    ],
  );
}

class _TeamComparison extends StatelessWidget {
  const _TeamComparison({required this.game});

  final PublicGame game;

  @override
  Widget build(BuildContext context) {
    final homeName = compactTeamName(game.homeTeamName ?? 'Home');
    final awayName = compactTeamName(game.awayTeamName ?? 'Away');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Team comparison', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                homeName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Text(
                awayName,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final entry in <String, int? Function(PublicPlayerGameLine)>{
          'Points': (p) => p.points,
          'Rebounds': (p) => p.rebounds,
          'Assists': (p) => p.assists,
          'Steals': (p) => p.steals,
          'Blocks': (p) => p.blocks,
        }.entries)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: const Color(0xFFE3E8F0)),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0B1D3A),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _teamTotal(game, game.homeTeamId, entry.value),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'BarlowCondensed',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(child: Text(entry.key, textAlign: TextAlign.center)),
                SizedBox(
                  width: 48,
                  child: Text(
                    _teamTotal(game, game.awayTeamId, entry.value),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'BarlowCondensed',
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetadataCard extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGameDetail detail;

  const _MetadataCard({required this.snapshot, required this.detail});

  @override
  Widget build(BuildContext context) {
    final game = detail.game;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _MetadataRow(
              icon: Icons.calendar_today_outlined,
              label: game.dateOnly
                  ? LeagueTime.formatJamaicaDate(game.startTime)
                  : '${LeagueTime.formatJamaicaDate(game.startTime)} · ${LeagueTime.formatJamaicaTime(game.startTime)}',
            ),
            _MetadataRow(
              icon: Icons.emoji_events_outlined,
              label:
                  snapshot.leagueForDivision(game.divisionId).seasonLabel ??
                  '${snapshot.seasonName} · ${detail.divisionName}',
            ),
            _MetadataRow(
              icon: Icons.location_on_outlined,
              label: game.venue ?? 'Venue not published',
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetadataRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

class _PeriodTable extends StatelessWidget {
  final PublicGame game;

  const _PeriodTable({required this.game});

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F4F8)),
        headingTextStyle: const TextStyle(
          color: Color(0xFF0B1D3A),
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: const TextStyle(
          color: Color(0xFF0B1D3A),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        columns: [
          const DataColumn(label: Text('Period')),
          DataColumn(
            label: Text(compactTeamName(game.homeTeamName ?? 'Home')),
            numeric: true,
          ),
          DataColumn(
            label: Text(compactTeamName(game.awayTeamName ?? 'Away')),
            numeric: true,
          ),
        ],
        rows: game.periodScores
            .map(
              (period) => DataRow(
                cells: [
                  DataCell(Text('${period.period}')),
                  DataCell(Text('${period.homeScore}')),
                  DataCell(Text('${period.awayScore}')),
                ],
              ),
            )
            .toList(growable: false),
      ),
    ),
  );
}

class _PlayerLineTable extends StatelessWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGame game;

  const _PlayerLineTable({required this.snapshot, required this.game});

  @override
  Widget build(BuildContext context) {
    final homeLines = game.playerLines
        .where((line) => line.teamId == game.homeTeamId)
        .toList(growable: false);
    final awayLines = game.playerLines
        .where((line) => line.teamId == game.awayTeamId)
        .toList(growable: false);
    final assignedIds = {...homeLines, ...awayLines};
    final otherLines = game.playerLines
        .where((line) => !assignedIds.contains(line))
        .toList(growable: false);
    final tables = <Widget>[
      if (homeLines.isNotEmpty)
        _TeamBoxScore(
          snapshot: snapshot,
          teamId: game.homeTeamId,
          teamName: game.homeTeamName ?? 'Home',
          score: game.homeScore,
          lines: homeLines,
        ),
      if (awayLines.isNotEmpty)
        _TeamBoxScore(
          snapshot: snapshot,
          teamId: game.awayTeamId,
          teamName: game.awayTeamName ?? 'Away',
          score: game.awayScore,
          lines: awayLines,
        ),
      if (otherLines.isNotEmpty)
        _TeamBoxScore(
          snapshot: snapshot,
          teamId: null,
          teamName: 'Other published players',
          score: null,
          lines: otherLines,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900 && tables.length == 2) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tables[0]),
                  const SizedBox(width: 20),
                  Expanded(child: tables[1]),
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < tables.length; i++) ...[
                  tables[i],
                  if (i != tables.length - 1) const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Tap a statistic to sort. The first tap shows the highest values. Swipe sideways for more statistics; player names stay visible. A dash means the statistic was not published.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _TeamBoxScore extends StatelessWidget {
  const _TeamBoxScore({
    required this.snapshot,
    required this.teamId,
    required this.teamName,
    required this.score,
    required this.lines,
  });

  final PublicLeagueSnapshot snapshot;
  final String? teamId;
  final String teamName;
  final int? score;
  final List<PublicPlayerGameLine> lines;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x100B1D3A),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: Column(
      children: [
        _TeamProfileLink(
          snapshot: snapshot,
          teamId: teamId,
          teamName: teamName,
          interactionKey: Key('box-score-team-${teamId ?? teamName}'),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color(0xFF102A70),
                  Color(0xFF234EBD),
                  Color(0xFF5274D3),
                  Color(0xFF234EBD),
                ],
                stops: [0, 0.34, 0.52, 1],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                PublicTeamMark(
                  snapshot: snapshot,
                  teamId: teamId,
                  name: teamName,
                  size: 46,
                  onDarkSurface: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    teamName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.45,
                    ),
                  ),
                ),
                if (score != null)
                  Text(
                    '$score',
                    style: const TextStyle(
                      color: Color(0xFFE7BC5A),
                      fontFamily: 'BarlowCondensed',
                      fontSize: 27,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                if (_publishedTeamId(snapshot, teamId) != null) ...[
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white70,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
        _PinnedStatsTable(snapshot: snapshot, lines: lines),
      ],
    ),
  );
}

String? _publishedTeamId(PublicLeagueSnapshot snapshot, String? teamId) {
  if (teamId == null) return null;
  return snapshot.teams.any((team) => team.teamId == teamId) ? teamId : null;
}

class _TeamProfileLink extends StatelessWidget {
  const _TeamProfileLink({
    required this.snapshot,
    required this.teamId,
    required this.teamName,
    required this.interactionKey,
    required this.borderRadius,
    required this.child,
  });

  final PublicLeagueSnapshot snapshot;
  final String? teamId;
  final String teamName;
  final Key interactionKey;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final publishedTeamId = _publishedTeamId(snapshot, teamId);
    if (publishedTeamId == null) return child;
    return Semantics(
      button: true,
      label: 'Open $teamName team profile',
      child: Tooltip(
        message: 'Open $teamName',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: interactionKey,
            borderRadius: borderRadius,
            onTap: () => context.push(PublicRoutePaths.team(publishedTeamId)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PinnedStatsTable extends StatefulWidget {
  const _PinnedStatsTable({required this.snapshot, required this.lines});

  final PublicLeagueSnapshot snapshot;
  final List<PublicPlayerGameLine> lines;

  @override
  State<_PinnedStatsTable> createState() => _PinnedStatsTableState();
}

class _PinnedStatsTableState extends State<_PinnedStatsTable> {
  String? _sortLabel;
  bool _descending = true;

  static const double _nameWidth = 150;
  static const double _rowHeight = 44;
  static const double _headerHeight = 36;

  @override
  Widget build(BuildContext context) {
    final columns = <_StatColumn>[
      _StatColumn.number('MIN', (line) => line.minutes),
      _StatColumn.number('PTS', (line) => line.points, emphasized: true),
      _StatColumn.number('REB', (line) => line.rebounds),
      _StatColumn.number('AST', (line) => line.assists),
      _StatColumn.number('STL', (line) => line.steals),
      _StatColumn.number('BLK', (line) => line.blocks),
      _StatColumn.number('TO', (line) => line.turnovers),
      _StatColumn.number('PF', (line) => line.fouls),
      _StatColumn.shooting(
        '2PT',
        (line) => line.twoPointMade,
        (line) => line.twoPointAttempted,
      ),
      _StatColumn.shooting(
        '3PT',
        (line) => line.threePointMade,
        (line) => line.threePointAttempted,
      ),
      _StatColumn.shooting(
        'FT',
        (line) => line.freeThrowMade,
        (line) => line.freeThrowAttempted,
      ),
    ];
    final statsWidth = columns.fold<double>(
      0,
      (total, column) => total + column.width,
    );
    final selectedColumn = _sortLabel == null
        ? null
        : columns.where((column) => column.label == _sortLabel).firstOrNull;
    final sortedLines = [...widget.lines];
    final read = selectedColumn?.sortValue;
    if (read != null) {
      sortedLines.sort((left, right) {
        final leftValue = read(left);
        final rightValue = read(right);
        if (leftValue == null && rightValue == null) {
          return left.displayName.compareTo(right.displayName);
        }
        if (leftValue == null) return 1;
        if (rightValue == null) return -1;
        final comparison = leftValue.compareTo(rightValue);
        if (comparison != 0) return _descending ? -comparison : comparison;
        return left.displayName.compareTo(right.displayName);
      });
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: _nameWidth,
          child: Column(
            children: [
              _TableCell(
                height: _headerHeight,
                background: const Color(0xFFF1F4F8),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                child: const Text(
                  'PLAYER',
                  style: TextStyle(
                    color: Color(0xFF5F6F86),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (var i = 0; i < sortedLines.length; i++)
                _PlayerNameCell(
                  snapshot: widget.snapshot,
                  line: sortedLines[i],
                  shaded: i.isOdd,
                ),
              const _TableCell(
                height: _rowHeight,
                background: Color(0xFFF1F4F8),
                padding: EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                child: Text(
                  'TOTALS',
                  style: TextStyle(
                    color: Color(0xFF0B1D3A),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: statsWidth,
              child: Column(
                children: [
                  _StatsRow(
                    height: _headerHeight,
                    background: const Color(0xFFF1F4F8),
                    children: [
                      for (final column in columns)
                        column.header(
                          selected: column.label == _sortLabel,
                          descending: _descending,
                          onTap: () => _sortBy(column),
                        ),
                    ],
                  ),
                  for (var i = 0; i < sortedLines.length; i++)
                    _StatsRow(
                      height: _rowHeight,
                      background: i.isOdd
                          ? const Color(0xFFF8FAFC)
                          : Colors.white,
                      children: [
                        for (final column in columns)
                          column.value(sortedLines[i]),
                      ],
                    ),
                  _StatsRow(
                    height: _rowHeight,
                    background: const Color(0xFFF1F4F8),
                    children: [
                      for (final column in columns) column.total(widget.lines),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _sortBy(_StatColumn column) {
    setState(() {
      if (_sortLabel == column.label) {
        _descending = !_descending;
      } else {
        _sortLabel = column.label;
        _descending = true;
      }
    });
  }
}

class _PlayerNameCell extends StatelessWidget {
  const _PlayerNameCell({
    required this.snapshot,
    required this.line,
    required this.shaded,
  });

  final PublicLeagueSnapshot snapshot;
  final PublicPlayerGameLine line;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final hasPublicProfile = snapshot.playerDetail(line.playerId) != null;
    final content = Row(
      children: [
        Expanded(
          child: Text(
            line.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: hasPublicProfile
                  ? const Color(0xFF184A9E)
                  : const Color(0xFF0B1D3A),
              fontSize: 12,
              fontWeight: hasPublicProfile ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        if (hasPublicProfile)
          const Icon(Icons.chevron_right, size: 15, color: Color(0xFF184A9E)),
      ],
    );
    return _TableCell(
      height: _PinnedStatsTableState._rowHeight,
      background: shaded ? const Color(0xFFF8FAFC) : Colors.white,
      padding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      child: hasPublicProfile
          ? InkWell(
              onTap: () => context.push(
                '${PublicRoutePaths.root}/players/${Uri.encodeComponent(line.playerId)}',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: content,
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: content,
            ),
    );
  }
}

class _StatColumn {
  const _StatColumn._({
    required this.label,
    required this.width,
    required this.lineValue,
    required this.totalValue,
    required this.sortValue,
    this.emphasized = false,
  });

  factory _StatColumn.number(
    String label,
    int? Function(PublicPlayerGameLine) read, {
    bool emphasized = false,
  }) => _StatColumn._(
    label: label,
    width: 48,
    emphasized: emphasized,
    sortValue: read,
    lineValue: (line) => _known(read(line)),
    totalValue: (lines) => _sumKnown(lines, read),
  );

  factory _StatColumn.shooting(
    String label,
    int? Function(PublicPlayerGameLine) made,
    int? Function(PublicPlayerGameLine) attempted,
  ) => _StatColumn._(
    label: label,
    width: 62,
    sortValue: made,
    lineValue: (line) => _madeAttempted(made(line), attempted(line)),
    totalValue: (lines) => _sumMadeAttempted(lines, made, attempted),
  );

  final String label;
  final double width;
  final String Function(PublicPlayerGameLine) lineValue;
  final String Function(List<PublicPlayerGameLine>) totalValue;
  final int? Function(PublicPlayerGameLine) sortValue;
  final bool emphasized;

  Widget header({
    required bool selected,
    required bool descending,
    required VoidCallback onTap,
  }) => SizedBox(
    width: width,
    child: Semantics(
      button: true,
      label: selected
          ? 'Sort by $label, ${descending ? 'highest first' : 'lowest first'}'
          : 'Sort by $label, highest first',
      child: InkWell(
        key: ValueKey('box-score-sort-$label'),
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF184A9E)
                    : const Color(0xFF5F6F86),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (selected)
              Icon(
                descending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 10,
                color: const Color(0xFF184A9E),
              ),
          ],
        ),
      ),
    ),
  );

  Widget value(PublicPlayerGameLine line) => SizedBox(
    width: width,
    child: Text(
      lineValue(line),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: const Color(0xFF0B1D3A),
        fontSize: 12,
        fontWeight: emphasized ? FontWeight.w900 : FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );

  Widget total(List<PublicPlayerGameLine> lines) => SizedBox(
    width: width,
    child: Text(
      totalValue(lines),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Color(0xFF0B1D3A),
        fontSize: 12,
        fontWeight: FontWeight.w900,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.height,
    required this.background,
    required this.children,
  });

  final double height;
  final Color background;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => _TableCell(
    height: height,
    background: background,
    padding: EdgeInsets.zero,
    child: Row(children: children),
  );
}

class _TableCell extends StatelessWidget {
  const _TableCell({
    required this.height,
    required this.background,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 6),
    this.alignment = Alignment.center,
  });

  final double height;
  final Color background;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    alignment: alignment,
    padding: padding,
    decoration: BoxDecoration(
      color: background,
      border: const Border(bottom: BorderSide(color: Color(0xFFE8EDF3))),
    ),
    child: child,
  );
}

class _ArtifactActions extends StatelessWidget {
  final bool canShare;
  final bool canCopy;
  final String shareLabel;
  final bool canShareBoxScore;
  final bool canExport;
  final bool downloadSupported;
  final bool downloadingCsv;
  final bool actionPending;
  final VoidCallback onShare;
  final VoidCallback onShareBoxScore;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDownloadCsv;

  const _ArtifactActions({
    required this.canShare,
    required this.canCopy,
    required this.shareLabel,
    required this.canShareBoxScore,
    required this.canExport,
    required this.downloadSupported,
    required this.downloadingCsv,
    required this.actionPending,
    required this.onShare,
    required this.onShareBoxScore,
    required this.onCopy,
    required this.onDownloadCsv,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: canShare && !actionPending ? onShare : null,
        icon: const Icon(Icons.ios_share_outlined),
        label: Text(shareLabel),
      ),
      if (canShareBoxScore) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: actionPending ? null : onShareBoxScore,
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Share box score'),
        ),
      ],
      if (canCopy) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: actionPending ? null : onCopy,
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy game summary'),
        ),
      ],
      if (canExport) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: actionPending || downloadingCsv || !downloadSupported
              ? null
              : onDownloadCsv,
          icon: downloadingCsv
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text(downloadingCsv ? 'Saving CSV…' : 'Download game CSV'),
        ),
        if (!downloadSupported)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'CSV downloads are not supported on this platform. Copy the published summary instead.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ],
  );
}

String _known(int? value) => value?.toString() ?? '—';

String _sumKnown(
  List<PublicPlayerGameLine> lines,
  int? Function(PublicPlayerGameLine) read,
) {
  final values = lines.map(read).toList(growable: false);
  if (values.isEmpty || values.any((value) => value == null)) return '—';
  return '${values.fold<int>(0, (sum, value) => sum + value!)}';
}

String _sumMadeAttempted(
  List<PublicPlayerGameLine> lines,
  int? Function(PublicPlayerGameLine) made,
  int? Function(PublicPlayerGameLine) attempted,
) {
  final madeTotal = _sumKnown(lines, made);
  final attemptedTotal = _sumKnown(lines, attempted);
  if (madeTotal == '—' || attemptedTotal == '—') return '—';
  return '$madeTotal-$attemptedTotal';
}

String _teamTotal(
  PublicGame game,
  String? teamId,
  int? Function(PublicPlayerGameLine) metric,
) {
  final values = game.playerLines
      .where((p) => p.teamId == teamId)
      .map(metric)
      .toList();
  if (values.isEmpty || values.any((v) => v == null)) return '—';
  return '${values.fold<int>(0, (sum, value) => sum + value!)}';
}

String _madeAttempted(int? made, int? attempted) =>
    made == null || attempted == null ? '—' : '$made-$attempted';

String _short(String? value) => value == null
    ? 'unavailable'
    : value.length <= 12
    ? value
    : value.substring(0, 12);

String _fileSlug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'hoopsconnect' : slug;
}

String _statusLabel(PublicGameStatus status) => switch (status) {
  PublicGameStatus.finalResult => 'FINAL',
  PublicGameStatus.scheduled => 'SCHEDULED',
  PublicGameStatus.postponed => 'POSTPONED',
  PublicGameStatus.canceled => 'CANCELED',
};
