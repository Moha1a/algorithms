import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class DeviceRegistrationService {
  DeviceRegistrationService._();
  static final DeviceRegistrationService instance = DeviceRegistrationService._();
  static const bool appPreviewSafeMode =
      bool.fromEnvironment('APP_PREVIEW_SAFE_MODE', defaultValue: false);

  StreamSubscription<String>? _tokenRefreshSub;

  String _resolveDeviceId(String token) => token.hashCode.abs().toString();

  bool get _shouldSkipIosSimulatorRegistration {
    return appPreviewSafeMode;
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'other';
  }

  bool _notificationsAllowed(AuthorizationStatus? status) {
    return status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
  }

  Future<String?> _waitForApnsToken() async {
    if (kIsWeb || !Platform.isIOS) return null;
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if (token != null && token.trim().isNotEmpty) return token;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  Future<void> _detachTokenFromOtherAccounts({
    required String token,
    required String activeUid,
  }) async {
    final db = FirebaseFirestore.instance;

    try {
      final deviceMatches = await db
          .collectionGroup('devices')
          .where('token', isEqualTo: token)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in deviceMatches.docs) {
        final ownerRef = doc.reference.parent.parent;
        final ownerUid = ownerRef?.id ?? '';
        if (ownerUid.isEmpty || ownerUid == activeUid) continue;
        await doc.reference.delete();
      }
    } catch (error, stackTrace) {
      debugPrint('[DeviceRegistrationService] detach devices failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
    }

    try {
      final legacyMatches = await db
          .collectionGroup('fcmTokens')
          .where('token', isEqualTo: token)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in legacyMatches.docs) {
        final ownerRef = doc.reference.parent.parent;
        final ownerUid = ownerRef?.id ?? '';
        if (ownerUid.isEmpty || ownerUid == activeUid) continue;
        await doc.reference.delete();
      }
    } catch (error, stackTrace) {
      debugPrint('[DeviceRegistrationService] detach fcmTokens failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
    }
  }

  Future<void> registerCurrentDeviceForUser({
    required String uid,
    String appVersion = 'unknown',
    String projectId = 'unknown',
    String packageName = 'unknown',
  }) async {
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;
    debugPrint('DEVICE_REGISTRATION_START');
    final crashlytics = FirebaseCrashlytics.instance;
    final platform = _platformName;
    crashlytics.setCustomKey('current_uid', cleanUid);
    crashlytics.setCustomKey('platform', platform);
    crashlytics.setCustomKey('token_registration_success', false);
    crashlytics.setCustomKey('token_registration_failure', false);

    if (_shouldSkipIosSimulatorRegistration) {
      debugPrint('PUSH_SKIPPED_PREVIEW_ONLY');
      return;
    }

    NotificationSettings? settings;
    try {
      settings = await FirebaseMessaging.instance.getNotificationSettings();
      crashlytics.setCustomKey('notification_permission_status', settings.authorizationStatus.name);
      debugPrint('[DeviceRegistrationService] permission=${settings.authorizationStatus.name} uid=$cleanUid platform=$platform');
    } catch (error, stackTrace) {
      debugPrint('[DeviceRegistrationService] notification settings failed: $error');
      debugPrint('$stackTrace');
      crashlytics.setCustomKey('token_registration_failure', true);
      crashlytics.recordError(error, stackTrace, fatal: false);
    }

    String? apnsToken;
    if (!kIsWeb && Platform.isIOS) {
      try {
        apnsToken = await _waitForApnsToken();
      } catch (error, stackTrace) {
        debugPrint('[DeviceRegistrationService] APNs token read failed: $error');
        debugPrint('$stackTrace');
        crashlytics.recordError(error, stackTrace, fatal: false);
      }

      final apnsAvailable = apnsToken != null && apnsToken.trim().isNotEmpty;
      crashlytics.setCustomKey('apns_token_available', apnsAvailable);
      debugPrint('[DeviceRegistrationService] apnsTokenAvailable=$apnsAvailable uid=$cleanUid');
      if (!apnsAvailable) {
        crashlytics.recordError(
          StateError('APNs token missing during iOS FCM device registration. Check Push Notifications capability, aps-environment, APNs key in Firebase, and physical device/TestFlight environment.'),
          StackTrace.current,
          fatal: false,
        );
      }
    } else {
      crashlytics.setCustomKey('apns_token_available', false);
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (error, stackTrace) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: FCM token error=$error');
      debugPrint('$stackTrace');
      crashlytics.setCustomKey('fcm_token_available', false);
      crashlytics.setCustomKey('token_registration_failure', true);
      crashlytics.recordError(error, stackTrace, fatal: false);
      return;
    }

    if (token == null || token.trim().isEmpty) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: no token uid=$cleanUid');
      crashlytics.setCustomKey('fcm_token_available', false);
      crashlytics.setCustomKey('token_registration_failure', true);
      crashlytics.recordError(
        StateError('FCM token missing during device registration.'),
        StackTrace.current,
        fatal: false,
      );
      return;
    }
    crashlytics.setCustomKey('fcm_token_available', true);

    await _detachTokenFromOtherAccounts(token: token, activeUid: cleanUid);

    final deviceId = _resolveDeviceId(token);
    final tokenWritePath = 'users/$cleanUid/devices/$deviceId';
    final permissionStatus = settings?.authorizationStatus;
    final notificationEnabled = _notificationsAllowed(permissionStatus);
    crashlytics.setCustomKey('token_registration_path', tokenWritePath);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanUid)
          .collection('devices')
          .doc(deviceId)
          .set({
        'token': token,
        'platform': platform,
        'projectId': projectId,
        'packageName': packageName,
        'appVersion': appVersion,
        'notificationEnabled': notificationEnabled,
        'notificationAuthorizationStatus': permissionStatus?.name ?? 'unknown',
        'apnsTokenAvailable': apnsToken != null && apnsToken.trim().isNotEmpty,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastTokenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(cleanUid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': platform,
        'notificationEnabled': notificationEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      crashlytics.setCustomKey('token_registration_success', true);
      crashlytics.setCustomKey('token_registration_failure', false);
      debugPrint('DEVICE_REGISTRATION_SUCCESS');
      debugPrint('[DeviceRegistrationService] wrote token path=$tokenWritePath notificationEnabled=$notificationEnabled platform=$platform uid=$cleanUid');
    } catch (error, stackTrace) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: $error');
      debugPrint('$stackTrace');
      crashlytics.setCustomKey('token_registration_failure', true);
      crashlytics.recordError(error, stackTrace, fatal: false);
    }
  }

  Future<void> unregisterCurrentDeviceForUser(String uid) async {
    if (uid.trim().isEmpty) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;

      final db = FirebaseFirestore.instance;
      final devicesSnap = await db
          .collection('users')
          .doc(uid)
          .collection('devices')
          .where('token', isEqualTo: token)
          .get();

      for (final doc in devicesSnap.docs) {
        await doc.reference.delete();
      }

      await db.collection('users').doc(uid).collection('fcmTokens').doc(token).delete();
    } catch (error, stackTrace) {
      debugPrint('[DEVICE REGISTRATION] unregister ignored: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> startTokenRefreshListenerForUser({
    required String uid,
    String appVersion = 'unknown',
    String projectId = 'unknown',
    String packageName = 'unknown',
  }) async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      debugPrint('[DeviceRegistrationService] token refresh uid=$uid tokenPreview=${token.substring(0, token.length < 12 ? token.length : 12)}...');
      FirebaseCrashlytics.instance.log('fcm_token_refresh uid=$uid');
      await registerCurrentDeviceForUser(
        uid: uid,
        appVersion: appVersion,
        projectId: projectId,
        packageName: packageName,
      );
    }, onError: (error, stackTrace) {
      debugPrint('[DeviceRegistrationService] token refresh listener error ignored: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
    });
  }

  Future<void> stopTokenRefreshListener() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }

  Future<void> registerAndListenTokenRefresh({
    String appVersion = 'unknown',
    String projectId = 'unknown',
    String packageName = 'unknown',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await registerCurrentDeviceForUser(
        uid: user.uid,
        appVersion: appVersion,
        projectId: projectId,
        packageName: packageName,
      );

      await startTokenRefreshListenerForUser(
        uid: user.uid,
        appVersion: appVersion,
        projectId: projectId,
        packageName: packageName,
      );
    } catch (error, stackTrace) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: $error');
      debugPrint('$stackTrace');
    }
  }
}
