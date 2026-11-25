import 'dart:async';

import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_record_list.dart';
import 'package:anbookkeep/features/detail/presentation/detail_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  for (final backupEnabled in [true, false]) {
    testWidgets(
      'pull refreshes the list with backup enabled = $backupEnabled',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'lanBackup.enabled': backupEnabled,
          'lanBackup.fileName': 'AN',
        });
        FlutterSecureStorage.setMockInitialValues({
          'lanBackup.key':
              'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA.dGVzdC1rZXk',
        });
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final repository = BookkeepingRepository(database);
        Future<void> createBill(String note) => repository.create(
          type: EntryType.expense,
          categoryId: 'expense-food',
          amount: Money.zero,
          occurredAt: LocalMinute.parse('2026-09-01 12:00'),
          note: note,
        );

        const channel = MethodChannel('com.an.anbookkeep/lan_backup');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        final finishBackup = Completer<void>();
        var backupAttempts = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'prepare') {
            backupAttempts++;
            await finishBackup.future;
            throw PlatformException(code: 'receiver_unavailable');
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

        await createBill('已有账单');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(database),
              sharedPreferencesProvider.overrideWithValue(
                await SharedPreferences.getInstance(),
              ),
            ],
            child: const MaterialApp(home: DetailPage()),
          ),
        );
        await tester.pumpAndSettle();

        await createBill('下拉后的账单');
        expect(find.text('下拉后的账单'), findsNothing);
        final list = find.byType(BookkeepingRecordList);
        final spinner = find.byWidgetPredicate(
          (widget) =>
              widget is CircularProgressIndicator &&
              widget.semanticsLabel == '正在刷新账单' &&
              widget.value == null,
        );

        final existingBill = find.text('已有账单');
        final originalTop = tester.getTopLeft(existingBill).dy;
        final pull = await tester.startGesture(tester.getCenter(list));
        await pull.moveBy(const Offset(0, 70));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(existingBill).dy, greaterThan(originalTop));
        expect(backupAttempts, 0);

        for (var step = 0; step < 4; step++) {
          await pull.moveBy(const Offset(0, 32));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await pull.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(spinner, findsOneWidget);
        expect(
          tester.getBottomLeft(spinner).dy,
          lessThan(tester.getTopLeft(list).dy),
        );

        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(find.text('下拉后的账单'), findsOneWidget);
        expect(backupAttempts, backupEnabled ? 1 : 0);
        expect(spinner, backupEnabled ? findsOneWidget : findsNothing);

        finishBackup.complete();
        await tester.pumpAndSettle();
        expect(spinner, findsNothing);
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        );
        expect(scrollable.position.outOfRange, isFalse);
      },
      variant: const TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
