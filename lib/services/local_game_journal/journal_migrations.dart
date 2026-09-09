import '../../models/official_stats/canonical_encoding.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_models.dart';
import 'journal_store.dart';
import 'journal_validation.dart';

typedef LocalJournalMigrationAction =
    Future<void> Function(LocalJournalMigrationContext context);

final class LocalJournalMigrationStep {
  final String migrationId;
  final int fromVersion;
  final int toVersion;
  final LocalJournalMigrationAction apply;

  const LocalJournalMigrationStep({
    required this.migrationId,
    required this.fromVersion,
    required this.toVersion,
    required this.apply,
  });
}

final class LocalJournalMigrationContext {
  final LocalJournalStoreTransaction transaction;
  final String migrationId;

  const LocalJournalMigrationContext({
    required this.transaction,
    required this.migrationId,
  });

  /// Moves an unreadable/unsupported record out of the active keyspace while
  /// preserving its exact bytes and provenance for deliberate recovery.
  Future<void> quarantineRecord({
    required String sourceKey,
    required String stableReasonCode,
  }) async {
    final value = await transaction.get(sourceKey);
    if (value == null) return;
    final quarantineId = OfficialStatCanonicalEncoding.sha256Hex({
      'migrationId': migrationId,
      'sourceKey': sourceKey,
    });
    await transaction.put(
      'migrationQuarantine/$quarantineId',
      LocalJournalRecordCodec.encode({
        'migrationId': migrationId,
        'originalBytes': value,
        'reasonCode': stableReasonCode,
        'sourceKey': sourceKey,
      }),
    );
    await transaction.delete(sourceKey);
  }
}

/// Reviewed logical schema migrations for device-local journal records.
///
/// Schema v2 makes assignment versions positive integers and gives the
/// reducer and calculator independent preparation-package fields. The step
/// also rewrites every v1 record envelope so no mixed-version active keyspace
/// can survive a successful transaction.
abstract final class LocalGameJournalMigrations {
  static final List<LocalJournalMigrationStep> steps = List.unmodifiable([
    LocalJournalMigrationStep(
      migrationId: 'local_game_journal_v1_to_v2',
      fromVersion: 1,
      toVersion: 2,
      apply: _migrateV1ToV2,
    ),
  ]);

