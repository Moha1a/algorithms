import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'device_registration_service.dart';
import 'iraqi_phone_utils.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static const _testClientEmail = 'test.client@monfathak.local';
  static const _testOutletEmail = 'test.outlet@monfathak.local';
  static const _testPassword = 'TestAccount#2026';

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password.trim())).toString();
  }

  String mapFirebaseAuthError(Object error) {
    if (error is! FirebaseAuthException) {
      return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
    }
    switch (error.code) {
      case 'invalid-phone-number':
        return 'رقم الهاتف غير صحيح.';
      case 'invalid-verification-code':
        return 'رمز التحقق غير صحيح.';
      case 'session-expired':
        return 'انتهت صلاحية رمز التحقق. أعد المحاولة.';
      case 'too-many-requests':
        return 'تمت محاولات كثيرة. انتظر قليلًا ثم أعد المحاولة.';
      case 'quota-exceeded':
        return 'تم تجاوز الحد المسموح للإرسال حاليًا. حاول لاحقًا.';
      case 'network-request-failed':
        return 'تعذر الاتصال بالإنترنت. تحقق من الشبكة.';
      case 'weak-password':
        return 'كلمة المرور ضعيفة. يجب أن تكون 6 أحرف على الأقل.';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة.';
      case 'missing-user-doc':
        return 'الحساب غير مكتمل. يرجى إنشاء حساب جديد أولًا.';
      case 'role-mismatch':
        return 'هذا الحساب مسجل بدور مختلف.';
      case 'captcha-check-failed':
        return 'تعذر التحقق الأمني. حاول مرة أخرى.';
      case 'app-not-authorized':
        return 'التطبيق غير مصرح لهذا المشروع.';
      default:
        return error.message ?? 'حدث خطأ في المصادقة. حاول مرة أخرى.';
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential credential) verificationCompleted,
    required void Function(FirebaseAuthException exception) verificationFailed,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) {
    return _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      forceResendingToken: forceResendingToken,
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> assertLoginPasswordBeforeOtp({
    required String phoneNumber,
    required String password,
    required String role,
  }) async {
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    final pass = password.trim();
    if (pass.length < 6) {
      throw FirebaseAuthException(code: 'weak-password', message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    final snap = await _firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: normalizedPhone)
        .limit(5)
        .get();

    if (snap.docs.isEmpty) {
      throw FirebaseAuthException(code: 'missing-user-doc', message: 'هذا الرقم غير مسجل بعد.');
    }

    final docs = snap.docs.map((d) => d.data()).toList(growable: false);
    final profile = docs.firstWhere(
      (d) => (d['role'] ?? '').toString() == role,
      orElse: () => docs.first,
    );
    final existingRole = (profile['role'] ?? '').toString();
    if (existingRole.isNotEmpty && existingRole != role) {
      throw FirebaseAuthException(code: 'role-mismatch', message: 'هذا الحساب مسجل بدور مختلف.');
    }

    final savedHash = (profile['passwordHash'] ?? '').toString().trim();
    if (savedHash.isEmpty) {
      return;
    }
    final enteredHash = _hashPassword(pass).trim();
    if (savedHash != enteredHash) {
      throw FirebaseAuthException(code: 'wrong-password', message: 'كلمة المرور غير صحيحة.');
    }
  }

  Future<Map<String, dynamic>> loginOrRegisterWithCredential({
    required PhoneAuthCredential credential,
    required String role,
    required String phoneNumber,
    required String password,
    required bool isRegistration,
    required String fullName,
    required String governorate,
    String? outletName,
  }) async {
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    final trimmedPassword = password.trim();
    if (trimmedPassword.length < 6) {
      throw FirebaseAuthException(code: 'weak-password', message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    final userCredential = await _auth.signInWithCredential(credential);
    final uid = userCredential.user?.uid;
    if (uid == null) {
      throw FirebaseAuthException(code: 'user-not-found', message: 'تعذر تسجيل الدخول');
    }

    try {
      await _migrateLegacyUidIfNeeded(
        currentUid: uid,
        normalizedPhone: normalizedPhone,
        role: role,
      );
    } catch (error, stackTrace) {
      debugPrint('[AuthService] legacy migration skipped due to error: $error');
      debugPrint('$stackTrace');
    }

    final userDocRef = _firestore.collection('users').doc(uid);
    final snap = await userDocRef.get();
    final passwordHash = _hashPassword(trimmedPassword);

    if (snap.exists && snap.data() != null) {
      final profile = snap.data()!;
      final existingRole = (profile['role'] ?? '').toString();
      if (existingRole.isNotEmpty && existingRole != role) {
        throw FirebaseAuthException(code: 'role-mismatch', message: 'هذا الحساب مسجل بدور مختلف');
      }

      var savedHash = (profile['passwordHash'] ?? '').toString();
      if (savedHash.isEmpty) {
        await userDocRef.set({
          'passwordHash': passwordHash,
          'passwordCreatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        savedHash = passwordHash;
      }
      if (savedHash.trim().isNotEmpty && savedHash.trim() != passwordHash.trim()) {
        await _auth.signOut();
        throw FirebaseAuthException(code: 'wrong-password', message: 'كلمة المرور غير صحيحة');
      }

      await userDocRef.set({
        'uid': uid,
        'phoneNumber': normalizedPhone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await DeviceRegistrationService.instance.registerAndListenTokenRefresh();
      final fresh = await userDocRef.get();
      return fresh.data()!;
    }

    if (!isRegistration) {
      throw FirebaseAuthException(
        code: 'missing-user-doc',
        message: 'هذا الرقم غير مسجل بعد. اختر إنشاء حساب جديد أولًا',
      );
    }

    final payload = <String, dynamic>{
      'uid': uid,
      'fullName': fullName.trim(),
      'role': role,
      'governorate': governorate.trim(),
      'phoneNumber': normalizedPhone,
      'passwordHash': passwordHash,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (role == 'outlet') {
      payload['outletName'] = (outletName ?? '').trim();
    }

    await userDocRef.set(payload, SetOptions(merge: true));

    await DeviceRegistrationService.instance.registerAndListenTokenRefresh();
    final fresh = await userDocRef.get();
    return fresh.data()!;
  }

  Future<void> resetPasswordAfterOtp({
    required PhoneAuthCredential credential,
    required String newPassword,
  }) async {
    final trimmed = newPassword.trim();
    if (trimmed.length < 6) {
      throw FirebaseAuthException(code: 'weak-password', message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    final userCredential = await _auth.signInWithCredential(credential);
    final uid = userCredential.user?.uid;
    if (uid == null) {
      throw FirebaseAuthException(code: 'user-not-found', message: 'تعذر إعادة تعيين كلمة المرور');
    }

    final userRef = _firestore.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      throw FirebaseAuthException(code: 'missing-user-doc', message: 'الحساب غير موجود');
    }

    await userRef.set({
      'passwordHash': _hashPassword(trimmed),
      'passwordUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await DeviceRegistrationService.instance.registerAndListenTokenRefresh();
  }

  Future<void> resetPasswordForVerifiedUid({
    required String uid,
    required String newPassword,
  }) async {
    final trimmed = newPassword.trim();
    if (trimmed.length < 6) {
      throw FirebaseAuthException(code: 'weak-password', message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      throw FirebaseAuthException(code: 'user-not-found', message: 'تعذر تحديد الحساب');
    }

    final userRef = _firestore.collection('users').doc(cleanUid);
    final snap = await userRef.get();
    if (!snap.exists) {
      throw FirebaseAuthException(code: 'missing-user-doc', message: 'الحساب غير موجود');
    }

    await userRef.set({
      'passwordHash': _hashPassword(trimmed),
      'passwordUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> loginAsTestAccount({required String role}) async {
    final isOutlet = role == 'outlet';
    final email = isOutlet ? _testOutletEmail : _testClientEmail;

    try {
      await _auth.signInWithEmailAndPassword(email: email, password: _testPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') rethrow;
      await _auth.createUserWithEmailAndPassword(email: email, password: _testPassword);
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw FirebaseAuthException(code: 'user-not-found', message: 'تعذر تسجيل دخول حساب الاختبار');
    }

    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'fullName': isOutlet ? 'مزود اختبار' : 'عميل اختبار',
      'role': role,
      'governorate': 'البصرة',
      'outletName': isOutlet ? 'منفذ اختبار' : null,
      'passwordHash': _hashPassword(_testPassword),
      'isTestAccount': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await DeviceRegistrationService.instance.registerAndListenTokenRefresh();
    final fresh = await _firestore.collection('users').doc(uid).get();
    return fresh.data()!;
  }

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      try {
        await DeviceRegistrationService.instance.unregisterCurrentDeviceForUser(uid);
      } catch (_) {}
    }

    try {
      await DeviceRegistrationService.instance.stopTokenRefreshListener();
    } catch (_) {}

    await _auth.signOut();
  }

  Future<void> _migrateLegacyUidIfNeeded({
    required String currentUid,
    required String normalizedPhone,
    required String role,
  }) async {
    if (currentUid.trim().isEmpty || normalizedPhone.trim().isEmpty || role.trim().isEmpty) return;

    final usersSnap = await _firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: normalizedPhone)
        .where('role', isEqualTo: role)
        .limit(20)
        .get();

    final legacyDocs = usersSnap.docs.where((doc) => doc.id != currentUid).toList(growable: false);
    if (legacyDocs.isEmpty) return;

    final legacyDoc = legacyDocs.first;
    final legacyUid = legacyDoc.id;
    final legacyData = legacyDoc.data();
    final currentRef = _firestore.collection('users').doc(currentUid);
    final legacyRef = _firestore.collection('users').doc(legacyUid);

    await _firestore.runTransaction((tx) async {
      final currentSnap = await tx.get(currentRef);
      final currentData = currentSnap.data() ?? <String, dynamic>{};

      final importantKeys = <String>{
        'fullName',
        'outletName',
        'governorate',
        'avatarUrl',
        'passwordHash',
        'passwordCreatedAt',
        'passwordUpdatedAt',
      };

      final merged = <String, dynamic>{...legacyData, ...currentData};
      for (final key in importantKeys) {
        final currentVal = currentData[key];
        final legacyVal = legacyData[key];
        final currentHasValue = currentVal != null && currentVal.toString().trim().isNotEmpty;
        final legacyHasValue = legacyVal != null && legacyVal.toString().trim().isNotEmpty;
        if (!currentHasValue && legacyHasValue) {
          merged[key] = legacyVal;
        }
      }

      final legacyUids = <String>{legacyUid};
      final currentLegacy = currentData['legacyUids'];
      if (currentLegacy is List) {
        legacyUids.addAll(currentLegacy.map((e) => e.toString()).where((e) => e.trim().isNotEmpty));
      }
      final legacyLegacy = legacyData['legacyUids'];
      if (legacyLegacy is List) {
        legacyUids.addAll(legacyLegacy.map((e) => e.toString()).where((e) => e.trim().isNotEmpty));
      }

      merged['uid'] = currentUid;
      merged['role'] = role;
      merged['phoneNumber'] = normalizedPhone;
      merged['legacyUids'] = legacyUids.toList(growable: false);
      merged['migratedFromLegacyAt'] = FieldValue.serverTimestamp();
      merged['updatedAt'] = FieldValue.serverTimestamp();

      tx.set(currentRef, merged, SetOptions(merge: true));
      tx.set(legacyRef, {
        'uid': legacyUid,
        'phoneNumber': normalizedPhone,
        'role': role,
        'migratedToUid': currentUid,
        'migratedAt': FieldValue.serverTimestamp(),
        'active': false,
        'legacyOf': currentUid,
      }, SetOptions(merge: true));
    });

    await _migrateLegacyIdentityReferences(
      legacyUid: legacyUid,
      currentUid: currentUid,
    );

    await _migrateLegacyDevices(
      legacyUid: legacyUid,
      currentUid: currentUid,
    );

    debugPrint('[AuthService] legacy UID migration done old=$legacyUid new=$currentUid role=$role');
  }

  Future<void> _migrateLegacyIdentityReferences({
    required String legacyUid,
    required String currentUid,
  }) async {
    if (legacyUid.trim().isEmpty || currentUid.trim().isEmpty || legacyUid == currentUid) return;

    await _replaceBookingsUidField(field: 'clientId', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(field: 'createdById', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(field: 'outletId', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(field: 'cancelledBy', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(field: 'completedBy', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(field: 'arrivalMarkedBy', legacyUid: legacyUid, currentUid: currentUid);

    await _replaceGenericUidField(collection: 'notifications', field: 'toUserId', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceGenericUidField(collection: 'notifications', field: 'actorId', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceGenericUidField(collection: 'admin_inbox', field: 'toUserId', legacyUid: legacyUid, currentUid: currentUid);

    await _replaceCollectionGroupUidField(
      collectionId: 'messages',
      field: 'toUserId',
      legacyUid: legacyUid,
      currentUid: currentUid,
    );
    await _replaceCollectionGroupUidField(
      collectionId: 'messages',
      field: 'senderId',
      legacyUid: legacyUid,
      currentUid: currentUid,
    );

    await _migrateBookingProposalsAndChatSeen(legacyUid: legacyUid, currentUid: currentUid);
  }

  Future<void> _replaceBookingsUidField({
    required String field,
    required String legacyUid,
    required String currentUid,
  }) async {
    while (true) {
      final snap = await _firestore.collection('bookings').where(field, isEqualTo: legacyUid).limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {field: currentUid});
      }
      await batch.commit();
    }
  }

  Future<void> _replaceGenericUidField({
    required String collection,
    required String field,
    required String legacyUid,
    required String currentUid,
  }) async {
    while (true) {
      final snap = await _firestore.collection(collection).where(field, isEqualTo: legacyUid).limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {field: currentUid});
      }
      await batch.commit();
    }
  }

  Future<void> _replaceCollectionGroupUidField({
    required String collectionId,
    required String field,
    required String legacyUid,
    required String currentUid,
  }) async {
    while (true) {
      final snap = await _firestore.collectionGroup(collectionId).where(field, isEqualTo: legacyUid).limit(400).get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {field: currentUid});
      }
      await batch.commit();
    }
  }

  Future<void> _migrateBookingProposalsAndChatSeen({
    required String legacyUid,
    required String currentUid,
  }) async {
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDoc;
    while (true) {
      Query<Map<String, dynamic>> query = _firestore.collection('bookings').orderBy(FieldPath.documentId).limit(400);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }
      final snap = await query.get();
      if (snap.docs.isEmpty) return;

      final batch = _firestore.batch();
      var changed = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final updates = <String, dynamic>{};

        final rawProposals = (data['priceProposals'] as List?) ?? const [];
        if (rawProposals.isNotEmpty) {
          var proposalsChanged = false;
          final patched = <Map<String, dynamic>>[];
          for (final raw in rawProposals) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            if ((item['outletId'] ?? '').toString() == legacyUid) {
              item['outletId'] = currentUid;
              proposalsChanged = true;
            }
            patched.add(item);
          }
          if (proposalsChanged) {
            updates['priceProposals'] = patched;
          }
        }

        final chatLastSeenRaw = data['chatLastSeen'];
        if (chatLastSeenRaw is Map && chatLastSeenRaw.containsKey(legacyUid)) {
          final chatLastSeen = Map<String, dynamic>.from(chatLastSeenRaw);
          chatLastSeen[currentUid] ??= chatLastSeen[legacyUid];
          chatLastSeen.remove(legacyUid);
          updates['chatLastSeen'] = chatLastSeen;
        }

        if (updates.isNotEmpty) {
          batch.update(doc.reference, updates);
          changed += 1;
        }
      }

      if (changed > 0) {
        await batch.commit();
      }
      lastDoc = snap.docs.last;
    }
  }

  Future<void> _migrateLegacyDevices({
    required String legacyUid,
    required String currentUid,
  }) async {
    if (legacyUid == currentUid) return;

    final legacyDevices = await _firestore.collection('users').doc(legacyUid).collection('devices').get();
    final legacyFcmTokens = await _firestore.collection('users').doc(legacyUid).collection('fcmTokens').get();
    final targetDevicesRef = _firestore.collection('users').doc(currentUid).collection('devices');

    if (legacyDevices.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in legacyDevices.docs) {
        final token = (doc.data()['token'] ?? '').toString().trim();
        if (token.isNotEmpty) {
          batch.set(targetDevicesRef.doc(doc.id), {
            ...doc.data(),
            'token': token,
            'uid': currentUid,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    if (legacyFcmTokens.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in legacyFcmTokens.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}