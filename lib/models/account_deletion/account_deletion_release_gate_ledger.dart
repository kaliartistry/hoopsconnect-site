import 'account_deletion_contract.dart';

enum AccountDeletionReleaseGateStatus {
  closedPendingAuthoritativeDecision,
  closedPendingOperationalProof,
  closedPendingImplementationAndProof,
  closedPendingReview,
  passed,
}

final class AccountDeletionReleaseGateEntry {
  AccountDeletionReleaseGateEntry({
    required this.id,
    required this.name,
    required this.status,
    required this.owner,
    required Iterable<String> requiredEvidence,
    required Iterable<String> evidenceRefs,
    required this.passed,
  }) : requiredEvidence = List.unmodifiable(requiredEvidence),
       evidenceRefs = List.unmodifiable(evidenceRefs) {
    if (!RegExp(r'^G(?:[1-9]|1[01])$').hasMatch(id)) {
      throw const FormatException('Invalid account-deletion gate ID.');
    }
    AccountDeletionContract.requireOpaqueId('gateName', name);
    if (owner != null) {
      AccountDeletionContract.requireOpaqueId('gateOwner', owner!);
    }
    if (this.requiredEvidence.isEmpty ||
        this.requiredEvidence.toSet().length != this.requiredEvidence.length) {
      throw const FormatException(
        'Release gates require unique evidence requirements.',
      );
    }
    for (final evidence in this.requiredEvidence) {
      AccountDeletionContract.requireOpaqueId('requiredEvidence', evidence);
    }
    if (this.evidenceRefs.toSet().length != this.evidenceRefs.length) {
      throw const FormatException('Release-gate evidence references repeat.');
    }
    if (this.evidenceRefs.length > this.requiredEvidence.length) {
      throw const FormatException(
        'Release-gate evidence cannot exceed the normative requirements.',
      );
    }
    for (final reference in this.evidenceRefs) {
      AccountDeletionContract.requireOpaqueId('evidenceRef', reference);
    }
    if (passed &&
        (status != AccountDeletionReleaseGateStatus.passed ||
            owner == null ||
            this.evidenceRefs.length != this.requiredEvidence.length)) {
      throw const FormatException(
        'A passed gate requires an owner and one ordered evidence reference per requirement.',
      );
    }
    if (!passed && status == AccountDeletionReleaseGateStatus.passed) {
      throw const FormatException('Gate status and passed flag disagree.');
    }
  }

  factory AccountDeletionReleaseGateEntry.fromMap(Map<String, Object?> value) {
    AccountDeletionContract.requireExactKeys(value, const {
      'id',
      'name',
      'status',
      'owner',
      'requiredEvidence',
      'evidenceRefs',
      'passed',
    });
    final owner = value['owner'];
    if (owner != null && owner is! String) {
      throw const FormatException('Gate owner must be null or a string.');
    }
    if (value['passed'] is! bool) {
      throw const FormatException('Gate passed must be a boolean.');
    }
    return AccountDeletionReleaseGateEntry(
      id: _string('id', value['id']),
      name: _string('name', value['name']),
      status: _status(value['status']),
      owner: owner as String?,
      requiredEvidence: _strings('requiredEvidence', value['requiredEvidence']),
      evidenceRefs: _strings('evidenceRefs', value['evidenceRefs']),
      passed: value['passed']! as bool,
    );
  }

  final String id;
  final String name;
  final AccountDeletionReleaseGateStatus status;
  final String? owner;
  final List<String> requiredEvidence;
  final List<String> evidenceRefs;
  final bool passed;

  bool get isClosed => !passed;

  Map<String, String> get evidenceByRequirement =>
      Map<String, String>.unmodifiable({
        for (var index = 0; index < evidenceRefs.length; index++)
          requiredEvidence[index]: evidenceRefs[index],
      });
}

