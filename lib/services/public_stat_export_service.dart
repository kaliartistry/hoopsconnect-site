import '../models/public_league_snapshot.dart';

class PublicExportGrant {
  final bool canExportGame;
  final bool canExportSeason;
  final bool canExportPlayerIdentity;

  const PublicExportGrant({
    required this.canExportGame,
    required this.canExportSeason,
    required this.canExportPlayerIdentity,
  });

  static const none = PublicExportGrant(
    canExportGame: false,
    canExportSeason: false,
    canExportPlayerIdentity: false,
  );

  static const media = PublicExportGrant(
    canExportGame: true,
    canExportSeason: true,
    canExportPlayerIdentity: true,
  );
}

class PublicExportDenied implements Exception {
  final String message;

  const PublicExportDenied(this.message);

  @override
  String toString() => message;
}

class PublicExportUnavailable implements Exception {
  final String message;

  const PublicExportUnavailable(this.message);

  @override
  String toString() => message;
}

/// Builds version-bound CSV and text artifacts exclusively from the public DTO.
/// Private repositories and raw Firestore records are intentionally absent.
class PublicStatExportService {
  static const _headers = [
    'record_type',
    'snapshot_version',
    'result_version',
    'season_id',
    'division_id',
    'game_id',
    'game_status',
    'start_time',
    'venue',
    'home_team',
    'away_team',
    'home_score',
    'away_score',
    'period',
    'player_id',
    'player_name',
    'team_id',
    'minutes',
    'points',
    '2pm',
    '2pa',
    '3pm',
    '3pa',
    'ftm',
    'fta',
    'oreb',
    'dreb',
    'reb',
    'assists',
    'steals',
    'blocks',
    'turnovers',
    'fouls',
    'category',
    'value',
    'games_played',
    'rank',
    'wins',
    'losses',
    'winning_percentage',
    'points_for',
    'points_against',
    'rank_status',
    'ranking_policy',
    'qualification_label',
  ];

  static String gameCsv({
    required PublicLeagueSnapshot snapshot,
    required String gameId,
    required PublicExportGrant grant,
  }) {
    if (!grant.canExportGame) {
      throw const PublicExportDenied(
        'Your account cannot export game statistics.',
      );
    }
    _requireVersionedSnapshot(snapshot);
    final detail = snapshot.gameDetail(gameId);
    if (detail == null) {
      throw const PublicExportUnavailable(
        'This game is not in the current public snapshot.',
      );
    }
    if (!detail.game.hasVersionedResult) {
      throw const PublicExportUnavailable(
        'A published final result is required before export.',
      );
    }

    return _encode([
      _headers,
      ..._gameRows(snapshot, detail.game, grant: grant),
    ]);
  }

  static String seasonCsv({
    required PublicLeagueSnapshot snapshot,
    required PublicExportGrant grant,
  }) {
    if (!grant.canExportSeason) {
      throw const PublicExportDenied(
        'Your account cannot export season statistics.',
      );
    }
    _requireVersionedSnapshot(snapshot);
    final rows = <List<Object?>>[];
    for (final game in snapshot.schedule) {
      if (game.isFinal && !game.hasVersionedResult) {
        throw const PublicExportUnavailable(
          'Every final game requires a versioned public result before season export.',
        );
      }
      rows.addAll(_gameRows(snapshot, game, grant: grant));
    }
    for (final standing in snapshot.standings) {
      rows.add(
        _row(
          recordType: 'standing',
          snapshot: snapshot,
          divisionId: standing.divisionId,
          homeTeam: standing.teamName,
          teamId: standing.teamId,
          gamesPlayed: standing.gamesPlayed,
          rank: standing.rank,
          wins: standing.wins,
          losses: standing.losses,
          winningPercentage: standing.pct,
          pointsFor: standing.pointsFor,
          pointsAgainst: standing.pointsAgainst,
          rankStatus: standing.rankStatus.name,
          rankingPolicy: snapshot.standingsPolicyLabel,
        ),
      );
    }
    for (final board in snapshot.leaderboards) {
      for (final leader in board.rankings) {
        rows.add(
          _row(
            recordType: 'leader',
            snapshot: snapshot,
            divisionId: board.divisionId ?? leader.divisionId,
            playerId:
                grant.canExportPlayerIdentity &&
                    snapshot.version.privacyEpoch != null
                ? leader.playerId
                : null,
            playerName:
                grant.canExportPlayerIdentity &&
                    snapshot.version.privacyEpoch != null
                ? leader.displayName
                : null,
            homeTeam: leader.teamName,
            teamId: leader.teamId,
            category: board.category,
            value: leader.value,
            gamesPlayed: leader.gamesPlayed,
            qualificationLabel: board.qualificationLabel,
          ),
        );
      }
    }
    return _encode([_headers, ...rows]);
  }

