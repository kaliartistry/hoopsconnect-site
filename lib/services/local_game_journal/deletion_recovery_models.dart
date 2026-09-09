import '../../models/official_stats/canonical_encoding.dart';
import 'journal_error.dart';
import 'journal_limits.dart';
import 'journal_models.dart';
import 'journal_validation.dart';

enum LocalReceiptKnowledge { notSubmitted, responseUnknown, accepted }

void requireLegacyDeletionManifestForReconsent(Map<String, Object?> legacy) {
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
      LocalJournalErrorCode.manifestMismatch,
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
      LocalJournalErrorCode.manifestMismatch,
      'Legacy deletion manifest workspace list is malformed',
    );
  }
  var previousPartitionKey = '';
  for (final raw in rawWorkspaces) {
    if (raw is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
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
        LocalJournalErrorCode.manifestMismatch,
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
        LocalJournalErrorCode.manifestMismatch,
        'Legacy deletion manifest workspace invariants are invalid',
      );
    }
    previousPartitionKey = partition.key;
  }
  final withoutChecksum = Map<String, Object?>.from(legacy)..remove('checksum');
  if (OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum) !=
      legacy['checksum']) {
    throw LocalJournalException(
      LocalJournalErrorCode.manifestMismatch,
      'Legacy deletion manifest checksum does not match',
    );
  }
}

final class DeviceJournalWorkspaceSummary {
  final JournalPartition partition;
  final String packageChecksum;
  final String deviceSessionId;
  final int writerEpoch;
  final int nextLocalSequence;
  final int unacknowledgedOperations;
  final int receiptUnknownOperations;
  final int acceptedOperations;
  final String reconciliationEvidenceChecksum;

  DeviceJournalWorkspaceSummary({
    required this.partition,
    required this.packageChecksum,
    required this.deviceSessionId,
    required this.writerEpoch,
    required this.nextLocalSequence,
    required this.unacknowledgedOperations,
    required this.receiptUnknownOperations,
    required this.acceptedOperations,
    required this.reconciliationEvidenceChecksum,
  }) {
    LocalJournalValidation.requireHash('packageChecksum', packageChecksum);
    LocalJournalValidation.requireHash(
      'reconciliationEvidenceChecksum',
      reconciliationEvidenceChecksum,
    );
    LocalJournalValidation.requireId('deviceSessionId', deviceSessionId);
    for (final entry in {
      'writerEpoch': writerEpoch,
      'nextLocalSequence': nextLocalSequence,
      'unacknowledgedOperations': unacknowledgedOperations,
      'receiptUnknownOperations': receiptUnknownOperations,
      'acceptedOperations': acceptedOperations,
    }.entries) {
      LocalJournalValidation.requireSafeInteger(entry.key, entry.value);
    }
    if (unacknowledgedOperations + acceptedOperations != nextLocalSequence) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
        'Manifest operation counts must exactly cover the workspace sequence',
      );
    }
    if (receiptUnknownOperations > unacknowledgedOperations) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
        'Receipt-unknown operations must be a subset of unacknowledged work',
      );
    }
  }

  Map<String, Object?> toContractMap() => {
    'acceptedOperations': acceptedOperations,
    'deviceSessionId': deviceSessionId,
    'nextLocalSequence': nextLocalSequence,
    'packageChecksum': packageChecksum,
    'partition': partition.toContractMap(),
    'receiptUnknownOperations': receiptUnknownOperations,
    'reconciliationEvidenceChecksum': reconciliationEvidenceChecksum,
    'unacknowledgedOperations': unacknowledgedOperations,
    'writerEpoch': writerEpoch,
  };

  factory DeviceJournalWorkspaceSummary.fromContractMap(
    Map<String, Object?> map,
  ) {
    LocalJournalValidation.exactKeys(map, const {
      'partition',
      'packageChecksum',
      'deviceSessionId',
      'writerEpoch',
      'nextLocalSequence',
      'unacknowledgedOperations',
      'receiptUnknownOperations',
      'reconciliationEvidenceChecksum',
      'acceptedOperations',
    });
    final rawPartition = map['partition'];
    if (rawPartition is! Map) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
        'Manifest workspace partition is malformed',
      );
    }
    return DeviceJournalWorkspaceSummary(
      partition: JournalPartition.fromContractMap(
        Map<String, Object?>.from(rawPartition),
      ),
      packageChecksum: LocalJournalValidation.requireHash(
        'packageChecksum',
        map['packageChecksum'],
      ),
      deviceSessionId: LocalJournalValidation.requireId(
        'deviceSessionId',
        map['deviceSessionId'],
      ),
      writerEpoch: LocalJournalValidation.requireSafeInteger(
        'writerEpoch',
        map['writerEpoch'],
      ),
      nextLocalSequence: LocalJournalValidation.requireSafeInteger(
        'nextLocalSequence',
        map['nextLocalSequence'],
      ),
      unacknowledgedOperations: LocalJournalValidation.requireSafeInteger(
        'unacknowledgedOperations',
        map['unacknowledgedOperations'],
      ),
      receiptUnknownOperations: LocalJournalValidation.requireSafeInteger(
        'receiptUnknownOperations',
        map['receiptUnknownOperations'],
      ),
      reconciliationEvidenceChecksum: LocalJournalValidation.requireHash(
        'reconciliationEvidenceChecksum',
        map['reconciliationEvidenceChecksum'],
      ),
      acceptedOperations: LocalJournalValidation.requireSafeInteger(
        'acceptedOperations',
        map['acceptedOperations'],
      ),
    );
  }
}

