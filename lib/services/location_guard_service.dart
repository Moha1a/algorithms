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
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (!context.mounted) return false;
      await _showSettingsDialog(
        context,
        title: 'إذن الموقع مطلوب',
        message: 'لا يمكنك إنشاء أو قبول الطلب بدون إذن الموقع. فعّل الإذن من إعدادات التطبيق.',
      );
      return false;
    }

    if (_grantedInSession) return true;

    var enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      try {
        await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 4));
        enabled = true;
      } catch (_) {}
    }
    if (!enabled) {
      if (!context.mounted) return false;
      await _showSettingsDialog(
        context,
        title: 'خدمة الموقع متوقفة',
        message: 'يرجى تشغيل خدمة الموقع من إعدادات الجهاز للمتابعة.',
      );
      enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return false;
    }

    _grantedInSession = true;
    return true;
  }


  Future<Position> getFreshCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    Duration timeLimit = const Duration(seconds: 12),
  }) async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw LocationFetchException('لا يوجد إذن موقع فعّال.');
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw LocationFetchException('خدمة الموقع غير مفعّلة.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: timeLimit,
      ),
    );

    if (position.latitude.abs() < 0.00001 && position.longitude.abs() < 0.00001) {
      throw LocationFetchException('تم استلام إحداثيات غير صالحة.');
    }

    return position;
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
            child: const Text('لاحقًا'),
          ),
          FilledButton(
            onPressed: () async {
              await Geolocator.openAppSettings();
              await Geolocator.openLocationSettings();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('الذهاب إلى الإعدادات'),
          ),
        ],
      ),
    );
  }
}