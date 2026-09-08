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

  static bool isWhole(dynamic value) {
    final n = num.tryParse('$value');
    return n != null && n.isFinite && n == n.roundToDouble();
  }
}
