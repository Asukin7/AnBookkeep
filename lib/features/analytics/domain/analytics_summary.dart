import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';

final class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalMinor,
    required this.averageMinor,
    required this.recordCount,
  });

  factory AnalyticsSummary.calculate(
    List<BookkeepingRecord> records, {
    required EntryType? type,
    required int denominator,
  }) {
    final relevant = type == null
        ? records
        : records.where((record) => record.type == type);
    final total = relevant.fold<int>(0, (sum, record) {
      if (type == null) {
        return sum +
            (record.type == EntryType.income
                ? record.entry.amountMinor
                : -record.entry.amountMinor);
      }
      return sum +
          (type == EntryType.expense
              ? -record.entry.amountMinor
              : record.entry.amountMinor);
    });
    return AnalyticsSummary(
      totalMinor: total,
      averageMinor: _roundedDivision(total, denominator),
      recordCount: relevant.length,
    );
  }

  factory AnalyticsSummary.fromAggregate({
    required int totalMinor,
    required int recordCount,
    required int denominator,
  }) => AnalyticsSummary(
    totalMinor: totalMinor,
    averageMinor: _roundedDivision(totalMinor, denominator),
    recordCount: recordCount,
  );

  final int totalMinor;
  final int averageMinor;
  final int recordCount;
}

int _roundedDivision(int value, int denominator) {
  if (denominator <= 0 || value == 0) return 0;
  final absolute = value.abs();
  final rounded = (absolute * 2 + denominator) ~/ (denominator * 2);
  return value.isNegative ? -rounded : rounded;
}

int bookkeepingYearCount(List<BookkeepingRecord> records, {EntryType? type}) {
  final relevant = type == null
      ? records
      : records.where((record) => record.type == type);
  return relevant
      .map((record) => record.occurredAt.date.substring(0, 4))
      .toSet()
      .length;
}