final class AccountDeletionReleaseGateLedger {
  AccountDeletionReleaseGateLedger({
    required this.contractVersion,
    required this.activationAllowed,
    required Iterable<AccountDeletionReleaseGateEntry> gates,
  }) : gates = List.unmodifiable(gates) {
    if (contractVersion != 'account-deletion-contract-v1') {
      throw const FormatException('Unsupported release-gate contract.');
    }
    if (this.gates.length != expectedGateIds.length) {
      throw const FormatException('The release ledger must contain G1-G11.');
    }
    for (var index = 0; index < expectedGateIds.length; index++) {
      final gate = this.gates[index];
      final expectedId = expectedGateIds[index];
      if (gate.id != expectedId) {
        throw const FormatException(
          'Release gates must be complete, unique, and ordered G1-G11.',
        );
      }
      final expected = _expectedGateContracts[expectedId]!;
      if (gate.name != expected.name ||
          !_sameStrings(gate.requiredEvidence, expected.requiredEvidence) ||
          (!gate.passed && gate.status != expected.closedStatus)) {
        throw FormatException(
          '$expectedId name, closed status, and required evidence must match the normative ledger.',
        );
      }
    }
    if (activationAllowed && this.gates.any((gate) => !gate.passed)) {
      throw const FormatException(
        'Activation cannot be allowed while any gate remains closed.',
      );
    }
  }

  factory AccountDeletionReleaseGateLedger.fromMap(Map<String, Object?> value) {
    AccountDeletionContract.requireExactKeys(value, const {
      'contractVersion',
      'activationAllowed',
      'gates',
    });
    if (value['activationAllowed'] is! bool) {
      throw const FormatException('activationAllowed must be a boolean.');
    }
    final rawGates = value['gates'];
    if (rawGates is! List) {
      throw const FormatException('gates must be a list.');
    }
    return AccountDeletionReleaseGateLedger(
      contractVersion: _string('contractVersion', value['contractVersion']),
      activationAllowed: value['activationAllowed']! as bool,
      gates: rawGates.map((raw) {
        if (raw is! Map || raw.keys.any((key) => key is! String)) {
          throw const FormatException('A release-gate row is malformed.');
        }
        return AccountDeletionReleaseGateEntry.fromMap(
          raw.map((key, entry) => MapEntry(key as String, entry)),
        );
      }),
    );
  }

  static const List<String> expectedGateIds = [
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
  ];

