import 'package:flutter/services.dart';

class InputDigitUtils {
  const InputDigitUtils._();

  static String normalizeArabicDigits(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + rune - 0x06F0);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static String digitsOnly(String input) {
    final normalized = normalizeArabicDigits(input);
    final buffer = StringBuffer();
    for (final codeUnit in normalized.codeUnits) {
      if (codeUnit >= 48 && codeUnit <= 57) {
        buffer.writeCharCode(codeUnit);
      }
    }
    return buffer.toString();
  }

  static String normalizePhoneText(String input) {
    final normalized = normalizeArabicDigits(input);
    final buffer = StringBuffer();
    var plusWritten = false;
    for (var i = 0; i < normalized.length; i += 1) {
      final char = normalized[i];
      final codeUnit = normalized.codeUnitAt(i);
      if (codeUnit >= 48 && codeUnit <= 57) {
        buffer.writeCharCode(codeUnit);
      } else if (char == '+' && !plusWritten && buffer.length == 0) {
        buffer.write('+');
        plusWritten = true;
      }
    }
    return buffer.toString();
  }
}

class ArabicDigitsTextInputFormatter extends TextInputFormatter {
  const ArabicDigitsTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final next = InputDigitUtils.normalizeArabicDigits(newValue.text);
    final offset = newValue.selection.end.clamp(0, next.length).toInt();
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }
}

class PhoneNumberInputFormatter extends TextInputFormatter {
  const PhoneNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final next = InputDigitUtils.normalizePhoneText(newValue.text);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
      composing: TextRange.empty,
    );
  }
}

class DigitOnlyInputFormatter extends TextInputFormatter {
  const DigitOnlyInputFormatter({this.maxLength});

  final int? maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var next = InputDigitUtils.digitsOnly(newValue.text);
    final limit = maxLength;
    if (limit != null && next.length > limit) {
      next = next.substring(0, limit);
    }
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
      composing: TextRange.empty,
    );
  }
}
