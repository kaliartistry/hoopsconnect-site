import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/services/repositories/division_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestFunctionsException extends FirebaseFunctionsException {
  _TestFunctionsException({
    required super.code,
    required super.message,
    super.details,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'protected division deletion survives repository restart and clears only after a matching terminal receipt',
    () async {
      Map<String, Object?>? firstRequest;
      final firstRepository = DivisionRepository(
        random: Random(7),
        callable: (name, request) async {
          expect(name, 'deleteDivisionIfUnreferenced');
          firstRequest = Map<String, Object?>.from(request);
          throw StateError('simulated lost response');
        },
      );

      await expectLater(
        firstRepository.deleteIfUnreferenced(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
          expectedDivisionVersion: 7,
        ),
        throwsStateError,
      );
      final saved = await firstRepository.pendingDeleteOperation(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
      );
      expect(saved, isNotNull);
      final savedOperation = saved!;
      expect(savedOperation.operationId, firstRequest!['operationId']);
      expect(savedOperation.expectedDivisionVersion, 7);
      expect(
        await firstRepository.pendingDeleteOperation(
          actorId: 'actor-2',
          associationId: 'jba',
          divisionId: 'premier',
        ),
        isNull,
      );

      var terminalReceiptReady = false;
      final restartedRepository = DivisionRepository(
        random: Random(99),
        callable: (name, request) async {
          expect(request['operationId'], savedOperation.operationId);
          if (!terminalReceiptReady) {
            return {
              'operationId': 'wrong-operation',
              'status': 'deleted',
              'divisionVersion': 7,
            };
          }
          return {
            'operationId': savedOperation.operationId,
            'status': 'deleted',
            'divisionVersion': 7,
          };
        },
      );
      await expectLater(
        restartedRepository.deleteIfUnreferenced(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
          expectedDivisionVersion: 7,
        ),
        throwsFormatException,
      );
      expect(
        await restartedRepository.pendingDeleteOperation(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
        ),
        isNotNull,
      );

      terminalReceiptReady = true;
      final receipt = await restartedRepository.deleteIfUnreferenced(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
        expectedDivisionVersion: 7,
      );
      expect(receipt.deleted, isTrue);
      expect(receipt.operationId, savedOperation.operationId);
      expect(
        await restartedRepository.pendingDeleteOperation(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
        ),
        isNull,
      );
    },
  );

  test('saved deletion version cannot be silently replaced', () async {
    final repository = DivisionRepository(
      random: Random(11),
      callable: (_, _) async => throw StateError('offline'),
    );
    await expectLater(
      repository.deleteIfUnreferenced(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
        expectedDivisionVersion: 7,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.deleteIfUnreferenced(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
        expectedDivisionVersion: 8,
      ),
      throwsStateError,
    );
    expect(
      (await repository.pendingDeleteOperation(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
      ))?.expectedDivisionVersion,
      7,
    );
  });

  test(
    'definitive stale rejection survives restart and requires proof-bound rebase',
    () async {
      final firstRepository = DivisionRepository(
        random: Random(21),
        callable: (_, request) async {
          throw _TestFunctionsException(
            code: 'aborted',
            message: 'The division changed. Reload it before deleting.',
            details: {
              'schemaVersion': 1,
              'reason': 'division-version-mismatch',
              'actorId': 'actor-1',
              'associationId': 'jba',
              'operationId': request['operationId'],
              'divisionId': 'premier',
              'expectedDivisionVersion': 7,
              'currentDivisionVersion': 8,
            },
          );
        },
      );
      await expectLater(
        firstRepository.deleteIfUnreferenced(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
          expectedDivisionVersion: 7,
        ),
        throwsA(isA<DivisionDeleteStaleVersionException>()),
      );
      final stale = await firstRepository.pendingDeleteOperation(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
      );
      expect(stale?.expectedDivisionVersion, 7);
      expect(stale?.definitiveStaleVersion, 8);

      Map<String, Object?>? recoveredRequest;
      final restartedRepository = DivisionRepository(
        random: Random(22),
        callable: (_, request) async {
          recoveredRequest = Map<String, Object?>.from(request);
          return {
            'operationId': request['operationId'],
            'status': 'deleted',
            'divisionVersion': 8,
          };
        },
      );
      await expectLater(
        restartedRepository.deleteIfUnreferenced(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
          expectedDivisionVersion: 8,
        ),
        throwsA(isA<DivisionDeleteStaleVersionException>()),
      );
      await expectLater(
        restartedRepository.rebaseDefinitiveStaleVersion(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
          currentDivisionVersion: 9,
        ),
        throwsStateError,
      );
      final rebased = await restartedRepository.rebaseDefinitiveStaleVersion(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
        currentDivisionVersion: 8,
      );
      expect(rebased.operationId, isNot(stale?.operationId));
      expect(rebased.expectedDivisionVersion, 8);
      expect(rebased.definitiveStaleVersion, isNull);
      final receipt = await restartedRepository.deleteIfUnreferenced(
        actorId: 'actor-1',
        associationId: 'jba',
        divisionId: 'premier',
        expectedDivisionVersion: 8,
      );
      expect(receipt.deleted, isTrue);
      expect(recoveredRequest?['operationId'], rebased.operationId);
      expect(
        await restartedRepository.pendingDeleteOperation(
          actorId: 'actor-1',
          associationId: 'jba',
          divisionId: 'premier',
        ),
        isNull,
      );
    },
  );

  test('legacy zero division version is valid and recoverable', () async {
    final operation = DivisionDeleteOperation.fromMap({
      'schemaVersion': 1,
      'actorId': 'actor-1',
      'associationId': 'jba',
      'divisionId': 'legacy',
      'expectedDivisionVersion': 0,
      'operationId': 'operation_zero_1',
    });
    expect(operation.expectedDivisionVersion, 0);
    final repository = DivisionRepository(
      random: Random(31),
      callable: (_, request) async => {
        'operationId': request['operationId'],
        'status': 'deleted',
        'divisionVersion': 0,
      },
    );
    final receipt = await repository.deleteIfUnreferenced(
      actorId: 'actor-1',
      associationId: 'jba',
      divisionId: 'legacy',
      expectedDivisionVersion: 0,
    );
    expect(receipt.deleted, isTrue);
    expect(receipt.divisionVersion, 0);
  });
}
