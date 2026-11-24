import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/features/analytics/presentation/analytics_page.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/search/presentation/search_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    await BookkeepingRepository(database).create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.fromMinorUnits(12850),
      occurredAt: LocalMinute.fromDateTime(now),
    );
    await BookkeepingRepository(database).create(
      type: EntryType.income,
      categoryId: 'income-salary',
      amount: Money.fromMinorUnits(50000),
      occurredAt: LocalMinute.fromDateTime(now),
    );
  });

  tearDown(() => database.close());

  testWidgets('period and metrics share one card and count has no unit', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: AnalyticsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.text('统计分析')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: appBar,
        matching: find.byWidgetPredicate(
          (widget) => widget is AppSegmentedButton,
        ),
      ),
      findsOneWidget,
    );

    final summaryCard = find.byType(AppCard).first;
    final now = DateTime.now();
    expect(
      find.descendant(
        of: summaryCard,
        matching: find.text('${now.year}年${now.month}月'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summaryCard, matching: find.text('总笔数')),
      findsOneWidget,
    );
    expect(
      tester
          .getCenter(
            find.descendant(
              of: summaryCard,
              matching: find.text('${now.year}年${now.month}月'),
            ),
          )
          .dx,
      closeTo(
        tester
            .getCenter(
              find.descendant(of: summaryCard, matching: find.text('总支出')),
            )
            .dx,
        1,
      ),
    );
    expect(
      find.descendant(of: summaryCard, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('1笔'), findsNothing);

    expect(
      tester
          .widget<Text>(
            find.descendant(of: summaryCard, matching: find.text('-128.50')),
          )
          .style
          ?.color,
      AppColors.expense,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: summaryCard, matching: find.text('1')),
          )
          .style
          ?.color,
      Theme.of(tester.element(find.byType(AnalyticsPage))).colorScheme.primary,
    );

    await tester.tap(find.text('收入'));
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.descendant(of: summaryCard, matching: find.text('+500.00')),
          )
          .style
          ?.color,
      AppColors.income,
    );
  });

  testWidgets('ledger change signal refreshes analytics data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: AnalyticsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('-128.50'), findsOneWidget);

    await BookkeepingRepository(database).create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.fromMinorUnits(500),
      occurredAt: LocalMinute.fromDateTime(DateTime.now()),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AnalyticsPage)),
    );
    container.read(ledgerChangeRevisionProvider.notifier).notifyChanged();
    await tester.pumpAndSettle();

    expect(find.text('-133.50'), findsOneWidget);
  });

  testWidgets('category progress row opens search with the analysis filters', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0, 23, 59);
    final previousMonth = DateTime(now.year, now.month, 0, 23, 59);
    final previousYear = DateTime(now.year - 1, 12, 1);
    final repository = BookkeepingRepository(database);
    for (final (date, note) in [
      (lastDay, '月底购物'),
      (previousMonth, '上月购物'),
      (previousYear, '去年购物'),
    ]) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-shopping',
        amount: Money.fromMinorUnits(2200),
        occurredAt: LocalMinute.fromDateTime(date),
        note: note,
      );
    }

    appRouter.go(AppRoutes.analytics);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();

    Future<void> expandFilters() async {
      expect(find.byType(AppSegmentedButton<EntryType?>), findsNothing);
      await tester.tap(find.byTooltip('展开筛选'));
      await tester.pumpAndSettle();
    }

    Future<void> openShoppingSearch() async {
      final shopping = find.text('购物');
      await tester.ensureVisible(shopping);
      await tester.tap(shopping);
      await tester.pumpAndSettle();
      expect(find.byType(SearchPage), findsOneWidget);
      expect(find.text('月底购物'), findsOneWidget);
      expect(find.text('-128.50'), findsNothing);
      await expandFilters();
      expect(
        tester
            .widget<AppSegmentedButton<EntryType?>>(
              find.byType(AppSegmentedButton<EntryType?>),
            )
            .selected,
        {EntryType.expense},
      );
      expect(find.text('已选1项分类'), findsOneWidget);
    }

    await openShoppingSearch();
    expect(
      find.text(LocalMinute.fromDateTime(DateTime(now.year, now.month)).date),
      findsOneWidget,
    );
    expect(find.text(LocalMinute.fromDateTime(lastDay).date), findsOneWidget);
    expect(find.text('上月购物'), findsNothing);
    expect(find.text('去年购物'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.donut_large_rounded), findsOneWidget);

    Future<void> selectPeriod(String periodLabel) async {
      final dateLabel = find.text('${now.year}年${now.month}月');
      await tester.ensureVisible(dateLabel);
      await tester.tap(dateLabel);
      await tester.pumpAndSettle();
      await tester.tap(find.text(periodLabel));
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
    }

    await selectPeriod('年');
    await openShoppingSearch();
    expect(find.text('${now.year}-01-01'), findsOneWidget);
    expect(find.text('${now.year}-12-31'), findsOneWidget);
    expect(find.text('去年购物'), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final yearLabel = find.text('${now.year}年');
    await tester.ensureVisible(yearLabel);
    await tester.tap(yearLabel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部'));
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    await openShoppingSearch();
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.text('上月购物'), findsOneWidget);
    expect(find.text('去年购物'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工资'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.text('工资'), findsOneWidget);
    expect(find.text('月底购物'), findsNothing);
    await expandFilters();
    expect(
      tester
          .widget<AppSegmentedButton<EntryType?>>(
            find.byType(AppSegmentedButton<EntryType?>),
          )
          .selected,
      {EntryType.income},
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('结余'));
    await tester.pumpAndSettle();
    expect(find.text('分类分析'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('charts use clean axes, average line and category colors', (
    tester,
  ) async {
    final expenseCategories = await BookkeepingRepository(database)
        .getCategories(EntryType.expense);
    final food = expenseCategories.firstWhere(
      (category) => category.id == 'expense-food',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: AnalyticsPage()),
      ),
    );
    await tester.pumpAndSettle();

    final line = tester.widget<LineChart>(find.byType(LineChart));
    expect(find.text('趋势分析'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('趋势分析')).style,
      Theme.of(tester.element(find.byType(AnalyticsPage)))
          .textTheme
          .titleMedium,
    );
    expect(line.data.gridData.show, isFalse);
    expect(line.data.borderData.show, isFalse);
    expect(line.data.titlesData.leftTitles.sideTitles.showTitles, isTrue);
    expect(line.data.titlesData.leftTitles.sideTitles.reservedSize, 36);
    expect(line.data.extraLinesData.horizontalLines, hasLength(1));
    expect(line.data.extraLinesData.horizontalLines.single.dashArray, [6, 4]);
    expect(line.data.lineBarsData.single.isCurved, isTrue);
    expect(line.data.lineBarsData.single.belowBarData.show, isTrue);
    expect(line.data.lineBarsData.single.belowBarData.gradient, isNotNull);

    final pie = tester.widget<PieChart>(find.byType(PieChart));
    expect(find.text('分类分析'), findsOneWidget);
    expect(pie.data.sectionsSpace, 0);
    expect(pie.data.sections.single.color, Color(food.colorValue));
    expect(find.text('餐饮 -128.50(100.00%)'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(PieChart)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.bar_chart_rounded));
    await tester.pumpAndSettle();
    final bar = tester.widget<BarChart>(find.byType(BarChart));
    expect(bar.data.gridData.show, isFalse);
    expect(bar.data.borderData.show, isFalse);
    expect(bar.data.titlesData.leftTitles.sideTitles.reservedSize, 36);
    expect(bar.data.extraLinesData.horizontalLines, hasLength(1));
    final radius = bar.data.barGroups
        .firstWhere((group) => group.barRods.single.toY > 0)
        .barRods
        .single
        .borderRadius!;
    expect(radius.topLeft.x, greaterThan(0));
    expect(radius.topRight.x, greaterThan(0));
    expect(radius.bottomLeft.x, 0);
    expect(radius.bottomRight.x, 0);

    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsNothing);
    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('-128.50(100.00%)'), findsOneWidget);
    final categoryIcon = find.byType(CategoryIcon);
    final categoryName = find.text('餐饮');
    final categoryAmount = find.text('-128.50(100.00%)');
    expect(
      tester.getSize(categoryIcon),
      const Size.square(AppSizes.categoryIcon),
    );
    expect(
      tester.widget<Text>(categoryName).style,
      Theme.of(tester.element(categoryName)).textTheme.bodyLarge,
    );
    expect(
      tester.widget<Text>(categoryAmount).style,
      AppTypography.numeric(
        Theme.of(tester.element(categoryAmount)).textTheme.labelLarge,
      ).copyWith(color: AppColors.expense),
    );
    expect(
      tester.getTopLeft(categoryName).dx - tester.getTopRight(categoryIcon).dx,
      AppSpacing.md,
    );
  });
}
