'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const {
  notificationRecipientFromActiveMemberV2,
  sendAuthorizedNotificationChunksV2,
} = require('../lib/domain/notification_delivery_ad02_v2');

function binding(index, tenant = null, generation = 'a'.repeat(64), epoch = 7) {
  return Object.freeze({
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: tenant,
    authUidV2: `user_${index}`,
    accountGenerationV2: generation,
    accountLifecycleEpochV2: epoch,
  });
}

function recipient(index, overrides = {}) {
  return Object.freeze({
    binding: overrides.binding ?? binding(index),
    associationId: overrides.associationId ?? 'jba',
    fcmTokens: Object.freeze(overrides.fcmTokens ?? [`token-${index}`]),
    notificationPrefs: Object.freeze(overrides.notificationPrefs ?? {newPosts: true}),
  });
}

class MemoryDeliveryStore {
  constructor(events = []) {
    this.events = events;
    this.effect = null;
    this.attempts = new Map();
    this.activeTokens = null;
    this.failSubmitted = false;
    this.failComplete = false;
    this.expandReservation = false;
  }

  isActive(entry) {
    return this.activeTokens === null || this.activeTokens.has(entry.token);
  }

  async claimEffect(effect) {
    this.events.push(`claim-effect:${effect.effectClaimId}`);
    if (this.effect === null) {
      this.effect = structuredClone(effect);
      return 'created';
    }
    return JSON.stringify(this.effect) === JSON.stringify(effect) ? 'matching' : 'conflict';
  }

  async reserveAttempt(attempt) {
    this.events.push(`reserve:${attempt.chunkIndex}`);
    if (this.attempts.has(attempt.attemptId)) return {kind: 'duplicate'};
    let bindings = attempt.intended.filter((entry) => this.isActive(entry));
    if (this.expandReservation) {
      bindings = [...bindings, {
        recipient: binding('attacker'),
        token: 'attacker-token',
        tokenHash: '0'.repeat(64),
      }];
    }
    const state = bindings.length === 0 ? 'skipped' : 'reserved';
    this.attempts.set(attempt.attemptId, {state, barrier: false, attempt});
    return bindings.length === 0 ? {kind: 'skipped'} : {kind: 'reserved', bindings};
  }

  async commitDispatch(attempt) {
    this.events.push(`commit:${attempt.chunkIndex}`);
    const current = this.attempts.get(attempt.attemptId);
    if (!current || current.state !== 'reserved') return {kind: 'duplicate'};
    const bindings = attempt.intended.filter((entry) => this.isActive(entry));
    if (bindings.length === 0) {
      current.state = 'skipped';
      return {kind: 'skipped'};
    }
    current.state = 'dispatchCommitted';
    current.barrier = true;
    current.bindings = bindings;
    return {kind: 'committed', bindings};
  }

  async markSubmitted(attemptId) {
    this.events.push(`mark-submitted:${attemptId}`);
    if (this.failSubmitted) throw new Error('submitted persistence failed');
    const current = this.attempts.get(attemptId);
    assert.equal(current.state, 'dispatchCommitted');
    current.state = 'submitted';
  }

  async completeAndRelease(input) {
    this.events.push(`complete:${input.state}`);
    if (this.failComplete) throw new Error('terminal persistence failed');
    const current = this.attempts.get(input.attemptId);
    assert.equal(current.state, 'submitted');
    current.state = input.state;
    current.barrier = false;
    current.outcome = input;
  }
}

class MemoryProvider {
  constructor(events = []) {
    this.events = events;
    this.calls = [];
    this.payloadWasFrozen = false;
    this.failure = null;
    this.response = null;
  }

  async submit(input) {
    this.events.push(`provider:${input.chunkIndex}`);
    this.calls.push(structuredClone(input));
    this.payloadWasFrozen = Object.isFrozen(input.payload) && Object.isFrozen(input.payload.data);
    if (this.failure) throw this.failure;
    return this.response ?? {successCount: input.tokens.length, failureCount: 0};
  }
}

