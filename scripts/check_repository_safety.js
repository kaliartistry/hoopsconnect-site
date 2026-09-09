#!/usr/bin/env node
'use strict';

const {execFileSync} = require('child_process');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const tracked = execFileSync('git', ['ls-files', '-z'], {
  cwd: repoRoot,
  encoding: 'utf8',
}).split('\0').filter(Boolean);

const forbiddenNamePatterns = [
  /(^|\/)\.env(?:\.|$)/,
  /\.(?:p8|p12|jks|keystore|mobileprovision)$/i,
  /(?:firebase|google-play|service)-service-account.*\.json$/i,
  /service-account.*\.json$/i,
  /android\/key\.properties$/i,
];
const secretContentPatterns = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /"type"\s*:\s*"service_account"/,
  /gh[pousr]_[A-Za-z0-9_]{30,}/,
  /xox[baprs]-[A-Za-z0-9-]{20,}/,
];
const textExtensions = new Set([
  '.dart', '.js', '.ts', '.json', '.yaml', '.yml', '.md', '.html', '.css',
  '.xml', '.gradle', '.kts', '.properties', '.plist', '.swift', '.kt', '.txt',
]);

const failures = [];
for (const relativePath of tracked) {
  if (forbiddenNamePatterns.some((pattern) => pattern.test(relativePath))) {
    failures.push('forbidden tracked credential filename: ' + relativePath);
    continue;
  }
  if (!textExtensions.has(path.extname(relativePath).toLowerCase())) continue;
  const content = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  if (secretContentPatterns.some((pattern) => pattern.test(content))) {
    failures.push('possible credential material in tracked file: ' + relativePath);
  }
}

const firebaserc = JSON.parse(
  fs.readFileSync(path.join(repoRoot, '.firebaserc'), 'utf8'),
);
if (firebaserc.projects?.default === 'hoops-connect-jm') {
  failures.push('default Firebase alias points at protected production');
}

for (const relativePath of [
  'scripts/seed_firestore.js',
  'scripts/seed_mock_league.js',
  'scripts/seed_nbl.js',
  'scripts/seed_season_games.js',
  'scripts/backfill_pending_game_stats.js',
  'scripts/audit_storage_migration.js',
  'scripts/audit_production_readiness_data.js',
  'scripts/stat_migration_inventory.js',
]) {
  const content = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  if (!content.includes('guardFirestoreTarget')) {
    failures.push('Firebase data script is missing target guard: ' + relativePath);
  }
}

const readOnlyInventoryCli = fs.readFileSync(
  path.join(repoRoot, 'scripts/stat_migration_inventory.js'),
  'utf8',
);
const readOnlyInventoryAdapter = fs.readFileSync(
  path.join(repoRoot, 'scripts/lib/stat_migration_readonly_firebase.js'),
  'utf8',
);
if (!readOnlyInventoryCli.includes("guardFirestoreTarget({argv, mode: 'read'})")) {
  failures.push('Stat migration Firebase mode is not explicitly guarded read-only.');
}
if (!readOnlyInventoryAdapter.includes("method: 'GET'")
    || !readOnlyInventoryAdapter.includes("orderBy: '__name__'")) {
  failures.push('Stat migration Firebase adapter is not bounded to ordered GET reads.');
}
for (const pattern of [
  /\.set\s*\(/,
  /\.update\s*\(/,
  /\.create\s*\(/,
  /\.delete\s*\(/,
  /batch\s*\(/,
  /runTransaction\s*\(/,
  /commit\s*\(/,
]) {
  if (pattern.test(readOnlyInventoryAdapter)) {
    failures.push('Stat migration Firebase adapter exposes a write-capable API.');
  }
}

for (const relativePath of [
  'scripts/seed_firestore.js',
  'scripts/seed_mock_league.js',
  'scripts/seed_nbl.js',
  'scripts/seed_season_games.js',
]) {
  const content = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
  if (!/port:\s*url\.port/.test(content)) {
    failures.push('REST script drops configured emulator port: ' + relativePath);
  }
}

if (failures.length) {
  console.error(failures.join('\n'));
  process.exit(1);
}
console.log(
  'Repository safety preflight passed for ' + tracked.length + ' tracked files.',
);
