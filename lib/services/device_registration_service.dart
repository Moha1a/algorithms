import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    }
  }

  Future<void> registerCurrentDeviceForUser({
    required String uid,
    String appVersion = 'unknown',
    String projectId = 'unknown',
    String packageName = 'unknown',
  }) async {
    if (uid.trim().isEmpty) return;
    debugPrint('DEVICE_REGISTRATION_START');

    if (_shouldSkipIosSimulatorRegistration) {
      debugPrint('PUSH_SKIPPED_PREVIEW_ONLY');
      return;
    }

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (error, stackTrace) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: $error');
      debugPrint('$stackTrace');
      return;
    }

    if (token == null || token.trim().isEmpty) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: no token uid=$uid');
      return;
    }

    await _detachTokenFromOtherAccounts(token: token, activeUid: uid);

    final deviceId = _resolveDeviceId(token);
    final platform = kIsWeb
        ? 'web'
        : Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : 'other';

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId)
          .set({
        'token': token,
        'platform': platform,
        'projectId': projectId,
        'packageName': packageName,
        'appVersion': appVersion,
        'notificationEnabled': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastTokenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(token)
          .set({
        'token': token,
        'platform': platform,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('DEVICE_REGISTRATION_SUCCESS');
    } catch (error, stackTrace) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: $error');
      debugPrint('$stackTrace');
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
    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) async {
      await registerCurrentDeviceForUser(
        uid: uid,
        appVersion: appVersion,
        projectId: projectId,
        packageName: packageName,
      );
    }, onError: (error, stackTrace) {
      debugPrint('[DeviceRegistrationService] token refresh listener error ignored: $error');
      debugPrint('$stackTrace');
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