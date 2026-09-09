#!/usr/bin/env node

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const repositoryRoot = path.resolve(__dirname, "..");
const vendorRoot = path.join(repositoryRoot, "third_party/unorm_dart");
// These review anchors intentionally live in executable code rather than in
// the co-editable provenance manifest. A source change therefore requires an
// explicit, review-visible update to this verifier.
const trustedManifest = {
  package: "unorm_dart",
  version: "0.3.2",
  unicodeDataVersion: "17.0",
  publishedArchiveSha256: "0c69186b03ca6addab0774bcc0f4f17b88d4ce78d9d4d8f0619e30a99ead58e7",
  upstreamCommit: "460e72da41a88e9b18d9180879347772345fb062",
  upstreamTagObject: "3301bdc74e9644c69201db31e0daefb24fd10cd8",
  upstreamUcharSha256: "76092cd836be925a4a13d9033e9348fab141626f3e0454dda7eb243416b73a26",
  files: {
    "LICENSE": "8884fc22f0944465ab8fca4e934fef3db9ab2b3b14f95874f1d833aa75f81553",
    "lib/src/composite_iterator.dart": "8dd75df590e26b50cf624508ec5bebd6343f3f7576fb7ffc6ee3acb7a6ed1c4e",
    "lib/src/decomposite_iterator.dart": "f13b6b0f408ca8891d795b841ba117e3f047d8f5646911c415a04623543e2e03",
    "lib/src/iterator.dart": "01d12a5227cda4b810c0e749e898af1ad1628cb5fc0c4a1478f49372c133f662",
    "lib/src/recursive_decomposite_iterator.dart": "9d4757d61a623e985f516eb1d1ceae6fb66d3421264b6302d694b6dfcd342b28",
    "lib/src/uchar.dart": "d22e909bf283cc2f05549fbcbe41066959a8dcc212303ba63ea4de43c1ff8cd3",
    "lib/src/uchar_iterator.dart": "4dba958b779e352c2a1ab49c3148dcf380822bb2a4111f5ebdd7a80ac2cdfc2d",
    "lib/src/unorm_dart_base.dart": "40f71ac5cddce25fccd08e69c099b3ede9b114fc3e7fa57e2de31ddedbad1175",
    "lib/src/unormdata.dart": "3c25b618fef2ccce2d5e5b47eac096948c9900e5f3c2da7d39fe56f8ad77cc74",
    "lib/src/utils.dart": "35d03b962051a8b534285e559a7d6047d08cea39a4d185e1ff83ad88d2ae2458",
    "lib/unorm_dart.dart": "95ab0ca47a8a2c602e845e84c5bc76a15fd069efe68424bfe45526f1cb30fdea",
    "pubspec.yaml": "a1f517e14f11f32210f9c817bfe61585baaa41bf132cbd27eb9d8f1e23d2c3c3",
  },
};
const patchDocumentSha256 =
  "d6cfc0c0dea467c5170f93fe3ff1a2abc55fe438e9b93c722b62e3ad08ff373b";
const digest = (contents) => crypto.createHash("sha256").update(contents).digest("hex");
const manifest = JSON.parse(fs.readFileSync(
  path.join(vendorRoot, "source_manifest.json"),
  "utf8",
));

assert.deepEqual(manifest, trustedManifest, "source manifest differs from reviewed anchors");

for (const [relativePath, expected] of Object.entries(trustedManifest.files)) {
  const contents = fs.readFileSync(path.join(vendorRoot, relativePath));
  const actual = digest(contents);
  assert.equal(actual, expected, `${relativePath} differs from its reviewed source`);
}
assert.equal(
  digest(fs.readFileSync(path.join(vendorRoot, "HOOPSCONNECT_PATCH.md"))),
  patchDocumentSha256,
  "the reviewed patch explanation changed",
);

const uchar = fs.readFileSync(path.join(vendorRoot, "lib/src/uchar.dart"), "utf8");
assert.equal(
  uchar.split("(_SBase + _SCount <= cp)").length - 1,
  1,
  "the corrected Hangul upper-bound check must occur exactly once",
);
assert.equal(
  uchar.includes("(_SBase + _SCount < cp)"),
  false,
  "the collision-causing strict upper bound must not return",
);
const reconstructedUpstreamUchar = uchar.replace(
  "(_SBase + _SCount <= cp)",
  "(_SBase + _SCount < cp)",
);
assert.equal(
  digest(reconstructedUpstreamUchar),
  trustedManifest.upstreamUcharSha256,
  "uchar.dart must differ from reviewed upstream by only the Hangul boundary patch",
);

const dependency = fs.readFileSync(path.join(repositoryRoot, "pubspec.yaml"), "utf8");
assert.match(
  dependency,
  /unorm_dart:\s*\n\s+path: third_party\/unorm_dart/,
  "the application must resolve the reviewed repository copy",
);

console.log(
  `Verified ${Object.keys(trustedManifest.files).length} vendored files, ` +
    "immutable provenance anchors, the exact one-line Hangul patch, and the path dependency.",
);
