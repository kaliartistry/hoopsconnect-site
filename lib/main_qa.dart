import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'platform/qa_environment.dart';
import 'services/notification_service.dart';

/// Isolated QA entrypoint.
///
/// Build this target only through `scripts/run_local_qa.js`. It deliberately
/// omits App Check, Crashlytics, Messaging registration, and external delivery;
/// all data-bearing Firebase products are connected to validated loopback
/// emulators before the application widget tree is created.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!QaEnvironment.enabled) {
    throw StateError(
      'lib/main_qa.dart requires --dart-define=HOOPSCONNECT_QA_MODE=true.',
    );
  }

  await Firebase.initializeApp(options: QaEnvironment.firebaseOptions);
  await QaEnvironment.connect();
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(NotificationService()),
      ],
      child: const JamaicaHoopsConnectApp(),
    ),
  );
}
