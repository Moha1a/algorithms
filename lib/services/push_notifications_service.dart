import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/home_shell_screen.dart';
import 'device_registration_service.dart';

class PushNotificationsService {
  PushNotificationsService._();
  static final PushNotificationsService instance = PushNotificationsService._();

  static const String highImportanceChannelId = 'high_importance_channel';
  static const String _channelName = 'High Importance Notifications';
  static const String _channelDescription =
      'Used for order/chat/proposal updates.';

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const bool appPreviewSafeMode =
      bool.fromEnvironment('APP_PREVIEW_SAFE_MODE', defaultValue: false);
  static final Map<String, DateTime> _recentLocalNotificationIds =
      <String, DateTime>{};

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<User?>? _authSub;
  bool _initialized = false;
  final Map<String, DateTime> _recentForegroundNotificationIds =
      <String, DateTime>{};

  static Future<void> ensureLocalNotificationsInitialized() async {
    if (kIsWeb) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _local.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    const channel = AndroidNotificationChannel(
      highImportanceChannelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    debugPrint(
        '[PushNotificationsService] channel created: $highImportanceChannelId');
  }

  static Future<void> showBackgroundNotification(
    RemoteMessage message, {
    bool allowNotificationPayloadLocalDisplay = false,
  }) async {
    if (kIsWeb) return;
    if (message.notification != null && !allowNotificationPayloadLocalDisplay) {
      debugPrint(
          '[PushNotificationsService] native notification payload handled by OS; local display skipped.');
      return;
    }
    await ensureLocalNotificationsInitialized();
    final data = message.data;
    final explicitTitle =
        (message.notification?.title ?? data['title']?.toString())?.trim() ??
            '';
    final body =
        (message.notification?.body ?? data['body']?.toString())?.trim() ?? '';
    final title =
        explicitTitle.isNotEmpty || body.isEmpty ? explicitTitle : 'منفذك';
    if (title.isEmpty && body.isEmpty) {
      FirebaseCrashlytics.instance
          .log('local_notification_skipped_missing_visible_content');
      FirebaseCrashlytics.instance.setCustomKey(
        'push_event_type',
        data['type']?.toString() ?? '',
      );
      debugPrint(
        '[PushNotificationsService] local notification skipped: missing title/body data=$data',
      );
      return;
    }
    final dedupeId = _notificationDedupeIdFor(message);
    if (_shouldSkipDuplicateLocalNotification(dedupeId)) {
      FirebaseCrashlytics.instance
          .setCustomKey('duplicate_notification_skipped', true);
      FirebaseCrashlytics.instance.setCustomKey('push_dedupe_key', dedupeId);
      debugPrint(
          '[PushNotificationsService] duplicate local notification skipped dedupeId=$dedupeId');
      return;
    }

    await _local.show(
      dedupeId.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          highImportanceChannelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(data),
    );
  }

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    debugPrint('PUSH_INIT_START');
    _initialized = true;

    try {
      if (_shouldSkipPushForPreview()) {
        debugPrint('PUSH_SKIPPED_PREVIEW_ONLY');
        return;
      }
      await ensureLocalNotificationsInitialized();

      if (!kIsWeb) {
        await _local.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
            iOS: DarwinInitializationSettings(),
          ),
          onDidReceiveNotificationResponse: (NotificationResponse response) {
            final payload = _decodePayload(response.payload);
            _routeByPayload(payload, navigatorKey);
          },
        );
      }

      await _requestPermissions();
      if (!kIsWeb && Platform.isIOS) {
        await _messaging.setForegroundNotificationPresentationOptions(
            alert: true, badge: true, sound: true);
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        try {
          FirebaseCrashlytics.instance
              .log('push_on_message messageId=${message.messageId ?? ''}');
          FirebaseCrashlytics.instance.setCustomKey(
              'push_event_type', message.data['type']?.toString() ?? '');
          await _showForegroundNotification(message);
        } catch (error, stackTrace) {
          debugPrint(
              '[PushNotificationsService] onMessage handling failed (ignored): $error');
          debugPrint('$stackTrace');
          FirebaseCrashlytics.instance
              .recordError(error, stackTrace, fatal: false);
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        try {
          FirebaseCrashlytics.instance.log(
              'push_on_message_opened_app messageId=${message.messageId ?? ''}');
          FirebaseCrashlytics.instance.setCustomKey(
              'push_event_type', message.data['type']?.toString() ?? '');
          _routeByPayload(message.data, navigatorKey);
        } catch (error, stackTrace) {
          debugPrint(
              '[PushNotificationsService] onMessageOpenedApp failed (ignored): $error');
          debugPrint('$stackTrace');
          FirebaseCrashlytics.instance
              .recordError(error, stackTrace, fatal: false);
        }
      });

