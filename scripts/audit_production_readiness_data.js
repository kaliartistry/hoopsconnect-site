#!/usr/bin/env node
'use strict';

const admin = require('../functions/node_modules/firebase-admin');
const {createHash, createHmac, randomBytes} = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const authorizationSchema = require('../functions/src/authorization_schema_v1.json');
const {guardFirestoreTarget, readFlag} = require('./lib/firebase_target_guard');

const allowedFlags = new Set([
  '--project',
  '--allow-production-read',
  '--allow-remote-nonprod',
  '--association',
  '--bucket',
  '--output-dir',
]);

const modelCollections = [
  'seasons',
  'divisions',
  'teams',
  'players',
  'rosters',
  'events',
  'gameStats',
  'playerSeasonStats',
  'teamSeasonStats',
  'standings',
  'leaderboard',
];

function parseArgs(argv) {
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) {
      throw new Error('Positional arguments are not allowed.');
    }
    const name = arg.split('=', 1)[0];
    if (!allowedFlags.has(name)) {
      throw new Error(`Unsupported flag ${name}; this command is read-only.`);
    }
    if (!arg.includes('=')) index += 1;
  }
  const associationId = readFlag(argv, '--association');
  if (!associationId || !/^[A-Za-z0-9_-]+$/.test(associationId)) {
    throw new Error('--association must be an exact Firestore document ID.');
  }
  const outputDir = readFlag(argv, '--output-dir');
  if (!outputDir) throw new Error('--output-dir is required.');
  const resolvedOutputDir = path.resolve(outputDir);
  const allowedRoot = path.resolve('.local/production-readiness');
  if (resolvedOutputDir !== allowedRoot && !resolvedOutputDir.startsWith(`${allowedRoot}${path.sep}`)) {
    throw new Error('--output-dir must stay under .local/production-readiness.');
  }
  return {
    associationId,
    bucketName: readFlag(argv, '--bucket'),
    outputDir: resolvedOutputDir,
  };
}

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonicalize(value), null, 2) + '\n';
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function sanitizeErrorMessage(error) {
  return String(error?.message || error || 'read failed')
    .replace(/[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}/g, '[redacted-principal]')
    .replace(/(?:users|memberships|inviteCodes)\/[A-Za-z0-9_-]+/g, (value) => {
      return `${value.split('/')[0]}/[redacted-id]`;
    })
    .replace(/associations\/[A-Za-z0-9_-]+\/(?:posts|teams|documents)\/[A-Za-z0-9_-]+/g,
      (value) => `${value.split('/').slice(0, 3).join('/')}/[redacted-id]`)
    .replace(/https?:\/\/\S*(?:X-Goog-|token=)\S*/gi, '[redacted-url]')
    .replace(/Bearer\s+[A-Za-z0-9._~-]+/gi, 'Bearer [redacted]');
}

function pseudonym(key, kind, rawId) {
  return `${kind}_${createHmac('sha256', key)
    .update(`${kind}\u0000${rawId}`, 'utf8')
    .digest('hex').slice(0, 16)}`;
}

function distribution(values) {
  const counts = {};
  for (const value of values) {
    const label = value === undefined || value === null ? 'missing' : String(value);
    counts[label] = (counts[label] || 0) + 1;
  }
  return Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)));
}

function schemaDistribution(records) {
  return distribution(records.map((record) => record.data.schemaVersion));
}

function validRole(value) {
  return Object.prototype.hasOwnProperty.call(authorizationSchema.roles, value);
}

function recordLabel(key, kind, record) {
  return pseudonym(key, kind, record.id);
}

function safeReference(value) {
  return typeof value === 'string' && value.length > 0;
}