final class DeviceJournalDeletionManifest {
  final int manifestVersion;
  final String manifestId;
  final String actorAccountId;
  final String deviceSessionId;
  final DateTime createdAt;
  final List<DeviceJournalWorkspaceSummary> workspaces;
  final bool serverDeletionContinuesIndependently;
  final bool consentInheritedAcrossDevices;
  final bool deletionStatusCanRecoverJournalContent;
  final String checksum;

  DeviceJournalDeletionManifest._({
    required this.manifestVersion,
    required this.manifestId,
    required this.actorAccountId,
    required this.deviceSessionId,
    required this.createdAt,
    required this.workspaces,
    required this.serverDeletionContinuesIndependently,
    required this.consentInheritedAcrossDevices,
    required this.deletionStatusCanRecoverJournalContent,
    required this.checksum,
  });

  factory DeviceJournalDeletionManifest.create({
    required String manifestId,
    required String actorAccountId,
    required String deviceSessionId,
    required DateTime createdAt,
    required List<DeviceJournalWorkspaceSummary> workspaces,
  }) {
    final normalizedAt = LocalJournalValidation.normalizeTimestamp(createdAt);
    final ordered = [
      ...workspaces,
    ]..sort((left, right) => left.partition.key.compareTo(right.partition.key));
    final withoutChecksum = _manifestMap(
      manifestVersion: LocalGameJournalLimits.deletionManifestVersion,
      manifestId: manifestId,
      actorAccountId: actorAccountId,
      deviceSessionId: deviceSessionId,
      createdAt: normalizedAt,
      workspaces: ordered,
    );
    final manifest = DeviceJournalDeletionManifest._(
      manifestVersion: LocalGameJournalLimits.deletionManifestVersion,
      manifestId: manifestId,
      actorAccountId: actorAccountId,
      deviceSessionId: deviceSessionId,
      createdAt: normalizedAt,
      workspaces: List.unmodifiable(ordered),
      serverDeletionContinuesIndependently: true,
      consentInheritedAcrossDevices: false,
      deletionStatusCanRecoverJournalContent: false,
      checksum: OfficialStatCanonicalEncoding.sha256Hex(withoutChecksum),
    );
    manifest._validate();
    return manifest;
  }

  factory DeviceJournalDeletionManifest.fromContractMap(
    Map<String, Object?> map,
  ) {
    LocalJournalValidation.exactKeys(map, const {
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
    final rawWorkspaces = map['workspaces'];
    if (rawWorkspaces is! List) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
        'Deletion manifest workspaces must be a list',
      );
    }
    for (final field in const [
      'serverDeletionContinuesIndependently',
      'consentInheritedAcrossDevices',
      'deletionStatusCanRecoverJournalContent',
    ]) {
      if (map[field] is! bool) {
        throw LocalJournalException(
          LocalJournalErrorCode.manifestMismatch,
          'Deletion manifest safety flags must be booleans',
        );
      }
    }
    final manifest = DeviceJournalDeletionManifest._(
      manifestVersion: LocalJournalValidation.requireSafeInteger(
        'manifestVersion',
        map['manifestVersion'],
        minimum: 1,
      ),
      manifestId: LocalJournalValidation.requireId(
        'manifestId',
        map['manifestId'],
      ),
      actorAccountId: LocalJournalValidation.requireId(
        'actorAccountId',
        map['actorAccountId'],
      ),
      deviceSessionId: LocalJournalValidation.requireId(
        'deviceSessionId',
        map['deviceSessionId'],
      ),
      createdAt: LocalJournalValidation.requireTimestamp(
        'createdAt',
        map['createdAt'],
      ),
      workspaces: List.unmodifiable(
        rawWorkspaces.map((raw) {
          if (raw is! Map) {
            throw LocalJournalException(
              LocalJournalErrorCode.manifestMismatch,
              'Deletion manifest workspace is malformed',
            );
          }
          return DeviceJournalWorkspaceSummary.fromContractMap(
            Map<String, Object?>.from(raw),
          );
        }),
      ),
      serverDeletionContinuesIndependently:
          map['serverDeletionContinuesIndependently'] as bool,
      consentInheritedAcrossDevices:
          map['consentInheritedAcrossDevices'] as bool,
      deletionStatusCanRecoverJournalContent:
          map['deletionStatusCanRecoverJournalContent'] as bool,
      checksum: LocalJournalValidation.requireHash('checksum', map['checksum']),
    );
    manifest._validate();
    return manifest;
  }

