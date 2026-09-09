#!/usr/bin/env node
'use strict';

const {createHash} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const CANONICAL_ENCODING_VERSION = 'official-stat-canonical-json-v1';
const SOURCE_SCHEMA_VERSION = 'stat-migration-source-v1';
const INVENTORY_SCHEMA_VERSION = 'stat-migration-inventory-v1';
const REPORT_SCHEMA_VERSION = 'stat-migration-dry-run-report-v1';
const MAPPER_VERSION = 'stat-migration-mapper-v1';
const MAPPER_NAMESPACE = 'hoopsconnect-stat-migration-namespace-v1';
const CLASSIFICATION_RULES_VERSION = 'stat-migration-classification-v1';
const MAX_PAGE_SIZE = 250;
const MAX_RECORDS = 50000;
const MAX_REPORT_BYTES = 16 * 1024 * 1024;

const classifications = Object.freeze([
  'evidenced',
  'unverified',
  'synthetic',
  'orphaned',
  'contradictory',
  'duplicateCandidate',
  'privacyRestricted',
]);

const errorCodes = Object.freeze({
  malformedSource: 'HC_MI_MALFORMED_SOURCE',
  unsupportedSchemaVersion: 'HC_MI_UNSUPPORTED_SCHEMA_VERSION',
  unsafePath: 'HC_MI_UNSAFE_PATH',
  crossAssociationReference: 'HC_MI_CROSS_ASSOCIATION_REFERENCE',
  missingScope: 'HC_MI_MISSING_SCOPE',
  contradictorySource: 'HC_MI_CONTRADICTORY_SOURCE',
  changedSourceHash: 'HC_MI_CHANGED_SOURCE_HASH',
  nondeterminism: 'HC_MI_NONDETERMINISM',
  oversizedPage: 'HC_MI_OVERSIZED_PAGE',
  oversizedReport: 'HC_MI_OVERSIZED_REPORT',
  attemptedWriteMode: 'HC_MI_WRITE_MODE_ATTEMPTED',
  orphanedReference: 'HC_MI_ORPHANED_REFERENCE',
  duplicateCandidate: 'HC_MI_DUPLICATE_CANDIDATE',
  privacyRestricted: 'HC_MI_PRIVACY_RESTRICTED',
});

class MigrationInventoryError extends Error {
  constructor(code, message, details = null) {
    super(message);
    this.name = 'MigrationInventoryError';
    this.code = code;
    this.details = details;
  }
}

const asciiKey = /^[\x21-\x7e]+$/;
const opaqueId = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;
const sensitiveFieldPattern = /email|phone|mobile|address|birth|dob|guardian|parent|contact|fcm.?token|auth.?token/i;

function asciiCompare(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function encodeCanonical(value) {
  if (value === null || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'string') return JSON.stringify(value.normalize('NFC'));
  if (typeof value === 'number') {
    if (!Number.isSafeInteger(value)) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical numbers must be safe integers.',
      );
    }
    return JSON.stringify(value);
  }
  if (value instanceof Date) {
    if (Object.getPrototypeOf(value) !== Date.prototype
        || Object.getOwnPropertyNames(value).length !== 0
        || Object.getOwnPropertySymbols(value).length !== 0) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical timestamps must be unmodified Date values.',
      );
    }
    if (!Number.isFinite(value.getTime())) {
      throw new MigrationInventoryError(errorCodes.malformedSource, 'Invalid timestamp.');
    }
    const year = value.getUTCFullYear();
    if (year < 1 || year > 9999) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical timestamps require years 0001-9999.',
      );
    }
    return JSON.stringify(value.toISOString());
  }
  if (Array.isArray(value)) {
    if (Object.getPrototypeOf(value) !== Array.prototype
        || Object.getOwnPropertySymbols(value).length !== 0) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical arrays must be ordinary dense arrays.',
      );
    }
    const ownNames = Object.getOwnPropertyNames(value);
    if (ownNames.length !== value.length + 1) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical arrays cannot have holes or extra properties.',
      );
    }
    const encoded = [];
    for (let index = 0; index < value.length; index += 1) {
      const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
      if (!descriptor || !('value' in descriptor) || !descriptor.enumerable) {
        throw new MigrationInventoryError(
          errorCodes.malformedSource,
          'Canonical arrays cannot have holes or accessors.',
        );
      }
      encoded.push(encodeCanonical(descriptor.value));
    }
    return `[${encoded.join(',')}]`;
  }
  if (typeof value === 'object') {
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical maps must be plain records.',
      );
    }
    if (Object.getOwnPropertySymbols(value).length !== 0) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical maps cannot contain symbol properties.',
      );
    }
    const ownNames = Object.getOwnPropertyNames(value);
    const keys = Object.keys(value);
    if (ownNames.length !== keys.length) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Canonical maps cannot contain non-enumerable properties.',
      );
    }
    for (const key of keys) {
      if (!asciiKey.test(key)) {
        throw new MigrationInventoryError(
          errorCodes.malformedSource,
          'Canonical map keys must be nonempty printable ASCII.',
        );
      }
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor || !('value' in descriptor) || !descriptor.enumerable) {
        throw new MigrationInventoryError(
          errorCodes.malformedSource,
          'Canonical maps cannot contain accessors.',
        );
      }
    }
    keys.sort();
    return `{${keys.map((key) => `${JSON.stringify(key)}:${encodeCanonical(value[key])}`).join(',')}}`;
  }
  throw new MigrationInventoryError(
    errorCodes.malformedSource,
    `Unsupported canonical value type: ${typeof value}.`,
  );
}

function canonicalEncode(value) {
  return encodeCanonical(value);
}

function canonicalSha256(value) {
  return createHash('sha256').update(canonicalEncode(value), 'utf8').digest('hex');
}

function requirePlainRecord(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || (Object.getPrototypeOf(value) !== Object.prototype
        && Object.getPrototypeOf(value) !== null)) {
    throw new MigrationInventoryError(
      errorCodes.malformedSource,
      `${label} must be a plain object.`,
    );
  }
  return value;
}

function requireString(value, label, {max = 2048, pattern = null} = {}) {
  if (typeof value !== 'string' || value.length === 0 || value.length > max
      || (pattern && !pattern.test(value))) {
    throw new MigrationInventoryError(
      errorCodes.malformedSource,
      `${label} is missing or invalid.`,
    );
  }
  return value;
}

function requireOpaqueId(value, label) {
  return requireString(value, label, {max: 128, pattern: opaqueId});
}

function validateSourcePath(sourcePath, associationId) {
  requireString(sourcePath, 'sourcePath', {max: 2048});
  if (sourcePath.startsWith('/') || sourcePath.endsWith('/') || sourcePath.includes('\\')
      || sourcePath.includes('//') || /[\u0000-\u001f\u007f]/.test(sourcePath)) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Source path is unsafe.');
  }
  const segments = sourcePath.split('/');
  if (segments.some((segment) => !segment || segment === '.' || segment === '..' || segment.length > 256)) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Source path is unsafe.');
  }
  if (segments[0] === 'associations') {
    if (segments.length < 2 || segments[1] !== associationId) {
      throw new MigrationInventoryError(
        errorCodes.crossAssociationReference,
        'Source path crosses the selected association boundary.',
      );
    }
  }
  return sourcePath;
}

