import 'dart:async';
import 'dart:io';

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
    debugPrint('[LOCATION PERMISSION] ensure start');
    LocationPermission permission;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (error) {
      debugPrint('[LOCATION PERMISSION] check/request failed: $error');
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر الوصول لإذن الموقع حالياً. يمكنك المتابعة بدون موقع تلقائي.'),
        ),
      );
      return false;
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      debugPrint('[LOCATION PERMISSION] denied=$permission');
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم رفض إذن الموقع. يمكنك المتابعة وإدخال البيانات يدوياً.'),
        ),
      );
      return false;
    }

    if (_grantedInSession) return true;

    var enabled = false;
    try {
      enabled = await Geolocator.isLocationServiceEnabled();
    } catch (error) {
      debugPrint('[LOCATION PERMISSION] service check failed: $error');
    }

    if (!enabled) {
      try {
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 4),
          ),
        );
        enabled = true;
      } catch (_) {}
    }

    if (!enabled) {
      if (!context.mounted) return false;
      await _showSettingsDialog(
        context,
        title: 'خدمة الموقع متوقفة',
        message: 'خدمة الموقع غير متاحة حالياً. يمكنك المتابعة بدون تحديد موقع تلقائي.',
      );
      return false;
    }

    _grantedInSession = true;
    debugPrint('[LOCATION PERMISSION] granted');
    return true;
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
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw LocationFetchException('تم رفض صلاحية الموقع. فعّلها من إعدادات التطبيق إذا رغبت.');
    }

    bool enabled;
    try {
      enabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      enabled = false;
    }
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

      if (position.latitude.abs() < 0.00001 && position.longitude.abs() < 0.00001) {
        throw LocationFetchException('تم استلام إحداثيات غير صالحة.');
      }
      debugPrint('[LOCATION PERMISSION] getFreshCurrentPosition success');
      return position;
    } on TimeoutException {
      throw LocationFetchException('انتهت مهلة تحديد الموقع. حاول مرة أخرى.');
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (!kIsWeb && Platform.isIOS && (message.contains('simulator') || message.contains('kcle')) ) {
        throw LocationFetchException('الموقع غير متاح حالياً في المحاكي. يمكنك المتابعة بدون موقع تلقائي.');
      }
      if (error is LocationFetchException) rethrow;
      throw LocationFetchException('تعذر جلب موقعك حالياً. يمكنك المتابعة بدون موقع تلقائي.');
    }
  }

  Future<void> _showSettingsDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              await Geolocator.openLocationSettings();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }
}