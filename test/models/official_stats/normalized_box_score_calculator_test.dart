import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'box_score_calculator_fixture.g.dart';
import 'normalized_box_score_fixture_suite.dart';

void main() {
  test('browser fixture mirror exactly matches the normative shared JSON', () {
    final source = File(
      'contracts/official_stats/v2/box_score_calculator_fixtures.json',
    ).readAsStringSync();
    expect(loadBoxScoreCalculatorBrowserFixture(), source);
    expect(
      sha256.convert(utf8.encode(source)).toString(),
      boxScoreCalculatorFixtureSourceSha256,
    );
  });

  registerNormalizedBoxScoreFixtureTests(
    () => File(
      'contracts/official_stats/v2/box_score_calculator_fixtures.json',
    ).readAsString(),
  );
}
