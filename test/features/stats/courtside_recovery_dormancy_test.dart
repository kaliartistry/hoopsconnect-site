import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/services/local_game_journal/courtside_recovery.dart';

void main() {
  const productionRoots = <String>[
    'lib/main.dart',
    'lib/main_qa.dart',
    'lib/app/router/app_router.dart',
    'lib/providers',
    'lib/services/repositories',
  ];
  const candidateFiles = <String>[
    'lib/services/local_game_journal/courtside_recovery.dart',
    'lib/features/stats/courtside_candidate_bridge.dart',
    'lib/features/stats/courtside_recovery_notifier.dart',
    'lib/features/stats/widgets/courtside_recovery_status_card.dart',
  ];

  test('candidate contract compiles while activation remains explicit', () {
    expect(CourtsideRecoveryOrchestrator, isNotNull);
  });

  test('candidate remains unreachable from every production client root', () {
    for (final root in productionRoots) {
      final entity = FileSystemEntity.typeSync(root);
      final files = entity == FileSystemEntityType.directory
          ? Directory(root)
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))
          : <File>[File(root)].where((file) => file.existsSync());
      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('courtside_recovery')),
          reason: '${file.path} must not activate the dormant candidate',
        );
        expect(
          source,
          isNot(contains('CourtsideRecovery')),
          reason: '${file.path} must not construct the dormant candidate',
        );
      }
    }
  });

  test('candidate files do not bypass the server adapter boundary', () {
    for (final path in candidateFiles) {
      final source = File(path).readAsStringSync();
      for (final forbidden in const <String>[
        'cloud_firestore',
        'cloud_functions',
        'firebase_auth',
        'FirebaseFunctions',
        'FirebaseFirestore',
        '.doc(',
        '.collection(',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '$path must not contain $forbidden',
        );
      }
    }
  });

  test('server, rules, and application roots remain outside this packet', () {
    final changed =
        Process.runSync('git', <String>[
              'status',
              '--short',
              '--untracked-files=all',
            ]).stdout
            as String;
    for (final line in changed.split('\n').where((line) => line.isNotEmpty)) {
      final path = line.substring(3);
      expect(path, isNot(startsWith('functions/')));
      expect(path, isNot(equals('firestore.rules')));
      expect(path, isNot(equals('lib/main.dart')));
      expect(path, isNot(equals('lib/main_qa.dart')));
      expect(path, isNot(startsWith('lib/app/router/')));
    }
  });
}
