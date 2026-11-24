import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/bookkeeping_search_order.dart';
import 'package:anbookkeep/features/search/domain/search_criteria.dart';

Future<({String anchorMonth, List<BookkeepingRecord> records})?>
loadInitialSearchYear(
  BookkeepingRepository repository,
  SearchCriteria criteria,
) {
  return repository.searchBoundaryYear(
    keyword: criteria.keyword,
    type: criteria.type,
    startDate: criteria.startDate,
    endDate: criteria.endDate,
    categoryIds: criteria.categoryIds.toSet(),
    minAmountMinor: criteria.minAmountMinor,
    maxAmountMinor: criteria.maxAmountMinor,
    oldestFirst: criteria.order == BookkeepingSearchOrder.timeAscending,
  );
}

Future<int?> findOlderSearchYear(
  BookkeepingRepository repository,
  SearchCriteria criteria,
  int year,
) async {
  if (year <= AppDatePolicy.minimumSupportedYear) return null;
  final previousDay = '${(year - 1).toString().padLeft(4, '0')}-12-31';
  final records = await _search(
    repository,
    criteria,
    endDate: _earliestDate(criteria.endDate, previousDay),
    order: BookkeepingSearchOrder.timeDescending,
    limit: 1,
  );
  return records.firstOrNull?.occurredAt.toDateTime().year;
}

Future<int?> findNewerSearchYear(
  BookkeepingRepository repository,
  SearchCriteria criteria,
  int year,
) async {
  if (year >= AppDatePolicy.maximumSupportedYear) return null;
  final nextDay = '${(year + 1).toString().padLeft(4, '0')}-01-01';
  final records = await _search(
    repository,
    criteria,
    startDate: _latestDate(criteria.startDate, nextDay),
    order: BookkeepingSearchOrder.timeAscending,
    limit: 1,
  );
  return records.firstOrNull?.occurredAt.toDateTime().year;
}

Future<List<BookkeepingRecord>> loadSearchYear(
  BookkeepingRepository repository,
  SearchCriteria criteria,
  int year,
) {
  final rangeStart = '${year.toString().padLeft(4, '0')}-01-01';
  final rangeEnd = '${year.toString().padLeft(4, '0')}-12-31';
  return _search(
    repository,
    criteria,
    startDate: _latestDate(criteria.startDate, rangeStart),
    endDate: _earliestDate(criteria.endDate, rangeEnd),
  );
}

Future<({List<BookkeepingRecord> records, bool hasMore})> loadAmountSearchPage(
  BookkeepingRepository repository,
  SearchCriteria criteria, {
  BookkeepingRecord? after,
  int pageSize = 100,
}) async {
  assert(criteria.order.isAmount && pageSize > 0);
  final records = await _search(
    repository,
    criteria,
    afterAmountRecord: after,
    limit: pageSize + 1,
  );
  final hasMore = records.length > pageSize;
  if (hasMore) records.removeLast();
  return (records: records, hasMore: hasMore);
}

Future<List<BookkeepingRecord>> _search(
  BookkeepingRepository repository,
  SearchCriteria criteria, {
  String? startDate,
  String? endDate,
  BookkeepingSearchOrder? order,
  BookkeepingRecord? afterAmountRecord,
  int? limit,
}) {
  return repository.search(
    keyword: criteria.keyword,
    type: criteria.type,
    startDate: startDate ?? criteria.startDate,
    endDate: endDate ?? criteria.endDate,
    categoryIds: criteria.categoryIds.toSet(),
    minAmountMinor: criteria.minAmountMinor,
    maxAmountMinor: criteria.maxAmountMinor,
    order: order ?? criteria.order,
    afterAmountRecord: afterAmountRecord,
    limit: limit,
  );
}

String? _latestDate(String? first, String? second) {
  if (first == null) return second;
  if (second == null) return first;
  return first.compareTo(second) >= 0 ? first : second;
}

String? _earliestDate(String? first, String? second) {
  if (first == null) return second;
  if (second == null) return first;
  return first.compareTo(second) <= 0 ? first : second;
}