function validateSourceKey(sourceKey) {
  requireString(sourceKey, 'sourceKey', {max: 512});
  if (!/^[\x21-\x7e]+$/.test(sourceKey) || sourceKey.includes('\\')
      || sourceKey.startsWith('/') || sourceKey.endsWith('/')
      || sourceKey.split('/').some((segment) => segment === '.' || segment === '..')) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Source key is unsafe.');
  }
  return sourceKey;
}

function sourceIdentity(record) {
  return `${record.sourcePath}#${record.sourceKey}`;
}

function sourceLabelFor(identity) {
  return `src_${createHash('sha256').update(identity, 'utf8').digest('hex').slice(0, 24)}`;
}

function normalizeScope(scope, associationId) {
  requirePlainRecord(scope || {}, 'record.scope');
  const normalized = {};
  for (const field of [
    'associationId', 'competitionId', 'seasonId', 'divisionId', 'phaseId', 'gameId',
  ]) {
    const value = scope[field];
    if (value === undefined || value === null) {
      normalized[field] = null;
    } else {
      normalized[field] = requireOpaqueId(value, `scope.${field}`);
    }
  }
  if (normalized.associationId && normalized.associationId !== associationId) {
    throw new MigrationInventoryError(
      errorCodes.crossAssociationReference,
      'Record scope crosses the selected association boundary.',
    );
  }
  return normalized;
}

const scopeRequirements = Object.freeze({
  season: ['associationId', 'competitionId', 'seasonId'],
  division: ['associationId', 'competitionId', 'seasonId', 'divisionId'],
  legacyTeam: ['associationId', 'competitionId', 'seasonId', 'divisionId'],
  legacyRosterEntry: ['associationId', 'competitionId', 'seasonId', 'divisionId'],
  legacyPlayer: ['associationId'],
  legacyGame: ['associationId', 'competitionId', 'seasonId', 'divisionId', 'phaseId', 'gameId'],
  legacyGameStats: ['associationId', 'competitionId', 'seasonId', 'divisionId', 'phaseId', 'gameId'],
  legacyGamePlayerLine: ['associationId', 'competitionId', 'seasonId', 'divisionId', 'phaseId', 'gameId'],
  playerSeasonAggregate: ['associationId', 'competitionId', 'seasonId'],
  teamSeasonAggregate: ['associationId', 'competitionId', 'seasonId'],
  standingsAggregate: ['associationId', 'competitionId', 'seasonId'],
  leaderboardAggregate: ['associationId', 'competitionId', 'seasonId'],
});

const targetTypes = Object.freeze({
  season: ['season'],
  division: ['division'],
  legacyTeam: ['teamIdentity', 'teamEntry'],
  legacyRosterEntry: ['person', 'player', 'rosterMembership', 'rosterMembershipVersion'],
  legacyPlayer: ['person', 'player'],
  legacyGame: ['game'],
  legacyGameStats: ['legacyStatSourceEvidence', 'statRevisionEvidence'],
  legacyGamePlayerLine: ['gameParticipantEvidence', 'rosterSnapshotParticipant'],
  playerSeasonAggregate: ['legacyAggregateEvidence'],
  teamSeasonAggregate: ['legacyAggregateEvidence'],
  standingsAggregate: ['legacyAggregateEvidence'],
  leaderboardAggregate: ['legacyAggregateEvidence'],
});

const requiredRelationTargets = Object.freeze({
  legacyRosterEntry: Object.freeze({team: 'legacyTeam'}),
  legacyGame: Object.freeze({awayTeam: 'legacyTeam', homeTeam: 'legacyTeam'}),
  legacyGameStats: Object.freeze({game: 'legacyGame'}),
  legacyGamePlayerLine: Object.freeze({game: 'legacyGame', team: 'legacyTeam'}),
});

const divisionScopedEntityTypes = new Set([
  'legacyTeam', 'legacyRosterEntry', 'legacyGame', 'legacyGameStats', 'legacyGamePlayerLine',
]);

function validateReference(reference, associationId) {
  requirePlainRecord(reference, 'reference');
  const relation = requireString(reference.relation, 'reference.relation', {
    max: 128,
    pattern: /^[A-Za-z][A-Za-z0-9_-]{0,127}$/,
  });
  const targetSourcePath = validateSourcePath(reference.targetSourcePath, associationId);
  const targetSourceKey = validateSourceKey(reference.targetSourceKey);
  return {
    relation,
    required: reference.required !== false,
    targetEntityType: reference.targetEntityType === null || reference.targetEntityType === undefined
      ? null
      : requireString(reference.targetEntityType, 'reference.targetEntityType', {max: 128}),
    targetSourceKey,
    targetSourcePath,
  };
}

function normalizeEvidence(record) {
  const evidence = requirePlainRecord(record.classificationEvidence || {}, 'classificationEvidence');
  const independentEvidence = Array.isArray(evidence.independentEvidence)
    ? evidence.independentEvidence.map((item) => {
      requirePlainRecord(item, 'independentEvidence');
      return {
        evidenceType: requireString(item.evidenceType, 'independentEvidence.evidenceType', {max: 128}),
        referenceHash: requireString(item.referenceHash, 'independentEvidence.referenceHash', {
          max: 64,
          pattern: sha256Pattern,
        }),
      };
    }).sort((a, b) => asciiCompare(canonicalEncode(a), canonicalEncode(b)))
    : [];
  const contradictions = Array.isArray(evidence.contradictions)
    ? [...new Set(evidence.contradictions.map((value) => requireString(
      value,
      'classificationEvidence.contradictions',
      {max: 128, pattern: /^[A-Za-z0-9_.-]+$/},
    )))].sort()
    : [];
  let duplicateCandidate = null;
  if (evidence.duplicateCandidate !== undefined && evidence.duplicateCandidate !== null) {
    const candidate = requirePlainRecord(evidence.duplicateCandidate, 'duplicateCandidate');
    duplicateCandidate = {
      evidenceHash: requireString(candidate.evidenceHash, 'duplicateCandidate.evidenceHash', {
        max: 64,
        pattern: sha256Pattern,
      }),
      groupId: requireOpaqueId(candidate.groupId, 'duplicateCandidate.groupId'),
    };
  }
  const privacyRestrictedFields = Array.isArray(evidence.privacyRestrictedFields)
    ? [...new Set(evidence.privacyRestrictedFields.map((value) => requireString(
      value,
      'privacyRestrictedFields',
      {max: 128, pattern: /^[A-Za-z][A-Za-z0-9_.-]{0,127}$/},
    )))].sort()
    : [];
  return {contradictions, duplicateCandidate, independentEvidence, privacyRestrictedFields};
}

