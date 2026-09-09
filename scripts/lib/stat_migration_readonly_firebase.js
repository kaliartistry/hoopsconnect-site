'use strict';

const {asciiCompare, canonicalEncode, canonicalSha256, errorCodes, MigrationInventoryError,
  MAX_PAGE_SIZE, MAX_RECORDS} = require('./stat_migration_inventory');

const MAX_PROVIDER_COLLECTIONS = 100;
const MAX_PROVIDER_RESPONSE_BYTES = 4 * 1024 * 1024;
const PROVIDER_TIMEOUT_MS = 30000;
const stableEmbeddedKeyField = /^(?:id|[A-Za-z][A-Za-z0-9_]*(?:Id|Key))$/;

function requirePlainRecord(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new MigrationInventoryError(errorCodes.malformedSource, `${label} must be an object.`);
  }
  return value;
}

function requireText(value, label) {
  if (typeof value !== 'string' || !value || value.length > 2048) {
    throw new MigrationInventoryError(errorCodes.malformedSource, `${label} is missing or invalid.`);
  }
  return value;
}

function decodeFirestoreValue(value) {
  requirePlainRecord(value, 'Firestore value');
  if (Object.prototype.hasOwnProperty.call(value, 'nullValue')) return null;
  if (Object.prototype.hasOwnProperty.call(value, 'booleanValue')) return Boolean(value.booleanValue);
  if (Object.prototype.hasOwnProperty.call(value, 'integerValue')) {
    const parsed = Number(value.integerValue);
    if (!Number.isSafeInteger(parsed)) {
      return {firestoreInteger: String(value.integerValue)};
    }
    return parsed;
  }
  if (Object.prototype.hasOwnProperty.call(value, 'doubleValue')) {
    return {firestoreDouble: String(value.doubleValue)};
  }
  if (Object.prototype.hasOwnProperty.call(value, 'timestampValue')) {
    return {firestoreTimestamp: String(value.timestampValue)};
  }
  if (Object.prototype.hasOwnProperty.call(value, 'stringValue')) return String(value.stringValue);
  if (Object.prototype.hasOwnProperty.call(value, 'bytesValue')) {
    return {firestoreBytesSha256: canonicalSha256(String(value.bytesValue))};
  }
  if (Object.prototype.hasOwnProperty.call(value, 'referenceValue')) {
    const reference = String(value.referenceValue);
    const marker = '/documents/';
    return {firestoreReference: reference.includes(marker) ? reference.split(marker)[1] : reference};
  }
  if (Object.prototype.hasOwnProperty.call(value, 'geoPointValue')) {
    const point = requirePlainRecord(value.geoPointValue, 'geoPointValue');
    return {
      firestoreGeoPoint: {
        latitude: String(point.latitude),
        longitude: String(point.longitude),
      },
    };
  }
  if (Object.prototype.hasOwnProperty.call(value, 'arrayValue')) {
    const values = value.arrayValue && Array.isArray(value.arrayValue.values)
      ? value.arrayValue.values
      : [];
    return values.map(decodeFirestoreValue);
  }
  if (Object.prototype.hasOwnProperty.call(value, 'mapValue')) {
    return decodeFirestoreFields(value.mapValue ? value.mapValue.fields : {});
  }
  throw new MigrationInventoryError(errorCodes.malformedSource, 'Unsupported Firestore value kind.');
}

function decodeFirestoreFields(fields) {
  requirePlainRecord(fields || {}, 'Firestore fields');
  return Object.fromEntries(
    Object.entries(fields || {}).map(([key, value]) => [key, decodeFirestoreValue(value)]),
  );
}

function readField(record, dottedPath) {
  return String(dottedPath).split('.').reduce((value, key) => (
    value && typeof value === 'object' ? value[key] : undefined
  ), record);
}

