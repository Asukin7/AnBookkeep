import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';

LocalMinute occurrenceForSave({
  required LocalMinute selected,
  required TimePrecision precision,
  required bool isEditing,
  DateTime? now,
}) {
  if (precision == TimePrecision.minute || isEditing) return selected;
  final selectedDate = selected.toDateTime();
  final current = now ?? DateTime.now();
  return LocalMinute.fromDateTime(
    DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      current.hour,
      current.minute,
    ),
  );
}
