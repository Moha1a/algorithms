import 'package:flutter/services.dart';

import 'input_digit_utils.dart';

class MoneyUtils {
  static String normalizeDigitsOnly(String input) {
    return InputDigitUtils.digitsOnly(input);
  }

  static String formatDigitString(String digits) {
    if (digits.isEmpty) return '';
    final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < normalized.length; i += 1) {
      final remaining = normalized.length - i;
      buffer.write(normalized[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }

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

class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = MoneyUtils.normalizeDigitsOnly(newValue.text);
    if (digits.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final formatted = MoneyUtils.formatDigitString(digits);
    final rawSelectionEnd = newValue.selection.end;
    final safeSelectionEnd = rawSelectionEnd.clamp(0, newValue.text.length).toInt();
    final selectedText = rawSelectionEnd <= 0 ? '' : newValue.text.substring(0, safeSelectionEnd);
    final digitsBeforeCursor = MoneyUtils.normalizeDigitsOnly(selectedText).length;
    final cursorOffset = _offsetAfterDigits(formatted, digitsBeforeCursor);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorOffset),
      composing: TextRange.empty,
    );
  }

  int _offsetAfterDigits(String text, int digitCount) {
    if (digitCount <= 0) return 0;
    var seen = 0;
    for (var i = 0; i < text.length; i += 1) {
      final code = text.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        seen += 1;
        if (seen >= digitCount) return i + 1;
      }
    }
    return text.length;
  }
}
