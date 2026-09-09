import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/models/official_stats/assigned_game_bootstrap.dart';

void main() {
  final fixture = jsonDecode(
    File(
      'contracts/official_stats/v2/assigned_game_bootstrap_fixtures.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;

  Map<String, Object?> dto() => Map<String, Object?>.from(
    jsonDecode(jsonEncode(fixture['dtoBase'])) as Map<String, dynamic>,
  );

  test('shared minimized DTO parses and round-trips its exact allowlist', () {
    expect(fixture['fixtureVersion'], 1);
    final raw = dto();
    final parsed = AssignedGameBootstrap.tryParse(raw);
    expect(parsed, isNotNull);
    expect(parsed!.toMap(), raw);
    expect(parsed.actorAccountId, 'operator');
    expect(parsed.homeTeamEntryId, 'team-a');
    expect(parsed.awayTeamEntryId, 'team-b');
    expect(parsed.gameControlVersion, 11);
    expect(parsed.associationControlVersion, 2);
    expect(parsed.seasonControlVersion, 7);
    expect(parsed.acceptedCalculatorVersions, ['calc-a', 'calc-z']);
    expect(parsed.toMap().keys.toList(), fixture['dtoKeys']);
  });

  test('unknown, missing, null, and stale exact-object fields reject', () {
    final cases = <Map<String, Object?>>[];
    final extra = dto()..['rawMembership'] = <String, Object?>{};
    cases.add(extra);
    final missing = dto()..remove('actorAccountId');
    cases.add(missing);
    final nullTeam = dto()..['homeTeamEntryId'] = null;
    cases.add(nullTeam);
    final scopeExtra = dto();
    (scopeExtra['scope'] as Map<String, dynamic>)['teamEntryId'] = 'team-a';
    cases.add(scopeExtra);
    final assignmentExtra = dto();
    (assignmentExtra['assignment'] as Map<String, dynamic>)['status'] = 'active';
    cases.add(assignmentExtra);
    final compatibilityExtra = dto();
    (compatibilityExtra['compatibility'] as Map<String, dynamic>)['calculatorVersion'] = 'calc-a';
    cases.add(compatibilityExtra);
    final badSchema = dto()..['readSchemaVersion'] = 1;
    cases.add(badSchema);
    final staleEpoch = dto();
    (staleEpoch['assignment'] as Map<String, dynamic>)['writerEpoch'] = 0;
    cases.add(staleEpoch);
    for (final candidate in cases) {
      expect(AssignedGameBootstrap.tryParse(candidate), isNull);
    }
  });

  test('transport doubles, unsafe counters, swapped teams, and malformed time reject', () {
    final doubleCounter = dto()..['gameControlVersion'] = 11.0;
    final unsafe = dto();
    (unsafe['assignment'] as Map<String, dynamic>)['assignmentVersion'] =
        9007199254740992;
    final swapped = dto()
      ..['homeTeamEntryId'] = 'team-a'
      ..['awayTeamEntryId'] = 'team-a';
    final noMilliseconds = dto()..['evaluatedAt'] = '2026-06-01T12:00:00Z';
    expect(AssignedGameBootstrap.tryParse(doubleCounter), isNull);
    expect(AssignedGameBootstrap.tryParse(unsafe), isNull);
    expect(AssignedGameBootstrap.tryParse(swapped), isNull);
    expect(AssignedGameBootstrap.tryParse(noMilliseconds), isNull);
  });

  test('calculator intersection vectors remain sorted, unique, bounded DTO values', () {
    for (final raw in fixture['calculatorIntersectionVectors'] as List) {
      final vector = raw as Map<String, dynamic>;
      final candidate = dto();
      (candidate['compatibility'] as Map<String, dynamic>)[
        'acceptedCalculatorVersions'
      ] = vector['expected'];
      expect(
        AssignedGameBootstrap.tryParse(candidate),
        isNotNull,
        reason: jsonEncode(vector),
      );
    }
    for (final calculators in [
      ['calc-a', 'calc-a'],
      ['bad/id'],
      ['a', 'b', 'c', 'd', 'e'],
      ['calc-z', 'calc-a'],
    ]) {
      final candidate = dto();
      (candidate['compatibility'] as Map<String, dynamic>)[
        'acceptedCalculatorVersions'
      ] = calculators;
      expect(AssignedGameBootstrap.tryParse(candidate), isNull);
    }
  });

  test('parsed collections are detached and unmodifiable', () {
    final raw = dto();
    final parsed = AssignedGameBootstrap.tryParse(raw)!;
    (raw['scope'] as Map<String, dynamic>)['gameId'] = 'mutated';
    (raw['assignment'] as Map<String, dynamic>)['duties'] = ['submit'];
    expect(parsed.scope['gameId'], 'game-1');
    expect(parsed.duties, ['submit', 'enter']);
    expect(() => parsed.scope['gameId'] = 'mutated', throwsUnsupportedError);
    expect(() => parsed.duties.add('enter'), throwsUnsupportedError);
    expect(
      () => parsed.acceptedCalculatorVersions.add('calc-b'),
      throwsUnsupportedError,
    );
  });

  test('response byte limit rejects oversized otherwise exact DTO', () {
    final candidate = dto()
      ..['actorAccountId'] = List<String>.filled(17000, 'A').join();
    expect(utf8.encode(jsonEncode(candidate)).length, greaterThan(16384));
    expect(AssignedGameBootstrap.tryParse(candidate), isNull);
  });
}
