import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class DeviceRegistrationService {
  DeviceRegistrationService._();
  static final DeviceRegistrationService instance = DeviceRegistrationService._();

  StreamSubscription<String>? _tokenRefreshSub;

  String _resolveDeviceId(String token) => token.hashCode.abs().toString();

  Future<void> _detachTokenFromOtherAccounts({
    required String token,
    required String activeUid,
  }) async {
    final db = FirebaseFirestore.instance;

    final deviceMatches = await db.collectionGroup('devices').where('token', isEqualTo: token).get();
    for (final doc in deviceMatches.docs) {
      final ownerRef = doc.reference.parent.parent;
      final ownerUid = ownerRef?.id ?? '';
      if (ownerUid.isEmpty || ownerUid == activeUid) continue;
      await doc.reference.delete();
    }

    final legacyMatches = await db.collectionGroup('fcmTokens').where('token', isEqualTo: token).get();
    for (final doc in legacyMatches.docs) {
      final ownerRef = doc.reference.parent.parent;
      final ownerUid = ownerRef?.id ?? '';
      if (ownerUid.isEmpty || ownerUid == activeUid) continue;
      await doc.reference.delete();
    }
  }

  Future<void> registerCurrentDeviceForUser({
    required String uid,
    String appVersion = 'unknown',
    String projectId = 'unknown',
    String packageName = 'unknown',
  }) async {
    if (uid.trim().isEmpty) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.trim().isEmpty) {
      debugPrint('[DeviceRegistrationService] no token for uid=$uid');
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

    debugPrint('[DeviceRegistrationService] token upserted under devices uid=$uid deviceId=$deviceId');

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

    debugPrint('[DeviceRegistrationService] token upserted under fcmTokens uid=$uid');
  }

  Future<void> unregisterCurrentDeviceForUser(String uid) async {
    if (uid.trim().isEmpty) return;

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
  }
}
