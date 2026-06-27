import 'dart:convert';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/firestore_paths.dart';

const _webVapidKey = String.fromEnvironment('FIREBASE_MESSAGING_WEB_VAPID_KEY');

/// Handles FCM token management, permission requests,
/// foreground notification display, and notification tap routing.
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Reference to the app's GoRouter for deep-link navigation on tap.
  GoRouter? _router;

  /// Android notification channel for foreground messages.
  static const _androidChannel = AndroidNotificationChannel(
    'hoops_connect_default',
    'HoopsConnect Notifications',
    description: 'Default notification channel for HoopsConnect',
    importance: Importance.high,
  );

  /// Set the router reference so notification taps can navigate.
  void setRouter(GoRouter router) {
    _router = router;
  }

  /// Initialize the notification service:
  /// 1. Request permission
  /// 2. Configure local notifications for foreground display
  /// 3. Register FCM token
  /// 4. Listen for token refresh
  /// 5. Listen for foreground messages
  /// 6. Handle notification taps (app opened from background/terminated)
  Future<void> init() async {
    try {
      if (kIsWeb && _webVapidKey.isEmpty) {
        dev.log(
          'Skipping web notification setup: FIREBASE_MESSAGING_WEB_VAPID_KEY is not set.',
          name: 'NotificationService',
        );
        return;
      }

      if (kIsWeb && !await _messaging.isSupported()) {
        dev.log(
          'FCM is not supported in this browser.',
          name: 'NotificationService',
        );
        return;
      }

      // 1. Request permission
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      dev.log(
        'FCM permission status: ${settings.authorizationStatus}',
        name: 'NotificationService',
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      // 2. Initialize local notifications plugin where it is supported.
      if (!kIsWeb) {
        const androidInit = AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        );
        const iosInit = DarwinInitializationSettings();
        const initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        );

        await _localNotifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onLocalNotificationTap,
        );

        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_androidChannel);
      }

      // 3. Get current token and save to user doc.
      // Web FCM needs a project VAPID key.
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey)
          : await _messaging.getToken();
      if (token != null) {
        await _saveToken(token);
      }

      // 4. Listen for token refresh
      _messaging.onTokenRefresh.listen(_saveToken);

      // 5. Foreground message handler
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6. Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // 7. Check if app was opened from a terminated state via notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (e, stack) {
      dev.log(
        'Notification setup failed; continuing without push registration.',
        error: e,
        stackTrace: stack,
        name: 'NotificationService',
      );
    }
  }

  /// Save the FCM token to the current user's Firestore doc.
  /// Uses arrayUnion so multiple device tokens are preserved.
  Future<void> _saveToken(String token) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _db.doc(FirestorePaths.user(uid)).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
      dev.log('FCM token saved for user $uid', name: 'NotificationService');
    } catch (e) {
      dev.log('Failed to save FCM token: $e', name: 'NotificationService');
    }
  }

  /// Remove the current device's FCM token from Firestore (e.g. on sign-out).
  Future<void> removeToken() async {
    final uid = _auth.currentUser?.uid;
    final token = await _messaging.getToken();
    if (uid == null || token == null) return;

    try {
      await _db.doc(FirestorePaths.user(uid)).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
    } catch (e) {
      dev.log('Failed to remove FCM token: $e', name: 'NotificationService');
    }
  }

  // ── Routing helpers ─────────────────────────────────────────────────

  /// Resolve the FCM data payload to a go_router path.
  ///
  /// Cloud Functions send these `type` values:
  ///   - `ack_required`  (with postId) → post detail
  ///   - `ack_reminder`  (with postId) → post detail
  ///   - `stat_reminder` → admin stats game-select
  ///   - `post`          → board feed
  String? _resolveRoute(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return null;

    switch (type) {
      case 'ack_required':
      case 'ack_reminder':
      case 'ack':
        final postId = data['postId'] as String?;
        if (postId != null) return '/board/post/$postId';
        return '/board';

      case 'stat_reminder':
      case 'stats_reminder':
        return '/admin/stats';

      case 'post':
        return '/board';

      default:
        dev.log(
          'Unknown notification type: $type',
          name: 'NotificationService',
        );
        return null;
    }
  }

  /// Navigate using go_router. Safely no-ops if router is not yet set.
  void _navigateTo(String route) {
    if (_router == null) {
      dev.log(
        'Router not set, cannot navigate to $route',
        name: 'NotificationService',
      );
      return;
    }
    dev.log('Navigating to $route', name: 'NotificationService');
    _router!.go(route);
  }

  // ── Message handlers ────────────────────────────────────────────────

  /// Display a foreground message as a local notification.
  void _handleForegroundMessage(RemoteMessage message) {
    if (kIsWeb) return;

    final notification = message.notification;
    if (notification == null) return;

    // Encode the full data map as JSON so the local notification payload
    // carries all the fields we need for routing on tap.
    final payload = jsonEncode(message.data);

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  /// Called when user taps a notification that opened the app from
  /// background or terminated state.
  void _handleNotificationTap(RemoteMessage message) {
    final route = _resolveRoute(message.data);
    if (route != null) {
      _navigateTo(route);
    }
  }

  /// Called when user taps a local (foreground) notification.
  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final route = _resolveRoute(data);
      if (route != null) {
        _navigateTo(route);
      }
    } catch (e) {
      // Legacy fallback: payload might be a plain route string
      dev.log(
        'Payload is not JSON, treating as route: $payload',
        name: 'NotificationService',
      );
      _navigateTo(payload);
    }
  }
}

/// Provider for the notification service singleton.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
