#!/usr/bin/env node
'use strict';

const path = require('node:path');
const {readFlag} = require('./lib/firebase_target_guard');
const {MigrationInventoryError, errorCodes, redactError, verifyReport} = require('./lib/stat_migration_inventory');
const {readJson} = require('./stat_migration_inventory');

const allowedFlags = new Set(['--report', '--operator-inventory', '--compare']);

function parseArgs(argv) {
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith('--')) {
      throw new MigrationInventoryError(errorCodes.malformedSource, 'Positional arguments are not allowed.');
    }
    const name = arg.split('=', 1)[0];
    if (!allowedFlags.has(name)) {
      throw new MigrationInventoryError(errorCodes.malformedSource, 'Unsupported verification flag.');
    }
    if (!arg.includes('=')) index += 1;
  }
  const report = readFlag(argv, '--report');
  const inventory = readFlag(argv, '--operator-inventory');
  if (!report || !inventory) {
    throw new MigrationInventoryError(
      errorCodes.malformedSource,
      '--report and --operator-inventory are required.',
    );
  }
  return {
    compare: readFlag(argv, '--compare') ? path.resolve(readFlag(argv, '--compare')) : null,
    inventory: path.resolve(inventory),
    report: path.resolve(report),
  };
}

function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const result = verifyReport(readJson(options.report, {requireCanonical: true}), {
    compareEnvelope: options.compare ? readJson(options.compare, {requireCanonical: true}) : null,
    inventoryEnvelope: readJson(options.inventory, {requireCanonical: true}),
  });
  console.log(JSON.stringify({...result, noWrites: true}, null, 2));
  return result;
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(redactError(error));
    process.exitCode = 1;
  }
}

module.exports = {main, parseArgs};
