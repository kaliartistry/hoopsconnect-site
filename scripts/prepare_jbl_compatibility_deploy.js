#!/usr/bin/env node
'use strict';
// Generated deployment package explicitly exports only the legacy live trigger.
// Never change the dormant official-stat v2 module's default entrypoint.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
cp.execFileSync('npm', ['--prefix', path.join(root, 'public_functions'), 'run', 'build'], {stdio: 'inherit'});
const target = path.join(root, '.local/jbl-live-migration/compatibility-deploy');
fs.mkdirSync(target, {recursive: true});
fs.cpSync(path.join(root, 'public_functions/lib'), path.join(target, 'lib'), {recursive: true});
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'public_functions/package.json')));
pkg.main = 'lib/legacy_live.js';
delete pkg.scripts;
fs.writeFileSync(path.join(target, 'package.json'), JSON.stringify(pkg, null, 2));
fs.copyFileSync(path.join(root, 'public_functions/package-lock.json'), path.join(target, 'package-lock.json'));
cp.execFileSync('npm', ['ci', '--omit=dev', '--ignore-scripts', '--prefix', target], {stdio: 'inherit'});
const config = path.join(root, '.local/jbl-live-migration/firebase.compatibility.json');
fs.writeFileSync(config, JSON.stringify({functions: [{source: target, codebase: 'public',
  ignore: ['node_modules', '.git']}]}, null, 2));
console.log(config);
