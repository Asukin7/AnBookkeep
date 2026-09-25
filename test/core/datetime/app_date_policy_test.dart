import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the product picker range when ledger is empty', () {
    final bounds = AppDatePolicy.pickerBounds(now: DateTime(2026, 9, 8));

    expect(bounds.minYear, 2020);
    expect(bounds.maxYear, 2026);
  });

  test('expands picker range around persisted data and active value', () {
    final bounds = AppDatePolicy.pickerBounds(
      dataMinimumYear: 1998,
      dataMaximumYear: 2030,
      anchorYears: const [1997, 2031],
      now: DateTime(2026, 9, 8),
    );

    expect(bounds.minYear, 1997);
    expect(bounds.maxYear, 2031);
  });

  test('rejects years that cannot use the four-digit storage format', () {
    expect(() => AppDatePolicy.validateYear(0), throwsArgumentError);
    expect(() => AppDatePolicy.validateYear(10000), throwsArgumentError);
  });
}
