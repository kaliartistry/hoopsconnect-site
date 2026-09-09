# HoopsConnect vendored Unicode normalizer

This directory vendors the runtime source of `unorm_dart` 0.3.2 from its
published package. The upstream source is MIT licensed; the unchanged license
is retained in `LICENSE`.

- Package: `unorm_dart` 0.3.2
- Published archive SHA-256 recorded by Dart pub:
  `0c69186b03ca6addab0774bcc0f4f17b88d4ce78d9d4d8f0619e30a99ead58e7`
- Upstream repository: `https://github.com/yshrsmz/unorm-dart`
- Upstream release tag object: `3301bdc74e9644c69201db31e0daefb24fd10cd8`
- Audited upstream `master` at:
  `460e72da41a88e9b18d9180879347772345fb062`
- Unicode data version: 17.0, as declared by the package

The upstream release and audited `master` both use a strict upper-bound check
for the algorithmic Hangul syllable range in `lib/src/uchar.dart`. The Unicode
Hangul syllable range is U+AC00 through U+D7A3 inclusive, so the first scalar
outside the range, U+D7A4, must take the ordinary Unicode-data path. The local
patch changes only:

```diff
- (_SBase + _SCount < cp)
+ (_SBase + _SCount <= cp)
```

Without this correction, U+D7A4 is incorrectly decomposed into the distinct
Jamo sequence U+1113 U+1161, creating a canonical-hash collision. The patch is
at the source decision boundary; it never rewrites a normalized result and
therefore preserves legitimate Jamo input as distinct input.

Run `node scripts/verify_unicode_normalization_source.js` to verify the pinned
source manifest and the exact one-line boundary correction.
