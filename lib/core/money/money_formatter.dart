import 'package:anbookkeep/core/money/money.dart';

abstract final class MoneyFormatter {
  static String format(
    Money money, {
    required String prefix,
    bool useGrouping = true,
  }) => formatMinorUnits(
    money.minorUnits,
    prefix: prefix,
    useGrouping: useGrouping,
  );

  /// Formats stored or aggregated minor units without applying the single-entry
  /// upper bound enforced by [Money].
  static String formatMinorUnits(
    int minorUnits, {
    required String prefix,
    bool useGrouping = true,
  }) {
    final absoluteMinorUnits = minorUnits.abs();
    final major = absoluteMinorUnits ~/ 100;
    final fraction = (absoluteMinorUnits % 100).toString().padLeft(2, '0');
    final majorText = useGrouping ? _groupDigits(major.toString()) : '$major';
    return '$prefix$majorText.$fraction';
  }

  static String _groupDigits(String digits) {
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
