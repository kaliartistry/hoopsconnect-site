import '../../models/association_branding_model.dart';
import '../../models/game_stats_model.dart';
import '../../models/leaderboard_model.dart';
import '../../models/player_season_stats_model.dart';
import '../../models/public_league_snapshot.dart';
import '../../models/standings_model.dart';
import '../time/league_time.dart';
import '../../services/game_summary_generator.dart';
import '../../services/public_artifact_release_validator.dart';

class BrandedShareTeam {
  final String name;
  final String? logoUrl;
  final int? score;

  const BrandedShareTeam({required this.name, this.logoUrl, this.score});
}

class BrandedShareTableRow {
  const BrandedShareTableRow({
    required this.name,
    required this.value,
    this.logoUrl,
    this.wins,
    this.losses,
  });
  final String name;
  final String value;
  final String? logoUrl;
  final int? wins;
  final int? losses;
}

/// Presentation-ready content shared from a league result or stat view.
class BrandedSharePayload {
  final String title;
  final String sheetTitle;
  final String eyebrow;
  final String headline;
  final String detail;
  final String shareText;
  final String fileName;
  final String sourceLabel;
  final String? versionLabel;
  final String? divisionLabel;
  final String? periodScoreLine;
  final List<String> performerLines;
  final List<BrandedShareTeam> teams;
  final bool isDemonstration;
  final List<BrandedShareTableRow> tableRows;
  final List<(String, String, String)> comparisonRows;

  /// Explicit values for the fixed six-tile player template. Missing is not zero.
  final Map<String, String> spotlightStats;

  const BrandedSharePayload({
    required this.title,
    this.sheetTitle = 'Share this published result',
    this.eyebrow = 'FINAL',
    required this.headline,
    required this.detail,
    required this.shareText,
    required this.fileName,
    this.sourceLabel = 'League result',
    this.versionLabel,
    this.divisionLabel,
    this.periodScoreLine,
    this.performerLines = const [],
    this.teams = const [],
    this.isDemonstration = false,
    this.tableRows = const [],
    this.comparisonRows = const [],
    this.spotlightStats = const {},
  });

  bool get isPlayerSpotlight =>
      eyebrow.toUpperCase().contains('PLAYER SPOTLIGHT');

