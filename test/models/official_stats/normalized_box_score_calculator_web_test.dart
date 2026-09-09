import 'package:flutter_test/flutter_test.dart';

import 'box_score_calculator_fixture.g.dart';
import 'normalized_box_score_fixture_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerNormalizedBoxScoreFixtureTests(
    () async => loadBoxScoreCalculatorBrowserFixture(),
  );
}
