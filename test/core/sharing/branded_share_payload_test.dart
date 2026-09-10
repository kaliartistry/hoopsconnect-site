import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:hoops_connect/models/game_stats_model.dart';
import 'package:hoops_connect/models/leaderboard_model.dart';
import 'package:hoops_connect/models/player_season_stats_model.dart';
import 'package:hoops_connect/models/standings_model.dart';

void main() {
  const stats = GameStatsModel(
    id: 'game-1',
    eventId: 'game-1',
    seasonId: 'season-1',
    divisionId: 'nbl',
    homeTeamId: 'home',
    awayTeamId: 'away',
    homeTeamName: 'Kingston Titans',
    awayTeamName: 'Montego Bay Storm',
    homeScore: 87,
    awayScore: 72,
    status: GameStatsStatus.approved,
  );

  test('game result identifies the league and HoopsConnect', () {
    final payload = BrandedSharePayload.gameSummary(
      stats: stats,
      branding: AssociationBrandingModel.jba(),
    );

    expect(payload.headline, contains('87-72'));
    expect(payload.shareText, contains('Jamaica Basketball Association'));
    expect(payload.shareText, contains('Shared from HoopsConnect'));
    expect(payload.fileName, 'jamaica-basketball-game-result.png');
  });

  test('active title sponsor is included without replacing the league', () {
    final branding = AssociationBrandingModel.jba().copyWith(
      sponsor: const SponsorBrandingModel(
        enabled: true,
        name: 'KFC',
        label: 'Presented by',
      ),
    );

    final payload = BrandedSharePayload.gameSummary(
      stats: stats,
      branding: branding,
    );

    expect(payload.shareText, contains('Presented by KFC'));
    expect(payload.shareText, contains('Jamaica Basketball Association'));
  });

  test('leaderboard highlights the top three and shares the full ranking', () {
    const rankings = [
      LeaderboardEntry(
        playerId: 'one',
        name: 'A. Brown',
        teamName: 'Kingston Titans',
        value: 24.8,
        gp: 8,
      ),
      LeaderboardEntry(
        playerId: 'two',
        name: 'B. Grant',
        teamName: 'Montego Bay Storm',
        value: 22.1,
        gp: 8,
      ),
      LeaderboardEntry(
        playerId: 'three',
        name: 'C. James',
        teamName: 'Portmore Waves',
        value: 20.4,
        gp: 7,
      ),
      LeaderboardEntry(
        playerId: 'four',
        name: 'D. Reid',
        teamName: 'Spanish Town Lions',
        value: 18.9,
        gp: 8,
      ),
    ];

    final payload = BrandedSharePayload.leaderboard(
      rankings: rankings,
      category: 'ppg',
      branding: AssociationBrandingModel.jba(),
    );

    expect(payload.eyebrow, 'SEASON LEADERS');
    expect(payload.headline, 'A. Brown leads with 24.8 PPG');
    expect(payload.detail, contains('#3 C. James'));
    expect(payload.detail, isNot(contains('D. Reid')));
    expect(payload.shareText, contains('4. D. Reid'));
    expect(payload.fileName, 'jamaica-basketball-ppg-leaders.png');
  });

  test('empty leaderboard cannot create a misleading share card', () {
    expect(
      () => BrandedSharePayload.leaderboard(
        rankings: const [],
        category: 'ppg',
        branding: AssociationBrandingModel.jba(),
      ),
      throwsArgumentError,
    );
  });

  test('player spotlight includes the complete season average line', () {
    const playerStats = PlayerSeasonStatsModel(
      id: 'player-1-season-1',
      playerId: 'player-1',
      playerName: 'A. Brown',
      teamId: 'home',
      teamName: 'Kingston Titans',
      seasonId: 'season-1',
      gamesPlayed: 8,
      averages: {'ppg': 24.8, 'rpg': 8.2, 'apg': 5.4, 'spg': 1.8, 'bpg': 0.9},
    );

    final payload = BrandedSharePayload.playerStats(
      stats: playerStats,
      branding: AssociationBrandingModel.jba(),
    );

    expect(payload.eyebrow, 'PLAYER SPOTLIGHT');
    expect(payload.headline, 'A. Brown');
    expect(payload.detail, contains('Kingston Titans · 8 GP'));
    expect(payload.detail, contains('24.8 PPG'));
    expect(payload.shareText, contains('0.9 BPG'));
    expect(payload.fileName, 'jamaica-basketball-a-brown-stats.png');
  });

  test('standings share shows podium teams and includes the full table', () {
    const standings = [
      TeamStanding(
        teamId: 'one',
        teamName: 'Kingston Titans',
        wins: 8,
        losses: 1,
        pct: .889,
        gb: 0,
        streak: 'W4',
        lastTen: '8-1',
        pointsFor: 720,
        pointsAgainst: 640,
      ),
      TeamStanding(
        teamId: 'two',
        teamName: 'Montego Bay Storm',
        wins: 7,
        losses: 2,
        pct: .778,
        gb: 1,
        streak: 'W2',
        lastTen: '7-2',
        pointsFor: 690,
        pointsAgainst: 650,
      ),
      TeamStanding(
        teamId: 'three',
        teamName: 'Portmore Waves',
        wins: 6,
        losses: 3,
        pct: .667,
        gb: 2,
        streak: 'L1',
        lastTen: '6-3',
        pointsFor: 670,
        pointsAgainst: 655,
      ),
      TeamStanding(
        teamId: 'four',
        teamName: 'Spanish Town Lions',
        wins: 5,
        losses: 4,
        pct: .556,
        gb: 3,
        streak: 'W1',
        lastTen: '5-4',
        pointsFor: 660,
        pointsAgainst: 658,
      ),
    ];

    final payload = BrandedSharePayload.standings(
      standings: standings,
      branding: AssociationBrandingModel.jba(),
      divisionName: 'NBL Premier',
    );

    expect(payload.eyebrow, 'LEAGUE STANDINGS');
    expect(payload.headline, 'Kingston Titans leads NBL Premier');
    expect(payload.detail, contains('#3 Portmore Waves · 6-3'));
    expect(payload.detail, isNot(contains('Spanish Town Lions')));
    expect(payload.shareText, contains('4. Spanish Town Lions 5-4'));
    expect(payload.fileName, 'jamaica-basketball-nbl-premier-standings.png');
  });

  test('empty standings cannot create a misleading share card', () {
    expect(
      () => BrandedSharePayload.standings(
        standings: const [],
        branding: AssociationBrandingModel.jba(),
      ),
      throwsArgumentError,
    );
  });
}
