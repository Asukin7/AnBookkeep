import 'dart:math' as math;

/// Product-wide rules for dates that can be persisted and selected.
abstract final class AppDatePolicy {
  static const int minimumSupportedYear = 1;
  static const int maximumSupportedYear = 9999;
  static const int defaultPickerMinimumYear = 2020;

  static void validateYear(int year) {
    if (year < minimumSupportedYear || year > maximumSupportedYear) {
      throw ArgumentError.value(year, 'year', '年份必须在1-9999之间');
    }
  }

  static AppDateBounds pickerBounds({
    int? dataMinimumYear,
    int? dataMaximumYear,
    Iterable<int> anchorYears = const <int>[],
    DateTime? now,
  }) {
    final currentYear = (now ?? DateTime.now()).year;
    var minimumYear = math.min(defaultPickerMinimumYear, currentYear);
    var maximumYear = currentYear;
    for (final year in <int?>[
      dataMinimumYear,
      dataMaximumYear,
      ...anchorYears,
    ]) {
      if (year == null) continue;
      validateYear(year);
      minimumYear = math.min(minimumYear, year);
      maximumYear = math.max(maximumYear, year);
    }
    return AppDateBounds(minYear: minimumYear, maxYear: maximumYear);
  }
}

final class AppDateBounds {
  const AppDateBounds({required this.minYear, required this.maxYear})
    : assert(minYear <= maxYear);

  final int minYear;
  final int maxYear;

  DateTime get firstDate => DateTime(minYear);
  DateTime get lastDate => DateTime(maxYear, 12, 31, 23, 59);
}
