import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:hoops_connect/models/game_stats_model.dart';
import 'package:hoops_connect/models/leaderboard_model.dart';

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
}
