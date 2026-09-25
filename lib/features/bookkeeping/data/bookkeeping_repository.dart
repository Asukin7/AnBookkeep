import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/database/database_provider.dart';
import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/domain/historical_note.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final class BookkeepingRecord {
  const BookkeepingRecord({required this.entry, required this.category});

  final TransactionRow entry;
  final CategoryRow category;

  EntryType get type => EntryType.fromDatabase(entry.type);
  Money get amount => Money.fromMinorUnits(entry.amountMinor);
  LocalMinute get occurredAt => LocalMinute.parse(entry.occurredAt);
  String get displayName {
    final note = entry.note?.trim();
    return note == null || note.isEmpty ? category.name : note;
  }
}

final class BookkeepingCreateInput {
  const BookkeepingCreateInput({
    required this.type,
    required this.categoryId,
    required this.amount,
    required this.occurredAt,
    this.note,
  });

  final EntryType type;
  final String categoryId;
  final Money amount;
  final LocalMinute occurredAt;
  final String? note;
}

final class BookkeepingImportInput {
  const BookkeepingImportInput({
    required this.type,
    required this.categoryName,
    required this.categoryColorValue,
    required this.amount,
    required this.occurredAt,
    this.note,
  });

  final EntryType type;
  final String categoryName;
  final int categoryColorValue;
  final Money amount;
  final LocalMinute occurredAt;
  final String? note;
}

final class BookkeepingImportResult {
  const BookkeepingImportResult({
    required this.importedCount,
    required this.createdCategoryCount,
  });

  final int importedCount;
  final int createdCategoryCount;
}

final class BookkeepingRepository {
  BookkeepingRepository(this._database);

  final AppDatabase _database;
  final Uuid _uuid = const Uuid();

  Stream<List<CategoryRow>> watchCategories(EntryType type) {
    final query = _database.select(_database.categories)
      ..where((row) => row.type.equals(type.databaseValue))
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.watch();
  }

