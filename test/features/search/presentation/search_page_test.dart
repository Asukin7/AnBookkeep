import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/search/presentation/search_page.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final repository = BookkeepingRepository(database);
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.fromDecimal(Decimal.parse('10')),
      occurredAt: LocalMinute.parse('2026-08-28 12:00'),
      note: '午餐',
    );
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-shopping',
      amount: Money.fromDecimal(Decimal.parse('30')),
      occurredAt: LocalMinute.parse('2026-08-29 12:00'),
      note: '纸巾',
    );
  });

  tearDown(() => database.close());

  test('selected dates use a tilde separator', () {
    expect(
      searchDateRangeText(
        DateTimeRange(start: DateTime(2026, 8), end: DateTime(2026, 8, 31)),
      ),
      '2026-08-01 ~ 2026-08-31',
    );
  });

  testWidgets('typing keyword and amount refreshes results automatically', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          categoriesByTypeProvider.overrideWith(
            (ref, type) => Stream.value(const [
              CategoryRow(
                id: 'expense-food',
                type: 0,
                name: '餐饮',
                iconCode: 'restaurant',
                colorValue: 0xFFFF0000,
                sortOrder: 0,
                createdAt: 0,
                updatedAt: 0,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '午');
    await tester.pumpAndSettle();
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();
    final dateRangeButton = find.byKey(
      const ValueKey('search-date-range-button'),
    );
    expect(dateRangeButton, findsOneWidget);
    expect(tester.widget(dateRangeButton), isA<FilledButton>());
    expect(
      find.descendant(of: dateRangeButton, matching: find.byType(Icon)),
      findsNothing,
    );
    expect(
      find.descendant(of: dateRangeButton, matching: find.text('时间范围')),
      findsNothing,
    );
    expect(find.text('全部时间'), findsOneWidget);

    final surfaceColor = Theme.of(tester.element(dateRangeButton))
        .colorScheme
        .surfaceContainerLow;
    expect(
      tester
          .widget<FilledButton>(dateRangeButton)
          .style
          ?.backgroundColor
          ?.resolve({}),
      surfaceColor,
    );

    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    final categoryButton = find.byKey(const ValueKey('search-category-button'));
    expect(categoryButton, findsOneWidget);
    expect(find.text('全部分类'), findsOneWidget);
    final dateText = tester.widget<Text>(
      find.descendant(of: dateRangeButton, matching: find.text('全部时间')),
    );
    final categoryText = tester.widget<Text>(
      find.descendant(of: categoryButton, matching: find.text('全部分类')),
    );
    expect(categoryText.style?.fontSize, dateText.style?.fontSize);
    expect(categoryText.style?.fontWeight, dateText.style?.fontWeight);
    expect(
      tester
          .widget<FilledButton>(categoryButton)
          .style
          ?.backgroundColor
          ?.resolve({}),
      surfaceColor,
    );
    expect(
      tester.getTopLeft(categoryButton).dy -
          tester.getBottomLeft(dateRangeButton).dy,
      closeTo(8, .1),
    );

    await tester.enterText(find.widgetWithText(TextField, '最小金额'), '20');
    await tester.pumpAndSettle();
    expect(find.text('午餐'), findsNothing);
    expect(find.text('纸巾'), findsOneWidget);

    await tester.tap(categoryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    expect(find.text('已选1项分类'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('ledger change signal refreshes search results', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('晚餐'), findsNothing);

    await BookkeepingRepository(database).create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.fromMinorUnits(2200),
      occurredAt: LocalMinute.parse('2026-08-30 18:00'),
      note: '晚餐',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    container.read(ledgerChangeRevisionProvider.notifier).notifyChanged();
    await tester.pumpAndSettle();

    expect(find.text('晚餐'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
