#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {guardFirestoreTarget, readFlag} = require('./lib/firebase_target_guard');
const {
  MAX_PAGE_SIZE,
  MigrationInventoryError,
  buildDryRunReport,
  buildInventory,
  canonicalEncode,
  ensurePrivateOutputDirectory,
  errorCodes,
  redactError,
  verifyReport,
  writePrivateCanonicalJson,
} = require('./lib/stat_migration_inventory');
const {loadReadOnlyFirebaseManifest} = require('./lib/stat_migration_readonly_firebase');

const repoRoot = path.resolve(__dirname, '..');
const defaultFixture = path.join(__dirname, 'fixtures/stat-migration/source-v1.json');
const allowedFlags = new Set([
  '--mode', '--input', '--output-dir', '--page-size', '--generated-at', '--previous-report',
  '--project', '--association', '--allow-production-read', '--allow-remote-nonprod',
  '--acknowledge-read-only',
]);

function parseArgs(argv) {
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) {
      throw new MigrationInventoryError(errorCodes.malformedSource, 'Positional arguments are not allowed.');
    }
    const name = arg.split('=', 1)[0];
    if (/write|apply|migrate|delete|update|create/i.test(name) || !allowedFlags.has(name)) {
      throw new MigrationInventoryError(
        /write|apply|migrate|delete|update|create/i.test(name)
          ? errorCodes.attemptedWriteMode
          : errorCodes.malformedSource,
        'Unsupported or write-capable flag was requested.',
      );
    }
    if (!arg.includes('=')) index += 1;
  }
  const mode = readFlag(argv, '--mode') || 'fixture';
  if (!['fixture', 'export', 'firebase'].includes(mode)) {
    throw new MigrationInventoryError(
      /write|apply|migrate|delete|update|create/i.test(mode)
        ? errorCodes.attemptedWriteMode
        : errorCodes.malformedSource,
      'Mode must be fixture, export, or firebase.',
    );
  }
  const input = readFlag(argv, '--input') || (mode === 'fixture' ? defaultFixture : null);
  if (!input) {
    throw new MigrationInventoryError(errorCodes.malformedSource, `${mode} mode requires --input.`);
  }
  const rawPageSize = readFlag(argv, '--page-size');
  const pageSize = rawPageSize === undefined ? MAX_PAGE_SIZE : Number(rawPageSize);
  if (!Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE) {
    throw new MigrationInventoryError(
      errorCodes.oversizedPage,
      `--page-size must be between 1 and ${MAX_PAGE_SIZE}.`,
    );
  }
  if (mode !== 'firebase' && [
    '--project', '--association', '--allow-production-read', '--allow-remote-nonprod',
    '--acknowledge-read-only',
  ].some((flag) => readFlag(argv, flag) !== undefined)) {
    throw new MigrationInventoryError(
      errorCodes.malformedSource,
      'Firebase target flags are valid only in firebase mode.',
    );
  }
  const rawGeneratedAt = readFlag(argv, '--generated-at');
  const generatedDate = rawGeneratedAt ? new Date(rawGeneratedAt) : new Date();
  if (!Number.isFinite(generatedDate.getTime())) {
    throw new MigrationInventoryError(errorCodes.malformedSource, '--generated-at must be a timestamp.');
  }
  return {
    associationId: readFlag(argv, '--association'),
    generatedAt: generatedDate.toISOString(),
    inputPath: path.resolve(input),
    mode,
    outputDir: path.resolve(readFlag(argv, '--output-dir') || '.local/stat-migration/latest'),
    pageSize,
    previousReportPath: readFlag(argv, '--previous-report')
      ? path.resolve(readFlag(argv, '--previous-report'))
      : null,
    projectId: readFlag(argv, '--project'),
    readOnlyAcknowledgement: readFlag(argv, '--acknowledge-read-only'),
  };
}

function readJson(filePath, {requireCanonical = false} = {}) {
  const stat = fs.lstatSync(filePath);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 32 * 1024 * 1024) {
    throw new MigrationInventoryError(errorCodes.unsafePath, 'Input must be a bounded regular JSON file.');
  }
  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed = JSON.parse(raw);
  if (requireCanonical && raw !== `${canonicalEncode(parsed)}\n`) {
    throw new MigrationInventoryError(errorCodes.nondeterminism, 'Artifact is not canonical JSON.');
  }
  return parsed;
}

