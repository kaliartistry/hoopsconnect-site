enum PublicReleaseState { published, unavailable, retracted }

enum PublicGameStatus { scheduled, finalResult, postponed, canceled }

enum PublicRankStatus { ranked, tied, unresolved }

/// Version metadata for the compatibility public snapshot.
///
/// This is deliberately not the dormant official-stat v2 release contract.
/// [snapshotVersion] fingerprints one complete public snapshot so every view,
/// share, and export can identify the same source without reading private data.
class PublicSnapshotVersion {
  static final RegExp _sha256 = RegExp(r'^[a-f0-9]{64}$');

  final int schemaVersion;
  final String contractVersion;
  final String? snapshotVersion;
  final String verificationStatus;
  final PublicReleaseState state;
  final int? privacyEpoch;
  final DateTime generatedAt;

  const PublicSnapshotVersion({
    required this.schemaVersion,
    required this.contractVersion,
    required this.snapshotVersion,
    required this.verificationStatus,
    required this.state,
    required this.privacyEpoch,
    required this.generatedAt,
  });

  bool get isVersioned =>
      snapshotVersion != null && _sha256.hasMatch(snapshotVersion!);

  bool get isPublished => state == PublicReleaseState.published;

  bool get isCompatibilityArtifactEligible =>
      contractVersion == 'legacy-public-snapshot-v1.1' &&
      verificationStatus == 'legacyApproved';

  String get shortLabel =>
      isVersioned ? snapshotVersion!.substring(0, 12) : 'legacy-unversioned';

  factory PublicSnapshotVersion.fromMap(Map<String, dynamic> map) {
    final schemaVersion = _integer(map['schemaVersion']) ?? 1;
    if (schemaVersion != 1) {
      throw FormatException(
        'Unsupported public snapshot schemaVersion $schemaVersion.',
      );
    }

    final publication = _optionalMap(map['publication']);
    final generatedAt = _dateTime(
      publication['generatedAt'] ?? map['generatedAt'],
      'generatedAt',
    );
    final rawState = _optionalText(
      publication['state'] ?? map['publicationState'],
    );
    final published = map['published'];
    if (published != null && published is! bool) {
      throw const FormatException('Public published state must be boolean.');
    }
    final state = switch (rawState) {
      'retracted' => PublicReleaseState.retracted,
      'unavailable' || 'absent' => PublicReleaseState.unavailable,
      'published' =>
        published == false
            ? PublicReleaseState.unavailable
            : PublicReleaseState.published,
      null =>
        published == true
            ? PublicReleaseState.published
            : PublicReleaseState.unavailable,
      _ => throw FormatException(
        'Unknown public snapshot publication state: $rawState.',
      ),
    };

    final snapshotVersion = _optionalText(
      publication['snapshotVersion'] ?? map['snapshotVersion'],
    );
    if (snapshotVersion != null && !_sha256.hasMatch(snapshotVersion)) {
      throw const FormatException(
        'Public snapshotVersion must be a lowercase SHA-256 value.',
      );
    }
    final privacyEpoch = _integer(
      publication['privacyEpoch'] ?? map['privacyEpoch'],
    );
    if (privacyEpoch != null && privacyEpoch < 0) {
      throw const FormatException('Public privacyEpoch cannot be negative.');
    }

    final contractVersion =
        _optionalText(
          publication['contractVersion'] ?? map['contractVersion'],
        ) ??
        'legacy-public-snapshot-v1';
    if (contractVersion != 'legacy-public-snapshot-v1' &&
        contractVersion != 'legacy-public-snapshot-v1.1') {
      throw FormatException(
        'Unsupported public snapshot contractVersion $contractVersion.',
      );
    }

    return PublicSnapshotVersion(
      schemaVersion: schemaVersion,
      contractVersion: contractVersion,
      snapshotVersion: snapshotVersion,
      verificationStatus:
          _optionalText(
            publication['verificationStatus'] ?? map['certificationStatus'],
          ) ??
          'legacyUnverified',
      state: state,
      privacyEpoch: privacyEpoch,
      generatedAt: generatedAt,
    );
  }
}

class PublicDivision {
  final String divisionId;
  final String name;

  const PublicDivision({required this.divisionId, required this.name});