  static Future<void> _migrateV1ToV2(
    LocalJournalMigrationContext context,
  ) async {
    final checksumMigrations = <String, String>{};
    String? cursor;
    do {
      final rows = await context.transaction.scanPrefix(
        'package/',
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        final decoded = LocalJournalRecordCodec.decodeVersioned(row.value);
        if (decoded.localSchemaVersion != 1) {
          throw LocalJournalException(
            LocalJournalErrorCode.migrationFailed,
            'Package record is not at the migration source version',
          );
        }
        final oldChecksum = LocalJournalValidation.requireHash(
          'packageChecksum',
          decoded.payload['packageChecksum'],
        );
        final migrated = _migratePackage(decoded.payload);
        final newChecksum = migrated['packageChecksum']! as String;
        checksumMigrations[oldChecksum] = newChecksum;
        await context.transaction.put(
          row.key,
          LocalJournalRecordCodec.encode(migrated),
        );
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);

    cursor = null;
    do {
      final rows = await context.transaction.scanPrefix(
        '',
        startAfter: cursor,
        limit: LocalGameJournalLimits.integrityScanPageSize,
      );
      for (final row in rows) {
        if (row.key == LocalJournalMigrationRunner.schemaKey ||
            row.key.startsWith('package/')) {
          continue;
        }
        final decoded = LocalJournalRecordCodec.decodeVersioned(row.value);
        if (decoded.localSchemaVersion != 1) {
          throw LocalJournalException(
            LocalJournalErrorCode.migrationFailed,
            'Journal record is not at the migration source version',
            {'recordKey': row.key},
          );
        }
        var payload = Map<String, Object?>.from(decoded.payload);
        if (row.key.startsWith('checkpoint/')) {
          payload = _migrateCheckpoint(payload, checksumMigrations);
        } else if (row.key.startsWith('workspaceIndex/')) {
          payload = _migrateWorkspaceIndex(payload, checksumMigrations);
        } else if (row.key.startsWith('deletionManifest/')) {
          payload = _migrateDeletionManifest(payload, checksumMigrations);
        } else if (row.key.startsWith('recoveryExport/')) {
          // A v1 archive embeds a v1 package/checkpoint and is intentionally
          // rejected by v2 readers. Preserve its audit record and checksum,
          // but require a new importable v2 export before any later prune.
          payload = <String, Object?>{
            ...payload,
            'localSchemaVersion': 1,
            'persistedConfirmation': false,
            'reexportRequired': true,
          };
        }
        await context.transaction.put(
          row.key,
          LocalJournalRecordCodec.encode(payload),
        );
      }
      cursor = rows.length < LocalGameJournalLimits.integrityScanPageSize
          ? null
          : rows.last.key;
    } while (cursor != null);
  }

  static Map<String, Object?> _migratePackage(Map<String, Object?> legacy) {
    const legacyKeys = {
      'packageVersion',
      'localSchemaVersion',
      'packageId',
      'partition',
      'deviceSessionId',
      'writerEpoch',
      'operationSchemaVersion',
      'reducerVersion',
      'calculatorVersion',
      'rulesProfileId',
      'competitionPolicyVersion',
      'assignmentId',
      'assignmentVersion',
      'rosterSnapshotId',
      'rosterSnapshotHash',
      'acceptedServerSequence',
      'acceptedJournalHead',
      'acceptedJournalHash',
      'preparedAt',
      'packageChecksum',
    };
    LocalJournalValidation.exactKeys(legacy, legacyKeys);
    if (legacy['packageVersion'] != 1 || legacy['localSchemaVersion'] != 1) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Prepared package does not match the v1 source contract',
      );
    }
    final withoutOldChecksum = Map<String, Object?>.from(legacy)
      ..remove('packageChecksum');
    final oldChecksum = LocalJournalValidation.requireHash(
      'packageChecksum',
      legacy['packageChecksum'],
    );
    if (OfficialStatCanonicalEncoding.sha256Hex(withoutOldChecksum) !=
        oldChecksum) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Legacy prepared package checksum does not match',
      );
    }

    final rawAssignmentVersion = legacy['assignmentVersion'];
    final int assignmentVersion;
    if (rawAssignmentVersion is int) {
      assignmentVersion = LocalJournalValidation.requireSafeInteger(
        'assignmentVersion',
        rawAssignmentVersion,
        minimum: 1,
      );
    } else if (rawAssignmentVersion is String) {
      final parsed = int.tryParse(rawAssignmentVersion);
      if (parsed == null || parsed.toString() != rawAssignmentVersion) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Legacy assignment version is not a canonical positive integer',
        );
      }
      assignmentVersion = LocalJournalValidation.requireSafeInteger(
        'assignmentVersion',
        parsed,
        minimum: 1,
      );
    } else {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Legacy assignment version has an unsupported type',
      );
    }

    final migratedWithoutChecksum =
        Map<String, Object?>.from(withoutOldChecksum)
          ..['packageVersion'] =
              LocalGameJournalLimits.preparedGamePackageVersion
          ..['localSchemaVersion'] = LocalGameJournalLimits.localSchemaVersion
          ..['assignmentVersion'] = assignmentVersion
          ..['journalReducerVersion'] = legacy['reducerVersion']
          ..remove('reducerVersion');
    final migrated = <String, Object?>{
      ...migratedWithoutChecksum,
      'packageChecksum': OfficialStatCanonicalEncoding.sha256Hex(
        migratedWithoutChecksum,
      ),
    };
    return PreparedGameRecoveryPackage.fromContractMap(
      migrated,
    ).toContractMap();
  }

  static Map<String, Object?> _migrateCheckpoint(
    Map<String, Object?> legacy,
    Map<String, String> checksumMigrations,
  ) {
    if (legacy['localSchemaVersion'] != 1) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Checkpoint does not match the v1 source contract',
      );
    }
    final migrated = Map<String, Object?>.from(legacy)
      ..['localSchemaVersion'] = LocalGameJournalLimits.localSchemaVersion;
    final rawFact = migrated['preparationPackageChecksum'];
    if (rawFact is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.mutatedRecord,
        'Legacy checkpoint package binding is malformed',
      );
    }
    final fact = Map<String, Object?>.from(rawFact);
    if (fact['state'] == 'known') {
      final oldChecksum = fact['value'];
      final newChecksum = checksumMigrations[oldChecksum];
      if (newChecksum == null) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Legacy checkpoint references an unavailable package',
        );
      }
      migrated['preparationPackageChecksum'] = <String, Object?>{
        ...fact,
        'value': newChecksum,
      };
    }
    return LocalWorkspaceCheckpoint.fromContractMap(migrated).toContractMap();
  }

  static Map<String, Object?> _migrateWorkspaceIndex(
    Map<String, Object?> legacy,
    Map<String, String> checksumMigrations,
  ) {
    final oldChecksum = legacy['packageChecksum'];
    final newChecksum = checksumMigrations[oldChecksum];
    if (newChecksum == null) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Legacy workspace index references an unavailable package',
      );
    }
    return <String, Object?>{...legacy, 'packageChecksum': newChecksum};
  }

  static Map<String, Object?> _migrateDeletionManifest(
    Map<String, Object?> legacy,
    Map<String, String> checksumMigrations,
  ) {
    // Validate the original inner contract and checksum before touching any
    // package binding. A migration must never "repair" compromised evidence
    // by calculating a new checksum around already-mutated legacy bytes.
    _validateLegacyDeletionManifest(legacy);
    final rawWorkspaces = legacy['workspaces'];
    if (rawWorkspaces is! List) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Legacy deletion manifest workspace list is malformed',
      );
    }
    final workspaces = rawWorkspaces
        .map<Object?>((raw) {
          if (raw is! Map) {
            throw LocalJournalException(
              LocalJournalErrorCode.migrationFailed,
              'Legacy deletion manifest workspace is malformed',
            );
          }
          final workspace = Map<String, Object?>.from(raw);
          final newChecksum = checksumMigrations[workspace['packageChecksum']];
          if (newChecksum == null) {
            throw LocalJournalException(
              LocalJournalErrorCode.migrationFailed,
              'Legacy deletion manifest references an unavailable package',
            );
          }
          return <String, Object?>{
            ...workspace,
            'packageChecksum': newChecksum,
          };
        })
        .toList(growable: false);
    final withoutChecksum = Map<String, Object?>.from(legacy)
      ..['workspaces'] = workspaces
      ..remove('checksum');
    // Keep the inner manifest at v1. Its consent did not bind operation
    // identities, so it must remain deliberately unparseable by the v2 model
    // and be recreated with fresh operator consent.
    return <String, Object?>{
      ...withoutChecksum,
      'checksum': OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum),
    };
  }

  static void _validateLegacyDeletionManifest(Map<String, Object?> legacy) {
    LocalJournalValidation.exactKeys(legacy, const {
      'manifestVersion',
      'manifestId',
      'actorAccountId',
      'deviceSessionId',
      'createdAt',
      'workspaces',
      'serverDeletionContinuesIndependently',
      'consentInheritedAcrossDevices',
      'deletionStatusCanRecoverJournalContent',
      'checksum',
    });
    if (legacy['manifestVersion'] != 1 ||
        legacy['serverDeletionContinuesIndependently'] != true ||
        legacy['consentInheritedAcrossDevices'] != false ||
        legacy['deletionStatusCanRecoverJournalContent'] != false) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Legacy deletion manifest safety invariants are invalid',
      );
    }
    final actorAccountId = LocalJournalValidation.requireId(
      'actorAccountId',
      legacy['actorAccountId'],
    );
    final deviceSessionId = LocalJournalValidation.requireId(
      'deviceSessionId',
      legacy['deviceSessionId'],
    );
    LocalJournalValidation.requireId('manifestId', legacy['manifestId']);
    LocalJournalValidation.requireTimestamp('createdAt', legacy['createdAt']);
    LocalJournalValidation.requireHash('checksum', legacy['checksum']);
    final rawWorkspaces = legacy['workspaces'];
    if (rawWorkspaces is! List) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Legacy deletion manifest workspace list is malformed',
      );
    }
    var previousPartitionKey = '';
    for (final raw in rawWorkspaces) {
      if (raw is! Map) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Legacy deletion manifest workspace is malformed',
        );
      }
      final workspace = Map<String, Object?>.from(raw);
      LocalJournalValidation.exactKeys(workspace, const {
        'acceptedOperations',
        'deviceSessionId',
        'nextLocalSequence',
        'packageChecksum',
        'partition',
        'receiptUnknownOperations',
        'unacknowledgedOperations',
        'writerEpoch',
      });
      final rawPartition = workspace['partition'];
      if (rawPartition is! Map) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Legacy deletion manifest partition is malformed',
        );
      }
      final partition = JournalPartition.fromContractMap(
        Map<String, Object?>.from(rawPartition),
      );
      final workspaceDevice = LocalJournalValidation.requireId(
        'deviceSessionId',
        workspace['deviceSessionId'],
      );
      LocalJournalValidation.requireHash(
        'packageChecksum',
        workspace['packageChecksum'],
      );
      LocalJournalValidation.requireSafeInteger(
        'writerEpoch',
        workspace['writerEpoch'],
      );
      final next = LocalJournalValidation.requireSafeInteger(
        'nextLocalSequence',
        workspace['nextLocalSequence'],
      );
      final unacknowledged = LocalJournalValidation.requireSafeInteger(
        'unacknowledgedOperations',
        workspace['unacknowledgedOperations'],
      );
      final unknown = LocalJournalValidation.requireSafeInteger(
        'receiptUnknownOperations',
        workspace['receiptUnknownOperations'],
      );
      final accepted = LocalJournalValidation.requireSafeInteger(
        'acceptedOperations',
        workspace['acceptedOperations'],
      );
      if (partition.actorAccountId != actorAccountId ||
          workspaceDevice != deviceSessionId ||
          partition.key.compareTo(previousPartitionKey) <= 0 ||
          unacknowledged + accepted > next ||
          unknown > unacknowledged) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Legacy deletion manifest workspace invariants are invalid',
        );
      }
      previousPartitionKey = partition.key;
    }
    final withoutChecksum = Map<String, Object?>.from(legacy)
      ..remove('checksum');
    if (OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum) !=
        legacy['checksum']) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Legacy deletion manifest checksum does not match',
      );
    }
  }
}

