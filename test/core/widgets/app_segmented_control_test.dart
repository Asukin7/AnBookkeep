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
}
