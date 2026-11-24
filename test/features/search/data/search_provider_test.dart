import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/bookkeeping_search_order.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/search/data/search_provider.dart';
import 'package:anbookkeep/features/search/domain/search_criteria.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BookkeepingRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = BookkeepingRepository(database);
    for (final entry in const [
      ('2024-08-01 12:00', '通勤'),
      ('2025-08-01 12:00', '午餐'),
      ('2026-08-01 12:00', '通勤'),
    ]) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.zero,
        occurredAt: LocalMinute.parse(entry.$1),
        note: entry.$2,
      );
    }
  });

  tearDown(() => database.close());

  test('search loads a year and skips years without matching data', () async {
    final criteria = SearchCriteria(keyword: '通勤');

    final initial = await loadInitialSearchYear(repository, criteria);
    expect(initial?.anchorMonth, '2026-08');
    expect(initial?.records, hasLength(1));
    expect(await loadSearchYear(repository, criteria, 2026), hasLength(1));
    expect(await findOlderSearchYear(repository, criteria, 2026), 2024);
    expect(await findOlderSearchYear(repository, criteria, 2024), isNull);
  });

  test('ascending time search starts at the earliest matching year', () async {
    final criteria = SearchCriteria(
      keyword: '通勤',
      order: BookkeepingSearchOrder.timeAscending,
    );
    final initial = await loadInitialSearchYear(repository, criteria);
    expect(initial?.anchorMonth, '2024-08');
    expect(await findNewerSearchYear(repository, criteria, 2024), 2026);
    expect(await findNewerSearchYear(repository, criteria, 2026), isNull);
  });

  test('amount cursors preserve global order and ties across pages', () async {
    for (final (date, amount, type, note) in const [
      ('2022-01-01 12:00', 30000, EntryType.expense, '金额旧年最大'),
      ('2025-12-01 12:00', 10000, EntryType.expense, '金额同额较早'),
      ('2026-01-01 09:00', 10000, EntryType.income, '金额同额上午'),
      ('2026-01-01 14:00', 10000, EntryType.expense, '金额同额下午'),
      ('2024-12-31 12:00', 100, EntryType.income, '金额最小'),
    ]) {
      await repository.create(
        type: type,
        categoryId: type == EntryType.income ? 'income-salary' : 'expense-food',
        amount: Money.fromMinorUnits(amount),
        occurredAt: LocalMinute.parse(date),
        note: note,
      );
    }

    Future<List<String>> collect(BookkeepingSearchOrder order) async {
      final criteria = SearchCriteria(keyword: '金额', order: order);
      final records = <BookkeepingRecord>[];
      for (var index = 0; index < 3; index++) {
        final page = await loadAmountSearchPage(
          repository,
          criteria,
          after: records.lastOrNull,
          pageSize: 2,
        );
        expect(page.hasMore, index < 2);
        records.addAll(page.records);
      }
      return records.map((record) => record.displayName).toList();
    }

    const ties = ['金额同额下午', '金额同额上午', '金额同额较早'];
    expect(await collect(BookkeepingSearchOrder.amountDescending), [
      '金额旧年最大',
      ...ties,
      '金额最小',
    ]);
    expect(await collect(BookkeepingSearchOrder.amountAscending), [
      '金额最小',
      ...ties,
      '金额旧年最大',
    ]);
  });
}
