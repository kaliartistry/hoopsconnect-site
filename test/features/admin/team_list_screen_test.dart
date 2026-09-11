import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/team_list_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/team_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';
import 'package:hoops_connect/providers/season_providers.dart';
import 'package:hoops_connect/providers/team_providers.dart';

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
          teamsStreamProvider.overrideWith((ref) => Stream.value([team])),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(id: 'premier-internal-id', name: 'Premier League'),
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
    expect(find.textContaining('Premier League'), findsOneWidget);
    expect(find.textContaining('premier-internal-id'), findsNothing);
    expect(find.textContaining('Season season_2026'), findsOneWidget);
  });
}
