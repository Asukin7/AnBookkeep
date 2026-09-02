import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/money/money_formatter.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats aggregate minor units beyond the single-entry limit', () {
    expect(
      MoneyFormatter.formatMinorUnits(Money.maxMinorUnits * 2, prefix: '+'),
      '+1,999,999,999.98',
    );
  });

  group('Money', () {
    test('converts decimal values to integer minor units', () {
      final money = Money.fromDecimal(Decimal.parse('123.45'));

      expect(money.minorUnits, 12345);
      expect(money.toString(), '123.45');
    });

    test('uses half-up rounding to two decimal places', () {
      expect(Money.fromDecimal(Decimal.parse('12.345')).minorUnits, 1235);
      expect(Money.fromDecimal(Decimal.parse('12.344')).minorUnits, 1234);
    });

    test('allows a zero amount', () {
      expect(Money.zero.minorUnits, 0);
      expect(Money.zero.toString(), '0.00');
    });

    test('rejects negative and over-limit amounts', () {
      expect(
        () => Money.fromDecimal(Decimal.parse('-0.01')),
        throwsArgumentError,
      );
      expect(
        () => Money.fromDecimal(Decimal.parse('1000000000.00')),
        throwsArgumentError,
      );
    });

    test('restores a decimal value from integer minor units', () {
      expect(Money.fromMinorUnits(12345).value, Decimal.parse('123.45'));
      expect(Money.fromMinorUnits(Money.maxMinorUnits).value, Money.maxValue);
    });
  });
}
