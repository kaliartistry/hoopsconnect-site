import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/services/repositories/division_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
