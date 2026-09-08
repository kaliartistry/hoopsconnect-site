'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  capabilitiesMatchRole,
  evaluateProductionFoundationBlockers,
} = require('../audit_production_foundation');

function result(overrides = {}) {
  return Object.assign({
    usersMissingMemberships: 0,
    membershipsMissingUsers: 0,
    invalidUserAuthorizationSchemas: 0,
    inactiveMemberships: 0,
    invalidMembershipAuthorizationSchemas: 0,
    invalidMembershipCapabilities: 0,
    conflictingUserMembershipScopes: 0,
    postsMissingVisibility: 0,
    postsMissingRequiresAck: 0,
    publicPostsContainingAcknowledgments: 0,
    legacyInviteDocuments: 0,
  }, overrides);
}

test('production audit classifies clean evidence as non-blocking', () => {
  assert.deepEqual(evaluateProductionFoundationBlockers(result()), []);
  assert.equal(capabilitiesMatchRole('fan', ['association.read']), true);
  assert.equal(
    capabilitiesMatchRole('fan', ['association.read', 'association.manage']),
    false,
  );
  assert.equal(capabilitiesMatchRole('fan', ['association.read', 'association.read']), false);
});

test('production audit makes every unsafe migration condition blocking', () => {
  const blockers = evaluateProductionFoundationBlockers(result({
    usersMissingMemberships: 1,
    membershipsMissingUsers: 2,
    invalidUserAuthorizationSchemas: 3,
    inactiveMemberships: 4,
    invalidMembershipAuthorizationSchemas: 5,
    invalidMembershipCapabilities: 6,
    conflictingUserMembershipScopes: 7,
    postsMissingVisibility: 8,
    postsMissingRequiresAck: 9,
    publicPostsContainingAcknowledgments: 10,
    legacyInviteDocuments: 11,
  }));
  assert.equal(blockers.length, 10);
});