function request(store, provider, overrides = {}) {
  return {
    effectId: overrides.effectId ?? 'effect-001',
    authProjectIdV2: 'demo-hoopsconnect',
    authTenantIdV2: overrides.authTenantIdV2 ?? null,
    associationId: 'jba',
    capability: 'posts.acknowledge',
    payload: overrides.payload ?? {
      title: 'New post',
      body: 'A new post is ready.',
      data: {route: 'board'},
    },
    recipients: overrides.recipients ?? [recipient(1)],
    preference: 'newPosts',
    store,
    provider,
    hooks: overrides.hooks,
  };
}

test('delivery tokens come only from current exact V2 installation registrations', () => {
  const member = {
    scope: {
      authProjectIdV2: 'demo-hoopsconnect',
      authTenantIdV2: null,
      authUidV2: 'user_1',
    },
    accountGenerationV2: 'a'.repeat(64),
    accountLifecycleEpochV2: 7,
    associationId: 'jba',
    capabilities: ['members.read'],
    profile: {notificationPrefs: {newPosts: true}},
  };
  const current = {
    binding: {...binding(1)},
    associationId: 'jba',
    installationId: 'slot0',
    token: 'current-token',
  };
  const selected = notificationRecipientFromActiveMemberV2(member, [
    current,
    {...current, installationId: 'slot1', binding: binding(1, null, 'b'.repeat(64), 0), token: 'old-token'},
    {...current, installationId: 'slot2', binding: binding(1, 'tenant-a'), token: 'tenant-token'},
    {...current, installationId: 'slot3', associationId: 'other', token: 'other-token'},
  ]);
  assert.deepEqual(selected.fcmTokens, ['current-token']);
  current.binding.accountGenerationV2 = 'b'.repeat(64);
  assert.equal(selected.binding.accountGenerationV2, 'a'.repeat(64));
  assert.throws(() => notificationRecipientFromActiveMemberV2(
    member,
    Array.from({length: 9}, (_, index) => ({
      ...current,
      installationId: `slot${index}`,
    })),
  ), /Unbounded/);
});

test('effect and attempt identity bind project/tenant/UID/G/E and provider precedes submitted', async () => {
  const events = [];
  const store = new MemoryDeliveryStore(events);
  const provider = new MemoryProvider(events);
  const result = await sendAuthorizedNotificationChunksV2(request(
    store,
    provider,
    {
      authTenantIdV2: 'tenant-a',
      recipients: [recipient(1, {binding: binding(1, 'tenant-a')})],
    },
  ));
  assert.deepEqual(result, {
    reserved: 1,
    submitted: 1,
    skipped: 0,
    duplicates: 0,
    succeeded: 1,
    partial: 0,
    failed: 0,
  });
  const persisted = [...store.attempts.values()][0];
  assert.deepEqual(persisted.attempt.intended[0].recipient, binding(1, 'tenant-a'));
  assert.equal(persisted.attempt.authProjectIdV2, 'demo-hoopsconnect');
  assert.equal(persisted.attempt.authTenantIdV2, 'tenant-a');
  assert.equal(persisted.attempt.payloadHash, provider.calls[0].payloadHash);
  assert.deepEqual(provider.calls[0].payload, {
    title: 'New post',
    body: 'A new post is ready.',
    data: {route: 'board'},
  });
  assert.equal(provider.payloadWasFrozen, true);
  const providerIndex = events.findIndex((entry) => entry === 'provider:0');
  const submittedIndex = events.findIndex((entry) => entry.startsWith('mark-submitted:'));
  assert.ok(providerIndex >= 0 && submittedIndex > providerIndex, events.join('\n'));
  assert.equal(persisted.barrier, false);
  assert.equal(persisted.state, 'succeeded');
});

