import '../../models/association_branding_model.dart';
import 'branded_share_payload.dart';

/// Local-only examples for demonstrating the sharing workflow. Team names can
/// match presentation rosters; scores and statistics are invented, never read
/// from private records, and never claimed as published league results.
abstract final class ShareDemoSamples {
  static AssociationBrandingModel get branding =>
      AssociationBrandingModel.jba().copyWith(
        leagueName: 'National Basketball League',
        shortName: 'NBL',
        logoUrl: 'asset:assets/images/nbl_jamaica_logo.png',
        primaryColorHex: '#184A9E',
        secondaryColorHex: '#0B1D3A',
        accentColorHex: '#E7BC5A',
        sponsor: const SponsorBrandingModel(
          enabled: true,
          name: 'ShipSafe SDK',
          label: 'Title sponsor',
          logoUrl: 'asset:assets/images/sponsor_shipsafe.png',
        ),
      );

  static BrandedSharePayload get boxScore => const BrandedSharePayload(
    title: 'NBL box score',
    sheetTitle: 'Share box score',
    eyebrow: 'BOX SCORE',
    headline: 'Final box score',
    detail: 'Quarter scores and top performers',
    shareText:
        'St George’s Slayers 82 · UWI Running Rebels 76\n'
        'Quarter scores: 21–18 · 19–20 · 20–19 · 22–19\n'
        'Andre Blake: 40 PTS · 2 REB · 6 AST\n'
        'Jordan Clarke: 34 PTS · 3 REB · 6 AST\n'
        'Shared from HoopsConnect',
    fileName: 'hoopsconnect-box-score.png',
    sourceLabel: 'League box score',
    isDemonstration: true,
    divisionLabel: 'Premier',
    periodScoreLine: '1: 21–18 · 2: 19–20 · 3: 20–19 · 4: 22–19',
    performerLines: [
      'Andre Blake · 40 PTS · 2 REB · 6 AST',
      'Jordan Clarke · 34 PTS · 3 REB · 6 AST',
    ],
    teams: [
      BrandedShareTeam(name: 'St George’s Slayers', score: 82),
      BrandedShareTeam(name: 'UWI Running Rebels', score: 76),
    ],
  );

  static BrandedSharePayload get player => const BrandedSharePayload(
    title: 'NBL player card',
    sheetTitle: 'Share player stats',
    eyebrow: 'PLAYER STATS',
    headline: 'Andre Blake · 40 PTS',
    detail: '40 points · 2 rebounds · 6 assists',
    shareText:
        'Andre Blake: 40 PTS · 2 REB · 6 AST\n'
        'National Basketball League · Premier\n'
        'Shared from HoopsConnect',
    fileName: 'hoopsconnect-player-stats.png',
    sourceLabel: 'Player statistics',
    isDemonstration: true,
    divisionLabel: 'Premier',
    teams: [BrandedShareTeam(name: 'Andre Blake')],
  );

  static BrandedSharePayload get leaderboard => leaderboardFor('ppg');

  static BrandedSharePayload leaderboardFor(String category) {
    final (label, first, second) = switch (category) {
      'rpg' => ('rebounds', '12.4 REB', '10.8 REB'),
      'apg' => ('assists', '8.2 AST', '7.5 AST'),
      'spg' => ('steals', '3.1 STL', '2.7 STL'),
      'bpg' => ('blocks', '2.6 BLK', '2.1 BLK'),
      _ => ('scoring', '40.0 PTS', '34.0 PTS'),
    };
    return BrandedSharePayload(
      title: 'NBL $label leaders',
      sheetTitle: 'Share $label leaders',
      eyebrow: 'SEASON LEADERS',
      headline: '$label leaders',
      detail:
          '1 · Andre Blake · $first\n'
          '2 · Jordan Clarke · $second',
      shareText:
          '$label leaders: Andre Blake $first; Jordan Clarke $second.\n'
          'Shared from HoopsConnect',
      fileName: 'hoopsconnect-$category-leaders.png',
      sourceLabel: 'Season leaders',
      isDemonstration: true,
      divisionLabel: 'Premier',
    );
  }
}
