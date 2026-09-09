import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/fact.dart';
import 'package:hoops_connect/services/local_game_journal/deletion_recovery_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_error.dart';
import 'package:hoops_connect/services/local_game_journal/journal_limits.dart';
import 'package:hoops_connect/services/local_game_journal/journal_migrations.dart';
import 'package:hoops_connect/services/local_game_journal/journal_models.dart';
import 'package:hoops_connect/services/local_game_journal/journal_repository.dart';
import 'package:hoops_connect/services/local_game_journal/journal_store.dart';

import 'journal_test_support.dart';

void main() {
  test(
    'v1 package migration makes assignment integer and separates reducers',
    () async {
      final store = FaultInjectingMemoryStore();
      await store.open();
      final partition = testPartition();
      final currentPackage = testPackage(partition).toContractMap();
      final legacyPackageWithoutChecksum =
          Map<String, Object?>.from(currentPackage)
            ..remove('packageChecksum')
            ..['packageVersion'] = 1
            ..['localSchemaVersion'] = 1
            ..['assignmentVersion'] = '1'
            ..['reducerVersion'] = currentPackage['journalReducerVersion']
            ..remove('journalReducerVersion');
      final legacyPackageChecksum = OfficialStatCanonicalEncoding.sha256Hex(
        legacyPackageWithoutChecksum,
      );
      final legacyPackage = <String, Object?>{
        ...legacyPackageWithoutChecksum,
        'packageChecksum': legacyPackageChecksum,
      };
      final checkpoint =
          LocalWorkspaceCheckpoint.empty(
              partition: partition,
              writerEpoch: 1,
              now: DateTime.utc(2026, 9, 8, 12),
            ).toContractMap()
            ..['localSchemaVersion'] = 1
            ..['preparationPackageChecksum'] = <String, Object?>{
              'state': 'known',
              'value': legacyPackageChecksum,
            };
      final manifest = DeviceJournalDeletionManifest.create(
        manifestId: 'legacy_manifest',
        actorAccountId: partition.actorAccountId,
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 8, 12, 1),
        workspaces: [
          DeviceJournalWorkspaceSummary(
            partition: partition,
            packageChecksum: legacyPackageChecksum,
            deviceSessionId: 'device_1',
            writerEpoch: 1,
            nextLocalSequence: 0,
            unacknowledgedOperations: 0,
            receiptUnknownOperations: 0,
            acceptedOperations: 0,
            reconciliationEvidenceChecksum:
                OfficialStatCanonicalEncoding.sha256Hex(const []),
          ),
        ],
      );
      final legacyManifest = Map<String, Object?>.from(
        manifest.toContractMap(),
      );
      final legacyWorkspaces = (legacyManifest['workspaces']! as List)
          .map((raw) {
            final workspace = Map<String, Object?>.from(raw as Map)
              ..remove('reconciliationEvidenceChecksum')
              // V1 counted retained rows only, so a fully pruned workspace
              // could legitimately have fewer classified operations than its
              // lifetime sequence count.
              ..['nextLocalSequence'] = 1;
            return workspace;
          })
          .toList(growable: false);
      legacyManifest['manifestVersion'] = 1;
      legacyManifest['workspaces'] = legacyWorkspaces;
      legacyManifest.remove('checksum');
      legacyManifest['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(
        legacyManifest,
      );
      final packageKey = 'package/${partition.key}';
      final checkpointKey = 'checkpoint/${partition.key}';
      final indexKey =
          'workspaceIndex/${partition.actorAccountId}/device_1/'
          '${partition.scope.key}/${partition.workspaceId}';
      final manifestKey =
          'deletionManifest/${partition.actorAccountId}/device_1/'
          'legacy_manifest';
      final exportKey = 'recoveryExport/${partition.key}/legacy_archive';
      store.unsafeWrite(
        LocalJournalMigrationRunner.schemaKey,
        _encodeLegacy({
          'appliedMigrations': <Object?>['initial_v1'],
          'schemaVersion': 1,
        }),
      );
      store.unsafeWrite(packageKey, _encodeLegacy(legacyPackage));
      store.unsafeWrite(checkpointKey, _encodeLegacy(checkpoint));
      store.unsafeWrite(
        indexKey,
        _encodeLegacy({
          'deviceSessionId': 'device_1',
          'packageChecksum': legacyPackageChecksum,
          'partition': partition.toContractMap(),
        }),
      );
      store.unsafeWrite(manifestKey, _encodeLegacy(legacyManifest));
      store.unsafeWrite(
        exportKey,
        _encodeLegacy({
          'archiveId': 'legacy_archive',
          'capturedThroughSequence': <String, Object?>{
            'state': 'notApplicable',
            'value': null,
            'reasonCode': 'no_operations',
          },
          'checksum': hashA,
          'exportedAt': DateTime.utc(2026, 9, 8, 12, 2),
          'manifestId': 'legacy_manifest',
          'persistedConfirmation': true,
        }),
      );

      final repository = LocalGameJournalRepository(
        store: store,
        activeActorAccountId: partition.actorAccountId,
        compatibility: testCompatibility(),
      );
      await repository.open();

      final migratedPackage = LocalJournalRecordCodec.decodeVersioned(
        store.unsafeRead(packageKey)!,
      );
      expect(
        migratedPackage.localSchemaVersion,
        LocalGameJournalLimits.localSchemaVersion,
      );
      expect(migratedPackage.payload['assignmentVersion'], 1);
      expect(migratedPackage.payload['journalReducerVersion'], 'reducer_v1');
      expect(migratedPackage.payload, isNot(contains('reducerVersion')));
      final newChecksum = migratedPackage.payload['packageChecksum'];

      final migratedCheckpoint = LocalJournalRecordCodec.decode(
        store.unsafeRead(checkpointKey)!,
      );
      expect(
        migratedCheckpoint['localSchemaVersion'],
        LocalGameJournalLimits.localSchemaVersion,
      );
      expect(
        (migratedCheckpoint['preparationPackageChecksum'] as Map)['value'],
        newChecksum,
      );
      expect(
        LocalJournalRecordCodec.decode(
          store.unsafeRead(indexKey)!,
        )['packageChecksum'],
        newChecksum,
      );
      final migratedManifest = LocalJournalRecordCodec.decode(
        store.unsafeRead(manifestKey)!,
      );
      expect(migratedManifest['manifestVersion'], 1);
      expect(
        (migratedManifest['workspaces'] as List).single['packageChecksum'],
        newChecksum,
      );
      expect(
        () => DeviceJournalDeletionManifest.fromContractMap(migratedManifest),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'legacy consent requires recreation',
            LocalJournalErrorCode.invalidArgument,
          ),
        ),
      );
      expect(
        LocalJournalRecordCodec.decode(
          store.unsafeRead(exportKey)!,
        )['persistedConfirmation'],
        isFalse,
      );
      await expectLater(
        repository.confirmRecoveryArchivePersisted(
          partition,
          archiveId: 'legacy_archive',
          checksum: hashA,
          confirmation: 'recoveryArchivePersisted',
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.unsupportedSchemaVersion,
          ),
        ),
      );
      final schema = LocalJournalRecordCodec.decode(
        store.unsafeRead(LocalJournalMigrationRunner.schemaKey)!,
      );
      expect(
        schema['schemaVersion'],
        LocalGameJournalLimits.localSchemaVersion,
      );
      expect(
        schema['appliedMigrations'],
        contains('local_game_journal_v1_to_v2'),
      );

      final operation = testOperation(
        partition: partition,
        sequence: 0,
        previousHash: const Fact.notApplicable(reasonCode: 'genesis'),
      );
      expect((await repository.append(operation)).savedOnDevice, isTrue);
    },
  );

  test(
    'migration step and version marker roll back together then rerun',
    () async {
      final store = FaultInjectingMemoryStore();
      await store.open();
      await store.transaction((transaction) async {
        await transaction.put(
          LocalJournalMigrationRunner.schemaKey,
          LocalJournalRecordCodec.encodeVersioned({
            'appliedMigrations': <Object?>[],
            'schemaVersion': 1,
          }, localSchemaVersion: 1),
        );
      });
      final steps = [
        LocalJournalMigrationStep(
          migrationId: 'v1_to_v2',
          fromVersion: 1,
          toVersion: 2,
          apply: (context) => context.transaction.put(
            'migrated/value',
            LocalJournalRecordCodec.encode({'value': 'preserved'}),
          ),
        ),
      ];
      store.failAtPut = 2;
      await expectLater(
        LocalJournalMigrationRunner.ensureCurrent(
          store: store,
          targetVersion: 2,
          steps: steps,
        ),
        throwsA(isA<LocalJournalException>()),
      );
      final afterFailure = await store.transaction((transaction) async {
        return (
          await transaction.get(LocalJournalMigrationRunner.schemaKey),
          await transaction.get('migrated/value'),
        );
      });
      expect(
        LocalJournalRecordCodec.decodeVersioned(
          afterFailure.$1!,
        ).payload['schemaVersion'],
        1,
      );
      expect(afterFailure.$2, isNull);

      await LocalJournalMigrationRunner.ensureCurrent(
        store: store,
        targetVersion: 2,
        steps: steps,
      );
      await LocalJournalMigrationRunner.ensureCurrent(
        store: store,
        targetVersion: 2,
        steps: steps,
      );
      final completed = await store.transaction((transaction) async {
        return (
          await transaction.get(LocalJournalMigrationRunner.schemaKey),
          await transaction.get('migrated/value'),
        );
      });
      final state = LocalJournalRecordCodec.decode(completed.$1!);
      expect(state['schemaVersion'], 2);
      expect(state['appliedMigrations'], ['v1_to_v2']);
      expect(
        LocalJournalRecordCodec.decode(completed.$2!)['value'],
        'preserved',
      );
    },
  );

  test('migration can atomically quarantine corrupt legacy bytes', () async {
    final store = FaultInjectingMemoryStore();
    await store.open();
    await store.transaction((transaction) async {
      await transaction.put(
        LocalJournalMigrationRunner.schemaKey,
        LocalJournalRecordCodec.encodeVersioned({
          'appliedMigrations': <Object?>[],
          'schemaVersion': 1,
        }, localSchemaVersion: 1),
      );
      await transaction.put('legacy/corrupt', '{not-json');
    });
    await LocalJournalMigrationRunner.ensureCurrent(
      store: store,
      targetVersion: 2,
      steps: [
        LocalJournalMigrationStep(
          migrationId: 'quarantine_v1',
          fromVersion: 1,
          toVersion: 2,
          apply: (context) => context.quarantineRecord(
            sourceKey: 'legacy/corrupt',
            stableReasonCode: 'invalid_legacy_envelope',
          ),
        ),
      ],
    );
    final records = await store.transaction((transaction) async {
      return (
        await transaction.get('legacy/corrupt'),
        await transaction.scanPrefix('migrationQuarantine/', limit: 10),
      );
    });
    expect(records.$1, isNull);
    expect(records.$2, hasLength(1));
    final quarantine = LocalJournalRecordCodec.decode(records.$2.single.value);
    expect(quarantine['originalBytes'], '{not-json');
    expect(quarantine['reasonCode'], 'invalid_legacy_envelope');
  });

  test('empty storage alone receives a fresh current schema marker', () async {
    final store = FaultInjectingMemoryStore();
    await store.open();

    await LocalJournalMigrationRunner.ensureCurrent(
      store: store,
      targetVersion: LocalGameJournalLimits.localSchemaVersion,
    );

    final decoded = LocalJournalRecordCodec.decodeVersioned(
      store.unsafeRead(LocalJournalMigrationRunner.schemaKey)!,
    );
    expect(
      decoded.localSchemaVersion,
      LocalGameJournalLimits.localSchemaVersion,
    );
    expect(
      decoded.payload['schemaVersion'],
      LocalGameJournalLimits.localSchemaVersion,
    );
  });

  test(
    'missing schema marker rejects known legacy bytes without modifying them',
    () async {
      final store = FaultInjectingMemoryStore();
      await store.open();
      const key = 'entry/legacy_partition/0000000000000000';
      const originalBytes = '{"opaque":"legacy"}';
      store.unsafeWrite(key, originalBytes);
      final repository = LocalGameJournalRepository(
        store: store,
        activeActorAccountId: 'account_1',
        compatibility: testCompatibility(),
      );

      await expectLater(
        repository.open(),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.migrationFailed,
          ),
        ),
      );
      expect(store.unsafeRead(key), originalBytes);
      expect(store.unsafeRead(LocalJournalMigrationRunner.schemaKey), isNull);
      expect(store.capability.captureEnabled, isFalse);
    },
  );

  test(
    'missing schema marker rejects unknown keyspace without losing bytes',
    () async {
      final store = FaultInjectingMemoryStore();
      await store.open();
      const key = 'futureExtension/opaque_record';
      const originalBytes = 'unrecognized-but-preserved';
      store.unsafeWrite(key, originalBytes);

      await expectLater(
        LocalJournalMigrationRunner.ensureCurrent(
          store: store,
          targetVersion: LocalGameJournalLimits.localSchemaVersion,
          steps: LocalGameJournalMigrations.steps,
        ),
        throwsA(isA<LocalJournalException>()),
      );
      expect(store.unsafeRead(key), originalBytes);
      expect(store.unsafeRead(LocalJournalMigrationRunner.schemaKey), isNull);
    },
  );

  test('schema marker rejects mismatched outer and inner versions', () async {
    final store = FaultInjectingMemoryStore();
    await store.open();
    final original = LocalJournalRecordCodec.encodeVersioned({
      'appliedMigrations': <Object?>['initial_v2'],
      'schemaVersion': 2,
    }, localSchemaVersion: 3);
    store.unsafeWrite(LocalJournalMigrationRunner.schemaKey, original);

    await expectLater(
      LocalJournalMigrationRunner.ensureCurrent(
        store: store,
        targetVersion: LocalGameJournalLimits.localSchemaVersion,
        steps: LocalGameJournalMigrations.steps,
      ),
      throwsA(
        isA<LocalJournalException>().having(
          (error) => error.code,
          'code',
          LocalJournalErrorCode.migrationFailed,
        ),
      ),
    );
    expect(store.unsafeRead(LocalJournalMigrationRunner.schemaKey), original);
  });

  test(
    'v1 migration rejects an invalid original deletion manifest checksum',
    () async {
      final store = FaultInjectingMemoryStore();
      await store.open();
      final current = DeviceJournalDeletionManifest.create(
        manifestId: 'legacy_manifest_bad_checksum',
        actorAccountId: 'account_1',
        deviceSessionId: 'device_1',
        createdAt: DateTime.utc(2026, 9, 8),
        workspaces: const [],
      ).toContractMap();
      final valid = Map<String, Object?>.from(current)
        ..['manifestVersion'] = 1
        ..remove('checksum');
      valid['checksum'] = OfficialStatCanonicalEncoding.sha256Hex(valid);
      final invalid = <String, Object?>{...valid, 'checksum': hashA};
      final manifestKey =
          'deletionManifest/account_1/device_1/legacy_manifest_bad_checksum';
      final originalManifestBytes = _encodeLegacy(invalid);
      store.unsafeWrite(
        LocalJournalMigrationRunner.schemaKey,
        _encodeLegacy({
          'appliedMigrations': <Object?>['initial_v1'],
          'schemaVersion': 1,
        }),
      );
      store.unsafeWrite(manifestKey, originalManifestBytes);

      await expectLater(
        LocalJournalMigrationRunner.ensureCurrent(
          store: store,
          targetVersion: LocalGameJournalLimits.localSchemaVersion,
          steps: LocalGameJournalMigrations.steps,
        ),
        throwsA(
          isA<LocalJournalException>().having(
            (error) => error.code,
            'code',
            LocalJournalErrorCode.migrationFailed,
          ),
        ),
      );
      expect(store.unsafeRead(manifestKey), originalManifestBytes);
      final marker = LocalJournalRecordCodec.decodeVersioned(
        store.unsafeRead(LocalJournalMigrationRunner.schemaKey)!,
      );
      expect(marker.localSchemaVersion, 1);
      expect(marker.payload['schemaVersion'], 1);
    },
  );
}

String _encodeLegacy(Map<String, Object?> payload) =>
    OfficialStatCanonicalEncoding.encode({
      'checksum': OfficialStatCanonicalEncoding.sha256Hex(payload),
      'localSchemaVersion': 1,
      'payload': payload,
    });
