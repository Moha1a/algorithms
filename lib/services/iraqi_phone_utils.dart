import 'input_digit_utils.dart';

class IraqiPhoneUtils {
  static const String countryCode = '+964';

  static String normalize(String rawInput) {
    final raw = InputDigitUtils.normalizeArabicDigits(rawInput.trim());
    final digits = InputDigitUtils.digitsOnly(raw);
    String local = digits;

    if (raw.startsWith('+964')) {
      local = InputDigitUtils.digitsOnly(raw.substring(4));
    } else if (digits.startsWith('964')) {
      local = digits.substring(3);
    }

    if (local.startsWith('0')) {
      local = local.substring(1);
    }

    return '$countryCode$local';
  }

  static String? validate(String rawInput) {
    final normalized = normalize(rawInput);
    if (!RegExp(r'^\+9647\d{9}$').hasMatch(normalized)) {
      return 'الرقم العراقي غير صحيح. أدخل الرقم بصيغة 07xxxxxxxxx أو 7xxxxxxxxx';
    }
    return null;
  }

  static String localPart(String normalizedPhone) {
    if (normalizedPhone.startsWith('+964')) {
      return normalizedPhone.substring(4);
    }
    return normalizedPhone;
  }
}
