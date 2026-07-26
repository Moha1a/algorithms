import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationFetchException implements Exception {
  LocationFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocationGuardService {
  LocationGuardService._();
  static final LocationGuardService instance = LocationGuardService._();
  bool _grantedInSession = false;

  Future<bool> ensureLocationEnabled(BuildContext context) async {
    final position = await requireCurrentLocation(
      context,
      title: 'مشاركة الموقع مطلوبة',
      message: 'نحتاج موقعك الحالي حتى نحسب المسافة بدقة ونحسن تجربة الطلبات.',
      crashlyticsKey: 'location_required_general',
      accuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 6),
    );
    return position != null;
  }

  Future<Position?> requireCurrentLocation(
    BuildContext context, {
    required String title,
    required String message,
    required String crashlyticsKey,
    LocationAccuracy accuracy = LocationAccuracy.best,
    Duration timeLimit = const Duration(seconds: 12),
  }) async {
    debugPrint('[LOCATION PERMISSION] require start key=$crashlyticsKey');
    FirebaseCrashlytics.instance.log(crashlyticsKey);
    FirebaseCrashlytics.instance.setCustomKey('location_permission_context', crashlyticsKey);

    try {
      final serviceEnabled = await _isServiceEnabled();
      if (!serviceEnabled) {
        FirebaseCrashlytics.instance.setCustomKey('location_permission_status', 'service_disabled');
        if (context.mounted) {
          await _showLocationDialog(
            context,
            title: title,
            message: '$message\n\nخدمة الموقع غير مفعّلة على الجهاز. فعّل خدمة الموقع ثم حاول مرة أخرى.',
            primaryLabel: 'فتح إعدادات الموقع',
            onPrimaryPressed: Geolocator.openLocationSettings,
          );
        }
        return null;
      }

      var permission = await _checkPermission();
      FirebaseCrashlytics.instance.setCustomKey('location_permission_status', permission.name);

      if (permission == LocationPermission.denied) {
        if (context.mounted) {
          final shouldRequest = await _showLocationDialog(
            context,
            title: title,
            message: message,
            primaryLabel: 'السماح بالموقع',
            onPrimaryPressed: () async {},
          );
          if (shouldRequest != true) return null;
        }
        permission = await Geolocator.requestPermission();
        FirebaseCrashlytics.instance.setCustomKey('location_permission_status', permission.name);
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever || permission == LocationPermission.unableToDetermine) {
        if (context.mounted) {
          await _showLocationDialog(
            context,
            title: title,
            message: '$message\n\nافتح الإعدادات وفعّل الوصول إلى الموقع لهذا التطبيق.',
            primaryLabel: 'الذهاب إلى الإعدادات',
            onPrimaryPressed: Geolocator.openAppSettings,
          );
        }
        return null;
      }

      final position = await getFreshCurrentPosition(accuracy: accuracy, timeLimit: timeLimit);
      if (!_isValidCoordinate(position.latitude, position.longitude)) {
        FirebaseCrashlytics.instance.setCustomKey('location_permission_status', 'invalid_coordinates');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر تحديد موقع صالح حالياً. حاول مرة أخرى.')),
          );
        }
        return null;
      }

      _grantedInSession = true;
      FirebaseCrashlytics.instance.setCustomKey('location_permission_status', 'granted');
      debugPrint('[LOCATION PERMISSION] require success key=$crashlyticsKey lat=${position.latitude} lng=${position.longitude}');
      return position;
    } catch (error, stackTrace) {
      debugPrint('[LOCATION PERMISSION] require failed key=$crashlyticsKey error=$error');
      debugPrint('$stackTrace');
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is LocationFetchException ? error.message : 'تعذر الوصول إلى الموقع حالياً. حاول مرة أخرى.')),
        );
      }
      return null;
    }
  }

  Future<Position> getFreshCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.best,
    Duration timeLimit = const Duration(seconds: 12),
  }) async {
    debugPrint('[LOCATION PERMISSION] getFreshCurrentPosition start');
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
    } catch (_) {
      throw LocationFetchException('تعذر الوصول إلى صلاحية الموقع على هذا الجهاز حالياً.');
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever || permission == LocationPermission.unableToDetermine) {
      throw LocationFetchException('تم رفض صلاحية الموقع. فعّلها من إعدادات التطبيق ثم حاول مرة أخرى.');
    }

    final enabled = await _isServiceEnabled();
    if (!enabled) {
      throw LocationFetchException('خدمة الموقع غير مفعّلة حالياً.');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeLimit,
        ),
      ).timeout(timeLimit + const Duration(seconds: 2));

      if (!_isValidCoordinate(position.latitude, position.longitude)) {
        throw LocationFetchException('تم استلام إحداثيات غير صالحة.');
      }
      debugPrint('[LOCATION PERMISSION] getFreshCurrentPosition success');
      return position;
    } on TimeoutException {
      throw LocationFetchException('انتهت مهلة تحديد الموقع. حاول مرة أخرى.');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (!kIsWeb && Platform.isIOS && (message.contains('simulator') || message.contains('kcle'))) {
        throw LocationFetchException('الموقع غير متاح حالياً في المحاكي. جرّب على جهاز حقيقي.');
      }
      if (error is LocationFetchException) rethrow;
      throw LocationFetchException('تعذر جلب موقعك حالياً. حاول مرة أخرى.');
    }
  }

  Future<LocationPermission> _checkPermission() async {
    try {
      return await Geolocator.checkPermission();
    } catch (error) {
      debugPrint('[LOCATION PERMISSION] check failed: $error');
      return LocationPermission.unableToDetermine;
    }
  }

  Future<bool> _isServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (error) {
      debugPrint('[LOCATION PERMISSION] service check failed: $error');
      return false;
    }
  }

  bool _isValidCoordinate(double lat, double lng) {
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    if (lat.abs() < 0.00001 && lng.abs() < 0.00001) return false;
    return true;
  }

  Future<bool?> _showLocationDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String primaryLabel,
    required Future<void> Function() onPrimaryPressed,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              await onPrimaryPressed();
              if (ctx.mounted) Navigator.of(ctx).pop(true);
            },
            child: Text(primaryLabel),
          ),
        ],
      ),
    );
  }
}