  factory PublicDivision.fromMap(Map<String, dynamic> map) => PublicDivision(
    divisionId: _requiredText(map['divisionId'], 'divisionId'),
    name: _requiredText(map['name'], 'division name'),
  );
}

class PublicTeam {
  final String teamId;
  final String name;
  final String? divisionId;

  const PublicTeam({required this.teamId, required this.name, this.divisionId});

  factory PublicTeam.fromMap(Map<String, dynamic> map) => PublicTeam(
    teamId: _requiredText(map['teamId'], 'teamId'),
    name: _requiredText(map['name'], 'team name'),
    divisionId: _optionalText(map['divisionId']),
  );
}

class PublicPeriodScore {
  final int period;
  final int homeScore;
  final int awayScore;

  const PublicPeriodScore({
    required this.period,
    required this.homeScore,
    required this.awayScore,
  });

  factory PublicPeriodScore.fromMap(Map<String, dynamic> map) {
    final period = _integer(map['period']);
    final homeScore = _integer(map['homeScore']);
    final awayScore = _integer(map['awayScore']);
    if (period == null ||
        period < 1 ||
        homeScore == null ||
        awayScore == null) {
      throw const FormatException('Invalid public period score.');
    }
    return PublicPeriodScore(
      period: period,
      homeScore: homeScore,
      awayScore: awayScore,
    );
  }
}

/// A field-whitelisted player line that has already crossed the public
/// projection boundary. Missing historical values remain null, never zero.
class PublicPlayerGameLine {
  final String playerId;
  final String displayName;
  final String teamId;
  final int? minutes;
  final int? points;
  final int? twoPointMade;
  final int? twoPointAttempted;
  final int? threePointMade;
  final int? threePointAttempted;
  final int? freeThrowMade;
  final int? freeThrowAttempted;
  final int? offensiveRebounds;
  final int? defensiveRebounds;
  final int? assists;
  final int? steals;
  final int? blocks;
  final int? turnovers;
  final int? fouls;

  const PublicPlayerGameLine({
    required this.playerId,
    required this.displayName,
    required this.teamId,
    this.minutes,
    this.points,
    this.twoPointMade,
    this.twoPointAttempted,
    this.threePointMade,
    this.threePointAttempted,
    this.freeThrowMade,
    this.freeThrowAttempted,
    this.offensiveRebounds,
    this.defensiveRebounds,
    this.assists,
    this.steals,
    this.blocks,
    this.turnovers,
    this.fouls,
  });

  int? get rebounds => offensiveRebounds == null || defensiveRebounds == null
      ? null
      : offensiveRebounds! + defensiveRebounds!;

  factory PublicPlayerGameLine.fromMap(Map<String, dynamic> map) =>
      PublicPlayerGameLine(
        playerId: _requiredText(map['playerId'], 'playerId'),
        displayName: _requiredText(map['displayName'], 'player displayName'),
        teamId: _requiredText(map['teamId'], 'player teamId'),
        minutes: _integer(map['minutes']),
        points: _integer(map['points']),
        twoPointMade: _integer(map['twoPointMade']),
        twoPointAttempted: _integer(map['twoPointAttempted']),
        threePointMade: _integer(map['threePointMade']),
        threePointAttempted: _integer(map['threePointAttempted']),
        freeThrowMade: _integer(map['freeThrowMade']),
        freeThrowAttempted: _integer(map['freeThrowAttempted']),
        offensiveRebounds: _integer(map['offensiveRebounds']),
        defensiveRebounds: _integer(map['defensiveRebounds']),
        assists: _integer(map['assists']),
        steals: _integer(map['steals']),
        blocks: _integer(map['blocks']),
        turnovers: _integer(map['turnovers']),
        fouls: _integer(map['fouls']),
      );
}

class PublicGame {
  static final RegExp _sha256 = RegExp(r'^[a-f0-9]{64}$');

  final String gameId;
  final String title;
  final DateTime startTime;
  final String? venue;
  final String? divisionId;
  final String? homeTeamId;
  final String? homeTeamName;
  final String? awayTeamId;
  final String? awayTeamName;
  final int? homeScore;
  final int? awayScore;
  final PublicGameStatus status;
  final String? resultVersion;
  final String? recap;
  final List<PublicPeriodScore> periodScores;
  final List<PublicPlayerGameLine> playerLines;

