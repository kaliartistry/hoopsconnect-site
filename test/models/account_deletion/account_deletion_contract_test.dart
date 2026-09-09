import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/account_deletion/account_deletion_contract.dart';

import 'account_deletion_wire_cases.dart';

Map<String, dynamic> loadJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<String> names<T extends Enum>(Iterable<T> values) =>
    values.map((value) => value.name).toList();

void main() {
  final fixture = loadJson(
    'contracts/account_deletion/v1/contract_fixtures.json',
  );
  final policyRegistry = loadJson(
    'contracts/account_deletion/v1/retention_policy_registry.json',
  );
  final releaseGates = loadJson(
    'contracts/account_deletion/v1/release_gates.json',
  );

  group('versions and state machines', () {
    test('Dart versions and enum names match the shared fixture', () {
      final versions = fixture['versions'] as Map<String, dynamic>;
      expect(AccountDeletionVersions.schema, versions['schemaVersion']);
      expect(AccountDeletionVersions.domain, versions['domainVersion']);
      expect(
        AccountDeletionVersions.policyRegistry,
        versions['policyRegistryVersion'],
      );
      expect(AccountDeletionVersions.inventory, versions['inventoryVersion']);
      expect(
        AccountDeletionVersions.canonicalEncoding,
        versions['canonicalEncodingVersion'],
      );
      expect(
        AccountDeletionVersions.fingerprint,
        versions['fingerprintVersion'],
      );
      expect(
        AccountDeletionVersions.statusCapability,
        versions['statusCapabilityVersion'],
      );
      final states = fixture['states'] as Map<String, dynamic>;
      expect(names(AccountLifecycleState.values), states['accountLifecycle']);
      expect(names(DeletionJobState.values), states['deletionJob']);
      expect(names(ResumeStage.values), states['resumeStage']);
      expect(names(CustodyChoice.values), states['custodyChoice']);
      expect(names(CustodyOutcome.values), states['custodyOutcome']);
      expect(
        names(AssociationCustodyState.values),
        states['associationCustody'],
      );
      expect(names(HoldState.values), states['hold']);
      expect(
        names(AdapterApplicability.values),
        states['adapterApplicability'],
      );
      expect(names(AdapterResultState.values), states['adapterResult']);
      expect(names(DispositionAction.values), states['disposition']);
      expect(names(ProviderName.values), states['providerName']);
      expect(
        names(StatusAliasBindingKind.values),
        states['statusAliasBindingKind'],
      );
      expect(
        names(AuthDeletionCheckpointState.values),
        states['authDeletionCheckpoint'],
      );
      expect(
        names(ProviderCheckpointState.values),
        states['providerCheckpoint'],
      );
      expect(names(DeletionStatusPhase.values), states['deletionStatusPhase']);
      expect(
        names(SubmittedOperationStatusResolution.values),
        states['submittedOperationStatusResolution'],
      );
      expect(names(IdempotencyDecision.values), states['idempotencyDecision']);
      expect(
        AccountDeletionContract.completionCheckpointNames,
        fixture['completionCheckpointNames'],
      );
    });

    test('only fixture lifecycle transitions are accepted', () {
      final transitions = fixture['transitions'] as Map<String, dynamic>;
      for (final edge in transitions['accountLifecycle'] as List<dynamic>) {
        final values = edge as List<dynamic>;
        expect(
          AccountDeletionContract.canTransitionAccountLifecycle(
            AccountLifecycleState.values.byName(values[0] as String),
            AccountLifecycleState.values.byName(values[1] as String),
          ),
          isTrue,
        );
      }
      expect(
        AccountDeletionContract.canTransitionAccountLifecycle(
          AccountLifecycleState.deleting,
          AccountLifecycleState.active,
        ),
        isFalse,
      );
      for (final edge in transitions['deletionJob'] as List<dynamic>) {
        final values = edge as List<dynamic>;
        expect(
          AccountDeletionContract.canTransitionDeletionJob(
            DeletionJobState.values.byName(values[0] as String),
            DeletionJobState.values.byName(values[1] as String),
          ),
          isTrue,
        );
      }
      expect(
        AccountDeletionContract.canTransitionDeletionJob(
          DeletionJobState.complete,
          DeletionJobState.accepted,
        ),
        isFalse,
      );
    });
  });

  group('schema and fingerprint', () {
    final capability = fixture['statusCapability'] as Map<String, dynamic>;

    Map<String, Object?> requestMap([
      Map<String, Object?> overrides = const {},
    ]) => {
      'schemaVersion': 1,
      'intentId': 'intent_1',
      'policyVersion': 'policy_v1',
      'impactVersion': 'impact_v1',
      'operationId': 'operation_fixture_1',
      'requestId': 'request_fixture_1',
      'statusSecretHash': capability['secretHash'] as String,
      'confirmation': 'deleteAccount',
      'custodyChoice': 'ordinary',
      ...overrides,
    };

    test('request serialization rejects unknown and missing fields', () {
      expect(
        () => AccountDeletionContract.validatePrepareDeletionRequest({
          'schemaVersion': 1,
        }),
        returnsNormally,
      );
      expect(
        () => AccountDeletionContract.validatePrepareDeletionRequest({
          'schemaVersion': 1,
          'uid': 'victim',
        }),
        throwsFormatException,
      );
      expect(
        () => RequestDeletionContract.fromContractMap(requestMap()),
        returnsNormally,
      );
      expect(
        () => RequestDeletionContract.fromContractMap(
          requestMap({'providerRevocationRef': 'apple_ref_1'}),
        ),
        returnsNormally,
      );
      expect(
        () => RequestDeletionContract.fromContractMap(
          requestMap({'providerRevocationRef': null}),
        ),
        throwsFormatException,
      );
      expect(
        () => RequestDeletionContract.fromContractMap(
          requestMap({'targetUid': 'victim'}),
        ),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionContract.validateDeletionStatusRequest({
          'schemaVersion': 1,
          'requestId': 'request_fixture_1',
          'statusSecret': capability['secret'] as String,
        }),
        returnsNormally,
      );
      expect(
        () => AccountDeletionContract.validateDeletionStatusRequest({
          'schemaVersion': 1,
          'requestId': 'request_fixture_1',
          'statusSecret': capability['secret'] as String,
          'uid': 'victim',
        }),
        throwsFormatException,
      );
      final missing = requestMap()..remove('policyVersion');
      expect(
        () => RequestDeletionContract.fromContractMap(missing),
        throwsFormatException,
      );
      expect(
        () => RequestDeletionContract.fromContractMap(
          requestMap({'confirmation': 'disableAccount'}),
        ),
        throwsFormatException,
      );
    });

    test('native wire integer cases exactly match the browser fixture', () {
      expect(fixture['wireIntegerCases'], accountDeletionWireIntegerCases);
      for (final testCase in accountDeletionWireIntegerCases) {
        final value = jsonDecode(testCase['json']! as String);
        if (testCase['accepted']! as bool) {
          expect(
            AccountDeletionContract.decodeWireSafeInteger(
              testCase['name']! as String,
              value,
            ),
            testCase['normalized'],
          );
        } else {
          expect(
            () => AccountDeletionContract.decodeWireSafeInteger(
              testCase['name']! as String,
              value,
            ),
            throwsFormatException,
          );
        }
      }
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () =>
              AccountDeletionContract.decodeWireSafeInteger('nonfinite', value),
          throwsFormatException,
        );
      }
    });

    test('status aliases and tombstones reject extra identity material', () {
      final statusAlias = <String, Object?>{
        'schemaVersion': 1,
        'requestId': 'request_fixture_1',
        'internalJobId': 'job_fixture_1',
        'generationHash':
            (fixture['generation'] as Map<String, dynamic>)['generationHash']
                as String,
        'acceptedSemanticFingerprint':
            (fixture['fingerprints'] as Map<String, dynamic>)['semanticHash']
                as String,
        'bindingKind': 'sameGenerationConvergence',
        'purpose': 'readOnlyDeletionStatus',
        'statusSecretHash': capability['secretHash'] as String,
        'createdAt': DateTime.utc(2026, 1, 2, 3, 4, 5, 678),
        'expiryPolicyDecisionId': 'retention.deletion_operational_residue.v1',
      };
      expect(
        () => AccountDeletionStatusAliasContract.fromContractMap(statusAlias),
        returnsNormally,
      );
      expect(
        () => AccountDeletionStatusAliasContract.fromContractMap({
          ...statusAlias,
          'uid': 'uid_fixture_alpha',
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionStatusAliasContract.fromContractMap({
          ...statusAlias,
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionStatusAliasContract.fromContractMap({
          ...statusAlias,
          'purpose': 'mutateDeletion',
        }),
        throwsFormatException,
      );
      final tombstone = <String, Object?>{
        'schemaVersion': 1,
        'generationHmac': '1' * 64,
        'deletionEpoch': 2,
        'policyVersion': 'policy_v1',
        'suppressionKeyVersion': 'key_v1',
        'acceptedAt': DateTime.utc(2026, 1, 2, 3, 4, 5, 678),
        'completedAt': null,
        'minimumReplayCutoff': DateTime.utc(2026, 1, 2, 3, 4, 5, 678),
      };
      expect(
        () => MinimalDeletionTombstoneContract.fromContractMap(tombstone),
        returnsNormally,
      );
      expect(
        () => MinimalDeletionTombstoneContract.fromContractMap({
          ...tombstone,
          'email': 'person@example.com',
        }),
        throwsFormatException,
      );
      expect(
        () => MinimalDeletionTombstoneContract.fromContractMap({
          ...tombstone,
          'deletionEpoch': 9007199254740992,
        }),
        throwsFormatException,
      );
      expect(
        () => MinimalDeletionTombstoneContract.fromContractMap({
          ...tombstone,
          'completedAt': DateTime.utc(2026, 1, 1),
        }),
        throwsFormatException,
      );
      expect(
        () => AccountLifecycleContract.fromContractMap({
          'schemaVersion': 1,
          'state': 'deleted',
          'epoch': 2,
          'generationHash':
              (fixture['generation'] as Map<String, dynamic>)['generationHash']
                  as String,
          'internalJobId': 'job_fixture_1',
          'acceptedAt': DateTime.utc(2026, 1, 2),
          'completedAt': DateTime.utc(2026, 1, 1),
        }),
        throwsFormatException,
      );
      expect(
        () => AccountLifecycleContract(
          state: AccountLifecycleState.active,
          epoch: 9007199254740992,
          generationHash: '1' * 64,
        ),
        throwsFormatException,
      );
      final schemas = fixture['schemas'] as Map<String, dynamic>;
      expect(
        statusAlias.keys.toSet(),
        ((schemas['statusAlias'] as Map<String, dynamic>)['required']
                as List<dynamic>)
            .cast<String>()
            .toSet(),
      );
      expect(
        tombstone.keys.toSet(),
        ((schemas['minimalTombstone'] as Map<String, dynamic>)['required']
                as List<dynamic>)
            .cast<String>()
            .toSet(),
      );
    });

    test('generation and fingerprints match the TypeScript golden values', () {
      final generationFixture = fixture['generation'] as Map<String, dynamic>;
      final input = generationFixture['input'] as Map<String, dynamic>;
      final generation = AccountGeneration(
        authNamespace: input['authNamespace'] as String,
        accountId: input['accountId'] as String,
        authCreatedAt: DateTime.parse(input['authCreatedAt'] as String),
      );
      expect({
        ...generation.toContractMap(),
        'authCreatedAt': generation.authCreatedAt.toIso8601String(),
      }, generationFixture['canonicalInput']);
      expect(generation.generationHash, generationFixture['generationHash']);
      final request = RequestDeletionContract.fromContractMap(
        requestMap({
          'intentId': 'intent_1',
          'providerRevocationRef': 'apple_ref_1',
        }),
      );
      final fingerprints = fixture['fingerprints'] as Map<String, dynamic>;
      final semanticInput = AccountDeletionContract.semanticFingerprintInput(
        request,
        generation,
      );
      expect(semanticInput, fingerprints['semanticInput']);
      expect(
        semanticInput.keys.toSet(),
        ((fingerprints['semanticFields'] as List<dynamic>).cast<String>())
            .toSet(),
      );
      final semantic = AccountDeletionContract.semanticFingerprint(
        request,
        generation,
      );
      expect(semantic, fingerprints['semanticHash']);
      expect(
        AccountDeletionContract.operationEnvelopeFingerprint(request, semantic),
        fingerprints['envelopeHash'],
      );
      expect(
        AccountDeletionContract.semanticFingerprint(
          RequestDeletionContract.fromContractMap(
            requestMap({'intentId': 'intent_2'}),
          ),
          generation,
        ),
        semantic,
      );
      expect(
        AccountDeletionContract.semanticFingerprint(
          RequestDeletionContract.fromContractMap(
            requestMap({'custodyChoice': 'suspendToCustody'}),
          ),
          generation,
        ),
        isNot(semantic),
      );
    });

    test('generation identity preserves exact Firebase UID bytes', () {
      final identityCases =
          fixture['generationIdentityCases'] as Map<String, dynamic>;
      final generationFixture = fixture['generation'] as Map<String, dynamic>;
      final input = generationFixture['input'] as Map<String, dynamic>;
      for (final accountId
          in identityCases['acceptedFirebaseUids'] as List<dynamic>) {
        expect(
          () => AccountGeneration(
            authNamespace: input['authNamespace'] as String,
            accountId: accountId as String,
            authCreatedAt: DateTime.parse(input['authCreatedAt'] as String),
          ).generationHash,
          returnsNormally,
        );
      }
      final distinct = identityCases['normalizationDistinct'] as List<dynamic>;
      String hashFor(String accountId) => AccountGeneration(
        authNamespace: input['authNamespace'] as String,
        accountId: accountId,
        authCreatedAt: DateTime.parse(input['authCreatedAt'] as String),
      ).generationHash;
      expect(
        hashFor(distinct[0] as String),
        isNot(hashFor(distinct[1] as String)),
      );
      final losslessEdgeHashes = {
        hashFor(String.fromCharCode(0xD800)),
        hashFor(String.fromCharCode(0xD801)),
        hashFor(String.fromCharCode(0xFFFD)),
      };
      expect(losslessEdgeHashes, hasLength(3));
      expect(() => hashFor(''), throwsFormatException);
      expect(() => hashFor('x' * 129), throwsFormatException);
    });

    test('status capability is exactly 256 bits and hash-bound', () {
      final secret = capability['secret'] as String;
      final secretHash = capability['secretHash'] as String;
      expect(AccountDeletionContract.decodeStatusSecret(secret), hasLength(32));
      expect(AccountDeletionContract.statusSecretHash(secret), secretHash);
      expect(
        AccountDeletionContract.statusSecretMatches(secret, secretHash),
        isTrue,
      );
      expect(
        AccountDeletionContract.statusSecretMatches(secret, '0' * 64),
        isFalse,
      );
      expect(
        () => AccountDeletionContract.decodeStatusSecret('short'),
        throwsFormatException,
      );
      expect(capability['allowedCapability'], ['readOwnCoarseDeletionStatus']);
      expect(
        capability['forbiddenCapabilities'],
        containsAll(['grantAuthority', 'restoreAccount', 'recoverJournal']),
      );
      expect(capability['serverNeverStores'], contains('statusSecret'));
    });

    test('deletion jobs require exact resume and terminal predicates', () {
      final base = <String, Object?>{
        'schemaVersion': 1,
        'internalJobId': 'job_1',
        'generationHash':
            (fixture['generation'] as Map<String, dynamic>)['generationHash']
                as String,
        'state': 'inventory',
        'resumeStage': null,
        'policyVersion': 'policy_v1',
        'inventoryVersion': AccountDeletionVersions.inventory,
        'attempt': 0,
        'leaseGeneration': 0,
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
      expect(
        () => AccountDeletionJobContract.fromContractMap(base),
        returnsNormally,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'state': 'retryWait',
          'resumeStage': 'inventory',
        }),
        returnsNormally,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'state': 'retryWait',
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'resumeStage': 'inventory',
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'safeErrorCode': 'INTERNAL_STACK_TRACE',
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'authDeletionCheckpointState': 'complete',
          'authAbsent': false,
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'authorityFenceDurable': true,
          'minimumCleanupReferencesCaptured': true,
          'authDeletionCheckpointState': 'notScheduled',
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'authorityFenceDurable': true,
          'minimumCleanupReferencesCaptured': true,
          'authDeletionCheckpointState': 'scheduled',
        }),
        returnsNormally,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'state': 'complete',
        }),
        throwsFormatException,
      );
      expect(
        () => AccountDeletionJobContract.fromContractMap({
          ...base,
          'state': 'complete',
          'authorityFenceDurable': true,
          'minimumCleanupReferencesCaptured': true,
          'authDeletionCheckpointState': 'complete',
          'authAbsent': true,
          'dataDispositionVerified': true,
          'publicPrivacyVerified': true,
          'custodyRecorded': true,
          'providerDispositionRecorded': true,
          'restoreSuppressionDurable': true,
        }),
        returnsNormally,
      );
      final schema =
          ((fixture['schemas'] as Map<String, dynamic>)['deletionJob']
                  as Map<String, dynamic>)['required']
              as List<dynamic>;
      expect(base.keys.toSet(), schema.cast<String>().toSet());
    });
  });

  group('idempotency and authority fence', () {
    test('exact retries, conflicts, and two-device aliases are distinct', () {
      for (final raw in fixture['idempotencyCases'] as List<dynamic>) {
        final value = raw as Map<String, dynamic>;
        final result = AccountDeletionContract.evaluateIdempotency(
          IdempotencyEvaluationInput(
            hasJob: value['hasJob'] as bool,
            sameOperation: value['sameOperation'] as bool,
            sameSemantic: value['sameSemantic'] as bool,
            sameEnvelope: value['sameEnvelope'] as bool,
            authenticatedSameGeneration:
                value['authenticatedSameGeneration'] as bool,
            lifecycle: AccountLifecycleState.values.byName(
              value['lifecycle'] as String,
            ),
          ),
        );
        expect(result.name, value['expected'], reason: value['name'] as String);
      }
      final changed = (fixture['idempotencyCases'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (value) =>
                value['name'] ==
                'secondDeviceChangedPreviewStillGetsReadOnlyAlias',
          );
      expect(changed['sameSemantic'], isFalse);
      expect(changed['expected'], 'attachStatusAlias');
      for (final raw in fixture['statusAliasCases'] as List<dynamic>) {
        final value = raw as Map<String, dynamic>;
        expect(value['purpose'], 'readOnlyDeletionStatus');
        expect(value['canMutateWinningJob'], isFalse);
        expect(value['canChangeAcceptedScope'], isFalse);
        expect(value['grantsGeneralAuthority'], isFalse);
      }
    });

    test('submitted failures resolve saved status before authentication', () {
      final sequence =
          fixture['submittedOperationRecoverySequence'] as Map<String, dynamic>;
      for (final code in [
        'AD_UNAUTHENTICATED',
        'AD_REAUTH_REQUIRED',
        'AD_APP_ATTESTATION_REQUIRED',
      ]) {
        expect(
          AccountDeletionContract.resolveSubmittedOperationFailure(
            errorCode: code,
            hasPersistedRequestMaterial: true,
            statusResolution: SubmittedOperationStatusResolution.notAttempted,
          ),
          sequence['beforeStatusResolution'],
        );
        expect(
          AccountDeletionContract.resolveSubmittedOperationFailure(
            errorCode: code,
            hasPersistedRequestMaterial: true,
            statusResolution: SubmittedOperationStatusResolution.accepted,
          ),
          sequence['afterAcceptedStatusResolution'],
        );
        expect(
          AccountDeletionContract.resolveSubmittedOperationFailure(
            errorCode: code,
            hasPersistedRequestMaterial: true,
            statusResolution: SubmittedOperationStatusResolution.unresolved,
          ),
          'AD_STATUS_UNAVAILABLE',
        );
        expect(
          AccountDeletionContract.resolveSubmittedOperationFailure(
            errorCode: code,
            hasPersistedRequestMaterial: true,
            statusResolution: SubmittedOperationStatusResolution.notAccepted,
          ),
          code,
        );
      }
      expect(sequence['newAuthenticationOnlyAfterNotAcceptedProof'], isTrue);
      expect(sequence['statusCapabilityCanMutate'], isFalse);
    });

    test(
      'Auth scheduling ignores cleanup blockers after its preconditions',
      () {
        for (final raw
            in fixture['authDeletionIndependenceCases'] as List<dynamic>) {
          final value = raw as Map<String, dynamic>;
          expect(
            AccountDeletionContract.authDeletionScheduleRequired(
              authorityFenceDurable: value['authorityFenceDurable'] as bool,
              minimumCleanupReferencesCaptured:
                  value['minimumCleanupReferencesCaptured'] as bool,
              authAbsent: value['authAbsent'] as bool,
              hasUnknownAdapter: value['hasUnknownAdapter'] as bool,
              retentionClassificationResolved:
                  value['retentionClassificationResolved'] as bool,
              custodyResolved: value['custodyResolved'] as bool,
            ),
            value['mustScheduleAuthDeletion'],
            reason: value['name'] as String,
          );
        }
      },
    );

    test(
      'deleting, deleted, stale, and unscoped receipt replays deny grants',
      () {
        for (final raw in fixture['authorityFenceCases'] as List<dynamic>) {
          final value = raw as Map<String, dynamic>;
          expect(
            AccountDeletionContract.canReplayGrant(
              lifecycle: AccountLifecycleState.values.byName(
                value['lifecycle'] as String,
              ),
              generationMatches: value['generationMatches'] as bool,
              epochMatches: value['epochMatches'] as bool,
              capabilityPresent: value['capabilityPresent'] as bool,
            ),
            value['grantReceiptReplay'],
            reason: value['name'] as String,
          );
        }
      },
    );
  });

  group('completion, policy, and release gates', () {
    DeletionCompletionInput completeInput(Map<String, dynamic> testCase) {
      final adapterIds = (fixture['adapterIds'] as List<dynamic>)
          .cast<String>();
      final adapters = [
        for (final adapterId in adapterIds)
          AdapterResultContract(
            adapterId: adapterId,
            applicability: AdapterApplicability.applicable,
            state: AdapterResultState.complete,
            disposition: adapterId == 'v2_certified_evidence'
                ? DispositionAction.restrictedRetention
                : DispositionAction.erase,
            policyDecisionState: PolicyDecisionState.approved,
            policyDecisionId: 'retention.$adapterId',
            policyVersion: 'policy_v1',
            holdState: adapterId == 'v2_certified_evidence'
                ? HoldState.activeApproved
                : HoldState.none,
            evidenceCode: 'fixture_verified',
            evidenceRef: 'evidence_fixture',
            holdBoundaryAt: adapterId == 'v2_certified_evidence'
                ? DateTime.utc(2027)
                : null,
          ),
      ];
      if (!(testCase['allAdaptersComplete'] as bool)) {
        adapters[0] = AdapterResultContract(
          adapterId: 'firebase_auth_identity',
          applicability: AdapterApplicability.applicable,
          state: AdapterResultState.blocked,
          disposition: DispositionAction.unresolved,
          policyDecisionState: PolicyDecisionState.approved,
          policyDecisionId: 'retention.firebase_auth_identity',
          policyVersion: 'policy_v1',
          holdState: HoldState.none,
          evidenceRef: 'evidence_fixture',
          holdBoundaryAt: null,
        );
      }
      final checkpoints = testCase['allCheckpoints'] as bool;
      final providersTerminal = testCase['allProvidersTerminal'] as bool;
      return DeletionCompletionInput(
        authAbsent: testCase['authAbsent'] as bool,
        dataDispositionVerified: checkpoints,
        publicPrivacyVerified: checkpoints,
        custodyRecorded: checkpoints,
        providerDispositionRecorded: checkpoints,
        restoreSuppressionDurable: checkpoints,
        requiredAdapterIds: adapterIds,
        adapterResults: adapters,
        providerCheckpoints: [
          ProviderCheckpointContract(
            provider: ProviderName.firebaseAuth,
            state: ProviderCheckpointState.complete,
            evidenceCode: 'absent_verified',
            checkedAt: DateTime.utc(2026),
          ),
          ProviderCheckpointContract(
            provider: ProviderName.appleCredential,
            state: providersTerminal
                ? ProviderCheckpointState.values.byName(
                    (testCase['appleOutcome'] as String?) ?? 'notApplicable',
                  )
                : ProviderCheckpointState.retryRequired,
            evidenceCode: 'fixture',
            checkedAt: DateTime.utc(2026),
          ),
        ],
        unknownRequiredState: testCase['unknownRequiredState'] as bool,
      );
    }

    test('completion fails closed for every missing or unknown predicate', () {
      for (final raw in fixture['completionCases'] as List<dynamic>) {
        final value = raw as Map<String, dynamic>;
        expect(
          AccountDeletionContract.isDeletionComplete(completeInput(value)),
          value['expected'],
          reason: value['name'] as String,
        );
      }
      final base = completeInput(
        (fixture['completionCases'] as List<dynamic>).first
            as Map<String, dynamic>,
      );
      expect(
        AccountDeletionContract.isDeletionComplete(
          DeletionCompletionInput(
            authAbsent: base.authAbsent,
            dataDispositionVerified: base.dataDispositionVerified,
            publicPrivacyVerified: base.publicPrivacyVerified,
            custodyRecorded: base.custodyRecorded,
            providerDispositionRecorded: base.providerDispositionRecorded,
            restoreSuppressionDurable: base.restoreSuppressionDurable,
            requiredAdapterIds: base.requiredAdapterIds,
            adapterResults: base.adapterResults,
            providerCheckpoints: [base.providerCheckpoints.first],
            unknownRequiredState: base.unknownRequiredState,
          ),
        ),
        isFalse,
      );
      expect(
        AccountDeletionContract.isDeletionComplete(
          DeletionCompletionInput(
            authAbsent: base.authAbsent,
            dataDispositionVerified: base.dataDispositionVerified,
            publicPrivacyVerified: base.publicPrivacyVerified,
            custodyRecorded: base.custodyRecorded,
            providerDispositionRecorded: base.providerDispositionRecorded,
            restoreSuppressionDurable: base.restoreSuppressionDurable,
            requiredAdapterIds: base.requiredAdapterIds,
            adapterResults: base.adapterResults,
            providerCheckpoints: [
              base.providerCheckpoints.first,
              ProviderCheckpointContract(
                provider: ProviderName.firebaseAuth,
                state: ProviderCheckpointState.manualActionGuidance,
                evidenceCode: 'not_valid_for_firebase',
                checkedAt: DateTime.utc(2026),
              ),
            ],
            unknownRequiredState: base.unknownRequiredState,
          ),
        ),
        isFalse,
      );
      DeletionCompletionInput replace({
        List<String>? requiredAdapterIds,
        List<AdapterResultContract>? adapterResults,
        List<ProviderCheckpointContract>? providerCheckpoints,
      }) => DeletionCompletionInput(
        authAbsent: base.authAbsent,
        dataDispositionVerified: base.dataDispositionVerified,
        publicPrivacyVerified: base.publicPrivacyVerified,
        custodyRecorded: base.custodyRecorded,
        providerDispositionRecorded: base.providerDispositionRecorded,
        restoreSuppressionDurable: base.restoreSuppressionDurable,
        requiredAdapterIds: requiredAdapterIds ?? base.requiredAdapterIds,
        adapterResults: adapterResults ?? base.adapterResults,
        providerCheckpoints: providerCheckpoints ?? base.providerCheckpoints,
        unknownRequiredState: base.unknownRequiredState,
      );
      AdapterResultContract replaceAdapter(
        AdapterResultContract value, {
        AdapterApplicability? applicability,
        AdapterResultState? state,
        DispositionAction? disposition,
        HoldState? holdState,
        String? evidenceCode,
        String? evidenceRef,
      }) => AdapterResultContract(
        adapterId: value.adapterId,
        applicability: applicability ?? value.applicability,
        state: state ?? value.state,
        disposition: disposition ?? value.disposition,
        policyDecisionState: value.policyDecisionState,
        policyDecisionId: value.policyDecisionId,
        policyVersion: value.policyVersion,
        holdState: holdState ?? value.holdState,
        evidenceCode: evidenceCode ?? value.evidenceCode,
        evidenceRef: evidenceRef ?? value.evidenceRef,
        holdBoundaryAt: value.holdBoundaryAt,
      );
      expect(
        AccountDeletionContract.isDeletionComplete(
          replace(requiredAdapterIds: const [], adapterResults: const []),
        ),
        isFalse,
      );
      final missingEvidence = [...base.adapterResults];
      missingEvidence[0] = replaceAdapter(missingEvidence[0], evidenceRef: '');
      expect(
        AccountDeletionContract.isDeletionComplete(
          replace(adapterResults: missingEvidence),
        ),
        isFalse,
      );
      final releasePending = [...base.adapterResults];
      releasePending[0] = replaceAdapter(
        releasePending[0],
        applicability: AdapterApplicability.notApplicable,
        state: AdapterResultState.notApplicable,
        disposition: DispositionAction.notApplicable,
        holdState: HoldState.releasePending,
      );
      expect(
        AccountDeletionContract.isDeletionComplete(
          replace(adapterResults: releasePending),
        ),
        isFalse,
      );
      final datedNotApplicable = [...base.adapterResults];
      datedNotApplicable[0] = AdapterResultContract(
        adapterId: datedNotApplicable[0].adapterId,
        applicability: AdapterApplicability.notApplicable,
        state: AdapterResultState.notApplicable,
        disposition: DispositionAction.notApplicable,
        policyDecisionState: datedNotApplicable[0].policyDecisionState,
        policyDecisionId: datedNotApplicable[0].policyDecisionId,
        policyVersion: datedNotApplicable[0].policyVersion,
        holdState: HoldState.none,
        evidenceCode: datedNotApplicable[0].evidenceCode,
        evidenceRef: datedNotApplicable[0].evidenceRef,
        holdBoundaryAt: DateTime.utc(2027),
      );
      expect(
        AccountDeletionContract.isDeletionComplete(
          replace(adapterResults: datedNotApplicable),
        ),
        isFalse,
      );
      final missingProviderEvidence = [...base.providerCheckpoints];
      missingProviderEvidence[0] = ProviderCheckpointContract(
        provider: missingProviderEvidence[0].provider,
        state: missingProviderEvidence[0].state,
        evidenceCode: '',
        checkedAt: missingProviderEvidence[0].checkedAt,
      );
      expect(
        AccountDeletionContract.isDeletionComplete(
          replace(providerCheckpoints: missingProviderEvidence),
        ),
        isFalse,
      );
      final adapterSchema =
          ((fixture['schemas'] as Map<String, dynamic>)['adapterResult']
                  as Map<String, dynamic>)['required']
              as List<dynamic>;
      expect(
        adapterSchema.cast<String>().toSet(),
        base.adapterResults.first.toContractMap().keys.toSet(),
      );
    });

    test('nested v1 maps reject extra fields and future schemas', () {
      final base = completeInput(
        (fixture['completionCases'] as List<dynamic>).first
            as Map<String, dynamic>,
      );
      Map<String, Object?> completionMap() => {
        'schemaVersion': 1,
        'authAbsent': base.authAbsent,
        'checkpoints': {
          'dataDispositionVerified': base.dataDispositionVerified,
          'publicPrivacyVerified': base.publicPrivacyVerified,
          'custodyRecorded': base.custodyRecorded,
          'providerDispositionRecorded': base.providerDispositionRecorded,
          'restoreSuppressionDurable': base.restoreSuppressionDurable,
        },
        'requiredAdapterIds': base.requiredAdapterIds,
        'adapterResults': [
          for (final result in base.adapterResults) result.toContractMap(),
        ],
        'providerCheckpoints': [
          for (final checkpoint in base.providerCheckpoints)
            checkpoint.toContractMap(),
        ],
        'unknownRequiredState': base.unknownRequiredState,
      };

      expect(
        () => DeletionCompletionInput.fromContractMap(completionMap()),
        returnsNormally,
      );
      expect(
        () => DeletionCompletionInput.fromContractMap({
          ...completionMap(),
          'future': true,
        }),
        throwsFormatException,
      );
      expect(
        () => DeletionCompletionInput.fromContractMap({
          ...completionMap(),
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      final checkpoints = Map<String, Object?>.from(
        completionMap()['checkpoints']! as Map,
      );
      expect(
        () => DeletionCompletionInput.fromContractMap({
          ...completionMap(),
          'checkpoints': {...checkpoints, 'future': true},
        }),
        throwsFormatException,
      );
      final adapterMaps = List<Map<String, Object?>>.from(
        completionMap()['adapterResults']! as List,
      );
      expect(
        () => AdapterResultContract.fromContractMap({
          ...adapterMaps.first,
          'future': true,
        }),
        throwsFormatException,
      );
      expect(
        () => AdapterResultContract.fromContractMap({
          ...adapterMaps.first,
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => AdapterResultContract.fromContractMap({
          ...adapterMaps.first,
          'holdBoundaryAt': 'invalid-date',
        }),
        throwsA(isA<TypeError>()),
      );
      final providerMaps = List<Map<String, Object?>>.from(
        completionMap()['providerCheckpoints']! as List,
      );
      expect(
        () => ProviderCheckpointContract.fromContractMap({
          ...providerMaps.first,
          'future': true,
        }),
        throwsFormatException,
      );
      expect(
        () => ProviderCheckpointContract.fromContractMap({
          ...providerMaps.first,
          'schemaVersion': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => ProviderCheckpointContract.fromContractMap({
          ...providerMaps.first,
          'checkedAt': 'invalid-date',
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('all matrix rows map to unique closed policy decisions', () {
      final adapterIds = (fixture['adapterIds'] as List<dynamic>)
          .cast<String>();
      expect(AccountDeletionContract.adapterIds, adapterIds);
      expect(adapterIds.toSet(), hasLength(adapterIds.length));
      final decisions = policyRegistry['decisions'] as List<dynamic>;
      expect(decisions, hasLength(adapterIds.length));
      expect(
        decisions
            .map((raw) => (raw as Map<String, dynamic>)['adapterId'])
            .toSet(),
        adapterIds.toSet(),
      );
      expect(policyRegistry['activationApproved'], isFalse);
      expect(policyRegistry['policyVersion'], isNull);
      expect(policyRegistry['governingMatrix'], fixture['governingMatrix']);
      final governingMatrix =
          fixture['governingMatrix'] as Map<String, dynamic>;
      expect(governingMatrix['adapterCount'], 27);
      expect(governingMatrix['normativeInvariants'], hasLength(5));
      final template =
          policyRegistry['decisionTemplate'] as Map<String, dynamic>;
      for (final field
          in policyRegistry['requiredDecisionFields'] as List<dynamic>) {
        expect(template[field], isNull, reason: field as String);
      }
      expect(template['approved'], isFalse);
    });

    test('G1-G11 remain closed with no owner or evidence', () {
      expect(releaseGates['activationAllowed'], isFalse);
      final gates = releaseGates['gates'] as List<dynamic>;
      expect(gates.map((raw) => (raw as Map<String, dynamic>)['id']).toList(), [
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
      ]);
      for (final raw in gates) {
        final gate = raw as Map<String, dynamic>;
        expect(gate['passed'], isFalse);
        expect(gate['owner'], isNull);
        expect(gate['evidenceRefs'], isEmpty);
        expect(gate['status'], startsWith('closed'));
      }
      final g10 = gates.cast<Map<String, dynamic>>().singleWhere(
        (gate) => gate['id'] == 'G10',
      );
      expect(
        g10['requiredEvidence'],
        containsAll([
          'auth_deletion_scheduled_after_durable_fence_and_minimum_references',
          'blocked_cleanup_does_not_block_auth_deletion',
          'auth_absence_does_not_bypass_cleanup_completion',
        ]),
      );
    });
  });

  group('compatibility, errors, and official-stat privacy', () {
    test('stable errors match shared retry and idempotency contracts', () {
      final fixtureErrors = fixture['errors'] as Map<String, dynamic>;
      expect(AccountDeletionContract.errorPolicies.keys, fixtureErrors.keys);
      for (final entry in AccountDeletionContract.errorPolicies.entries) {
        final expected = fixtureErrors[entry.key] as Map<String, dynamic>;
        expect(entry.value.transport, expected['transport']);
        expect(entry.value.retry, expected['retry']);
        expect(entry.value.idempotency, expected['idempotency']);
      }
      expect(
        AccountDeletionContract.internalErrorCodes,
        fixture['internalErrors'],
      );
    });

    test('Auth-only deletion never creates or infers membership authority', () {
      for (final raw in fixture['compatibilityCases'] as List<dynamic>) {
        final value = raw as Map<String, dynamic>;
        expect(
          AccountDeletionContract.selfDeletionEligible(
            authenticatedSameGeneration: value['hasAuth'] as bool,
            hasProfile: value['hasProfile'] as bool,
            hasMembership: value['hasMembership'] as bool,
            legacyRole: value['legacyRole'] as String?,
          ),
          value['selfDeletionEligible'],
          reason: value['name'] as String,
        );
        expect(value['createsMembership'], isFalse);
      }
    });

    test('stat fixtures preserve facts and close identity presentation', () {
      final cases = {
        for (final raw in fixture['statPrivacyCases'] as List<dynamic>)
          (raw as Map<String, dynamic>)['name'] as String: raw,
      };
      final facts = cases['deleteActorBinding']!;
      expect(facts['preserveSportingFacts'], isTrue);
      expect(facts['preserveRevisionBytes'], isTrue);
      expect(facts['preserveCertifiedHash'], isTrue);
      expect(facts['removeAccountBinding'], isTrue);
      final legacy = cases['legacyNameBearingKey']!;
      expect(legacy['nameMatchAllowed'], isFalse);
      expect(legacy['requiresControlledRekey'], isTrue);
      expect(legacy['requiresRebuildSuppression'], isTrue);
      final minor = cases['unknownMinor']!;
      expect(minor['defaultsToAdult'], isFalse);
      expect(minor['publicNameAllowed'], isFalse);
      expect(minor['publicPhotoAllowed'], isFalse);
      final truths = policyRegistry['policyTruths'] as Map<String, dynamic>;
      expect(truths['pseudonymizationIsAnonymity'], isFalse);
      expect(truths['hashIsAnonymousByDefault'], isFalse);
      expect(truths['accountDeletionDeletesTenantOrTeam'], isFalse);
      final journal =
          fixture['localJournalReconciliationCase'] as Map<String, dynamic>;
      expect(journal['serverDeletionContinuesIndependently'], isTrue);
      expect(journal['statusCapabilityCanRecoverJournalContent'], isFalse);
      expect(journal['statusAliasCanAuthorizeJournalMutation'], isFalse);
      expect(journal['consentInheritedAcrossDevices'], isFalse);
      final devices = journal['devices'] as List<dynamic>;
      expect(devices, hasLength(2));
      expect(
        (devices[0] as Map<String, dynamic>)['manifestId'],
        isNot((devices[1] as Map<String, dynamic>)['manifestId']),
      );
    });

    test('last-owner custody outcomes match the shared contract', () {
      for (final raw in fixture['custodyCases'] as List<dynamic>) {
        final value = raw as Map<String, dynamic>;
        expect(
          AccountDeletionContract.resolveCustodyOutcome(
            isLastRecoverableOwner: value['isLastRecoverableOwner'] as bool,
            transferVerified: value['transferVerified'] as bool,
            namedCustodyAvailable: value['namedCustodyAvailable'] as bool,
          ).name,
          value['expected'],
          reason: value['name'] as String,
        );
      }
    });
  });
}
