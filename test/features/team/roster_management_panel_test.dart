import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/team/roster_management_panel.dart';
import 'package:hoops_connect/models/player_season_stats_model.dart';
import 'package:hoops_connect/models/roster_workflow_model.dart';
import 'package:hoops_connect/models/team_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/providers/auth_providers.dart';
import 'package:hoops_connect/providers/roster_workflow_providers.dart';

UserModel representative({required String teamId}) => UserModel(
  id: 'rep_1',
  email: 'rep@example.com',
  displayName: 'Team Rep',
  associationId: 'jba',
  teamId: teamId,
  role: UserRole.rep,
  capabilities: const {'association.read', 'teams.represent'},
);

UserModel manager() => const UserModel(
  id: 'admin_1',
  email: 'admin@example.com',
  displayName: 'Roster Admin',
  associationId: 'jba',
  role: UserRole.admin,
  capabilities: {'association.read', 'teams.manage'},
);

final team = TeamModel(
  id: 'team_1',
  name: 'Kingston Lions',
  divisionId: 'premier',
  seasonId: 'season_1',
);

void main() {
  testWidgets('unrelated representative sees an explicit view-only denial', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            AsyncValue.data(representative(teamId: 'team_2')),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: const AsyncValue.data([]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('View only'), findsOneWidget);
    expect(find.textContaining('only for your assigned team'), findsOneWidget);
    expect(find.text('Propose player'), findsNothing);
  });

  testWidgets('manager sees registration facts without fabricated stats', (
    tester,
  ) async {
    final workspace = RosterWorkspace(
      rosterVersion: 2,
      registrations: [
        RosterRegistration(
          registrationId: 'registration_1',
          playerId: 'player_1',
          displayName: 'Aaliyah Brown',
          teamId: 'team_1',
          seasonId: 'season_1',
          jerseyNumber: '00',
          position: 'Guard',
          status: 'active',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(AsyncValue.data(manager())),
          rosterWorkspaceProvider.overrideWith(
            (ref, target) async => workspace,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: const AsyncValue.data([]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add player'), findsOneWidget);
    expect(find.text('Aaliyah Brown'), findsOneWidget);
    expect(find.text('00'), findsOneWidget);
    expect(find.textContaining('Season stats not calculated'), findsOneWidget);
  });

  testWidgets('canonical registrations remain visible when aggregates fail', (
    tester,
  ) async {
    const workspace = RosterWorkspace(
      rosterVersion: 2,
      registrations: [
        RosterRegistration(
          registrationId: 'registration_1',
          playerId: 'player_1',
          displayName: 'Canonical Player',
          teamId: 'team_1',
          seasonId: 'season_1',
          jerseyNumber: '0',
          status: 'active',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(AsyncValue.data(manager())),
          rosterWorkspaceProvider.overrideWith(
            (ref, target) async => workspace,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: AsyncValue.error(
                StateError('legacy aggregate unavailable'),
                StackTrace.empty,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Canonical Player'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Season statistics unavailable'), findsOneWidget);
  });

  testWidgets('canonical empty roster does not revive stale aggregate rows', (
    tester,
  ) async {
    const workspace = RosterWorkspace(rosterVersion: 3);
    const staleAggregate = PlayerSeasonStatsModel(
      id: 'stale_season_1',
      playerId: 'stale',
      playerName: 'Stale Legacy Player',
      teamId: 'team_1',
      seasonId: 'season_1',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(AsyncValue.data(manager())),
          rosterWorkspaceProvider.overrideWith(
            (ref, target) async => workspace,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: const AsyncValue.data([staleAggregate]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No registered players'), findsOneWidget);
    expect(find.text('Stale Legacy Player'), findsNothing);
  });

  testWidgets('canonical empty roster survives aggregate failure', (
    tester,
  ) async {
    const workspace = RosterWorkspace(rosterVersion: 3);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(AsyncValue.data(manager())),
          rosterWorkspaceProvider.overrideWith(
            (ref, target) async => workspace,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: AsyncValue.error(
                StateError('legacy aggregate unavailable'),
                StackTrace.empty,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No registered players'), findsOneWidget);
    expect(find.text('Season statistics unavailable'), findsOneWidget);
  });

  testWidgets('pending representative proposal is clearly not approved', (
    tester,
  ) async {
    final workspace = RosterWorkspace(
      rosterVersion: 2,
      proposals: [
        RosterProposalSummary(
          proposalId: 'proposal_1',
          kind: RosterChangeKind.addPlayer,
          status: RosterApprovalStatus.pending,
          teamId: 'team_1',
          seasonId: 'season_1',
          before: null,
          after: const RosterPlayerFacts(
            displayName: 'Aaliyah Brown',
            jerseyNumber: '00',
            position: 'Guard',
          ),
          reason: 'New registration',
          requestedByName: 'Team Rep',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(
            AsyncValue.data(representative(teamId: 'team_1')),
          ),
          rosterWorkspaceProvider.overrideWith(
            (ref, target) async => workspace,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: const AsyncValue<List<PlayerSeasonStatsModel>>.data(
                [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Propose player'), findsOneWidget);
    expect(find.textContaining('pending roster request'), findsOneWidget);
    expect(find.textContaining('Pending admin approval'), findsOneWidget);
    expect(
      find.textContaining('After: Aaliyah Brown • #00 • Guard'),
      findsOneWidget,
    );
    expect(find.text('Reason: New registration'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('admin sees immutable proposal facts before approval', (
    tester,
  ) async {
    final workspace = RosterWorkspace(
      rosterVersion: 4,
      proposals: [
        RosterProposalSummary(
          proposalId: 'proposal_2',
          kind: RosterChangeKind.updatePlayer,
          status: RosterApprovalStatus.pending,
          teamId: 'team_1',
          seasonId: 'season_1',
          before: const RosterPlayerFacts(
            playerId: 'player_1',
            registrationId: 'registration_1',
            displayName: 'Aaliyah Brown',
            jerseyNumber: '0',
            position: 'Forward',
          ),
          after: const RosterPlayerFacts(
            playerId: 'player_1',
            registrationId: 'registration_1',
            displayName: 'Aaliyah Brown',
            jerseyNumber: '00',
            position: 'Guard',
          ),
          reason: 'Correct jersey and position',
          requestedByName: 'Team Rep',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(AsyncValue.data(manager())),
          rosterWorkspaceProvider.overrideWith(
            (ref, target) async => workspace,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TeamRosterManagementPanel(
              team: team,
              seasonId: 'season_1',
              legacyRoster: const AsyncValue.data([]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Before: Aaliyah Brown • #0 • Forward'),
      findsOneWidget,
    );
    expect(
      find.textContaining('After: Aaliyah Brown • #00 • Guard'),
      findsOneWidget,
    );
    expect(find.text('Reason: Correct jersey and position'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Approve roster request?'), findsOneWidget);
    expect(
      find.text('Requested reason: Correct jersey and position'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Before: Aaliyah Brown • #0 • Forward'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('After: Aaliyah Brown • #00 • Guard'),
      findsNWidgets(2),
    );
  });
}
