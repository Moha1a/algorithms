import 'package:geolocator/geolocator.dart';

class DistanceUtils {
  const DistanceUtils._();

  static double? toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  static double? kmBetween({
    required Object? fromLat,
    required Object? fromLng,
    required Object? toLat,
    required Object? toLng,
  }) {
    final aLat = toDouble(fromLat);
    final aLng = toDouble(fromLng);
    final bLat = toDouble(toLat);
    final bLng = toDouble(toLng);
    if (!_valid(aLat, aLng) || !_valid(bLat, bLng)) return null;
    return Geolocator.distanceBetween(aLat!, aLng!, bLat!, bLng!) / 1000;
  }

  static bool _valid(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN || lat.isInfinite || lng.isInfinite) {
      return false;
    }
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  static String text(double? km) {
    if (km == null || km.isNaN || km.isInfinite || km < 0) {
      return 'المسافة غير متاحة';
    }
    final meters = km * 1000;
    if (meters < 1000) return '${meters.round()} متر';
    if (km < 10) return '${km.toStringAsFixed(1)} كم';
    return '${km.round()} كم';
  }

  static String level(double? km) {
    if (km == null || km.isNaN || km.isInfinite || km < 0) {
      return 'فعّل الموقع لرؤية البعد';
    }
    if (km <= 1) return 'قريب جداً';
    if (km <= 3) return 'قريب';
    if (km <= 8) return 'متوسط البعد';
    if (km <= 15) return 'بعيد';
    return 'بعيد جداً';
  }

  static String fullText(double? km) {
    if (km == null || km.isNaN || km.isInfinite || km < 0) {
      return 'المسافة غير متاحة';
    }
    return '${text(km)} (${level(km)})';
  }
}
