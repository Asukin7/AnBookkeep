import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
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

  testWidgets(
    'new entry starts in save mode with one surface for date and time',
    (tester) async {
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
      final combinedLabel = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')
                .hasMatch(widget.data ?? ''),
      );
      expect(combinedLabel, findsOneWidget);
      final zeroKey = find.ancestor(
        of: find.text('0'),
        matching: find.byType(TextButton),
      );
      final zeroButton = tester.widget<TextButton>(zeroKey);
      final dateTimeKey = find.byKey(
        const ValueKey('calculator-date-time-key'),
      );
      final surface = tester.widget<Material>(dateTimeKey);
      expect(surface.color, zeroButton.style?.backgroundColor?.resolve({}));
      final zeroShape =
          zeroButton.style?.shape?.resolve({}) as RoundedRectangleBorder;
      expect(surface.borderRadius, zeroShape.borderRadius);
      expect(tester.getSize(dateTimeKey), tester.getSize(zeroKey));
      expect(
        (tester.getCenter(combinedLabel) - tester.getCenter(dateTimeKey))
            .distance,
        lessThan(0.1),
      );
      final tapTargets = find.descendant(
        of: dateTimeKey,
        matching: find.byType(InkWell),
      );
      expect(tapTargets, findsNWidgets(2));
      final gapCenter = _textPartCenter(tester, combinedLabel, 10, 11).dx;
      expect(tester.getTopRight(tapTargets.first).dx, closeTo(gapCenter, 0.1));
      expect(tester.getTopLeft(tapTargets.last).dx, closeTo(gapCenter, 0.1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump();
    },
  );

  testWidgets(
    'date and time open independent pickers and preserve each other',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = BookkeepingRepository(database);
      final id = await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromMinorUnits(1250),
        occurredAt: LocalMinute.parse('2026-09-25 12:14'),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bookkeepingRepositoryProvider.overrideWithValue(repository),
            categoriesByTypeProvider.overrideWith(
              (ref, type) => Stream.value(const []),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (context) => BookkeepingPage(transactionId: id),
                    ),
                  ),
                  child: const Text('打开账单'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开账单'));
      await tester.pumpAndSettle();

      final timeDialog = find.byType(TimePickerDialog);
      final dateDialog = find.byType(DatePickerDialog);
      await tester.tapAt(
        _textPartCenter(tester, find.text('2026-09-25 12:14'), 11, 16),
      );
      await tester.pumpAndSettle();
      expect(dateDialog, findsNothing);
      expect(
        tester.widget<TimePickerDialog>(timeDialog).initialTime,
        const TimeOfDay(hour: 12, minute: 14),
      );
      Navigator.of(tester.element(timeDialog))
          .pop(const TimeOfDay(hour: 17, minute: 42));
      await tester.pumpAndSettle();
      expect(find.text('2026-09-25 17:42'), findsOneWidget);

      await tester.tapAt(
        _textPartCenter(tester, find.text('2026-09-25 17:42'), 0, 10),
      );
      await tester.pumpAndSettle();
      expect(timeDialog, findsNothing);
      expect(
        tester.widget<DatePickerDialog>(dateDialog).initialDate,
        DateTime(2026, 9, 25),
      );
      Navigator.of(tester.element(dateDialog)).pop(DateTime(2026, 9, 26));
      await tester.pumpAndSettle();
      expect(timeDialog, findsNothing);
      expect(find.text('2026-09-26 17:42'), findsOneWidget);

      await tester.tapAt(
        _textPartCenter(tester, find.text('2026-09-26 17:42'), 11, 16),
      );
      await tester.pumpAndSettle();
      final localizations = MaterialLocalizations.of(
        tester.element(timeDialog),
      );
      await tester.tap(
        find.widgetWithText(TextButton, localizations.cancelButtonLabel),
      );
      await tester.pumpAndSettle();
      expect(timeDialog, findsNothing);
      expect(find.text('2026-09-26 17:42'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.text('打开账单'), findsOneWidget);
      expect(
        (await repository.getById(id))?.occurredAt.value,
        '2026-09-26 17:42',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

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
            dateLabel: '2026-09-25',
            onDateTap: () {},
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

Offset _textPartCenter(WidgetTester tester, Finder label, int start, int end) {
  final paragraph = tester.renderObject<RenderParagraph>(label);
  final box = paragraph
      .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))
      .single;
  return paragraph.localToGlobal(box.toRect().center);
}