  static String gameSummaryText({
    required PublicLeagueSnapshot snapshot,
    required String gameId,
  }) {
    _requireVersionedSnapshot(snapshot);
    final game = snapshot.gameDetail(gameId)?.game;
    if (game == null || !game.hasVersionedResult) {
      throw const PublicExportUnavailable(
        'A published final result is required before sharing.',
      );
    }
    final buffer = StringBuffer()
      ..writeln('${game.homeTeamName ?? 'Home'} ${game.homeScore}')
      ..writeln('${game.awayTeamName ?? 'Away'} ${game.awayScore}')
      ..writeln('Final')
      ..writeln();
    if (game.recap != null) {
      buffer
        ..writeln(game.recap)
        ..writeln();
    }
    buffer
      ..writeln('Season: ${snapshot.seasonName}')
      ..writeln('Publication: ${snapshot.version.snapshotVersion}')
      ..writeln('Result: ${game.resultVersion}')
      ..write('Shared from HoopsConnect');
    return buffer.toString();
  }

  /// Prefixes text that spreadsheet applications may interpret as a formula.
  /// Quoting a CSV field alone does not stop formula execution.
  static String escapeSpreadsheetText(String value) {
    if (value.isEmpty || value.startsWith("'")) return value;
    var firstMeaningful = 0;
    while (firstMeaningful < value.length) {
      final code = value.codeUnitAt(firstMeaningful);
      final ignorablePrefix =
          code <= 0x20 ||
          code == 0x7f ||
          code == 0xa0 ||
          code == 0x200b ||
          code == 0xfeff;
      if (!ignorablePrefix) break;
      firstMeaningful++;
    }
    final trimmed = value.substring(firstMeaningful);
    final startsWithFormula =
        trimmed.startsWith('=') ||
        trimmed.startsWith('+') ||
        trimmed.startsWith('-') ||
        trimmed.startsWith('@');
    final firstCodeUnit = value.codeUnitAt(0);
    final startsWithControl = firstCodeUnit <= 0x1f || firstCodeUnit == 0x7f;
    return startsWithFormula || startsWithControl ? "'$value" : value;
  }

  static void _requireVersionedSnapshot(PublicLeagueSnapshot snapshot) {
    if (!snapshot.version.isPublished) {
      throw const PublicExportUnavailable(
        'The public release is unavailable or has been withdrawn.',
      );
    }
    if (!snapshot.version.isVersioned) {
      throw const PublicExportUnavailable(
        'The public release is not versioned, so an export cannot be verified.',
      );
    }
    if (!snapshot.version.isCompatibilityArtifactEligible) {
      throw const PublicExportUnavailable(
        'The public release has not passed the compatibility publication check.',
      );
    }
  }