  Future<List<CategoryRow>> getCategories(EntryType type) {
    final query = _database.select(_database.categories)
      ..where((row) => row.type.equals(type.databaseValue))
      ..orderBy([
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.createdAt),
        (row) => OrderingTerm.asc(row.id),
      ]);
    return query.get();
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    required String iconCode,
    required int colorValue,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 32) {
      throw const AppValidationException('分类名称长度需为1-32个字符');
    }
    final current = await (_database.select(
      _database.categories,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (current == null) throw const AppValidationException('分类不存在或已被删除');
    await _validateCategoryNameAvailable(
      type: EntryType.fromDatabase(current.type),
      name: normalized,
      excludingId: id,
    );
    final affected =
        await (_database.update(
          _database.categories,
        )..where((row) => row.id.equals(id))).write(
          CategoriesCompanion(
            name: Value(normalized),
            iconCode: Value(iconCode),
            colorValue: Value(colorValue),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    if (affected != 1) {
      throw const AppValidationException('分类不存在或已被删除');
    }
  }

  Future<String> createCategory({
    required EntryType type,
    required String name,
    required String iconCode,
    required int colorValue,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty || normalized.length > 32) {
      throw const AppValidationException('分类名称长度需为1-32个字符');
    }
    await _validateCategoryNameAvailable(type: type, name: normalized);
    final existing =
        await (_database.select(_database.categories)
              ..where((row) => row.type.equals(type.databaseValue))
              ..orderBy([(row) => OrderingTerm.desc(row.sortOrder)])
              ..limit(1))
            .getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v7();
    await _database
        .into(_database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            type: type.databaseValue,
            name: normalized,
            iconCode: iconCode,
            colorValue: colorValue,
            sortOrder: (existing?.sortOrder ?? -1) + 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> deleteCategory(String id) async {
    if (await isCategoryUsed(id)) {
      throw const AppValidationException('该分类已被账单使用，不能删除');
    }
    final affected = await (_database.delete(
      _database.categories,
    )..where((row) => row.id.equals(id))).go();
    if (affected != 1) {
      throw const AppValidationException('分类不存在或已被删除');
    }
  }

  Future<void> reorderCategories({
    required EntryType type,
    required List<String> orderedIds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _database.transaction(() async {
      await _database.batch((batch) {
        for (var index = 0; index < orderedIds.length; index++) {
          batch.update(
            _database.categories,
            CategoriesCompanion(sortOrder: Value(index), updatedAt: Value(now)),
            where: (row) =>
                row.id.equals(orderedIds[index]) &
                row.type.equals(type.databaseValue),
          );
        }
      });
    });
  }

  Future<bool> isCategoryUsed(String id) async {
    final query = _database.selectOnly(_database.bookkeepingEntries)
      ..addColumns([_database.bookkeepingEntries.id.count()])
      ..where(_database.bookkeepingEntries.categoryId.equals(id));
    final row = await query.getSingle();
    return (row.read(_database.bookkeepingEntries.id.count()) ?? 0) > 0;
  }

  Future<String?> latestMonth() async {
    final row =
        await (_database.select(_database.bookkeepingEntries)
              ..orderBy([
                (entry) => OrderingTerm.desc(entry.occurredAt),
                (entry) => OrderingTerm.desc(entry.createdAt),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row?.occurredAt.substring(0, 7);
  }

  Future<({int minYear, int maxYear})?> dataYearRange() async {
    final row = await _database
        .customSelect(
          '''SELECT MIN(substr(occurred_at, 1, 4)) AS min_year,
                    MAX(substr(occurred_at, 1, 4)) AS max_year
             FROM transactions''',
          readsFrom: {_database.bookkeepingEntries},
        )
        .getSingle();
    final minimum = row.readNullable<String>('min_year');
    final maximum = row.readNullable<String>('max_year');
    if (minimum == null || maximum == null) return null;
    return (minYear: int.parse(minimum), maxYear: int.parse(maximum));
  }

  Future<List<BookkeepingRecord>> getYear(int year) {
    _validateYear(year);
    return search(
      startDate: '${year.toString().padLeft(4, '0')}-01-01',
      endDate: '${year.toString().padLeft(4, '0')}-12-31',
    );
  }

  Future<int?> previousDataYear(int year) async {
    _validateYear(year);
    final start = '${year.toString().padLeft(4, '0')}-01-01 00:00';
    final row =
        await ((_database.select(_database.bookkeepingEntries)
              ..where((entry) => entry.occurredAt.isSmallerThanValue(start))
              ..orderBy([(entry) => OrderingTerm.desc(entry.occurredAt)])
              ..limit(1))
            .getSingleOrNull());
    return row == null ? null : int.parse(row.occurredAt.substring(0, 4));
  }

  Future<int?> nextDataYear(int year) async {
    _validateYear(year);
    if (year == 9999) return null;
    final nextYear = '${(year + 1).toString().padLeft(4, '0')}-01-01 00:00';
    final row =
        await ((_database.select(_database.bookkeepingEntries)
              ..where(
                (entry) => entry.occurredAt.isBiggerOrEqualValue(nextYear),
              )
              ..orderBy([(entry) => OrderingTerm.asc(entry.occurredAt)])
              ..limit(1))
            .getSingleOrNull());
    return row == null ? null : int.parse(row.occurredAt.substring(0, 4));
  }

  Future<BookkeepingRecord?> getById(String id) async {
    final query = _database.select(_database.bookkeepingEntries).join([
      innerJoin(
        _database.categories,
        _database.categories.id.equalsExp(
          _database.bookkeepingEntries.categoryId,
        ),
      ),
    ])..where(_database.bookkeepingEntries.id.equals(id));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return BookkeepingRecord(
      entry: row.readTable(_database.bookkeepingEntries),
      category: row.readTable(_database.categories),
    );
  }

  Future<List<BookkeepingRecord>> search({
    String? keyword,
    EntryType? type,
    String? startDate,
    String? endDate,
    Set<String> categoryIds = const {},
    int? minAmountMinor,
    int? maxAmountMinor,
    int? limit,
    int? offset,
  }) async {
    final query = _database.select(_database.bookkeepingEntries).join([
      innerJoin(
        _database.categories,
        _database.categories.id.equalsExp(
          _database.bookkeepingEntries.categoryId,
        ),
      ),
    ]);
    final normalizedKeyword = keyword?.trim();
    if (type != null) {
      query.where(_database.bookkeepingEntries.type.equals(type.databaseValue));
    }
    if (normalizedKeyword != null && normalizedKeyword.isNotEmpty) {
      final escapedKeyword = normalizedKeyword
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      query.where(
        _database.bookkeepingEntries.note.like(
          '%$escapedKeyword%',
          escapeChar: r'\',
        ),
      );
    }
    if (startDate != null) {
      query.where(
        _database.bookkeepingEntries.occurredAt.isBiggerOrEqualValue(
          '$startDate 00:00',
        ),
      );
    }
    if (endDate != null) {
      query.where(
        _database.bookkeepingEntries.occurredAt.isSmallerOrEqualValue(
          '$endDate 23:59',
        ),
      );
    }
    if (categoryIds.isNotEmpty) {
      query.where(_database.categories.id.isIn(categoryIds));
    }
    if (minAmountMinor != null) {
      query.where(
        _database.bookkeepingEntries.amountMinor.isBiggerOrEqualValue(
          minAmountMinor,
        ),
      );
    }
    if (maxAmountMinor != null) {
      query.where(
        _database.bookkeepingEntries.amountMinor.isSmallerOrEqualValue(
          maxAmountMinor,
        ),
      );
    }
    query.orderBy([
      OrderingTerm.desc(_database.bookkeepingEntries.occurredAt),
      OrderingTerm.desc(_database.bookkeepingEntries.createdAt),
      OrderingTerm.desc(_database.bookkeepingEntries.id),
    ]);
    if (limit != null) query.limit(limit, offset: offset);
    final rows = await query.get();
    return [
      for (final row in rows)
        BookkeepingRecord(
          entry: row.readTable(_database.bookkeepingEntries),
          category: row.readTable(_database.categories),
        ),
    ];
  }

  Future<({String latestMonth, List<BookkeepingRecord> records})?>
  searchLatestYear({
    String? keyword,
    EntryType? type,
    String? startDate,
    String? endDate,
    Set<String> categoryIds = const {},
    int? minAmountMinor,
    int? maxAmountMinor,
  }) async {
    final clauses = <String>[];
    final variables = <Variable<Object>>[];
    final normalizedKeyword = keyword?.trim();
    if (type != null) {
      clauses.add('t.type = ?');
      variables.add(Variable<int>(type.databaseValue));
    }
    if (normalizedKeyword != null && normalizedKeyword.isNotEmpty) {
      final escapedKeyword = normalizedKeyword
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      clauses.add("t.note LIKE ? ESCAPE '\\'");
      variables.add(Variable<String>('%$escapedKeyword%'));
    }
    if (startDate != null) {
      clauses.add('t.occurred_at >= ?');
      variables.add(Variable<String>('$startDate 00:00'));
    }
    if (endDate != null) {
      clauses.add('t.occurred_at <= ?');
      variables.add(Variable<String>('$endDate 23:59'));
    }
    if (categoryIds.isNotEmpty) {
      clauses.add(
        'c.id IN (${List.filled(categoryIds.length, '?').join(',')})',
      );
      variables.addAll(categoryIds.map(Variable<String>.new));
    }
    if (minAmountMinor != null) {
      clauses.add('t.amount_minor >= ?');
      variables.add(Variable<int>(minAmountMinor));
    }
    if (maxAmountMinor != null) {
      clauses.add('t.amount_minor <= ?');
      variables.add(Variable<int>(maxAmountMinor));
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await _database
        .customSelect(
          '''
WITH filtered AS (
  SELECT t.id AS entry_id,
         t.type AS entry_type,
         t.category_id AS entry_category_id,
         t.amount_minor,
         t.note,
         t.occurred_at,
         t.created_at AS entry_created_at,
         t.updated_at AS entry_updated_at,
         c.id AS category_row_id,
         c.type AS category_type,
         c.name AS category_name,
         c.icon_code,
         c.color_value,
         c.sort_order,
         c.created_at AS category_created_at,
         c.updated_at AS category_updated_at
  FROM transactions AS t
  INNER JOIN categories AS c ON c.id = t.category_id
  $where
), latest AS (
  SELECT substr(MAX(occurred_at), 1, 7) AS latest_month,
         substr(MAX(occurred_at), 1, 4) AS latest_year
  FROM filtered
)
SELECT filtered.*, latest.latest_month
FROM filtered CROSS JOIN latest
WHERE substr(filtered.occurred_at, 1, 4) = latest.latest_year
ORDER BY filtered.occurred_at DESC,
         filtered.entry_created_at DESC,
         filtered.entry_id DESC
''',
          variables: variables,
          readsFrom: {_database.bookkeepingEntries, _database.categories},
        )
        .get();
    if (rows.isEmpty) return null;
    return (
      latestMonth: rows.first.read<String>('latest_month'),
      records: [for (final row in rows) _recordFromLatestYearRow(row)],
    );
  }

  static BookkeepingRecord _recordFromLatestYearRow(QueryRow row) {
    return BookkeepingRecord(
      entry: TransactionRow(
        id: row.read<String>('entry_id'),
        type: row.read<int>('entry_type'),
        categoryId: row.read<String>('entry_category_id'),
        amountMinor: row.read<int>('amount_minor'),
        note: row.readNullable<String>('note'),
        occurredAt: row.read<String>('occurred_at'),
        createdAt: row.read<int>('entry_created_at'),
        updatedAt: row.read<int>('entry_updated_at'),
      ),
      category: CategoryRow(
        id: row.read<String>('category_row_id'),
        type: row.read<int>('category_type'),
        name: row.read<String>('category_name'),
        iconCode: row.read<String>('icon_code'),
        colorValue: row.read<int>('color_value'),
        sortOrder: row.read<int>('sort_order'),
        createdAt: row.read<int>('category_created_at'),
        updatedAt: row.read<int>('category_updated_at'),
      ),
    );
  }

  Future<List<HistoricalNote>> getHistoricalNotes({
    required bool smartSort,
    String? categoryId,
    int? amountMinor,
    int? minuteOfDay,
    int limit = 20,
    DateTime? now,
  }) async {
    if (minuteOfDay != null && (minuteOfDay < 0 || minuteOfDay >= 1440)) {
      throw ArgumentError.value(minuteOfDay, 'minuteOfDay', '必须在0-1439之间');
    }
    final scoreColumns = <String>[];
    final values = <Object>[];
    if (smartSort && categoryId != null) {
      scoreColumns.add(
        'AVG(CASE WHEN category_id = ? THEN 1.0 ELSE 0.0 END) '
        'AS category_affinity',
      );
      values.add(categoryId);
    }
    if (smartSort && amountMinor != null) {
      scoreColumns.add(
        'AVG(1.0 / (1.0 + ABS(amount_minor - ?) * 1.0 / MAX(?, 100))) '
        'AS amount_similarity',
      );
      values
        ..add(amountMinor)
        ..add(amountMinor);
    }
    if (smartSort && minuteOfDay != null) {
      scoreColumns.add(
        'AVG(1.0 / (1.0 + MIN(ABS(minute_of_day - ?), '
        '1440 - ABS(minute_of_day - ?)) / 60.0)) AS minute_similarity',
      );
      values
        ..add(minuteOfDay)
        ..add(minuteOfDay);
    }
    final optionalColumns = scoreColumns.isEmpty
        ? ''
        : ',\n       ${scoreColumns.join(',\n       ')}';
    final candidateLimit = smartSort
        ? (limit * 25 < 200 ? 200 : limit * 25)
        : limit;
    final rows = await _database
        .customSelect(
          '''
WITH note_entries AS (
  SELECT TRIM(note) AS note_value,
         category_id,
         amount_minor,
         occurred_at,
         CAST(SUBSTR(occurred_at, 12, 2) AS INTEGER) * 60 +
           CAST(SUBSTR(occurred_at, 15, 2) AS INTEGER) AS minute_of_day
  FROM transactions
  WHERE note IS NOT NULL AND TRIM(note) <> ''
)
SELECT note_value,
       COUNT(*) AS use_count,
       MAX(occurred_at) AS last_used_at$optionalColumns
FROM note_entries
GROUP BY note_value
ORDER BY use_count DESC, last_used_at DESC, note_value ASC
LIMIT ?
''',
          variables: [
            for (final value in values)
              if (value is int)
                Variable<int>(value)
              else
                Variable<String>(value as String),
            Variable<int>(candidateLimit),
          ],
          readsFrom: {_database.bookkeepingEntries},
        )
        .get();
    final notes = [
      for (final row in rows)
        HistoricalNote(
          value: row.read<String>('note_value'),
          useCount: row.read<int>('use_count'),
          lastUsedAt: LocalMinute.parse(row.read<String>('last_used_at')),
          categoryAffinity: categoryId == null || !smartSort
              ? null
              : row.read<double>('category_affinity'),
          amountSimilarity: amountMinor == null || !smartSort
              ? null
              : row.read<double>('amount_similarity'),
          minuteSimilarity: minuteOfDay == null || !smartSort
              ? null
              : row.read<double>('minute_similarity'),
        ),
    ];
    return rankHistoricalNotes(
      notes,
      smartSort: smartSort,
      now: now ?? DateTime.now(),
      limit: limit,
    );
  }

  Future<String> create({
    required EntryType type,
    required String categoryId,
    required Money amount,
    required LocalMinute occurredAt,
    String? note,
  }) async {
    await _validateCategory(categoryId, type);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v7();
    await _database
        .into(_database.bookkeepingEntries)
        .insert(
          BookkeepingEntriesCompanion.insert(
            id: id,
            type: type.databaseValue,
            categoryId: categoryId,
            amountMinor: amount.minorUnits,
            note: Value(_normalizeNote(note)),
            occurredAt: occurredAt.value,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<List<String>> createBatch(List<BookkeepingCreateInput> entries) {
    return _database.transaction(() async {
      if (entries.isEmpty) return const <String>[];

      final requestedCategoryIds = {
        for (final entry in entries) entry.categoryId,
      };
      final categories = await (_database.select(
        _database.categories,
      )..where((row) => row.id.isIn(requestedCategoryIds))).get();
      final categoryTypes = {
        for (final category in categories) category.id: category.type,
      };
      for (final entry in entries) {
        final categoryType = categoryTypes[entry.categoryId];
        if (categoryType == null) {
          throw const AppValidationException('分类不存在');
        }
        if (categoryType != entry.type.databaseValue) {
          throw const AppValidationException('分类与收支类型不匹配');
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final ids = [for (final _ in entries) _uuid.v7()];
      await _database.batch((batch) {
        batch.insertAll(_database.bookkeepingEntries, [
          for (var index = 0; index < entries.length; index++)
            BookkeepingEntriesCompanion.insert(
              id: ids[index],
              type: entries[index].type.databaseValue,
              categoryId: entries[index].categoryId,
              amountMinor: entries[index].amount.minorUnits,
              note: Value(_normalizeNote(entries[index].note)),
              occurredAt: entries[index].occurredAt.value,
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
      return ids;
    });
  }

  Future<BookkeepingImportResult> importBatch(
    List<BookkeepingImportInput> entries,
  ) {
    return _database.transaction(() async {
      final allCategories = await _database.select(_database.categories).get();
      final categoryIds = <String, String>{};
      final nextSortOrders = <EntryType, int>{
        EntryType.expense: 0,
        EntryType.income: 0,
      };
      for (final category in allCategories) {
        final type = EntryType.fromDatabase(category.type);
        categoryIds[_categoryKey(type, category.name)] = category.id;
        if (category.sortOrder >= nextSortOrders[type]!) {
          nextSortOrders[type] = category.sortOrder + 1;
        }
      }

      var createdCategoryCount = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final newCategories = <CategoriesCompanion>[];
      final newEntries = <BookkeepingEntriesCompanion>[];
      for (final entry in entries) {
        final key = _categoryKey(entry.type, entry.categoryName);
        var categoryId = categoryIds[key];
        if (categoryId == null) {
          categoryId = _uuid.v7();
          newCategories.add(
            CategoriesCompanion.insert(
              id: categoryId,
              type: entry.type.databaseValue,
              name: entry.categoryName.trim(),
              iconCode: 'other',
              colorValue: entry.categoryColorValue,
              sortOrder: nextSortOrders[entry.type]!,
              createdAt: now,
              updatedAt: now,
            ),
          );
          nextSortOrders[entry.type] = nextSortOrders[entry.type]! + 1;
          categoryIds[key] = categoryId;
          createdCategoryCount++;
        }
        newEntries.add(
          BookkeepingEntriesCompanion.insert(
            id: _uuid.v7(),
            type: entry.type.databaseValue,
            categoryId: categoryId,
            amountMinor: entry.amount.minorUnits,
            note: Value(_normalizeNote(entry.note)),
            occurredAt: entry.occurredAt.value,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _database.batch((batch) {
        if (newCategories.isNotEmpty) {
          batch.insertAll(_database.categories, newCategories);
        }
        if (newEntries.isNotEmpty) {
          batch.insertAll(_database.bookkeepingEntries, newEntries);
        }
      });
      return BookkeepingImportResult(
        importedCount: entries.length,
        createdCategoryCount: createdCategoryCount,
      );
    });
  }

  Future<void> update({
    required String id,
    required EntryType type,
    required String categoryId,
    required Money amount,
    required LocalMinute occurredAt,
    String? note,
  }) async {
    await _validateCategory(categoryId, type);
    final affected =
        await (_database.update(
          _database.bookkeepingEntries,
        )..where((row) => row.id.equals(id))).write(
          BookkeepingEntriesCompanion(
            type: Value(type.databaseValue),
            categoryId: Value(categoryId),
            amountMinor: Value(amount.minorUnits),
            note: Value(_normalizeNote(note)),
            occurredAt: Value(occurredAt.value),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
    if (affected != 1) {
      throw const AppValidationException('账单不存在或已被删除');
    }
  }

  Future<void> delete(String id) async {
    final affected = await (_database.delete(
      _database.bookkeepingEntries,
    )..where((row) => row.id.equals(id))).go();
    if (affected != 1) {
      throw const AppValidationException('账单不存在或已被删除');
    }
  }

  Future<void> _validateCategory(String categoryId, EntryType type) async {
    final query = _database.select(_database.categories)
      ..where((row) => row.id.equals(categoryId));
    final category = await query.getSingleOrNull();
    if (category == null) {
      throw const AppValidationException('分类不存在');
    }
    if (category.type != type.databaseValue) {
      throw const AppValidationException('分类与收支类型不匹配');
    }
  }

  Future<void> _validateCategoryNameAvailable({
    required EntryType type,
    required String name,
    String? excludingId,
  }) async {
    final query = _database.select(_database.categories)
      ..where(
        (row) =>
            row.type.equals(type.databaseValue) & row.name.equals(name.trim()),
      );
    if (excludingId != null) {
      query.where((row) => row.id.equals(excludingId).not());
    }
    if (await query.getSingleOrNull() != null) {
      throw const AppValidationException('该类型下已存在同名分类');
    }
  }

  static String? _normalizeNote(String? note) {
    final normalized = note?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _categoryKey(EntryType type, String name) =>
      '${type.databaseValue}\u0000${name.trim()}';

  static void _validateYear(int year) {
    AppDatePolicy.validateYear(year);
  }
}

final bookkeepingRepositoryProvider = Provider<BookkeepingRepository>((ref) {
  return BookkeepingRepository(ref.watch(appDatabaseProvider));
});

final categoriesByTypeProvider =
    StreamProvider.family<List<CategoryRow>, EntryType>((ref, type) {
      return ref.watch(bookkeepingRepositoryProvider).watchCategories(type);
    });
