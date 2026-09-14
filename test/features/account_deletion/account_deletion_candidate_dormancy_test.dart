import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/features/account_deletion/account_deletion_candidate_models.dart';

void main() {
  final repositoryRoot = Directory.current.absolute.path;
  final productionRoots = [
    'lib/main.dart',
    'lib/providers/auth_providers.dart',
    'lib/app/router/app_router.dart',
    'lib/services/notification_service.dart',
    'lib/services/repositories/auth_repository.dart',
  ];
  final candidateSources = [
    'lib/features/account_deletion/account_deletion_candidate_models.dart',
    'lib/features/account_deletion/account_deletion_candidate_controller.dart',
    'lib/features/account_deletion/account_deletion_candidate_wire.dart',
    'lib/features/account_deletion/account_deletion_candidate_screen.dart',
    'lib/models/account_deletion/account_deletion_release_gate_ledger.dart',
  ];

  test('candidate activation remains explicitly closed', () {
    expect(accountDeletionCandidateActivationAllowed, isFalse);
  });

  test('candidate modules are unreachable from production client roots', () {
    final reachable = _transitiveDartSources(repositoryRoot, productionRoots);

    for (final relativePath in candidateSources) {
      expect(
        reachable,
        isNot(contains(_absolute(repositoryRoot, relativePath))),
        reason: '$relativePath must remain dormant until shared-root handoff',
      );
    }

    final reachableSource = reachable
        .map(File.new)
        .map((file) {
          return file.readAsStringSync();
        })
        .join('\n');
    expect(
      reachableSource,
      isNot(contains('features/account_deletion/account_deletion_candidate_')),
    );
    expect(
      reachableSource,
      isNot(contains('account_deletion_release_gate_ledger.dart')),
    );
  });

  test('candidate client has no live provider or shared-root imports', () {
    final imports = candidateSources
        .map((path) => File(_absolute(repositoryRoot, path)).readAsStringSync())
        .expand(_importSpecifiers)
        .toList(growable: false);

    for (final forbidden in [
      'cloud_firestore',
      'cloud_functions',
      'firebase_auth',
      'firebase_messaging',
      'go_router',
      '/app/router/',
      '/providers/auth_providers.dart',
      '/services/notification_service.dart',
      '/services/repositories/auth_repository.dart',
    ]) {
      expect(
        imports.where((specifier) => specifier.contains(forbidden)),
        isEmpty,
        reason: 'candidate import boundary includes $forbidden',
      );
    }
  });
}

Set<String> _transitiveDartSources(
  String repositoryRoot,
  Iterable<String> roots,
) {
  final seen = <String>{};
  final pending = roots
      .map((root) => _absolute(repositoryRoot, root))
      .toList(growable: true);

  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!seen.add(current)) continue;
    final source = File(current).readAsStringSync();
    for (final specifier in _importSpecifiers(source)) {
      final resolved = _resolveDartImport(repositoryRoot, current, specifier);
      if (resolved != null && File(resolved).existsSync()) {
        pending.add(resolved);
      }
    }
  }
  return seen;
}

Iterable<String> _importSpecifiers(String source) sync* {
  final pattern = RegExp(r'''(?:import|export|part)\s+['\"]([^'\"]+)['\"]''');
  for (final match in pattern.allMatches(source)) {
    yield match.group(1)!;
  }
}

String? _resolveDartImport(
  String repositoryRoot,
  String importer,
  String specifier,
) {
  const packagePrefix = 'package:hoops_connect/';
  if (specifier.startsWith(packagePrefix)) {
    return _absolute(
      repositoryRoot,
      'lib/${specifier.substring(packagePrefix.length)}',
    );
  }
  if (!specifier.startsWith('.')) return null;
  return Uri.file(importer).resolve(specifier).toFilePath();
}

String _absolute(String repositoryRoot, String relativePath) =>
    Uri.directory(repositoryRoot).resolve(relativePath).toFilePath();