  static const Map<String, _ReleaseGateContract> _expectedGateContracts = {
    'G1': _ReleaseGateContract(
      name: 'controller_and_retention',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingAuthoritativeDecision,
      requiredEvidence: [
        'named_controller',
        'authorized_decision_maker',
        'approved_per_class_retention_registry',
        'approved_disclosure_versions',
      ],
    ),
    'G2': _ReleaseGateContract(
      name: 'player_and_minor_rights',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingAuthoritativeDecision,
      requiredEvidence: [
        'verified_account_person_claim_policy',
        'guardian_and_non_account_process',
        'field_level_publication_policy',
        'ranking_privacy_treatment',
      ],
    ),
    'G3': _ReleaseGateContract(
      name: 'recoverable_ownership',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingOperationalProof,
      requiredEvidence: [
        'named_custody_operator',
        'named_recovery_operator',
        'independent_infrastructure_owner',
        'transfer_rehearsal',
        'last_owner_suspension_rehearsal',
      ],
    ),
    'G4': _ReleaseGateContract(
      name: 'legacy_migration_inventory',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingOperationalProof,
      requiredEvidence: [
        'fresh_authorized_auth_profile_membership_inventory',
        'generation_metadata',
        'approved_owner_bootstrap',
        'source_and_media_classification',
        'suppression_before_migration',
      ],
    ),
    'G5': _ReleaseGateContract(
      name: 'complete_fencing',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingImplementationAndProof,
      requiredEvidence: [
        'rules_fence',
        'command_and_receipt_fence',
        'provisioning_fence',
        'notification_fence',
        'storage_fence',
        'legacy_and_public_read_fence',
        'old_client_denial',
      ],
    ),
    'G6': _ReleaseGateContract(
      name: 'provider_configuration',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingOperationalProof,
      requiredEvidence: [
        'pinned_sdk_compatibility',
        'apple_native_and_web_identifiers',
        'revocation_material_handling',
        'provider_event_validation',
        'app_check',
        'domains_and_csp',
        'indexes',
        'least_privilege_workers',
      ],
    ),
    'G7': _ReleaseGateContract(
      name: 'deadline_and_operations',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingAuthoritativeDecision,
      requiredEvidence: [
        'approved_completion_timing',
        'staffing_and_alerts',
        'backlog_capacity',
        'completion_delivery',
        'processor_request_process',
        'outage_and_attention_handling',
      ],
    ),
    'G8': _ReleaseGateContract(
      name: 'restore_and_retained_copies',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingOperationalProof,
      requiredEvidence: [
        'backup_pitr_object_version_log_and_processor_retention',
        'durable_suppression_ledger',
        'key_custody',
        'restore_before_traffic_rehearsal',
      ],
    ),
    'G9': _ReleaseGateContract(
      name: 'official_stat_integration',
      closedStatus: AccountDeletionReleaseGateStatus.closedPendingReview,
      requiredEvidence: [
        'approved_identity_evidence_privacy_addendum',
        'legacy_privacy_adapter',
        'no_certified_hash_conflict',
        'no_raw_export_or_public_fallback',
      ],
    ),
    'G10': _ReleaseGateContract(
      name: 'end_to_end_evidence',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingOperationalProof,
      requiredEvidence: [
        'applicable_scenario_matrix_pass',
        'independent_disposition_review',
        'custody_review',
        'public_privacy_review',
        'auth_deletion_scheduled_after_durable_fence_and_minimum_references',
        'blocked_cleanup_does_not_block_auth_deletion',
        'verified_auth_absence',
        'auth_absence_does_not_bypass_cleanup_completion',
        'zero_unresolved_required_adapters',
      ],
    ),
    'G11': _ReleaseGateContract(
      name: 'public_and_store_consistency',
      closedStatus:
          AccountDeletionReleaseGateStatus.closedPendingOperationalProof,
      requiredEvidence: [
        'live_web_route_readback',
        'privacy_policy_readback',
        'mobile_and_pwa_screenshots',
        'reviewer_test_procedure',
        'app_store_privacy_consistency',
        'google_data_safety_and_deletion_url_consistency',
      ],
    ),
  };

  final String contractVersion;
  final bool activationAllowed;
  final List<AccountDeletionReleaseGateEntry> gates;

  bool get allPassed => gates.every((gate) => gate.passed);

  bool get candidateRemainsClosed => !activationAllowed || !allPassed;

  Map<String, List<String>> get unresolvedEvidence =>
      Map<String, List<String>>.unmodifiable({
        for (final gate in gates.where((entry) => entry.isClosed))
          gate.id: List<String>.unmodifiable(gate.requiredEvidence),
      });
}

final class _ReleaseGateContract {
  const _ReleaseGateContract({
    required this.name,
    required this.closedStatus,
    required this.requiredEvidence,
  });

  final String name;
  final AccountDeletionReleaseGateStatus closedStatus;
  final List<String> requiredEvidence;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _string(String field, Object? value) {
  if (value is! String) throw FormatException('$field must be a string.');
  return value;
}

List<String> _strings(String field, Object? value) {
  if (value is! List) throw FormatException('$field must be a list.');
  return [
    for (var index = 0; index < value.length; index++)
      _string('$field[$index]', value[index]),
  ];
}

AccountDeletionReleaseGateStatus _status(Object? value) {
  final raw = _string('status', value);
  for (final status in AccountDeletionReleaseGateStatus.values) {
    if (status.name == raw) return status;
  }
  throw const FormatException('Unsupported release-gate status.');
}