function normalizedCollectionPath(collectionPath, associationId) {
  requireText(collectionPath, 'provider collectionPath');
  if (collectionPath.startsWith('/') || collectionPath.endsWith('/') || collectionPath.includes('\\')
      || collectionPath.includes('//')) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Provider collection path is unsafe.');
  }
  const segments = collectionPath.split('/');
  if (segments.length % 2 === 0 || segments.some((segment) => !segment || segment === '.' || segment === '..')) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Provider collection path is unsafe.');
  }
  if (segments[0] === 'associations' && segments[1] !== associationId) {
    throw new MigrationInventoryError(
      errorCodes.crossAssociationReference,
      'Provider collection crosses the selected association boundary.',
    );
  }
  return segments;
}

function listDocumentsUrl(baseUrl, collectionPath, pageSize, pageToken) {
  const segments = collectionPath.split('/');
  const collectionId = segments.pop();
  const parent = segments.map(encodeURIComponent).join('/');
  const target = `${baseUrl}${parent ? `/${parent}` : ''}/${encodeURIComponent(collectionId)}`;
  const query = new URLSearchParams({
    orderBy: '__name__',
    pageSize: String(pageSize),
    showMissing: 'false',
  });
  if (pageToken) query.append('pageToken', pageToken);
  return `${target}?${query.toString()}`;
}

async function readCollection({baseUrl, bearerToken, collectionPath, fetchImpl, pageSize}) {
  const documents = [];
  const checkpoints = [];
  const seenPageTokens = new Set();
  let pageToken = null;
  let previousDocumentName = null;
  do {
    if (checkpoints.length > Math.ceil(MAX_RECORDS / pageSize) + 1) {
      throw new MigrationInventoryError(errorCodes.oversizedReport, 'Provider page bound exceeded.');
    }
    const url = listDocumentsUrl(baseUrl, collectionPath, pageSize, pageToken);
    const response = await fetchImpl(url, {
      headers: bearerToken ? {Authorization: `Bearer ${bearerToken}`} : {},
      method: 'GET',
      redirect: 'error',
      signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
    });
    if (!response || !response.ok) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        `Read-only Firestore request failed with HTTP ${response ? response.status : 'unknown'}.`,
      );
    }
    const body = await response.json();
    if (Buffer.byteLength(JSON.stringify(body), 'utf8') > MAX_PROVIDER_RESPONSE_BYTES) {
      throw new MigrationInventoryError(errorCodes.oversizedReport, 'Provider response byte bound exceeded.');
    }
    const page = Array.isArray(body.documents) ? body.documents : [];
    if (page.length > pageSize) {
      throw new MigrationInventoryError(errorCodes.oversizedPage, 'Provider returned an oversized page.');
    }
    for (const document of page) {
      requireText(document.name, 'Firestore document name');
      if (previousDocumentName !== null && asciiCompare(previousDocumentName, document.name) >= 0) {
        throw new MigrationInventoryError(
          errorCodes.contradictorySource,
          'Provider documents are not strictly ordered by document ID.',
        );
      }
      previousDocumentName = document.name;
      documents.push(document);
      if (documents.length > MAX_RECORDS) {
        throw new MigrationInventoryError(errorCodes.oversizedReport, 'Provider record bound exceeded.');
      }
    }
    checkpoints.push({
      documentCount: page.length,
      firstDocumentNameHash: page.length ? canonicalSha256(page[0].name) : null,
      lastDocumentNameHash: page.length ? canonicalSha256(page[page.length - 1].name) : null,
      pageIndex: checkpoints.length,
      pageSha256: canonicalSha256(page.map((document) => ({
        fieldsHash: canonicalSha256(document.fields || {}),
        nameHash: canonicalSha256(document.name),
      }))),
    });
    pageToken = typeof body.nextPageToken === 'string' && body.nextPageToken
      ? body.nextPageToken
      : null;
    if (pageToken) {
      if (seenPageTokens.has(pageToken)) {
        throw new MigrationInventoryError(errorCodes.contradictorySource, 'Provider repeated a page token.');
      }
      seenPageTokens.add(pageToken);
    }
  } while (pageToken);
  return {checkpoints, documents};
}

