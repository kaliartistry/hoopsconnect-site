import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/admin/division_management_screen.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/models/league_catalog_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/association_branding_providers.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/division_providers.dart';

void main() {
  testWidgets('division menu exposes archive and dependencies but no delete', (
    tester,
  ) async {
    const admin = UserModel(
      id: 'admin_1',
      email: 'admin@example.com',
      displayName: 'Admin',
      associationId: 'jba',
      role: UserRole.admin,
      capabilities: {'association.read', 'association.manage'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(const AsyncValue.data(admin)),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(id: 'premier', name: 'Premier', leagueId: 'nbl'),
            ]),
          ),
          leagueCatalogProvider.overrideWith(
            (ref) => Stream.value(
              const LeagueCatalogModel(
                leagues: [
                  LeagueProfileModel(
                    id: 'nbl',
                    name: 'National Basketball League',
                    shortName: 'NBL',
                    divisionIds: ['premier'],
                  ),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: DivisionManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions for Premier'));
    await tester.pumpAndSettle();

    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Review dependencies'), findsOneWidget);
    expect(find.text('Delete permanently'), findsNothing);
  });

  testWidgets('division is visibly nested under its parent league', (
    tester,
  ) async {
    const admin = UserModel(
      id: 'admin_1',
      email: 'admin@example.com',
      displayName: 'Admin',
      associationId: 'jba',
      role: UserRole.admin,
      capabilities: {'association.read', 'association.manage'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(const AsyncValue.data(admin)),
          divisionsStreamProvider.overrideWith(
            (ref) => Stream.value(const [
              DivisionModel(
                id: 'schoolboy-a',
                name: 'Division A',
                leagueId: 'schools',
              ),
            ]),
          ),
          leagueCatalogProvider.overrideWith(
            (ref) => Stream.value(
              const LeagueCatalogModel(
                leagues: [
                  LeagueProfileModel(
                    id: 'schools',
                    name: 'Schoolboy League',
                    shortName: 'Schools',
                    divisionIds: ['schoolboy-a'],
                  ),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: DivisionManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Schoolboy League'), findsOneWidget);
    expect(find.text('Division A'), findsOneWidget);
    expect(find.textContaining('beneath this league'), findsOneWidget);
  });
}
