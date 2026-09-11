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

  test('unknown or mistyped explicit team lifecycle fails closed', () {
    Map<String, dynamic> data(Object? status, Object? active) {
      final value = <String, dynamic>{
        'name': 'Kingston Lions',
        'divisionId': 'premier',
        'seasonId': '2026',
      };
      if (status != null) value['status'] = status;
      if (active != null) value['active'] = active;
      return value;
    }

    expect(
      () => TeamModel.fromMap(id: 'team-1', data: data('enabled', null)),
      throwsFormatException,
    );
    expect(
      () => TeamModel.fromMap(id: 'team-1', data: data(1, null)),
      throwsFormatException,
    );
    expect(
      () => TeamModel.fromMap(id: 'team-1', data: data(null, 'false')),
      throwsFormatException,
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
