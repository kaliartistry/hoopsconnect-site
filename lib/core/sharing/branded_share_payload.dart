import '../../models/association_branding_model.dart';
import '../../models/game_stats_model.dart';
import '../../models/leaderboard_model.dart';
import '../../models/player_season_stats_model.dart';
import '../../models/public_league_snapshot.dart';
import '../../models/standings_model.dart';
import '../../services/game_summary_generator.dart';

/// Presentation-ready content shared from a league result or stat view.
class BrandedSharePayload {
  final String title;
  final String eyebrow;
  final String headline;
  final String detail;
  final String shareText;
  final String fileName;
  final String sourceLabel;
  final String? versionLabel;

  const BrandedSharePayload({
    required this.title,
    this.eyebrow = 'FINAL',
    required this.headline,
    required this.detail,
    required this.shareText,
    required this.fileName,
    this.sourceLabel = 'League result',
    this.versionLabel,
  });

  factory BrandedSharePayload.gameSummary({
    required GameStatsModel stats,
    required AssociationBrandingModel branding,
  }) {
    final headline = GameSummaryGenerator.generateHeadline(stats);
    final detail = GameSummaryGenerator.generateNarrative(stats);
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      headline,
      if (detail.isNotEmpty && detail != headline) '',
      if (detail.isNotEmpty && detail != headline) detail,
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '${branding.shortName} game result',
      eyebrow: 'FINAL',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-game-result.png',
      sourceLabel: 'Approved internal result',
    );
  }

  factory BrandedSharePayload.publicGame({
    required PublicLeagueSnapshot snapshot,
    required PublicGame game,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
  }) {
    if (!snapshot.canCreatePublishedArtifacts || !game.hasVersionedResult) {
      throw StateError(
        'A versioned, published final result is required for sharing.',
      );
    }
    final homeName = game.homeTeamName ?? 'Home';
    final awayName = game.awayTeamName ?? 'Away';
    final homeScore = game.homeScore!;
    final awayScore = game.awayScore!;
    final headline = homeScore == awayScore
        ? '$homeName and $awayName finish tied $homeScore-$awayScore'
        : homeScore > awayScore
        ? '$homeName defeats $awayName $homeScore-$awayScore'
        : '$awayName defeats $homeName $awayScore-$homeScore';
    final detail = game.recap ?? '${snapshot.seasonName} published result';
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      headline,
      if (game.recap != null) '',
      if (game.recap != null) game.recap!,
      '',
      ?sponsorLine,
      snapshot.leagueName,
      'Publication: ${snapshot.version.snapshotVersion}',
      'Result: ${game.resultVersion}',
      if (canonicalUri != null) canonicalUri.toString(),
      'Shared from HoopsConnect',
    ];

    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} published game result',
      eyebrow: 'FINAL',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(game.gameId)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league result',
      versionLabel: 'Publication ${snapshot.version.shortLabel}',
    );
  }

  factory BrandedSharePayload.leaderboard({
    required List<LeaderboardEntry> rankings,
    required String category,
    required AssociationBrandingModel branding,
  }) {
    if (rankings.isEmpty) {
      throw ArgumentError.value(
        rankings,
        'rankings',
        'A leaderboard share requires at least one ranking.',
      );
    }
    final label = _categoryLabel(category);
    final topRankings = rankings.take(3).toList(growable: false);
    final leader = topRankings.first;
    final detail = topRankings.indexed
        .map(
          (item) =>
              '#${item.$1 + 1} ${item.$2.name} · ${item.$2.teamName} · ${item.$2.value.toStringAsFixed(1)}',
        )
        .join('\n');
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      '$label Leaders',
      '',
      ...rankings.indexed.map(
        (item) =>
            '${item.$1 + 1}. ${item.$2.name} (${item.$2.teamName}) - ${item.$2.value.toStringAsFixed(1)}',
      ),
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '${branding.shortName} $label leaders',
      eyebrow: 'SEASON LEADERS',
      headline:
          '${leader.name} leads with ${leader.value.toStringAsFixed(1)} $label',
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-${_slug(category)}-leaders.png',
    );
  }

  factory BrandedSharePayload.publicLeaderboard({
    required PublicLeagueSnapshot snapshot,
    required PublicLeaderboard leaderboard,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
  }) {
    _requirePublishedSnapshot(snapshot);
    _requirePublicIdentityEpoch(snapshot);
    if (leaderboard.rankings.isEmpty) {
      throw ArgumentError.value(
        leaderboard.rankings,
        'leaderboard.rankings',
        'A leaderboard share requires at least one public ranking.',
      );
    }
    final label = leaderboard.categoryLabel;
    final topRankings = leaderboard.rankings.take(3).toList(growable: false);
    final leader = topRankings.first;
    final detail = topRankings.indexed
        .map(
          (item) =>
              '#${item.$1 + 1} ${item.$2.displayName} · ${item.$2.teamName} · ${_publicMetric(item.$2.value)}',
        )
        .join('\n');
    final lines = <String>[
      '$label Leaders',
      '',
      ...leaderboard.rankings.indexed.map(
        (item) =>
            '${item.$1 + 1}. ${item.$2.displayName} (${item.$2.teamName}) - ${_publicMetric(item.$2.value)}',
      ),
      '',
      ..._publishedFooter(snapshot, branding, canonicalUri),
    ];
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} $label leaders',
      eyebrow: 'SEASON LEADERS',
      headline:
          '${leader.displayName} leads with ${_publicMetric(leader.value)} $label',
      detail: detail,
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(leaderboard.category)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league statistics',
      versionLabel: 'Publication ${snapshot.version.shortLabel}',
    );
  }

  factory BrandedSharePayload.playerStats({
    required PlayerSeasonStatsModel stats,
    required AssociationBrandingModel branding,
  }) {
    final teamName = stats.teamName?.trim().isNotEmpty == true
        ? stats.teamName!.trim()
        : 'Independent player';
    final statLine = [
      '${stats.ppg.toStringAsFixed(1)} PPG',
      '${stats.rpg.toStringAsFixed(1)} RPG',
      '${stats.apg.toStringAsFixed(1)} APG',
      '${stats.spg.toStringAsFixed(1)} SPG',
      '${stats.bpg.toStringAsFixed(1)} BPG',
    ];
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      stats.playerName,
      '$teamName · ${stats.gamesPlayed} GP',
      '',
      statLine.join(' · '),
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '${branding.shortName} player stats',
      eyebrow: 'PLAYER SPOTLIGHT',
      headline: stats.playerName,
      detail: '$teamName · ${stats.gamesPlayed} GP\n${statLine.join(' · ')}',
      shareText: lines.join('\n'),
      fileName:
          '${_slug(branding.shortName)}-${_slug(stats.playerName)}-stats.png',
    );
  }

  factory BrandedSharePayload.publicPlayer({
    required PublicLeagueSnapshot snapshot,
    required PublicPlayerDetail player,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
  }) {
    _requirePublishedSnapshot(snapshot);
    _requirePublicIdentityEpoch(snapshot);
    final statLine = player.categories
        .map(
          (entry) =>
              '${_publicMetric(entry.value.value)} ${_categoryLabel(entry.category)} (${snapshot.divisionName(entry.divisionId)})',
        )
        .toList(growable: false);
    final gamesPlayed = player.categories.first.value.gamesPlayed;
    final lines = <String>[
      player.displayName,
      '${player.teamName} · ${_publicGamesPlayed(gamesPlayed)}',
      '',
      statLine.join(' · '),
      '',
      ..._publishedFooter(snapshot, branding, canonicalUri),
    ];
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} player stats',
      eyebrow: 'PLAYER SPOTLIGHT',
      headline: player.displayName,
      detail:
          '${player.teamName} · ${_publicGamesPlayed(gamesPlayed)}\n${statLine.join(' · ')}',
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(player.playerId)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league statistics',
      versionLabel: 'Publication ${snapshot.version.shortLabel}',
    );
  }

  factory BrandedSharePayload.standings({
    required List<TeamStanding> standings,
    required AssociationBrandingModel branding,
    String? divisionName,
  }) {
    if (standings.isEmpty) {
      throw ArgumentError.value(
        standings,
        'standings',
        'A standings share requires at least one team.',
      );
    }
    final leaders = standings.take(3).toList(growable: false);
    final detail = leaders.indexed
        .map(
          (item) =>
              '#${item.$1 + 1} ${item.$2.teamName} · ${item.$2.wins}-${item.$2.losses}',
        )
        .join('\n');
    final scope = divisionName?.trim().isNotEmpty == true
        ? divisionName!.trim()
        : branding.shortName;
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      '$scope Standings',
      '',
      ...standings.indexed.map(
        (item) =>
            '${item.$1 + 1}. ${item.$2.teamName} ${item.$2.wins}-${item.$2.losses} (${item.$2.pct.toStringAsFixed(3)})',
      ),
      '',
    ];
    if (sponsorLine != null) {
      lines.add(sponsorLine);
    }
    lines.addAll([branding.leagueName, 'Shared from HoopsConnect']);

    return BrandedSharePayload(
      title: '$scope standings',
      eyebrow: 'LEAGUE STANDINGS',
      headline: '${standings.first.teamName} leads $scope',
      detail: detail,
      shareText: lines.join('\n'),
      fileName: '${_slug(branding.shortName)}-${_slug(scope)}-standings.png',
    );
  }

  factory BrandedSharePayload.publicStandings({
    required PublicLeagueSnapshot snapshot,
    required List<PublicStanding> standings,
    required AssociationBrandingModel branding,
    String? divisionName,
    Uri? canonicalUri,
  }) {
    _requirePublishedSnapshot(snapshot);
    if (standings.isEmpty) {
      throw ArgumentError.value(
        standings,
        'standings',
        'A standings share requires at least one public row.',
      );
    }
    final leaders = standings.take(3).toList(growable: false);
    final detail = leaders
        .map(
          (row) =>
              '${_publicRankLabel(row)} ${row.teamName} · ${_publicRecord(row)}',
        )
        .join('\n');
    final scope = divisionName?.trim().isNotEmpty == true
        ? divisionName!.trim()
        : snapshot.leagueShortName;
    final lines = <String>[
      '$scope Standings',
      '',
      ...standings.map(
        (row) =>
            '${_publicRankLabel(row)} ${row.teamName} ${_publicRecord(row)} (${_publicMetric(row.pct, decimals: 3)})',
      ),
      '',
      ..._publishedFooter(snapshot, branding, canonicalUri),
    ];
    final first = standings.first;
    final headline = first.rankStatus == PublicRankStatus.unresolved
        ? '$scope standings are published with unresolved ranks'
        : '${first.teamName} leads $scope';
    return BrandedSharePayload(
      title: '$scope standings',
      eyebrow: 'LEAGUE STANDINGS',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(scope)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league statistics',
      versionLabel: 'Publication ${snapshot.version.shortLabel}',
    );
  }
}

