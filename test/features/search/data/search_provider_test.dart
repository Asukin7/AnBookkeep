import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
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
    expect(initial?.latestMonth, '2026-08');
    expect(initial?.records, hasLength(1));
    expect(await loadSearchYear(repository, criteria, 2026), hasLength(1));
    expect(await findOlderSearchYear(repository, criteria, 2026), 2024);
    expect(await findOlderSearchYear(repository, criteria, 2024), isNull);
  });
}
