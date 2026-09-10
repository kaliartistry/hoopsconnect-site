import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';

void main() {
  test('parses the certified public snapshot used by guest mode', () {
    final snapshot = PublicLeagueSnapshot.fromMap({
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
    expect(
      snapshot.leaderboards.single.rankings.single.displayName,
      'Player One',
    );
  });
}
