import 'package:anbookkeep/features/search/domain/search_criteria.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category order does not create a different provider key', () {
    final first = SearchCriteria(categoryIds: const ['b', 'a', 'a']);
    final second = SearchCriteria(categoryIds: const ['a', 'b']);

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.categoryIds, const ['a', 'b']);
  });
}
