import 'dart:collection';

import 'calculators/normalized_box_score.dart';
import 'canonical_encoding.dart';
import 'contract_versions.dart';
import 'domain_contracts.dart';
import 'legacy_game_stats_v2_adapter.dart';

enum RulesProfileDecisionState { unresolved, referenceOnly, adopted }

/// Named and immutable rule selection supplied by league policy.
///
/// The runtime date is intentionally absent. `unresolved` is the current JBA
/// state until adoption evidence is recorded by the integration owner.
final class CandidateRulesProfile {
  CandidateRulesProfile({
    required this.rulesProfileId,
    required this.rulesetVersion,
    required this.decisionState,
    required Map<String, Object?> rulesArtifact,
    List<String> adoptionEvidenceRefs = const [],
  }) : adoptionEvidenceRefs = List.unmodifiable(adoptionEvidenceRefs),
       rulesArtifactCanonicalJson = OfficialStatCanonicalEncoding.encode(
         rulesArtifact,
       ),
       rulesArtifactHash = OfficialStatCanonicalEncoding.sha256Hex(
         rulesArtifact,
       ) {
    OfficialStatIdentifiers.requireValid('rulesProfileId', rulesProfileId);
    if (rulesArtifact['rulesProfileId'] != rulesProfileId) {
      throw const FormatException(
        'The rules artifact must bind the named rules profile',
      );
    }
    if (rulesArtifactHash != rulesetVersion.sha256) {
      throw const FormatException(
        'The ruleset version hash must match the canonical rules artifact',
      );
    }
    for (final reference in adoptionEvidenceRefs) {
      OfficialStatIdentifiers.requireValid('adoptionEvidenceRef', reference);
    }
    if (decisionState == RulesProfileDecisionState.adopted &&
        adoptionEvidenceRefs.isEmpty) {
      throw ArgumentError('An adopted rules profile requires evidence');
    }
    if (decisionState != RulesProfileDecisionState.adopted &&
        adoptionEvidenceRefs.isNotEmpty) {
      throw ArgumentError(
        'Only an adopted rules profile may claim adoption evidence',
      );
    }
  }

  final String rulesProfileId;
  final VersionReference rulesetVersion;
  final RulesProfileDecisionState decisionState;
  final List<String> adoptionEvidenceRefs;
  final String rulesArtifactCanonicalJson;
  final String rulesArtifactHash;

  OfficialStatRulesProfilePin get legacyAdapterPin =>
      OfficialStatRulesProfilePin(
        rulesProfileId: rulesProfileId,
        rulesetVersion: rulesetVersion,
      );
}

enum CandidateCalculationSource { reviewedV2Input, legacyEvidence }

/// Result from the candidate-only bridge. Arithmetic acceptance never implies
/// certification or activation.
final class CandidateCalculationResult {
  CandidateCalculationResult({
    required this.source,
    required this.profile,
    required this.arithmeticAccepted,
    required this.calculatorInvoked,
    required Map<String, Object?> calculatorResult,
    required List<String> blockers,
    required Map<String, Object?> provenance,
  }) : calculatorResult = UnmodifiableMapView(
         Map<String, Object?>.from(calculatorResult),
       ),
       blockers = List.unmodifiable(blockers),
       provenance = UnmodifiableMapView(Map<String, Object?>.from(provenance));

  final CandidateCalculationSource source;
  final CandidateRulesProfile profile;
  final bool arithmeticAccepted;
  final bool calculatorInvoked;
  final Map<String, Object?> calculatorResult;
  final List<String> blockers;
  final Map<String, Object?> provenance;

  /// Remains false until the integration owner deliberately replaces the
  /// dormant import-graph boundary and every activation gate is proven.
  bool get activationAllowed => false;

  /// Review approval is not certification. This bridge cannot certify.
  bool get certificationAllowed => false;
}

typedef CandidateCalculator = Map<String, Object?> Function(Object? input);

/// The only Stage 1 bridge between legacy evidence, a reviewed v2 input, and
/// the dormant normalized calculator. It performs no I/O and is not imported
/// from app, provider, repository, or Functions entrypoints.
final class CandidateOfficialStatsRuntime {
  CandidateOfficialStatsRuntime({
    required this.profile,
    LegacyGameStatsV2CandidateAdapter? legacyAdapter,
    CandidateCalculator? calculator,
  }) : legacyAdapter = legacyAdapter ?? ReadOnlyLegacyGameStatsV2Adapter(),
       calculator = calculator ?? calculateNormalizedBoxScore;

