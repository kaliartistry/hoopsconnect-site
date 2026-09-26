import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Compile-time configuration for the isolated, remotely hosted acceptance
/// environment. Production remains the default unless the staging define is
/// supplied explicitly during a build. Native staging builds must also use
/// the matching platform Firebase configuration files.
class StagingEnvironment {
  static const enabled = bool.fromEnvironment('HOOPSCONNECT_STAGING_MODE');

  static FirebaseOptions get firebaseOptions {
    if (!enabled) {
      throw StateError('Staging Firebase options require staging mode.');
    }
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'The remotely hosted staging target supports web, iOS, and Android.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAUAxEcLMgC1eqTDUodTLhKBi9cGtxuQdk',
    appId: '1:842064766966:web:d7676ac1737f0f055689d7',
    messagingSenderId: '842064766966',
    projectId: 'hoopsconnect-jba-staging',
    authDomain: 'hoopsconnect-jba-staging.firebaseapp.com',
    storageBucket: 'hoopsconnect-jba-staging.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCewukpSemkYK6giit24LY1Somou-dJCP0',
    appId: '1:842064766966:ios:b10e07bc1891ca805689d7',
    messagingSenderId: '842064766966',
    projectId: 'hoopsconnect-jba-staging',
    storageBucket: 'hoopsconnect-jba-staging.firebasestorage.app',
    iosBundleId: 'com.hoopsconnect.hoopsConnect',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDqLvNgX4bOBh1vbHDYlJsfyQawWJ4NUNA',
    appId: '1:842064766966:android:d1004c9d8fe189755689d7',
    messagingSenderId: '842064766966',
    projectId: 'hoopsconnect-jba-staging',
    storageBucket: 'hoopsconnect-jba-staging.firebasestorage.app',
  );
}
