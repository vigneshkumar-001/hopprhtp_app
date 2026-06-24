import 'package:flutter/services.dart';

/// Common formatting helpers (no `intl` dependency needed).
class Money {
  Money._();

  static const String naira = '₦'; // ₦

  /// 137428 -> "₦137,428"  (no decimals when whole).
  static String format(num value, {bool symbol = true}) {
    final isWhole = value == value.roundToDouble();
    final String str;
    if (isWhole) {
      str = _group(value.round().toString());
    } else {
      final cents =
          ((value - value.floor()) * 100).round().toString().padLeft(2, '0');
      str = '${_group(value.floor().toString())}.$cents';
    }
    return symbol ? '$naira$str' : str;
  }

  static String _group(String digits) {
    final neg = digits.startsWith('-');
    final s = neg ? digits.substring(1) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return (neg ? '-' : '') + buf.toString();
  }
}

/// Input formatter that groups the integer part with thousands separators
/// while the user types an amount.
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final parts = digits.split('.');
    final grouped =
        Money._group(parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), ''));
    final out = parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}
