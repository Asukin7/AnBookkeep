import 'package:anbookkeep/core/collections/reorder_items.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moves an item forward onto the target slot', () {
    expect(reorderItems(['a', 'b', 'c'], 0, 1), ['b', 'a', 'c']);
  });

  test('moves an item backward onto the target slot', () {
    expect(reorderItems(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
  });
}
