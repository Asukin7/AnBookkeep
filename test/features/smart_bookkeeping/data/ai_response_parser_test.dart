import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/data/ai_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = AiResponseParser();
  const categoryTypes = {
    'expense-food': EntryType.expense,
    'income-salary': EntryType.income,
  };

  test('parses a fenced response and validates all fields', () {
    final result = parser.parse(r'''结果如下：```json
{"type":"expense","amount":"-28.50","category_id":"expense-food","note":"安安咖啡\n消费","occurred_at":"2026-08-31T18:30:10","confidence":1.4}
```''', categoryTypes: categoryTypes);

    expect(result.type, EntryType.expense);
    expect(result.amount?.minorUnits, 2850);
    expect(result.categoryId, 'expense-food');
    expect(result.note, '安安咖啡 消费');
    expect(result.occurredAt?.value, '2026-08-31 18:30');
    expect(result.confidence, 1);
  });

  test('rejects a category belonging to another transaction type', () {
    final result = parser.parse(
      '{"type":"income","amount":"10","category_id":"expense-food"}',
      categoryTypes: categoryTypes,
    );

    expect(result.type, EntryType.income);
    expect(result.categoryId, isNull);
  });

  test('drops an amount above the application limit', () {
    final result = parser.parse(
      '{"type":"expense","amount":"1000000000.00"}',
      categoryTypes: categoryTypes,
    );

    expect(result.amount, isNull);
  });

  test('rejects a response without a complete JSON object', () {
    expect(
      () => parser.parse('{"type":"expense"', categoryTypes: categoryTypes),
      throwsFormatException,
    );
  });
}