  const PublicGame({
    required this.gameId,
    required this.title,
    required this.startTime,
    this.venue,
    this.divisionId,
    this.homeTeamId,
    this.homeTeamName,
    this.awayTeamId,
    this.awayTeamName,
    this.homeScore,
    this.awayScore,
    required this.status,
    this.resultVersion,
    this.recap,
    this.periodScores = const [],
    this.playerLines = const [],
  });

  bool get isFinal => status == PublicGameStatus.finalResult;

  bool get hasVersionedResult =>
      isFinal && resultVersion != null && _sha256.hasMatch(resultVersion!);

  factory PublicGame.fromMap(
    Map<String, dynamic> map, {
    required bool requireResultVersion,
    required bool includePlayerIdentity,
  }) {
    final rawStatus = _requiredText(map['status'], 'game status');
    final status = switch (rawStatus) {
      'scheduled' => PublicGameStatus.scheduled,
      'final' => PublicGameStatus.finalResult,
      'postponed' => PublicGameStatus.postponed,
      'canceled' || 'cancelled' => PublicGameStatus.canceled,
      _ => throw FormatException('Unknown public game status: $rawStatus.'),
    };
    final homeScore = _integer(map['homeScore']);
    final awayScore = _integer(map['awayScore']);
    final resultVersion = _optionalText(map['resultVersion']);
    final recap = _optionalText(map['recap']);
    final rawPeriodScores = _mapList(map['periodScores'], 'periodScores');
    final rawPlayerLines = _mapList(map['playerLines'], 'playerLines');
    if (resultVersion != null &&
        !PublicSnapshotVersion._sha256.hasMatch(resultVersion)) {
      throw const FormatException(
        'Public resultVersion must be a lowercase SHA-256 value.',
      );
    }
    if (status == PublicGameStatus.finalResult &&
        (homeScore == null || awayScore == null)) {
      throw const FormatException('A final public game requires both scores.');
    }
    if (status == PublicGameStatus.finalResult &&
        requireResultVersion &&
        resultVersion == null) {
      throw const FormatException(
        'A versioned final public game requires resultVersion.',
      );
    }
    if (status != PublicGameStatus.finalResult &&
        (homeScore != null ||
            awayScore != null ||
            resultVersion != null ||
            recap != null ||
            rawPeriodScores.isNotEmpty ||
            rawPlayerLines.isNotEmpty)) {
      throw const FormatException(
        'A non-final public game cannot contain result fields.',
      );
    }

    return PublicGame(
      gameId: _requiredText(map['gameId'], 'gameId'),
      title: _requiredText(map['title'], 'game title'),
      startTime: _dateTime(map['startTime'], 'game startTime'),
      venue: _optionalText(map['venue']),
      divisionId: _optionalText(map['divisionId']),
      homeTeamId: _optionalText(map['homeTeamId']),
      homeTeamName: _optionalText(map['homeTeamName']),
      awayTeamId: _optionalText(map['awayTeamId']),
      awayTeamName: _optionalText(map['awayTeamName']),
      homeScore: homeScore,
      awayScore: awayScore,
      status: status,
      resultVersion: resultVersion,
      recap: recap,
      periodScores: List.unmodifiable(
        rawPeriodScores.map(PublicPeriodScore.fromMap),
      ),
      playerLines: includePlayerIdentity
          ? List.unmodifiable(rawPlayerLines.map(PublicPlayerGameLine.fromMap))
          : const [],
    );
  }
}

class PublicStanding {
  final String? teamId;
  final String teamName;
  final String? divisionId;
  final int? rank;
  final PublicRankStatus rankStatus;
  final int? wins;
  final int? losses;
  final double? pct;
  final int? pointsFor;
  final int? pointsAgainst;

  const PublicStanding({
    this.teamId,
    required this.teamName,
    this.divisionId,
    this.rank,
    this.rankStatus = PublicRankStatus.unresolved,
    required this.wins,
    required this.losses,
    required this.pct,
    required this.pointsFor,
    required this.pointsAgainst,
  });

  int? get gamesPlayed =>
      wins == null || losses == null ? null : wins! + losses!;

