import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/link.dart';

import '../../app/router/app_route_contract.dart';
import '../../core/sharing/branded_share_payload.dart';
import '../../core/sharing/branded_share_sheet.dart';
import '../../core/sharing/public_share_branding.dart';
import '../../core/widgets/sponsor_banner.dart';
import '../../core/widgets/public_brand_context.dart';
import '../../models/public_league_snapshot.dart';
import '../../providers/public_league_provider.dart';
import '../../services/public_artifact_release_validator.dart';

/// Cumulative player totals are additive. Player appearances are not team games.
Map<String, int?> recordedTeamTotals(
  PublicLeagueSnapshot snapshot,
  String teamId,
) {
  final result = <String, int?>{};
  final team = snapshot.teams.where((t) => t.teamId == teamId).firstOrNull;
  for (final category in PublicLeaderboard.categoryOrder) {
    final scoped = snapshot.leaderboards.any(
      (b) => b.category == category && b.divisionId == team?.divisionId,
    );
    final rows = snapshot.leaderboards
        .where(
          (b) =>
              b.category == category &&
              (!scoped || b.divisionId == team?.divisionId),
        )
        .expand((b) => b.rankings)
        .where((p) => p.teamId == teamId)
        .toList();
    result[category] =
        rows.isEmpty || rows.any((p) => p.cumulativeTotal == null)
        ? null
        : rows.fold<int>(0, (sum, p) => sum + p.cumulativeTotal!);
    if (category == 'ppg') {
      for (final key in ['twoMade', 'threeMade', 'ftMade']) {
        result[key] =
            rows.isEmpty || rows.any((p) => !p.shootingMade.containsKey(key))
            ? null
            : rows.fold<int>(0, (sum, p) => sum + p.shootingMade[key]!);
      }
    }
  }
  return result;
}

class RecordedTeamTotals extends StatelessWidget {
  const RecordedTeamTotals({
    super.key,
    required this.snapshot,
    required this.teamId,
    this.showAverages = false,
    this.gamesPlayed,
  });
  final PublicLeagueSnapshot snapshot;
  final String teamId;
  final bool showAverages;
  final int? gamesPlayed;