test('501-token delivery revalidates each chunk and suppresses a switched second chunk', async () => {
  const events = [];
  const store = new MemoryDeliveryStore(events);
  const provider = new MemoryProvider(events);
  const recipients = Array.from({length: 63}, (_, index) => recipient(index, {
    fcmTokens: Array.from({length: 8}, (_, tokenIndex) => `token-${index}-${tokenIndex}`),
  }));
  store.activeTokens = new Set(recipients.flatMap((value) => value.fcmTokens));
  const result = await sendAuthorizedNotificationChunksV2(request(store, provider, {
    recipients,
    hooks: {
      afterProviderInvocation(attempt) {
        if (attempt.chunkIndex === 0) store.activeTokens.clear();
      },
    },
  }));
  assert.equal(provider.calls.length, 1);
  assert.equal(provider.calls[0].tokens.length, 500);
  assert.equal(result.succeeded, 1);
  assert.equal(result.skipped, 1);
  assert.equal(result.submitted, 1);
});

test('token or lifecycle fence after reservation suppresses provider invocation', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  store.activeTokens = new Set(['token-1']);
  const result = await sendAuthorizedNotificationChunksV2(request(store, provider, {
    hooks: {
      afterReservation() {
        store.activeTokens.clear();
      },
    },
  }));
  assert.equal(provider.calls.length, 0);
  assert.equal(result.reserved, 1);
  assert.equal(result.skipped, 1);
  assert.equal(result.submitted, 0);
});

test('duplicate workers and retries never resubmit an existing attempt', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  const first = await sendAuthorizedNotificationChunksV2(request(store, provider));
  const second = await sendAuthorizedNotificationChunksV2(request(store, provider));
  assert.equal(first.succeeded, 1);
  assert.equal(second.duplicates, 1);
  assert.equal(second.submitted, 0);
  assert.equal(provider.calls.length, 1);
});

test('crash after dispatch commit is uncertain, barrier-held, and not retried', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider, {
      hooks: {
        afterDispatchCommit() {
          throw new Error('simulated crash before provider');
        },
      },
    })),
    /simulated crash/,
  );
  const attempt = [...store.attempts.values()][0];
  assert.equal(attempt.state, 'dispatchCommitted');
  assert.equal(attempt.barrier, true);
  assert.equal(provider.calls.length, 0);

  const retry = await sendAuthorizedNotificationChunksV2(request(store, provider));
  assert.equal(retry.duplicates, 1);
  assert.equal(provider.calls.length, 0);
});

test('provider invocation followed by submitted persistence failure stays uncertain', async () => {
  const events = [];
  const store = new MemoryDeliveryStore(events);
  const provider = new MemoryProvider(events);
  store.failSubmitted = true;
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider)),
    /submitted persistence failed/,
  );
  assert.equal(provider.calls.length, 1);
  const attempt = [...store.attempts.values()][0];
  assert.equal(attempt.state, 'dispatchCommitted');
  assert.equal(attempt.barrier, true);
  assert.ok(
    events.findIndex((entry) => entry === 'provider:0') <
      events.findIndex((entry) => entry.startsWith('mark-submitted:')),
  );
  store.failSubmitted = false;
  const retry = await sendAuthorizedNotificationChunksV2(request(store, provider));
  assert.equal(retry.duplicates, 1);
  assert.equal(provider.calls.length, 1);
});

test('provider rejection stays submitted and barrier-held for AD04 reconciliation', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  provider.failure = new Error('provider unavailable');
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider)),
    /provider unavailable/,
  );
  const attempt = [...store.attempts.values()][0];
  assert.equal(attempt.state, 'submitted');
  assert.equal(attempt.barrier, true);
  assert.equal(attempt.outcome, undefined);

  const retry = await sendAuthorizedNotificationChunksV2(request(store, provider));
  assert.equal(retry.duplicates, 1);
  assert.equal(provider.calls.length, 1);
});

test('invalid provider response stays submitted and barrier-held', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  provider.response = {successCount: 1, failureCount: 1};
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider)),
    /invalid uncertain outcome/,
  );
  const attempt = [...store.attempts.values()][0];
  assert.equal(attempt.state, 'submitted');
  assert.equal(attempt.barrier, true);
  assert.equal(attempt.outcome, undefined);
});

test('terminal persistence failure preserves submitted state and deletion barrier', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  store.failComplete = true;
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider)),
    /terminal persistence failed/,
  );
  const attempt = [...store.attempts.values()][0];
  assert.equal(attempt.state, 'submitted');
  assert.equal(attempt.barrier, true);
});