  Map<String, String> get resolvedSpotlightStats => {
    for (final label in ['GP', 'PPG', 'RPG', 'APG', 'SPG', 'BPG'])
      label:
          spotlightStats[label] ??
          RegExp(
            r'(?<![\w.])([0-9]+(?:\.[0-9]+)?)\s*' + label + r'\b',
          ).firstMatch(detail)?.group(1) ??
          'N/A',
  };

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
      sheetTitle: 'Share this final score',
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
    bool presentation = false,
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
    final homeTeam = _publicTeam(snapshot, game.homeTeamId);
    final awayTeam = _publicTeam(snapshot, game.awayTeamId);
    final headline = homeScore == awayScore
        ? '$homeName and $awayName finish tied $homeScore-$awayScore'
        : homeScore > awayScore
        ? '$homeName defeats $awayName $homeScore-$awayScore'
        : '$awayName defeats $homeName $awayScore-$homeScore';
    final detail = game.recap ?? '${snapshot.seasonName} published result';
    final sponsorLine = _sponsorLine(branding);
    final lines = <String>[
      if (presentation) 'Presentation statistics',
      headline,
      if (game.recap != null) '',
      if (game.recap != null) game.recap!,
      '',
      ?sponsorLine,
      snapshot.leagueName,
      if (canonicalUri != null) canonicalUri.toString(),
      'Shared from HoopsConnect',
    ];

    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} published game result',
      sheetTitle: 'Share this final score',
      eyebrow: 'FINAL',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_publicGameFileSlug(game)}-${snapshot.version.shortLabel}.png',
      sourceLabel: presentation
          ? 'Presentation statistics'
          : 'Published league result',
      isDemonstration: presentation,
      versionLabel: null,
      divisionLabel: game.divisionId == null
          ? null
          : snapshot.divisionName(game.divisionId),
      teams: [
        BrandedShareTeam(
          name: homeName,
          logoUrl: homeTeam?.logoUrl,
          score: homeScore,
        ),
        BrandedShareTeam(
          name: awayName,
          logoUrl: awayTeam?.logoUrl,
          score: awayScore,
        ),
      ],
    );
  }

  factory BrandedSharePayload.legacyPublicGame({
    required PublicLeagueSnapshot snapshot,
    required PublicGame game,
    required AssociationBrandingModel branding,
  }) {
    if (!isLegacyPublicScoreShareEligible(snapshot, game)) {
      throw StateError(
        'Only an already-public legacy final score can be previewed.',
      );
    }
    final homeName = game.homeTeamName ?? 'Home';
    final awayName = game.awayTeamName ?? 'Away';
    final homeTeam = _publicTeam(snapshot, game.homeTeamId);
    final awayTeam = _publicTeam(snapshot, game.awayTeamId);
    final homeScore = game.homeScore!;
    final awayScore = game.awayScore!;
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} final score',
      sheetTitle: 'Share final score',
      eyebrow: 'FINAL',
      headline: '$homeName $homeScore · $awayName $awayScore',
      detail: '${LeagueTime.formatJamaicaDate(game.startTime)} · Final',
      shareText: [
        '$homeName $homeScore · $awayName $awayScore',
        '${LeagueTime.formatJamaicaDate(game.startTime)} · Final',
        '',
        ?_sponsorLine(branding),
        snapshot.leagueName,
        'Shared from HoopsConnect',
      ].join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_publicGameFileSlug(game)}-final-score.png',
      sourceLabel: 'League result',
      divisionLabel: game.divisionId == null
          ? null
          : snapshot.divisionName(game.divisionId),
      teams: [
        BrandedShareTeam(
          name: homeName,
          logoUrl: homeTeam?.logoUrl,
          score: homeScore,
        ),
        BrandedShareTeam(
          name: awayName,
          logoUrl: awayTeam?.logoUrl,
          score: awayScore,
        ),
      ],
    );
  }

  factory BrandedSharePayload.publicFixture({
    required PublicLeagueSnapshot snapshot,
    required PublicGame game,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
  }) {
    _requirePublishedSnapshot(snapshot);
    if (game.status != PublicGameStatus.scheduled) {
      throw ArgumentError.value(
        game,
        'game',
        'Only a scheduled game can use the upcoming-game share.',
      );
    }
    final homeName = game.homeTeamName ?? 'Home team';
    final awayName = game.awayTeamName ?? 'Away team';
    final homeTeam = _publicTeam(snapshot, game.homeTeamId);
    final awayTeam = _publicTeam(snapshot, game.awayTeamId);
    final detail = [
      '${LeagueTime.formatJamaicaDate(game.startTime)} · ${LeagueTime.formatJamaicaTime(game.startTime)}',
      if (game.venue != null) game.venue!,
    ].join('\n');
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} upcoming game',
      sheetTitle: 'Share this game',
      eyebrow: 'UPCOMING GAME',
      headline: '$homeName vs $awayName',
      detail: detail,
      shareText: [
        '$homeName vs $awayName',
        detail,
        '',
        ..._publishedFooter(snapshot, branding, canonicalUri),
      ].join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_publicGameFileSlug(game)}-fixture-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league schedule',
      versionLabel: null,
      divisionLabel: game.divisionId == null
          ? null
          : snapshot.divisionName(game.divisionId),
      teams: [
        BrandedShareTeam(name: homeName, logoUrl: homeTeam?.logoUrl),
        BrandedShareTeam(name: awayName, logoUrl: awayTeam?.logoUrl),
      ],
    );
  }

  factory BrandedSharePayload.publicMedia({
    required PublicLeagueSnapshot snapshot,
    required PublicMediaItem item,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
  }) {
    _requirePublishedSnapshot(snapshot);
    if (!snapshot.media.any((entry) => entry.mediaId == item.mediaId)) {
      throw ArgumentError.value(
        item.mediaId,
        'mediaId',
        'Media item is not in this public release.',
      );
    }
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} media',
      sheetTitle: 'Share this story',
      eyebrow: item.typeLabel.toUpperCase(),
      headline: item.title,
      detail: item.summary,
      shareText: [
        item.title,
        '',
        item.summary,
        '',
        ..._publishedFooter(snapshot, branding, canonicalUri),
      ].join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(item.mediaId)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league media',
      versionLabel: null,
    );
  }

  factory BrandedSharePayload.publicBoxScore({
    required PublicLeagueSnapshot snapshot,
    required PublicGame game,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
    bool presentation = false,
  }) {
    if (!snapshot.canCreatePublishedArtifacts || !game.hasVersionedResult) {
      throw StateError(
        'A versioned, published final result is required for sharing.',
      );
    }
    if (game.playerLines.isEmpty) {
      throw ArgumentError.value(
        game.playerLines,
        'game.playerLines',
        'A box-score share requires published player lines.',
      );
    }
    final linesByPoints = game.playerLines.toList(growable: false)
      ..sort((a, b) {
        final points = (b.points ?? -1).compareTo(a.points ?? -1);
        return points != 0 ? points : a.displayName.compareTo(b.displayName);
      });
    PublicPlayerGameLine? topForTeam(String? teamId) {
      if (teamId == null) return null;
      for (final line in linesByPoints) {
        if (line.teamId == teamId) return line;
      }
      return null;
    }

    final leaders = <PublicPlayerGameLine>[
      ?topForTeam(game.homeTeamId),
      ?topForTeam(game.awayTeamId),
    ];
    for (final line in linesByPoints) {
      if (leaders.length >= 2) break;
      if (leaders.every((leader) => leader.playerId != line.playerId)) {
        leaders.add(line);
      }
    }
    final leader = leaders.first;
    final leaderPoints = leader.points == null ? 'Unknown' : '${leader.points}';
    final periodLine = game.periodScores.isEmpty
        ? null
        : game.periodScores
              .map(
                (score) =>
                    '${score.period}: ${score.homeScore}-${score.awayScore}',
              )
              .join(' · ');
    final performerLines = leaders
        .map((line) {
          return '${line.displayName} · ${line.points ?? 'Unknown'} PTS · ${line.rebounds ?? 'Unknown'} REB · ${line.assists ?? 'Unknown'} AST';
        })
        .toList(growable: false);
    final detail = [?periodLine, ...performerLines].join('\n');
    final textPerformerLines = leaders
        .map((line) {
          final team = _publicTeam(snapshot, line.teamId);
          return '${line.displayName} · ${team?.name ?? 'Team unavailable'} · ${line.points ?? 'Unknown'} PTS · ${line.rebounds ?? 'Unknown'} REB · ${line.assists ?? 'Unknown'} AST';
        })
        .toList(growable: false);
    final textDetail = [?periodLine, ...textPerformerLines].join('\n');
    final homeName = game.homeTeamName ?? 'Home';
    final awayName = game.awayTeamName ?? 'Away';
    final homeTeam = _publicTeam(snapshot, game.homeTeamId);
    final awayTeam = _publicTeam(snapshot, game.awayTeamId);
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} published box score',
      sheetTitle: 'Share this box score',
      eyebrow: 'BOX SCORE',
      headline:
          '${leader.displayName} leads all scorers with $leaderPoints PTS',
      detail: detail,
      shareText: [
        if (presentation) 'Presentation statistics',
        '${game.title} box score',
        '',
        textDetail,
        '',
        ..._publishedFooter(snapshot, branding, canonicalUri),
      ].join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_publicGameFileSlug(game)}-box-score-${snapshot.version.shortLabel}.png',
      sourceLabel: presentation
          ? 'Presentation statistics'
          : 'Published box score',
      isDemonstration: presentation,
      versionLabel: null,
      divisionLabel: game.divisionId == null
          ? null
          : snapshot.divisionName(game.divisionId),
      periodScoreLine: periodLine,
      performerLines: performerLines,
      teams: [
        BrandedShareTeam(
          name: homeName,
          logoUrl: homeTeam?.logoUrl,
          score: game.homeScore,
        ),
        BrandedShareTeam(
          name: awayName,
          logoUrl: awayTeam?.logoUrl,
          score: game.awayScore,
        ),
      ],
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
      sheetTitle: 'Share these leaders',
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
    final period = snapshot
        .leagueForDivision(leaderboard.divisionId)
        .seasonLabel;
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
      if (period != null) '$period · Per-game averages',
      '',
      ...leaderboard.rankings
          .take(25)
          .indexed
          .map(
            (item) =>
                '${item.$1 + 1}. ${item.$2.displayName} (${item.$2.teamName}) - ${_publicMetric(item.$2.value)}',
          ),
      '',
      ..._publishedFooter(snapshot, branding, canonicalUri),
    ];
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} $label leaders',
      sheetTitle: 'Share these leaders',
      eyebrow: period == null ? 'SEASON LEADERS' : 'FIRST-ROUND LEADERS',
      divisionLabel: period,
      headline:
          '${leader.displayName} leads with ${_publicMetric(leader.value)} $label',
      detail: detail,
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(leaderboard.category)}-${snapshot.version.shortLabel}.png',
      sourceLabel: period == null
          ? 'Published league statistics'
          : '$period · Per-game averages',
      versionLabel: null,
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
      sheetTitle: 'Share this player spotlight',
      eyebrow: 'PLAYER SPOTLIGHT',
      headline: stats.playerName,
      teams: [BrandedShareTeam(name: teamName)],
      spotlightStats: {
        'GP': '${stats.gamesPlayed}',
        'PPG': stats.ppg.toStringAsFixed(1),
        'RPG': stats.rpg.toStringAsFixed(1),
        'APG': stats.apg.toStringAsFixed(1),
        'SPG': stats.spg.toStringAsFixed(1),
        'BPG': stats.bpg.toStringAsFixed(1),
      },
      detail: '$teamName · ${stats.gamesPlayed} GP\n${statLine.join(' · ')}',
      shareText: lines.join('\n'),
      fileName:
          '${_slug(branding.shortName)}-${_slug(stats.playerName)}-stats.png',
    );
  }

  factory BrandedSharePayload.publicPlayerComparison({
    required PublicLeagueSnapshot snapshot,
    required PublicPlayerDetail first,
    required PublicPlayerDetail second,
    required AssociationBrandingModel branding,
  }) {
    _requirePublishedSnapshot(snapshot);
    _requirePublicIdentityEpoch(snapshot);
    if (first.playerId == second.playerId ||
        first.categories.isEmpty ||
        second.categories.isEmpty) {
      throw ArgumentError('Choose two different published players.');
    }
    String metric(PublicPlayerDetail player, String category) {
      final entry = player.categories
          .where((entry) => entry.category.toLowerCase() == category)
          .firstOrNull;
      return entry?.value.value?.toStringAsFixed(1) ?? 'N/A';
    }

    final rows = <(String, String, String)>[
      (
        'GP',
        '${first.categories.first.value.gamesPlayed ?? 'N/A'}',
        '${second.categories.first.value.gamesPlayed ?? 'N/A'}',
      ),
      for (final category in ['ppg', 'rpg', 'apg', 'spg', 'bpg'])
        (
          category.toUpperCase(),
          metric(first, category),
          metric(second, category),
        ),
    ];
    final leagueA = snapshot.leagueForDivision(
      first.categories.first.divisionId,
    );
    final leagueB = snapshot.leagueForDivision(
      second.categories.first.divisionId,
    );
    final periodA = leagueA.seasonLabel ?? snapshot.seasonName;
    final periodB = leagueB.seasonLabel ?? snapshot.seasonName;
    final period = periodA == periodB ? periodA : '$periodA / $periodB';
    return BrandedSharePayload(
      title: '${first.displayName} vs ${second.displayName}',
      sheetTitle: 'Share this player comparison',
      eyebrow: 'PLAYER COMPARISON',
      headline: '${first.displayName} vs ${second.displayName}',
      detail: '${first.teamName} · ${second.teamName}',
      divisionLabel: period,
      sourceLabel: 'Per-game comparison · GP = appearances',
      comparisonRows: rows,
      teams: [
        BrandedShareTeam(
          name: first.displayName,
          logoUrl: _publicTeam(
            snapshot,
            first.categories.first.value.teamId,
          )?.logoUrl,
        ),
        BrandedShareTeam(
          name: second.displayName,
          logoUrl: _publicTeam(
            snapshot,
            second.categories.first.value.teamId,
          )?.logoUrl,
        ),
      ],
      shareText: [
        '${first.displayName} (${first.teamName}) vs ${second.displayName} (${second.teamName})',
        '$period · Per-game comparison',
        for (final row in rows) '${row.$1}: ${row.$2} vs ${row.$3}',
        ..._publishedFooter(snapshot, branding, null),
      ].join('\n'),
      fileName:
          '${_slug(first.playerId)}-vs-${_slug(second.playerId)}-${snapshot.version.shortLabel}.png',
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
    final period = snapshot
        .leagueForDivision(player.categories.first.divisionId)
        .seasonLabel;
    final statLine = player.categories
        .map(
          (entry) =>
              '${_publicMetric(entry.value.value)} ${_categoryLabel(entry.category)}${period == null ? ' (${snapshot.divisionName(entry.divisionId)})' : ''}',
        )
        .toList(growable: false);
    final gamesPlayed = player.categories.first.value.gamesPlayed;
    final team = _publicTeam(snapshot, player.categories.first.value.teamId);
    final lines = <String>[
      player.displayName,
      if (period != null) '$period · Historical cumulative statistics',
      '${player.teamName} · ${_publicGamesPlayed(gamesPlayed)}',
      '',
      statLine.join(' · '),
      '',
      ..._publishedFooter(snapshot, branding, canonicalUri),
    ];
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} player stats',
      sheetTitle: 'Share this player spotlight',
      eyebrow: 'PLAYER SPOTLIGHT',
      divisionLabel: period,
      headline: player.displayName,
      spotlightStats: {
        'GP': gamesPlayed?.toString() ?? 'N/A',
        for (final entry in player.categories)
          _categoryLabel(entry.category):
              entry.value.value?.toStringAsFixed(1) ?? 'N/A',
      },
      detail:
          '${player.teamName} · ${_publicGamesPlayed(gamesPlayed)}\n${statLine.join(' · ')}',
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(player.playerId)}-${snapshot.version.shortLabel}.png',
      sourceLabel: period == null
          ? 'Published league statistics'
          : '$period · Per-game averages',
      versionLabel: null,
      teams: [BrandedShareTeam(name: player.teamName, logoUrl: team?.logoUrl)],
    );
  }

  factory BrandedSharePayload.publicTeam({
    required PublicLeagueSnapshot snapshot,
    required PublicTeamDetail team,
    required AssociationBrandingModel branding,
    Uri? canonicalUri,
  }) {
    _requirePublishedSnapshot(snapshot);
    final standing = team.standing;
    if (standing == null) {
      throw ArgumentError.value(
        standing,
        'team.standing',
        'A team-stat share requires a published standing.',
      );
    }
    final divisionName = snapshot.divisionName(team.team.divisionId);
    final record = standing.wins == null || standing.losses == null
        ? 'Record unknown'
        : '${standing.wins}-${standing.losses}';
    final rank = switch (standing.rankStatus) {
      PublicRankStatus.ranked => 'Rank ${standing.rank ?? 'unknown'}',
      PublicRankStatus.tied => 'Tied at ${standing.rank ?? 'unknown'}',
      PublicRankStatus.unresolved => 'Rank unresolved',
    };
    final detail = [
      '$divisionName · $record · $rank',
      '${standing.gamesPlayed ?? 'Unknown'} GP · ${standing.pointsFor ?? 'Unknown'} PF · ${standing.pointsAgainst ?? 'Unknown'} PA',
    ].join('\n');
    return BrandedSharePayload(
      title: '${snapshot.leagueShortName} team stats',
      sheetTitle: 'Share this team snapshot',
      eyebrow: 'TEAM SNAPSHOT',
      headline: team.team.name,
      detail: detail,
      shareText: [
        team.team.name,
        detail,
        '',
        ..._publishedFooter(snapshot, branding, canonicalUri),
      ].join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(team.team.name)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published team statistics',
      versionLabel: null,
      teams: [
        BrandedShareTeam(name: team.team.name, logoUrl: team.team.logoUrl),
      ],
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
      sheetTitle: 'Share these standings',
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
      sheetTitle: 'Share these standings',
      eyebrow: 'LEAGUE STANDINGS',
      headline: headline,
      detail: detail,
      shareText: lines.join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(scope)}-${snapshot.version.shortLabel}.png',
      sourceLabel: 'Published league statistics',
      versionLabel: null,
    );
  }

  factory BrandedSharePayload.legacyPublicStandings({
    required PublicLeagueSnapshot snapshot,
    required List<PublicStanding> standings,
    required AssociationBrandingModel branding,
    String? divisionName,
  }) {
    if (!isLegacyPublicTeamStandingsShareEligible(snapshot) ||
        standings.isEmpty ||
        standings.any((row) => !snapshot.standings.contains(row))) {
      throw StateError(
        'Only current legacy public team standings can be previewed.',
      );
    }
    final scope = divisionName?.trim().isNotEmpty == true
        ? divisionName!.trim()
        : snapshot.leagueShortName;
    final byDivision = <String?, List<PublicStanding>>{};
    for (final row in standings) {
      byDivision.putIfAbsent(row.divisionId, () => []).add(row);
    }
    final mixedDivisions = byDivision.length > 1;
    final rows = mixedDivisions
        ? byDivision.entries
              .take(3)
              .map(
                (entry) =>
                    '${snapshot.divisionName(entry.key)}: ${entry.value.first.teamName} · ${_publicRecord(entry.value.first)}',
              )
              .join('\n')
        : standings
              .take(3)
              .map(
                (row) =>
                    '${_legacyPreviewRank(row)} ${row.teamName} · ${_publicRecord(row)}',
              )
              .join('\n');
    final standingsLines = mixedDivisions
        ? [
            for (final entry in byDivision.entries) ...[
              '${snapshot.divisionName(entry.key)} division',
              ...entry.value.map(
                (row) =>
                    '${_legacyPreviewRank(row)} ${row.teamName} ${_publicRecord(row)}',
              ),
              '',
            ],
          ]
        : standings
              .map(
                (row) =>
                    '${_legacyPreviewRank(row)} ${row.teamName} ${_publicRecord(row)}',
              )
              .toList(growable: false);
    return BrandedSharePayload(
      title: '$scope standings',
      sheetTitle: 'Share standings',
      eyebrow: 'LEAGUE STANDINGS',
      headline: mixedDivisions
          ? '$scope division overview'
          : '$scope standings',
      detail: rows,
      shareText: [
        '$scope standings',
        '',
        ...standingsLines,
        '',
        ?_sponsorLine(branding),
        snapshot.leagueName,
        'Shared from HoopsConnect',
      ].join('\n'),
      fileName:
          '${_slug(snapshot.leagueShortName)}-${_slug(scope)}-standings.png',
      sourceLabel: 'League standings',
    );
  }
}

PublicTeam? _publicTeam(PublicLeagueSnapshot snapshot, String? teamId) {
  if (teamId == null) return null;
  for (final team in snapshot.teams) {
    if (team.teamId == teamId) return team;
  }
  return null;
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
  ?canonicalUri?.toString(),
  'Shared from HoopsConnect',
];

String _publicRankLabel(
  PublicStanding standing,
) => switch (standing.rankStatus) {
  PublicRankStatus.ranked => standing.rank == null ? '—' : '${standing.rank}.',
  PublicRankStatus.tied => standing.rank == null ? '—' : 'T${standing.rank}.',
  PublicRankStatus.unresolved => '—',
};

String _legacyPreviewRank(PublicStanding standing) =>
    standing.rankStatus == PublicRankStatus.unresolved || standing.rank == null
    ? 'Rank pending ·'
    : _publicRankLabel(standing);

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

String _publicGameFileSlug(PublicGame game) => _slug(
  '${game.homeTeamName ?? game.homeTeamId} vs '
  '${game.awayTeamName ?? game.awayTeamId} '
  '${game.startTime.toIso8601String().substring(0, 10)}',
);
