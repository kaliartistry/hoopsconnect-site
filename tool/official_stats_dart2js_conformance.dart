// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'package:hoops_connect/models/official_stats/calculators/normalized_box_score.dart';
import 'package:hoops_connect/models/official_stats/canonical_encoding.dart';

import '../test/models/official_stats/box_score_calculator_fixture.g.dart';

Never _fail(String message) => throw StateError(message);

void main() {
  final executionChallenge = Uri.base.queryParameters['execution_challenge'];
  if (executionChallenge == null ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(executionChallenge)) {
    _fail('missing or malformed Dart execution challenge');
  }
  final fixture =
      jsonDecode(loadBoxScoreCalculatorBrowserFixture())
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  for (final entry in cases) {
    final outcome = calculateNormalizedBoxScore(entry['input']);
    final canonical = OfficialStatCanonicalEncoding.encode(outcome);
    if (canonical != entry['expectedCanonical']) {
      _fail('${entry['name']}: canonical bytes differ');
    }
    if (utf8.encode(canonical).length != entry['expectedCanonicalByteLength']) {
      _fail('${entry['name']}: canonical length differs');
    }
    if (OfficialStatCanonicalEncoding.sha256Hex(outcome) !=
        entry['expectedSha256']) {
      _fail('${entry['name']}: hash differs');
    }
  }

  final base =
      (cases.singleWhere(
            (entry) => entry['name'] == 'complete_zero_disciplinary_incidents',
          )['input']
          as Map<String, dynamic>);
  final raw = jsonEncode(base);
  for (final spelling in ['2.0', '2e0']) {
    final outcome = calculateNormalizedBoxScoreFromJson(
      raw.replaceFirst('"schemaVersion":2', '"schemaVersion":$spelling'),
    );
    if (outcome['status'] != 'accepted' ||
        (outcome['normalizedBoxScore']! as Map)['schemaVersion'] != 2) {
      _fail('runtime mathematical integer $spelling was not normalized');
    }
  }

  const firstAfterHangul = '\uD7A4';
  const followingJamoPair = '\u1113\u1161';
  if (OfficialStatCanonicalEncoding.encode({'text': firstAfterHangul}) ==
      OfficialStatCanonicalEncoding.encode({'text': followingJamoPair})) {
    _fail('post-Hangul scalar collided with the following Jamo pair');
  }
  if (OfficialStatCanonicalEncoding.encode({'text': 'a\u1ACF\u0323'}) !=
      '{"text":"ạ᫏"}') {
    _fail('Unicode 17 combining-order sentinel failed');
  }

  final accepted = calculateNormalizedBoxScore(base);
  try {
    (accepted['normalizedBoxScore']! as Map)['schemaVersion'] = 99;
    _fail('accepted result graph remained mutable');
  } on UnsupportedError {
    // Required immutable boundary.
  }

  final body = html.document.body;
  if (body == null) _fail('browser document body is unavailable');
  body.dataset['dartExecutionChallenge'] = executionChallenge;

  // The harness captures this stable marker from the real browser console.
  // ignore: avoid_print
  print(
    'HOOPSCONNECT_DART2JS_OK cases=${cases.length} '
    'numeric=2 unicode=17-distinct immutable=true',
  );
}