function firestoreDocumentPath(name) {
  const marker = '/documents/';
  const index = name.indexOf(marker);
  if (index < 0) {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'Firestore document name is invalid.');
  }
  return name.slice(index + marker.length);
}

function scopeFor(data, spec, associationId, sourceKey) {
  const raw = {...(spec.scope || {})};
  for (const [scopeField, dataField] of Object.entries(spec.scopeFields || {})) {
    raw[scopeField] = readField(data, dataField);
  }
  if (spec.gameIdFromDocumentId === true) raw.gameId = sourceKey;
  raw.associationId = raw.associationId || associationId;
  return raw;
}

function referencesFor(data, spec) {
  return (spec.referenceFields || []).flatMap((referenceSpec) => {
    requirePlainRecord(referenceSpec, 'reference field');
    const value = readField(data, requireText(referenceSpec.field, 'reference field name'));
    if ((value === undefined || value === null || value === '') && referenceSpec.required === false) return [];
    if (typeof value !== 'string' || !value) {
      return [{
        relation: requireText(referenceSpec.relation, 'reference relation'),
        required: true,
        targetEntityType: referenceSpec.targetEntityType || null,
        targetSourceKey: '__missing_reference__',
        targetSourcePath: `${requireText(referenceSpec.targetCollectionPath, 'target collection path')}/__missing_reference__`,
      }];
    }
    return [{
      relation: requireText(referenceSpec.relation, 'reference relation'),
      required: referenceSpec.required !== false,
      targetEntityType: referenceSpec.targetEntityType || null,
      targetSourceKey: value,
      targetSourcePath: `${requireText(referenceSpec.targetCollectionPath, 'target collection path')}/${value}`,
    }];
  });
}

function recordFromDocument(document, spec, associationId) {
  const sourcePath = firestoreDocumentPath(document.name);
  const sourceKey = sourcePath.split('/').pop();
  const data = decodeFirestoreFields(document.fields || {});
  return {
    classificationEvidence: spec.classificationEvidence || {},
    data,
    entityType: requireText(spec.entityType, 'provider entityType'),
    provenance: {
      evidenceHashes: Array.isArray(spec.provenanceEvidenceHashes) ? spec.provenanceEvidenceHashes : [],
      generator: spec.generator || null,
      sourceKind: 'firebaseRead',
    },
    references: referencesFor(data, spec),
    scope: scopeFor(data, spec, associationId, sourceKey),
    sourceCollection: spec.sourceCollection || spec.collectionPath,
    sourceKey,
    sourcePath,
    sourceSchemaVersion: typeof data.schemaVersion === 'string'
      ? data.schemaVersion
      : data.schemaVersion === undefined ? null : String(data.schemaVersion),
    temporalEvidence: spec.temporalEvidence || null,
  };
}

