import 'dart:math' as math;

import 'package:anbookkeep/core/widgets/app_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('random category colors are opaque and vivid', () {
    final color = randomVividAppColor(math.Random(7));
    final hsv = HSVColor.fromColor(color);

    expect(color.a, 1);
    expect(hsv.saturation, greaterThanOrEqualTo(.71));
    expect(hsv.value, greaterThanOrEqualTo(.81));
  });

  testWidgets('palette uses the actual canvas for picking and painting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 200,
              child: AppColorPickerSheet(
                title: '主题颜色',
                current: Color(0xFF555555),
              ),
            ),
          ),
        ),
      ),
    );

    final palette = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onPanUpdate != null,
      ),
      matching: find.byType(CustomPaint),
    );
    final size = tester.getSize(palette);
    const indicatorRadius = 8.0;
    const strokeWidth = 3.0;
    final radius = size.shortestSide / 2;
    final selectionRadius = radius - indicatorRadius - strokeWidth / 2;
    final localCenter = size.center(Offset.zero);
    final center = tester.getCenter(palette);

    expect(find.text('#555555'), findsOneWidget);
    expect(
      palette,
      paints
        ..circle()
        ..circle()
        ..circle(
          x: localCenter.dx,
          y: localCenter.dy,
          color: Colors.black,
          style: PaintingStyle.stroke,
        ),
    );

    await tester.tapAt(center);
    await tester.pump();
    expect(find.text('#FFFFFF'), findsOneWidget);

    await tester.tapAt(center.translate(selectionRadius / 2, 0));
    await tester.pump();
    expect(find.text('#FF8080'), findsOneWidget);

    await tester.dragFrom(center, Offset(radius - 1, 0));
    await tester.pumpAndSettle();
    expect(find.text('#FF0000'), findsOneWidget);
    expect(
      palette,
      paints
        ..circle()
        ..circle()
        ..circle(
          x: localCenter.dx + selectionRadius,
          y: localCenter.dy,
          radius: indicatorRadius,
          strokeWidth: strokeWidth,
          color: Colors.white,
          style: PaintingStyle.stroke,
        ),
    );
  });
}
