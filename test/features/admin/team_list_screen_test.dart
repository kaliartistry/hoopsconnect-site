import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/team_list_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/league_catalog_model.dart';
import 'package:hoops_connect/models/team_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/association_branding_providers.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/providers/team_providers.dart';
import 'package:hoops_connect/services/repositories/team_repository.dart';

class _TeamRepositorySpy implements TeamRepository {
  final created = <TeamModel>[];
  int identityUpdates = 0;

  @override
  Future<String> createTeam(String assocId, TeamModel team) async {
    created.add(team);
    return 'new-team';
  }

  @override
  Future<void> updateTeamIdentity({
    required String assocId,
    required String teamId,
    required String name,
    required String divisionId,
    String? logoUrl,
  }) async {
    identityUpdates++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('team list displays division names instead of raw IDs', (
    tester,
  ) async {
    final team = TeamModel(
      id: 'team_1',
      name: 'Kingston Lions',
      divisionId: 'premier-internal-id',
      seasonId: 'season_2026',
    );
    const viewer = UserModel(
      id: 'fan_1',
      email: 'fan@example.com',
      displayName: 'Fan',
      associationId: 'jba',
      role: UserRole.fan,
      capabilities: {'association.read'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(const AsyncValue.data(viewer)),
          leagueCatalogProvider.overrideWith(
            (ref) => Stream.value(
              const LeagueCatalogModel(
                leagues: [
                  LeagueProfileModel(
                    id: 'jbl',
                    name: 'Jamaica Basketball League',
                    shortName: 'JBL',
                  ),
                ],
              ),
            ),
          ),
          teamsStreamProvider.overrideWith((ref) => Stream.value([team])),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(
                id: 'premier-internal-id',
                name: 'First Round',
                leagueId: 'jbl',
              ),
            ]),
          ),
          activeSeasonIdProvider.overrideWith(
            (ref) => Stream.value('season_2026'),
          ),
        ],
        child: const MaterialApp(home: TeamListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kingston Lions'), findsOneWidget);
    expect(
      find.textContaining('Jamaica Basketball League · First Round'),
      findsOneWidget,
    );
    expect(find.textContaining('premier-internal-id'), findsNothing);
    expect(find.textContaining('Season season_2026'), findsOneWidget);
  });

  testWidgets('team editor offers a real logo upload workflow', (tester) async {
    const administrator = UserModel(
      id: 'admin_1',
      email: 'admin@example.com',
      displayName: 'Administrator',
      associationId: 'jba',
      role: UserRole.admin,
      capabilities: {'association.read', 'teams.manage'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AsyncValue.data(administrator),
          ),
          leagueCatalogProvider.overrideWith(
            (ref) => Stream.value(
              const LeagueCatalogModel(
                leagues: [
                  LeagueProfileModel(
                    id: 'jbl',
                    name: 'Jamaica Basketball League',
                    shortName: 'JBL',
                  ),
                ],
              ),
            ),
          ),
          teamsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(id: 'premier', name: 'Premier'),
            ]),
          ),
          activeSeasonIdProvider.overrideWith(
            (ref) => Stream.value('season_2026'),
          ),
        ],
        child: const MaterialApp(home: TeamListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Team logo'), findsOneWidget);
    expect(find.byKey(const Key('choose-team-logo')), findsOneWidget);
    expect(find.textContaining('Maximum 2 MB'), findsOneWidget);
  });

  testWidgets('a new team is written only after review and confirmation', (
    tester,
  ) async {
    const administrator = UserModel(
      id: 'admin_1',
      email: 'admin@example.com',
      displayName: 'Administrator',
      associationId: 'jba',
      role: UserRole.admin,
      capabilities: {'association.read', 'teams.manage'},
    );
    final repository = _TeamRepositorySpy();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            const AsyncValue.data(administrator),
          ),
          leagueCatalogProvider.overrideWith(
            (ref) => Stream.value(
              const LeagueCatalogModel(
                leagues: [
                  LeagueProfileModel(
                    id: 'jbl',
                    name: 'Jamaica Basketball League',
                    shortName: 'JBL',
                  ),
                ],
              ),
            ),
          ),
          teamsStreamProvider.overrideWith((ref) => Stream.value(const [])),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(
                id: 'premier',
                name: 'First Round',
                leagueId: 'jbl',
              ),
            ]),
          ),
          activeSeasonIdProvider.overrideWith(
            (ref) => Stream.value('season_2026'),
          ),
          teamRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: TeamListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final teamName = find.widgetWithText(TextFormField, 'Official team name');
    await tester.enterText(teamName, 'Kingston Lions');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Review team'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('Jamaica Basketball League · First Round'),
      ),
      findsOneWidget,
    );
    expect(repository.created, isEmpty);
    await tester.tap(find.text('Edit details'));
    await tester.pumpAndSettle();
    await tester.enterText(teamName, 'Kingston Royals');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Review team'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create team'));
    await tester.pumpAndSettle();

    expect(repository.created.single.name, 'Kingston Royals');
    expect(repository.created.single.divisionId, 'premier');
    expect(repository.identityUpdates, 1);
  });
}