      RemoteMessage? initialMessage;
      try {
        initialMessage = await _messaging.getInitialMessage();
      } catch (error, stackTrace) {
        debugPrint(
            '[PushNotificationsService] getInitialMessage failed (ignored): $error');
        debugPrint('$stackTrace');
        FirebaseCrashlytics.instance
            .recordError(error, stackTrace, fatal: false);
      }
      if (initialMessage != null) {
        FirebaseCrashlytics.instance.log(
            'push_initial_message messageId=${initialMessage.messageId ?? ''}');
        FirebaseCrashlytics.instance.setCustomKey(
            'push_event_type', initialMessage.data['type']?.toString() ?? '');
        _routeByPayload(initialMessage.data, navigatorKey);
      }

      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user == null) {
          await DeviceRegistrationService.instance.stopTokenRefreshListener();
          return;
        }

        try {
          await DeviceRegistrationService.instance
              .registerAndListenTokenRefresh();
        } catch (error, stackTrace) {
          debugPrint(
              '[PushNotificationsService] token registration failed: $error');
          debugPrint('$stackTrace');
          FirebaseCrashlytics.instance
              .recordError(error, stackTrace, fatal: false);
        }
      });

      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint('PUSH_INIT_SUCCESS');
      if (currentUser != null) {
        try {
          await DeviceRegistrationService.instance
              .registerAndListenTokenRefresh();
        } catch (error, stackTrace) {
          debugPrint(
              '[PushNotificationsService] initial token registration failed: $error');
          debugPrint('$stackTrace');
          FirebaseCrashlytics.instance
              .recordError(error, stackTrace, fatal: false);
        }
      }
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('PUSH_INIT_FAILED_IGNORED: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<void> _requestPermissions() async {
    if (_shouldSkipPushForPreview()) {
      debugPrint('PUSH_SKIPPED_PREVIEW_ONLY');
      return;
    }
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      FirebaseCrashlytics.instance.setCustomKey(
          'notification_permission_status', settings.authorizationStatus.name);
      debugPrint(
          'PUSH_INIT_SUCCESS: permission=${settings.authorizationStatus}');
    } catch (error, stackTrace) {
      if (_isExpectedSimulatorPushError(error)) {
        debugPrint(
            '[PushNotificationsService] simulator push permission issue ignored: $error');
        return;
      }
      debugPrint('[PushNotificationsService] requestPermission failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      rethrow;
    }

    if (!kIsWeb) {
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  bool _isExpectedSimulatorPushError(Object error) {
    if (kIsWeb || !Platform.isIOS) return false;
    final msg = error.toString().toLowerCase();
    return msg.contains('apns') ||
        msg.contains('token') ||
        msg.contains('simulator') ||
        msg.contains('messaging#gettoken') ||
        msg.contains('notifications are not supported');
  }

  bool _shouldSkipPushForPreview() {
    return appPreviewSafeMode;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (kIsWeb) {
      debugPrint(
          '[PushNotificationsService] web foreground message: ${message.data}');
      return;
    }
    if (Platform.isIOS && message.notification != null) {
      debugPrint(
          '[PushNotificationsService] iOS foreground notification payload displayed by FCM presentation options; local display skipped.');
      return;
    }
    final dedupeId = _notificationDedupeId(message);
    if (_shouldSkipDuplicateForegroundNotification(dedupeId)) {
      FirebaseCrashlytics.instance
          .setCustomKey('duplicate_notification_skipped', true);
      FirebaseCrashlytics.instance.setCustomKey('push_dedupe_key', dedupeId);
      debugPrint(
          '[PushNotificationsService] duplicate foreground notification skipped dedupeId=$dedupeId');
      return;
    }
    await showBackgroundNotification(message,
        allowNotificationPayloadLocalDisplay: true);
  }

  String _notificationDedupeId(RemoteMessage message) {
    return _notificationDedupeIdFor(message);
  }

  static String _notificationDedupeIdFor(RemoteMessage message) {
    final data = message.data;
    final bookingId = data['bookingId']?.toString() ?? '';
    final type = data['type']?.toString() ?? '';
    final dedupeKey = data['dedupeKey']?.toString() ?? '';
    return dedupeKey.isNotEmpty
        ? dedupeKey
        : message.messageId ??
            message.collapseKey ??
            '$type|$bookingId|${message.notification?.title ?? ''}|${message.notification?.body ?? ''}';
  }

  static bool _shouldSkipDuplicateLocalNotification(String dedupeId) {
    final now = DateTime.now();
    _recentLocalNotificationIds.removeWhere(
        (_, seenAt) => now.difference(seenAt) > const Duration(minutes: 2));
    if (dedupeId.isEmpty) return false;
    if (_recentLocalNotificationIds.containsKey(dedupeId)) {
      return true;
    }
    _recentLocalNotificationIds[dedupeId] = now;
    return false;
  }

  bool _shouldSkipDuplicateForegroundNotification(String dedupeId) {
    final now = DateTime.now();
    _recentForegroundNotificationIds.removeWhere(
        (_, seenAt) => now.difference(seenAt) > const Duration(minutes: 2));
    if (dedupeId.isEmpty) return false;
    if (_recentForegroundNotificationIds.containsKey(dedupeId)) {
      return true;
    }
    _recentForegroundNotificationIds[dedupeId] = now;
    return false;
  }

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _routeByPayload(
      Map<String, dynamic> data, GlobalKey<NavigatorState> navKey) async {
    final nav = navKey.currentState;
    if (nav == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final profile = userSnap.data();
    if (profile == null) return;
    final role = (profile['role'] ?? '').toString();
    final mapIndex = role == 'outlet' ? 3 : 1;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            HomeShellScreen(profile: profile, initialIndex: mapIndex),
      ),
      (_) => false,
    );
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await DeviceRegistrationService.instance.stopTokenRefreshListener();
  }
}
