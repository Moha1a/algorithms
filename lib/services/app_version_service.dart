import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'input_digit_utils.dart';

enum AppPlatformKind { ios, android, other }

class AppVersionStatus {
  const AppVersionStatus({
    required this.updateRequired,
    required this.platform,
    required this.packageName,
    required this.currentVersion,
    required this.currentBuild,
    required this.requiredVersion,
    required this.requiredBuild,
    required this.title,
    required this.message,
    required this.storeUrl,
    this.policyLoaded = false,
  });

  final bool updateRequired;
  final AppPlatformKind platform;
  final String packageName;
  final String currentVersion;
  final int currentBuild;
  final String requiredVersion;
  final int requiredBuild;
  final String title;
  final String message;
  final String storeUrl;
  final bool policyLoaded;

  String get platformKey {
    switch (platform) {
      case AppPlatformKind.ios:
        return 'ios';
      case AppPlatformKind.android:
        return 'android';
      case AppPlatformKind.other:
        return 'other';
    }
  }

  String get currentLabel => '$currentVersion+$currentBuild';

  String get requiredLabel {
    final version = requiredVersion.trim().isEmpty ? 'غير محدد' : requiredVersion.trim();
    final build = requiredBuild > 0 ? '+$requiredBuild' : '';
    return '$version$build';
  }

  Uri get fallbackStoreUri {
    if (platform == AppPlatformKind.android && packageName.trim().isNotEmpty) {
      return Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
    }
    return Uri.parse('https://apps.apple.com/search?term=%D9%85%D9%86%D9%81%D8%B0%D9%83&entity=software');
  }

  Uri get effectiveStoreUri {
    final raw = storeUrl.trim();
    if (raw.isEmpty) return fallbackStoreUri;
    return Uri.tryParse(raw) ?? fallbackStoreUri;
  }
}

class AppVersionService {
  AppVersionService._();

  static final AppVersionService instance = AppVersionService._();
  static const policyPath = 'appConfig/versionPolicy';

  Future<AppVersionStatus> checkVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final platform = _currentPlatform();
    final currentVersion = packageInfo.version.trim();
    final currentBuild = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
    final packageName = packageInfo.packageName.trim();

