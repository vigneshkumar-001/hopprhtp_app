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

/// Lightweight date formatting (no `intl` dependency).
class Dates {
  Dates._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "12 May 2025".
  static String medium(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  /// Notification-style relative label: "2:14 PM" today, "Yesterday",
  /// "3 days ago", else the full date.
  static String relative(DateTime d) {
    final l = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(l.year, l.month, l.day);
    final days = today.difference(that).inDays;
    if (days <= 0) return _time(l);
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    return medium(l);
  }

  static String _time(DateTime l) {
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
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
