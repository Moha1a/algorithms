class BusinessHoursService {
  static const List<String> dayKeys = [
    'sat',
    'sun',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
  ];

  static const Map<String, String> dayLabels = {
    'sat': 'السبت',
    'sun': 'الأحد',
    'mon': 'الاثنين',
    'tue': 'الثلاثاء',
    'wed': 'الأربعاء',
    'thu': 'الخميس',
    'fri': 'الجمعة',
  };

  static bool hasConfiguredHours(Map<String, dynamic> profile) {
    final raw = profile['businessHours'];
    if (raw is! Map) return false;
    for (final key in dayKeys) {
      final day = raw[key];
      if (day is! Map || day['closed'] == true) continue;
      final periods = day['periods'];
      if (periods is List && periods.any(_validPeriod)) return true;
    }
    return false;
  }

  static bool isOpenNow(Map<String, dynamic> profile, {DateTime? now}) {
    final raw = profile['businessHours'];
    if (raw is! Map) return true;
    final current = now ?? DateTime.now();
    final key = _keyForDate(current);
    final day = raw[key];
    if (day is! Map || day['closed'] == true) return false;
    final periods = day['periods'];
    if (periods is! List) return false;
    final minute = current.hour * 60 + current.minute;
    for (final period in periods) {
      if (!_validPeriod(period)) continue;
      final open = _minutes((period as Map)['open']);
      final close = _minutes(period['close']);
      if (open == null || close == null) continue;
      if (open <= close) {
        if (minute >= open && minute <= close) return true;
      } else {
        if (minute >= open || minute <= close) return true;
      }
    }
    return false;
  }

  static String statusText(Map<String, dynamic> profile) {
    if (isOpenNow(profile)) return 'المنفذ مفتوح حالياً';
    return 'المنفذ مغلق حالياً';
  }

  static String todayScheduleText(Map<String, dynamic> profile,
      {DateTime? now}) {
    final raw = profile['businessHours'];
    if (raw is! Map) return 'وقت العمل غير محدد';
    final current = now ?? DateTime.now();
    final key = _keyForDate(current);
    final day = raw[key];
    if (day is! Map || day['closed'] == true) return 'مغلق اليوم';
    final periods = day['periods'];
    if (periods is! List) return 'وقت العمل غير محدد';
    final parts = <String>[];
    for (final period in periods) {
      if (!_validPeriod(period)) continue;
      final open = _formatTime((period as Map)['open']);
      final close = _formatTime(period['close']);
      if (open == null || close == null) continue;
      parts.add('$open - $close');
    }
    if (parts.isEmpty) return 'وقت العمل غير محدد';
    return parts.join('  |  ');
  }

  static String _keyForDate(DateTime date) {
    switch (date.weekday) {
      case DateTime.saturday:
        return 'sat';
      case DateTime.sunday:
        return 'sun';
      case DateTime.monday:
        return 'mon';
      case DateTime.tuesday:
        return 'tue';
      case DateTime.wednesday:
        return 'wed';
      case DateTime.thursday:
        return 'thu';
      case DateTime.friday:
      default:
        return 'fri';
    }
  }

  static bool _validPeriod(Object? raw) {
    if (raw is! Map) return false;
    final open = _minutes(raw['open']);
    final close = _minutes(raw['close']);
    return open != null && close != null && open != close;
  }

  static int? _minutes(Object? raw) {
    final value = raw?.toString() ?? '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static String? _formatTime(Object? raw) {
    final minutes = _minutes(raw);
    if (minutes == null) return null;
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour24 < 12 ? 'ص' : 'م';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }
}
