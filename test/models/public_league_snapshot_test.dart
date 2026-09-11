import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';

void main() {
  test('parses the certified public snapshot used by guest mode', () {
    final snapshot = PublicLeagueSnapshot.fromMap({
      'published': true,
      'league': {'name': 'Jamaica Basketball Association', 'shortName': 'JBA'},
      'seasonId': 'season-1',
      'generatedAt': '2026-09-10T21:00:00.000Z',
      'schedule': [
        {
          'gameId': 'game-1',
          'title': 'Home vs Away',
          'startTime': '2026-09-10T20:00:00.000Z',
          'status': 'final',
          'homeTeamName': 'Home',
          'awayTeamName': 'Away',
          'homeScore': 82,
          'awayScore': 79,
        },
      ],
      'standings': [
        {
          'teamName': 'Home',
          'wins': 1,
          'losses': 0,
          'pct': 1,
          'pointsFor': 82,
          'pointsAgainst': 79,
        },
      ],
      'leaderboards': [
        {
          'category': 'ppg',
          'rankings': [
            {
              'displayName': 'Player One',
              'teamName': 'Home',
              'value': 20,
              'gamesPlayed': 1,
            },
          ],
        },
      ],
    });

    expect(snapshot.leagueShortName, 'JBA');
    expect(snapshot.schedule.single.isFinal, isTrue);
    expect(snapshot.schedule.single.homeScore, 82);
    expect(snapshot.standings.single.wins, 1);
    expect(snapshot.leaderboards.single.rankings, isEmpty);
    expect(snapshot.playerDetail('player-1'), isNull);
  });

  test('parses versioned scope and builds public-only detail models', () {
    final snapshot = PublicLeagueSnapshot.fromMap(_versionedSnapshot());

    expect(snapshot.version.isVersioned, isTrue);
    expect(snapshot.version.privacyEpoch, 7);
    expect(snapshot.seasonName, '2026 NBL');
    expect(snapshot.divisionName('premier'), 'Premier');
    expect(snapshot.schedule.single.resultVersion, _resultHash);
    expect(
      snapshot.schedule.single.resultVersion,
      'c46005d8eb6b9cd76b4d5a51c7d41d1667e04738eefc0d715aabfe043dc8e7b0',
    );
    expect(snapshot.schedule.single.playerLines.single.turnovers, 2);
    expect(snapshot.schedule.single.playerLines.single.threePointMade, isNull);
    expect(snapshot.leaderboards.map((board) => board.category), [
      'ppg',
      'apg',
    ]);

    final game = snapshot.gameDetail('game-1');
    expect(game?.divisionName, 'Premier');
    final team = snapshot.teamDetail('home');
    expect(team?.games.single.gameId, 'game-1');
    expect(team?.standing?.gamesPlayed, 1);
    final player = snapshot.playerDetail('player-1');
    expect(player?.displayName, 'Player One');
    expect(player?.categories.length, 2);
    expect(player?.categories.first.divisionId, 'premier');
    expect(
      () => snapshot.schedule.add(snapshot.schedule.single),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.schedule.single.playerLines.add(
        snapshot.schedule.single.playerLines.single,
      ),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.leaderboards.first.rankings.add(
        snapshot.leaderboards.first.rankings.single,
      ),
      throwsUnsupportedError,
    );
  });

  test('a versioned final result without resultVersion fails closed', () {
    final map = _versionedSnapshot();
    final schedule = map['schedule']! as List<Map<String, dynamic>>;
    schedule.single.remove('resultVersion');

    expect(
      () => PublicLeagueSnapshot.fromMap(map),
      throwsA(isA<FormatException>()),
    );
  });

  test('a malformed resultVersion fails closed', () {
    final map = _versionedSnapshot();
    final schedule = map['schedule']! as List<Map<String, dynamic>>;
    schedule.single['resultVersion'] = 'not-a-result-hash';

    expect(
      () => PublicLeagueSnapshot.fromMap(map),
      throwsA(isA<FormatException>()),
    );
  });

  test('corrected result content with the previous version fails closed', () {
    final map = _versionedSnapshot();
    final schedule = map['schedule']! as List<Map<String, dynamic>>;
    schedule.single['homeScore'] = 83;

    expect(
      () => PublicLeagueSnapshot.fromMap(map),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('does not match'),
        ),
      ),
    );
  });

  test('a non-final game with result fields fails closed', () {
    final map = _versionedSnapshot();
    final schedule = map['schedule']! as List<Map<String, dynamic>>;
    schedule.single['status'] = 'scheduled';

    expect(
      () => PublicLeagueSnapshot.fromMap(map),
      throwsA(isA<FormatException>()),
    );
  });

  test('retracted release discards stale rows even if supplied', () {
    final map = _versionedSnapshot();
    final publication = map['publication']! as Map<String, dynamic>;
    publication['state'] = 'retracted';

    final snapshot = PublicLeagueSnapshot.fromMap(map);

    expect(snapshot.version.state, PublicReleaseState.retracted);
    expect(snapshot.schedule, isEmpty);
    expect(snapshot.teams, isEmpty);
    expect(snapshot.standings, isEmpty);
    expect(snapshot.leaderboards, isEmpty);
  });

  test('a missing published rank is presented as unresolved', () {
    final map = _versionedSnapshot();
    final standings = map['standings']! as List<Map<String, dynamic>>;
    standings.single.remove('rank');

    final snapshot = PublicLeagueSnapshot.fromMap(map);

    expect(snapshot.standings.single.rank, isNull);
    expect(snapshot.standings.single.rankStatus, PublicRankStatus.unresolved);
  });

  test(
    'missing publication signals fail closed without parsing stale rows',
    () {
      final map = _versionedSnapshot();
      map.remove('publication');
      map.remove('published');
      map['generatedAt'] = '2026-09-10T21:00:00.000Z';

      final snapshot = PublicLeagueSnapshot.fromMap(map);

      expect(snapshot.version.state, PublicReleaseState.unavailable);
      expect(snapshot.schedule, isEmpty);
      expect(snapshot.standings, isEmpty);
      expect(snapshot.leaderboards, isEmpty);
    },
  );

  test('versioned player identity without a privacy epoch fails closed', () {
    final map = _versionedSnapshot();
    final publication = map['publication']! as Map<String, dynamic>;
    publication.remove('privacyEpoch');

    expect(
      () => PublicLeagueSnapshot.fromMap(map),
      throwsA(isA<FormatException>()),
    );
  });

  test('malformed status and unsupported schemas are rejected', () {
    final badStatus = _versionedSnapshot();
    final schedule = badStatus['schedule']! as List<Map<String, dynamic>>;
    schedule.single['status'] = 'approved-ish';
    expect(
      () => PublicLeagueSnapshot.fromMap(badStatus),
      throwsA(isA<FormatException>()),
    );

    final badSchema = _versionedSnapshot()..['schemaVersion'] = 2;
    expect(
      () => PublicLeagueSnapshot.fromMap(badSchema),
      throwsA(isA<FormatException>()),
    );

    final badContract = _versionedSnapshot();
    final publication = badContract['publication']! as Map<String, dynamic>;
    publication['contractVersion'] = 'unknown-public-contract';
    expect(
      () => PublicLeagueSnapshot.fromMap(badContract),
      throwsA(isA<FormatException>()),
    );

    final badPublished = _versionedSnapshot()..['published'] = 'true';
    expect(
      () => PublicLeagueSnapshot.fromMap(badPublished),
      throwsA(isA<FormatException>()),
    );
  });
}