test('store cannot expand or swap an authority-bound reservation', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  store.expandReservation = true;
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider)),
    /expanded or changed authority/,
  );
  assert.equal(provider.calls.length, 0);
});

test('same effect ID with a changed token or generation is a conflict, not a new send', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  await sendAuthorizedNotificationChunksV2(request(store, provider));
  const changed = recipient(1, {
    binding: binding(1, null, 'b'.repeat(64), 8),
    fcmTokens: ['replacement-token'],
  });
  const result = await sendAuthorizedNotificationChunksV2(request(store, provider, {
    recipients: [changed],
  }));
  assert.equal(result.duplicates, 1);
  assert.equal(result.submitted, 0);
  assert.equal(provider.calls.length, 1);
});

test('same effect ID with a changed exact payload conflicts before resend', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  await sendAuthorizedNotificationChunksV2(request(store, provider));
  const result = await sendAuthorizedNotificationChunksV2(request(store, provider, {
    payload: {
      title: 'Changed post',
      body: 'Different provider-visible content.',
      data: {route: 'board'},
    },
  }));
  assert.equal(result.duplicates, 1);
  assert.equal(result.submitted, 0);
  assert.equal(provider.calls.length, 1);
});

test('one token claimed by two incarnation bindings fails closed', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  const result = await sendAuthorizedNotificationChunksV2(request(store, provider, {
    recipients: [
      recipient(1, {fcmTokens: ['shared-token']}),
      recipient(2, {
        binding: binding(2),
        fcmTokens: ['shared-token'],
      }),
    ],
  }));
  assert.deepEqual(result, {
    reserved: 0,
    submitted: 0,
    skipped: 0,
    duplicates: 0,
    succeeded: 0,
    partial: 0,
    failed: 0,
  });
  assert.equal(provider.calls.length, 0);
});

test('missing or false notification preference is never treated as opt-in', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  const result = await sendAuthorizedNotificationChunksV2(request(store, provider, {
    recipients: [
      recipient(1, {notificationPrefs: {}}),
      recipient(2, {notificationPrefs: {newPosts: false}}),
      recipient(3, {notificationPrefs: {newPosts: true}}),
    ],
  }));
  assert.equal(result.submitted, 1);
  assert.deepEqual(provider.calls[0].tokens, ['token-3']);
});

test('notification batches reject mixed project or tenant scope', async () => {
  const store = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(store, provider, {
      recipients: [
        recipient(1),
        recipient(2, {binding: binding(2, 'tenant-a')}),
      ],
    })),
    /Mixed-scope/,
  );
  assert.equal(provider.calls.length, 0);
  assert.equal(store.effect, null);
});

test('per-recipient and per-effect notification work is bounded', async () => {
  const provider = new MemoryProvider();
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(new MemoryDeliveryStore(), provider, {
      recipients: [recipient(1, {
        fcmTokens: Array.from({length: 9}, (_, index) => `token-${index}`),
      })],
    })),
    /oversized/,
  );
  await assert.rejects(
    sendAuthorizedNotificationChunksV2(request(new MemoryDeliveryStore(), provider, {
      recipients: Array.from({length: 201}, (_, index) => recipient(index)),
    })),
    /Invalid AD02 V2 notification request/,
  );
  assert.equal(provider.calls.length, 0);
});

test('effect identity binds exact project and tenant without separator ambiguity', async () => {
  const firstStore = new MemoryDeliveryStore();
  const secondStore = new MemoryDeliveryStore();
  const provider = new MemoryProvider();
  await sendAuthorizedNotificationChunksV2(request(firstStore, provider));
  await sendAuthorizedNotificationChunksV2(request(secondStore, provider, {
    authTenantIdV2: 'tenant-a',
    recipients: [recipient(1, {binding: binding(1, 'tenant-a')})],
  }));
  assert.notEqual(firstStore.effect.effectClaimId, secondStore.effect.effectClaimId);
  assert.equal(provider.calls.length, 2);
});
