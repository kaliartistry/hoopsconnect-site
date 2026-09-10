import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/models/association_branding_model.dart';
import 'package:hoops_connect/models/game_stats_model.dart';

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
}
