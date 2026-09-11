import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/season_model.dart';
import 'package:hoops_connect/services/repositories/season_repository.dart';

void main() {
  test('stable IDs and date-only validation are deterministic', () async {
    expect(SeasonRepository.stableSeasonId('  NBL 2027 / 28  '), 'nbl-2027-28');
    expect(SeasonRepository.dateOnly(DateTime(2027, 1, 3, 22)), '2027-01-03');

    final repository = SeasonRepository(
      operationStore: _MemoryStore(),
      callable: (_, _) async => throw StateError('must not run'),
    );
    expect(
      () => repository.prepareSeason(
        actorId: 'admin',
        associationId: 'jba',
        name: 'NBL 2027',
        startDate: DateTime(2027, 5, 2),
        endDate: DateTime(2027, 5, 1),
      ),
      throwsArgumentError,
    );
  });

  test('lost response retry reuses the persisted operation ID', () async {
    final store = _MemoryStore();
    final requests = <Map<String, Object?>>[];
    var attempt = 0;
    final repository = SeasonRepository(
      operationStore: store,
      random: Random(7),
      callable: (name, request) async {
        expect(name, 'seasonPrepare');
        requests.add(Map.of(request));
        attempt++;
        if (attempt == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'connection lost',
          );
        }
        return {
          'operationId': request['operationId'],
          'seasonId': 'nbl-2027',
          'status': 'prepared',
          'seasonVersion': 1,
          'currentSeasonId': 'nbl-2026',
        };
      },
    );
    Future<SeasonOperationReceipt> call() => repository.prepareSeason(
      actorId: 'admin',
      associationId: 'jba',
      name: 'NBL 2027',
      startDate: DateTime(2027, 1, 1),
      endDate: DateTime(2027, 9, 1),
    );

    await expectLater(
      call(),
      throwsA(
        isA<SeasonWorkflowException>().having(
          (error) => error.retryable,
          'retryable',
          true,
        ),
      ),
    );
    expect(store.values, hasLength(1));
    final receipt = await call();
    expect(receipt.status, 'prepared');
    expect(requests[1]['operationId'], requests[0]['operationId']);
    expect(store.values, isEmpty);
  });

  test(
    'uncertain request cannot be silently changed before recovery',
    () async {
      final store = _MemoryStore();
      final repository = SeasonRepository(
        operationStore: store,
        callable: (_, _) async => throw StateError('offline'),
      );
      Future<SeasonOperationReceipt> prepare(String name) =>
          repository.prepareSeason(
            actorId: 'admin',
            associationId: 'jba',
            name: name,
            startDate: DateTime(2027, 1, 1),
            endDate: DateTime(2027, 9, 1),
          );
      await expectLater(
        prepare('NBL 2027'),
        throwsA(isA<SeasonWorkflowException>()),
      );
      await expectLater(
        prepare('NBL 2027!'),
        throwsA(
          isA<SeasonWorkflowException>().having(
            (error) => error.retryable,
            'retryable',
            false,
          ),
        ),
      );
    },
  );

  test('activation carries exact current and candidate versions', () async {
    final requests = <Map<String, Object?>>[];
    final repository = SeasonRepository(
      operationStore: _MemoryStore(),
      callable: (name, request) async {
        expect(name, 'seasonActivate');
        requests.add(Map.of(request));
        return {
          'operationId': request['operationId'],
          'seasonId': request['seasonId'],
          'status': 'active',
          'seasonVersion': 4,
          'previousSeasonId': 'nbl-2026',
          'currentSeasonId': 'nbl-2027',
        };
      },
    );
    const season = SeasonModel(
      id: 'nbl-2027',
      associationId: 'jba',
      name: 'NBL 2027',
      startDate: '2027-01-01',
      endDate: '2027-09-01',
      status: SeasonStatus.prepared,
      version: 3,
    );
    final receipt = await repository.activateSeason(
      actorId: 'admin',
      associationId: 'jba',
      season: season,
      currentSeasonId: 'nbl-2026',
    );
    expect(receipt.previousSeasonId, 'nbl-2026');
    expect(requests.single['expectedCurrentSeasonId'], 'nbl-2026');
    expect(requests.single['expectedSeasonVersion'], 3);
  });

  test(
    'malformed receipt remains retryable and does not clear recovery state',
    () async {
      final store = _MemoryStore();
      final repository = SeasonRepository(
        operationStore: store,
        callable: (_, request) async => {
          'operationId': '${request['operationId']}-wrong',
          'seasonId': request['seasonId'],
          'status': 'archived',
          'seasonVersion': 2,
          'currentSeasonId': 'nbl-2026',
        },
      );
      const season = SeasonModel(
        id: 'nbl-2025',
        associationId: 'jba',
        name: 'NBL 2025',
        startDate: '2025-01-01',
        endDate: '2025-09-01',
        status: SeasonStatus.inactive,
        version: 1,
      );
      await expectLater(
        repository.archiveSeason(
          actorId: 'admin',
          associationId: 'jba',
          season: season,
          currentSeasonId: 'nbl-2026',
        ),
        throwsA(
          isA<SeasonWorkflowException>().having(
            (error) => error.retryable,
            'retryable',
            true,
          ),
        ),
      );
      expect(store.values, hasLength(1));
    },
  );

  test(
    'definitive stale-state rejection clears the operation for a reload',
    () async {
      final store = _MemoryStore();
      final repository = SeasonRepository(
        operationStore: store,
        callable: (_, _) async => throw FirebaseFunctionsException(
          code: 'aborted',
          message: 'The current season changed. Reload before continuing.',
        ),
      );
      const season = SeasonModel(
        id: 'nbl-2027',
        associationId: 'jba',
        name: 'NBL 2027',
        startDate: '2027-01-01',
        endDate: '2027-09-01',
        status: SeasonStatus.prepared,
        version: 1,
      );
      await expectLater(
        repository.activateSeason(
          actorId: 'admin',
          associationId: 'jba',
          season: season,
          currentSeasonId: 'nbl-2026',
        ),
        throwsA(
          isA<SeasonWorkflowException>().having(
            (error) => error.retryable,
            'retryable',
            false,
          ),
        ),
      );
      expect(store.values, isEmpty);
    },
  );
}

class _MemoryStore implements SeasonOperationStore {
  final values = <String, SeasonPendingOperation>{};

  @override
  Future<void> clear(String key) async => values.remove(key);

  @override
  Future<SeasonPendingOperation?> load(String key) async => values[key];

  @override
  Future<void> save(SeasonPendingOperation operation) async {
    values[operation.key] = operation;
  }
}
