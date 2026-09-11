#!/usr/bin/env node
'use strict';

const {
  buildCandidate,
  cleanupIsolation,
  createIsolation,
  prepare,
  run,
  shellCommand,
  validateInvocation,
  verifyDeliveryGuard,
} = require('./qa/local_qa_runtime');

function main() {
  const {target, tools} = prepare();
  buildCandidate(tools);
  const isolation = createIsolation(tools);
  try {
    run(
      tools.node.path,
      [
        tools.firebase.entrypoint,
        'emulators:exec',
        '--config', target.config,
        '--project', target.projectId,
        '--only', 'auth,firestore,functions,storage',
        shellCommand(
          tools.node.path,
          ['scripts/qa/run_ephemeral_checks.js'],
          isolation.env,
        ),
      ],
      {env: isolation.env},
    );
    const guard = verifyDeliveryGuard(isolation.guardLog);
    console.log(
      `HOOPSCONNECT_QA_DELIVERY_GUARD_OK codebases=${guard.codebases.join(',')} ` +
      `workers=${guard.records}`,
    );
  } finally {
    cleanupIsolation(isolation);
  }
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {validateInvocation};
