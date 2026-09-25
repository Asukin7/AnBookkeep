import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BookkeepingRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = BookkeepingRepository(database);
  });

  tearDown(() => database.close());

  test('seeds the complete default income and expense categories', () async {
    final income = await repository.getCategories(EntryType.income);
    final expense = await repository.getCategories(EntryType.expense);

    expect(income.map((category) => category.name), [
      '工资',
      '房租',
      '红包',
      '收礼',
      '退款',
      '转卖',
      '理财',
      '其他',
    ]);
    expect(expense.map((category) => category.name), [
      '餐饮',
      '购物',
      '服饰',
      '交通',
      '教育',
      '医疗',
      '情感',
      '宠物',
      '通讯',
      '网络',
      '娱乐',
      '旅行',
      '住房',
      '缴费',
      '社交',
      '转账',
      '红包',
      '送礼',
      '捐款',
      '其他',
    ]);
    for (final category in [...income, ...expense]) {
      expect(categoryIconCodes, contains(category.iconCode));
      expect(Color(category.colorValue).a, 1);
    }
    final incomeIcons = {
      for (final category in income) category.name: category.iconCode,
    };
    expect(incomeIcons['工资'], 'part_time');
    expect(incomeIcons['红包'], 'wallet');
    expect(incomeIcons['退款'], 'undo');
    expect(incomeIcons['转卖'], 'loyalty');
    final expenseIcons = {
      for (final category in expense) category.name: category.iconCode,
    };
    expect(expenseIcons['交通'], 'directions_car');
    expect(expenseIcons['通讯'], 'communication');
    expect(expenseIcons['旅行'], 'flight');
    expect(expenseIcons['转账'], 'refund');
    expect(expenseIcons['红包'], 'wallet');
  });

  test('creates, edits and deletes a bookkeeping record', () async {
    final id = await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-08-28 12:30'),
      note: ' 午餐 ',
    );

    var record = await repository.getById(id);
    expect(record, isNotNull);
    expect(record!.entry.amountMinor, 0);
    expect(record.entry.note, '午餐');
    expect(record.type, EntryType.expense);

    await repository.update(
      id: id,
      type: EntryType.income,
      categoryId: 'income-salary',
      amount: Money.fromDecimal(Decimal.parse('123.45')),
      occurredAt: LocalMinute.parse('2026-09-01 09:00'),
      note: null,
    );

    record = await repository.getById(id);
    expect(record!.entry.amountMinor, 12345);
    expect(record.entry.note, isNull);
    expect(record.type, EntryType.income);
    expect(record.occurredAt.yearMonth, '2026-09');

    await repository.delete(id);
    expect(await repository.getById(id), isNull);
  });

  test('rejects a category from the other transaction type', () async {
    expect(
      () => repository.create(
        type: EntryType.income,
        categoryId: 'expense-food',
        amount: Money.zero,
        occurredAt: LocalMinute.parse('2026-08-28 12:30'),
      ),
      throwsA(isA<AppValidationException>()),
    );
  });

  test(
    'batch creation rolls back every entry when one entry is invalid',
    () async {
      final entries = [
        BookkeepingCreateInput(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.fromDecimal(Decimal.parse('12.34')),
          occurredAt: LocalMinute.parse('2026-08-28 12:30'),
        ),
        BookkeepingCreateInput(
          type: EntryType.income,
          categoryId: 'expense-food',
          amount: Money.fromDecimal(Decimal.parse('20')),
          occurredAt: LocalMinute.parse('2026-08-28 12:31'),
        ),
      ];

      await expectLater(
        repository.createBatch(entries),
        throwsA(isA<AppValidationException>()),
      );
      expect(await repository.search(), isEmpty);
    },
  );

  test('batch creation inserts validated entries in input order', () async {
    final ids = await repository.createBatch([
      BookkeepingCreateInput(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromDecimal(Decimal.parse('12.34')),
        occurredAt: LocalMinute.parse('2026-08-28 12:30'),
        note: '午餐',
      ),
      BookkeepingCreateInput(
        type: EntryType.income,
        categoryId: 'income-salary',
        amount: Money.fromDecimal(Decimal.parse('100')),
        occurredAt: LocalMinute.parse('2026-08-28 12:31'),
        note: '工资',
      ),
    ]);

    expect(ids, hasLength(2));
    expect((await repository.getById(ids[0]))?.entry.note, '午餐');
    expect((await repository.getById(ids[1]))?.entry.note, '工资');
  });

  test('search applies keyword, type and amount bounds together', () async {
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.fromDecimal(Decimal.parse('12.34')),
      occurredAt: LocalMinute.parse('2026-08-28 12:30'),
      note: '工作午餐',
    );
    await repository.create(
      type: EntryType.income,
      categoryId: 'income-salary',
      amount: Money.fromDecimal(Decimal.parse('1200')),
      occurredAt: LocalMinute.parse('2026-08-28 12:30'),
      note: '工资',
    );

    final records = await repository.search(
      keyword: '午餐',
      type: EntryType.expense,
      minAmountMinor: 1000,
      maxAmountMinor: 2000,
    );

    expect(records, hasLength(1));
    expect(records.single.entry.note, '工作午餐');
  });

  test(
    'loads the latest matching year and anchor month in one query',
    () async {
      for (final value in const [
        ('2024-01-01 10:00', '旧账单'),
        ('2026-02-01 10:00', '目标账单'),
        ('2026-08-01 10:00', '忽略'),
      ]) {
        await repository.create(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.zero,
          occurredAt: LocalMinute.parse(value.$1),
          note: value.$2,
        );
      }

      final result = await repository.searchLatestYear(keyword: '账单');

      expect(result?.latestMonth, '2026-02');
      expect(result?.records.map((record) => record.entry.note), ['目标账单']);
    },
  );

  test('search treats SQL wildcard characters as ordinary text', () async {
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-08-28 12:30'),
      note: '折扣 10%',
    );
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-08-28 12:31'),
      note: '普通记录',
    );

    final records = await repository.search(keyword: '%');
    expect(records, hasLength(1));
    expect(records.single.entry.note, '折扣 10%');
  });

  test('search pagination follows the same stable ordering', () async {
    await repository.createBatch([
      for (var index = 0; index < 3; index++)
        BookkeepingCreateInput(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.zero,
          occurredAt: LocalMinute.parse('2026-08-28 12:0$index'),
          note: '账单$index',
        ),
    ]);

    final firstPage = await repository.search(limit: 2);
    final secondPage = await repository.search(limit: 2, offset: 2);

    expect(firstPage.map((record) => record.entry.note), ['账单2', '账单1']);
    expect(secondPage.map((record) => record.entry.note), ['账单0']);
  });

  test(
    'historical notes are aggregated, trimmed and ordered by usage',
    () async {
      await repository.createBatch([
        BookkeepingCreateInput(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.zero,
          occurredAt: LocalMinute.parse('2026-08-28 12:30'),
          note: '午餐',
        ),
        BookkeepingCreateInput(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.zero,
          occurredAt: LocalMinute.parse('2026-08-29 12:30'),
          note: ' 午餐 ',
        ),
        BookkeepingCreateInput(
          type: EntryType.expense,
          categoryId: 'expense-transport',
          amount: Money.zero,
          occurredAt: LocalMinute.parse('2026-09-01 08:00'),
          note: '通勤',
        ),
        BookkeepingCreateInput(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.zero,
          occurredAt: LocalMinute.parse('2026-09-01 12:00'),
          note: '   ',
        ),
      ]);

      final notes = await repository.getHistoricalNotes(
        smartSort: false,
        now: DateTime(2026, 9, 2),
      );

      expect(notes.map((note) => note.value), ['午餐', '通勤']);
      expect(notes.first.useCount, 2);
    },
  );

  test('historical note profiles include active smart-sort context', () async {
    await repository.createBatch([
      BookkeepingCreateInput(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromDecimal(Decimal.parse('20')),
        occurredAt: LocalMinute.parse('2026-09-01 12:00'),
        note: '午餐',
      ),
      BookkeepingCreateInput(
        type: EntryType.expense,
        categoryId: 'expense-transport',
        amount: Money.fromDecimal(Decimal.parse('100')),
        occurredAt: LocalMinute.parse('2026-09-01 08:00'),
        note: '通勤',
      ),
    ]);

    final notes = await repository.getHistoricalNotes(
      smartSort: true,
      categoryId: 'expense-food',
      amountMinor: 2000,
      minuteOfDay: 12 * 60,
      now: DateTime(2026, 9, 2),
    );
    final lunch = notes.singleWhere((note) => note.value == '午餐');
    final commute = notes.singleWhere((note) => note.value == '通勤');

    expect(lunch.categoryAffinity, 1);
    expect(commute.categoryAffinity, 0);
    expect(lunch.amountSimilarity, greaterThan(commute.amountSimilarity!));
    expect(lunch.minuteSimilarity, greaterThan(commute.minuteSimilarity!));
  });

  test('reorders categories in one batch', () async {
    final before = await repository.watchCategories(EntryType.expense).first;
    final reversedIds = before
        .map((category) => category.id)
        .toList()
        .reversed
        .toList();

    await repository.reorderCategories(
      type: EntryType.expense,
      orderedIds: reversedIds,
    );

    final after = await repository.watchCategories(EntryType.expense).first;
    expect(after.map((category) => category.id), reversedIds);
  });

  test('rejects duplicate category names within the same type', () async {
    await expectLater(
      repository.createCategory(
        type: EntryType.expense,
        name: '餐饮',
        iconCode: 'food',
        colorValue: 0xFFFF0000,
      ),
      throwsA(
        isA<AppValidationException>().having(
          (error) => error.message,
          'message',
          contains('同名分类'),
        ),
      ),
    );

    final created = await repository.createCategory(
      type: EntryType.income,
      name: '临时分类',
      iconCode: 'other',
      colorValue: 0xFF00FF00,
    );
    await expectLater(
      repository.updateCategory(
        id: created,
        name: '工资',
        iconCode: 'other',
        colorValue: 0xFF00FF00,
      ),
      throwsA(isA<AppValidationException>()),
    );
  });

  test('loads a whole year and finds the nearest data years', () async {
    for (final date in const ['2023-07-01', '2025-08-01', '2026-09-01']) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.zero,
        occurredAt: LocalMinute.parse('$date 10:00'),
      );
    }

    expect(await repository.getYear(2025), hasLength(1));
    expect(await repository.nextDataYear(2023), 2025);
    expect(await repository.previousDataYear(2026), 2025);
    expect(await repository.nextDataYear(2026), isNull);
    expect(await repository.previousDataYear(2023), isNull);
    expect(await repository.dataYearRange(), (minYear: 2023, maxYear: 2026));
  });

  test('returns no data year range for an empty ledger', () async {
    expect(await repository.dataYearRange(), isNull);
  });
}
