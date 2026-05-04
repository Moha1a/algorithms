class IraqiPhoneUtils {
  static const String countryCode = '+964';

  static String normalize(String rawInput) {
    final digits = rawInput.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('964') && digits.length == 12) {
      return '+$digits';
    }

    if (digits.startsWith('0') && digits.length == 11) {
      return '$countryCode${digits.substring(1)}';
    }

    if (digits.startsWith('7') && digits.length == 10) {
      return '$countryCode$digits';
    }

    return '$countryCode$digits';
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
