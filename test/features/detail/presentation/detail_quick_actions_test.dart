import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/features/detail/presentation/detail_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  testWidgets('quick actions rotate, pop from the main button and collapse', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: DetailPage()),
      ),
    );
    await tester.pumpAndSettle();

    final mainButton = find.bySemanticsLabel('记账');
    final gesture = await tester.startGesture(tester.getCenter(mainButton));
    await tester.pump(const Duration(milliseconds: 199));
    expect(find.bySemanticsLabel('收起AI记账'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 360));
    await gesture.up();
    await tester.pump();

    expect(find.bySemanticsLabel('收起AI记账'), findsOneWidget);
    expect(find.text('收起AI记账'), findsNothing);
    expect(find.byTooltip('拍照记账'), findsOneWidget);
    expect(find.byTooltip('图片记账'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('拍照记账')),
      tester.getSize(find.bySemanticsLabel('收起AI记账')),
    );
    expect(
      tester.getSize(find.byTooltip('图片记账')),
      tester.getSize(find.bySemanticsLabel('收起AI记账')),
    );
    final cameraCenter = tester.getCenter(find.byTooltip('拍照记账'));
    final imageCenter = tester.getCenter(find.byTooltip('图片记账'));
    final mainCenter = tester.getCenter(find.bySemanticsLabel('收起AI记账'));
    expect(
      imageCenter.dy - cameraCenter.dy,
      closeTo(mainCenter.dy - imageCenter.dy, 0.001),
    );
    final rotation = tester.widget<RotationTransition>(
      find.descendant(
        of: find.bySemanticsLabel('收起AI记账'),
        matching: find.byType(RotationTransition),
      ),
    );
    expect(rotation.turns.value, closeTo(1.125, 0.001));

    await tester.tap(find.bySemanticsLabel('收起AI记账'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    await tester.pump();

    expect(find.bySemanticsLabel('记账'), findsOneWidget);
    final collapsedRotation = tester.widget<RotationTransition>(
      find.descendant(
        of: find.bySemanticsLabel('记账'),
        matching: find.byType(RotationTransition),
      ),
    );
    expect(collapsedRotation.turns.value, closeTo(0, 0.001));
  });
}
