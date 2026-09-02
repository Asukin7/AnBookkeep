/// Moves the item at [from] onto the slot at [to].
///
/// The target index follows Flutter's `DragTarget` item-index semantics rather
/// than the insertion-index semantics used by `ReorderableListView`.
List<T> reorderItems<T>(List<T> items, int from, int to) {
  if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
    throw RangeError('排序索引超出范围');
  }
  if (from == to) return List<T>.of(items);
  final reordered = List<T>.of(items);
  final item = reordered.removeAt(from);
  reordered.insert(to.clamp(0, reordered.length), item);
  return reordered;
}
