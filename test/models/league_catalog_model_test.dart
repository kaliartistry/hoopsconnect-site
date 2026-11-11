import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/league_catalog_model.dart';
import 'package:hoops_connect/models/public_league_snapshot.dart';

void main() {
  test('parses nested leagues, divisions, branding, and sponsors', () {
    final catalog = LeagueCatalogModel.fromAssociationMap({
      'leagueCatalogV1': {
        'schemaVersion': 1,
        'leagues': [
          {
            'leagueId': 'schools',
            'name': 'School Leagues',
            'shortName': 'Schools',
            'divisionIds': ['a', 'b', 'girls'],
            'branding': {
              'primaryColorHex': '#1565C0',
              'sponsor': {
                'enabled': true,
                'name': 'Campus Courts',
                'label': 'Title sponsor',
              },
            },
          },
        ],
      },
    });

    expect(catalog.orderedActive.single.id, 'schools');
    expect(catalog.orderedActive.single.divisionIds, ['a', 'b', 'girls']);
    expect(catalog.orderedActive.single.primaryColorHex, '#1565C0');
    expect(catalog.orderedActive.single.sponsor.isActive, isTrue);
  });

  test('both sponsor views switch at midnight in Jamaica', () {
    final branding = <String, dynamic>{
      'sponsor': {'enabled': true, 'name': 'Current sponsor'},
      'scheduledSponsor': {
        'startsOn': '2026-12-01',
        'sponsor': {'enabled': true, 'name': 'Next sponsor'},
      },
    };
    final league = LeagueProfileModel.fromMap({
      'leagueId': 'jbl',
      'name': 'Jamaica Basketball League',
      'branding': branding,
    });
    final public = PublicBrandIdentity.fromMap(
      branding,
      fallbackName: league.name,
      fallbackShortName: league.shortName,
    );
    final before = DateTime.utc(2026, 12, 1, 4, 59, 59);
    final after = DateTime.utc(2026, 12, 1, 5);
    expect(league.sponsorAt(before).name, 'Current sponsor');
    expect(public.sponsorAt(before).name, 'Current sponsor');
    expect(league.sponsorAt(after).name, 'Next sponsor');
    expect(public.sponsorAt(after).name, 'Next sponsor');
    expect(
      league.copyWith(name: 'Updated name').sponsorAt(after).name,
      'Next sponsor',
    );
  });

  test('rejects a division assigned to multiple leagues', () {
    expect(
      () => LeagueCatalogModel.fromAssociationMap({
        'leagueCatalogV1': {
          'schemaVersion': 1,
          'leagues': [
            {
              'leagueId': 'one',
              'name': 'One',
              'divisionIds': ['a'],
            },
            {
              'leagueId': 'two',
              'name': 'Two',
              'divisionIds': ['a'],
            },
          ],
        },
      }),
      throwsFormatException,
    );
  });

  test('supports 100 leagues and rejects a larger catalog', () {
    Map<String, dynamic> associationWith(int count) => {
      'leagueCatalogV1': {
        'schemaVersion': 1,
        'leagues': [
          for (var index = 0; index < count; index++)
            {
              'leagueId': 'league-$index',
              'name': 'League $index',
              'divisionIds': <String>[],
            },
        ],
      },
    };

    expect(
      LeagueCatalogModel.fromAssociationMap(
        associationWith(LeagueCatalogModel.maxLeagues),
      ).leagues,
      hasLength(LeagueCatalogModel.maxLeagues),
    );
    expect(
      () => LeagueCatalogModel.fromAssociationMap(
        associationWith(LeagueCatalogModel.maxLeagues + 1),
      ),
      throwsFormatException,
    );
  });
}
