import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/team_model.dart';

void main() {
  test('normalizes whitespace and casing for duplicate guidance', () {
    expect(normalizeTeamName('  Kingston   Lions '), 'kingston lions');
  });

  test('team name conflicts are season-scoped and exclude the edited team', () {
    final teams = [
      TeamModel(
        id: 'a',
        name: 'Kingston Lions',
        divisionId: 'premier',
        seasonId: '2026',
      ),
      TeamModel(
        id: 'b',
        name: 'Kingston Lions',
        divisionId: 'premier',
        seasonId: '2025',
      ),
    ];

    expect(
      teamNameConflicts(
        teams: teams,
        candidateName: 'kingston  lions',
        seasonId: '2026',
      ).map((team) => team.id),
      ['a'],
    );
    expect(
      teamNameConflicts(
        teams: teams,
        candidateName: 'Kingston Lions',
        seasonId: '2026',
        excludingTeamId: 'a',
      ),
      isEmpty,
    );
  });

  test('legacy team maps derive normalized name without changing wire ID', () {
    final team = TeamModel.fromMap(
      id: 'stable-team-id',
      data: const {
        'name': 'Montego Bay Storm',
        'divisionId': 'development',
        'seasonId': '2026',
        'repIds': <String>[],
      },
    );

    expect(team.id, 'stable-team-id');
    expect(team.normalizedName, 'montego bay storm');
    expect(team.toFirestore()['normalizedName'], 'montego bay storm');
    expect(team.acceptsNewReferences, isTrue);
    expect(team.toFirestore().containsKey('status'), isFalse);
    expect(team.toFirestore().containsKey('active'), isFalse);
  });

  test('team lifecycle matches the legacy-compatible server contract', () {
    TeamModel parse(Map<String, dynamic> lifecycle) => TeamModel.fromMap(
      id: 'team-1',
      data: {
        'name': 'Kingston Lions',
        'divisionId': 'premier',
        'seasonId': '2026',
        ...lifecycle,
      },
    );

    expect(parse({'status': 'active'}).acceptsNewReferences, isTrue);
    expect(
      parse({'status': 'active', 'active': true}).acceptsNewReferences,
      isTrue,
    );
    expect(parse({'status': 'inactive'}).acceptsNewReferences, isFalse);
    expect(parse({'status': 'archived'}).acceptsNewReferences, isFalse);
    expect(parse({'active': false}).acceptsNewReferences, isFalse);
    expect(
      parse({'status': 'archived', 'active': true}).acceptsNewReferences,
      isFalse,
    );
    expect(parse({'status': 'active'}).toFirestore()['status'], 'active');
    expect(parse({'active': false}).toFirestore()['active'], isFalse);
  });

  test('lifecycle round trip preserves field presence and raw values', () {
    TeamModel parse(Map<String, dynamic> lifecycle) => TeamModel.fromMap(
      id: 'team-1',
      data: {
        'name': 'Kingston Lions',
        'divisionId': 'premier',
        'seasonId': '2026',
        ...lifecycle,
      },
    );

    final absent = parse({});
    expect(absent.hasStatus, isFalse);
    expect(absent.hasLegacyActive, isFalse);
    expect(absent.toFirestore().containsKey('status'), isFalse);
    expect(absent.toFirestore().containsKey('active'), isFalse);

    final explicitNulls = parse({'status': null, 'active': null});
    expect(explicitNulls.hasStatus, isTrue);
    expect(explicitNulls.hasLegacyActive, isTrue);
    expect(explicitNulls.toFirestore().containsKey('status'), isTrue);
    expect(explicitNulls.toFirestore()['status'], isNull);
    expect(explicitNulls.toFirestore().containsKey('active'), isTrue);
    expect(explicitNulls.toFirestore()['active'], isNull);

    final malformed = parse({'status': 7, 'active': 'false'});
    expect(malformed.toFirestore()['status'], 7);
    expect(malformed.toFirestore()['active'], 'false');
    final copied = malformed.copyWith(name: 'Renamed');
    expect(copied.hasStatus, isTrue);
    expect(copied.status, 7);
    expect(copied.hasLegacyActive, isTrue);
    expect(copied.active, 'false');
  });

  test('explicit status and legacy active use exact server predicates', () {
    TeamModel parse(Map<String, dynamic> lifecycle) => TeamModel.fromMap(
      id: 'team-1',
      data: {
        'name': 'Kingston Lions',
        'divisionId': 'premier',
        'seasonId': '2026',
        ...lifecycle,
      },
    );

    expect(parse({'status': null}).acceptsNewReferences, isFalse);
    expect(parse({'status': 'unknown'}).acceptsNewReferences, isFalse);
    expect(parse({'status': 1}).acceptsNewReferences, isFalse);
    expect(parse({'active': null}).acceptsNewReferences, isTrue);
    expect(parse({'active': 'false'}).acceptsNewReferences, isTrue);
    expect(parse({'active': 0}).acceptsNewReferences, isTrue);
    expect(parse({'active': false}).acceptsNewReferences, isFalse);
    expect(
      parse({'status': null, 'active': true}).acceptsNewReferences,
      isFalse,
    );
  });

  test('schedule eligibility requires the exact season and division', () {
    final teams = [
      TeamModel(
        id: 'eligible',
        name: 'Eligible',
        seasonId: 'season_1',
        divisionId: 'premier',
      ),
      TeamModel(
        id: 'wrong_season',
        name: 'Wrong Season',
        seasonId: 'season_2',
        divisionId: 'premier',
      ),
      TeamModel(
        id: 'wrong_division',
        name: 'Wrong Division',
        seasonId: 'season_1',
        divisionId: 'development',
      ),
    ];

    expect(
      teamsEligibleForSchedule(
        teams: teams,
        seasonId: 'season_1',
        divisionId: 'premier',
      ).map((team) => team.id),
      ['eligible'],
    );
  });
}