  factory PublicStanding.fromMap(Map<String, dynamic> map) {
    final parsedRank = _integer(map['rank']);
    final rank = parsedRank != null && parsedRank > 0 ? parsedRank : null;
    final rawRankStatus = _optionalText(map['rankStatus']);
    final rankStatus = switch (rawRankStatus) {
      'ranked' when rank != null => PublicRankStatus.ranked,
      'tied' when rank != null => PublicRankStatus.tied,
      'ranked' || 'tied' => PublicRankStatus.unresolved,
      'unresolved' || null => PublicRankStatus.unresolved,
      _ => throw FormatException(
        'Unknown public standing rankStatus: $rawRankStatus.',
      ),
    };
    return PublicStanding(
      teamId: _optionalText(map['teamId']),
      teamName: _requiredText(map['teamName'], 'standing teamName'),
      divisionId: _optionalText(map['divisionId']),
      rank: rank,
      rankStatus: rankStatus,
      wins: _integer(map['wins']),
      losses: _integer(map['losses']),
      pct: _number(map['pct']),
      pointsFor: _integer(map['pointsFor']),
      pointsAgainst: _integer(map['pointsAgainst']),
    );
  }
}

class PublicLeader {
  final String? playerId;
  final String displayName;
  final String? teamId;
  final String teamName;
  final String? divisionId;
  final double? value;
  final int? gamesPlayed;

  const PublicLeader({
    this.playerId,
    required this.displayName,
    this.teamId,
    required this.teamName,
    this.divisionId,
    required this.value,
    required this.gamesPlayed,
  });

  factory PublicLeader.fromMap(Map<String, dynamic> map) => PublicLeader(
    playerId: _optionalText(map['playerId']),
    displayName: _requiredText(map['displayName'], 'leader displayName'),
    teamId: _optionalText(map['teamId']),
    teamName: _requiredText(map['teamName'], 'leader teamName'),
    divisionId: _optionalText(map['divisionId']),
    value: _number(map['value']),
    gamesPlayed: _integer(map['gamesPlayed']),
  );
}

class PublicLeaderboard {
  static const categoryOrder = ['ppg', 'rpg', 'apg', 'spg', 'bpg'];

  final String category;
  final String? divisionId;
  final String? qualificationLabel;
  final List<PublicLeader> rankings;

  const PublicLeaderboard({
    required this.category,
    this.divisionId,
    this.qualificationLabel,
    required this.rankings,
  });

  String get categoryLabel => switch (category.toLowerCase()) {
    'ppg' => 'PTS',
    'rpg' => 'REB',
    'apg' => 'AST',
    'spg' => 'STL',
    'bpg' => 'BLK',
    _ => category.toUpperCase(),
  };

  factory PublicLeaderboard.fromMap(
    Map<String, dynamic> map, {
    required bool includePlayerIdentity,
  }) => PublicLeaderboard(
    category: _requiredText(map['category'], 'leaderboard category'),
    divisionId: _optionalText(map['divisionId']),
    qualificationLabel: _optionalText(map['qualificationLabel']),
    rankings: includePlayerIdentity
        ? List.unmodifiable(
            _mapList(map['rankings'], 'rankings').map(PublicLeader.fromMap),
          )
        : const [],
  );

  static int compare(PublicLeaderboard a, PublicLeaderboard b) {
    final aIndex = categoryOrder.indexOf(a.category.toLowerCase());
    final bIndex = categoryOrder.indexOf(b.category.toLowerCase());
    final normalizedA = aIndex < 0 ? categoryOrder.length : aIndex;
    final normalizedB = bIndex < 0 ? categoryOrder.length : bIndex;
    final categoryComparison = normalizedA.compareTo(normalizedB);
    if (categoryComparison != 0) return categoryComparison;
    return a.category.compareTo(b.category);
  }
}

class PublicGameDetail {
  final PublicGame game;
  final String divisionName;

  const PublicGameDetail({required this.game, required this.divisionName});
}

class PublicTeamDetail {
  final PublicTeam team;
  final PublicStanding? standing;
  final List<PublicGame> games;
  final List<PublicLeaderboard> leaderboards;

  const PublicTeamDetail({
    required this.team,
    required this.standing,
    required this.games,
    required this.leaderboards,
  });
}

class PublicPlayerDetail {
  final String playerId;
  final String displayName;
  final String teamName;
  final List<({String category, String? divisionId, PublicLeader value})>
  categories;

  const PublicPlayerDetail({
    required this.playerId,
    required this.displayName,
    required this.teamName,
    required this.categories,
  });
}