function normalizeProvenance(record) {
  const provenance = requirePlainRecord(record.provenance || {}, 'record.provenance');
  const evidenceHashes = Array.isArray(provenance.evidenceHashes)
    ? [...new Set(provenance.evidenceHashes.map((value) => requireString(
      value,
      'provenance.evidenceHashes',
      {max: 64, pattern: sha256Pattern},
    )))].sort()
    : [];
  let generator = null;
  if (provenance.generator !== undefined && provenance.generator !== null) {
    const raw = requirePlainRecord(provenance.generator, 'provenance.generator');
    generator = {
      generatorId: requireOpaqueId(raw.generatorId, 'provenance.generator.generatorId'),
      ruleVersion: requireOpaqueId(raw.ruleVersion, 'provenance.generator.ruleVersion'),
      evidenceHash: requireString(raw.evidenceHash, 'provenance.generator.evidenceHash', {
        max: 64,
        pattern: sha256Pattern,
      }),
    };
  }
  return {
    evidenceHashes,
    generator,
    sourceKind: requireString(provenance.sourceKind, 'provenance.sourceKind', {
      max: 64,
      pattern: /^(fixture|export|firebaseRead)$/,
    }),
  };
}

function containsSensitiveField(value) {
  if (!value || typeof value !== 'object') return false;
  if (Array.isArray(value)) return value.some(containsSensitiveField);
  return Object.entries(value).some(([key, nested]) => (
    sensitiveFieldPattern.test(key) || containsSensitiveField(nested)
  ));
}

function validateManifest(manifest) {
  requirePlainRecord(manifest, 'manifest');
  if (manifest.manifestSchemaVersion !== SOURCE_SCHEMA_VERSION) {
    throw new MigrationInventoryError(
      errorCodes.unsupportedSchemaVersion,
      `Only ${SOURCE_SCHEMA_VERSION} is supported.`,
    );
  }
  if (manifest.canonicalEncodingVersion !== CANONICAL_ENCODING_VERSION
      || manifest.mapperVersion !== MAPPER_VERSION
      || manifest.classificationRulesVersion !== CLASSIFICATION_RULES_VERSION) {
    throw new MigrationInventoryError(
      errorCodes.unsupportedSchemaVersion,
      'Manifest versions do not match this inventory tool.',
    );
  }
  const source = requirePlainRecord(manifest.source, 'manifest.source');
  const associationId = requireOpaqueId(source.associationId, 'source.associationId');
  const normalizedSource = {
    adapterCheckpointSha256: source.adapterCheckpointSha256 === undefined
      ? null
      : requireString(source.adapterCheckpointSha256, 'source.adapterCheckpointSha256', {
        max: 64,
        pattern: sha256Pattern,
      }),
    associationId,
    exportIdentifier: requireString(source.exportIdentifier, 'source.exportIdentifier', {max: 256}),
    projectOrExportId: requireString(source.projectOrExportId, 'source.projectOrExportId', {max: 256}),
  };
  const syntheticRules = Array.isArray(manifest.syntheticRules)
    ? manifest.syntheticRules.map((rule) => {
      requirePlainRecord(rule, 'syntheticRule');
      return {
        generatorId: requireOpaqueId(rule.generatorId, 'syntheticRule.generatorId'),
        ruleVersion: requireOpaqueId(rule.ruleVersion, 'syntheticRule.ruleVersion'),
      };
    }).sort((a, b) => asciiCompare(canonicalEncode(a), canonicalEncode(b)))
    : [];
  if (!Array.isArray(manifest.records)) {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'manifest.records must be an array.');
  }
  if (manifest.records.length > MAX_RECORDS) {
    throw new MigrationInventoryError(errorCodes.oversizedReport, 'Source record count exceeds the bounded limit.');
  }
  const records = manifest.records.map((raw) => {
    requirePlainRecord(raw, 'source record');
    const entityType = requireString(raw.entityType, 'record.entityType', {max: 128});
    if (!Object.prototype.hasOwnProperty.call(targetTypes, entityType)) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Source record uses an unsupported entity type.',
      );
    }
    const sourcePath = validateSourcePath(raw.sourcePath, associationId);
    const sourceKey = validateSourceKey(raw.sourceKey);
    const data = requirePlainRecord(raw.data, 'record.data');
    canonicalEncode(data);
    return {
      classificationEvidence: normalizeEvidence(raw),
      data,
      entityType,
      provenance: normalizeProvenance(raw),
      references: Array.isArray(raw.references)
        ? raw.references.map((reference) => validateReference(reference, associationId))
          .sort((a, b) => asciiCompare(canonicalEncode(a), canonicalEncode(b)))
        : [],
      scope: normalizeScope(raw.scope, associationId),
      sourceCollection: requireString(raw.sourceCollection, 'record.sourceCollection', {max: 256}),
      sourceKey,
      sourcePath,
      sourceSchemaVersion: raw.sourceSchemaVersion === null
        ? null
        : requireString(raw.sourceSchemaVersion, 'record.sourceSchemaVersion', {max: 128}),
      temporalEvidence: validateTemporalInterval(normalizeTemporalEvidence(raw.temporalEvidence)),
    };
  });
  return {records, source: normalizedSource, syntheticRules};
}

function normalizeTemporalEvidence(raw) {
  const evidence = raw === undefined || raw === null ? {} : requirePlainRecord(raw, 'temporalEvidence');
  return {
    effectiveFrom: normalizeImportFact(evidence.effectiveFrom, 'not_recorded'),
    effectiveTo: normalizeImportFact(evidence.effectiveTo, 'not_recorded'),
  };
}

function normalizeImportFact(raw, defaultReason) {
  if (raw === undefined || raw === null) {
    return {reasonCode: defaultReason, state: 'unknown', value: null};
  }
  requirePlainRecord(raw, 'temporal fact');
  if (raw.state === 'known') {
    const value = requireString(raw.value, 'temporal fact value', {max: 64});
    const parsed = Date.parse(value);
    if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== value) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Known temporal facts must use canonical ISO-8601 UTC timestamps.',
      );
    }
    return {
      reasonCode: null,
      state: 'known',
      value,
    };
  }
  if (raw.state === 'unknown') {
    if (raw.value !== null) {
      throw new MigrationInventoryError(errorCodes.malformedSource, 'Unknown temporal fact requires null.');
    }
    return {
      reasonCode: requireString(raw.reasonCode, 'temporal fact reasonCode', {max: 128}),
      state: 'unknown',
      value: null,
    };
  }
  if (raw.state === 'notApplicable') {
    if (raw.value !== null) {
      throw new MigrationInventoryError(errorCodes.malformedSource, 'Not-applicable temporal fact requires null.');
    }
    return {
      reasonCode: requireString(raw.reasonCode, 'temporal fact reasonCode', {max: 128}),
      state: 'notApplicable',
      value: null,
    };
  }
  throw new MigrationInventoryError(errorCodes.malformedSource, 'Temporal fact state is invalid.');
}

function validateTemporalInterval(temporalEvidence) {
  const from = temporalEvidence.effectiveFrom;
  const to = temporalEvidence.effectiveTo;
  if (from.state === 'known' && to.state === 'known'
      && Date.parse(from.value) >= Date.parse(to.value)) {
    throw new MigrationInventoryError(
      errorCodes.contradictorySource,
      'Known effectiveFrom must not be after effectiveTo.',
    );
  }
  return temporalEvidence;
}

function mappingId(associationId, sourceEntityType, targetEntityType, identity) {
  const digest = canonicalSha256({
    associationId,
    mapperNamespace: MAPPER_NAMESPACE,
    mapperVersion: MAPPER_VERSION,
    sourceEntityType,
    sourceIdentity: identity,
    targetEntityType,
  });
  const prefix = targetEntityType.replace(/[^A-Za-z0-9]/g, '').slice(0, 18).toLowerCase() || 'entity';
  return `${prefix}_${digest.slice(0, 48)}`;
}

