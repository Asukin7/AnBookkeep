import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_year_paging_controller.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads newer and older years around a selected middle year', () async {
    final controller = LedgerYearPagingController(
      loadYear: (year) async => const [],
      findNewerYear: (year) async => switch (year) {
        2025 => 2026,
        _ => null,
      },
      findOlderYear: (year) async => switch (year) {
        2025 => 2024,
        _ => null,
      },
    );

    await controller.initialize('2025-08');
    await controller.loadNewer();
    await controller.loadOlder();

    expect(controller.years.map((page) => page.year), [2026, 2025, 2024]);
  });

  test('deduplicates concurrent adjacent page requests', () async {
    var olderLookups = 0;
    final controller = LedgerYearPagingController(
      loadYear: (year) async => const [],
      findOlderYear: (year) async {
        olderLookups++;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return null;
      },
    );
    await controller.initialize('2026-08');

    await Future.wait([controller.loadOlder(), controller.loadOlder()]);

    expect(olderLookups, 1);
    expect(controller.hasOlder, isFalse);
  });

  test('one annual load is split into descending month pages', () async {
    var loadCount = 0;
    final controller = LedgerYearPagingController(
      loadYear: (year) async {
        loadCount++;
        return [
          _record(id: 'sep', occurredAt: '$year-09-01 12:00'),
          _record(id: 'aug-2', occurredAt: '$year-08-02 12:00'),
          _record(id: 'aug-1', occurredAt: '$year-08-01 12:00'),
        ];
      },
      findOlderYear: (year) async => null,
    );

    await controller.initialize('2026-08');

    expect(loadCount, 1);
    expect(controller.pages.map((page) => page.month), ['2026-09', '2026-08']);
    expect(controller.pageFor('2026-08')?.records, hasLength(2));
  });

  test('clears initializing state when the annual load fails', () async {
    final controller = LedgerYearPagingController(
      loadYear: (year) => Future.error(StateError('load failed')),
      findOlderYear: (year) async => null,
    );

    await expectLater(controller.initialize('2026-08'), throwsStateError);

    expect(controller.isInitializing, isFalse);
    expect(controller.pages, isEmpty);
  });
}

BookkeepingRecord _record({required String id, required String occurredAt}) {
  return BookkeepingRecord(
    entry: TransactionRow(
      id: id,
      type: 0,
      categoryId: 'expense-food',
      amountMinor: 100,
      occurredAt: occurredAt,
      createdAt: 0,
      updatedAt: 0,
    ),
    category: const CategoryRow(
      id: 'expense-food',
      type: 0,
      name: '餐饮',
      iconCode: 'food',
      colorValue: 0xFFFF0000,
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
    ),
  );
}
