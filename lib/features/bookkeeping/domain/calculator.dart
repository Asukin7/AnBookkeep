import 'package:decimal/decimal.dart';

final class CalculatorState {
  const CalculatorState({
    this.expression = '',
    this.result,
    this.hasInput = false,
    this.isError = false,
    this.isCommitted = false,
  });

  final String expression;
  final Decimal? result;
  final bool hasInput;
  final bool isError;
  final bool isCommitted;

  String get equation {
    if (isError) return '错误';
    if (isCommitted && result != null) {
      return '$expression=${result!.toStringAsFixed(2)}';
    }
    return expression;
  }
}

final class CalculatorController {
  CalculatorState state = const CalculatorState();

  void setAmount(Decimal amount) {
    var expression = amount.toStringAsFixed(2);
    expression = expression
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    if (expression.isEmpty) expression = '0';
    state = CalculatorState(
      expression: expression,
      result: amount,
      hasInput: true,
    );
  }

  void press(String key) {
    if (key == 'AC') {
      state = const CalculatorState();
      return;
    }
    if (state.isError) {
      // AC is intentionally not exposed in the UI; backspace is the recovery
      // action after an invalid expression such as division by zero.
      if (key == '←') state = const CalculatorState();
      return;
    }

    switch (key) {
      case '←':
        _backspace();
      case '=':
        _commit();
      case '+':
      case '-':
      case '×':
      case '÷':
        _appendOperator(key);
      case '.':
        _appendDecimalPoint();
      default:
        if (RegExp(r'^\d$').hasMatch(key)) {
          _appendDigit(key);
        }
    }
  }

  void _appendDigit(String digit) {
    var expression = state.isCommitted ? '' : state.expression;
    final currentNumber = _currentNumber(expression);
    if (currentNumber == '0') {
      expression = '${expression.substring(0, expression.length - 1)}$digit';
    } else {
      expression += digit;
    }
    _update(expression, hasInput: true);
  }

  void _appendDecimalPoint() {
    var expression = state.isCommitted ? '' : state.expression;
    final currentNumber = _currentNumber(expression);
    if (currentNumber.contains('.')) return;
    expression += currentNumber.isEmpty ? '0.' : '.';
    _update(expression, hasInput: true);
  }

  void _appendOperator(String operator) {
    if (!state.hasInput || state.expression.isEmpty) return;

    if (state.isCommitted && state.result != null) {
      _update('${state.result}$operator', hasInput: true);
      return;
    }

    var expression = state.expression;
    if (expression.endsWith('.')) {
      expression = expression.substring(0, expression.length - 1);
    }
    if (_isOperator(expression[expression.length - 1])) {
      expression = expression.substring(0, expression.length - 1);
    }
    _update('$expression$operator', hasInput: true);
  }

  void _backspace() {
    if (state.isCommitted || state.expression.isEmpty) {
      state = const CalculatorState();
      return;
    }

    final expression = state.expression.substring(
      0,
      state.expression.length - 1,
    );
    _update(expression, hasInput: RegExp(r'\d').hasMatch(expression));
  }

  void _commit() {
    if (!state.hasInput || !_isComplete(state.expression)) return;
    try {
      final result = CalculatorEvaluator.evaluate(state.expression);
      state = CalculatorState(
        expression: state.expression,
        result: result,
        hasInput: true,
        isCommitted: true,
      );
    } on CalculatorException {
      state = CalculatorState(
        expression: state.expression,
        hasInput: state.hasInput,
        isError: true,
      );
    }
  }

  void _update(String expression, {required bool hasInput}) {
    Decimal? result;
    if (_isComplete(expression)) {
      try {
        result = CalculatorEvaluator.evaluate(expression);
      } on CalculatorException {
        state = CalculatorState(
          expression: expression,
          hasInput: hasInput,
          isError: true,
        );
        return;
      }
    }
    state = CalculatorState(
      expression: expression,
      result: result,
      hasInput: hasInput,
    );
  }

  static String _currentNumber(String expression) {
    final lastOperator = expression.lastIndexOf(RegExp(r'[+\-×÷]'));
    return expression.substring(lastOperator + 1);
  }

  static bool _isComplete(String expression) =>
      expression.isNotEmpty &&
      !_isOperator(expression[expression.length - 1]) &&
      !expression.endsWith('.');

  static bool _isOperator(String character) =>
      character == '+' ||
      character == '-' ||
      character == '×' ||
      character == '÷';
}

abstract final class CalculatorEvaluator {
  static Decimal evaluate(String expression) {
    try {
      return _Parser(expression).parse();
    } on CalculatorException {
      rethrow;
    } catch (_) {
      throw const CalculatorException('表达式无效');
    }
  }
}

final class _Parser {
  _Parser(this.source);

  final String source;
  int index = 0;

  Decimal parse() {
    if (source.isEmpty) throw const CalculatorException('表达式为空');
    final value = _parseExpression();
    if (index != source.length) {
      throw const CalculatorException('表达式包含无效字符');
    }
    return value;
  }

  Decimal _parseExpression() {
    var value = _parseTerm();
    while (index < source.length &&
        (source[index] == '+' || source[index] == '-')) {
      final operator = source[index++];
      final right = _parseTerm();
      value = operator == '+' ? value + right : value - right;
    }
    return value;
  }

  Decimal _parseTerm() {
    var value = _parseNumber();
    while (index < source.length &&
        (source[index] == '×' || source[index] == '÷')) {
      final operator = source[index++];
      final right = _parseNumber();
      if (operator == '×') {
        value *= right;
      } else {
        if (right == Decimal.zero) {
          throw const CalculatorException('不能除以0');
        }
        value = (value / right).toDecimal(scaleOnInfinitePrecision: 12);
      }
    }
    return value;
  }

  Decimal _parseNumber() {
    final start = index;
    var hasDecimalPoint = false;
    while (index < source.length) {
      final character = source[index];
      if (character == '.') {
        if (hasDecimalPoint) break;
        hasDecimalPoint = true;
        index++;
      } else if (RegExp(r'\d').hasMatch(character)) {
        index++;
      } else {
        break;
      }
    }
    if (start == index) throw const CalculatorException('缺少数字');
    final number = source.substring(start, index);
    return Decimal.tryParse(number) ??
        (throw const CalculatorException('数字无效'));
  }
}

final class CalculatorException implements Exception {
  const CalculatorException(this.message);

  final String message;

  @override
  String toString() => message;
}
