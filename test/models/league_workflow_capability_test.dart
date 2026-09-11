import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/league_workflow_capability.dart';

void main() {
  Map<String, dynamic> fixture() => {
    'schemaVersion': 1,
    'associationId': 'jba',
    'competitionId': 'nbl',
    'activeSeasonId': 's2026',
    'defaultPhaseId': 'regular',
    'timezone': 'America/Jamaica',
    'authorityMode': 'legacyV1',
    'callablesReady': true,
    'directWritesDenied': true,
    'lifecycleAuthorityReady': true,
    'custodyAuthorityReady': true,
    'actorAuthorityReady': true,
    'identityAuthorityReady': true,
    'privacyAuthorityReady': true,
    'custodyPolicyVersionV2': 1,
    'privacyEpochV2': 1,
    'rosters': true,
    'divisionDeletion': true,
    'scheduling': true,
  };

  test(
    'requires every server-owned readiness fact before enabling actions',
    () {
      final ready = LeagueWorkflowCapability.fromMap(
        fixture(),
        expectedAssociationId: 'jba',
        clientAuthorizationSchemaVersion: 1,
      );
      expect(ready.schedulingEnabled, isTrue);
      for (final key in [
        'callablesReady',
        'directWritesDenied',
        'lifecycleAuthorityReady',
        'custodyAuthorityReady',
        'actorAuthorityReady',
        'identityAuthorityReady',
        'privacyAuthorityReady',
      ]) {
        final closed = LeagueWorkflowCapability.fromMap(
          {...fixture(), key: false},
          expectedAssociationId: 'jba',
          clientAuthorizationSchemaVersion: 1,
        );
        expect(closed.schedulingEnabled, isFalse, reason: key);
        expect(closed.rosterEnabled, isFalse, reason: key);
        expect(closed.divisionDeletionEnabled, isFalse, reason: key);
      }
      final mismatchedSchema = LeagueWorkflowCapability.fromMap(
        fixture(),
        expectedAssociationId: 'jba',
        clientAuthorizationSchemaVersion: 2,
      );
      expect(mismatchedSchema.schedulingEnabled, isFalse);
    },
  );

  test('fails closed on association, timezone, and authority mismatch', () {
    expect(
      () => LeagueWorkflowCapability.fromMap(
        fixture(),
        expectedAssociationId: 'other',
        clientAuthorizationSchemaVersion: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => LeagueWorkflowCapability.fromMap(
        {...fixture(), 'timezone': 'America/New_York'},
        expectedAssociationId: 'jba',
        clientAuthorizationSchemaVersion: 1,
      ),
      throwsFormatException,
    );
    expect(
      () => LeagueWorkflowCapability.fromMap(
        {...fixture(), 'authorityMode': 'unknown'},
        expectedAssociationId: 'jba',
        clientAuthorizationSchemaVersion: 1,
      ),
      throwsFormatException,
    );
  });
}
