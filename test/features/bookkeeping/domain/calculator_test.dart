import 'package:anbookkeep/features/bookkeeping/domain/calculator.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalculatorEvaluator', () {
    test('uses multiplication and division precedence', () {
      expect(CalculatorEvaluator.evaluate('4÷2×3+1-0'), Decimal.parse('7'));
    });

    test('keeps decimal arithmetic exact', () {
      expect(CalculatorEvaluator.evaluate('0.1+0.2'), Decimal.parse('0.3'));
    });

    test('rejects division by zero', () {
      expect(
        () => CalculatorEvaluator.evaluate('1÷0'),
        throwsA(isA<CalculatorException>()),
      );
    });
  });

  group('CalculatorController', () {
    test('distinguishes no input from an entered zero', () {
      final controller = CalculatorController();

      expect(controller.state.hasInput, isFalse);
      controller.press('0');
      expect(controller.state.hasInput, isTrue);
      expect(controller.state.result, Decimal.zero);
      controller.press('AC');
      expect(controller.state.hasInput, isFalse);
    });

    test('appends digits to an existing edited amount', () {
      final controller = CalculatorController()
        ..setAmount(Decimal.parse('123'))
        ..press('4');

      expect(controller.state.expression, '1234');
      expect(controller.state.result, Decimal.parse('1234'));
    });

    test('shows entered decimals without adding trailing zeros', () {
      final controller = CalculatorController();

      expect(controller.state.displayAmount, '0');
      controller
        ..press('1')
        ..press('2');
      expect(controller.state.displayAmount, '12');
      controller.press('.');
      expect(controller.state.displayAmount, '12.');
      controller.press('3');
      expect(controller.state.displayAmount, '12.3');
      controller.press('+');
      expect(controller.state.displayAmount, '12.30');
      controller.press('4');
      expect(controller.state.displayAmount, '16.30');
    });

    test('replaces consecutive operators', () {
      final controller = CalculatorController()
        ..press('1')
        ..press('+')
        ..press('×')
        ..press('2');

      expect(controller.state.expression, '1×2');
      expect(controller.state.result, Decimal.parse('2'));
    });

    test('backspace recovers an error state when AC is hidden', () {
      final controller = CalculatorController()
        ..press('1')
        ..press('÷')
        ..press('0')
        ..press('=');

      expect(controller.state.isError, isTrue);
      controller.press('2');
      expect(controller.state.isError, isTrue);
      controller.press('←');
      expect(controller.state.isError, isFalse);
    });
  });
}
