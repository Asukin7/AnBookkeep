import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('built-in category icon catalog is grouped and keeps stable codes', () {
    expect(categoryIconOptions, hasLength(97));
    expect(categoryIconCodes.toSet(), hasLength(categoryIconCodes.length));
    for (final group in CategoryIconGroup.values) {
      expect(categoryIconOptionsForGroup(group), isNotEmpty);
    }

    expect(categoryIconData('food'), Icons.restaurant_outlined);
    expect(categoryIconData('part_time'), Icons.work_outline);
    expect(categoryIconData('refund'), Icons.currency_exchange_outlined);
    expect(categoryIconData('other'), Icons.category_outlined);
    expect(categoryIconData('directions_car'), Icons.directions_car_outlined);
    expect(categoryIconData('unknown-code'), Icons.category_outlined);
  });
}
