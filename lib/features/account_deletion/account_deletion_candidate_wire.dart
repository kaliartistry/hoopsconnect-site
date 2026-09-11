import '../../models/account_deletion/account_deletion_contract.dart';
import '../../models/official_stats/canonical_encoding.dart';
import 'account_deletion_candidate_models.dart';

/// Strict candidate client parsing for the existing AD04 response surface and
/// the provisional sanitized impact DTO requested from the integration owner.
abstract final class AccountDeletionCandidateWire {
  static CandidateAccountDeletionImpact parseImpact(
    Map<String, Object?> value,
  ) {
    AccountDeletionContract.requireExactKeys(value, const {
      'schemaVersion',
      'intentId',
      'policyVersion',
      'impactVersion',
      'expiresAt',
      'custodyChoice',
      'ownershipResolution',
      'isLastRecoverableOwner',
      'associationId',
      'serverDeletionContinuesIndependently',
      'sportingHistoryIsNotAccountData',
    });
    _requireSchema(value['schemaVersion']);
    return CandidateAccountDeletionImpact(
      intentId: _string('intentId', value['intentId']),
      policyVersion: _string('policyVersion', value['policyVersion']),
      impactVersion: _string('impactVersion', value['impactVersion']),
      expiresAt: _date('expiresAt', value['expiresAt']),
      custodyChoice: _enum(
        'custodyChoice',
        value['custodyChoice'],
        CustodyChoice.values,
      ),
      ownershipResolution: _enum(
        'ownershipResolution',
        value['ownershipResolution'],
        AccountDeletionOwnershipResolution.values,
      ),
      isLastRecoverableOwner: _bool(
        'isLastRecoverableOwner',
        value['isLastRecoverableOwner'],
      ),
      associationId: _nullableString('associationId', value['associationId']),
      serverDeletionContinuesIndependently: _bool(
        'serverDeletionContinuesIndependently',
        value['serverDeletionContinuesIndependently'],
      ),
      sportingHistoryIsNotAccountData: _bool(
        'sportingHistoryIsNotAccountData',
        value['sportingHistoryIsNotAccountData'],
      ),
    );
  }

  static AcceptedAccountDeletionRequest parseAccepted(
    Map<String, Object?> value,
  ) {
    AccountDeletionContract.requireExactKeys(value, const {
      'requestId',
      'internalJobId',
      'acceptedAt',
      'state',
      'completionTargetText',
      'nextPollAfterSeconds',
      'bindingKind',
    });
    if (value['state'] != 'deleting') {
      throw const FormatException(
        'Accepted deletion must enter the deleting lifecycle.',
      );
    }
    final completionTarget = _string(
      'completionTargetText',
      value['completionTargetText'],
    );
    if (completionTarget.isEmpty || completionTarget.length > 320) {
      throw const FormatException('Invalid deletion completion target.');
    }
    final nextPollSeconds = AccountDeletionContract.decodeWireSafeInteger(
      'nextPollAfterSeconds',
      value['nextPollAfterSeconds'],
      nonNegative: true,
    );
    if (nextPollSeconds == 0 || nextPollSeconds > 3600) {
      throw const FormatException('Invalid deletion poll interval.');
    }
    final bindingKind = _string('bindingKind', value['bindingKind']);
    if (bindingKind != 'winningOperation' &&
        bindingKind != 'sameGenerationConvergence') {
      throw const FormatException('Invalid deletion binding kind.');
    }
    return AcceptedAccountDeletionRequest(
      requestId: _string('requestId', value['requestId']),
      internalJobId: _string('internalJobId', value['internalJobId']),
      acceptedAt: _date('acceptedAt', value['acceptedAt']),
      nextPollAfter: Duration(seconds: nextPollSeconds),
      sameGenerationConvergence: bindingKind == 'sameGenerationConvergence',
    );
  }

  static AccountDeletionStatusSnapshot parseStatus(Map<String, Object?> value) {
    AccountDeletionContract.requireExactKeys(
      value,
      const {
        'requestId',
        'phase',
        'acceptedAt',
        'retainedCategoryCodes',
        'messageCode',
      },
      const {'completedAt', 'nextPollAfterSeconds', 'providerOutcome'},
    );
    final phase = _enum('phase', value['phase'], DeletionStatusPhase.values);
    final completedAt = value.containsKey('completedAt')
        ? _date('completedAt', value['completedAt'])
        : null;
    final nextPollAfter = value.containsKey('nextPollAfterSeconds')
        ? Duration(
            seconds: AccountDeletionContract.decodeWireSafeInteger(
              'nextPollAfterSeconds',
              value['nextPollAfterSeconds'],
              nonNegative: true,
            ),
          )
        : null;
    final rawCodes = value['retainedCategoryCodes'];
    if (rawCodes is! List || rawCodes.length > 64) {
      throw const FormatException('Invalid retained category codes.');
    }
    final codes = <String>[];
    for (var index = 0; index < rawCodes.length; index++) {
      final code = _string('retainedCategoryCodes[$index]', rawCodes[index]);
      AccountDeletionContract.requireOpaqueId(
        'retainedCategoryCodes[$index]',
        code,
      );
      codes.add(code);
    }
    if (codes.toSet().length != codes.length) {
      throw const FormatException('Duplicate retained category code.');
    }
    final providerOutcome = switch (value['providerOutcome']) {
      'revoked' => ProviderCheckpointState.complete,
      'not_applicable' => ProviderCheckpointState.notApplicable,
      'manual_action_guidance' => ProviderCheckpointState.manualActionGuidance,
      'pending' || null => ProviderCheckpointState.pending,
      _ => throw const FormatException('Invalid provider outcome.'),
    };
    return AccountDeletionStatusSnapshot(
      requestId: _string('requestId', value['requestId']),
      phase: phase,
      acceptedAt: _date('acceptedAt', value['acceptedAt']),
      completedAt: completedAt,
      nextPollAfter: nextPollAfter,
      providerOutcome: providerOutcome,
      messageCode: _string('messageCode', value['messageCode']),
      retainedCategoryCodes: codes,
    );
  }

  static void _requireSchema(Object? value) {
    if (AccountDeletionContract.decodeWireSafeInteger(
          'schemaVersion',
          value,
          nonNegative: true,
        ) !=
        AccountDeletionVersions.schema) {
      throw const FormatException('Unsupported deletion schema.');
    }
  }

  static String _string(String field, Object? value) {
    if (value is! String) throw FormatException('$field must be a string.');
    return value;
  }

  static String? _nullableString(String field, Object? value) =>
      value == null ? null : _string(field, value);

  static bool _bool(String field, Object? value) {
    if (value is! bool) throw FormatException('$field must be a boolean.');
    return value;
  }

  static DateTime _date(String field, Object? value) {
    final raw = _string(field, value);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null ||
        !parsed.isUtc ||
        parsed.toIso8601String() != raw ||
        parsed.millisecondsSinceEpoch.abs() >
            OfficialStatCanonicalEncoding.maxSafeInteger) {
      throw FormatException('$field must be a canonical UTC timestamp.');
    }
    return parsed;
  }

  static T _enum<T extends Enum>(String field, Object? value, List<T> values) {
    final name = _string(field, value);
    for (final candidate in values) {
      if (candidate.name == name) return candidate;
    }
    throw FormatException('$field has an unsupported value.');
  }
}
