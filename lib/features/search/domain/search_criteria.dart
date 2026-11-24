import 'package:anbookkeep/features/bookkeeping/domain/bookkeeping_search_order.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';

/// Immutable value used as the single source of truth for a search request.
final class SearchCriteria {
  SearchCriteria({
    this.keyword = '',
    this.type,
    this.startDate,
    this.endDate,
    Iterable<String> categoryIds = const [],
    this.minAmountMinor,
    this.maxAmountMinor,
    this.order = BookkeepingSearchOrder.timeDescending,
  }) : categoryIds = List.unmodifiable(categoryIds.toSet().toList()..sort());

  final String keyword;
  final EntryType? type;
  final String? startDate;
  final String? endDate;
  final List<String> categoryIds;
  final int? minAmountMinor;
  final int? maxAmountMinor;
  final BookkeepingSearchOrder order;

  SearchCriteria copyWith({
    String? keyword,
    EntryType? type,
    bool clearType = false,
    String? startDate,
    String? endDate,
    bool clearStartDate = false,
    bool clearEndDate = false,
    Iterable<String>? categoryIds,
    int? minAmountMinor,
    int? maxAmountMinor,
    bool clearMinAmount = false,
    bool clearMaxAmount = false,
    BookkeepingSearchOrder? order,
  }) {
    return SearchCriteria(
      keyword: keyword ?? this.keyword,
      type: clearType ? null : type ?? this.type,
      startDate: clearStartDate ? null : startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      categoryIds: categoryIds ?? this.categoryIds,
      minAmountMinor: clearMinAmount
          ? null
          : minAmountMinor ?? this.minAmountMinor,
      maxAmountMinor: clearMaxAmount
          ? null
          : maxAmountMinor ?? this.maxAmountMinor,
      order: order ?? this.order,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SearchCriteria &&
            other.keyword == keyword &&
            other.type == type &&
            other.startDate == startDate &&
            other.endDate == endDate &&
            other.minAmountMinor == minAmountMinor &&
            other.maxAmountMinor == maxAmountMinor &&
            other.order == order &&
            _sameItems(other.categoryIds, categoryIds);
  }

  @override
  int get hashCode => Object.hash(
    keyword,
    type,
    startDate,
    endDate,
    minAmountMinor,
    maxAmountMinor,
    order,
    Object.hashAll(categoryIds),
  );

  static bool _sameItems(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