function proposedPath(targetType, id, scope, mappingIds = {}, canonicalScope = {}) {
  const associationRoot = `associations/${scope.associationId}`;
  const seasonId = canonicalScope.seasonId || (targetType === 'season' ? id : null);
  const gameId = canonicalScope.gameId || (targetType === 'game' ? id : null);
  const seasonRoot = seasonId
    ? `${associationRoot}/competitions/${scope.competitionId}/seasons/${seasonId}`
    : null;
  const gameRoot = seasonRoot && gameId ? `${seasonRoot}/games/${gameId}` : null;
  switch (targetType) {
  case 'season': return seasonRoot;
  case 'division': return seasonRoot ? `${seasonRoot}/divisions/${id}` : null;
  case 'teamIdentity': return `${associationRoot}/teamIdentities/${id}`;
  case 'person': return `${associationRoot}/persons/${id}`;
  case 'player': return `${associationRoot}/players/${id}`;
  case 'teamEntry': return seasonRoot ? `${seasonRoot}/teamEntries/${id}` : null;
  case 'rosterMembership': return seasonRoot ? `${seasonRoot}/rosterMemberships/${id}` : null;
  case 'rosterMembershipVersion': return seasonRoot
    ? `${seasonRoot}/rosterMemberships/${mappingIds.rosterMembership}/versions/${id}`
    : null;
  case 'game': return gameRoot;
  case 'legacyStatSourceEvidence': return gameRoot ? `${gameRoot}/migrationStatEvidence/${id}` : null;
  case 'statRevisionEvidence': return gameRoot ? `${gameRoot}/migrationRevisionEvidence/${id}` : null;
  case 'gameParticipantEvidence': return gameRoot ? `${gameRoot}/migrationParticipantEvidence/${id}` : null;
  case 'rosterSnapshotParticipant': return gameRoot ? `${gameRoot}/migrationSnapshotParticipants/${id}` : null;
  case 'legacyAggregateEvidence': return seasonRoot ? `${seasonRoot}/migrationAggregateEvidence/${id}` : null;
  default: throw new MigrationInventoryError(errorCodes.malformedSource, 'Unsupported target entity type.');
  }
}

function scopeKey(scope, fields) {
  if (fields.some((field) => scope[field] === null)) return null;
  return canonicalEncode(Object.fromEntries(fields.map((field) => [field, scope[field]])));
}

function seasonScopeKey(scope) {
  return scopeKey(scope, ['associationId', 'competitionId', 'seasonId']);
}

function divisionScopeKey(scope) {
  return scopeKey(scope, ['associationId', 'competitionId', 'seasonId', 'divisionId']);
}

function scopeMissing(record) {
  const required = scopeRequirements[record.entityType] || [];
  return required.filter((field) => record.scope[field] === null);
}

function hasSyntheticEvidence(record, syntheticRules) {
  if (!record.provenance.generator) return false;
  return syntheticRules.some((rule) => (
    rule.generatorId === record.provenance.generator.generatorId
      && rule.ruleVersion === record.provenance.generator.ruleVersion
  ));
}

function relationshipContradictions(record, recordsByIdentity) {
  const contradictions = [...record.classificationEvidence.contradictions];
  for (const reference of record.references.filter((candidate) => candidate.required)) {
    const target = recordsByIdentity.get(`${reference.targetSourcePath}#${reference.targetSourceKey}`);
    if (!target) continue;
    const expectedType = (requiredRelationTargets[record.entityType] || {})[reference.relation];
    if (expectedType && target.entityType !== expectedType) {
      contradictions.push(`reference_${reference.relation}_target_type_mismatch`);
    }
    if (reference.targetEntityType !== null && reference.targetEntityType !== target.entityType) {
      contradictions.push(`reference_${reference.relation}_declared_type_mismatch`);
    }
    for (const field of ['associationId', 'competitionId', 'seasonId', 'divisionId', 'phaseId', 'gameId']) {
      if (record.scope[field] !== null && target.scope[field] !== null
          && record.scope[field] !== target.scope[field]) {
        contradictions.push(`scope_${field}_mismatch`);
      }
    }
  }
  if (record.entityType === 'legacyGame') {
    const home = record.references.find((reference) => reference.relation === 'homeTeam');
    const away = record.references.find((reference) => reference.relation === 'awayTeam');
    if (home && away && home.targetSourcePath === away.targetSourcePath
        && home.targetSourceKey === away.targetSourceKey) {
      contradictions.push('same_home_and_away_team');
    }
  }
  return [...new Set(contradictions)].sort();
}

function sourceSnapshotForPayload(payload) {
  return canonicalSha256({
    canonicalEncodingVersion: payload.canonicalEncodingVersion,
    classificationRulesVersion: payload.classificationRulesVersion,
    inventorySchemaVersion: payload.inventorySchemaVersion,
    mapperVersion: payload.mapperVersion,
    records: payload.records.map((record) => ({
      classificationEvidenceHash: record.provenanceEvidenceHash,
      entityType: record.entityType,
      fieldHash: record.fieldHash,
      occurrenceEvidenceHashes: record.occurrenceEvidenceHashes,
      provenance: record.provenance,
      referenceEdges: record.referenceEdges.map((edge) => ({
        relation: edge.relation,
        required: edge.required,
        targetEntityType: edge.targetEntityType,
        targetSourceIdentity: edge.targetSourceIdentity,
      })),
      scope: record.scope,
      sourceCollection: record.sourceCollection,
      sourceIdentity: record.sourceIdentity,
      sourceSchemaVersion: record.sourceSchemaVersion,
      sourceOccurrences: record.sourceOccurrences,
      temporalEvidence: record.temporalEvidence,
    })),
    source: payload.source,
    syntheticRules: payload.syntheticRules,
  });
}

