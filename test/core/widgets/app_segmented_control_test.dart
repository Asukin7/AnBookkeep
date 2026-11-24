import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('provides explicit regular and compact total heights', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppSegmentedButton<int>(
                key: const ValueKey('regular'),
                segments: const [
                  ButtonSegment(value: 0, label: Text('A')),
                  ButtonSegment(value: 1, label: Text('B')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
              ),
              AppSegmentedButton<int>(
                key: const ValueKey('compact'),
                compact: true,
                segments: const [
                  ButtonSegment(value: 0, label: Text('A')),
                  ButtonSegment(value: 1, label: Text('B')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('regular'))).height,
      AppSizes.segmentedControl + 8,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('compact'))).height,
      AppSizes.segmentedControl,
    );
  });

  testWidgets('a single indicator and the label color animate on selection', (
    tester,
  ) async {
    String? selected;
    var selectionChanges = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppSegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('全部')),
                ButtonSegment(value: 'expense', label: Text('支出')),
                ButtonSegment(value: 'income', label: Text('收入')),
              ],
              selected: {selected},
              onSelectionChanged: (values) {
                selectionChanges++;
                setState(() => selected = values.single);
              },
            ),
          ),
        ),
      ),
    );

    final indicator = find.descendant(
      of: find.byType(AnimatedAlign),
      matching: find.byType(FractionallySizedBox),
    );
    expect(indicator, findsOneWidget);
    final income = find.text('收入');
    Color? incomeColor() =>
        DefaultTextStyle.of(tester.element(income)).style.color;
    final start = tester.getCenter(indicator).dx;
    final destination = tester.getCenter(income).dx;
    final unselectedColor = incomeColor();
    final selectedColor = Theme.of(tester.element(income)).colorScheme.primary;
    expect(start, closeTo(tester.getCenter(find.text('全部')).dx, 0.1));

    final tapTarget = tester.widget<InkWell>(
      find.ancestor(of: income, matching: find.byType(InkWell)),
    );
    expect(tapTarget.highlightColor, Colors.transparent);
    expect(tapTarget.splashFactory, NoSplash.splashFactory);

    final gesture = await tester.startGesture(tester.getCenter(income));
    await tester.pump(AppMotion.standard);
    expect(tester.getCenter(indicator).dx, closeTo(start, 0.1));
    expect(selectionChanges, 0);

    await gesture.up();
    await tester.pump();
    await tester.pump(AppMotion.standard ~/ 2);
    expect(
      tester.getCenter(indicator).dx,
      inExclusiveRange(start, destination),
    );
    expect(incomeColor(), isNot(anyOf(unselectedColor, selectedColor)));

    await tester.pumpAndSettle();
    expect(tester.getCenter(indicator).dx, closeTo(destination, 0.1));
    expect(incomeColor(), selectedColor);
    expect(selectionChanges, 1);

    await tester.tap(income);
    await tester.pumpAndSettle();
    expect(selectionChanges, 1);
  });
}
