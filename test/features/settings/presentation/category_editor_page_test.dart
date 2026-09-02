import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/settings/presentation/category_editor_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  testWidgets('selects a grouped icon and persists its stable code', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CategoryEditorPage(
                      args: CategoryEditorArgs(type: EntryType.expense),
                    ),
                  ),
                ),
                child: const Text('新增'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('新增'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '通勤');
    await tester.tap(find.text('交通'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.directions_car_outlined));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final categories = await BookkeepingRepository(database)
        .getCategories(EntryType.expense);
    final created = categories.singleWhere((category) => category.name == '通勤');
    expect(created.iconCode, 'directions_car');
  });

  testWidgets('keeps the delete icon clickable at the top right', (
    tester,
  ) async {
    final repository = BookkeepingRepository(database);
    final category = (await repository.getCategories(EntryType.expense)).first;
    await repository.create(
      type: EntryType.expense,
      categoryId: category.id,
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-09-01 12:00'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: CategoryEditorPage(
            args: CategoryEditorArgs(
              type: EntryType.expense,
              category: category,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final deleteFinder = find.byKey(const ValueKey('category-delete-button'));
    expect(deleteFinder, findsOneWidget);
    expect(
      tester.getCenter(deleteFinder).dx,
      greaterThan(tester.getCenter(find.text('编辑分类')).dx),
    );
    final button = tester.widget<IconButton>(deleteFinder);
    expect(button.onPressed, isNotNull);
    expect(
      button.style?.foregroundColor?.resolve({}),
      Theme.of(tester.element(deleteFinder)).colorScheme.error,
    );
    await tester.tap(deleteFinder);
    await tester.pump();
    expect(find.text('该分类已被账单使用，不能删除'), findsOneWidget);
  });
}
