import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/services/presentation_public_snapshot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled presentation snapshot is published and multi-league', () async {
    final snapshot = await PresentationPublicSnapshotReader().load();

    expect(snapshot.version.isPublished, isTrue);
    expect(snapshot.availableLeagues.map((league) => league.name), [
      'Jamaica Basketball League',
      'Women’s League',
      'Schoolboy League',
    ]);
    expect(
      snapshot.divisionsForLeague('jbl').map((division) => division.name),
      ['2025 Season'],
    );
    expect(snapshot.schedule.any((game) => game.isFinal), isTrue);
    expect(snapshot.schedule.any((game) => !game.isFinal), isTrue);
    expect(snapshot.seasonName, '2026 Season');
    expect(snapshot.leagueName, 'Jamaica Basketball Association');
    expect(snapshot.leagueShortName, 'JBA');
    expect(
      snapshot.effectiveAssociationBrand.sponsor.label,
      'Association partner',
    );
    expect(
      snapshot.availableLeagues
          .where((league) => league.leagueId != 'jbl')
          .every((league) => league.sponsor.label == 'Title sponsor'),
      isTrue,
    );
    final jbl = snapshot.leagueById('jbl');
    expect(jbl.historicalStatistics, isTrue);
    expect(jbl.seasonLabel, '2025 Season');
    expect(jbl.sponsor.name, 'FOSKA Oats');
    expect(jbl.sponsor.label, 'Main Sponsor');
    expect(jbl.supportingSponsorExamples, hasLength(2));
    expect(
      jbl.supportingSponsorExamples.every(
        (s) => s.label == 'Demo supporting sponsor',
      ),
      isTrue,
    );
    final teams = snapshot.teams.where(
      (t) => jbl.divisionIds.contains(t.divisionId),
    );
    expect(teams, hasLength(10));
    expect(
      teams.every(
        (t) => t.logoUrl?.startsWith('asset:assets/images/jbl_') == true,
      ),
      isTrue,
    );
    expect(
      snapshot.schedule.where((g) => jbl.divisionIds.contains(g.divisionId)),
      isEmpty,
    );
    expect(
      snapshot.standings.where((s) => jbl.divisionIds.contains(s.divisionId)),
      isEmpty,
    );
    final boards = snapshot.leaderboards
        .where((b) => jbl.divisionIds.contains(b.divisionId))
        .toList();
    expect(boards, hasLength(5));
    expect(boards.every((b) => b.rankings.length == 188), isTrue);
    final points = boards.firstWhere((b) => b.category == 'ppg');
    expect(
      points.rankings.fold<int>(0, (total, p) => total + p.cumulativeTotal!),
      5555,
    );
    for (final player in points.rankings) {
      expect(
        player.value,
        closeTo(player.cumulativeTotal! / player.gamesPlayed!, 0.00001),
      );
    }
  });
}
