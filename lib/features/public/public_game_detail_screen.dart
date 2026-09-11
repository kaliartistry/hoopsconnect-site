import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/sharing/artifact_downloader.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/association_branding_model.dart';
import '../../models/public_league_snapshot.dart';
import '../../services/public_stat_export_service.dart';
import '../../services/stat_export_service.dart';

class PublicGameDetailScreen extends StatefulWidget {
  final PublicLeagueSnapshot snapshot;
  final PublicGameDetail detail;
  final bool canExportStats;
  final Uri? canonicalUri;
  final ArtifactDownloader? downloader;

  const PublicGameDetailScreen({
    super.key,
    required this.snapshot,
    required this.detail,
    this.canExportStats = false,
    this.canonicalUri,
    this.downloader,
  });

  @override
  State<PublicGameDetailScreen> createState() => _PublicGameDetailScreenState();
}

class _PublicGameDetailScreenState extends State<PublicGameDetailScreen> {
  late final ArtifactDownloader _downloader;
  bool _downloadingCsv = false;

  @override
  void initState() {
    super.initState();
    _downloader = widget.downloader ?? createArtifactDownloader();
  }

  PublicGame get game => widget.detail.game;

  AssociationBrandingModel get branding =>
      AssociationBrandingModel.jba(
        associationId: widget.snapshot.associationId,
      ).copyWith(
        leagueName: widget.snapshot.leagueName,
        shortName: widget.snapshot.leagueShortName,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game details'),
        actions: [
          if (_canShare)
            IconButton(
              onPressed: _share,
              tooltip: 'Share published result',
              icon: const Icon(Icons.ios_share_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMd),
        children: [
          if (!_canShare) ...[
            AppStateMessage(
              title: 'Sharing and exports unavailable',
              message: _artifactUnavailableMessage,
              tone: AppStateTone.warning,
            ),
            const SizedBox(height: 16),
          ],
          _ScoreCard(game: game),
          const SizedBox(height: 16),
          _MetadataCard(snapshot: widget.snapshot, detail: widget.detail),
          const SizedBox(height: 20),
          Text('Recap', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          game.recap == null
              ? const AppStateMessage(
                  title: 'Recap unavailable',
                  message:
                      'A public recap was not included with this published result.',
                  icon: Icons.article_outlined,
                )
              : Text(game.recap!, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
          Text('Period scores', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          game.periodScores.isEmpty
              ? const AppStateMessage(
                  title: 'Period breakdown unavailable',
                  message:
                      'The final score is published, but period-by-period scores were not available in this result version.',
                  icon: Icons.table_rows_outlined,
                )
              : _PeriodTable(game: game),
          const SizedBox(height: 20),
          Text('Box score', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          game.playerLines.isEmpty
              ? const AppStateMessage(
                  title: 'Player box score unavailable',
                  message:
                      'No player lines cleared the public identity and publication checks for this result.',
                  icon: Icons.people_outline,
                )
              : _PlayerLineTable(game: game),
          const SizedBox(height: 20),
          _ArtifactActions(
            canShare: _canShare,
            canExport: widget.canExportStats && _canShare,
            downloadSupported: _downloader.isSupported,
            downloadingCsv: _downloadingCsv,
            onShare: _share,
            onCopy: _copy,
            onDownloadCsv: _downloadCsv,
          ),
          const SizedBox(height: 12),
          Text(
            widget.snapshot.version.isVersioned
                ? 'Publication ${widget.snapshot.version.shortLabel} · Result ${_short(game.resultVersion)}'
                : 'Legacy public snapshot · exact version unavailable',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  bool get _canShare =>
      widget.snapshot.canCreatePublishedArtifacts && game.hasVersionedResult;

  String get _artifactUnavailableMessage {
    if (!widget.snapshot.version.isVersioned) {
      return 'You can read this legacy result, but its exact public version cannot be verified.';
    }
    if (!widget.snapshot.version.isCompatibilityArtifactEligible) {
      return 'This publication has not passed the compatibility artifact check.';
    }
    return 'This game does not have a versioned published final result yet.';
  }

  void _share() {
    if (!_canShare) return;
    showBrandedShareSheet(
      context: context,
      branding: branding,
      payload: BrandedSharePayload.publicGame(
        snapshot: widget.snapshot,
        game: game,
        branding: branding,
        canonicalUri: widget.canonicalUri,
      ),
    );
  }

  Future<void> _copy() async {
    if (!_canShare) return;
    final text = PublicStatExportService.gameSummaryText(
      snapshot: widget.snapshot,
      gameId: game.gameId,
    );
    await StatExportService.copyToClipboard(text, context);
  }

  Future<void> _downloadCsv() async {
    if (!widget.canExportStats || !_canShare || _downloadingCsv) return;
    setState(() => _downloadingCsv = true);
    try {
      final csv = PublicStatExportService.gameCsv(
        snapshot: widget.snapshot,
        gameId: game.gameId,
        grant: PublicExportGrant.media,
      );
      if (!_downloader.isSupported) {
        throw UnsupportedError('Downloads are unavailable.');
      }
      final fileName =
          '${_fileSlug(widget.snapshot.leagueShortName)}-${_fileSlug(game.gameId)}-${widget.snapshot.version.shortLabel}.csv';
      final destination = await _downloader.download(
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV download started for $destination')),
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
    }
  }
}

class _ScoreCard extends StatelessWidget {
  final PublicGame game;

  const _ScoreCard({required this.game});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
      ),
      child: Column(
        children: [
          Text(
            _statusLabel(game.status),
            style: TextStyle(
              color: game.isFinal ? scheme.tertiaryContainer : Colors.white70,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          _TeamScore(name: game.homeTeamName ?? 'Home', score: game.homeScore),
          const Divider(color: Colors.white24, height: 24),
          _TeamScore(name: game.awayTeamName ?? 'Away', score: game.awayScore),
        ],
      ),
    );
  }
}

class _TeamScore extends StatelessWidget {
  final String name;
  final int? score;

  const _TeamScore({required this.name, required this.score});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Text(
        score?.toString() ?? 'Not available',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
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
              label: DateFormat(
                'EEEE, MMMM d, yyyy · h:mm a',
              ).format(game.startTime.toLocal()),
            ),
            _MetadataRow(
              icon: Icons.emoji_events_outlined,
              label: '${snapshot.seasonName} · ${detail.divisionName}',
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
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Period')),
          DataColumn(label: Text('Home'), numeric: true),
          DataColumn(label: Text('Away'), numeric: true),
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
  final PublicGame game;

  const _PlayerLineTable({required this.game});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Unknown means the field was not available in this published result.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(8),
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Player')),
              DataColumn(label: Text('MIN'), numeric: true),
              DataColumn(label: Text('PTS'), numeric: true),
              DataColumn(label: Text('OREB'), numeric: true),
              DataColumn(label: Text('DREB'), numeric: true),
              DataColumn(label: Text('REB'), numeric: true),
              DataColumn(label: Text('AST'), numeric: true),
              DataColumn(label: Text('STL'), numeric: true),
              DataColumn(label: Text('BLK'), numeric: true),
              DataColumn(label: Text('TOV'), numeric: true),
              DataColumn(label: Text('FLS'), numeric: true),
              DataColumn(label: Text('2PM-A')),
              DataColumn(label: Text('3PM-A')),
              DataColumn(label: Text('FTM-A')),
            ],
            rows: game.playerLines
                .map(
                  (line) => DataRow(
                    cells: [
                      DataCell(Text(line.displayName)),
                      DataCell(Text(_known(line.minutes))),
                      DataCell(Text(_known(line.points))),
                      DataCell(Text(_known(line.offensiveRebounds))),
                      DataCell(Text(_known(line.defensiveRebounds))),
                      DataCell(Text(_known(line.rebounds))),
                      DataCell(Text(_known(line.assists))),
                      DataCell(Text(_known(line.steals))),
                      DataCell(Text(_known(line.blocks))),
                      DataCell(Text(_known(line.turnovers))),
                      DataCell(Text(_known(line.fouls))),
                      DataCell(
                        Text(
                          _madeAttempted(
                            line.twoPointMade,
                            line.twoPointAttempted,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _madeAttempted(
                            line.threePointMade,
                            line.threePointAttempted,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          _madeAttempted(
                            line.freeThrowMade,
                            line.freeThrowAttempted,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    ],
  );
}

class _ArtifactActions extends StatelessWidget {
  final bool canShare;
  final bool canExport;
  final bool downloadSupported;
  final bool downloadingCsv;
  final VoidCallback onShare;
  final Future<void> Function() onCopy;
  final Future<void> Function() onDownloadCsv;

  const _ArtifactActions({
    required this.canShare,
    required this.canExport,
    required this.downloadSupported,
    required this.downloadingCsv,
    required this.onShare,
    required this.onCopy,
    required this.onDownloadCsv,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.icon(
        onPressed: canShare ? onShare : null,
        icon: const Icon(Icons.ios_share_outlined),
        label: const Text('Share published result'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: canShare ? onCopy : null,
        icon: const Icon(Icons.copy_outlined),
        label: const Text('Copy published summary'),
      ),
      if (canExport) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: downloadingCsv || !downloadSupported
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

String _known(int? value) => value?.toString() ?? 'Unknown';

String _madeAttempted(int? made, int? attempted) =>
    made == null || attempted == null ? 'Unknown' : '$made-$attempted';

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
