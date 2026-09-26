import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final points = {
      for (final row in league.reportedStandings) row.teamId: row.leaguePoints,
    };
    teams.sort(
      (a, b) => (points[b.teamId] ?? -1).compareTo(points[a.teamId] ?? -1),
    );
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
            Text(
              '${league.name} · ${league.seasonLabel ?? 'Statistics'}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              points.isEmpty
                  ? 'League points have not been supplied. Recorded team totals are below.'
                  : 'League points · Reported ${league.standingsAsOf ?? ''}. Equal points remain tied; no tie-break order is assumed.',
            ),
            if (points.isNotEmpty && snapshot.canCreatePublishedArtifacts)
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
                                value: '${points[team.teamId] ?? '—'}',
                                logoUrl: team.logoUrl,
                              ),
                          ],
                          detail: teams
                              .map(
                                (t) =>
                                    '${t.name} · W — · L — · ${points[t.teamId]} league pts',
                              )
                              .join('\n'),
                          shareText: [
                            league.name,
                            '${league.seasonLabel} standings',
                            for (final t in teams)
                              '${t.name}: W — · L — · ${points[t.teamId] ?? '—'} league points',
                            'Reported ${league.standingsAsOf}',
                            'Equal points remain tied.',
                            if (league.standingsSourceUrl != null)
                              league.standingsSourceUrl!,
                            if (league.sponsor.enabled)
                              '${league.sponsor.label}: ${league.sponsor.name}',
                          ].join('\n'),
                          fileName: '${league.leagueId}-standings.png',
                          sourceLabel:
                              'League points · ${league.standingsAsOf}',
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
                    child: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'TEAM',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text(
                            'W',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text(
                            'L',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        SizedBox(
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
                      leading: team.logoUrl == null
                          ? const Icon(Icons.sports_basketball_outlined)
                          : SponsorLogo(
                              reference: team.logoUrl!,
                              semanticLabel: '${team.name} logo',
                              width: 40,
                              height: 40,
                            ),
                      title: Text(
                        team.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: SizedBox(
                        width: 120,
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 28,
                              child: Text('—', textAlign: TextAlign.center),
                            ),
                            const SizedBox(
                              width: 28,
                              child: Text('—', textAlign: TextAlign.center),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${points[team.teamId] ?? '—'}',
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
            Text(
              '— Win/loss records were not supplied with this standings table. Available game reports do not cover the complete season.',
              style: theme.textTheme.bodySmall,
            ),
            if (league.standingsSourceUrl != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(league.standingsSourceUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Source: Jamaica Gleaner'),
                ),
              ),
            const SizedBox(height: 24),
            Text('Team statistics', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${league.description ?? 'Recorded player totals'}. Cumulative totals, not per-game averages or standings points.',
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
