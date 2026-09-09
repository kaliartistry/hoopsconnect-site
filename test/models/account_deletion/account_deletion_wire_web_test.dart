import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';

import 'account_deletion_wire_cases.dart';

Object? decodeLiteral(String literal) => jsonDecode(literal);

Map<String, Object?> requestMapFromSchemaLiteral(String literal) =>
    Map<String, Object?>.from(
      jsonDecode('''
        {
          "schemaVersion": $literal,
          "intentId": "intent_1",
          "policyVersion": "policy_v1",
          "impactVersion": "impact_v1",
          "operationId": "operation_1",
          "requestId": "request_1",
          "statusSecretHash": "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd",
          "confirmation": "deleteAccount",
          "custodyChoice": "ordinary"
        }
      '''),
    );

void main() {
  test('Chrome JSON parsing applies the mathematical safe-integer decoder', () {
    for (final testCase in accountDeletionWireIntegerCases) {
      final value = decodeLiteral(testCase['json']! as String);
      if (testCase['accepted']! as bool) {
        expect(
          AccountDeletionContract.decodeWireSafeInteger(
            testCase['name']! as String,
            value,
          ),
          testCase['normalized'],
          reason: testCase['name']! as String,
        );
      } else {
        expect(
          () => AccountDeletionContract.decodeWireSafeInteger(
            testCase['name']! as String,
            value,
          ),
          throwsFormatException,
          reason: testCase['name']! as String,
        );
      }
    }
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => AccountDeletionContract.decodeWireSafeInteger('nonfinite', value),
        throwsFormatException,
      );
    }
  });

  test('Chrome parses equivalent v1 schema literals identically', () {
    for (final literal in ['1', '1.0', '1e0', '-0.0']) {
      final map = requestMapFromSchemaLiteral(literal);
      if (literal == '-0.0') {
        expect(
          () => RequestDeletionContract.fromContractMap(map),
          throwsFormatException,
        );
      } else {
        expect(RequestDeletionContract.fromContractMap(map).schemaVersion, 1);
      }
    }
    for (final literal in ['1.5', '9007199254740992', '"1"']) {
      expect(
        () => RequestDeletionContract.fromContractMap(
          requestMapFromSchemaLiteral(literal),
        ),
        throwsFormatException,
      );
    }
  });

  test('Chrome rejects future and expanded nested v1 records', () {
    final adapter = <String, Object?>{
      'schemaVersion': decodeLiteral('1e0'),
      'adapterId': 'user_profile',
      'applicability': 'applicable',
      'state': 'complete',
      'disposition': 'erase',
      'policyDecisionState': 'approved',
      'policyDecisionId': 'retention.user_profile',
      'policyVersion': 'policy_v1',
      'holdState': 'none',
      'evidenceCode': 'verified',
      'evidenceRef': 'evidence_1',
      'holdBoundaryAt': null,
    };
    final provider = <String, Object?>{
      'schemaVersion': decodeLiteral('1.0'),
      'provider': 'firebaseAuth',
      'state': 'complete',
      'evidenceCode': 'absent_verified',
      'checkedAt': DateTime.utc(2026),
    };
    expect(AdapterResultContract.fromContractMap(adapter).schemaVersion, 1);
    expect(
      ProviderCheckpointContract.fromContractMap(provider).schemaVersion,
      1,
    );
    expect(
      () => AdapterResultContract.fromContractMap({...adapter, 'future': true}),
      throwsFormatException,
    );
    expect(
      () => AdapterResultContract.fromContractMap({
        ...adapter,
        'schemaVersion': decodeLiteral('2'),
      }),
      throwsFormatException,
    );
    expect(
      () => ProviderCheckpointContract.fromContractMap({
        ...provider,
        'future': true,
      }),
      throwsFormatException,
    );
    expect(
      () => DeletionCompletionInput.fromContractMap({
        'schemaVersion': decodeLiteral('1'),
        'authAbsent': true,
        'checkpoints': {
          for (final name in AccountDeletionContract.completionCheckpointNames)
            name: true,
          'future': true,
        },
        'requiredAdapterIds': ['user_profile'],
        'adapterResults': [adapter],
        'providerCheckpoints': [provider],
        'unknownRequiredState': false,
      }),
      throwsFormatException,
    );
  });

  test(
    'Chrome applies safe integers to lifecycle, tombstone, and job fields',
    () {
      final generation =
          '8c2c2e70608172d988bb4a4a384b5d6d2d87c83c98f9023ab39b99af69151c00';
      final lifecycle = <String, Object?>{
        'schemaVersion': decodeLiteral('1.0'),
        'state': 'active',
        'epoch': decodeLiteral('-0.0'),
        'generationHash': generation,
        'internalJobId': null,
        'acceptedAt': null,
        'completedAt': null,
      };
      expect(AccountLifecycleContract.fromContractMap(lifecycle).epoch, 0);
      final tombstone = <String, Object?>{
        'schemaVersion': decodeLiteral('1e0'),
        'generationHmac': '1' * 64,
        'deletionEpoch': decodeLiteral('9007199254740991'),
        'policyVersion': 'policy_v1',
        'suppressionKeyVersion': 'key_v1',
        'acceptedAt': DateTime.utc(2026),
        'completedAt': null,
        'minimumReplayCutoff': DateTime.utc(2026),
      };
      expect(
        MinimalDeletionTombstoneContract.fromContractMap(
          tombstone,
        ).deletionEpoch,
        9007199254740991,
      );
      final job = <String, Object?>{
        'schemaVersion': decodeLiteral('1'),
        'internalJobId': 'job_1',
        'generationHash': generation,
        'state': 'inventory',
        'resumeStage': null,
        'policyVersion': 'policy_v1',
        'inventoryVersion': AccountDeletionVersions.inventory,
        'attempt': decodeLiteral('1e0'),
        'leaseGeneration': decodeLiteral('-0.0'),
        'authorityFenceDurable': false,
        'minimumCleanupReferencesCaptured': false,
        'authDeletionCheckpointState': 'notScheduled',
        'authAbsent': false,
        'dataDispositionVerified': false,
        'publicPrivacyVerified': false,
        'custodyRecorded': false,
        'providerDispositionRecorded': false,
        'restoreSuppressionDurable': false,
        'safeErrorCode': null,
      };
      expect(AccountDeletionJobContract.fromContractMap(job).attempt, 1);
      expect(
        AccountDeletionJobContract.fromContractMap(job).leaseGeneration,
        0,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...job,
          'attempt': decodeLiteral('1.5'),
        }),
        throwsFormatException,
      );
    },
  );
}
