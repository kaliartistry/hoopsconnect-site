import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Compile-time configuration for the isolated HoopsConnect QA backend.
///
/// QA mode is deliberately opt-in and accepts only synthetic project IDs and
/// loopback emulator hosts. A malformed QA build fails before Firebase starts,
/// rather than silently falling through to the production configuration.
class QaEnvironment {
  static const enabled = bool.fromEnvironment('HOOPSCONNECT_QA_MODE');
  static const projectId = String.fromEnvironment(
    'HOOPSCONNECT_QA_PROJECT_ID',
    defaultValue: 'demo-hoopsconnect-stage0-platform',
  );
  static const host = String.fromEnvironment(
    'HOOPSCONNECT_QA_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static const authPort = int.fromEnvironment(
    'HOOPSCONNECT_QA_AUTH_PORT',
    defaultValue: 19099,
  );
  static const firestorePort = int.fromEnvironment(
    'HOOPSCONNECT_QA_FIRESTORE_PORT',
    defaultValue: 18080,
  );
  static const functionsPort = int.fromEnvironment(
    'HOOPSCONNECT_QA_FUNCTIONS_PORT',
    defaultValue: 15001,
  );
  static const storagePort = int.fromEnvironment(
    'HOOPSCONNECT_QA_STORAGE_PORT',
    defaultValue: 19199,
  );

  static QaFirebaseTarget get target => QaFirebaseTarget(
    projectId: projectId,
    host: host,
    authPort: authPort,
    firestorePort: firestorePort,
    functionsPort: functionsPort,
    storagePort: storagePort,
  );

  static FirebaseOptions get firebaseOptions {
    final current = target..validate();
    return FirebaseOptions(
      apiKey: 'demo-key',
      appId: '1:1234567890:web:hoopsconnectqa',
      messagingSenderId: '1234567890',
      projectId: current.projectId,
      authDomain: 'localhost',
      storageBucket: '${current.projectId}.appspot.com',
    );
  }

  static Future<void> connect() async {
    if (!enabled) return;
    final current = target..validate();
    await FirebaseAuth.instance.useAuthEmulator(
      current.host,
      current.authPort,
      automaticHostMapping: false,
    );
    FirebaseFirestore.instance.useFirestoreEmulator(
      current.host,
      current.firestorePort,
      automaticHostMapping: false,
    );
    FirebaseFunctions.instance.useFunctionsEmulator(
      current.host,
      current.functionsPort,
      automaticHostMapping: false,
    );
    await FirebaseStorage.instance.useStorageEmulator(
      current.host,
      current.storagePort,
      automaticHostMapping: false,
    );
  }
}

class QaFirebaseTarget {
  final String projectId;
  final String host;
  final int authPort;
  final int firestorePort;
  final int functionsPort;
  final int storagePort;

  const QaFirebaseTarget({
    required this.projectId,
    required this.host,
    required this.authPort,
    required this.firestorePort,
    required this.functionsPort,
    required this.storagePort,
  });

  void validate() {
    if (!projectId.startsWith('demo-') || projectId == 'hoops-connect-jm') {
      throw StateError(
        'QA mode requires a synthetic demo-* Firebase project, got '
        '$projectId.',
      );
    }
    if (!const {'localhost', '127.0.0.1', '::1'}.contains(host)) {
      throw StateError('QA emulators must use a loopback host, got $host.');
    }
    for (final entry in {
      'Auth': authPort,
      'Firestore': firestorePort,
      'Functions': functionsPort,
      'Storage': storagePort,
    }.entries) {
      if (entry.value < 1 || entry.value > 65535) {
        throw StateError('${entry.key} emulator port is invalid.');
      }
    }
    final ports = {authPort, firestorePort, functionsPort, storagePort};
    if (ports.length != 4) {
      throw StateError('QA emulator ports must be unique.');
    }
  }
}
