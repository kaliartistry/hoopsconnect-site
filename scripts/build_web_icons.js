'use strict';
// Deterministic packaging of the existing native icon, never AI regeneration.
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png');
const sizes = {'favicon.png': [64, 0.9], 'icons/Icon-192.png': [192, 0.9],
  'icons/Icon-512.png': [512, 0.9], 'icons/Icon-maskable-192.png': [192, 0.55],
  'icons/Icon-maskable-512.png': [512, 0.55]};
// 55% square sits inside the maskable safe circle (80% diameter).
for (const [name, [size, fraction]] of Object.entries(sizes)) {
  const out = path.join(root, 'web', name);
  const inner = Math.floor(size * fraction);
  execFileSync('sips', ['--resampleHeightWidth', `${inner}`, `${inner}`, source, '--out', out], {stdio:'pipe'});
  execFileSync('sips', ['--padToHeightWidth', `${size}`, `${size}`, '--padColor', '1B5E20', out, '--out', out], {stdio:'pipe'});
  const png = fs.readFileSync(out);
  if (png.readUInt32BE(16) !== size || png.readUInt32BE(20) !== size) throw Error('Incorrect icon size: '+name);
  console.log(`${name}: ${size} x ${size}, canonical native JBA artwork`);
}