const _snapshotHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _resultHash = PublicGame(
  gameId: 'game-1',
  title: 'Home vs Away',
  startTime: DateTime.utc(2026, 9, 10, 20),
  divisionId: 'premier',
  homeTeamId: 'home',
  homeTeamName: 'Home',
  awayTeamId: 'away',
  awayTeamName: 'Away',
  homeScore: 82,
  awayScore: 79,
  status: PublicGameStatus.finalResult,
  periodScores: const [
    PublicPeriodScore(period: 1, homeScore: 20, awayScore: 18),
  ],
  playerLines: const [
    PublicPlayerGameLine(
      playerId: 'player-1',
      displayName: 'Player One',
      teamId: 'home',
      points: 20,
      twoPointMade: 6,
      twoPointAttempted: 10,
      turnovers: 2,
    ),
  ],
).resultContentDigest;

Map<String, dynamic> _versionedSnapshot() => {
  'schemaVersion': 1,
  'associationId': 'jba',
  'publication': {
    'state': 'published',
    'contractVersion': 'legacy-public-snapshot-v1.1',
    'snapshotVersion': _snapshotHash,
    'verificationStatus': 'legacyApproved',
    'privacyEpoch': 7,
    'generatedAt': '2026-09-10T21:00:00.000Z',
  },
  'league': {'name': 'Jamaica Basketball Association', 'shortName': 'JBA'},
  'season': {'seasonId': 'season-1', 'name': '2026 NBL'},
  'divisions': [
    {'divisionId': 'premier', 'name': 'Premier'},
  ],
  'teams': [
    {'teamId': 'home', 'name': 'Home', 'divisionId': 'premier'},
    {'teamId': 'away', 'name': 'Away', 'divisionId': 'premier'},
  ],
  'schedule': <Map<String, dynamic>>[
    {
      'gameId': 'game-1',
      'title': 'Home vs Away',
      'startTime': '2026-09-10T20:00:00.000Z',
      'status': 'final',
      'divisionId': 'premier',
      'homeTeamId': 'home',
      'homeTeamName': 'Home',
      'awayTeamId': 'away',
      'awayTeamName': 'Away',
      'homeScore': 82,
      'awayScore': 79,
      'resultVersion': _resultHash,
      'periodScores': [
        {'period': 1, 'homeScore': 20, 'awayScore': 18},
      ],
      'playerLines': [
        {
          'playerId': 'player-1',
          'displayName': 'Player One',
          'teamId': 'home',
          'points': 20,
          'twoPointMade': 6,
          'twoPointAttempted': 10,
          'turnovers': 2,
        },
      ],
    },
  ],
  'standings': [
    {
      'teamId': 'home',
      'teamName': 'Home',
      'divisionId': 'premier',
      'rank': 1,
      'rankStatus': 'ranked',
      'wins': 1,
      'losses': 0,
      'pct': 1,
      'pointsFor': 82,
      'pointsAgainst': 79,
    },
  ],
  'leaderboards': [
    {
      'category': 'apg',
      'divisionId': 'premier',
      'rankings': [
        {
          'playerId': 'player-1',
          'displayName': 'Player One',
          'teamId': 'home',
          'teamName': 'Home',
          'value': 4,
          'gamesPlayed': 1,
        },
      ],
    },
    {
      'category': 'ppg',
      'divisionId': 'premier',
      'rankings': [
        {
          'playerId': 'player-1',
          'displayName': 'Player One',
          'teamId': 'home',
          'teamName': 'Home',
          'value': 20,
          'gamesPlayed': 1,
        },
      ],
    },
  ],
};