function buildInventory(manifest, {pageSize = MAX_PAGE_SIZE, previousReport = null} = {}) {
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
    throw new MigrationInventoryError(
      errorCodes.oversizedPage,
      `Page size must be between 1 and ${MAX_PAGE_SIZE}.`,
    );
  }
  const normalized = validateManifest(manifest);
  const sorted = [...normalized.records].sort((a, b) => {
    const identityOrder = asciiCompare(sourceIdentity(a), sourceIdentity(b));
    if (identityOrder !== 0) return identityOrder;
    return asciiCompare(canonicalEncode(a), canonicalEncode(b));
  });
  const recordsByIdentity = new Map();
  const changedHashIdentities = new Set();
  const changedHashDetails = new Map();
  const sourceOccurrences = new Map();
  const occurrenceEvidenceHashes = new Map();
  const fieldHashesByIdentity = new Map();
  for (const record of sorted) {
    const identity = sourceIdentity(record);
    sourceOccurrences.set(identity, (sourceOccurrences.get(identity) || 0) + 1);
    if (!recordsByIdentity.has(identity)) recordsByIdentity.set(identity, record);
    const occurrenceHashes = occurrenceEvidenceHashes.get(identity) || [];
    occurrenceHashes.push(canonicalSha256(record));
    occurrenceEvidenceHashes.set(identity, occurrenceHashes);
    const fieldHashes = fieldHashesByIdentity.get(identity) || [];
    fieldHashes.push(canonicalSha256(record.data));
    fieldHashesByIdentity.set(identity, fieldHashes);
  }
  for (const [identity] of recordsByIdentity) {
    const fieldHashes = [...new Set(fieldHashesByIdentity.get(identity))].sort();
    if (fieldHashes.length > 1) {
      changedHashIdentities.add(identity);
      changedHashDetails.set(identity, {
        expectedSourceFieldHash: fieldHashes[0],
        observedSourceFieldHashes: fieldHashes,
      });
    }
    occurrenceEvidenceHashes.set(
      identity,
      [...new Set(occurrenceEvidenceHashes.get(identity))].sort(),
    );
  }
  if (previousReport) verifyEnvelope(previousReport, REPORT_SCHEMA_VERSION);
  const priorHashes = previousReport ? priorSourceHashes(previousReport) : new Map();
  for (const [identity, record] of recordsByIdentity) {
    const priorHash = priorHashes.get(canonicalSha256(identity));
    if (priorHash && priorHash !== canonicalSha256(record.data)) {
      changedHashIdentities.add(identity);
      const observed = changedHashDetails.get(identity)?.observedSourceFieldHashes
        || [canonicalSha256(record.data)];
      changedHashDetails.set(identity, {
        expectedSourceFieldHash: priorHash,
        observedSourceFieldHashes: [...new Set(observed)].sort(),
      });
    }
  }

  const seasonIdentitiesByScope = new Map();
  const divisionIdentitiesByScope = new Map();
  for (const record of recordsByIdentity.values()) {
    const targetMap = record.entityType === 'season'
      ? seasonIdentitiesByScope
      : record.entityType === 'division' ? divisionIdentitiesByScope : null;
    if (!targetMap) continue;
    const key = record.entityType === 'season' ? seasonScopeKey(record.scope) : divisionScopeKey(record.scope);
    if (!key) continue;
    const values = targetMap.get(key) || [];
    values.push(sourceIdentity(record));
    targetMap.set(key, values.sort());
  }

  const inventoryRecords = [];
  for (const record of recordsByIdentity.values()) {
    const identity = sourceIdentity(record);
    const missingScope = scopeMissing(record);
    const missingRelations = Object.keys(requiredRelationTargets[record.entityType] || {}).filter((relation) => (
      !record.references.some((reference) => reference.required && reference.relation === relation)
    ));
    const seasonCandidates = record.entityType === 'season' || record.scope.seasonId === null
      ? []
      : seasonIdentitiesByScope.get(seasonScopeKey(record.scope)) || [];
    const divisionCandidates = !divisionScopedEntityTypes.has(record.entityType)
      || record.scope.divisionId === null
      ? []
      : divisionIdentitiesByScope.get(divisionScopeKey(record.scope)) || [];
    if (record.entityType !== 'season' && record.scope.seasonId !== null && seasonCandidates.length !== 1) {
      missingRelations.push('seasonScope');
    }
    if (divisionScopedEntityTypes.has(record.entityType)
        && record.scope.divisionId !== null && divisionCandidates.length !== 1) {
      missingRelations.push('divisionScope');
    }
    const orphaned = record.references.filter((reference) => (
      reference.required
        && !recordsByIdentity.has(`${reference.targetSourcePath}#${reference.targetSourceKey}`)
    ));
    const contradictions = relationshipContradictions(record, recordsByIdentity);
    const synthetic = hasSyntheticEvidence(record, normalized.syntheticRules);
    const evidence = record.classificationEvidence.independentEvidence;
    const recordClassifications = new Set([synthetic ? 'synthetic' : evidence.length ? 'evidenced' : 'unverified']);
    if (orphaned.length || missingRelations.length) recordClassifications.add('orphaned');
    if (contradictions.length || changedHashIdentities.has(identity)) recordClassifications.add('contradictory');
    if (record.classificationEvidence.duplicateCandidate || sourceOccurrences.get(identity) > 1) {
      recordClassifications.add('duplicateCandidate');
    }
    if (record.classificationEvidence.privacyRestrictedFields.length || containsSensitiveField(record.data)) {
      recordClassifications.add('privacyRestricted');
    }
    const orderedClassifications = classifications.filter((value) => recordClassifications.has(value));
    const issues = [];
    if (missingScope.length) issues.push({code: errorCodes.missingScope, fields: missingScope});
    if (orphaned.length || missingRelations.length) issues.push({
      code: errorCodes.orphanedReference,
      relations: [...new Set([
        ...missingRelations,
        ...orphaned.map((reference) => reference.relation),
      ])].sort(),
    });
    if (contradictions.length) issues.push({
      code: errorCodes.contradictorySource,
      contradictionCodes: contradictions,
    });
    if (changedHashIdentities.has(identity)) issues.push({
      code: errorCodes.changedSourceHash,
      ...changedHashDetails.get(identity),
    });
    if (record.classificationEvidence.duplicateCandidate || sourceOccurrences.get(identity) > 1) {
      issues.push({
        code: errorCodes.duplicateCandidate,
        sourceOccurrences: sourceOccurrences.get(identity),
      });
    }
    if (recordClassifications.has('privacyRestricted')) issues.push({code: errorCodes.privacyRestricted});
    const blocked = missingScope.length > 0
      || orphaned.length > 0
      || missingRelations.length > 0
      || contradictions.length > 0
      || changedHashIdentities.has(identity)
      || record.classificationEvidence.duplicateCandidate !== null
      || sourceOccurrences.get(identity) > 1
      || recordClassifications.has('privacyRestricted');
    inventoryRecords.push({
      blocked,
      classifications: orderedClassifications,
      contradictionCodes: contradictions,
      duplicateCandidate: record.classificationEvidence.duplicateCandidate,
      entityType: record.entityType,
      fieldHash: canonicalSha256(record.data),
      issues,
      provenance: record.provenance,
      provenanceEvidenceHash: canonicalSha256({
        classificationEvidence: record.classificationEvidence,
        provenance: record.provenance,
      }),
      occurrenceEvidenceHashes: occurrenceEvidenceHashes.get(identity),
      referenceEdges: record.references.map((reference) => ({
        ...reference,
        targetSourceIdentity: `${reference.targetSourcePath}#${reference.targetSourceKey}`,
      })),
      scope: record.scope,
      sourceCollection: record.sourceCollection,
      sourceIdentity: identity,
      sourceIdentityHash: canonicalSha256(identity),
      sourceKey: record.sourceKey,
      sourcePath: record.sourcePath,
      sourceSchemaVersion: record.sourceSchemaVersion,
      sourceOccurrences: sourceOccurrences.get(identity),
      temporalEvidence: record.temporalEvidence,
      containerSourceIdentities: [...seasonCandidates, ...divisionCandidates].sort(),
    });
  }
  inventoryRecords.sort((a, b) => asciiCompare(a.sourceIdentity, b.sourceIdentity));
  const inventoryByIdentity = new Map(inventoryRecords.map((record) => [record.sourceIdentity, record]));
  let dependencyChanged = true;
  while (dependencyChanged) {
    dependencyChanged = false;
    for (const record of inventoryRecords) {
      const requiredIdentities = [
        ...record.containerSourceIdentities,
        ...record.referenceEdges.filter((edge) => edge.required).map((edge) => edge.targetSourceIdentity),
      ];
      const dependencyIsIneligible = (identity) => {
        const dependency = inventoryByIdentity.get(identity);
        return dependency && (dependency.blocked || dependency.classifications.includes('synthetic'));
      };
      const blockedRelations = record.referenceEdges.filter((edge) => (
        edge.required && dependencyIsIneligible(edge.targetSourceIdentity)
      )).map((edge) => edge.relation);
      if (record.containerSourceIdentities.some(dependencyIsIneligible)) {
        blockedRelations.push('containerScope');
      }
      if (!record.blocked && requiredIdentities.some(dependencyIsIneligible)) {
        record.blocked = true;
        if (!record.classifications.includes('orphaned')) {
          record.classifications = classifications.filter((value) => (
            record.classifications.includes(value) || value === 'orphaned'
          ));
        }
        record.issues.push({
          code: errorCodes.orphanedReference,
          relations: [...new Set(blockedRelations)].sort(),
        });
        dependencyChanged = true;
      }
    }
  }
  const checkpoints = [];
  for (let index = 0; index < inventoryRecords.length; index += pageSize) {
    const page = inventoryRecords.slice(index, index + pageSize);
    checkpoints.push({
      firstSourceIdentityHash: page[0].sourceIdentityHash,
      lastSourceIdentityHash: page[page.length - 1].sourceIdentityHash,
      pageIndex: checkpoints.length,
      pageRecordCount: page.length,
      pageSha256: canonicalSha256(page.map((record) => ({
        fieldHash: record.fieldHash,
        sourceIdentity: record.sourceIdentity,
      }))),
    });
  }
  const snapshotPayload = {
    canonicalEncodingVersion: CANONICAL_ENCODING_VERSION,
    classificationRulesVersion: CLASSIFICATION_RULES_VERSION,
    inventorySchemaVersion: INVENTORY_SCHEMA_VERSION,
    mapperVersion: MAPPER_VERSION,
    records: inventoryRecords,
    source: normalized.source,
    syntheticRules: normalized.syntheticRules,
  };
  const sourceSnapshotSha256 = sourceSnapshotForPayload(snapshotPayload);
  const payload = {
    ...snapshotPayload,
    pagination: {checkpoints, maximumPageSize: MAX_PAGE_SIZE, pageSize},
    sourceSnapshotSha256,
  };
  return {payload, payloadSha256: canonicalSha256(payload)};
}

