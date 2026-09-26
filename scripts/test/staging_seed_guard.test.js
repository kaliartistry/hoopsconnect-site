'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  CONFIRMATION,
  STAGING_PROJECT_ID,
  requireSafeTarget,
} = require('../seed_staging_demo');

test('staging seed requires the exact confirmation', () => {
  assert.throws(() => requireSafeTarget([], {}), /Refusing to seed/);
  assert.doesNotThrow(() =>
    requireSafeTarget([`--confirm=${CONFIRMATION}`], {
      GCLOUD_PROJECT: STAGING_PROJECT_ID,
    }),
  );
});

test('staging seed rejects every other ambient project', () => {
  assert.throws(
    () =>
      requireSafeTarget([`--confirm=${CONFIRMATION}`], {
        GCLOUD_PROJECT: 'hoops-connect-jm',
      }),
    /ambient project is hoops-connect-jm/,
  );
});
