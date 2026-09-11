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
      );
      expect(ready.schedulingEnabled, isTrue);
      for (final key in [
        'callablesReady',
        'directWritesDenied',
        'lifecycleAuthorityReady',
        'custodyAuthorityReady',
      ]) {
        final closed = LeagueWorkflowCapability.fromMap({
          ...fixture(),
          key: false,
        }, expectedAssociationId: 'jba');
        expect(closed.schedulingEnabled, isFalse, reason: key);
        expect(closed.rosterEnabled, isFalse, reason: key);
        expect(closed.divisionDeletionEnabled, isFalse, reason: key);
      }
    },
  );

  test('fails closed on association, timezone, and authority mismatch', () {
    expect(
      () => LeagueWorkflowCapability.fromMap(
        fixture(),
        expectedAssociationId: 'other',
      ),
      throwsFormatException,
    );
    expect(
      () => LeagueWorkflowCapability.fromMap({
        ...fixture(),
        'timezone': 'America/New_York',
      }, expectedAssociationId: 'jba'),
      throwsFormatException,
    );
    expect(
      () => LeagueWorkflowCapability.fromMap({
        ...fixture(),
        'authorityMode': 'unknown',
      }, expectedAssociationId: 'jba'),
      throwsFormatException,
    );
  });
}
