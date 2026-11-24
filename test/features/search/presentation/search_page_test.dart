import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_record_list.dart';
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

  final startDateButton = find.byKey(
    const ValueKey('search-start-date-button'),
  );
  final endDateButton = find.byKey(const ValueKey('search-end-date-button'));

  void expectDateLabelLeft(WidgetTester tester, Finder button, String text) {
    final label = find.descendant(of: button, matching: find.text(text));
    expect(
      tester.getTopLeft(label).dx - tester.getTopLeft(button).dx,
      closeTo(AppSpacing.md, 0.1),
    );
  }

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

    final keywordField = find.byType(TextField).first;
    final expandButton = find.descendant(
      of: keywordField,
      matching: find.byTooltip('展开筛选'),
    );
    final collapseButton = find.descendant(
      of: keywordField,
      matching: find.byTooltip('收起筛选'),
    );
    void expectCenteredIcon(Finder button, IconData icon) {
      final glyph = find.descendant(of: button, matching: find.byIcon(icon));
      expect(
        (tester.getCenter(glyph) - tester.getCenter(button)).distance,
        lessThan(0.1),
      );
    }

    expect(
      tester.getCenter(expandButton).dx,
      greaterThan(tester.getCenter(keywordField).dx),
    );
    expectCenteredIcon(expandButton, Icons.expand_more_rounded);
    await tester.tap(expandButton);
    await tester.pumpAndSettle();
    expect(startDateButton, findsOneWidget);
    expectCenteredIcon(collapseButton, Icons.expand_less_rounded);
    await tester.tap(collapseButton);
    await tester.pumpAndSettle();
    expect(startDateButton, findsNothing);

    await tester.enterText(keywordField, '');
    await tester.tap(expandButton);
    await tester.pumpAndSettle();
    final typeFilter = find.byType(AppSegmentedButton<EntryType?>);
    final categoryButton = find.byKey(const ValueKey('search-category-button'));
    final minAmountField = find.widgetWithText(TextField, '最小金额');
    final maxAmountField = find.widgetWithText(TextField, '最大金额');

    void expectGroupGap(Finder above, Finder below) {
      expect(
        tester.getTopLeft(below).dy - tester.getBottomLeft(above).dy,
        closeTo(AppSpacing.componentGap, 0.1),
      );
    }

    expect(categoryButton, findsNothing);
    expectGroupGap(typeFilter, startDateButton);
    expectGroupGap(startDateButton, minAmountField);
    expectDateLabelLeft(tester, startDateButton, '开始时间');
    expectDateLabelLeft(tester, endDateButton, '结束时间');
    expect(
      tester.getTopLeft(startDateButton).dy,
      tester.getTopLeft(endDateButton).dy,
    );
    expect(
      tester.getSize(startDateButton).width,
      tester.getSize(endDateButton).width,
    );
    expect(
      find.descendant(of: startDateButton, matching: find.byType(Icon)),
      findsNothing,
    );

    final surfaceColor = Theme.of(tester.element(startDateButton))
        .colorScheme
        .surfaceContainerLow;
    expect(
      tester
          .widget<FilledButton>(startDateButton)
          .style
          ?.backgroundColor
          ?.resolve({}),
      surfaceColor,
    );

    await tester.tap(find.text('支出'));
    await tester.pumpAndSettle();
    expect(categoryButton, findsOneWidget);
    expect(find.text('全部分类'), findsOneWidget);
    expect(find.byTooltip('清除分类'), findsNothing);
    expect(find.byTooltip('清除最小金额'), findsNothing);
    expect(find.byTooltip('清除最大金额'), findsNothing);
    final dateText = tester.widget<Text>(
      find.descendant(of: startDateButton, matching: find.text('开始时间')),
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
    expectGroupGap(typeFilter, categoryButton);
    expectGroupGap(categoryButton, startDateButton);
    expectGroupGap(startDateButton, minAmountField);

    await tester.enterText(minAmountField, '20');
    await tester.pumpAndSettle();
    expect(find.text('午餐'), findsNothing);
    expect(find.text('纸巾'), findsOneWidget);

    await tester.tap(categoryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('餐饮'));
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('已选1项分类')).dx,
      closeTo(tester.getCenter(categoryButton).dx, 0.1),
    );
    expect(find.text('暂无符合条件的账单'), findsOneWidget);

    final clearCategory = find.byTooltip('清除分类');
    final clearBounds = tester.getRect(clearCategory);
    expect(tester.getRect(categoryButton).intersect(clearBounds), clearBounds);
    expectCenteredIcon(clearCategory, Icons.close_rounded);
    await tester.tap(clearCategory);
    await tester.pumpAndSettle();
    expect(find.text('全部分类'), findsOneWidget);
    expect(find.byTooltip('清除分类'), findsNothing);
    expect(find.text('午餐'), findsNothing);
    expect(find.text('纸巾'), findsOneWidget);

    await tester.enterText(maxAmountField, '25');
    await tester.pumpAndSettle();
    expect(find.text('暂无符合条件的账单'), findsOneWidget);
    await tester.tap(find.byTooltip('清除最小金额'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('清除最小金额'), findsNothing);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsNothing);

    await tester.enterText(maxAmountField, 'invalid');
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额'), findsWidgets);
    await tester.tap(find.byTooltip('清除最大金额'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额'), findsNothing);
    expect(find.byTooltip('清除最大金额'), findsNothing);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('start and end dates can be selected and cleared independently', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();

    final datePicker = find.byType(DatePickerDialog);
    Future<void> selectDate(
      Finder button,
      DateTime date, {
      DateTime? firstDate,
    }) async {
      await tester.tap(button);
      await tester.pumpAndSettle();
      if (firstDate != null) {
        expect(
          tester.widget<DatePickerDialog>(datePicker).firstDate,
          firstDate,
        );
      }
      final localizations = MaterialLocalizations.of(
        tester.element(datePicker),
      );
      await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: datePicker, matching: find.byType(TextField)),
        localizations.formatCompactDate(date),
      );
      await tester.tap(find.text(localizations.okButtonLabel));
      await tester.pumpAndSettle();
    }

    Future<void> clearDate(Finder button, String tooltip) async {
      final clearButton = find.byTooltip(tooltip);
      final clearBounds = tester.getRect(clearButton);
      expect(tester.getRect(button).intersect(clearBounds), clearBounds);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      expect(datePicker, findsNothing);
    }

    final august29 = DateTime(2026, 8, 29);
    await selectDate(startDateButton, august29);
    expect(find.text('2026-08-29'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.text('午餐'), findsNothing);
    expect(find.text('纸巾'), findsOneWidget);

    await selectDate(endDateButton, august29, firstDate: august29);
    expectDateLabelLeft(tester, startDateButton, '2026-08-29');
    expectDateLabelLeft(tester, endDateButton, '2026-08-29');
    expect(find.text('午餐'), findsNothing);

    await clearDate(startDateButton, '清除开始时间');
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('2026-08-29'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsOneWidget);

    await selectDate(endDateButton, DateTime(2026, 8, 28));
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsNothing);

    await clearDate(endDateButton, '清除结束时间');
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('纸巾'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
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

  testWidgets('cycles search order, preserves filters, and resets the order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = BookkeepingRepository(database);
    for (final (date, amount, note) in const [
      ('2024-10-05 12:00', 8000, '账单早年'),
      ('2026-08-29 09:00', 1500, '账单上午'),
      ('2026-08-29 14:00', 500, '账单下午'),
    ]) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(amount),
        occurredAt: LocalMinute.parse(date),
        note: note,
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();
    final keyword = find.byType(TextField).first;
    await tester.enterText(keyword, '账单');
    await tester.tap(find.byTooltip('展开筛选'));
    await tester.pumpAndSettle();

    List<String> resultNames() => tester
        .widgetList<BookkeepingRecordTile>(find.byType(BookkeepingRecordTile))
        .map((tile) => tile.record.displayName)
        .toList();

    final reset = find.widgetWithText(TextButton, '重置条件');
    final initialSort = find.widgetWithText(TextButton, '时间倒序');
    expect(tester.getCenter(initialSort).dy, tester.getCenter(reset).dy);
    expect(
      tester.getTopLeft(initialSort).dx,
      closeTo(tester.getTopLeft(startDateButton).dx, 0.1),
    );
    expect(
      tester.getTopRight(reset).dx,
      closeTo(tester.getTopRight(endDateButton).dx, 0.1),
    );
    expect(resultNames(), ['账单下午', '账单上午', '账单早年']);
    expect(find.byType(BookkeepingDayGroup), findsNWidgets(2));

    Future<void> cycle(String current, String next) async {
      await tester.tap(find.widgetWithText(TextButton, current));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, next), findsOneWidget);
      expect(tester.widget<TextField>(keyword).controller?.text, '账单');
    }

    await cycle('时间倒序', '时间正序');
    expect(resultNames(), ['账单早年', '账单上午', '账单下午']);
    expect(find.byType(BookkeepingDayGroup), findsNWidgets(2));

    await cycle('时间正序', '金额倒序');
    expect(resultNames(), ['账单早年', '账单上午', '账单下午']);
    expect(find.byType(BookkeepingDayGroup), findsNothing);
    expect(find.text('2024-10-05 12:00'), findsOneWidget);

    await cycle('金额倒序', '金额正序');
    expect(resultNames(), ['账单下午', '账单上午', '账单早年']);
    await cycle('金额正序', '时间倒序');
    expect(find.byType(BookkeepingDayGroup), findsNWidgets(2));

    await cycle('时间倒序', '时间正序');
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(initialSort, findsOneWidget);
    expect(tester.widget<TextField>(keyword).controller?.text, isEmpty);
    expect(find.text('午餐'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