function priorSourceHashes(previousReport) {
  const envelope = requirePlainRecord(previousReport, 'previousReport');
  const payload = requirePlainRecord(envelope.payload, 'previousReport.payload');
  if (!Array.isArray(payload.rollbackSourceMappings)) {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'Previous report has no source mappings.');
  }
  const result = new Map();
  for (const mapping of payload.rollbackSourceMappings) {
    if (typeof mapping.sourceIdentityHash === 'string' && typeof mapping.sourceFieldHash === 'string') {
      result.set(mapping.sourceIdentityHash, mapping.sourceFieldHash);
    }
  }
  return result;
}

function targetProposalFields(
  record,
  targetEntityType,
  proposedId,
  mappingIds,
  referenceMappings,
  canonicalScope,
) {
  const base = {
    associationId: record.scope.associationId,
    dataSchemaVersion: 2,
    mapperVersion: MAPPER_VERSION,
    proposedId,
    sourceFieldHash: record.fieldHash,
    sourceIdentityHash: record.sourceIdentityHash,
    targetEntityType,
  };
  if (referenceMappings.length) base.referenceMappings = referenceMappings;
  if (['teamEntry', 'rosterMembership', 'rosterMembershipVersion', 'game',
    'legacyStatSourceEvidence', 'statRevisionEvidence', 'gameParticipantEvidence',
    'rosterSnapshotParticipant', 'legacyAggregateEvidence', 'season', 'division'].includes(targetEntityType)) {
    Object.assign(base, {
      competitionId: record.scope.competitionId,
      seasonId: canonicalScope.seasonId,
    });
  }
  if (targetEntityType === 'teamEntry') {
    base.divisionId = canonicalScope.divisionId;
    base.teamId = mappingIds.teamIdentity;
  }
  if (targetEntityType === 'player') base.personId = mappingIds.person;
  if (targetEntityType === 'rosterMembership' || targetEntityType === 'rosterMembershipVersion') {
    Object.assign(base, {
      effectiveFrom: record.temporalEvidence.effectiveFrom,
      effectiveTo: record.temporalEvidence.effectiveTo,
      playerId: mappingIds.player,
      teamEntryId: referenceMappings.find((mapping) => mapping.relation === 'team')?.proposedId || null,
    });
  }
  if (['game', 'legacyStatSourceEvidence', 'statRevisionEvidence',
    'gameParticipantEvidence', 'rosterSnapshotParticipant'].includes(targetEntityType)) {
    Object.assign(base, {
      divisionId: canonicalScope.divisionId,
      gameId: canonicalScope.gameId,
      phaseId: record.scope.phaseId,
    });
  }
  return base;
}

