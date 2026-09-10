class PublicGame {
  final String gameId;
  final String title;
  final DateTime startTime;
  final String? venue;
  final String? divisionId;
  final String? homeTeamName;
  final String? awayTeamName;
  final int? homeScore;
  final int? awayScore;
  final bool isFinal;

  const PublicGame({
    required this.gameId,
    required this.title,
    required this.startTime,
    this.venue,
    this.divisionId,
    this.homeTeamName,
    this.awayTeamName,
    this.homeScore,
    this.awayScore,
    required this.isFinal,
  });

  factory PublicGame.fromMap(Map<String, dynamic> map) => PublicGame(
    gameId: map['gameId'] as String? ?? '',
    title: map['title'] as String? ?? 'Basketball game',
    startTime: DateTime.parse(map['startTime'] as String),
    venue: map['venue'] as String?,
    divisionId: map['divisionId'] as String?,
    homeTeamName: map['homeTeamName'] as String?,
    awayTeamName: map['awayTeamName'] as String?,
    homeScore: (map['homeScore'] as num?)?.toInt(),
    awayScore: (map['awayScore'] as num?)?.toInt(),
    isFinal: map['status'] == 'final',
  );
}

class PublicStanding {
  final String teamName;
  final int wins;
  final int losses;
  final double pct;
  final int pointsFor;
  final int pointsAgainst;

  const PublicStanding({
    required this.teamName,
    required this.wins,
    required this.losses,
    required this.pct,
    required this.pointsFor,
    required this.pointsAgainst,
  });

  factory PublicStanding.fromMap(Map<String, dynamic> map) => PublicStanding(
    teamName: map['teamName'] as String? ?? 'Team',
    wins: (map['wins'] as num?)?.toInt() ?? 0,
    losses: (map['losses'] as num?)?.toInt() ?? 0,
    pct: (map['pct'] as num?)?.toDouble() ?? 0,
    pointsFor: (map['pointsFor'] as num?)?.toInt() ?? 0,
    pointsAgainst: (map['pointsAgainst'] as num?)?.toInt() ?? 0,
  );
}

class PublicLeader {
  final String displayName;
  final String teamName;
  final double value;
  final int gamesPlayed;

  const PublicLeader({
    required this.displayName,
    required this.teamName,
    required this.value,
    required this.gamesPlayed,
  });

  factory PublicLeader.fromMap(Map<String, dynamic> map) => PublicLeader(
    displayName: map['displayName'] as String? ?? 'Player',
    teamName: map['teamName'] as String? ?? 'Team',
    value: (map['value'] as num?)?.toDouble() ?? 0,
    gamesPlayed: (map['gamesPlayed'] as num?)?.toInt() ?? 0,
  );
}

class PublicLeaderboard {
  final String category;
  final List<PublicLeader> rankings;

  const PublicLeaderboard({required this.category, required this.rankings});

  factory PublicLeaderboard.fromMap(Map<String, dynamic> map) =>
      PublicLeaderboard(
        category: map['category'] as String? ?? '',
        rankings: (map['rankings'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PublicLeader.fromMap)
            .toList(),
      );
}

class PublicLeagueSnapshot {
  final String leagueName;
  final String leagueShortName;
  final String seasonId;
  final DateTime generatedAt;
  final List<PublicGame> schedule;
  final List<PublicStanding> standings;
  final List<PublicLeaderboard> leaderboards;

  const PublicLeagueSnapshot({
    required this.leagueName,
    required this.leagueShortName,
    required this.seasonId,
    required this.generatedAt,
    required this.schedule,
    required this.standings,
    required this.leaderboards,
  });

  factory PublicLeagueSnapshot.fromMap(Map<String, dynamic> map) {
    final league = Map<String, dynamic>.from(
      map['league'] as Map? ?? const <String, dynamic>{},
    );
    return PublicLeagueSnapshot(
      leagueName: league['name'] as String? ?? 'Jamaica Basketball Association',
      leagueShortName: league['shortName'] as String? ?? 'JBA',
      seasonId: map['seasonId'] as String? ?? '',
      generatedAt:
          DateTime.tryParse(map['generatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      schedule: (map['schedule'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PublicGame.fromMap)
          .toList(),
      standings: (map['standings'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PublicStanding.fromMap)
          .toList(),
      leaderboards: (map['leaderboards'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PublicLeaderboard.fromMap)
          .toList(),
    );
  }
}
