import 'package:flutter_test/flutter_test.dart';
import 'package:hoops_connect/platform/qa_environment.dart';

void main() {
  const valid = QaFirebaseTarget(
    projectId: 'demo-hoopsconnect-stage0-platform',
    host: '127.0.0.1',
    authPort: 19099,
    firestorePort: 18080,
    functionsPort: 15001,
    storagePort: 19199,
  );

  test('accepts the isolated demo project and loopback emulator set', () {
    expect(valid.validate, returnsNormally);
  });

  test('rejects the production project before Firebase can initialize', () {
    expect(
      () => QaFirebaseTarget(
        projectId: 'hoops-connect-jm',
        host: valid.host,
        authPort: valid.authPort,
        firestorePort: valid.firestorePort,
        functionsPort: valid.functionsPort,
        storagePort: valid.storagePort,
      ).validate(),
      throwsStateError,
    );
  });

  test('rejects remote and credential-shaped hosts', () {
    for (final host in [
      'emulator.example.com',
      '127.0.0.1@evil.example',
      '127.0.0.1:8080',
    ]) {
      expect(
        () => QaFirebaseTarget(
          projectId: valid.projectId,
          host: host,
          authPort: valid.authPort,
          firestorePort: valid.firestorePort,
          functionsPort: valid.functionsPort,
          storagePort: valid.storagePort,
        ).validate(),
        throwsStateError,
      );
    }
  });

  test('rejects invalid and ambiguous emulator ports', () {
    expect(
      () => const QaFirebaseTarget(
        projectId: 'demo-hoopsconnect-stage0-platform',
        host: 'localhost',
        authPort: 9099,
        firestorePort: 9099,
        functionsPort: 5001,
        storagePort: 9199,
      ).validate(),
      throwsStateError,
    );
    expect(
      () => const QaFirebaseTarget(
        projectId: 'demo-hoopsconnect-stage0-platform',
        host: '::1',
        authPort: 70000,
        firestorePort: 8080,
        functionsPort: 5001,
        storagePort: 9199,
      ).validate(),
      throwsStateError,
    );
  });
}