    try {
      final doc = await FirebaseFirestore.instance
          .doc(policyPath)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      final data = doc.data() ?? <String, dynamic>{};
      if (!doc.exists || data.isEmpty) {
        _logStatus(
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          platform: platform,
          updateRequired: false,
          policyLoaded: false,
        );
        return _allowed(
          platform: platform,
          packageName: packageName,
          currentVersion: currentVersion,
          currentBuild: currentBuild,
          policyLoaded: false,
        );
      }

      final enabled = data['enabled'] != false;
      final key = _platformKey(platform);
      final requiredVersion = _normalizeVersionText(
        _stringValue(data['${key}MinVersion'] ?? data['minVersion']),
      );
      final requiredBuild = _intValue(data['${key}MinBuild'] ?? data['minBuild']);
      final storeUrl = _stringValue(data['${key}StoreUrl'] ?? data['storeUrl']);
      final title = _stringValue(data['title']).isEmpty ? 'تحديث ضروري للتطبيق' : _stringValue(data['title']);
      final message = _stringValue(data['message']).isEmpty
          ? 'حتى تستمر باستخدام منفذك بأمان، يرجى تحديث التطبيق إلى آخر نسخة متوفرة.'
          : _stringValue(data['message']);
      final updateRequired = enabled &&
          _isOlderThanRequired(
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            requiredVersion: requiredVersion,
            requiredBuild: requiredBuild,
          );

      _logStatus(
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        platform: platform,
        requiredVersion: requiredVersion,
        requiredBuild: requiredBuild,
        updateRequired: updateRequired,
        policyLoaded: true,
      );

      return AppVersionStatus(
        updateRequired: updateRequired,
        platform: platform,
        packageName: packageName,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        requiredVersion: requiredVersion,
        requiredBuild: requiredBuild,
        title: title,
        message: message,
        storeUrl: storeUrl,
        policyLoaded: true,
      );
    } catch (error, stackTrace) {
      debugPrint('[VersionPolicy] check failed: $error');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      return _allowed(
        platform: platform,
        packageName: packageName,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        policyLoaded: false,
      );
    }
  }

  AppVersionStatus _allowed({
    required AppPlatformKind platform,
    required String packageName,
    required String currentVersion,
    required int currentBuild,
    required bool policyLoaded,
  }) {
    return AppVersionStatus(
      updateRequired: false,
      platform: platform,
      packageName: packageName,
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      requiredVersion: '',
      requiredBuild: 0,
      title: 'تحديث ضروري للتطبيق',
      message: 'حتى تستمر باستخدام منفذك بأمان، يرجى تحديث التطبيق إلى آخر نسخة متوفرة.',
      storeUrl: '',
      policyLoaded: policyLoaded,
    );
  }

  bool _isOlderThanRequired({
    required String currentVersion,
    required int currentBuild,
    required String requiredVersion,
    required int requiredBuild,
  }) {
    final versionRequirement = requiredVersion.trim();
    if (versionRequirement.isNotEmpty) {
      final versionCompare = _compareVersions(currentVersion, versionRequirement);
      if (versionCompare < 0) return true;
      if (versionCompare > 0) return false;
    }
    if (requiredBuild > 0 && currentBuild > 0) {
      return currentBuild < requiredBuild;
    }
    return false;
  }

  int _compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength = leftParts.length > rightParts.length ? leftParts.length : rightParts.length;
    for (var i = 0; i < maxLength; i += 1) {
      final l = i < leftParts.length ? leftParts[i] : 0;
      final r = i < rightParts.length ? rightParts[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  List<int> _versionParts(String version) {
    return _normalizeVersionText(version)
        .split('+')
        .first
        .split('-')
        .first
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList(growable: false);
  }

  AppPlatformKind _currentPlatform() {
    if (kIsWeb) return AppPlatformKind.other;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AppPlatformKind.ios;
      case TargetPlatform.android:
        return AppPlatformKind.android;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return AppPlatformKind.other;
    }
  }

  String _platformKey(AppPlatformKind platform) {
    switch (platform) {
      case AppPlatformKind.ios:
        return 'ios';
      case AppPlatformKind.android:
        return 'android';
      case AppPlatformKind.other:
        return 'other';
    }
  }

  String _stringValue(Object? value) => value?.toString().trim() ?? '';

  String _normalizeVersionText(String value) {
    return InputDigitUtils.normalizeArabicDigits(value)
        .trim()
        .replaceAll('،', '.')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s+'), '');
  }

  int _intValue(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(InputDigitUtils.digitsOnly(value?.toString() ?? '')) ?? 0;
  }

  void _logStatus({
    required String currentVersion,
    required int currentBuild,
    required AppPlatformKind platform,
    required bool updateRequired,
    required bool policyLoaded,
    String requiredVersion = '',
    int requiredBuild = 0,
  }) {
    final crashlytics = FirebaseCrashlytics.instance;
    crashlytics.setCustomKey('app_version_current', currentVersion);
    crashlytics.setCustomKey('app_build_current', currentBuild);
    crashlytics.setCustomKey('app_platform', _platformKey(platform));
    crashlytics.setCustomKey('app_version_policy_loaded', policyLoaded);
    crashlytics.setCustomKey('app_version_update_required', updateRequired);
    if (requiredVersion.trim().isNotEmpty) {
      crashlytics.setCustomKey('app_version_min_required', requiredVersion);
    }
    if (requiredBuild > 0) {
      crashlytics.setCustomKey('app_build_min_required', requiredBuild);
    }
    debugPrint(
      '[VersionPolicy] platform=${_platformKey(platform)} current=$currentVersion+$currentBuild '
      'required=$requiredVersion+$requiredBuild loaded=$policyLoaded updateRequired=$updateRequired',
    );
  }
}