  static Iterable<List<Object?>> _gameRows(
    PublicLeagueSnapshot snapshot,
    PublicGame game, {
    required PublicExportGrant grant,
  }) sync* {
    yield _row(
      recordType: game.isFinal ? 'game_result' : 'scheduled_game',
      snapshot: snapshot,
      resultVersion: game.resultVersion,
      divisionId: game.divisionId,
      gameId: game.gameId,
      gameStatus: _gameStatus(game.status),
      startTime: game.startTime.toUtc().toIso8601String(),
      venue: game.venue,
      homeTeam: game.homeTeamName,
      awayTeam: game.awayTeamName,
      homeScore: game.homeScore,
      awayScore: game.awayScore,
    );
    for (final period in game.periodScores) {
      yield _row(
        recordType: 'period',
        snapshot: snapshot,
        resultVersion: game.resultVersion,
        divisionId: game.divisionId,
        gameId: game.gameId,
        period: period.period,
        homeScore: period.homeScore,
        awayScore: period.awayScore,
      );
    }
    if (!game.isFinal ||
        !grant.canExportPlayerIdentity ||
        snapshot.version.privacyEpoch == null) {
      return;
    }
    for (final player in game.playerLines) {
      yield _row(
        recordType: 'player_line',
        snapshot: snapshot,
        resultVersion: game.resultVersion,
        divisionId: game.divisionId,
        gameId: game.gameId,
        playerId: player.playerId,
        playerName: player.displayName,
        teamId: player.teamId,
        minutes: player.minutes,
        points: player.points,
        twoPointMade: player.twoPointMade,
        twoPointAttempted: player.twoPointAttempted,
        threePointMade: player.threePointMade,
        threePointAttempted: player.threePointAttempted,
        freeThrowMade: player.freeThrowMade,
        freeThrowAttempted: player.freeThrowAttempted,
        offensiveRebounds: player.offensiveRebounds,
        defensiveRebounds: player.defensiveRebounds,
        rebounds: player.rebounds,
        assists: player.assists,
        steals: player.steals,
        blocks: player.blocks,
        turnovers: player.turnovers,
        fouls: player.fouls,
      );
    }
  }

  static List<Object?> _row({
    required String recordType,
    required PublicLeagueSnapshot snapshot,
    String? resultVersion,
    String? divisionId,
    String? gameId,
    String? gameStatus,
    String? startTime,
    String? venue,
    String? homeTeam,
    String? awayTeam,
    int? homeScore,
    int? awayScore,
    int? period,
    String? playerId,
    String? playerName,
    String? teamId,
    int? minutes,
    int? points,
    int? twoPointMade,
    int? twoPointAttempted,
    int? threePointMade,
    int? threePointAttempted,
    int? freeThrowMade,
    int? freeThrowAttempted,
    int? offensiveRebounds,
    int? defensiveRebounds,
    int? rebounds,
    int? assists,
    int? steals,
    int? blocks,
    int? turnovers,
    int? fouls,
    String? category,
    double? value,
    int? gamesPlayed,
    int? rank,
    int? wins,
    int? losses,
    double? winningPercentage,
    int? pointsFor,
    int? pointsAgainst,
    String? rankStatus,
    String? rankingPolicy,
    String? qualificationLabel,
  }) => [
    recordType,
    snapshot.version.snapshotVersion,
    resultVersion,
    snapshot.seasonId,
    divisionId,
    gameId,
    gameStatus,
    startTime,
    venue,
    homeTeam,
    awayTeam,
    homeScore,
    awayScore,
    period,
    playerId,
    playerName,
    teamId,
    minutes,
    points,
    twoPointMade,
    twoPointAttempted,
    threePointMade,
    threePointAttempted,
    freeThrowMade,
    freeThrowAttempted,
    offensiveRebounds,
    defensiveRebounds,
    rebounds,
    assists,
    steals,
    blocks,
    turnovers,
    fouls,
    category,
    value,
    gamesPlayed,
    rank,
    wins,
    losses,
    winningPercentage,
    pointsFor,
    pointsAgainst,
    rankStatus,
    rankingPolicy,
    qualificationLabel,
  ];

  static String _encode(List<List<Object?>> rows) {
    final body = rows.map((row) => row.map(_cell).join(',')).join('\r\n');
    return '$body\r\n';
  }

  static String _cell(Object? value) {
    if (value == null) return 'Unknown';
    if (value is num) return value.toString();
    final safe = escapeSpreadsheetText(value.toString());
    return '"${safe.replaceAll('"', '""')}"';
  }

  static String _gameStatus(PublicGameStatus status) => switch (status) {
    PublicGameStatus.finalResult => 'final',
    PublicGameStatus.scheduled => 'scheduled',
    PublicGameStatus.postponed => 'postponed',
    PublicGameStatus.canceled => 'canceled',
  };
}
