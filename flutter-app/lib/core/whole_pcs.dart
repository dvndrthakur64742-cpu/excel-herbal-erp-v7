import 'package:flutter/services.dart';

abstract final class WholePcs {
  static final TextInputFormatter positiveFormatter =
      FilteringTextInputFormatter.digitsOnly;

  static final TextInputFormatter signedFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'));

  static int parse(String raw, {bool allowZero = false, bool signed = false}) {
    final value = raw.trim();
    final pattern = signed ? RegExp(r'^-?\d+$') : RegExp(r'^\d+$');
    if (!pattern.hasMatch(value)) {
      throw const FormatException('Quantity whole PCS mein enter karein.');
    }
    final number = int.parse(value);
    if (!signed && number < 0) {
      throw const FormatException('Valid whole PCS quantity required hai.');
    }
    if (!allowZero && number == 0) {
      throw const FormatException('Valid whole PCS quantity required hai.');
    }
    return number;
  }

  static int parseOrZero(String raw, {bool signed = false}) {
    final value = raw.trim();
    if (value.isEmpty) return 0;
    final pattern = signed ? RegExp(r'^-?\d+$') : RegExp(r'^\d+$');
    if (!pattern.hasMatch(value)) {
      throw const FormatException('Quantity whole PCS mein enter karein.');
    }
    return int.parse(value);
  }

  // WordPress / MariaDB DECIMAL columns arrive as strings (for example,
  // "0.0000" or "3.00"). Normalize those at the API boundary before filling
  // integer-only TextFields. Never relax user-entered whole-PCS validation.
  static String apiQuantityText(dynamic value) {
    if (value == null) return '0';
    final raw = '$value'.trim();
    if (raw.isEmpty) return '0';
    final parsed = num.tryParse(raw);
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < 0 ||
        parsed > 9007199254740991 ||
        parsed != parsed.truncateToDouble()) {
      throw const FormatException(
        'Server quantity must be a non-negative whole PCS value.',
      );
    }
    return parsed.toInt().toString();
  }

  static bool isWhole(dynamic value) {
    final n = num.tryParse('$value');
    return n != null && n.isFinite && n == n.roundToDouble();
  }
}
