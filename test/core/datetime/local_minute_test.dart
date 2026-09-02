import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips a valid local minute', () {
    final value = LocalMinute.fromDateTime(DateTime(2026, 8, 28, 9, 7, 59));

    expect(value.value, '2026-08-28 09:07');
    expect(LocalMinute.parse(value.value), value);
    expect(value.yearMonth, '2026-08');
  });

  test('rejects impossible dates', () {
    expect(() => LocalMinute.parse('2026-02-30 10:00'), throwsFormatException);
  });
}