class PublicLeagueSnapshot {
  final String associationId;
  final String leagueName;
  final String leagueShortName;
  final String seasonId;
  final String seasonName;
  final String? standingsPolicyLabel;
  final PublicSnapshotVersion version;
  final List<PublicDivision> divisions;
  final List<PublicTeam> teams;
  final List<PublicGame> schedule;
  final List<PublicStanding> standings;
  final List<PublicLeaderboard> leaderboards;

  const PublicLeagueSnapshot({
    this.associationId = 'jba',
    required this.leagueName,
    required this.leagueShortName,
    required this.seasonId,
    String? seasonName,
    this.standingsPolicyLabel,
    required this.version,
    this.divisions = const [],
    this.teams = const [],
    required this.schedule,
    required this.standings,
    required this.leaderboards,
  }) : seasonName = seasonName ?? seasonId;

  DateTime get generatedAt => version.generatedAt;

  bool get canCreatePublishedArtifacts =>
      version.isPublished &&
      version.isVersioned &&
      version.isCompatibilityArtifactEligible;

  factory PublicLeagueSnapshot.fromMap(Map<String, dynamic> map) {
    final version = PublicSnapshotVersion.fromMap(map);
    final league = _optionalMap(map['league']);
    final season = _optionalMap(map['season']);

    if (!version.isPublished) {
      return PublicLeagueSnapshot(
        associationId: _optionalText(map['associationId']) ?? 'jba',
        leagueName:
            _optionalText(league['name']) ?? 'Jamaica Basketball Association',
        leagueShortName: _optionalText(league['shortName']) ?? 'JBA',
        seasonId: _optionalText(season['seasonId'] ?? map['seasonId']) ?? '',
        seasonName:
            _optionalText(season['name']) ??
            _optionalText(season['seasonId'] ?? map['seasonId']) ??
            'Season unavailable',
        version: version,
        schedule: const [],
        standings: const [],
        leaderboards: const [],
      );
    }

    final rawSchedule = _mapList(map['schedule'], 'schedule');
    final rawLeaderboards = _mapList(map['leaderboards'], 'leaderboards');
    final hasPublishedPlayerIdentity =
        rawSchedule.any(
          (game) => _mapList(game['playerLines'], 'playerLines').isNotEmpty,
        ) ||
        rawLeaderboards.any(
          (board) => _mapList(board['rankings'], 'rankings').isNotEmpty,
        );
    if (version.contractVersion == 'legacy-public-snapshot-v1.1' &&
        version.privacyEpoch == null &&
        hasPublishedPlayerIdentity) {
      throw const FormatException(
        'Versioned public player identity requires a privacyEpoch.',
      );
    }
    final includePlayerIdentity =
        version.contractVersion == 'legacy-public-snapshot-v1.1' &&
        version.privacyEpoch != null;

    final schedule = rawSchedule
        .map(
          (game) => PublicGame.fromMap(
            game,
            requireResultVersion: version.isVersioned,
            includePlayerIdentity: includePlayerIdentity,
          ),
        )
        .toList(growable: false);
    final standings = _mapList(
      map['standings'],
      'standings',
    ).map(PublicStanding.fromMap).toList(growable: false);
    final leaderboards =
        rawLeaderboards
            .map(
              (board) => PublicLeaderboard.fromMap(
                board,
                includePlayerIdentity: includePlayerIdentity,
              ),
            )
            .toList(growable: true)
          ..sort(PublicLeaderboard.compare);

    final explicitTeams = _mapList(
      map['teams'],
      'teams',
    ).map(PublicTeam.fromMap).toList(growable: true);
    final teamById = <String, PublicTeam>{
      for (final team in explicitTeams) team.teamId: team,
    };
    for (final game in schedule) {
      if (game.homeTeamId != null && game.homeTeamName != null) {
        teamById.putIfAbsent(
          game.homeTeamId!,
          () => PublicTeam(
            teamId: game.homeTeamId!,
            name: game.homeTeamName!,
            divisionId: game.divisionId,
          ),
        );
      }
      if (game.awayTeamId != null && game.awayTeamName != null) {
        teamById.putIfAbsent(
          game.awayTeamId!,
          () => PublicTeam(
            teamId: game.awayTeamId!,
            name: game.awayTeamName!,
            divisionId: game.divisionId,
          ),
        );
      }
    }
    for (final standing in standings) {
      if (standing.teamId != null) {
        teamById.putIfAbsent(
          standing.teamId!,
          () => PublicTeam(
            teamId: standing.teamId!,
            name: standing.teamName,
            divisionId: standing.divisionId,
          ),
        );
      }
    }

    return PublicLeagueSnapshot(
      associationId: _optionalText(map['associationId']) ?? 'jba',
      leagueName:
          _optionalText(league['name']) ?? 'Jamaica Basketball Association',
      leagueShortName: _optionalText(league['shortName']) ?? 'JBA',
      seasonId: _requiredText(
        season['seasonId'] ?? map['seasonId'],
        'seasonId',
      ),
      seasonName:
          _optionalText(season['name']) ??
          _requiredText(season['seasonId'] ?? map['seasonId'], 'seasonId'),
      standingsPolicyLabel: _optionalText(map['standingsPolicyLabel']),
      version: version,
      divisions: List.unmodifiable(
        _mapList(map['divisions'], 'divisions').map(PublicDivision.fromMap),
      ),
      teams: List.unmodifiable(
        teamById.values.toList(growable: false)
          ..sort((a, b) => a.name.compareTo(b.name)),
      ),
      schedule: List.unmodifiable(schedule),
      standings: List.unmodifiable(standings),
      leaderboards: List.unmodifiable(leaderboards),
    );
  }