function buildDryRunReport(inventoryEnvelope) {
  verifyEnvelope(inventoryEnvelope, INVENTORY_SCHEMA_VERSION);
  const inventory = inventoryEnvelope.payload;
  const sanitizedRecords = [];
  const proposedCreates = [];
  const rollbackSourceMappings = [];
  const seenProposedIds = new Set();
  const seenProposedPaths = new Set();
  const inventoryByIdentity = new Map(
    inventory.records.map((record) => [record.sourceIdentity, record]),
  );
  const canonicalSeasons = new Map();
  const canonicalDivisions = new Map();
  for (const record of inventory.records) {
    if (record.entityType === 'season') {
      canonicalSeasons.set(seasonScopeKey(record.scope), mappingId(
        inventory.source.associationId, record.entityType, 'season', record.sourceIdentity,
      ));
    }
    if (record.entityType === 'division') {
      canonicalDivisions.set(divisionScopeKey(record.scope), mappingId(
        inventory.source.associationId, record.entityType, 'division', record.sourceIdentity,
      ));
    }
  }
  for (const record of inventory.records) {
    const sourceLabel = sourceLabelFor(record.sourceIdentity);
    const mappingIds = {};
    for (const targetEntityType of targetTypes[record.entityType]) {
      mappingIds[targetEntityType] = mappingId(
        inventory.source.associationId,
        record.entityType,
        targetEntityType,
        record.sourceIdentity,
      );
    }
    const referenceMappings = record.referenceEdges.flatMap((edge) => {
      const target = inventoryByIdentity.get(edge.targetSourceIdentity);
      if (!target) return [];
      const preferredTargetType = edge.relation.toLowerCase().includes('team')
        ? 'teamEntry'
        : edge.relation.toLowerCase().includes('game')
          ? 'game'
          : edge.relation.toLowerCase().includes('player')
            ? 'player'
            : targetTypes[target.entityType][0];
      if (!targetTypes[target.entityType].includes(preferredTargetType)) return [];
      return [{
        proposedId: mappingId(
          inventory.source.associationId,
          target.entityType,
          preferredTargetType,
          target.sourceIdentity,
        ),
        relation: edge.relation,
        targetEntityType: preferredTargetType,
      }];
    }).sort((a, b) => asciiCompare(canonicalEncode(a), canonicalEncode(b)));
    const canonicalScope = {
      divisionId: record.entityType === 'division'
        ? mappingIds.division
        : canonicalDivisions.get(divisionScopeKey(record.scope)) || null,
      gameId: record.entityType === 'legacyGame'
        ? mappingIds.game
        : referenceMappings.find((mapping) => mapping.relation === 'game')?.proposedId || null,
      seasonId: record.entityType === 'season'
        ? mappingIds.season
        : canonicalSeasons.get(seasonScopeKey(record.scope)) || null,
    };
    const hasMissingScope = record.issues.some((issue) => issue.code === errorCodes.missingScope);
    const proposals = targetTypes[record.entityType].map((targetEntityType) => {
      const proposedId = mappingIds[targetEntityType];
      if (seenProposedIds.has(proposedId)) {
        throw new MigrationInventoryError(
          errorCodes.nondeterminism,
          'Deterministic mapper produced an ID collision.',
        );
      }
      seenProposedIds.add(proposedId);
      const fields = targetProposalFields(
        record,
        targetEntityType,
        proposedId,
        mappingIds,
        referenceMappings,
        canonicalScope,
      );
      const destination = hasMissingScope
        ? null
        : proposedPath(targetEntityType, proposedId, record.scope, mappingIds, canonicalScope);
      if (destination && seenProposedPaths.has(destination)) {
        throw new MigrationInventoryError(
          errorCodes.nondeterminism,
          'Deterministic mapper produced a destination path collision.',
        );
      }
      if (destination) seenProposedPaths.add(destination);
      const proposal = {
        proposedFieldHash: canonicalSha256(fields),
        proposedId,
        proposedPath: destination,
        targetEntityType,
      };
      if (!record.blocked && !record.classifications.includes('synthetic')) {
        proposedCreates.push({...proposal, sourceLabel});
      }
      return proposal;
    });
    sanitizedRecords.push({
      blocked: record.blocked,
      classifications: record.classifications,
      entityType: record.entityType,
      fieldHash: record.fieldHash,
      issues: record.issues,
      proposedMappings: proposals,
      provenanceEvidenceHash: record.provenanceEvidenceHash,
      referenceMappings,
      sourceCollectionHash: canonicalSha256(record.sourceCollection),
      sourceIdentityHash: record.sourceIdentityHash,
      sourceLabel,
      sourceSchemaVersion: record.sourceSchemaVersion,
    });
    rollbackSourceMappings.push({
      proposedIds: proposals.map(({proposedId, targetEntityType}) => ({proposedId, targetEntityType})),
      sourceFieldHash: record.fieldHash,
      sourceIdentityHash: record.sourceIdentityHash,
      sourceLabel,
    });
  }
  sanitizedRecords.sort((a, b) => asciiCompare(a.sourceLabel, b.sourceLabel));
  proposedCreates.sort((a, b) => (
    asciiCompare(a.proposedPath, b.proposedPath) || asciiCompare(a.sourceLabel, b.sourceLabel)
  ));
  rollbackSourceMappings.sort((a, b) => asciiCompare(a.sourceLabel, b.sourceLabel));
  const byEntity = countBy(sanitizedRecords.map((record) => record.entityType));
  const byClassification = countBy(sanitizedRecords.flatMap((record) => record.classifications));
  const recordsFor = (classification) => sanitizedRecords
    .filter((record) => record.classifications.includes(classification))
    .map((record) => record.sourceLabel)
    .sort();
  const conflicts = sanitizedRecords.filter((record) => (
    record.issues.some((issue) => [errorCodes.contradictorySource, errorCodes.changedSourceHash].includes(issue.code))
  )).map((record) => ({issues: record.issues, sourceLabel: record.sourceLabel}));
  const unresolvedJoins = sanitizedRecords.filter((record) => (
    record.issues.some((issue) => [errorCodes.missingScope, errorCodes.orphanedReference].includes(issue.code))
  )).map((record) => ({issues: record.issues, sourceLabel: record.sourceLabel}));
  const payload = {
    canonicalEncodingVersion: CANONICAL_ENCODING_VERSION,
    classificationRulesVersion: CLASSIFICATION_RULES_VERSION,
    conflicts,
    counts: {
      blocked: sanitizedRecords.filter((record) => record.blocked).length,
      byClassification,
      byEntity,
      proposedCreates: proposedCreates.length,
      sourceRecords: sanitizedRecords.length,
    },
    dependencyOrder: [
      'season', 'division', 'teamIdentity', 'person', 'player', 'teamEntry',
      'rosterMembership', 'rosterMembershipVersion', 'game',
      'gameParticipantEvidence', 'rosterSnapshotParticipant',
      'legacyStatSourceEvidence', 'statRevisionEvidence', 'legacyAggregateEvidence',
    ],
    duplicateCandidates: recordsFor('duplicateCandidate'),
    errorCodeRegistry: errorCodes,
    estimatedBoundedOperations: {
      maximumReadPageSize: MAX_PAGE_SIZE,
      proposedCreateOperations: proposedCreates.length,
      sourceReadPages: inventory.pagination.checkpoints.length,
      writesExecuted: 0,
    },
    inventorySchemaVersion: INVENTORY_SCHEMA_VERSION,
    mapperNamespace: MAPPER_NAMESPACE,
    mapperVersion: MAPPER_VERSION,
    privacyRestrictions: recordsFor('privacyRestricted'),
    proposedCreates,
    reconciliationExpectations: {
      autoCertifications: 0,
      changedSourceHashesMustConflict: true,
      everyProposedCreateHasRollbackMapping: true,
      legacyApprovalGrantsCertification: false,
      remoteWrites: 0,
      sourceDocumentsMutated: 0,
      syntheticRecordsAutoCertified: 0,
    },
    records: sanitizedRecords,
    reportSchemaVersion: REPORT_SCHEMA_VERSION,
    rollbackSourceMappings,
    source: {
      adapterCheckpointSha256: inventory.source.adapterCheckpointSha256,
      associationId: inventory.source.associationId,
      exportIdentifierHash: canonicalSha256(inventory.source.exportIdentifier),
      projectOrExportIdHash: canonicalSha256(inventory.source.projectOrExportId),
    },
    sourceSnapshotSha256: inventory.sourceSnapshotSha256,
    syntheticExclusions: recordsFor('synthetic'),
    unresolvedJoins,
  };
  const envelope = {payload, payloadSha256: canonicalSha256(payload)};
  if (Buffer.byteLength(canonicalEncode(envelope), 'utf8') > MAX_REPORT_BYTES) {
    throw new MigrationInventoryError(errorCodes.oversizedReport, 'Dry-run report exceeds the bounded size.');
  }
  return envelope;
}

function countBy(values) {
  const result = {};
  for (const value of values) result[value] = (result[value] || 0) + 1;
  return Object.fromEntries(Object.entries(result).sort(([a], [b]) => asciiCompare(a, b)));
}

