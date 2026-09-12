import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_release_gate_ledger.dart';

void main() {
  Map<String, Object?> fixture() => Map<String, Object?>.from(
    jsonDecode(
          File(
            'contracts/account_deletion/v1/release_gates.json',
          ).readAsStringSync(),
        )
        as Map,
  );

  test('normative G1-G11 ledger remains explicitly closed', () {
    final ledger = AccountDeletionReleaseGateLedger.fromMap(fixture());

    expect(
      ledger.gates.map((gate) => gate.id),
      AccountDeletionReleaseGateLedger.expectedGateIds,
    );
    expect(ledger.activationAllowed, isFalse);
    expect(ledger.allPassed, isFalse);
    expect(ledger.candidateRemainsClosed, isTrue);
    expect(ledger.unresolvedEvidence.keys, {
      'G1',
      'G2',
      'G3',
      'G4',
      'G5',
      'G6',
      'G7',
      'G8',
      'G9',
      'G10',
      'G11',
    });
    for (final gate in ledger.gates) {
      expect(gate.owner, isNull, reason: gate.id);
      expect(gate.evidenceRefs, isEmpty, reason: gate.id);
      expect(gate.passed, isFalse, reason: gate.id);
      expect(gate.requiredEvidence, isNotEmpty, reason: gate.id);
    }
  });

  test('activation cannot hide a closed gate', () {
    final changed = fixture()..['activationAllowed'] = true;

    expect(
      () => AccountDeletionReleaseGateLedger.fromMap(changed),
      throwsFormatException,
    );
  });

  test('a deliberately disabled all-passed ledger still remains closed', () {
    final changed = fixture();
    for (final gate in changed['gates']! as List<Object?>) {
      final row = gate! as Map<String, Object?>;
      row
        ..['status'] = 'passed'
        ..['owner'] = 'review_owner'
        ..['evidenceRefs'] = <Object?>[
          for (final requirement in row['requiredEvidence']! as List<Object?>)
            'evidence_for_$requirement',
        ]
        ..['passed'] = true;
    }

    final ledger = AccountDeletionReleaseGateLedger.fromMap(changed);

    expect(ledger.allPassed, isTrue);
    expect(ledger.activationAllowed, isFalse);
    expect(ledger.candidateRemainsClosed, isTrue);
  });

  test('passed status requires owner and evidence', () {
    final changed = fixture();
    final gates = (changed['gates']! as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    gates[0] = {...gates[0], 'status': 'passed', 'passed': true};
    changed['gates'] = gates;

    expect(
      () => AccountDeletionReleaseGateLedger.fromMap(changed),
      throwsFormatException,
    );
  });

  test('passed status requires complete ordered evidence coverage', () {
    final changed = fixture();
    final rows = (changed['gates']! as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    rows[0] = {
      ...rows[0],
      'status': 'passed',
      'owner': 'review_owner',
      'evidenceRefs': ['only_one_reference'],
      'passed': true,
    };
    changed['gates'] = rows;

    expect(
      () => AccountDeletionReleaseGateLedger.fromMap(changed),
      throwsFormatException,
    );
  });

  test('closed status cannot carry evidence beyond its requirements', () {
    final changed = fixture();
    final rows = (changed['gates']! as List)
        .map((value) => Map<String, Object?>.from(value as Map))
        .toList();
    rows[0] = {
      ...rows[0],
      'evidenceRefs': [
        'controller_reference',
        'decision_maker_reference',
        'retention_reference',
        'disclosures_reference',
        'unexpected_extra_reference',
      ],
    };
    changed['gates'] = rows;

    expect(
      () => AccountDeletionReleaseGateLedger.fromMap(changed),
      throwsFormatException,
    );
  });

  test(
    'exact gate names, closed statuses and evidence requirements are pinned',
    () {
      for (final mutation
          in <Map<String, Object?> Function(Map<String, Object?>)>[
            (row) => {...row, 'name': 'renamed_gate'},
            (row) => {...row, 'status': 'closedPendingOperationalProof'},
            (row) => {
              ...row,
              'requiredEvidence': [
                ...(row['requiredEvidence']! as List<Object?>).skip(1),
              ],
            },
            (row) => {
              ...row,
              'requiredEvidence': [
                ...(row['requiredEvidence']! as List<Object?>).reversed,
              ],
            },
          ]) {
        final changed = fixture();
        final rows = (changed['gates']! as List)
            .map((value) => Map<String, Object?>.from(value as Map))
            .toList();
        rows[0] = mutation(rows[0]);
        changed['gates'] = rows;
        expect(
          () => AccountDeletionReleaseGateLedger.fromMap(changed),
          throwsFormatException,
        );
      }
    },
  );

  test('missing, reordered, duplicate and expanded rows fail closed', () {
    for (final mutate in <void Function(List<Map<String, Object?>>)>[
      (rows) => rows.removeLast(),
      (rows) {
        final first = rows.removeAt(0);
        rows.insert(1, first);
      },
      (rows) => rows[1] = {...rows[1], 'id': 'G1'},
      (rows) => rows[0] = {...rows[0], 'unexpected': true},
    ]) {
      final changed = fixture();
      final rows = (changed['gates']! as List)
          .map((value) => Map<String, Object?>.from(value as Map))
          .toList();
      mutate(rows);
      changed['gates'] = rows;
      expect(
        () => AccountDeletionReleaseGateLedger.fromMap(changed),
        throwsFormatException,
      );
    }
  });
}
