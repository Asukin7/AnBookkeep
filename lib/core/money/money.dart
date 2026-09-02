import 'package:decimal/decimal.dart';

final class Money {
  Money._(this.value, this.minorUnits);

  static final Decimal maxValue = Decimal.parse('999999999.99');
  static const int maxMinorUnits = 99999999999;

  final Decimal value;
  final int minorUnits;

  factory Money.fromDecimal(Decimal amount) {
    if (amount < Decimal.zero) {
      throw ArgumentError.value(amount, 'amount', '金额不能小于0');
    }

    final rounded = amount.round(scale: 2);
    if (rounded > maxValue) {
      throw ArgumentError.value(amount, 'amount', '金额超出允许范围');
    }

    final minorUnits = (rounded * Decimal.fromInt(100)).toBigInt().toInt();
    return Money._(rounded, minorUnits);
  }

  factory Money.fromMinorUnits(int minorUnits) {
    if (minorUnits < 0 || minorUnits > maxMinorUnits) {
      throw ArgumentError.value(minorUnits, 'minorUnits', '金额分值超出允许范围');
    }

    final major = minorUnits ~/ 100;
    final fraction = (minorUnits % 100).toString().padLeft(2, '0');
    return Money._(Decimal.parse('$major.$fraction'), minorUnits);
  }

  static Money get zero => Money.fromMinorUnits(0);

  @override
  String toString() => value.toStringAsFixed(2);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money && minorUnits == other.minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;
}
