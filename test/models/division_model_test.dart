import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/division_model.dart';
import 'package:hoops_connect/services/repositories/division_repository.dart';

void main() {
  test('legacy divisions default to active', () {
    final division = DivisionModel.fromMap(
      id: 'premier',
      data: const {'name': 'Premier'},
    );

    expect(division.status, DivisionStatus.active);
    expect(division.isArchived, isFalse);
    expect(division.version, 0);
  });

  test(
    'new division writes start at version one and preserve explicit versions',
    () {
      const created = DivisionModel(id: 'new', name: 'New');
      expect(created.toFirestore()['version'], 1);
      final existing = DivisionModel.fromMap(
        id: 'existing',
        data: const {'name': 'Existing', 'status': 'active', 'version': 7},
      );
      expect(existing.version, 7);
      expect(existing.toFirestore()['version'], 7);
    },
  );

  test('archived division round-trips its lifecycle state', () {
    final division = DivisionModel.fromMap(
      id: 'development',
      data: const {'name': 'Development', 'status': 'archived'},
    );

    expect(division.isArchived, isTrue);
    expect(division.toFirestore()['status'], 'archived');
  });

  test('unknown explicit division status fails closed', () {
    expect(
      () => DivisionModel.fromMap(
        id: 'premier',
        data: const {'name': 'Premier', 'status': 'deleted-ish'},
      ),
      throwsFormatException,
    );
  });

  test('dependency report names reference classes and blocks deletion', () {
    const report = DivisionDependencyReport(
      teamReferences: [
        DivisionReference(
          kind: DivisionReferenceKind.team,
          id: 'team_1',
          path: 'associations/jba/teams/team_1',
          displayName: 'Kingston Lions',
        ),
      ],
      eventReferences: [
        DivisionReference(
          kind: DivisionReferenceKind.event,
          id: 'event_1',
          path: 'associations/jba/events/event_1',
          displayName: 'Lions vs Storm',
        ),
      ],
    );

    expect(report.hasReferences, isTrue);
    expect(report.totalReferences, 2);
    expect(report.summary, '1 team and 1 scheduled event');
  });

  test('malformed dependency names retain an explicit blocking label', () {
    expect(
      divisionReferenceDisplayName(const {
        'unexpected': 'shape',
      }, fallback: 'Unnamed team (team_bad)'),
      'Unnamed team (team_bad)',
    );
    expect(
      divisionReferenceDisplayName(
        '   ',
        fallback: 'Untitled event (event_bad)',
      ),
      'Untitled event (event_bad)',
    );
  });
}
