class MoneyUtils {
  static String formatWhole(num value) {
    final rounded = value.round().abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < rounded.length; i += 1) {
      final remaining = rounded.length - i;
      buffer.write(rounded[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    final prefix = value < 0 ? '-' : '';
    return '$prefix$buffer';
  }

  static String formatIqD(num value) {
    return '${formatWhole(value)} د.ع';
  }

  static String iqdWithWords(num value) {
    final n = value.round();
    return '${formatIqD(n)} (${numberToArabicWords(n)} دينار عراقي)';
  }

  static String numberToArabicWords(int number) {
    if (number == 0) return 'صفر';
    if (number < 0) return 'ناقص ${numberToArabicWords(number.abs())}';

    final parts = <String>[];
    final millions = number ~/ 1000000;
    final thousands = (number % 1000000) ~/ 1000;
    final rest = number % 1000;

    if (millions > 0) {
      parts.add(_scaleText(millions, 'مليون', 'مليونان', 'ملايين'));
    }
    if (thousands > 0) {
      parts.add(_scaleText(thousands, 'ألف', 'ألفان', 'آلاف'));
    }
    if (rest > 0) {
      parts.add(_underThousand(rest));
    }

    return parts.join(' و ');
  }

  static String _scaleText(int value, String singular, String dual, String plural) {
    if (value == 1) return singular;
    if (value == 2) return dual;
    if (value >= 3 && value <= 10) return '${_underThousand(value)} $plural';
    return '${_underThousand(value)} $singular';
  }

  static String _underThousand(int n) {
    if (n < 100) return _underHundred(n);

    final hundreds = <String>[
      '',
      'مئة',
      'مئتان',
      'ثلاثمئة',
      'أربعمئة',
      'خمسمئة',
      'ستمئة',
      'سبعمئة',
      'ثمانمئة',
      'تسعمئة',
    ];

    final h = n ~/ 100;
    final r = n % 100;
    if (r == 0) return hundreds[h];
    return '${hundreds[h]} و ${_underHundred(r)}';
  }

  static String _underHundred(int n) {
    final units = <String>[
      '',
      'واحد',
      'اثنان',
      'ثلاثة',
      'أربعة',
      'خمسة',
      'ستة',
      'سبعة',
      'ثمانية',
      'تسعة',
    ];
    final teens = <String>[
      'عشرة',
      'أحد عشر',
      'اثنا عشر',
      'ثلاثة عشر',
      'أربعة عشر',
      'خمسة عشر',
      'ستة عشر',
      'سبعة عشر',
      'ثمانية عشر',
      'تسعة عشر',
    ];
    final tens = <String>[
      '',
      '',
      'عشرون',
      'ثلاثون',
      'أربعون',
      'خمسون',
      'ستون',
      'سبعون',
      'ثمانون',
      'تسعون',
    ];

    if (n < 10) return units[n];
    if (n < 20) return teens[n - 10];
    final t = n ~/ 10;
    final u = n % 10;
    if (u == 0) return tens[t];
    return '${units[u]} و ${tens[t]}';
  }
}
