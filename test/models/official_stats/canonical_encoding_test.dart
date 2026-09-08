import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';

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

  test('unsafe or ambiguous inputs are rejected', () {
    expect(
      () => OfficialStatCanonicalEncoding.encode(0.0),
      throwsFormatException,
    );
    expect(
      () => OfficialStatCanonicalEncoding.encode(9007199254740992),
      throwsFormatException,
    );
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
  });
}