  @override
  Widget build(BuildContext context) {
    final totals = recordedTeamTotals(snapshot, teamId);
    const labels = {
      'ppg': 'PTS',
      'rpg': 'REB',
      'apg': 'AST',
      'spg': 'STL',
      'bpg': 'BLK',
      'twoMade': '2PM',
      'threeMade': '3PM',
      'ftMade': 'FTM',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final entry in labels.entries)
              SizedBox(
                width: 72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showAverages
                          ? (totals[entry.key] == null ||
                                    gamesPlayed == null ||
                                    gamesPlayed! <= 0
                                ? '—'
                                : (totals[entry.key]! / gamesPlayed!)
                                      .toStringAsFixed(1))
                          : '${totals[entry.key] ?? '—'}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      entry.value,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HistoricalLeagueStandings extends ConsumerWidget {
  const HistoricalLeagueStandings({
    super.key,
    required this.snapshot,
    required this.league,
    this.showBranding = false,
  });
  final PublicLeagueSnapshot snapshot;
  final PublicLeagueDefinition league;
  final bool showBranding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = snapshot.teams
        .where((t) => league.divisionIds.contains(t.divisionId))
        .toList();
    final reports = {
      for (final row in league.reportedStandings) row.teamId: row,
    };
    int? points(PublicTeam team) => reports[team.teamId]?.leaguePoints;
    final hasWins = teams.any((team) => reports[team.teamId]?.wins != null);
    final hasLosses = teams.any((team) => reports[team.teamId]?.losses != null);
    final reportedDate = DateTime.tryParse(league.standingsAsOf ?? '');
    final isMidseason =
        league.isNbl2025Archive && league.standingsAsOf == '2025-04-15';
    final reportLabel = [
      if (reportedDate != null)
        'Reported ${DateFormat.yMMMd().format(reportedDate)}',
      if (isMidseason) 'After nine games per team',
    ].join(' · ');
    String shareRow(PublicTeam team) => [
      if (hasWins) '${reports[team.teamId]?.wins ?? '—'} W',
      if (hasLosses) '${reports[team.teamId]?.losses ?? '—'} L',
      '${points(team) ?? '—'} league points',
    ].join(' · ');
    teams.sort((a, b) => (points(b) ?? -1).compareTo(points(a) ?? -1));
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (showBranding) ...[
              PublicBrandContext(
                snapshot: snapshot,
                league: league,
                divisionName: league.seasonLabel,
                showSponsorText: true,
              ),
              const SizedBox(height: 16),
            ],
            Semantics(
              header: true,
              child: Text(
                isMidseason ? 'Midseason standings' : 'Reported standings',
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              reports.isEmpty
                  ? 'League points have not been supplied. Recorded team totals are below.'
                  : [
                      if (reportLabel.isNotEmpty) '$reportLabel.',
                      'Equal points remain tied.',
                    ].join(' '),
            ),
            if (reports.isNotEmpty && snapshot.canCreatePublishedArtifacts)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('Share standings'),
                  onPressed: () async {
                    final binding = PublicArtifactBinding.snapshot(snapshot);
                    final validator = ref.read(
                      publicArtifactReleaseValidatorProvider,
                    );
                    try {
                      await validator.requireCurrent(binding);
                      if (!context.mounted) return;
                      final branding = publicShareBranding(snapshot, league);
                      await showBrandedShareSheet(
                        context: context,
                        branding: branding,
                        payload: BrandedSharePayload(
                          title: '${league.shortName} standings',
                          sheetTitle: 'Share standings',
                          eyebrow: 'LEAGUE STANDINGS',
                          headline: league.name,
                          divisionLabel: league.seasonLabel,
                          tableRows: [
                            for (final team in teams)
                              BrandedShareTableRow(
                                name: team.name,
                                value: '${points(team) ?? '—'}',
                                logoUrl: team.logoUrl,
                                wins: reports[team.teamId]?.wins,
                                losses: reports[team.teamId]?.losses,
                              ),
                          ],
                          detail: teams
                              .map((t) => '${t.name} · ${shareRow(t)}')
                              .join('\n'),
                          shareText: [
                            league.name,
                            '${league.seasonLabel} standings',
                            for (final t in teams) '${t.name}: ${shareRow(t)}',
                            if (reportLabel.isNotEmpty) reportLabel,
                            'Equal points remain tied.',
                            if (league.standingsSourceUrl != null)
                              league.standingsSourceUrl!,
                            if (league.sponsor.enabled)
                              '${league.sponsor.label}: ${league.sponsor.name}',
                          ].join('\n'),
                          fileName: '${league.leagueId}-standings.png',
                          sourceLabel: reportLabel.isEmpty
                              ? 'League points'
                              : reportLabel,
                        ),
                        validateCurrent: () async {
                          await validator.requireCurrent(binding);
                        },
                      );
                    } on PublicArtifactReleaseException catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(error.message)));
                      }
                    }
                  },
                ),
              ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Container(
                    color: const Color(0xFF173B8F),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'TEAM',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (hasWins)
                          const SizedBox(
                            width: 28,
                            child: Text(
                              'W',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        if (hasLosses)
                          const SizedBox(
                            width: 28,
                            child: Text(
                              'L',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        const SizedBox(
                          width: 64,
                          child: Text(
                            'LEAGUE\nPOINTS',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final team in teams)
                    ListTile(
                      onTap: () =>
                          context.push(PublicRoutePaths.team(team.teamId)),
                      leading: SponsorLogo(
                        reference: team.logoUrl,
                        semanticLabel: '${team.name} logo',
                        width: 40,
                        height: 40,
                      ),
                      title: Text(
                        team.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: SizedBox(
                        width: 64 + (hasWins ? 28 : 0) + (hasLosses ? 28 : 0),
                        child: Row(
                          children: [
                            if (hasWins)
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${reports[team.teamId]?.wins ?? '—'}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (hasLosses)
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '${reports[team.teamId]?.losses ?? '—'}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${points(team) ?? '—'}',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!hasWins && !hasLosses)
              Text(
                'The report gives league points. Win and loss totals were not supplied.',
                style: theme.textTheme.bodySmall,
              ),
            if (league.standingsSourceUrl case final String url)
              Align(
                alignment: Alignment.centerLeft,
                child: Link(
                  uri: Uri.parse(url),
                  target: LinkTarget.blank,
                  builder: (context, followLink) => TextButton(
                    onPressed: followLink,
                    child: const Text('Source: Jamaica Gleaner'),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text('Team statistics', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${league.firstRoundStatisticsLabel ?? league.description ?? 'Recorded player totals'}. These totals come from the player statistics workbook.',
            ),
            for (final team in teams) ...[
              const SizedBox(height: 16),
              Text(team.name, style: theme.textTheme.titleMedium),
              RecordedTeamTotals(snapshot: snapshot, teamId: team.teamId),
            ],
          ],
        ),
      ),
    );
  }
}
