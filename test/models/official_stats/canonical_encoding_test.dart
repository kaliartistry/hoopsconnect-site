import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';
import 'package:hoops_connect/models/official_stats/unicode_normalization.dart';

class _UnsupportedRecord {
  final int value = 1;
}

void main() {
  final fixture =
      jsonDecode(
            File(
              'contracts/official_stats/v2/contract_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('golden canonical encodings and hashes are stable', () {
    for (final raw in fixture['canonicalCases'] as List<dynamic>) {
      final testCase = raw as Map<String, dynamic>;
      expect(
        OfficialStatCanonicalEncoding.encode(testCase['input']),
        testCase['canonical'],
        reason: testCase['name'] as String,
      );
      expect(
        OfficialStatCanonicalEncoding.sha256Hex(testCase['input']),
        testCase['sha256'],
        reason: testCase['name'] as String,
      );
    }
    final byName = {
      for (final raw in fixture['canonicalCases'] as List<dynamic>)
        (raw as Map<String, dynamic>)['name']: raw,
    };
    expect(
      (byName['hangul-last-valid-precomposed'] as Map)['sha256'],
      (byName['hangul-last-valid-decomposed'] as Map)['sha256'],
    );
    expect(
      (byName['hangul-first-after-range'] as Map)['sha256'],
      isNot((byName['jamo-after-leading-range'] as Map)['sha256']),
    );
    expect(
      (byName['unicode-17-combining-order-sentinel'] as Map)['canonical'],
      '{"text":"ạ᫏"}',
    );
    expect(
      OfficialStatUnicodeNormalization.implementationVersion,
      'unicode-17.0-unorm-dart-0.3.2-hangul-boundary-patch1',
    );
  });

  test('timestamps normalize to UTC milliseconds', () {
    final testCase =
        (fixture['timestampCases'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(
      OfficialStatCanonicalEncoding.normalizeTimestamp(
        DateTime.parse(testCase['input'] as String),
      ),
      testCase['canonical'],
    );
  });

  test('numeric domain is the same mathematical safe-integer domain', () {
    expect(
      OfficialStatCanonicalEncoding.encode(-9007199254740991),
      '-9007199254740991',
    );
    expect(
      OfficialStatCanonicalEncoding.encode(9007199254740991),
      '9007199254740991',
    );
    expect(OfficialStatCanonicalEncoding.encode(1.0), '1');
    expect(OfficialStatCanonicalEncoding.encode(-0.0), '0');
    expect(OfficialStatCanonicalEncoding.encode(jsonDecode('-0')), '0');
    expect(OfficialStatCanonicalEncoding.encode(jsonDecode('-0.0')), '0');
    expect(OfficialStatCanonicalEncoding.encode(jsonDecode('1e0')), '1');
    expect(
      () => OfficialStatCanonicalEncoding.encode(
        int.parse('-9223372036854775808'),
      ),
      throwsFormatException,
      reason: 'the minimum host int must fail without overflowing abs()',
    );
    expect(
      () => OfficialStatCanonicalEncoding.encode(-9007199254740992),
      throwsFormatException,
    );
    expect(
      () => OfficialStatCanonicalEncoding.encode(9007199254740992),
      throwsFormatException,
    );
    for (final value in [
      0.5,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => OfficialStatCanonicalEncoding.encode(value),
        throwsFormatException,
      );
    }
  });

  test('unsupported containers and values are rejected', () {
    expect(
      () => OfficialStatCanonicalEncoding.encode({1, 2}),
      throwsFormatException,
    );
    expect(
      () => OfficialStatCanonicalEncoding.encode({'naïveKey': 1}),
      throwsFormatException,
    );
    expect(
      () => OfficialStatCanonicalEncoding.encode(DateTime.utc(10000)),
      throwsFormatException,
    );
    expect(
      () => OfficialStatCanonicalEncoding.encode(_UnsupportedRecord()),
      throwsFormatException,
    );
  });
}