function embeddedRecords(parentRecord, spec) {
  const records = [];
  for (const embeddedSpec of spec.embeddedArrays || []) {
    if (embeddedSpec.keyField && !stableEmbeddedKeyField.test(embeddedSpec.keyField)) {
      throw new MigrationInventoryError(
        errorCodes.malformedSource,
        'Embedded keyField must name an explicit stable ID or key field.',
      );
    }
    const values = readField(parentRecord.data, embeddedSpec.field);
    if (!Array.isArray(values)) continue;
    values.forEach((value, index) => {
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new MigrationInventoryError(errorCodes.malformedSource, 'Embedded record must be an object.');
      }
      const embeddedKey = embeddedSpec.keyField ? readField(value, embeddedSpec.keyField) : null;
      const stableKey = typeof embeddedKey === 'string' && embeddedKey
        ? embeddedKey
        : String(index).padStart(6, '0');
      const references = referencesFor(value, embeddedSpec);
      if (embeddedSpec.parentRelation) {
        references.push({
          relation: requireText(embeddedSpec.parentRelation, 'embedded parentRelation'),
          required: true,
          targetEntityType: embeddedSpec.parentEntityType || parentRecord.entityType,
          targetSourceKey: parentRecord.sourceKey,
          targetSourcePath: parentRecord.sourcePath,
        });
      }
      records.push({
        classificationEvidence: embeddedSpec.classificationEvidence || {},
        data: value,
        entityType: requireText(embeddedSpec.entityType, 'embedded entityType'),
        provenance: parentRecord.provenance,
        references,
        scope: scopeFor(value, {
          scope: {...parentRecord.scope, ...(embeddedSpec.scope || {})},
          scopeFields: embeddedSpec.scopeFields || {},
        }, parentRecord.scope.associationId, stableKey),
        sourceCollection: embeddedSpec.sourceCollection || `${parentRecord.sourceCollection}.${embeddedSpec.field}`,
        sourceKey: `${parentRecord.sourceKey}:${embeddedSpec.field}:${stableKey}`,
        sourcePath: parentRecord.sourcePath,
        sourceSchemaVersion: embeddedSpec.sourceSchemaVersion || parentRecord.sourceSchemaVersion,
        temporalEvidence: embeddedSpec.temporalEvidence || null,
      });
    });
  }
  return records;
}

async function loadReadOnlyFirebaseManifest({
  baseUrl,
  bearerToken = null,
  fetchImpl = globalThis.fetch,
  manifest,
  pageSize = MAX_PAGE_SIZE,
}) {
  if (typeof fetchImpl !== 'function') {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'A fetch implementation is required.');
  }
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
    throw new MigrationInventoryError(errorCodes.oversizedPage, 'Firebase page size is outside the bounded limit.');
  }
  requirePlainRecord(manifest, 'provider manifest');
  const associationId = requireText(manifest.source && manifest.source.associationId, 'source association');
  if (!Array.isArray(manifest.providerCollections) || manifest.providerCollections.length === 0) {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'Firebase input requires providerCollections.');
  }
  if (manifest.providerCollections.length > MAX_PROVIDER_COLLECTIONS) {
    throw new MigrationInventoryError(errorCodes.oversizedReport, 'Provider collection bound exceeded.');
  }
  const records = Array.isArray(manifest.records) ? [...manifest.records] : [];
  const providerSnapshotMarkers = [];
  for (const spec of manifest.providerCollections) {
    requirePlainRecord(spec, 'provider collection');
    normalizedCollectionPath(spec.collectionPath, associationId);
    const result = await readCollection({
      baseUrl,
      bearerToken,
      collectionPath: spec.collectionPath,
      fetchImpl,
      pageSize,
    });
    providerSnapshotMarkers.push({
      collectionPath: spec.collectionPath,
      documents: result.documents.map((document) => ({
        fieldsHash: canonicalSha256(document.fields || {}),
        name: document.name,
      })),
    });
    for (const document of result.documents) {
      const parent = recordFromDocument(document, spec, associationId);
      records.push(parent, ...embeddedRecords(parent, spec));
      if (records.length > MAX_RECORDS) {
        throw new MigrationInventoryError(errorCodes.oversizedReport, 'Global provider record bound exceeded.');
      }
    }
  }
  providerSnapshotMarkers.sort((a, b) => asciiCompare(canonicalEncode(a), canonicalEncode(b)));
  return {
    ...manifest,
    providerCollections: undefined,
    records,
    source: {
      ...manifest.source,
      adapterCheckpointSha256: canonicalSha256(providerSnapshotMarkers),
    },
  };
}

module.exports = {
  decodeFirestoreFields,
  decodeFirestoreValue,
  listDocumentsUrl,
  loadReadOnlyFirebaseManifest,
  readCollection,
};