  Map<String, Object?> toContractMap() => {
    ..._manifestMap(
      manifestVersion: manifestVersion,
      manifestId: manifestId,
      actorAccountId: actorAccountId,
      deviceSessionId: deviceSessionId,
      createdAt: createdAt,
      workspaces: workspaces,
    ),
    'checksum': checksum,
  };

  void _validate() {
    if (manifestVersion != LocalGameJournalLimits.deletionManifestVersion ||
        !serverDeletionContinuesIndependently ||
        consentInheritedAcrossDevices ||
        deletionStatusCanRecoverJournalContent) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
        'Deletion manifest safety invariants are invalid',
      );
    }
    LocalJournalValidation.requireId('manifestId', manifestId);
    LocalJournalValidation.requireId('actorAccountId', actorAccountId);
    LocalJournalValidation.requireId('deviceSessionId', deviceSessionId);
    var previousKey = '';
    for (final workspace in workspaces) {
      if (workspace.partition.actorAccountId != actorAccountId ||
          workspace.deviceSessionId != deviceSessionId ||
          workspace.partition.key.compareTo(previousKey) <= 0) {
        throw LocalJournalException(
          LocalJournalErrorCode.manifestMismatch,
          'Deletion manifest workspace identity/order is invalid',
        );
      }
      previousKey = workspace.partition.key;
    }
    final expected = OfficialStatCanonicalEncoding.sha256Hex(
      _manifestMap(
        manifestVersion: manifestVersion,
        manifestId: manifestId,
        actorAccountId: actorAccountId,
        deviceSessionId: deviceSessionId,
        createdAt: createdAt,
        workspaces: workspaces,
      ),
    );
    if (checksum != expected) {
      throw LocalJournalException(
        LocalJournalErrorCode.manifestMismatch,
        'Deletion manifest checksum does not match',
      );
    }
  }
}

Map<String, Object?> _manifestMap({
  required int manifestVersion,
  required String manifestId,
  required String actorAccountId,
  required String deviceSessionId,
  required DateTime createdAt,
  required List<DeviceJournalWorkspaceSummary> workspaces,
}) => {
  'actorAccountId': actorAccountId,
  'consentInheritedAcrossDevices': false,
  'createdAt': createdAt,
  'deletionStatusCanRecoverJournalContent': false,
  'deviceSessionId': deviceSessionId,
  'manifestId': manifestId,
  'manifestVersion': manifestVersion,
  'serverDeletionContinuesIndependently': true,
  'workspaces': workspaces.map((value) => value.toContractMap()).toList(),
};

final class LocalReconciliationIdentity {
  final JournalPartition partition;
  final String deviceSessionId;
  final String operationId;
  final String commandId;
  final String requestHash;
  final int writerEpoch;
  final int localSequence;
  final LocalReceiptKnowledge receiptKnowledge;

  const LocalReconciliationIdentity({
    required this.partition,
    required this.deviceSessionId,
    required this.operationId,
    required this.commandId,
    required this.requestHash,
    required this.writerEpoch,
    required this.localSequence,
    required this.receiptKnowledge,
  });
}

/// Deliberate per-device consent. It has no meaning for any other manifest.
final class LocalDeletionConsent {
  final String consentId;
  final String manifestId;
  final String manifestChecksum;
  final String deviceSessionId;
  final DateTime grantedAt;

  LocalDeletionConsent({
    required this.consentId,
    required this.manifestId,
    required this.manifestChecksum,
    required this.deviceSessionId,
    required DateTime grantedAt,
  }) : grantedAt = LocalJournalValidation.normalizeTimestamp(grantedAt) {
    LocalJournalValidation.requireId('consentId', consentId);
    LocalJournalValidation.requireId('manifestId', manifestId);
    LocalJournalValidation.requireHash('manifestChecksum', manifestChecksum);
    LocalJournalValidation.requireId('deviceSessionId', deviceSessionId);
  }
}
