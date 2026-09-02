import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/detail/presentation/detail_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('initial detail load exposes every data month in the year', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BookkeepingRepository(database);
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-09-01 12:00'),
      note: '九月账单',
    );
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-08-01 12:00'),
      note: '八月账单',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: DetailPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('九月账单'), findsOneWidget);
    expect(find.text('八月账单'), findsOneWidget);
  });
}
