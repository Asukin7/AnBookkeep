import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('selecting a historical note immediately fills the note field', (
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
      note: '工作午餐',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookkeepingRepositoryProvider.overrideWithValue(repository),
          categoriesByTypeProvider.overrideWith(
            (ref, type) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: BookkeepingPage()),
      ),
    );
    await tester.pumpAndSettle();

    final initialNoteField = tester.widget<TextField>(find.byType(TextField));
    expect(initialNoteField.decoration?.labelText, '备注');
    expect(initialNoteField.decoration?.hintText, isNull);

    await tester.tap(find.byTooltip('历史备注'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(Wrap)).width,
      greaterThan(tester.getSize(find.text('工作午餐')).width),
    );
    expect(find.text('工作午餐'), findsOneWidget);
    await tester.tap(find.text('工作午餐'));
    await tester.pumpAndSettle();

    final noteField = tester.widget<TextField>(find.byType(TextField));
    expect(noteField.controller?.text, '工作午餐');
  });

  testWidgets('new entry starts in save mode and uses a card time key', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesByTypeProvider.overrideWith(
            (ref, type) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: BookkeepingPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
    final dateText = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(widget.data ?? ''),
    );
    expect(dateText, findsOneWidget);
    final timeText = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data ?? ''),
    );
    expect(timeText, findsOneWidget);
    final timeButton = tester.widget<TextButton>(
      find.ancestor(of: dateText, matching: find.byType(TextButton)),
    );
    final zeroButton = tester.widget<TextButton>(
      find.ancestor(of: find.text('0'), matching: find.byType(TextButton)),
    );
    expect(
      timeButton.style?.backgroundColor?.resolve({}),
      zeroButton.style?.backgroundColor?.resolve({}),
    );
    expect(
      timeButton.style?.shape?.resolve({}),
      zeroButton.style?.shape?.resolve({}),
    );
    final dateWidget = tester.widget<Text>(dateText);
    final timeWidget = tester.widget<Text>(timeText);
    expect(timeWidget.style?.fontSize, dateWidget.style?.fontSize);
    expect(timeWidget.style?.fontWeight, dateWidget.style?.fontWeight);
    expect(timeWidget.textAlign, TextAlign.center);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('date precision keeps the original date typography', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'settings.timePrecision': TimePrecision.date.name,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          categoriesByTypeProvider.overrideWith(
            (ref, type) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: BookkeepingPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    final dateText = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(widget.data ?? ''),
    );
    final text = tester.widget<Text>(dateText);
    expect(
      text.style?.fontSize,
      AppTypography.calculator(Theme.of(tester.element(dateText)).textTheme)
          .fontSize,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^\d{2}:\d{2}$').hasMatch(widget.data ?? ''),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('editing a category below the first three rows reveals it', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = BookkeepingRepository(database);
    final id = await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-transfer',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-09-25 12:00'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookkeepingRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(home: BookkeepingPage(transactionId: id)),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(grid.controller!.offset, greaterThan(0));
    expect(find.text('转账'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('backspace has the normal button tap and hold behavior', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalculatorKeyboard(
            onPressed: (key) {
              if (key == '←') presses++;
            },
            timeLabel: '2026-09-25',
            onTimeTap: () {},
            saveMode: true,
          ),
        ),
      ),
    );

    final backspace = find.text('←');
    await tester.tap(backspace);
    expect(presses, 1);

    final gesture = await tester.startGesture(tester.getCenter(backspace));
    await tester.pump(const Duration(milliseconds: 600));
    expect(presses, greaterThan(2));
    final countWhileHeld = presses;
    await gesture.up();
    await tester.pump();
    expect(presses, countWhileHeld);
  });
}