function buildPlan(snapshot, key) {
  const memberships = new Map(snapshot.memberships.map((record) => [record.id, record.data]));
  const profiles = new Map(snapshot.users.map((record) => [record.id, record]));
  const authIds = new Set(snapshot.authUserIds);
  const accountIds = [...new Set([...snapshot.authUserIds, ...profiles.keys()])];
  const userActions = accountIds.map((accountId) => {
    const record = profiles.get(accountId);
    const user = record?.data || {};
    const membership = memberships.get(accountId);
    const role = validRole(user.role) ? user.role : null;
    const conflicts = [];
    if (!authIds.has(accountId)) conflicts.push('auth_identity_missing');
    if (!record) conflicts.push('profile_missing');
    if (!membership) conflicts.push('membership_missing');
    if (user.authorizationSchemaVersion !== authorizationSchema.schemaVersion) {
      conflicts.push('user_authorization_schema_legacy');
    }
    if (user.associationId !== snapshot.associationId) conflicts.push('association_unverified');
    if (!role) conflicts.push('role_invalid');
    if (membership) {
      if (membership.authorizationSchemaVersion !== authorizationSchema.schemaVersion) {
        conflicts.push('membership_authorization_schema_legacy');
      }
      if (membership.status !== 'active') conflicts.push('membership_inactive');
      for (const field of ['associationId', 'role', 'teamId', 'divisionId']) {
        if ((membership[field] ?? null) !== (user[field] ?? null)) {
          conflicts.push(`profile_membership_${field}_mismatch`);
        }
      }
    }
    return {
      label: pseudonym(key, 'user', accountId),
      evidence: {
        authIdentityPresent: authIds.has(accountId),
        profilePresent: Boolean(record),
        legacyRoleLabel: role || 'invalid',
        associationMatchesTarget: user.associationId === snapshot.associationId,
        hasTeamScope: typeof user.teamId === 'string',
        hasDivisionScope: typeof user.divisionId === 'string',
        currentMembershipPresent: Boolean(membership),
      },
      conflicts: [...new Set(conflicts)].sort(),
      proposed: {
        profileOperation: record ? 'preserve_after_manual_review' : 'create_after_manual_review',
        operation: membership ? 'replace_after_manual_review' : 'create_after_manual_review',
        associationId: snapshot.associationId,
        roleCandidate: role,
        capabilitiesCandidate: role ? [...authorizationSchema.roles[role]].sort() : [],
        statusAfterApproval: 'active',
        currentDecision: 'fail_closed_manual_review_required',
      },
    };
  }).filter((action) => action.conflicts.length > 0)
    .sort((a, b) => a.label.localeCompare(b.label));

  const postActions = snapshot.posts
    .filter((record) => !['public', 'internal'].includes(record.data.visibility))
    .map((record) => ({
      label: recordLabel(key, 'post', record),
      evidence: {
        currentVisibility: 'missing_or_invalid',
        requiresAck: typeof record.data.requiresAck === 'boolean'
          ? record.data.requiresAck
          : 'missing_or_invalid',
        hasDivisionFilter: typeof record.data.divisionFilter === 'string',
      },
      proposed: {
        visibility: 'internal',
        reason: 'uncertain_legacy_items_never_default_public',
        requiresManualContentReviewBeforePublic: true,
      },
    }))
    .sort((a, b) => a.label.localeCompare(b.label));

  const inviteActions = snapshot.invites
    .filter((record) => record.data.credentialVersion !== 2
      || record.data.authorizationSchemaVersion !== authorizationSchema.schemaVersion)
    .map((record) => ({
      label: recordLabel(key, 'invite', record),
      evidence: {
        credentialVersion: record.data.credentialVersion ?? 'missing',
        authorizationSchemaVersion: record.data.authorizationSchemaVersion ?? 'missing',
        status: typeof record.data.status === 'string' ? record.data.status : 'missing',
      },
      proposed: {
        operation: 'revoke_legacy_invite',
        usesRemaining: 0,
        requireAuditRecord: true,
      },
    }))
    .sort((a, b) => a.label.localeCompare(b.label));

  const storageActions = snapshot.storageObjects
    .filter((record) => record.classification !== 'canonical_clean')
    .map((record) => ({
      label: pseudonym(key, 'object', record.name),
      evidence: {
        classification: record.classification,
        kind: record.kind,
        hasDownloadToken: record.hasDownloadToken,
        hasRequiredMetadata: record.hasRequiredMetadata,
      },
      proposed: {
        canonicalPath: `associations/${snapshot.associationId}/${record.kind}/${pseudonym(key, 'source', record.entityId)}/asset`,
        sourceRecord: `associations/${snapshot.associationId}/${record.kind}/${pseudonym(key, 'source', record.entityId)}`,
        attachPolicyMetadata: true,
        removeDownloadTokenMetadata: true,
        deleteLegacyObjectOnlyAfterVerifiedCopy: true,
      },
    }))
    .sort((a, b) => a.label.localeCompare(b.label));

  const referenceActions = [
    ...snapshot.posts.filter((record) => record.data.hasImageReference).map((record) => ({
      kind: 'post',
      label: recordLabel(key, 'post', record),
    })),
    ...snapshot.teams.filter((record) => record.data.hasLogoReference).map((record) => ({
      kind: 'team',
      label: recordLabel(key, 'team', record),
    })),
  ].map((record) => ({
    ...record,
    proposed: 'replace_download_url_with_authenticated_sdk_object_path',
  })).sort((a, b) => a.label.localeCompare(b.label));

  const collections = {};
  for (const name of modelCollections) {
    const records = snapshot.collections[name] || [];
    collections[name] = {
      documents: records.length,
      schemaVersions: schemaDistribution(records),
    };
  }
  const teamsWithRoster = snapshot.teams.filter((record) => record.data.rosterEntries > 0).length;
  const rosterEntries = snapshot.teams.reduce((sum, record) => sum + record.data.rosterEntries, 0);
  const gameEvents = snapshot.events.filter((record) => record.data.type === 'game');
  const gameStatsPlayerLines = snapshot.gameStats.reduce(
    (sum, record) => sum + record.data.playerLineEntries,
    0,
  );

  const summary = {
    projectId: snapshot.projectId,
    associationId: snapshot.associationId,
    readOnly: true,
    associationExists: snapshot.associationExists,
    auth: {
      identities: snapshot.authUserIds.length,
      identitiesMissingProfiles: snapshot.authUserIds.filter((id) => !profiles.has(id)).length,
      profilesMissingIdentities: snapshot.users.filter((record) => !authIds.has(record.id)).length,
    },
    users: {
      total: snapshot.users.length,
      legacyRoleLabels: distribution(snapshot.users.map((record) => record.data.role)),
      authorizationSchemaVersions: distribution(
        snapshot.users.map((record) => record.data.authorizationSchemaVersion),
      ),
    },
    memberships: {
      total: snapshot.memberships.length,
      statuses: distribution(snapshot.memberships.map((record) => record.data.status)),
      authorizationSchemaVersions: distribution(
        snapshot.memberships.map((record) => record.data.authorizationSchemaVersion),
      ),
    },
    posts: {
      total: snapshot.posts.length,
      visibility: distribution(snapshot.posts.map((record) => record.data.visibility)),
      requiresAck: distribution(snapshot.posts.map((record) => record.data.requiresAck)),
    },
    invites: {
      total: snapshot.invites.length,
      credentialVersions: distribution(snapshot.invites.map((record) => record.data.credentialVersion)),
      authorizationSchemaVersions: distribution(
        snapshot.invites.map((record) => record.data.authorizationSchemaVersion),
      ),
      statuses: distribution(snapshot.invites.map((record) => record.data.status)),
    },
    roster: {
      teamDocuments: snapshot.teams.length,
      teamsWithEmbeddedRoster: teamsWithRoster,
      embeddedPlayerEntries: rosterEntries,
    },
    games: {
      eventDocuments: snapshot.events.length,
      gameEvents: gameEvents.length,
      eventStatsStatuses: distribution(gameEvents.map((record) => record.data.statsStatus)),
      gameStatsDocuments: snapshot.gameStats.length,
      gameStatsStatuses: distribution(snapshot.gameStats.map((record) => record.data.status)),
      playerLinesEmbeddedInGameStats: gameStatsPlayerLines,
    },
    collections,
    storage: {
      objects: snapshot.storageObjects.length,
      legacyOrUnsafeObjects: storageActions.length,
      legacyUrlReferences: referenceActions.length,
    },
  };

  const blockers = [];
  if (userActions.length > 0) blockers.push(`manualMembershipReviews=${userActions.length}`);
  if (postActions.length > 0) blockers.push(`legacyPostVisibility=${postActions.length}`);
  if (inviteActions.length > 0) blockers.push(`legacyInvites=${inviteActions.length}`);
  if (storageActions.length > 0) blockers.push(`storageObjectActions=${storageActions.length}`);
  if (referenceActions.length > 0) blockers.push(`storageReferenceActions=${referenceActions.length}`);

  const sourceView = {
    summary,
    userActions,
    postActions,
    inviteActions,
    storageActions,
    referenceActions,
  };
  const sourceSnapshotSha256 = sha256(canonicalJson(sourceView));
  const planWithoutHash = {
    manifestVersion: 1,
    authorizationSchemaVersion: authorizationSchema.schemaVersion,
    summary,
    blockers,
    preconditions: [
      'approved_production_export_and_restore_drill_complete',
      'writes_paused_or_migration_conflicts_transactionally_rejected',
      'operator_mapping_reviewed_by_authorized_owner',
      'functions_client_indexes_and_rules_rollout_order_approved',
      'rollback_owner_and_window_recorded',
    ],
    proposedActions: {
      memberships: userActions,
      posts: postActions,
      invites: inviteActions,
      storageObjects: storageActions,
      storageReferences: referenceActions,
    },
    expectedDryRunDeltas: {
      membershipsCreatedOrReplacedAfterApproval: userActions.length,
      postsDefaultedInternal: postActions.length,
      legacyInvitesRevoked: inviteActions.length,
      storageObjectsCopiedThenRetired: storageActions.length,
      legacyUrlReferencesReplaced: referenceActions.length,
    },
    postconditions: [
      'all_profiles_have_exactly_one_matching_schema_v1_membership',
      'all_membership_capabilities_match_the_versioned_role_mapping',
      'all_posts_have_explicit_visibility_and_requiresAck',
      'all_legacy_invites_are_revoked_and_v2_only_queries_succeed',
      'storage_audit_has_zero_blockers_and_no_download_tokens',
      'production_foundation_audit_has_zero_blockers',
    ],
    rollbackRequirements: [
      'immutable_pre_migration_export',
      'verified_staging_restore',
      'operator_mapping_and_manifest_hashes',
      'previous_functions_rules_indexes_and_client_versions',
      'named_rollback_owner',
    ],
    verification: {sourceSnapshotSha256},
  };
  const planSha256 = sha256(canonicalJson(planWithoutHash));
  const plan = {
    ...planWithoutHash,
    verification: {...planWithoutHash.verification, planSha256},
  };
  const operatorMapping = {
    manifestVersion: 1,
    sourceSnapshotSha256,
    users: accountIds.map((accountId) => ({
      label: pseudonym(key, 'user', accountId),
      authUid: accountId,
      profilePath: profiles.has(accountId) ? `users/${accountId}` : null,
    })).sort((a, b) => a.label.localeCompare(b.label)),
    posts: snapshot.posts.map((record) => ({
      label: recordLabel(key, 'post', record),
      documentPath: `associations/${snapshot.associationId}/posts/${record.id}`,
    })).sort((a, b) => a.label.localeCompare(b.label)),
    storageObjects: snapshot.storageObjects.map((record) => ({
      label: pseudonym(key, 'object', record.name),
      objectName: record.name,
    })).sort((a, b) => a.label.localeCompare(b.label)),
    inviteNotice: 'Raw legacy invite document IDs are intentionally excluded. Re-scan and HMAC-match labels at execution time.',
  };
  return {plan, operatorMapping};
}

