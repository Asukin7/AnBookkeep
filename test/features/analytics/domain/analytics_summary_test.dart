import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/analytics/data/analytics_repository.dart';
import 'package:anbookkeep/features/analytics/domain/analytics_summary.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BookkeepingRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = BookkeepingRepository(database);
  });

  tearDown(() => database.close());

  test(
    'dimension summary counts only records of that type including zero',
    () async {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.zero,
        occurredAt: LocalMinute.parse('2025-01-01 10:00'),
      );
      await repository.create(
        type: EntryType.income,
        categoryId: 'income-salary',
        amount: Money.fromMinorUnits(1200),
        occurredAt: LocalMinute.parse('2026-01-01 10:00'),
      );
      final records = await repository.search();

      final expense = AnalyticsSummary.calculate(
        records,
        type: EntryType.expense,
        denominator: 31,
      );
      expect(expense.recordCount, 1);
      expect(expense.totalMinor, 0);
      expect(bookkeepingYearCount(records), 2);
      expect(bookkeepingYearCount(records, type: EntryType.expense), 1);
    },
  );

  test(
    'database aggregation supports totals above the single-entry limit',
    () async {
      for (var index = 0; index < 2; index++) {
        await repository.create(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.fromMinorUnits(Money.maxMinorUnits),
          occurredAt: LocalMinute.parse('2026-08-20 10:0$index'),
        );
      }

      final dataset = await AnalyticsRepository(database).load(
        type: EntryType.expense,
        granularity: AnalyticsGranularity.day,
        startDate: '2026-08-01',
        endDate: '2026-08-31',
      );

      expect(dataset.totalMinor, -Money.maxMinorUnits * 2);
      expect(dataset.recordCount, 2);
      expect(dataset.yearCount, 1);
      expect(dataset.trendMinorByKey['20'], Money.maxMinorUnits * 2);
      expect(dataset.categories.single.amountMinor, Money.maxMinorUnits * 2);
    },
  );
}
