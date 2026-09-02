import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_year_paging_controller.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_record_list.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BookkeepingRepository repository;
  late LedgerMonthPage july;
  late LedgerMonthPage august;
  late LedgerMonthPage september;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = BookkeepingRepository(database);
    for (var index = 0; index < 6; index++) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(50 + index),
        occurredAt: LocalMinute.parse(
          '2026-07-01 ${index.toString().padLeft(2, '0')}:00',
        ),
      );
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(100 + index),
        occurredAt: LocalMinute.parse(
          '2026-08-01 ${index.toString().padLeft(2, '0')}:00',
        ),
      );
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(200 + index),
        occurredAt: LocalMinute.parse(
          '2026-09-01 ${index.toString().padLeft(2, '0')}:00',
        ),
      );
    }
    final year = LedgerYearPage(
      year: 2026,
      records: await repository.getYear(2026),
    );
    july = year.pageForMonth('2026-07')!;
    august = year.pageForMonth('2026-08')!;
    september = year.pageForMonth('2026-09')!;
  });

  tearDown(() => database.close());

  testWidgets('a centered month stays fixed when a newer month is inserted', (
    tester,
  ) async {
    final controller = BookkeepingRecordListController();
    final harnessKey = GlobalKey<_LedgerHarnessState>();
    await tester.pumpWidget(
      MaterialApp(
        home: _LedgerHarness(
          key: harnessKey,
          controller: controller,
          initialPages: [august, july],
          centerMonth: '2026-08',
        ),
      ),
    );
    await tester.pump();
    final augustFinder = find.textContaining('2026-08-01');
    final before = tester.getTopLeft(augustFinder).dy;

    harnessKey.currentState!.prepend(september);
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(augustFinder).dy, closeTo(before, 1));
  });

  testWidgets('a full newer month grows above the selected month smoothly', (
    tester,
  ) async {
    for (var day = 1; day <= 31; day++) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(day),
        occurredAt: LocalMinute.parse(
          '2026-01-${day.toString().padLeft(2, '0')} 12:00',
        ),
      );
    }
    for (var day = 1; day <= 28; day++) {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(day),
        occurredAt: LocalMinute.parse(
          '2026-02-${day.toString().padLeft(2, '0')} 12:00',
        ),
      );
    }
    final year = LedgerYearPage(
      year: 2026,
      records: await repository.getYear(2026),
    );
    final january = year.pageForMonth('2026-01')!;
    final february = year.pageForMonth('2026-02')!;
    final harnessKey = GlobalKey<_LedgerHarnessState>();
    var loaded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: _LedgerHarness(
          key: harnessKey,
          controller: BookkeepingRecordListController(),
          initialPages: [january],
          centerMonth: '2026-01',
          onReachTop: () {
            if (loaded) return;
            loaded = true;
            harnessKey.currentState!.prepend(february);
          },
        ),
      ),
    );
    await tester.pump();
    final januaryLastDay = find.textContaining('2026-01-31');
    final before = tester.getTopLeft(januaryLastDay).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );

    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await tester.pump();
    expect(loaded, isTrue);
    expect(tester.getTopLeft(januaryLastDay).dy, closeTo(before, 1));

    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(find.textContaining('2026-02-01'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('2026-02-01')).dy,
      lessThan(tester.getTopLeft(januaryLastDay).dy),
    );
    await gesture.up();
  });

  testWidgets('reports the month of the first visible day group', (
    tester,
  ) async {
    final visibleMonths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: _LedgerHarness(
          controller: BookkeepingRecordListController(),
          initialPages: [september, august, july],
          onVisibleMonthChanged: visibleMonths.add,
        ),
      ),
    );
    await tester.pump();
    expect(visibleMonths.last, '2026-09');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(visibleMonths.last, '2026-09');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pumpAndSettle();

    expect(visibleMonths.last, '2026-08');
  });

  testWidgets('selected month waits for a real scroll before prefetching', (
    tester,
  ) async {
    final controller = BookkeepingRecordListController();
    final harnessKey = GlobalKey<_LedgerHarnessState>();
    var newerRequests = 0;
    var olderRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _LedgerHarness(
          key: harnessKey,
          controller: controller,
          initialPages: [august],
          centerMonth: '2026-08',
          onReachTop: () => newerRequests++,
          onReachBottom: () => olderRequests++,
        ),
      ),
    );
    await tester.pump();
    newerRequests = 0;
    olderRequests = 0;

    controller.waitForUserScrollBeforePrefetch();
    harnessKey.currentState!.rebuild();
    await tester.pump();
    await tester.pump();
    expect(newerRequests, 0);
    expect(olderRequests, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 50));
    await tester.pump();
    await gesture.up();
    expect(newerRequests, 1);
    expect(olderRequests, 0);
  });

  testWidgets('an entirely empty ledger shows one generic empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _LedgerHarness(
          controller: BookkeepingRecordListController(),
          initialPages: [LedgerMonthPage(month: '2026-08', records: [])],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('暂无账单'), findsOneWidget);
    expect(find.textContaining('2026年8月暂无账单'), findsNothing);
  });
}

class _LedgerHarness extends StatefulWidget {
  const _LedgerHarness({
    required this.controller,
    required this.initialPages,
    this.onVisibleMonthChanged,
    this.onReachTop,
    this.onReachBottom,
    this.centerMonth,
    super.key,
  });

  final BookkeepingRecordListController controller;
  final List<LedgerMonthPage> initialPages;
  final ValueChanged<String>? onVisibleMonthChanged;
  final VoidCallback? onReachTop;
  final VoidCallback? onReachBottom;
  final String? centerMonth;

  @override
  State<_LedgerHarness> createState() => _LedgerHarnessState();
}

class _LedgerHarnessState extends State<_LedgerHarness> {
  late List<LedgerMonthPage> pages = List.of(widget.initialPages);

  void prepend(LedgerMonthPage page) {
    setState(() => pages = [page, ...pages]);
  }

  void rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BookkeepingRecordList(
        controller: widget.controller,
        pages: pages,
        centerMonth: widget.centerMonth,
        onVisibleMonthChanged: widget.onVisibleMonthChanged,
        onReachTop: widget.onReachTop,
        onReachBottom: widget.onReachBottom,
        onDelete: (_) {},
        timePrecision: TimePrecision.minute,
        useGrouping: true,
        incomeColor: Colors.green,
        expenseColor: Colors.red,
      ),
    );
  }
}
