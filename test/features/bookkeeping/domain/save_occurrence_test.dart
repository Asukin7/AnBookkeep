import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/domain/save_occurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final selected = LocalMinute.parse('2026-08-20 08:15');

  test('new date-precision entry uses current hour and minute', () {
    expect(
      occurrenceForSave(
        selected: selected,
        precision: TimePrecision.date,
        isEditing: false,
        now: DateTime(2026, 8, 29, 14, 35),
      ).value,
      '2026-08-20 14:35',
    );
  });

  test('editing a date-precision entry preserves its stored time', () {
    expect(
      occurrenceForSave(
        selected: selected,
        precision: TimePrecision.date,
        isEditing: true,
        now: DateTime(2026, 8, 29, 14, 35),
      ),
      selected,
    );
  });
}
