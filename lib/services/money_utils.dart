class MoneyUtils {
  static String formatIqD(num value) {
    final s = value.toStringAsFixed(0);
    return '$s د.ع';
  }

  static String iqdWithWords(num value) {
    final n = value.round();
    return '${formatIqD(n)} (${numberToArabicWords(n)} دينار عراقي)';
  }

  static String numberToArabicWords(int number) {
    if (number == 0) return 'صفر';
    final units = [
      '',
      'واحد',
      'اثنان',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة'
    ];
    final tens = [
      '',
      'عشرة',
      'عشرون',
      'ثلاثون',
      'أربعون',
      'خمسون',
      'ستون',
      'سبعون',
      'ثمانون',
      'تسعون'
    ];

    String underHundred(int n) {
      if (n < 10) return units[n];
      if (n < 20) {
        switch (n) {
          case 10:
            return 'عشرة';
          case 11:
            return 'أحد عشر';
          case 12:
            return 'اثنا عشر';
          default:
            return '${units[n - 10]} عشر';
        }
      }
      final t = n ~/ 10;
      final u = n % 10;
      if (u == 0) return tens[t];
      return '${units[u]} و ${tens[t]}';
    }

    String underThousand(int n) {
      if (n < 100) return underHundred(n);
      final h = n ~/ 100;
      final r = n % 100;
      final hundreds = [
        '',
        'مئة',
        'مئتان',
        'ثلاثمئة',
        'أربعمئة',
        'خمسمئة',
        'ستمئة',
        'سبعمئة',
        'ثمانمئة',
        'تسعمئة'
      ];
      if (r == 0) return hundreds[h];
      return '${hundreds[h]} و ${underHundred(r)}';
    }

    final millions = number ~/ 1000000;
    final thousands = (number % 1000000) ~/ 1000;
    final rest = number % 1000;
    final parts = <String>[];

    if (millions > 0) parts.add('${underThousand(millions)} مليون');
    if (thousands > 0) parts.add('${underThousand(thousands)} ألف');
    if (rest > 0) parts.add(underThousand(rest));

    return parts.join(' و ');
  }
}