void _requirePublishedSnapshot(PublicLeagueSnapshot snapshot) {
  if (!snapshot.canCreatePublishedArtifacts) {
    throw StateError(
      'A versioned, published snapshot is required for sharing.',
    );
  }
}

void _requirePublicIdentityEpoch(PublicLeagueSnapshot snapshot) {
  if (snapshot.version.privacyEpoch == null) {
    throw StateError(
      'A privacy-epoch-bound public snapshot is required for player sharing.',
    );
  }
}

List<String> _publishedFooter(
  PublicLeagueSnapshot snapshot,
  AssociationBrandingModel branding,
  Uri? canonicalUri,
) => [
  ?_sponsorLine(branding),
  snapshot.leagueName,
  'Publication: ${snapshot.version.snapshotVersion}',
  ?canonicalUri?.toString(),
  'Shared from HoopsConnect',
];

String _publicRankLabel(PublicStanding standing) =>
    switch (standing.rankStatus) {
      PublicRankStatus.ranked => '${standing.rank ?? '?'}.',
      PublicRankStatus.tied => 'T${standing.rank ?? '?'}.',
      PublicRankStatus.unresolved => '?.',
    };

String _publicMetric(double? value, {int decimals = 1}) =>
    value?.toStringAsFixed(decimals) ?? 'Unknown';

String _publicRecord(PublicStanding standing) =>
    standing.wins == null || standing.losses == null
    ? 'Record unknown'
    : '${standing.wins}-${standing.losses}';

String _publicGamesPlayed(int? value) =>
    value == null ? 'Games played unknown' : '$value GP';

String? _sponsorLine(AssociationBrandingModel branding) {
  final sponsor = branding.sponsor;
  if (!sponsor.isActive) return null;
  final label = sponsor.label.trim().isEmpty
      ? 'Presented by'
      : sponsor.label.trim();
  return '$label ${sponsor.name.trim()}';
}

String _categoryLabel(String category) {
  switch (category) {
    case 'ppg':
      return 'PPG';
    case 'rpg':
      return 'RPG';
    case 'apg':
      return 'APG';
    case 'spg':
      return 'SPG';
    case 'bpg':
      return 'BPG';
    default:
      return category.trim().toUpperCase();
  }
}

String _slug(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'hoopsconnect' : slug;
}
