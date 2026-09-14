import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/league_catalog_model.dart';

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