function ensurePrivateDirectory(directory) {
  fs.mkdirSync(directory, {recursive: true, mode: 0o700});
  fs.chmodSync(directory, 0o700);
}

function loadOrCreateKey(keyPath) {
  if (!fs.existsSync(keyPath)) {
    const descriptor = fs.openSync(keyPath, 'wx', 0o600);
    try {
      fs.writeFileSync(descriptor, randomBytes(32));
    } finally {
      fs.closeSync(descriptor);
    }
  }
  const stat = fs.lstatSync(keyPath);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('Pseudonym key must be a regular file.');
  fs.chmodSync(keyPath, 0o600);
  const key = fs.readFileSync(keyPath);
  if (key.length < 32) throw new Error('Pseudonym key must contain at least 32 bytes.');
  return key;
}

function writePrivateJson(filePath, value) {
  const temporaryPath = `${filePath}.tmp`;
  try {
    fs.unlinkSync(temporaryPath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const descriptor = fs.openSync(temporaryPath, 'wx', 0o600);
  try {
    fs.writeFileSync(descriptor, canonicalJson(value));
  } finally {
    fs.closeSync(descriptor);
  }
  fs.renameSync(temporaryPath, filePath);
  fs.chmodSync(filePath, 0o600);
}

function documentRecords(snapshot) {
  return snapshot.docs.map((doc) => ({id: doc.id, data: doc.data()}));
}

async function loadAuthUserIds(auth) {
  const ids = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    ids.push(...page.users.map((user) => user.uid));
    pageToken = page.pageToken;
  } while (pageToken);
  return ids.sort();
}

async function loadSnapshot(db, auth, bucket, projectId, associationId) {
  const association = db.doc(`associations/${associationId}`);
  const queries = {
    users: db.collection('users').select(
      'role', 'associationId', 'teamId', 'divisionId', 'authorizationSchemaVersion',
    ),
    memberships: db.collection('memberships').select(
      'role', 'associationId', 'teamId', 'divisionId', 'status',
      'capabilities', 'authorizationSchemaVersion',
    ),
    posts: association.collection('posts').select(
      'visibility', 'requiresAck', 'divisionFilter', 'authorizationSchemaVersion', 'schemaVersion', 'imageUrl',
    ),
    invites: db.collection('inviteCodes').select(
      'credentialVersion', 'authorizationSchemaVersion', 'status', 'associationId',
    ),
  };
  for (const name of modelCollections) {
    if (name === 'teams') {
      queries[name] = association.collection(name).select(
        'schemaVersion', 'authorizationSchemaVersion', 'roster', 'logoUrl',
      );
    } else if (name === 'events') {
      queries[name] = association.collection(name).select(
        'schemaVersion', 'authorizationSchemaVersion', 'type', 'statsStatus',
      );
    } else if (name === 'gameStats') {
      queries[name] = association.collection(name).select(
        'schemaVersion', 'authorizationSchemaVersion', 'status', 'playerLines',
      );
    } else {
      queries[name] = association.collection(name).select('schemaVersion', 'authorizationSchemaVersion');
    }
  }
  const entries = Object.entries(queries);
  const [associationSnap, authUserIds, ...snapshots] = await Promise.all([
    association.get(),
    loadAuthUserIds(auth),
    ...entries.map(([, query]) => query.get()),
  ]);
  const loaded = Object.fromEntries(
    entries.map(([name], index) => [name, documentRecords(snapshots[index])]),
  );
  loaded.posts = loaded.posts.map((record) => ({
    id: record.id,
    data: {
      ...record.data,
      hasImageReference: safeReference(record.data.imageUrl),
      imageUrl: undefined,
    },
  }));
  loaded.teams = loaded.teams.map((record) => ({
    id: record.id,
    data: {
      schemaVersion: record.data.schemaVersion,
      authorizationSchemaVersion: record.data.authorizationSchemaVersion,
      rosterEntries: Array.isArray(record.data.roster) ? record.data.roster.length : 0,
      hasLogoReference: safeReference(record.data.logoUrl),
    },
  }));
  loaded.events = loaded.events.map((record) => ({
    id: record.id,
    data: {
      schemaVersion: record.data.schemaVersion,
      authorizationSchemaVersion: record.data.authorizationSchemaVersion,
      type: record.data.type,
      statsStatus: record.data.statsStatus,
    },
  }));
  loaded.gameStats = loaded.gameStats.map((record) => ({
    id: record.id,
    data: {
      schemaVersion: record.data.schemaVersion,
      authorizationSchemaVersion: record.data.authorizationSchemaVersion,
      status: record.data.status,
      playerLineEntries: record.data.playerLines && typeof record.data.playerLines === 'object'
        ? Object.keys(record.data.playerLines).length
        : 0,
    },
  }));

  const [files] = await bucket.getFiles();
  const storageObjects = await Promise.all(files.map(async (file) => {
    const [metadata] = await file.getMetadata();
    const name = file.name;
    const match = /^(?:associations\/[^/]+\/)?(posts|teams|documents)\/([^/]+)\/[^/]+$/.exec(name);
    const custom = metadata.metadata && typeof metadata.metadata === 'object' ? metadata.metadata : {};
    const canonical = /^associations\/[^/]+\/(posts|teams|documents)\/[^/]+\/[^/]+$/.test(name);
    const kind = match ? match[1] : 'documents';
    const entityId = match ? match[2] : name;
    const hasDownloadToken = safeReference(custom.firebaseStorageDownloadTokens);
    const hasRequiredMetadata = safeReference(custom.associationId)
      && (safeReference(custom.postId) || safeReference(custom.teamId) || safeReference(custom.documentId));
    return {
      name,
      kind,
      entityId,
      hasDownloadToken,
      hasRequiredMetadata,
      classification: canonical && hasRequiredMetadata && !hasDownloadToken
        ? 'canonical_clean'
        : canonical ? 'canonical_unsafe' : 'legacy_or_unclassified',
    };
  }));

  return {
    projectId,
    associationId,
    associationExists: associationSnap.exists,
    authUserIds,
    users: loaded.users,
    memberships: loaded.memberships,
    posts: loaded.posts,
    invites: loaded.invites,
    teams: loaded.teams,
    events: loaded.events,
    gameStats: loaded.gameStats,
    collections: Object.fromEntries(
      modelCollections.map((name) => [name, loaded[name] || []]),
    ),
    storageObjects,
  };
}

function assertSanitized(plan, snapshot) {
  const serialized = canonicalJson(plan);
  const rawValues = [
    ...snapshot.users.map((record) => record.id),
    ...snapshot.authUserIds,
    ...snapshot.posts.map((record) => record.id),
    ...snapshot.invites.map((record) => record.id),
    ...snapshot.storageObjects.map((record) => record.name),
  ].filter((value) => typeof value === 'string' && value.length >= 8);
  for (const raw of rawValues) {
    if (serialized.includes(raw)) throw new Error('Sanitized plan contains a raw identifier.');
  }
  for (const forbidden of ['fcmTokens', 'firebaseStorageDownloadTokens', 'email', 'phone']) {
    if (serialized.includes(`"${forbidden}"`)) {
      throw new Error(`Sanitized plan contains forbidden field ${forbidden}.`);
    }
  }
}

function exitCodeForPlan(plan) {
  return Array.isArray(plan.blockers) && plan.blockers.length > 0 ? 1 : 0;
}

async function main() {
  const argv = process.argv.slice(2);
  const options = parseArgs(argv);
  const target = guardFirestoreTarget({argv, mode: 'read'});
  const allowedBuckets = new Set([
    `${target.projectId}.appspot.com`,
    `${target.projectId}.firebasestorage.app`,
  ]);
  if (!allowedBuckets.has(options.bucketName)) {
    throw new Error('--bucket must exactly match the selected Firebase project.');
  }
  ensurePrivateDirectory(options.outputDir);
  const keyPath = path.join(options.outputDir, 'pseudonym.key');
  const key = loadOrCreateKey(keyPath);
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: target.projectId,
      storageBucket: options.bucketName,
    });
  }
  const snapshot = await loadSnapshot(
    admin.firestore(), admin.auth(), admin.storage().bucket(), target.projectId, options.associationId,
  );
  const {plan, operatorMapping} = buildPlan(snapshot, key);
  assertSanitized(plan, snapshot);
  const planPath = path.join(options.outputDir, 'sanitized-plan.json');
  const mappingPath = path.join(options.outputDir, 'operator-map.json');
  writePrivateJson(planPath, plan);
  writePrivateJson(mappingPath, operatorMapping);
  console.log(JSON.stringify({
    projectId: target.projectId,
    associationId: options.associationId,
    readOnly: true,
    summary: plan.summary,
    blockers: plan.blockers,
    expectedDryRunDeltas: plan.expectedDryRunDeltas,
    verification: plan.verification,
    artifacts: {
      sanitizedPlan: path.relative(process.cwd(), planPath),
      operatorMap: path.relative(process.cwd(), mappingPath),
      pseudonymKey: path.relative(process.cwd(), keyPath),
      fileMode: '0600',
      directoryMode: '0700',
    },
  }, null, 2));
  process.exitCode = exitCodeForPlan(plan);
}

if (require.main === module) {
  main()
    .then(async () => {
      if (admin.apps.length > 0) await admin.app().delete();
    })
    .catch(async (error) => {
      console.error(sanitizeErrorMessage(error));
      process.exitCode = 1;
      if (admin.apps.length > 0) await admin.app().delete();
    });
}

module.exports = {
  assertSanitized,
  buildPlan,
  canonicalJson,
  exitCodeForPlan,
  loadOrCreateKey,
  parseArgs,
  pseudonym,
  sanitizeErrorMessage,
  writePrivateJson,
};
