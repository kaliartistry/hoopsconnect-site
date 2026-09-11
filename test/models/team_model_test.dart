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
  });
}
