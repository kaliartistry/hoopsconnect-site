import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/public/historical_league_standings.dart';
import 'package:hoops_connect/models/league_catalog_model.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';
import 'package:hoops_connect/services/presentation_public_snapshot.dart';
import 'package:hoops_connect/features/stats/standings_screen.dart';
import 'package:hoops_connect/providers/public_league_provider.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/core/sharing/branded_share_payload.dart';
import 'package:hoops_connect/core/sharing/branded_share_sheet.dart';
import 'package:hoops_connect/core/sharing/public_share_branding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PublicLeagueSnapshot loadedSnapshot;
  setUpAll(() async {
    loadedSnapshot = await PresentationPublicSnapshotReader().load();
  });
  test(
    'team totals reconcile without inferring team games or win-loss records',
    () async {
      final snapshot = await PresentationPublicSnapshotReader().load();
      final totals = snapshot.teams
          .where((t) => t.divisionId == 'jbl-2025-first-round')
          .map((t) => recordedTeamTotals(snapshot, t.teamId))
          .toList();
      expect(totals.fold<int>(0, (s, t) => s + t['ppg']!), 5555);
      expect(totals.fold<int>(0, (s, t) => s + t['rpg']!), 4073);
      expect(totals.fold<int>(0, (s, t) => s + t['apg']!), 1181);
      expect(
        recordedTeamTotals(snapshot, 'absent').values,
        everyElement(isNull),
      );
      expect(totals.first.containsKey('gamesPlayed'), isFalse);
    },
  );
  test('catalog edits retain historical scope and reported standings', () {
    final original = LeagueProfileModel.fromMap({
      'leagueId': 'jbl',
      'name': 'Jamaica Basketball League',
      'divisionIds': ['stats'],
      'historicalStatistics': true,
      'seasonLabel': '2025 Season',
      'reportedStandings': [
        {'teamId': 'slayers', 'leaguePoints': 16},
      ],
      'standingsAsOf': '2025-04-15',
      'standingsSourceUrl': 'https://example.org/results',
    });
    final result = original.copyWith(name: 'Updated name').toMap();
    expect(result['reportedStandings'], original.toMap()['reportedStandings']);
    expect(result['seasonLabel'], '2025 Season');
    expect(result['historicalStatistics'], isTrue);
  });
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets(
      'reported points table renders on $size without fabricated wins',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final snapshot = loadedSnapshot;
        final league = PublicLeagueDefinition(
          leagueId: 'jbl',
          name: 'Jamaica Basketball League',
          shortName: 'JBL',
          historicalStatistics: true,
          seasonLabel: '2025 Season',
          standingsAsOf: '2025-04-15',
          divisionIds: ['jbl-2025-first-round'],
          reportedStandings: [
            ReportedTeamStanding(
              teamId: 'st-georges-slayers',
              leaguePoints: 16,
            ),
            ReportedTeamStanding(teamId: 'upper-room-eagles', leaguePoints: 16),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: HistoricalLeagueStandings(
                  snapshot: snapshot,
                  league: league,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('LEAGUE\nPOINTS'), findsOneWidget);
        expect(find.text('W'), findsOneWidget);
        expect(find.text('L'), findsOneWidget);
        expect(find.text('16'), findsNWidgets(2));
        expect(find.textContaining('First Round'), findsNothing);
        expect(find.textContaining('7-2'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'member standings use published JBL totals without requiring win-loss documents',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeSeasonIdProvider.overrideWith(
              (ref) => Stream.value('season'),
            ),
            selectedDivisionProvider.overrideWithValue(null),
            selectedDivisionIdProvider.overrideWith(
              (ref) => 'jbl-2025-first-round',
            ),
            publicLeagueSnapshotProvider.overrideWith(
              (ref) => Stream.value(loadedSnapshot),
            ),
          ],
          child: const MaterialApp(home: StandingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LEAGUE\nPOINTS'), findsOneWidget);
      expect(find.text('No standings data'), findsNothing);
      expect(find.textContaining('FOSKA Oats'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ten-team share table fits the card and retains its sponsor', (
    tester,
  ) async {
    final league = loadedSnapshot.leagueById('jbl');
    final teams = loadedSnapshot.teams
        .where((t) => league.divisionIds.contains(t.divisionId))
        .toList();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BrandedShareCard(
                branding: publicShareBranding(loadedSnapshot, league),
                payload: BrandedSharePayload(
                  title: 'Standings',
                  eyebrow: 'LEAGUE STANDINGS',
                  headline: league.name,
                  detail: '',
                  shareText: '',
                  fileName: 'standings.png',
                  divisionLabel: '2025 Season',
                  tableRows: [
                    for (final team in teams)
                      BrandedShareTableRow(
                        name: team.name,
                        value: '16',
                        logoUrl: team.logoUrl,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final team in teams) {
      expect(find.text(team.name), findsOneWidget);
    }
    expect(find.text('LEAGUE PTS'), findsOneWidget);
    expect(find.textContaining('Equal points remain tied'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(20));
    expect(tester.takeException(), isNull);
  });
}
