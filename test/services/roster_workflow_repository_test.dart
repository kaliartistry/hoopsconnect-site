import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/roster_workflow_model.dart';
import 'package:hoops_connect/models/user_model.dart';
import 'package:hoops_connect/services/repositories/roster_workflow_repository.dart';

UserModel user({String? teamId, Set<String> capabilities = const {}}) =>
    UserModel(
      id: 'user_1',
      email: 'user@example.com',
      displayName: 'User',
      associationId: 'jba',
      teamId: teamId,
      role: teamId == null ? UserRole.admin : UserRole.rep,
      capabilities: capabilities,
    );

RosterChangeRequest request({String teamId = 'team_1'}) => RosterChangeRequest(
  operationId: 'operation_1',
  teamId: teamId,
  seasonId: 'season_1',
  expectedRosterVersion: 4,
  kind: RosterChangeKind.addPlayer,
  displayName: 'Aaliyah Brown',
  jerseyNumber: '00',
  reason: 'New registration',
);

void main() {
  test('own-team representative submits a pending proposal contract', () async {
    String? calledName;
    Map<String, Object?>? calledData;
    final repository = RosterWorkflowRepository(
      callable: (name, data) async {
        calledName = name;
        calledData = data;
        return {
          'operationId': data['operationId'],
          'proposalId': 'proposal_1',
          'status': 'pending',
          'rosterVersion': 4,
        };
      },
    );

    final receipt = await repository.submitChange(
      user: user(teamId: 'team_1', capabilities: const {'teams.represent'}),
      request: request(),
    );

    expect(calledName, 'submitRosterChange');
    expect(calledData!['requestedOutcome'], 'propose');
    expect(calledData!['jerseyNumber'], '00');
    expect(receipt.status, RosterApprovalStatus.pending);
  });

  test(
    'unrelated-team representative is denied before a callable runs',
    () async {
      var calls = 0;
      final repository = RosterWorkflowRepository(
        callable: (_, _) async {
          calls++;
          return {};
        },
      );

      await expectLater(
        repository.submitChange(
          user: user(teamId: 'team_1', capabilities: const {'teams.represent'}),
          request: request(teamId: 'team_2'),
        ),
        throwsA(
          isA<RosterWorkflowException>().having(
            (error) => error.code,
            'code',
            'client-permission-denied',
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  test('roster manager requests immediate server application', () async {
    final repository = RosterWorkflowRepository(
      callable: (_, data) async => {
        'operationId': data['operationId'],
        'playerId': 'player_1',
        'registrationId': 'registration_1',
        'status': 'approved',
        'rosterVersion': 5,
      },
    );

    final receipt = await repository.submitChange(
      user: user(capabilities: const {'teams.manage'}),
      request: request(),
    );

    expect(receipt.status, RosterApprovalStatus.approved);
    expect(receipt.playerId, 'player_1');
  });

  test('operation IDs are opaque and distinct', () {
    final repository = RosterWorkflowRepository(random: Random(7));
    final first = repository.newOperationId(now: DateTime.utc(2026, 9, 11));
    final second = repository.newOperationId(now: DateTime.utc(2026, 9, 11));

    expect(first, isNot(second));
    expect(first, startsWith('roster_'));
    expect(first, isNot(contains('Aaliyah')));
  });
}
