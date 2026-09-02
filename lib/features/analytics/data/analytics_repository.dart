import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AnalyticsGranularity { day, month, year }

final class AnalyticsCategoryTotal {
  const AnalyticsCategoryTotal({
    required this.id,
    required this.name,
    required this.iconCode,
    required this.colorValue,
    required this.type,
    required this.amountMinor,
  });

  final String id;
  final String name;
  final String iconCode;
  final int colorValue;
  final EntryType type;
  final int amountMinor;
}

final class AnalyticsDataset {
  const AnalyticsDataset({
    required this.totalMinor,
    required this.recordCount,
    required this.yearCount,
    required this.trendMinorByKey,
    required this.categories,
  });

  final int totalMinor;
  final int recordCount;
  final int yearCount;
  final Map<String, int> trendMinorByKey;
  final List<AnalyticsCategoryTotal> categories;
}

final class AnalyticsRepository {
  AnalyticsRepository(this._database);

  final AppDatabase _database;

  Future<AnalyticsDataset> load({
    required EntryType? type,
    required AnalyticsGranularity granularity,
    String? startDate,
    String? endDate,
  }) async {
    final summaryFilter = _filter(
      type: type,
      startDate: startDate,
      endDate: endDate,
    );
    final signedAmount = switch (type) {
      EntryType.expense => '-amount_minor',
      EntryType.income => 'amount_minor',
      null => 'CASE WHEN type = 1 THEN amount_minor ELSE -amount_minor END',
    };
    final trendAmount = type == null
        ? 'CASE WHEN type = 1 THEN amount_minor ELSE -amount_minor END'
        : 'amount_minor';
    final keyExpression = switch (granularity) {
      AnalyticsGranularity.day => 'substr(occurred_at, 9, 2)',
      AnalyticsGranularity.month => 'substr(occurred_at, 6, 2)',
      AnalyticsGranularity.year => 'substr(occurred_at, 1, 4)',
    };
    final categoryFilter = type == null
        ? null
        : _categoryFilter(type: type, startDate: startDate, endDate: endDate);

    final summaryFuture = _database
        .customSelect(
          '''SELECT COALESCE(SUM($signedAmount), 0) AS total_minor,
                COUNT(*) AS record_count,
                COUNT(DISTINCT substr(occurred_at, 1, 4)) AS year_count
         FROM transactions${summaryFilter.sql}''',
          variables: summaryFilter.variables,
          readsFrom: {_database.bookkeepingEntries},
        )
        .getSingle();
    final trendFuture = _database
        .customSelect(
          '''SELECT $keyExpression AS period_key,
                COALESCE(SUM($trendAmount), 0) AS amount_minor
         FROM transactions${summaryFilter.sql}
         GROUP BY period_key
         ORDER BY period_key''',
          variables: summaryFilter.variables,
          readsFrom: {_database.bookkeepingEntries},
        )
        .get();
    final categoryFuture = type == null
        ? Future.value(const <QueryRow>[])
        : _database
              .customSelect(
                '''SELECT c.id, c.name, c.icon_code, c.color_value, c.type,
                      COALESCE(SUM(t.amount_minor), 0) AS amount_minor
               FROM transactions AS t
               INNER JOIN categories AS c ON c.id = t.category_id
               ${categoryFilter!.sql}
               GROUP BY c.id, c.name, c.icon_code, c.color_value, c.type
               ORDER BY amount_minor DESC, c.sort_order ASC''',
                variables: categoryFilter.variables,
                readsFrom: {_database.bookkeepingEntries, _database.categories},
              )
              .get();

    final values = await Future.wait<Object>([
      summaryFuture,
      trendFuture,
      categoryFuture,
    ]);
    final summary = values[0] as QueryRow;
    final trendRows = values[1] as List<QueryRow>;
    final categoryRows = values[2] as List<QueryRow>;
    return AnalyticsDataset(
      totalMinor: summary.read<int>('total_minor'),
      recordCount: summary.read<int>('record_count'),
      yearCount: summary.read<int>('year_count'),
      trendMinorByKey: {
        for (final row in trendRows)
          row.read<String>('period_key'): row.read<int>('amount_minor'),
      },
      categories: [
        for (final row in categoryRows)
          AnalyticsCategoryTotal(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            iconCode: row.read<String>('icon_code'),
            colorValue: row.read<int>('color_value'),
            type: EntryType.fromDatabase(row.read<int>('type')),
            amountMinor: row.read<int>('amount_minor'),
          ),
      ],
    );
  }

  static _SqlFilter _filter({
    required EntryType? type,
    required String? startDate,
    required String? endDate,
  }) {
    final clauses = <String>[];
    final values = <Object>[];
    if (type != null) {
      clauses.add('type = ?');
      values.add(type.databaseValue);
    }
    if (startDate != null) {
      clauses.add('occurred_at >= ?');
      values.add('$startDate 00:00');
    }
    if (endDate != null) {
      clauses.add('occurred_at <= ?');
      values.add('$endDate 23:59');
    }
    return _SqlFilter(clauses: clauses, values: values);
  }

  static _SqlFilter _categoryFilter({
    required EntryType type,
    required String? startDate,
    required String? endDate,
  }) {
    final clauses = <String>['t.type = ?'];
    final values = <Object>[type.databaseValue];
    if (startDate != null) {
      clauses.add('t.occurred_at >= ?');
      values.add('$startDate 00:00');
    }
    if (endDate != null) {
      clauses.add('t.occurred_at <= ?');
      values.add('$endDate 23:59');
    }
    return _SqlFilter(clauses: clauses, values: values);
  }
}

final class _SqlFilter {
  const _SqlFilter({required this.clauses, required this.values});

  final List<String> clauses;
  final List<Object> values;

  String get sql => clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}';

  List<Variable<Object>> get variables => [
    for (final value in values)
      if (value is int)
        Variable<int>(value)
      else
        Variable<String>(value as String),
  ];
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(appDatabaseProvider));
});
