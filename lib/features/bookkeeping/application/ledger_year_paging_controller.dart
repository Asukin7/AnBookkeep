import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';

typedef LedgerYearLoader = Future<List<BookkeepingRecord>> Function(int year);
typedef LedgerAdjacentYearFinder = Future<int?> Function(int year);

final class LedgerDayGroup {
  const LedgerDayGroup({required this.date, required this.records});

  final String date;
  final List<BookkeepingRecord> records;
}

final class LedgerMonthPage {
  LedgerMonthPage({
    required this.month,
    required List<BookkeepingRecord> records,
  }) : records = List.unmodifiable(records),
       days = _groupDays(records),
       incomeMinor = records
           .where((record) => record.type.databaseValue == 1)
           .fold(0, (sum, record) => sum + record.entry.amountMinor),
       expenseMinor = records
           .where((record) => record.type.databaseValue == 0)
           .fold(0, (sum, record) => sum + record.entry.amountMinor);

  final String month;
  final List<BookkeepingRecord> records;
  final List<LedgerDayGroup> days;
  final int incomeMinor;
  final int expenseMinor;

  static List<LedgerDayGroup> _groupDays(List<BookkeepingRecord> records) {
    final groups = <String, List<BookkeepingRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(record.occurredAt.date, () => []).add(record);
    }
    return List.unmodifiable([
      for (final entry in groups.entries)
        LedgerDayGroup(
          date: entry.key,
          records: List.unmodifiable(entry.value),
        ),
    ]);
  }
}

final class LedgerYearPage {
  LedgerYearPage({required this.year, required List<BookkeepingRecord> records})
    : records = List.unmodifiable(records),
      months = _groupMonths(records);

  final int year;
  final List<BookkeepingRecord> records;
  final List<LedgerMonthPage> months;

  LedgerMonthPage? pageForMonth(String month) =>
      months.where((page) => page.month == month).firstOrNull;

  static List<LedgerMonthPage> _groupMonths(List<BookkeepingRecord> records) {
    final groups = <String, List<BookkeepingRecord>>{};
    for (final record in records) {
      groups.putIfAbsent(record.occurredAt.yearMonth, () => []).add(record);
    }
    final pages = [
      for (final entry in groups.entries)
        LedgerMonthPage(month: entry.key, records: entry.value),
    ]..sort((left, right) => right.month.compareTo(left.month));
    return List.unmodifiable(pages);
  }
}

/// Loads one data year at a time while exposing month pages to the ledger UI.
final class LedgerYearPagingController {
  LedgerYearPagingController({
    required this.loadYear,
    required this.findOlderYear,
    this.findNewerYear,
  });

  final LedgerYearLoader loadYear;
  final LedgerAdjacentYearFinder findOlderYear;
  final LedgerAdjacentYearFinder? findNewerYear;
  final Map<int, LedgerYearPage> _years = {};

  int _generation = 0;
  bool isInitializing = false;
  bool isLoadingOlder = false;
  bool isLoadingNewer = false;
  bool hasOlder = true;
  bool hasNewer = true;

  List<LedgerYearPage> get years {
    final values = _years.values.toList()
      ..sort((left, right) => right.year.compareTo(left.year));
    return List.unmodifiable(values);
  }

  List<LedgerMonthPage> get pages =>
      List.unmodifiable([for (final year in years) ...year.months]);

  LedgerMonthPage? pageFor(String month) {
    final year = _parseYearMonth(month);
    return _years[year]?.pageForMonth(month);
  }

  int? get newestYear => years.firstOrNull?.year;
  int? get oldestYear => years.lastOrNull?.year;
  String? get newestMonth => pages.firstOrNull?.month;
  String? get oldestMonth => pages.lastOrNull?.month;

  Future<void> initialize(String anchorMonth) async {
    final year = _parseYearMonth(anchorMonth);
    final generation = ++_generation;
    isInitializing = true;
    isLoadingOlder = false;
    isLoadingNewer = false;
    hasOlder = true;
    hasNewer = findNewerYear != null;
    try {
      final records = await loadYear(year);
      if (generation != _generation) return;
      _years
        ..clear()
        ..[year] = LedgerYearPage(year: year, records: records);
    } finally {
      if (generation == _generation) isInitializing = false;
    }
  }

  void initializeWithRecords(
    String anchorMonth,
    List<BookkeepingRecord> records,
  ) {
    final year = _parseYearMonth(anchorMonth);
    _generation++;
    _years
      ..clear()
      ..[year] = LedgerYearPage(year: year, records: records);
    isInitializing = false;
    isLoadingOlder = false;
    isLoadingNewer = false;
    hasOlder = true;
    hasNewer = findNewerYear != null;
  }

  Future<bool> loadOlder() async {
    final fromYear = oldestYear;
    if (fromYear == null || !hasOlder || isLoadingOlder) return false;
    isLoadingOlder = true;
    final generation = _generation;
    try {
      final year = await findOlderYear(fromYear);
      if (generation != _generation) return false;
      if (year == null) {
        hasOlder = false;
        return false;
      }
      final records = await loadYear(year);
      if (generation != _generation) return false;
      _years[year] = LedgerYearPage(year: year, records: records);
      return true;
    } finally {
      if (generation == _generation) isLoadingOlder = false;
    }
  }

  Future<bool> loadNewer() async {
    final fromYear = newestYear;
    final finder = findNewerYear;
    if (fromYear == null || finder == null || !hasNewer || isLoadingNewer) {
      return false;
    }
    isLoadingNewer = true;
    final generation = _generation;
    try {
      final year = await finder(fromYear);
      if (generation != _generation) return false;
      if (year == null) {
        hasNewer = false;
        return false;
      }
      final records = await loadYear(year);
      if (generation != _generation) return false;
      _years[year] = LedgerYearPage(year: year, records: records);
      return true;
    } finally {
      if (generation == _generation) isLoadingNewer = false;
    }
  }

  Future<void> refreshLoaded() async {
    final generation = _generation;
    final loadedYears = _years.keys.toList(growable: false);
    final records = await Future.wait([
      for (final year in loadedYears) loadYear(year),
    ]);
    if (generation != _generation) return;
    for (var index = 0; index < loadedYears.length; index++) {
      final year = loadedYears[index];
      _years[year] = LedgerYearPage(year: year, records: records[index]);
    }
  }

  void invalidate() {
    _generation++;
    _years.clear();
    isInitializing = false;
    isLoadingOlder = false;
    isLoadingNewer = false;
  }

  static int _parseYearMonth(String month) {
    final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(month);
    if (match == null) {
      throw FormatException('月份格式必须为 yyyy-MM', month);
    }
    return int.parse(match.group(1)!);
  }
}