  String divisionName(String? divisionId) {
    if (divisionId == null) return 'All divisions';
    for (final division in divisions) {
      if (division.divisionId == divisionId) return division.name;
    }
    return 'Division unavailable';
  }

  PublicGameDetail? gameDetail(String gameId) {
    for (final game in schedule) {
      if (game.gameId == gameId) {
        return PublicGameDetail(
          game: game,
          divisionName: divisionName(game.divisionId),
        );
      }
    }
    return null;
  }

  PublicTeamDetail? teamDetail(String teamId) {
    PublicTeam? matchingTeam;
    for (final team in teams) {
      if (team.teamId == teamId) {
        matchingTeam = team;
        break;
      }
    }
    if (matchingTeam == null) return null;

    PublicStanding? matchingStanding;
    for (final standing in standings) {
      if (standing.teamId == teamId) {
        matchingStanding = standing;
        break;
      }
    }
    final games =
        schedule
            .where(
              (game) => game.homeTeamId == teamId || game.awayTeamId == teamId,
            )
            .toList(growable: false)
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    final boards = leaderboards
        .where((board) => board.rankings.any((entry) => entry.teamId == teamId))
        .toList(growable: false);
    return PublicTeamDetail(
      team: matchingTeam,
      standing: matchingStanding,
      games: List.unmodifiable(games),
      leaderboards: List.unmodifiable(boards),
    );
  }

  PublicPlayerDetail? playerDetail(String playerId) {
    final categories =
        <({String category, String? divisionId, PublicLeader value})>[];
    for (final board in leaderboards) {
      for (final entry in board.rankings) {
        if (entry.playerId == playerId) {
          categories.add((
            category: board.category,
            divisionId: board.divisionId ?? entry.divisionId,
            value: entry,
          ));
          break;
        }
      }
    }
    if (categories.isEmpty) return null;
    final first = categories.first.value;
    return PublicPlayerDetail(
      playerId: playerId,
      displayName: first.displayName,
      teamName: first.teamName,
      categories: List.unmodifiable(categories),
    );
  }
}

Map<String, dynamic> _optionalMap(Object? value) {
  if (value == null) return const <String, dynamic>{};
  if (value is! Map) throw const FormatException('Expected a map value.');
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _mapList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List) throw FormatException('$field must be a list.');
  return value
      .map((entry) {
        if (entry is! Map) {
          throw FormatException('$field contains a non-map row.');
        }
        return Map<String, dynamic>.from(entry);
      })
      .toList(growable: false);
}

String _requiredText(Object? value, String field) {
  final parsed = _optionalText(value);
  if (parsed == null) throw FormatException('$field is required.');
  return parsed;
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('Expected text value.');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _dateTime(Object? value, String field) {
  final text = _requiredText(value, field);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) throw FormatException('$field must be an ISO timestamp.');
  return parsed;
}

int? _integer(Object? value) {
  if (value == null) return null;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw const FormatException('Expected an integer value.');
}

double? _number(Object? value) {
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw const FormatException('Expected a finite number.');
}
