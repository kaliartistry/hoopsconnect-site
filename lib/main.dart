import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';
import 'app/app_bootstrap.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

const _webAppCheckSiteKey = String.fromEnvironment(
  'FIREBASE_APPCHECK_WEB_SITE_KEY',
);
const _macOSKeychainAccessGroup = String.fromEnvironment(
  'MACOS_KEYCHAIN_ACCESS_GROUP',
);

/// Top-level handler for background FCM messages.
/// Must be a top-level function (not a class method).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Background messages are handled by the OS notification tray automatically.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _configurePlatformAuth();

  // Enable Firestore offline persistence
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // Set up Crashlytics error reporting where it is supported.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (!kIsWeb) {
      unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details));
    }
  };

  // Catch asynchronous errors not handled by Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kIsWeb) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
    } else {
      dev.log(
        'Unhandled async error',
        error: error,
        stackTrace: stack,
        name: 'Bootstrap',
      );
    }
    return true;
  };

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize notification service after the app shell renders. Notification
  // permission/token failures should not block sign-in or public screens.
  final notificationService = NotificationService();

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: AppBootstrap(
        initialize: _activateAppCheckIfConfigured,
        child: const JamaicaHoopsConnectApp(),
      ),
    ),
  );

  unawaited(notificationService.init());
}

Future<void> _configurePlatformAuth() async {
  if (!kIsWeb &&
      defaultTargetPlatform == TargetPlatform.macOS &&
      _macOSKeychainAccessGroup.isNotEmpty) {
    await FirebaseAuth.instance.setSettings(
      userAccessGroup: _macOSKeychainAccessGroup,
    );
  }
}

Future<void> _activateAppCheckIfConfigured() async {
  try {
    if (kIsWeb) {
      if (_webAppCheckSiteKey.isEmpty) {
        dev.log(
          'Skipping App Check on web: FIREBASE_APPCHECK_WEB_SITE_KEY is not set.',
          name: 'Bootstrap',
        );
        return;
      }

      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider(_webAppCheckSiteKey),
      );
      return;
    }

    // Debug builds: use debug provider. Release builds: production attestation.
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
        appleProvider: AppleProvider.debug,
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.deviceCheck,
      );
    }
  } catch (error, stack) {
    dev.log(
      'App Check activation failed; continuing without blocking startup.',
      error: error,
      stackTrace: stack,
      name: 'Bootstrap',
    );
    if (!kIsWeb) {
      unawaited(FirebaseCrashlytics.instance.recordError(error, stack));
    }
  }
}
