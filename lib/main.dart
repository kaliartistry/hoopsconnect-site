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
import 'app/router/app_router.dart';
import 'firebase_options.dart';
import 'platform/staging_environment.dart';
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
  await Firebase.initializeApp(options: _firebaseOptionsForCurrentBuild);
  // Background messages are handled by the OS notification tray automatically.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  // Capture the browser deep link before async Firebase startup. Reading it
  // later can yield `/` after a provider-driven router rebuild.
  final initialBrowserLocation = kIsWeb
      ? Uri(
          path: Uri.base.path,
          query: Uri.base.hasQuery ? Uri.base.query : null,
        ).toString()
      : null;

  await Firebase.initializeApp(options: _firebaseOptionsForCurrentBuild);
  await _configurePlatformAuth();

  // The staging presentation is online-only and commonly open in several
  // browser tabs. Its IndexedDB single-tab lock otherwise emits a warning and
  // falls back to memory in the second tab. Native and production web retain
  // their existing offline persistence setting.
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: !(kIsWeb && StagingEnvironment.enabled),
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
  if (!StagingEnvironment.enabled) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Initialize notification service after the app shell renders. Notification
  // permission/token failures should not block sign-in or public screens.
  final notificationService = NotificationService();

  runApp(
    ProviderScope(
      overrides: [
        notificationServiceProvider.overrideWithValue(notificationService),
        initialBrowserLocationProvider.overrideWithValue(
          initialBrowserLocation,
        ),
      ],
      child: AppBootstrap(
        initialize: _activateAppCheckIfConfigured,
        child: const JamaicaHoopsConnectApp(),
      ),
    ),
  );

  // Synthetic staging does not register devices for outbound push delivery.
  if (!StagingEnvironment.enabled) {
    unawaited(notificationService.init());
  }
}

FirebaseOptions get _firebaseOptionsForCurrentBuild =>
    StagingEnvironment.enabled
    ? StagingEnvironment.firebaseOptions
    : DefaultFirebaseOptions.currentPlatform;

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
    // Staging callable functions are deliberately isolated from production
    // attestation and do not require device App Check registration.
    if (StagingEnvironment.enabled) return;
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
