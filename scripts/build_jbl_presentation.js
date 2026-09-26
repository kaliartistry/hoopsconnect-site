'use strict';

// LOCAL BUNDLE ONLY. No Firebase client, database reset, hosting or store action.
// Usage: node scripts/build_jbl_presentation.js [--check]
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {replaceNblPresentation} = require('./lib/jbl_presentation_import');
const root = path.resolve(__dirname, '..');
const staging = path.join(root, '.local/jbl-import-20260917');
const sourceDir = path.join(staging, 'source');
const source = JSON.parse(execFileSync(path.join(staging, 'venv/bin/python'), [
  path.join(__dirname, 'extract_jbl_first_round.py'),
  path.join(sourceDir, 'NBL total stats1ist round (1).xls'),
], {encoding: 'utf8', maxBuffer: 4e6}));
const destination = path.join(root, 'assets/demo/presentation_public_snapshot.json');
const baseline = JSON.parse(fs.readFileSync(destination, 'utf8'));
const next = replaceNblPresentation(baseline, source);
const encoded = `${JSON.stringify(next, null, 2)}\n`;
const logos = {full: 'jbl-full', sub: 'jbl-sub', foska: 'foska',
  tivoli: 'tivoli', slayers: 'slayers', warriors: 'warriors', raptors: 'raptors',
  flames: 'flames', eagles: 'eagles', knights: 'knights', celtics: 'celtics',
  rebels: 'rebels', spartans: 'spartans'};
if (process.argv.includes('--check')) {
  if (fs.readFileSync(destination, 'utf8') !== encoded) throw new Error('Bundle needs regeneration.');
  for (const [target, original] of Object.entries(logos)) {
    if (!fs.readFileSync(path.join(root, `assets/images/jbl_${target}.png`))
      .equals(fs.readFileSync(path.join(sourceDir, `${original}.png`)))) {
      throw new Error(`Logo differs from original: ${target}`);
    }
  }
} else {
  for (const saved of ['presentation_public_snapshot.json', 'seed_local_qa.js', 'share_demo_samples.dart']) {
    if (!fs.existsSync(path.join(staging, 'rollback', saved))) throw new Error('Missing rollback copy.');
  }
  for (const [target, original] of Object.entries(logos)) {
    fs.copyFileSync(path.join(sourceDir, `${original}.png`), path.join(root, `assets/images/jbl_${target}.png`));
  }
  fs.writeFileSync(destination, encoded);
}
console.log(`Local JBL bundle ${process.argv.includes('--check') ? 'verified' : 'generated'}: ${source.teams.length} teams, ${source.players.length} players, ${source.asOf}. No live services accessed.`);