  final CandidateRulesProfile profile;
  final LegacyGameStatsV2CandidateAdapter legacyAdapter;
  final CandidateCalculator calculator;

  LegacyGameStatsV2Candidate adaptLegacy({
    required LegacyGameStatsSourceReference source,
    required Map<String, Object?> legacyDocument,
    required GameScope scope,
    LegacyGameStatsReviewedScopeMapping? reviewedScopeMapping,
  }) => legacyAdapter.adapt(
    source: source,
    legacyDocument: legacyDocument,
    scope: scope,
    rulesProfile: profile.legacyAdapterPin,
    reviewedScopeMapping: reviewedScopeMapping,
  );

  CandidateCalculationResult inspectLegacy(
    LegacyGameStatsV2Candidate candidate,
  ) {
    _requireAssociation(candidate.scope.associationId);
    if (candidate.rulesProfile.rulesProfileId != profile.rulesProfileId ||
        candidate.rulesProfile.rulesetVersion.versionId !=
            profile.rulesetVersion.versionId ||
        candidate.rulesProfile.rulesetVersion.sha256 !=
            profile.rulesetVersion.sha256) {
      throw const FormatException(
        'Legacy candidate does not bind the selected rules profile',
      );
    }
    return CandidateCalculationResult(
      source: CandidateCalculationSource.legacyEvidence,
      profile: profile,
      arithmeticAccepted: false,
      calculatorInvoked: false,
      calculatorResult: const {
        'calculatorVersion': normalizedBoxScoreCalculatorVersion,
        'status': 'blocked',
      },
      blockers: [
        ...candidate.calculatorBlockers,
        'legacy_evidence_requires_reviewed_v2_input',
        if (profile.decisionState != RulesProfileDecisionState.adopted)
          'rules_profile_adoption_unresolved',
      ],
      provenance: {
        'adapterVersion': LegacyGameStatsV2AdapterContract.adapterVersion,
        'candidateHash': candidate.candidateHash,
        'evidenceClassification': candidate.evidenceClassification.name,
        'sourcePayloadHash': candidate.source.sourcePayloadHash,
        'unmappedSourcePaths': candidate.unmappedSourcePaths,
      },
    );
  }

  CandidateCalculationResult calculateReviewedV2Input(
    Map<String, Object?> input,
  ) {
    final scope = _map(input, 'scope');
    _requireAssociation(_string(scope, 'associationId'));
    if (_string(input, 'calculatorVersion') !=
        normalizedBoxScoreCalculatorVersion) {
      throw const FormatException('Calculator version does not match v2');
    }
    final provenance = _map(input, 'provenance');
    if (_string(provenance, 'rulesetVersion') !=
        profile.rulesetVersion.versionId) {
      throw const FormatException(
        'Calculator provenance does not match the ruleset version',
      );
    }
    final rules = _map(input, 'rules');
    if (_string(rules, 'rulesProfileId') != profile.rulesProfileId) {
      throw const FormatException(
        'Calculator rules do not match the named rules profile',
      );
    }
    if (OfficialStatCanonicalEncoding.sha256Hex(rules) !=
        profile.rulesArtifactHash) {
      throw const FormatException(
        'Calculator rules do not match the hash-bound rules artifact',
      );
    }

    final result = calculator(input);
    final accepted = result['status'] == 'accepted';
    return CandidateCalculationResult(
      source: CandidateCalculationSource.reviewedV2Input,
      profile: profile,
      arithmeticAccepted: accepted,
      calculatorInvoked: true,
      calculatorResult: result,
      blockers: [
        if (!accepted) 'calculator_rejected_input',
        if (profile.decisionState != RulesProfileDecisionState.adopted)
          'rules_profile_adoption_unresolved',
        'official_revision_not_sealed',
        'authority_and_activation_gates_not_proven',
      ],
      provenance: {
        'calculatorVersion': normalizedBoxScoreCalculatorVersion,
        'rulesProfileDecisionState': profile.decisionState.name,
        'rulesArtifactHash': profile.rulesArtifactHash,
        'rulesProfileId': profile.rulesProfileId,
        'rulesetVersion': profile.rulesetVersion.toContractMap(),
      },
    );
  }

  void _requireAssociation(String associationId) {
    if (associationId != profile.rulesetVersion.associationId) {
      throw const FormatException(
        'Rules profile and candidate must share one association',
      );
    }
  }
}

Map<String, Object?> _map(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! Map) throw FormatException('\$.$key must be a map');
  return Map<String, Object?>.from(value);
}

String _string(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('\$.$key must be a nonempty string');
  }
  return value;
}
