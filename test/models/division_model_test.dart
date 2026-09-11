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
  });

  test('archived division round-trips its lifecycle state', () {
    final division = DivisionModel.fromMap(
      id: 'development',
      data: const {'name': 'Development', 'status': 'archived'},
    );

    expect(division.isArchived, isTrue);
    expect(division.toFirestore()['status'], 'archived');
  });

  test('dependency report names reference classes and blocks deletion', () {
    const report = DivisionDependencyReport(
      teamNames: ['Kingston Lions'],
      eventTitles: ['Lions vs Storm'],
    );

    expect(report.canDelete, isFalse);
    expect(report.totalReferences, 2);
    expect(report.summary, '1 team and 1 scheduled event');
  });
}
