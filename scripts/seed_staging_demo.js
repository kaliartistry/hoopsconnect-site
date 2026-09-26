#!/usr/bin/env node
'use strict';

const {createHash} = require('node:crypto');
const path = require('node:path');

const STAGING_PROJECT_ID = 'hoopsconnect-jba-staging';
const CONFIRMATION = `${STAGING_PROJECT_ID}:SEED_SYNTHETIC_DEMO`;
const firebaseAdmin = require(
  path.resolve(__dirname, '../functions/node_modules/firebase-admin'),
);
const {
  ASSOCIATION_ID,
  AUTHORIZATION_SCHEMA_VERSION,
  PASSWORD,
  publishQaPublicSnapshot,
  roles,
  seedIdentities,
  seedLeague,
} = require('./qa/seed_local_qa');

function requireSafeTarget(argv = process.argv.slice(2), env = process.env) {
  if (!argv.includes(`--confirm=${CONFIRMATION}`)) {
    throw new Error(
      `Refusing to seed. Pass --confirm=${CONFIRMATION} for the dedicated staging project.`,
    );
  }
  const ambientProject =
    env.GOOGLE_CLOUD_PROJECT || env.GCLOUD_PROJECT || env.CLOUDSDK_CORE_PROJECT;
  if (ambientProject && ambientProject !== STAGING_PROJECT_ID) {
    throw new Error(
      `Refusing to seed while the ambient project is ${ambientProject}.`,
    );
  }
}

async function activateStagingActors(auth, db) {
  for (const [role] of roles) {
    for (const dataset of ['full', 'empty']) {
      const uid = `qa-${role.toLowerCase()}${dataset === 'empty' ? '-empty' : ''}`;
      const associationId = dataset === 'full' ? ASSOCIATION_ID : 'jba-empty';
      const accountGenerationV2 = createHash('sha256')
        .update(`staging-generation:${uid}`)
        .digest('hex');
      const actorIdentity = {
        authIncarnationSchemaVersionV2: 2,
        authProjectIdV2: STAGING_PROJECT_ID,
        authTenantIdV2: null,
        authUidV2: uid,
        accountGenerationV2,
        accountLifecycleEpochV2: 1,
      };

      await auth.setCustomUserClaims(uid, {
        authIncarnationSchemaVersionV2: 2,
        accountGenerationV2,
        accountLifecycleEpochV2: 1,
      });
      await db.doc(`memberships/${uid}`).set({
        ...actorIdentity,
        membershipStatusV2: 'active',
      }, {merge: true});
      await db.doc(
        `associations/${associationId}/leagueActorAuthorities/${uid}`,
      ).set({
        schemaVersion: 1,
        ...actorIdentity,
        lifecycleStateV2: 'active',
        membershipStatusV2: 'active',
        reauthAfterSecV2: 0,
        associationId,
        authorizationSchemaVersion: AUTHORIZATION_SCHEMA_VERSION,
        operationalStateV2: 'operating',
        custodyStateV2: 'operating',
        custodyPolicyVersionV2: 1,
        identitySuppressedV2: false,
        privacyStateV2: 'internal',
        privacyEpochV2: 1,
      });
    }
  }
}

async function resetSyntheticStagingAssociations(db) {
  if (db.projectId !== STAGING_PROJECT_ID) {
    throw new Error(
      `Refusing to reset synthetic data in Firebase project ${db.projectId}.`,
    );
  }
  // These two associations exist only for the guarded presentation fixture.
  // The published snapshot remains available until the rebuilt data is ready.
  await db.recursiveDelete(db.doc(`associations/${ASSOCIATION_ID}`));
  await db.recursiveDelete(db.doc('associations/jba-empty'));
}

async function main() {
  requireSafeTarget();
  if (firebaseAdmin.apps.length !== 0) {
    throw new Error('Refusing to reuse an existing Firebase Admin app.');
  }
  firebaseAdmin.initializeApp({
    credential: firebaseAdmin.credential.applicationDefault(),
    projectId: STAGING_PROJECT_ID,
  });
  const db = firebaseAdmin.firestore();
  const auth = firebaseAdmin.auth();

  await resetSyntheticStagingAssociations(db);
  await seedIdentities(auth, db);
  await seedLeague(db, firebaseAdmin);
  await activateStagingActors(auth, db);
  const publicSnapshot = await publishQaPublicSnapshot(db);

  console.log(
    `HOOPSCONNECT_STAGING_SEED_OK project=${STAGING_PROJECT_ID} ` +
    `users=${roles.length * 2} games=${publicSnapshot.schedule.length} ` +
    `password=${PASSWORD}`,
  );
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.stack || error.message);
    process.exitCode = 1;
  });
}

module.exports = {
  CONFIRMATION,
  STAGING_PROJECT_ID,
  requireSafeTarget,
  resetSyntheticStagingAssociations,
};
