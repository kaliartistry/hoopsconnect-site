import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/player_season_stats_model.dart';
import 'package:hoops_connect/models/roster_workflow_model.dart';

void main() {
  test('jersey is serialized as the exact string including leading zeroes', () {
    final request = RosterChangeRequest(
      operationId: 'operation_1',
      teamId: 'team_1',
      seasonId: 'season_1',
      expectedRosterVersion: 3,
      kind: RosterChangeKind.addPlayer,
      displayName: 'Aaliyah Brown',
      jerseyNumber: '00',
      position: 'Guard',
      reason: 'New registration',
    );

    expect(request.toMap(requestedOutcome: 'propose')['jerseyNumber'], '00');
  });

  test('new player cannot smuggle a client-generated stable identity', () {
    expect(
      () => RosterChangeRequest(
        operationId: 'operation_1',
        teamId: 'team_1',
        seasonId: 'season_1',
        expectedRosterVersion: 0,
        kind: RosterChangeKind.addPlayer,
        playerId: 'name_timestamp',
        displayName: 'Aaliyah Brown',
        jerseyNumber: '0',
        reason: 'New registration',
      ),
      throwsArgumentError,
    );
  });

  test('remove request cannot overwrite player facts', () {
    expect(
      () => RosterChangeRequest(
        operationId: 'operation_1',
        teamId: 'team_1',
        seasonId: 'season_1',
        expectedRosterVersion: 2,
        kind: RosterChangeKind.removePlayer,
        playerId: 'player_1',
        registrationId: 'registration_1',
        displayName: 'Replacement Name',
        reason: 'No longer registered',
      ),
      throwsArgumentError,
    );
  });

  test('rejection requires a review note', () {
    expect(
      () => RosterProposalReviewRequest(
        operationId: 'review_1',
        proposalId: 'proposal_1',
        teamId: 'team_1',
        seasonId: 'season_1',
        expectedRosterVersion: 2,
        decision: RosterProposalDecision.reject,
      ),
      throwsArgumentError,
    );
  });

  test('registration-only player projection omits fabricated aggregates', () {
    final player = PlayerSeasonStatsModel.fromMap(
      id: 'player_1_season_1',
      data: const {
        'playerId': 'player_1',
        'playerName': 'Aaliyah Brown',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'jerseyNumber': '00',
      },
    );

    expect(player.hasAggregateData, isFalse);
    expect(player.jerseyNumber, '00');
    expect(player.toFirestore(), isNot(contains('gamesPlayed')));
    expect(player.toFirestore(), isNot(contains('totals')));
  });

  test('proposal requires immutable before and after facts for its kind', () {
    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_1',
        'kind': 'updatePlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'Correct jersey',
        'requestedByName': 'Team Rep',
        'after': {
          'playerId': 'player_1',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '00',
        },
      }),
      throwsArgumentError,
    );
  });

  test('proposal preserves exact before and after facts for review', () {
    final proposal = RosterProposalSummary.fromMap(const {
      'proposalId': 'proposal_2',
      'kind': 'updatePlayer',
      'status': 'pending',
      'teamId': 'team_1',
      'seasonId': 'season_1',
      'reason': 'Correct jersey',
      'requestedByName': 'Team Rep',
      'before': {
        'playerId': 'player_1',
        'registrationId': 'registration_1',
        'displayName': 'Aaliyah Brown',
        'jerseyNumber': '0',
        'position': 'Forward',
      },
      'after': {
        'playerId': 'player_1',
        'registrationId': 'registration_1',
        'displayName': 'Aaliyah Brown',
        'jerseyNumber': '00',
        'position': 'Guard',
      },
    });

    expect(proposal.before!.jerseyNumber, '0');
    expect(proposal.after!.jerseyNumber, '00');
    expect(proposal.after!.position, 'Guard');
    expect(proposal.reason, 'Correct jersey');
  });

  test('add proposal rejects client-assigned canonical identity', () {
    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_add',
        'kind': 'addPlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'New registration',
        'requestedByName': 'Team Rep',
        'after': {
          'playerId': 'player_1',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '00',
        },
      }),
      throwsArgumentError,
    );
  });

  test('update proposal requires identical canonical identities', () {
    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_update',
        'kind': 'updatePlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'Correct registration',
        'requestedByName': 'Team Rep',
        'before': {
          'playerId': 'player_1',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '0',
        },
        'after': {
          'playerId': 'player_2',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '00',
        },
      }),
      throwsArgumentError,
    );

    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_update_registration',
        'kind': 'updatePlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'Correct registration',
        'requestedByName': 'Team Rep',
        'before': {
          'playerId': 'player_1',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '0',
        },
        'after': {
          'playerId': 'player_1',
          'registrationId': 'registration_2',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '00',
        },
      }),
      throwsArgumentError,
    );
  });

  test('update proposal requires canonical IDs on both fact snapshots', () {
    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_update_missing_ids',
        'kind': 'updatePlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'Correct jersey',
        'requestedByName': 'Team Rep',
        'before': {
          'playerId': 'player_1',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '0',
        },
        'after': {'displayName': 'Aaliyah Brown', 'jerseyNumber': '00'},
      }),
      throwsArgumentError,
    );
  });

  test('remove proposal requires canonical identity in before facts', () {
    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_remove',
        'kind': 'removePlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'No longer registered',
        'requestedByName': 'Team Rep',
        'before': {'displayName': 'Aaliyah Brown', 'jerseyNumber': '0'},
      }),
      throwsArgumentError,
    );
  });

  test('direct proposal construction rejects one-sided canonical identity', () {
    expect(
      () => RosterProposalSummary(
        proposalId: 'proposal_direct',
        kind: RosterChangeKind.updatePlayer,
        status: RosterApprovalStatus.pending,
        teamId: 'team_1',
        seasonId: 'season_1',
        before: const RosterPlayerFacts(
          playerId: 'player_1',
          displayName: 'Aaliyah Brown',
          jerseyNumber: '0',
        ),
        after: const RosterPlayerFacts(
          playerId: 'player_1',
          registrationId: 'registration_1',
          displayName: 'Aaliyah Brown',
          jerseyNumber: '00',
        ),
        reason: 'Correct jersey',
        requestedByName: 'Team Rep',
      ),
      throwsArgumentError,
    );
  });

  test('proposal decoding rejects nested facts with the wrong shape', () {
    expect(
      () => RosterProposalSummary.fromMap(const {
        'proposalId': 'proposal_wrong_shape',
        'kind': 'updatePlayer',
        'status': 'pending',
        'teamId': 'team_1',
        'seasonId': 'season_1',
        'reason': 'Correct jersey',
        'requestedByName': 'Team Rep',
        'before': <Object>[],
        'after': {
          'playerId': 'player_1',
          'registrationId': 'registration_1',
          'displayName': 'Aaliyah Brown',
          'jerseyNumber': '00',
        },
      }),
      throwsFormatException,
    );
  });

  test('canonical registration count overrides stale legacy aggregates', () {
    expect(
      preferredRosterPlayerCount(
        canonicalWorkspace: const RosterWorkspace(rosterVersion: 1),
        legacyAggregateCount: 7,
      ),
      0,
    );
  });
}
