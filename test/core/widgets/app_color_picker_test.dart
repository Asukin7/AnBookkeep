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
}
