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

  test('aggregate summary rounds positive and negative averages', () {
    final positive = AnalyticsSummary.fromAggregate(
      totalMinor: 5,
      recordCount: 1,
      denominator: 2,
    );
    final negative = AnalyticsSummary.fromAggregate(
      totalMinor: -5,
      recordCount: 1,
      denominator: 2,
    );

    expect(positive.averageMinor, 3);
    expect(negative.averageMinor, -3);
  });

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
