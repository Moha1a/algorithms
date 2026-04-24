import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  static const String _channelDescription = 'Used for order/chat/proposal updates.';

  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static const bool isPreviewSafeMode =
      bool.fromEnvironment('APP_PREVIEW_SAFE_MODE', defaultValue: false);

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<User?>? _authSub;
  bool _initialized = false;

  static Future<void> ensureLocalNotificationsInitialized() async {
    if (kIsWeb) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    debugPrint('[PushNotificationsService] channel created: $highImportanceChannelId');
  }

  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    if (kIsWeb) return;
    await ensureLocalNotificationsInitialized();
    final data = message.data;
    final title = message.notification?.title ?? data['title']?.toString() ?? 'إشعار جديد';
    final body = message.notification?.body ?? data['body']?.toString() ?? '';

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
    _initialized = true;

    try {
      if (_shouldSkipPushForPreview()) {
        debugPrint('[PushNotificationsService] preview safe mode: skipping push initialization');
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

      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        try {
          await _showForegroundNotification(message);
        } catch (error, stackTrace) {
          debugPrint('[PushNotificationsService] onMessage handling failed (ignored): $error');
          debugPrint('$stackTrace');
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        try {
          _routeByPayload(message.data, navigatorKey);
        } catch (error, stackTrace) {
          debugPrint('[PushNotificationsService] onMessageOpenedApp failed (ignored): $error');
          debugPrint('$stackTrace');
        }
      });

      RemoteMessage? initialMessage;
      try {
        initialMessage = await _messaging.getInitialMessage();
      } catch (error, stackTrace) {
        debugPrint('[PushNotificationsService] getInitialMessage failed (ignored): $error');
        debugPrint('$stackTrace');
      }
      if (initialMessage != null) {
        _routeByPayload(initialMessage.data, navigatorKey);
      }

      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
        if (user == null) {
          await DeviceRegistrationService.instance.stopTokenRefreshListener();
          return;
        }

        try {
          await DeviceRegistrationService.instance.registerAndListenTokenRefresh();
        } catch (error, stackTrace) {
          debugPrint('[PushNotificationsService] token registration failed: $error');
          debugPrint('$stackTrace');
        }
      });

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          await DeviceRegistrationService.instance.registerAndListenTokenRefresh();
        } catch (error, stackTrace) {
          debugPrint('[PushNotificationsService] initial token registration failed: $error');
          debugPrint('$stackTrace');
        }
      }
    } catch (error, stackTrace) {
      _initialized = false;
      debugPrint('[PushNotificationsService] initialize failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<void> _requestPermissions() async {
    if (_shouldSkipPushForPreview()) return;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('[PushNotificationsService] Firebase permission: ${settings.authorizationStatus}');
    } catch (error, stackTrace) {
      if (_isExpectedSimulatorPushError(error)) {
        debugPrint('[PushNotificationsService] simulator push permission issue ignored: $error');
        return;
      }
      debugPrint('[PushNotificationsService] requestPermission failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }

    if (!kIsWeb) {
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  bool _isExpectedSimulatorPushError(Object error) {
    if (!Platform.isIOS) return false;
    final msg = error.toString().toLowerCase();
    return msg.contains('apns') ||
        msg.contains('token') ||
        msg.contains('simulator') ||
        msg.contains('messaging#gettoken') ||
        msg.contains('notifications are not supported');
  }

  bool _shouldSkipPushForPreview() {
    if (isPreviewSafeMode) return true;
    if (kIsWeb) return false;
    return !kReleaseMode && Platform.isIOS;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (kIsWeb) {
      debugPrint('[PushNotificationsService] web foreground message: ${message.data}');
      return;
    }
    await showBackgroundNotification(message);
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

  Future<void> _routeByPayload(Map<String, dynamic> data, GlobalKey<NavigatorState> navKey) async {
    final nav = navKey.currentState;
    if (nav == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;
    final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final profile = userSnap.data();
    if (profile == null) return;
    final role = (profile['role'] ?? '').toString();
    final mapIndex = role == 'outlet' ? 3 : 1;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomeShellScreen(profile: profile, initialIndex: mapIndex),
      ),
      (_) => false,
    );
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await DeviceRegistrationService.instance.stopTokenRefreshListener();
  }
}