function verifyEnvelope(envelope, expectedSchema) {
  requirePlainRecord(envelope, 'envelope');
  requirePlainRecord(envelope.payload, 'envelope.payload');
  if (!sha256Pattern.test(envelope.payloadSha256 || '')) {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'Envelope payload hash is invalid.');
  }
  const actual = canonicalSha256(envelope.payload);
  if (actual !== envelope.payloadSha256) {
    throw new MigrationInventoryError(errorCodes.nondeterminism, 'Envelope payload hash does not reconcile.');
  }
  const schema = expectedSchema === REPORT_SCHEMA_VERSION
    ? envelope.payload.reportSchemaVersion
    : envelope.payload.inventorySchemaVersion;
  if (schema !== expectedSchema) {
    throw new MigrationInventoryError(errorCodes.unsupportedSchemaVersion, 'Envelope schema is unsupported.');
  }
  if (expectedSchema === INVENTORY_SCHEMA_VERSION
      && sourceSnapshotForPayload(envelope.payload) !== envelope.payload.sourceSnapshotSha256) {
    throw new MigrationInventoryError(
      errorCodes.nondeterminism,
      'Inventory source snapshot does not reconcile with its semantic evidence.',
    );
  }
  return actual;
}

function verifyReport(reportEnvelope, {inventoryEnvelope = null, compareEnvelope = null} = {}) {
  verifyEnvelope(reportEnvelope, REPORT_SCHEMA_VERSION);
  const report = reportEnvelope.payload;
  if (inventoryEnvelope) {
    verifyEnvelope(inventoryEnvelope, INVENTORY_SCHEMA_VERSION);
    if (report.sourceSnapshotSha256 !== inventoryEnvelope.payload.sourceSnapshotSha256) {
      throw new MigrationInventoryError(errorCodes.nondeterminism, 'Report does not match its inventory snapshot.');
    }
    const rebuilt = buildDryRunReport(inventoryEnvelope);
    if (canonicalEncode(rebuilt) !== canonicalEncode(reportEnvelope)) {
      throw new MigrationInventoryError(errorCodes.nondeterminism, 'Report cannot be reproduced from inventory.');
    }
  }
  if (compareEnvelope && canonicalEncode(reportEnvelope) !== canonicalEncode(compareEnvelope)) {
    throw new MigrationInventoryError(errorCodes.nondeterminism, 'Compared reports are not byte-identical.');
  }
  if (report.estimatedBoundedOperations.writesExecuted !== 0
      || report.reconciliationExpectations.remoteWrites !== 0
      || report.reconciliationExpectations.autoCertifications !== 0) {
    throw new MigrationInventoryError(errorCodes.attemptedWriteMode, 'Report claims a prohibited write or certification.');
  }
  return {
    payloadSha256: reportEnvelope.payloadSha256,
    proposedCreates: report.counts.proposedCreates,
    sourceRecords: report.counts.sourceRecords,
    sourceSnapshotSha256: report.sourceSnapshotSha256,
    verified: true,
  };
}

function ensurePrivateOutputDirectory(outputDir, repoRoot) {
  const resolvedRepo = path.resolve(repoRoot);
  const realRepo = fs.realpathSync(resolvedRepo);
  const localRoot = path.join(resolvedRepo, '.local');
  const allowedRoot = path.join(localRoot, 'stat-migration');
  const resolved = path.resolve(outputDir);
  if (resolved !== allowedRoot && !resolved.startsWith(`${allowedRoot}${path.sep}`)) {
    throw new MigrationInventoryError(
      errorCodes.unsafePath,
      'Output directory must stay under .local/stat-migration.',
    );
  }
  for (const directory of [localRoot, allowedRoot]) {
    if (fs.existsSync(directory) && fs.lstatSync(directory).isSymbolicLink()) {
      throw new MigrationInventoryError(errorCodes.unsafePath, 'Private output roots cannot be symbolic links.');
    }
    if (!fs.existsSync(directory)) fs.mkdirSync(directory, {mode: 0o700});
    if (!fs.lstatSync(directory).isDirectory()) {
      throw new MigrationInventoryError(errorCodes.unsafePath, 'Private output root is not a directory.');
    }
  }
  if (fs.realpathSync(allowedRoot) !== path.join(realRepo, '.local', 'stat-migration')) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Private output root resolves outside the repository.');
  }
  fs.chmodSync(allowedRoot, 0o700);
  const relative = path.relative(allowedRoot, resolved);
  let cursor = allowedRoot;
  for (const segment of relative.split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, segment);
    if (fs.existsSync(cursor) && fs.lstatSync(cursor).isSymbolicLink()) {
      throw new MigrationInventoryError(errorCodes.unsafePath, 'Private output paths cannot contain symbolic links.');
    }
    if (!fs.existsSync(cursor)) fs.mkdirSync(cursor, {mode: 0o700});
    if (!fs.lstatSync(cursor).isDirectory()) {
      throw new MigrationInventoryError(errorCodes.unsafePath, 'Private output path is not a directory.');
    }
  }
  const realAllowed = fs.realpathSync(allowedRoot);
  const realResolved = fs.realpathSync(resolved);
  if (realResolved !== realAllowed && !realResolved.startsWith(`${realAllowed}${path.sep}`)) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Output directory resolves outside the private root.');
  }
  fs.chmodSync(resolved, 0o700);
  return resolved;
}

function writePrivateCanonicalJson(filePath, value) {
  let target = null;
  try {
    target = fs.lstatSync(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (target) {
    if (target.isSymbolicLink() || !target.isFile()) {
      throw new MigrationInventoryError(errorCodes.unsafePath, 'Private output file must be a regular file.');
    }
  }
  const temporaryPath = `${filePath}.tmp`;
  try {
    fs.unlinkSync(temporaryPath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const descriptor = fs.openSync(temporaryPath, 'wx', 0o600);
  try {
    fs.writeFileSync(descriptor, `${canonicalEncode(value)}\n`, 'utf8');
  } finally {
    fs.closeSync(descriptor);
  }
  fs.renameSync(temporaryPath, filePath);
  fs.chmodSync(filePath, 0o600);
}

function redactError(error) {
  const code = error && error.code && Object.values(errorCodes).includes(error.code)
    ? error.code
    : errorCodes.malformedSource;
  if (!(error instanceof MigrationInventoryError) || error.code !== code) {
    return `${code}: Inventory failed safely; inspect the private operator context.`;
  }
  return `${code}: ${error.message}`;
}

module.exports = {
  CANONICAL_ENCODING_VERSION,
  CLASSIFICATION_RULES_VERSION,
  INVENTORY_SCHEMA_VERSION,
  MAPPER_NAMESPACE,
  MAPPER_VERSION,
  MAX_PAGE_SIZE,
  MAX_RECORDS,
  MAX_REPORT_BYTES,
  MigrationInventoryError,
  REPORT_SCHEMA_VERSION,
  SOURCE_SCHEMA_VERSION,
  buildDryRunReport,
  buildInventory,
  asciiCompare,
  canonicalEncode,
  canonicalSha256,
  classifications,
  ensurePrivateOutputDirectory,
  errorCodes,
  mappingId,
  redactError,
  sourceLabelFor,
  validateManifest,
  verifyEnvelope,
  verifyReport,
  writePrivateCanonicalJson,
};
