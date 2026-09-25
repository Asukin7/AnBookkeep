import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/search/domain/search_criteria.dart';

Future<({String latestMonth, List<BookkeepingRecord> records})?>
loadInitialSearchYear(
  BookkeepingRepository repository,
  SearchCriteria criteria,
) {
  return repository.searchLatestYear(
    keyword: criteria.keyword,
    type: criteria.type,
    startDate: criteria.startDate,
    endDate: criteria.endDate,
    categoryIds: criteria.categoryIds.toSet(),
    minAmountMinor: criteria.minAmountMinor,
    maxAmountMinor: criteria.maxAmountMinor,
  );
}

Future<int?> findOlderSearchYear(
  BookkeepingRepository repository,
  SearchCriteria criteria,
  int year,
) async {
  final previousDay = '${(year - 1).toString().padLeft(4, '0')}-12-31';
  final records = await _search(
    repository,
    criteria,
    endDate: _earliestDate(criteria.endDate, previousDay),
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

Future<List<BookkeepingRecord>> _search(
  BookkeepingRepository repository,
  SearchCriteria criteria, {
  String? startDate,
  String? endDate,
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