async function getBearerToken(isEmulator) {
  if (isEmulator) return null;
  let applicationDefault;
  try {
    ({applicationDefault} = require('firebase-admin/app'));
  } catch {
    ({applicationDefault} = require('../functions/node_modules/firebase-admin/app'));
  }
  const token = await applicationDefault().getAccessToken();
  if (!token || typeof token.access_token !== 'string') {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'Unable to acquire read credentials.');
  }
  return token.access_token;
}

async function loadManifest(options, argv) {
  const manifest = readJson(options.inputPath);
  if (options.mode !== 'firebase') return manifest;
  if (!options.projectId || !options.associationId) {
    throw new MigrationInventoryError(
      errorCodes.malformedSource,
      'Firebase mode requires explicit --project and --association flags.',
    );
  }
  const acknowledgement = `${options.projectId}:${options.associationId}:NO_WRITES`;
  if (options.readOnlyAcknowledgement !== acknowledgement) {
    throw new MigrationInventoryError(
      errorCodes.attemptedWriteMode,
      'Firebase mode requires an exact project-and-association-bound read-only acknowledgement.',
    );
  }
  if (!manifest.source || manifest.source.associationId !== options.associationId
      || manifest.source.projectOrExportId !== options.projectId) {
    throw new MigrationInventoryError(
      errorCodes.crossAssociationReference,
      'Firebase flags do not match the explicit input manifest source.',
    );
  }
  const target = guardFirestoreTarget({argv, mode: 'read'});
  if (target.projectId !== options.projectId) {
    throw new MigrationInventoryError(errorCodes.malformedSource, 'Firebase target does not match --project.');
  }
  return loadReadOnlyFirebaseManifest({
    baseUrl: target.baseUrl,
    bearerToken: await getBearerToken(target.isEmulator),
    manifest,
    pageSize: options.pageSize,
  });
}

async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const manifest = await loadManifest(options, argv);
  const previousReport = options.previousReportPath
    ? readJson(options.previousReportPath, {requireCanonical: true})
    : null;
  const firstInventory = buildInventory(manifest, {pageSize: options.pageSize, previousReport});
  const firstReport = buildDryRunReport(firstInventory);
  const secondInventory = buildInventory(manifest, {pageSize: options.pageSize, previousReport});
  const secondReport = buildDryRunReport(secondInventory);
  verifyReport(firstReport, {inventoryEnvelope: firstInventory, compareEnvelope: secondReport});
  if (canonicalEncode(firstInventory) !== canonicalEncode(secondInventory)) {
    throw new MigrationInventoryError(errorCodes.nondeterminism, 'Repeated inventories differ.');
  }

  const outputDir = ensurePrivateOutputDirectory(options.outputDir, repoRoot);
  const inventoryPath = path.join(outputDir, 'operator-inventory.json');
  const reportPath = path.join(outputDir, 'canonical-report.json');
  const metadataPath = path.join(outputDir, 'run-metadata.json');
  writePrivateCanonicalJson(inventoryPath, firstInventory);
  writePrivateCanonicalJson(reportPath, firstReport);
  writePrivateCanonicalJson(metadataPath, {
    generatedAt: options.generatedAt,
    mode: options.mode,
    note: 'Incidental runtime metadata; excluded from semantic report and hashes.',
    reportPayloadSha256: firstReport.payloadSha256,
    sourceSnapshotSha256: firstInventory.payload.sourceSnapshotSha256,
  });
  const summary = {
    blockedRecords: firstReport.payload.counts.blocked,
    classifications: firstReport.payload.counts.byClassification,
    files: {
      canonicalReport: path.relative(repoRoot, reportPath),
      operatorInventory: path.relative(repoRoot, inventoryPath),
      runMetadata: path.relative(repoRoot, metadataPath),
    },
    mode: options.mode,
    noWrites: true,
    reportPayloadSha256: firstReport.payloadSha256,
    sourceRecords: firstReport.payload.counts.sourceRecords,
    sourceSnapshotSha256: firstInventory.payload.sourceSnapshotSha256,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(redactError(error));
    process.exitCode = 1;
  });
}

module.exports = {loadManifest, main, parseArgs, readJson};
