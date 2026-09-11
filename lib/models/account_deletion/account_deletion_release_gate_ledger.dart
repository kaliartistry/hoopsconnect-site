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
    for (final reference in this.evidenceRefs) {
      AccountDeletionContract.requireOpaqueId('evidenceRef', reference);
    }
    if (passed &&
        (status != AccountDeletionReleaseGateStatus.passed ||
            owner == null ||
            this.evidenceRefs.isEmpty)) {
      throw const FormatException(
        'A passed gate requires passed status, an owner, and evidence.',
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
      if (this.gates[index].id != expectedGateIds[index]) {
        throw const FormatException(
          'Release gates must be complete, unique, and ordered G1-G11.',
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