/// Restart-safe logical migration runner shared by SQLite and IndexedDB.
///
/// Each step and its version marker commit in the same underlying transaction.
/// A crash can leave the previous completed version, never a falsely completed
/// partial step. Steps use create-if-absent/replace-with-identical semantics so
/// they remain idempotent if a platform retries an upgrade transaction.
abstract final class LocalJournalMigrationRunner {
  static const String schemaKey = 'meta/schema';

  static Future<void> ensureCurrent({
    required LocalGameJournalStore store,
    required int targetVersion,
    List<LocalJournalMigrationStep> steps = const [],
  }) async {
    if (targetVersion < 1 ||
        targetVersion > LocalGameJournalLimits.localSchemaVersion) {
      throw ArgumentError.value(
        targetVersion,
        'targetVersion',
        'must be a supported local schema version',
      );
    }
    var state = await store.transaction((transaction) async {
      final raw = await transaction.get(schemaKey);
      if (raw == null) {
        final existing = await transaction.scanPrefix('', limit: 1);
        if (existing.isNotEmpty) {
          throw LocalJournalException(
            LocalJournalErrorCode.migrationFailed,
            'Journal schema metadata is missing from nonempty storage',
            {'firstRecordKey': existing.single.key},
          );
        }
        final fresh = <String, Object?>{
          'appliedMigrations': <Object?>['initial_v$targetVersion'],
          'schemaVersion': targetVersion,
        };
        await transaction.put(
          schemaKey,
          LocalJournalRecordCodec.encodeVersioned(
            fresh,
            localSchemaVersion: targetVersion,
          ),
        );
        return fresh;
      }
      return _decodeAndValidateState(raw);
    });

    while (state['schemaVersion'] != targetVersion) {
      final version = state['schemaVersion'];
      if (version is! int || version < 0 || version > targetVersion) {
        throw LocalJournalException(
          LocalJournalErrorCode.unsupportedSchemaVersion,
          'Stored journal schema cannot be migrated by this build',
          {'storedVersion': version, 'targetVersion': targetVersion},
        );
      }
      final candidates = steps
          .where((step) => step.fromVersion == version)
          .toList(growable: false);
      if (candidates.length != 1 ||
          candidates.single.toVersion <= version ||
          candidates.single.toVersion > targetVersion) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Journal migration path is incomplete or ambiguous',
          {'storedVersion': version, 'targetVersion': targetVersion},
        );
      }
      final step = candidates.single;
      state = await store.transaction((transaction) async {
        final currentRaw = await transaction.get(schemaKey);
        if (currentRaw == null) {
          throw LocalJournalException(
            LocalJournalErrorCode.migrationFailed,
            'Journal migration state disappeared',
          );
        }
        final current = _decodeAndValidateState(currentRaw);
        if (current['schemaVersion'] != step.fromVersion) {
          return current;
        }
        await step.apply(
          LocalJournalMigrationContext(
            transaction: transaction,
            migrationId: step.migrationId,
          ),
        );
        final applied = <Object?>[
          ...((current['appliedMigrations'] as List?) ?? const []),
          step.migrationId,
        ];
        final next = <String, Object?>{
          'appliedMigrations': applied,
          'schemaVersion': step.toVersion,
        };
        await transaction.put(
          schemaKey,
          LocalJournalRecordCodec.encodeVersioned(
            next,
            localSchemaVersion: step.toVersion,
          ),
        );
        return next;
      });
    }
  }

  static Map<String, Object?> _decodeAndValidateState(String raw) {
    final decoded = LocalJournalRecordCodec.decodeVersioned(raw);
    final state = _validateState(decoded.payload);
    if (decoded.localSchemaVersion != state['schemaVersion']) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Journal schema envelope and payload versions do not agree',
        {
          'envelopeVersion': decoded.localSchemaVersion,
          'payloadVersion': state['schemaVersion'],
        },
      );
    }
    return state;
  }

  static Map<String, Object?> _validateState(Map<String, Object?> state) {
    if (state.length != 2 ||
        !state.containsKey('schemaVersion') ||
        !state.containsKey('appliedMigrations') ||
        state['appliedMigrations'] is! List) {
      throw LocalJournalException(
        LocalJournalErrorCode.migrationFailed,
        'Journal migration state is malformed',
      );
    }
    LocalJournalValidation.requireSafeInteger(
      'schemaVersion',
      state['schemaVersion'],
      minimum: 1,
    );
    final applied = state['appliedMigrations']! as List;
    final ids = <String>{};
    for (final value in applied) {
      if (value is! String ||
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value) ||
          !ids.add(value)) {
        throw LocalJournalException(
          LocalJournalErrorCode.migrationFailed,
          'Journal migration history is invalid',
        );
      }
    }
    return state;
  }
}
