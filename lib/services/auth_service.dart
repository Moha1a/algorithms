import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_registration_service.dart';
import 'input_digit_utils.dart';
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
  static const appReviewPhone = '1111112222';
  static const appReviewPassword = 'AppleReview#2026!Mf';
  static const _appReviewNormalizedPhone = '+9641111112222';
  static const _appReviewClientEmail = 'app.review.client@monfathak.local';
  static const _appReviewOutletEmail = 'app.review.outlet@monfathak.local';
  static const _appReviewAdminEmail = 'app.review.admin@monfathak.local';
  static const _webAuthEmailDomain = 'monfathak.app';

  static String _appReviewEmailForRole(String role) {
    final normalizedRole = role == 'admin'
        ? 'admin'
        : role == 'outlet'
            ? 'outlet'
            : 'client';
    if (normalizedRole == 'admin') return _appReviewAdminEmail;
    if (normalizedRole == 'outlet') return _appReviewOutletEmail;
    return _appReviewClientEmail;
  }

  static bool _isAppReviewEmail(String email) {
    return email == _appReviewClientEmail ||
        email == _appReviewOutletEmail ||
        email == _appReviewAdminEmail;
  }

  static bool isAppReviewPhoneInput(String phoneNumber) {
    final digits = InputDigitUtils.digitsOnly(phoneNumber);
    return digits == appReviewPhone ||
        IraqiPhoneUtils.normalize(phoneNumber) == _appReviewNormalizedPhone;
  }

  static bool isAppReviewCredentials({
    required String phoneNumber,
    required String password,
  }) {
    return isAppReviewPhoneInput(phoneNumber) &&
        password.trim() == appReviewPassword;
  }

  static String _webEmailForPhoneRole({
    required String normalizedPhone,
    required String role,
  }) {
    final digits = InputDigitUtils.digitsOnly(normalizedPhone);
    final normalizedRole = role == 'outlet' ? 'outlet' : 'client';
    return 'web.$normalizedRole.$digits@$_webAuthEmailDomain';
  }

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
      case 'invalid-credential':
        return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
      case 'email-already-in-use':
        return 'هذا الحساب موجود مسبقاً. جرّب تسجيل الدخول.';
      case 'missing-user-doc':
        return 'الحساب غير موجود. يرجى إنشاء حساب جديد أولًا.';
      case 'role-mismatch':
        return 'هذا الحساب مسجل بدور مختلف.';
      case 'outlet-pending-approval':
        return 'تم إنشاء حساب المنفذ بنجاح، لكنه بانتظار موافقة الإدارة.';
      case 'outlet-rejected':
        return 'تم رفض طلب حساب المنفذ. يرجى التواصل مع الإدارة.';
      case 'captcha-check-failed':
        return 'تعذر التحقق الأمني. حاول مرة أخرى.';
      case 'invalid-app-credential':
        return 'تعذر التحقق الأمني للتطبيق. إذا كنت تستخدم الموقع، تأكد أن رابط الموقع مضاف في Firebase Authentication ضمن Authorized domains ثم حاول مرة أخرى.';
      case 'app-not-authorized':
        return 'التطبيق غير مصرح لهذا المشروع.';
      case 'operation-not-allowed':
        return 'طريقة تسجيل الدخول غير مفعلة في Firebase. فعّل Phone و Email/Password من إعدادات Authentication.';
      case 'unauthorized-domain':
        return 'نطاق الموقع غير مصرح في Firebase Authentication. أضف رابط الموقع ضمن Authorized domains.';
      case 'internal-error':
        return 'تعذر إرسال رمز التحقق حالياً. تأكد من الاتصال وحاول مرة أخرى، وإذا استمرت المشكلة تواصل مع الدعم.';
      case 'web-auth-timeout':
        return 'تعذر فتح الحساب من الموقع حالياً. تحقق من إعدادات Firebase Auth وقواعد Firestore ثم حاول مرة أخرى.';
      case 'user-profile-load-failed':
        return 'تعذر التحقق من الحساب، حاول مرة أخرى';
      case 'preview-phone-auth-disabled':
        return 'تسجيل OTP غير متاح في وضع المعاينة.';
      default:
        return error.message ?? 'حدث خطأ في المصادقة. حاول مرة أخرى.';
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential credential)
        verificationCompleted,
    required void Function(FirebaseAuthException exception) verificationFailed,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(String verificationId) codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) {
    try {
      final firebaseApp = _auth.app;
      final isLikelyE164 = RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phoneNumber);
      final hasPlus = phoneNumber.startsWith('+');
      final plusDigitsOnly = RegExp(r'^\+\d+$').hasMatch(phoneNumber);
      debugPrint('[PHONE AUTH PREFLIGHT] platform=$defaultTargetPlatform');
      debugPrint(
          '[PHONE AUTH PREFLIGHT] appName=${firebaseApp.name} projectId=${firebaseApp.options.projectId} appId=${firebaseApp.options.appId}');
      debugPrint(
          '[PHONE AUTH PREFLIGHT] phone=$phoneNumber hasPlus=$hasPlus plusDigitsOnly=$plusDigitsOnly isLikelyE164=$isLikelyE164');
      FirebaseCrashlytics.instance
          .log('[PHONE AUTH PREFLIGHT] phone=$phoneNumber role=unknown');
      if (!isLikelyE164) {
        throw FirebaseAuthException(
          code: 'invalid-phone-number',
          message: 'رقم الهاتف غير صالح. يجب أن يكون بصيغة +9647XXXXXXXXX',
        );
      }
      debugPrint('PHONE_AUTH_START');
      debugPrint('PHONE_AUTH_VERIFY_START');
      return _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) {
          try {
            verificationCompleted(credential);
          } catch (error, stackTrace) {
            debugPrint(
                '[OTP FLOW] verificationCompleted callback failed: $error');
            debugPrint('$stackTrace');
          }
        },
        verificationFailed: (exception) {
          try {
            _recordPhoneAuthFailure(exception, phoneNumber);
            verificationFailed(exception);
          } catch (error, stackTrace) {
            debugPrint('[OTP FLOW] verificationFailed callback failed: $error');
            debugPrint('$stackTrace');
          }
        },
        codeSent: (verificationId, resendToken) {
          try {
            codeSent(verificationId, resendToken);
          } catch (error, stackTrace) {
            debugPrint('[OTP FLOW] codeSent callback failed: $error');
            debugPrint('$stackTrace');
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          try {
            codeAutoRetrievalTimeout(verificationId);
          } catch (error, stackTrace) {
            debugPrint(
                '[OTP FLOW] codeAutoRetrievalTimeout callback failed: $error');
            debugPrint('$stackTrace');
          }
        },
        forceResendingToken: forceResendingToken,
        timeout: const Duration(seconds: 60),
      );
    } on FirebaseAuthException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[OTP FLOW] verifyPhoneNumber failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      debugPrint('PHONE_AUTH_EXCEPTION_CAUGHT');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed',
          message: 'تعذر التحقق من الحساب، حاول مرة أخرى');
    }
  }

  Future<String> sendWebPhoneVerificationCode({
    required String phoneNumber,
  }) async {
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    final isLikelyE164 = RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalizedPhone);
    debugPrint(
      '[WEB PHONE AUTH] start host=${Uri.base.host} phone=$normalizedPhone isLikelyE164=$isLikelyE164',
    );
    if (!kIsWeb) {
      throw FirebaseAuthException(
        code: 'unsupported-platform',
        message: 'Web phone verification is only available on web.',
      );
    }
    if (!isLikelyE164) {
      throw FirebaseAuthException(
        code: 'invalid-phone-number',
        message: 'رقم الهاتف غير صالح. يجب أن يكون بصيغة +9647XXXXXXXXX',
      );
    }

    try {
      final result = await _auth.signInWithPhoneNumber(normalizedPhone);
      final verificationId = result.verificationId.trim();
      debugPrint(
        '[WEB PHONE AUTH] code sent verificationIdPresent=${verificationId.isNotEmpty}',
      );
      if (verificationId.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-verification-id',
          message: 'تعذر إنشاء جلسة التحقق من رقم الهاتف.',
        );
      }
      return verificationId;
    } on FirebaseAuthException catch (exception) {
      _recordPhoneAuthFailure(exception, normalizedPhone);
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('[WEB PHONE AUTH] failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      throw FirebaseAuthException(
        code: 'invalid-app-credential',
        message:
            'Phone verification failed because the web app verifier was rejected.',
      );
    }
  }

  void _recordPhoneAuthFailure(
      FirebaseAuthException exception, String phoneNumber) {
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    final phonePrefix = normalizedPhone.length >= 7
        ? normalizedPhone.substring(0, 7)
        : normalizedPhone;
    final crashlytics = FirebaseCrashlytics.instance;

    debugPrint(
        '[PHONE AUTH FAILED] code=${exception.code} message=${exception.message ?? ''}');
    crashlytics.log('phone_auth_failed code=${exception.code}');
    crashlytics.setCustomKey('phone_auth_error_code', exception.code);
    crashlytics.setCustomKey(
        'phone_auth_error_message', exception.message ?? '');
    crashlytics.setCustomKey(
        'phone_auth_project_id', _auth.app.options.projectId);
    crashlytics.setCustomKey('phone_auth_app_id', _auth.app.options.appId);
    crashlytics.setCustomKey('phone_auth_platform', defaultTargetPlatform.name);
    crashlytics.setCustomKey('phone_auth_phone_prefix', phonePrefix);
    crashlytics.recordError(exception, StackTrace.current, fatal: false);
  }

  Future<Map<String, dynamic>> loginWithPhonePasswordPreview({
    required String role,
    required String phoneNumber,
    required String password,
  }) async {
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    await assertLoginPasswordBeforeOtp(
        phoneNumber: normalizedPhone, password: password, role: role);
    return _resolveProfileForLogin(
      role: role,
      normalizedPhone: normalizedPhone,
    );
  }

  Future<Map<String, dynamic>> loginOrRegisterWebWithPhonePassword({
    required String role,
    required String phoneNumber,
    required String password,
    required bool isRegistration,
    required String fullName,
    required String governorate,
    String? outletName,
    required bool acceptedTerms,
    required String termsVersion,
    required List<String> acceptedTermsItems,
  }) async {
    final normalizedRole = role == 'outlet' ? 'outlet' : 'client';
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    final trimmedPassword = password.trim();
    final passwordHash = _hashPassword(trimmedPassword);
    final normalizedTermsVersion = termsVersion.trim();
    final normalizedTermsItems = acceptedTermsItems
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    if (trimmedPassword.length < 6) {
      throw FirebaseAuthException(
          code: 'weak-password',
          message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }
    if (isRegistration &&
        (!acceptedTerms ||
            normalizedTermsVersion.isEmpty ||
            normalizedTermsItems.isEmpty)) {
      throw FirebaseAuthException(
        code: 'terms-not-accepted',
        message: 'يرجى الموافقة على الشروط والأحكام لإكمال التسجيل.',
      );
    }

    Map<String, dynamic>? existingProfile;
    if (!isRegistration) {
      existingProfile = await _tryFindProfileByPhoneCandidatesFast(
        normalizedPhone: normalizedPhone,
        role: normalizedRole,
      );
    }
    if (existingProfile != null) {
      final existingRole = (existingProfile['role'] ?? '').toString();
      if (existingRole.isNotEmpty && existingRole != normalizedRole) {
        throw FirebaseAuthException(
            code: 'role-mismatch', message: 'هذا الحساب مسجل بدور مختلف.');
      }
      final savedHash =
          (existingProfile['passwordHash'] ?? '').toString().trim();
      if (savedHash.isNotEmpty && savedHash != passwordHash) {
        throw FirebaseAuthException(
            code: 'wrong-password', message: 'كلمة المرور غير صحيحة.');
      }
    } else if (!isRegistration) {
      throw FirebaseAuthException(
          code: 'missing-user-doc', message: 'هذا الرقم غير مسجل بعد.');
    }

    final email = _webEmailForPhoneRole(
      normalizedPhone: normalizedPhone,
      role: normalizedRole,
    );

    try {
      if (isRegistration) {
        try {
          await _auth.createUserWithEmailAndPassword(
              email: email, password: trimmedPassword);
        } on FirebaseAuthException catch (error) {
          if (error.code != 'email-already-in-use') rethrow;
          await _auth.signInWithEmailAndPassword(
              email: email, password: trimmedPassword);
        }
      } else {
        try {
          await _auth.signInWithEmailAndPassword(
              email: email, password: trimmedPassword);
        } on FirebaseAuthException catch (error) {
          if (error.code != 'user-not-found' &&
              error.code != 'invalid-credential' &&
              error.code != 'wrong-password') {
            rethrow;
          }
          if (existingProfile == null ||
              (existingProfile['passwordHash'] ?? '').toString().trim() !=
                  passwordHash) {
            throw FirebaseAuthException(
                code: 'wrong-password', message: 'كلمة المرور غير صحيحة.');
          }
          await _auth.createUserWithEmailAndPassword(
              email: email, password: trimmedPassword);
        }
      }
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        await _auth.signInWithEmailAndPassword(
            email: email, password: trimmedPassword);
      } else {
        rethrow;
      }
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw FirebaseAuthException(
          code: 'user-not-found', message: 'تعذر فتح الحساب من الموقع.');
    }

    try {
      await _migrateLegacyUidIfNeeded(
        currentUid: uid,
        normalizedPhone: normalizedPhone,
        role: normalizedRole,
      );
    } catch (error, stackTrace) {
      debugPrint('[AuthService] web legacy migration skipped: $error');
      debugPrint('$stackTrace');
    }

    final userDocRef = _firestore.collection('users').doc(uid);
    final snap = await userDocRef.get().timeout(const Duration(seconds: 8));
    final existingCurrent = snap.data();

    if (existingCurrent != null && existingCurrent.isNotEmpty) {
      final existingRole = (existingCurrent['role'] ?? '').toString();
      if (existingRole.isNotEmpty && existingRole != normalizedRole) {
        throw FirebaseAuthException(
            code: 'role-mismatch', message: 'هذا الحساب مسجل بدور مختلف.');
      }
      if (normalizedRole == 'outlet') {
        final approvalStatus =
            (existingCurrent['approvalStatus'] ?? '').toString();
        if (approvalStatus == 'pending') {
          throw FirebaseAuthException(
            code: 'outlet-pending-approval',
            message: 'حساب المنفذ بانتظار موافقة الإدارة.',
          );
        }
        if (approvalStatus == 'rejected') {
          throw FirebaseAuthException(
              code: 'outlet-rejected', message: 'تم رفض طلب حساب المنفذ.');
        }
      }
      final savedHash =
          (existingCurrent['passwordHash'] ?? '').toString().trim();
      if (savedHash.isNotEmpty && savedHash != passwordHash) {
        await _auth.signOut();
        throw FirebaseAuthException(
            code: 'wrong-password', message: 'كلمة المرور غير صحيحة.');
      }
      await userDocRef.set({
        'uid': uid,
        'phoneNumber': normalizedPhone,
        'passwordHash': passwordHash,
        'webAuthEmail': email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (existingProfile != null) {
      await userDocRef.set({
        ...existingProfile,
        'uid': uid,
        'phoneNumber': normalizedPhone,
        'passwordHash': passwordHash,
        'webAuthEmail': email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      final payload = <String, dynamic>{
        'uid': uid,
        'fullName': fullName.trim(),
        'role': normalizedRole,
        'governorate': governorate.trim(),
        'phoneNumber': normalizedPhone,
        'passwordHash': passwordHash,
        'webAuthEmail': email,
        'termsAccepted': acceptedTerms,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'termsVersion': normalizedTermsVersion,
        'termsAcceptedRole': normalizedRole,
        'termsAcceptedItems': normalizedTermsItems,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (normalizedRole == 'outlet') {
        payload['outletName'] = (outletName ?? '').trim();
        payload['approvalStatus'] = 'pending';
        payload['approvalRequestedAt'] = FieldValue.serverTimestamp();
        payload['approvalDecisionAt'] = null;
        payload['approvedBy'] = '';
      }

      await userDocRef.set(payload, SetOptions(merge: true));

      if (normalizedRole == 'outlet') {
        await _firestore.collection('notifications').add({
          'toUserId': 'admin',
          'type': 'outlet_approval_request',
          'title': 'طلب منفذ جديد',
          'body':
              'تم تقديم طلب جديد من منفذ: ${fullName.trim().isEmpty ? normalizedPhone : fullName.trim()}',
          'requestUid': uid,
          'requestPhone': normalizedPhone,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await _safeRegisterDevice();
    final fresh = await userDocRef.get().timeout(const Duration(seconds: 8));
    final data = fresh.data();
    if (data == null || data.isEmpty) {
      throw FirebaseAuthException(
          code: 'user-profile-load-failed', message: 'تعذر تحميل الملف الشخصي');
    }
    return data;
  }

  Future<void> assertLoginPasswordBeforeOtp({
    required String phoneNumber,
    required String password,
    required String role,
  }) async {
    final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
    debugPrint(
        'login_precheck_start rawPhone=$phoneNumber normalizedPhone=$normalizedPhone role=$role');
    final pass = password.trim();
    if (pass.length < 6) {
      throw FirebaseAuthException(
          code: 'weak-password',
          message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    final profile = await _resolveProfileForLogin(
      role: role,
      normalizedPhone: normalizedPhone,
    );
    final existingRole = (profile['role'] ?? '').toString();
    if (existingRole.isNotEmpty && existingRole != role) {
      throw FirebaseAuthException(
          code: 'role-mismatch', message: 'هذا الحساب مسجل بدور مختلف.');
    }
    if (role == 'outlet') {
      final approvalStatus = (profile['approvalStatus'] ?? '').toString();
      if (approvalStatus == 'pending') {
        throw FirebaseAuthException(
            code: 'outlet-pending-approval',
            message: 'حساب المنفذ بانتظار موافقة الإدارة.');
      }
      if (approvalStatus == 'rejected') {
        throw FirebaseAuthException(
            code: 'outlet-rejected', message: 'تم رفض طلب حساب المنفذ.');
      }
    }

    final savedHash = (profile['passwordHash'] ?? '').toString().trim();
    if (savedHash.isEmpty) {
      return;
    }
    final enteredHash = _hashPassword(pass).trim();
    if (savedHash != enteredHash) {
      debugPrint('password_check_failure role=$role');
      throw FirebaseAuthException(
          code: 'wrong-password', message: 'كلمة المرور غير صحيحة.');
    }
    debugPrint('password_check_success role=$role');
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
    required bool acceptedTerms,
    required String termsVersion,
    required List<String> acceptedTermsItems,
  }) async {
    debugPrint('[LOGIN FLOW] start');
    try {
      final normalizedPhone = IraqiPhoneUtils.normalize(phoneNumber);
      final trimmedPassword = password.trim();
      final normalizedTermsVersion = termsVersion.trim();
      final normalizedTermsItems = acceptedTermsItems
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (trimmedPassword.length < 6) {
        throw FirebaseAuthException(
            code: 'weak-password',
            message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      }

      if (isRegistration &&
          (!acceptedTerms ||
              normalizedTermsVersion.isEmpty ||
              normalizedTermsItems.isEmpty)) {
        throw FirebaseAuthException(
          code: 'terms-not-accepted',
          message: 'يرجى الموافقة على الشروط والأحكام لإكمال التسجيل.',
        );
      }

      final userCredential = await _auth.signInWithCredential(credential);
      debugPrint('[LOGIN FLOW] credential sign-in success');
      final uid = userCredential.user?.uid;
      if (uid == null) {
        throw FirebaseAuthException(
            code: 'user-not-found', message: 'تعذر تسجيل الدخول');
      }

      try {
        await _migrateLegacyUidIfNeeded(
          currentUid: uid,
          normalizedPhone: normalizedPhone,
          role: role,
        );
      } catch (error, stackTrace) {
        debugPrint(
            '[AuthService] legacy migration skipped due to error: $error');
        debugPrint('$stackTrace');
      }

      final userDocRef = _firestore.collection('users').doc(uid);
      debugPrint('[PROFILE LOAD] start');
      DocumentSnapshot<Map<String, dynamic>> snap;
      try {
        snap = await userDocRef.get().timeout(const Duration(seconds: 8));
      } catch (error, stackTrace) {
        debugPrint('PROFILE_LOAD_FAILED: $error');
        debugPrint('$stackTrace');
        throw FirebaseAuthException(
            code: 'user-profile-load-failed',
            message: 'تعذر تحميل الملف الشخصي');
      }
      final passwordHash = _hashPassword(trimmedPassword);

      if (snap.exists && snap.data() != null) {
        final profile = snap.data()!;
        final existingRole = (profile['role'] ?? '').toString();
        if (existingRole.isNotEmpty && existingRole != role) {
          throw FirebaseAuthException(
              code: 'role-mismatch', message: 'هذا الحساب مسجل بدور مختلف');
        }
        if (role == 'outlet') {
          final approvalStatus = (profile['approvalStatus'] ?? '').toString();
          if (approvalStatus == 'pending') {
            throw FirebaseAuthException(
              code: 'outlet-pending-approval',
              message: 'حساب المنفذ بانتظار موافقة الإدارة.',
            );
          }
          if (approvalStatus == 'rejected') {
            throw FirebaseAuthException(
                code: 'outlet-rejected', message: 'تم رفض طلب حساب المنفذ.');
          }
        }

        var savedHash = (profile['passwordHash'] ?? '').toString();
        if (savedHash.isEmpty) {
          await userDocRef.set({
            'passwordHash': passwordHash,
            'passwordCreatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          savedHash = passwordHash;
        }
        if (savedHash.trim().isNotEmpty &&
            savedHash.trim() != passwordHash.trim()) {
          await _auth.signOut();
          throw FirebaseAuthException(
              code: 'wrong-password', message: 'كلمة المرور غير صحيحة');
        }

        await userDocRef.set({
          'uid': uid,
          'phoneNumber': normalizedPhone,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await _safeRegisterDevice();
        final fresh =
            await userDocRef.get().timeout(const Duration(seconds: 8));
        final freshData = fresh.data();
        if (freshData == null) {
          debugPrint('PROFILE_LOAD_FAILED: null profile after login');
          throw FirebaseAuthException(
              code: 'user-profile-load-failed',
              message: 'تعذر تحميل الملف الشخصي');
        }
        debugPrint('[PROFILE LOAD] success');
        return freshData;
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
        'termsAccepted': acceptedTerms,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'termsVersion': normalizedTermsVersion,
        'termsAcceptedRole': role,
        'termsAcceptedItems': normalizedTermsItems,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (role == 'outlet') {
        payload['outletName'] = (outletName ?? '').trim();
        payload['approvalStatus'] = 'pending';
        payload['approvalRequestedAt'] = FieldValue.serverTimestamp();
        payload['approvalDecisionAt'] = null;
        payload['approvedBy'] = '';
      }

      await userDocRef.set(payload, SetOptions(merge: true));

      if (role == 'outlet') {
        await _firestore.collection('notifications').add({
          'toUserId': 'admin',
          'type': 'outlet_approval_request',
          'title': 'طلب منفذ جديد',
          'body':
              'تم تقديم طلب جديد من منفذ: ${fullName.trim().isEmpty ? normalizedPhone : fullName.trim()}',
          'requestUid': uid,
          'requestPhone': normalizedPhone,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _safeRegisterDevice();
      final fresh = await userDocRef.get().timeout(const Duration(seconds: 8));
      final freshData = fresh.data();
      if (freshData == null) {
        debugPrint('PROFILE_LOAD_FAILED: null profile after registration');
        throw FirebaseAuthException(
            code: 'user-profile-load-failed',
            message: 'تعذر تحميل الملف الشخصي');
      }
      debugPrint('[PROFILE LOAD] success');
      return freshData;
    } on FirebaseAuthException {
      rethrow;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('PROFILE_LOAD_FAILED: $error');
      debugPrint('$stackTrace');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed', message: 'تعذر تحميل الملف الشخصي');
    } on PlatformException catch (error, stackTrace) {
      debugPrint('PROFILE_LOAD_FAILED: $error');
      debugPrint('$stackTrace');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed', message: 'تعذر تحميل الملف الشخصي');
    } on FormatException catch (error, stackTrace) {
      debugPrint('PROFILE_LOAD_FAILED: $error');
      debugPrint('$stackTrace');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed', message: 'تعذر تحميل الملف الشخصي');
    } catch (error, stackTrace) {
      debugPrint('PROFILE_LOAD_FAILED: $error');
      debugPrint('$stackTrace');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed', message: 'تعذر تحميل الملف الشخصي');
    }
  }

  Future<void> resetPasswordAfterOtp({
    required PhoneAuthCredential credential,
    required String newPassword,
  }) async {
    final trimmed = newPassword.trim();
    if (trimmed.length < 6) {
      throw FirebaseAuthException(
          code: 'weak-password',
          message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    final userCredential = await _auth.signInWithCredential(credential);
    final uid = userCredential.user?.uid;
    if (uid == null) {
      throw FirebaseAuthException(
          code: 'user-not-found', message: 'تعذر إعادة تعيين كلمة المرور');
    }

    final userRef = _firestore.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      throw FirebaseAuthException(
          code: 'missing-user-doc', message: 'الحساب غير موجود');
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
      throw FirebaseAuthException(
          code: 'weak-password',
          message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      throw FirebaseAuthException(
          code: 'user-not-found', message: 'تعذر تحديد الحساب');
    }

    final userRef = _firestore.collection('users').doc(cleanUid);
    final snap = await userRef.get();
    if (!snap.exists) {
      throw FirebaseAuthException(
          code: 'missing-user-doc', message: 'الحساب غير موجود');
    }

    await userRef.set({
      'passwordHash': _hashPassword(trimmed),
      'passwordUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> loginAsTestAccount(
      {required String role}) async {
    final isOutlet = role == 'outlet';
    final email = isOutlet ? _testOutletEmail : _testClientEmail;

    try {
      await _auth.signInWithEmailAndPassword(
          email: email, password: _testPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') rethrow;
      await _auth.createUserWithEmailAndPassword(
          email: email, password: _testPassword);
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw FirebaseAuthException(
          code: 'user-not-found', message: 'تعذر تسجيل دخول حساب الاختبار');
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

    await _safeRegisterDevice();
    final fresh = await _firestore.collection('users').doc(uid).get();
    return fresh.data()!;
  }

  Future<Map<String, dynamic>> loginAsAppReviewAccount({
    required String role,
    required String phoneNumber,
    required String password,
  }) async {
    if (!isAppReviewCredentials(phoneNumber: phoneNumber, password: password)) {
      throw FirebaseAuthException(
          code: 'wrong-password', message: 'كلمة المرور غير صحيحة.');
    }

    final normalizedRole = role == 'admin'
        ? 'admin'
        : role == 'outlet'
            ? 'outlet'
            : 'client';
    final isOutlet = normalizedRole == 'outlet';
    final isAdmin = normalizedRole == 'admin';
    final email = _appReviewEmailForRole(normalizedRole);

    try {
      await _auth.signInWithEmailAndPassword(
          email: email, password: appReviewPassword);
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') rethrow;
      await _auth.createUserWithEmailAndPassword(
          email: email, password: appReviewPassword);
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw FirebaseAuthException(
          code: 'user-not-found', message: 'تعذر فتح حساب المراجعة.');
    }

    final profile = <String, dynamic>{
      'uid': uid,
      'fullName': isAdmin
          ? 'أدمن مراجعة Apple'
          : isOutlet
              ? 'منفذ مراجعة Apple'
              : 'عميل مراجعة Apple',
      'role': normalizedRole,
      'governorate': 'بغداد',
      'phoneNumber': _appReviewNormalizedPhone,
      'passwordHash': _hashPassword(appReviewPassword),
      'termsAccepted': true,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsVersion': 'app_review',
      'termsAcceptedRole': normalizedRole,
      'isTestAccount': true,
      'isAppReviewAccount': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (isOutlet) {
      profile.addAll({
        'outletName': 'منفذ مراجعة Apple',
        'approvalStatus': 'approved',
        'approvalDecisionAt': FieldValue.serverTimestamp(),
        'approvedBy': 'app_review_seed',
      });
    }

    await _firestore
        .collection('users')
        .doc(uid)
        .set(profile, SetOptions(merge: true));

    await _safeRegisterDevice();
    final fresh = await _firestore.collection('users').doc(uid).get();
    return fresh.data()!;
  }

  Future<void> _safeRegisterDevice() async {
    debugPrint('DEVICE_REGISTRATION_START');
    if (kIsWeb) {
      unawaited(
        DeviceRegistrationService.instance
            .registerAndListenTokenRefresh()
            .timeout(const Duration(seconds: 8))
            .catchError((Object error, StackTrace stackTrace) {
          debugPrint('DEVICE_REGISTRATION_WEB_BACKGROUND_IGNORED: $error');
          debugPrint('$stackTrace');
        }),
      );
      return;
    }

    try {
      await DeviceRegistrationService.instance
          .registerAndListenTokenRefresh()
          .timeout(const Duration(seconds: 12));
    } catch (error, stackTrace) {
      debugPrint('DEVICE_REGISTRATION_FAILED_IGNORED: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      try {
        await DeviceRegistrationService.instance
            .unregisterCurrentDeviceForUser(uid);
      } catch (_) {}
    }

    try {
      await DeviceRegistrationService.instance.stopTokenRefreshListener();
    } catch (_) {}

    await _auth.signOut();
  }

  Future<void> deleteCurrentAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      await _auth.signOut();
      return;
    }

    final uid = user.uid.trim();
    if (uid.isEmpty) {
      await _auth.signOut();
      return;
    }

    final crashlytics = FirebaseCrashlytics.instance;
    crashlytics.log('account_deletion_started uid=$uid');
    crashlytics.setCustomKey('account_deletion_uid', uid);
    crashlytics.setCustomKey('account_deletion_success', false);

    await _reauthenticateAppReviewUserIfNeeded(user);

    try {
      await DeviceRegistrationService.instance
          .unregisterCurrentDeviceForUser(uid);
      await DeviceRegistrationService.instance.stopTokenRefreshListener();
    } catch (error, stackTrace) {
      debugPrint(
          '[AuthService] account deletion device cleanup ignored: $error');
      debugPrint('$stackTrace');
      crashlytics.recordError(error, stackTrace, fatal: false);
    }

    try {
      await _cancelActiveBookingsForDeletedAccount(uid);
      await _deleteAccountCollections(uid);
      await _deleteAccountNotificationsAndRatings(uid);
    } catch (error, stackTrace) {
      debugPrint('[AuthService] account related data cleanup ignored: $error');
      debugPrint('$stackTrace');
      crashlytics.recordError(error, stackTrace, fatal: false);
    }

    await _deleteOrAnonymizeUserDocument(uid);

    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        throw FirebaseAuthException(
          code: 'requires-recent-login',
          message: 'يرجى تسجيل الخروج ثم تسجيل الدخول مرة أخرى قبل حذف الحساب.',
        );
      }
      rethrow;
    }

    crashlytics.setCustomKey('account_deletion_success', true);
    crashlytics.log('account_deletion_completed uid=$uid');
    await _auth.signOut();
  }

  Future<void> _reauthenticateAppReviewUserIfNeeded(User user) async {
    final email = (user.email ?? '').trim();
    if (!_isAppReviewEmail(email)) return;

    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: email,
          password: appReviewPassword,
        ),
      );
      debugPrint(
          '[AuthService] app review user reauthenticated before deletion');
    } catch (error, stackTrace) {
      debugPrint('[AuthService] app review reauthentication failed: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      rethrow;
    }
  }

  Future<void> _deleteAccountCollections(String uid) async {
    final userRef = _firestore.collection('users').doc(uid);
    await _deleteCollectionDocs(userRef.collection('devices'));
    await _deleteCollectionDocs(userRef.collection('fcmTokens'));
    await _deleteCollectionDocs(_firestore
        .collection('support_general')
        .doc(uid)
        .collection('messages'));
    await _safeDeleteDocument(
        _firestore.collection('support_general').doc(uid));
  }

  Future<void> _deleteAccountNotificationsAndRatings(String uid) async {
    await _deleteMatchingDocs(
        collection: 'notifications', field: 'toUserId', value: uid);
    await _deleteMatchingDocs(
        collection: 'notifications', field: 'actorId', value: uid);
    await _deleteMatchingDocs(
        collection: 'admin_inbox', field: 'toUserId', value: uid);
    await _deleteMatchingDocs(
        collection: 'ratings', field: 'fromUserId', value: uid);
    await _deleteMatchingDocs(
        collection: 'ratings', field: 'toUserId', value: uid);
  }

  Future<void> _cancelActiveBookingsForDeletedAccount(String uid) async {
    const fields = ['createdById', 'clientId', 'outletId'];
    const activeStatuses = {'pending', 'accepted', 'in_progress'};

    for (final field in fields) {
      DocumentSnapshot<Map<String, dynamic>>? lastDoc;
      while (true) {
        Query<Map<String, dynamic>> query = _firestore
            .collection('bookings')
            .where(field, isEqualTo: uid)
            .orderBy(FieldPath.documentId)
            .limit(200);
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snap = await query.get().timeout(const Duration(seconds: 12));
        if (snap.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString();
          final updates = <String, dynamic>{
            'updatedAt': FieldValue.serverTimestamp(),
            'accountDeletedAt': FieldValue.serverTimestamp(),
          };

          if (field == 'clientId' || field == 'createdById') {
            updates['clientName'] = 'مستخدم محذوف';
          }
          if (field == 'outletId') {
            updates['outletName'] = 'مستخدم محذوف';
          }
          if (activeStatuses.contains(status)) {
            updates.addAll({
              'status': 'cancelled',
              'cancelReason': 'account_deleted',
              'cancelledAt': FieldValue.serverTimestamp(),
              'cancelledBy': uid,
            });
          }

          batch.set(doc.reference, updates, SetOptions(merge: true));
        }
        await batch.commit();
        lastDoc = snap.docs.last;
      }
    }
  }

  Future<void> _deleteOrAnonymizeUserDocument(String uid) async {
    final userRef = _firestore.collection('users').doc(uid);
    try {
      await userRef.delete();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
          '[AuthService] user doc delete failed, anonymizing instead: $error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      await userRef.set({
        'uid': uid,
        'role': 'deleted',
        'fullName': 'مستخدم محذوف',
        'accountDeleted': true,
        'accountDeletedAt': FieldValue.serverTimestamp(),
        'phoneNumber': FieldValue.delete(),
        'outletName': FieldValue.delete(),
        'passwordHash': FieldValue.delete(),
        'termsAcceptedItems': FieldValue.delete(),
        'fcmToken': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _deleteCollectionDocs(
      CollectionReference<Map<String, dynamic>> ref) async {
    while (true) {
      final snap =
          await ref.limit(200).get().timeout(const Duration(seconds: 12));
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteMatchingDocs({
    required String collection,
    required String field,
    required String value,
  }) async {
    while (true) {
      final snap = await _firestore
          .collection(collection)
          .where(field, isEqualTo: value)
          .limit(200)
          .get()
          .timeout(const Duration(seconds: 12));
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _safeDeleteDocument(
      DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.delete();
    } catch (_) {}
  }

  Future<void> _migrateLegacyUidIfNeeded({
    required String currentUid,
    required String normalizedPhone,
    required String role,
  }) async {
    if (currentUid.trim().isEmpty ||
        normalizedPhone.trim().isEmpty ||
        role.trim().isEmpty) {
      return;
    }

    final usersSnap = await _firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: normalizedPhone)
        .where('role', isEqualTo: role)
        .limit(20)
        .get();

    final legacyDocs = usersSnap.docs
        .where((doc) => doc.id != currentUid)
        .toList(growable: false);
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
        final currentHasValue =
            currentVal != null && currentVal.toString().trim().isNotEmpty;
        final legacyHasValue =
            legacyVal != null && legacyVal.toString().trim().isNotEmpty;
        if (!currentHasValue && legacyHasValue) {
          merged[key] = legacyVal;
        }
      }

      final legacyUids = <String>{legacyUid};
      final currentLegacy = currentData['legacyUids'];
      if (currentLegacy is List) {
        legacyUids.addAll(currentLegacy
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty));
      }
      final legacyLegacy = legacyData['legacyUids'];
      if (legacyLegacy is List) {
        legacyUids.addAll(legacyLegacy
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty));
      }

      merged['uid'] = currentUid;
      merged['role'] = role;
      merged['phoneNumber'] = normalizedPhone;
      merged['legacyUids'] = legacyUids.toList(growable: false);
      merged['migratedFromLegacyAt'] = FieldValue.serverTimestamp();
      merged['updatedAt'] = FieldValue.serverTimestamp();

      tx.set(currentRef, merged, SetOptions(merge: true));
      tx.set(
          legacyRef,
          {
            'uid': legacyUid,
            'phoneNumber': normalizedPhone,
            'role': role,
            'migratedToUid': currentUid,
            'migratedAt': FieldValue.serverTimestamp(),
            'active': false,
            'legacyOf': currentUid,
          },
          SetOptions(merge: true));
    });

    await _migrateLegacyIdentityReferences(
      legacyUid: legacyUid,
      currentUid: currentUid,
    );

    await _migrateLegacyDevices(
      legacyUid: legacyUid,
      currentUid: currentUid,
    );

    debugPrint(
        '[AuthService] legacy UID migration done old=$legacyUid new=$currentUid role=$role');
  }

  Future<void> _migrateLegacyIdentityReferences({
    required String legacyUid,
    required String currentUid,
  }) async {
    if (legacyUid.trim().isEmpty ||
        currentUid.trim().isEmpty ||
        legacyUid == currentUid) {
      return;
    }

    await _replaceBookingsUidField(
        field: 'clientId', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(
        field: 'createdById', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(
        field: 'outletId', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(
        field: 'cancelledBy', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(
        field: 'completedBy', legacyUid: legacyUid, currentUid: currentUid);
    await _replaceBookingsUidField(
        field: 'arrivalMarkedBy', legacyUid: legacyUid, currentUid: currentUid);

    await _replaceGenericUidField(
        collection: 'notifications',
        field: 'toUserId',
        legacyUid: legacyUid,
        currentUid: currentUid);
    await _replaceGenericUidField(
        collection: 'notifications',
        field: 'actorId',
        legacyUid: legacyUid,
        currentUid: currentUid);
    await _replaceGenericUidField(
        collection: 'admin_inbox',
        field: 'toUserId',
        legacyUid: legacyUid,
        currentUid: currentUid);

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

    await _migrateBookingProposalsAndChatSeen(
        legacyUid: legacyUid, currentUid: currentUid);
  }

  Future<void> _replaceBookingsUidField({
    required String field,
    required String legacyUid,
    required String currentUid,
  }) async {
    while (true) {
      final snap = await _firestore
          .collection('bookings')
          .where(field, isEqualTo: legacyUid)
          .limit(400)
          .get();
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
      final snap = await _firestore
          .collection(collection)
          .where(field, isEqualTo: legacyUid)
          .limit(400)
          .get();
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
      final snap = await _firestore
          .collectionGroup(collectionId)
          .where(field, isEqualTo: legacyUid)
          .limit(400)
          .get();
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
      Query<Map<String, dynamic>> query = _firestore
          .collection('bookings')
          .orderBy(FieldPath.documentId)
          .limit(400);
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

    final legacyDevices = await _firestore
        .collection('users')
        .doc(legacyUid)
        .collection('devices')
        .get();
    final legacyFcmTokens = await _firestore
        .collection('users')
        .doc(legacyUid)
        .collection('fcmTokens')
        .get();
    final targetDevicesRef =
        _firestore.collection('users').doc(currentUid).collection('devices');

    if (legacyDevices.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (final doc in legacyDevices.docs) {
        final token = (doc.data()['token'] ?? '').toString().trim();
        if (token.isNotEmpty) {
          batch.set(
              targetDevicesRef.doc(doc.id),
              {
                ...doc.data(),
                'token': token,
                'uid': currentUid,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true));
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

  Future<Map<String, dynamic>> previewBypassOtpForLoginOrRegistration({
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
      throw FirebaseAuthException(
          code: 'weak-password',
          message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }

    if (!isRegistration) {
      return loginWithPhonePasswordPreview(
          role: role, phoneNumber: normalizedPhone, password: trimmedPassword);
    }

    final existing = await _firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: normalizedPhone)
        .limit(10)
        .get()
        .timeout(const Duration(seconds: 8));

    Map<String, dynamic>? existingProfile;
    for (final doc in existing.docs) {
      final data = doc.data();
      if ((data['role'] ?? '').toString() == role) {
        existingProfile = data;
        break;
      }
    }
    if (existingProfile != null) {
      return existingProfile;
    }

    final generatedUid = 'preview_${DateTime.now().millisecondsSinceEpoch}';
    final profile = <String, dynamic>{
      'uid': generatedUid,
      'fullName': fullName.trim(),
      'role': role,
      'governorate': governorate.trim(),
      'phoneNumber': normalizedPhone,
      'passwordHash': _hashPassword(trimmedPassword),
      'isPreviewBypass': true,
    };

    if (role == 'outlet') {
      profile['outletName'] = (outletName ?? '').trim();
      profile['approvalStatus'] = 'pending';
    }

    final canWriteProtectedData = _auth.currentUser != null;
    if (!canWriteProtectedData) {
      debugPrint(
          '[AuthService] preview registration write skipped: unauthenticated');
      return profile;
    }

    try {
      await _firestore
          .collection('users')
          .doc(generatedUid)
          .set(profile, SetOptions(merge: true));
      final fresh =
          await _firestore.collection('users').doc(generatedUid).get();
      return fresh.data() ?? profile;
    } catch (error, stackTrace) {
      debugPrint('[AuthService] preview registration write skipped: $error');
      debugPrint('$stackTrace');
      return profile;
    }
  }

  Future<Map<String, dynamic>> _resolveProfileForLogin({
    required String role,
    required String normalizedPhone,
  }) async {
    debugPrint('PROFILE_RESOLVE_START');
    final currentUser = _auth.currentUser;
    final currentUid = currentUser?.uid ?? '';
    final currentPhone =
        IraqiPhoneUtils.normalize(currentUser?.phoneNumber ?? normalizedPhone);
    debugPrint('CURRENT_USER_UID: ${currentUid.isEmpty ? 'null' : currentUid}');
    debugPrint('CURRENT_USER_PHONE: $currentPhone');

    if (currentUid.isNotEmpty) {
      debugPrint('USER_DOC_BY_UID_START');
      try {
        final byUid = await _firestore
            .collection('users')
            .doc(currentUid)
            .get()
            .timeout(const Duration(seconds: 8));
        final data = byUid.data();
        if (byUid.exists && data != null && data.isNotEmpty) {
          debugPrint('USER_DOC_BY_UID_FOUND');
          return data;
        }
        debugPrint('USER_DOC_BY_UID_MISSING');
      } on TimeoutException catch (error) {
        debugPrint('PROFILE_RESOLVE_FAILED_CONTROLLED: $error');
        throw FirebaseAuthException(
            code: 'user-profile-load-failed',
            message: 'تعذر التحقق من الحساب، حاول مرة أخرى');
      } on FirebaseException catch (error) {
        debugPrint('PROFILE_RESOLVE_FAILED_CONTROLLED: $error');
        throw FirebaseAuthException(
            code: 'user-profile-load-failed',
            message: 'تعذر التحقق من الحساب، حاول مرة أخرى');
      } catch (error) {
        debugPrint('PROFILE_RESOLVE_FAILED_CONTROLLED: $error');
      }
    }

    debugPrint('USER_DOC_BY_PHONE_QUERY_START');
    try {
      final byPhone = await _findProfileByPhoneCandidates(
        normalizedPhone: normalizedPhone,
        role: role,
      );
      if (byPhone != null) {
        debugPrint('USER_DOC_BY_PHONE_QUERY_FOUND');
        return byPhone;
      }
      debugPrint('USER_DOC_BY_PHONE_QUERY_MISSING');
      throw FirebaseAuthException(
          code: 'missing-user-doc', message: 'هذا الرقم غير مسجل بعد.');
    } on FirebaseAuthException {
      rethrow;
    } on TimeoutException catch (error) {
      debugPrint('PROFILE_RESOLVE_FAILED_CONTROLLED: $error');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed',
          message: 'تعذر التحقق من الحساب، حاول مرة أخرى');
    } on FirebaseException catch (error) {
      debugPrint('PROFILE_RESOLVE_FAILED_CONTROLLED: $error');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed',
          message: 'تعذر التحقق من الحساب، حاول مرة أخرى');
    } catch (error) {
      debugPrint('PROFILE_RESOLVE_FAILED_CONTROLLED: $error');
      throw FirebaseAuthException(
          code: 'user-profile-load-failed',
          message: 'تعذر التحقق من الحساب، حاول مرة أخرى');
    }
  }

  Set<String> _phoneCandidates(String normalizedPhone) {
    final normalized = IraqiPhoneUtils.normalize(normalizedPhone);
    final digits = normalized.replaceAll(RegExp(r'\D'), '');
    final local = IraqiPhoneUtils.localPart(normalized);
    final withZero = local.startsWith('0') ? local : '0$local';
    final withCountryAndZero = '+964$withZero';
    final digitsWithZero = '964$withZero';
    return {
      normalized,
      digits,
      local,
      withZero,
      '+$digits',
      withCountryAndZero,
      digitsWithZero,
    }.where((e) => e.trim().isNotEmpty).toSet();
  }

  Future<Map<String, dynamic>?> _tryFindProfileByPhoneCandidatesFast({
    required String normalizedPhone,
    required String role,
  }) async {
    try {
      return await _findProfileByPhoneCandidates(
        normalizedPhone: normalizedPhone,
        role: role,
      ).timeout(const Duration(seconds: 6));
    } on TimeoutException catch (error) {
      debugPrint('[LOGIN LOOKUP] skipped after timeout: $error');
      return null;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[LOGIN LOOKUP] skipped due to firebase error: ${error.code}');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      return null;
    } catch (error, stackTrace) {
      debugPrint('[LOGIN LOOKUP] skipped due to error: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _findProfileByPhoneCandidates({
    required String normalizedPhone,
    required String role,
  }) async {
    final candidates =
        _phoneCandidates(normalizedPhone).toList(growable: false);
    const fields = ['phoneNumber', 'phone', 'normalizedPhone', 'mobile'];
    debugPrint(
        '[LOGIN LOOKUP] role=$role normalized=$normalizedPhone candidates=$candidates');

    for (final field in fields) {
      for (final value in candidates) {
        debugPrint('[LOGIN LOOKUP] query field=$field value=$value');
        final snap = await _firestore
            .collection('users')
            .where(field, isEqualTo: value)
            .limit(10)
            .get()
            .timeout(const Duration(seconds: 8));
        debugPrint(
            '[LOGIN LOOKUP] field=$field value=$value docs=${snap.docs.length}');
        if (snap.docs.isEmpty) continue;
        final docs = snap.docs.map((d) {
          final data = d.data();
          debugPrint(
            '[LOGIN LOOKUP] hit uid=${d.id} role=${(data['role'] ?? '').toString()} phoneNumber=${(data['phoneNumber'] ?? '').toString()}',
          );
          return data;
        }).toList(growable: false);
        final selected = docs.firstWhere(
          (d) => (d['role'] ?? '').toString() == role,
          orElse: () => docs.first,
        );
        if (selected.isNotEmpty) {
          debugPrint(
              '[LOGIN LOOKUP] selected uid=${(selected['uid'] ?? '').toString()} role=${(selected['role'] ?? '').toString()}');
          return selected;
        }
      }
    }
    return null;
  }
}
