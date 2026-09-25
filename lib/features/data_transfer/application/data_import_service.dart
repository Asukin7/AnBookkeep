import 'dart:math' as math;
import 'dart:isolate';

import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/data_transfer/data/tabular_file_codec.dart';
import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dataImportServiceProvider = Provider<DataImportService>((ref) {
  return DataImportService(ref.watch(bookkeepingRepositoryProvider));
});

final class DataImportService {
  DataImportService(this._repository);

  static const _logger = AppLogger('DataImport');
  final BookkeepingRepository _repository;

  ImportMapping autoMapping(TabularDocument document) {
    final header = document.rows[document.detectedHeaderIndex];
    return ImportMapping(
      headerRowIndex: document.detectedHeaderIndex,
      columns: TabularFileCodec.autoMap(header),
    );
  }

  Future<ImportPreview> preview(
    TabularDocument document,
    ImportMapping mapping,
  ) async {
    final missing = <ImportField>{};
    for (final field in ImportField.values.where((field) => field.required)) {
      if (field == ImportField.type && mapping.fixedType != null) continue;
      if (mapping.columns[field] == null) missing.add(field);
    }
    if (mapping.headerRowIndex < 0 ||
        mapping.headerRowIndex >= document.rows.length) {
      return ImportPreview(
        entries: const [],
        issues: const [],
        dataRowCount: 0,
        missingMappingFields: missing,
        newCategoryCount: 0,
      );
    }

    final parsed = await Isolate.run(
      () => _parseRows(document: document, mapping: mapping, missing: missing),
    );
    final entries = parsed.entries;
    final issues = parsed.issues;
    final dataRowCount = parsed.dataRowCount;

    final existing = <String>{};
    for (final type in EntryType.values) {
      for (final category in await _repository.getCategories(type)) {
        existing.add(_categoryKey(type, category.name));
      }
    }
    final newCategories = <String>{
      for (final entry in entries)
        if (!existing.contains(_categoryKey(entry.type, entry.categoryName)))
          _categoryKey(entry.type, entry.categoryName),
    };
    _logger.debug(
      'import_preview_built',
      fields: {
        'dataRows': dataRowCount,
        'validRows': entries.length,
        'invalidRows': issues.length,
        'newCategories': newCategories.length,
        'headerRow': mapping.headerRowIndex + 1,
      },
    );
    return ImportPreview(
      entries: entries,
      issues: issues,
      dataRowCount: dataRowCount,
      missingMappingFields: missing,
      newCategoryCount: newCategories.length,
    );
  }

  static ({
    List<PreparedImportEntry> entries,
    List<ImportIssue> issues,
    int dataRowCount,
  })
  _parseRows({
    required TabularDocument document,
    required ImportMapping mapping,
    required Set<ImportField> missing,
  }) {
    final entries = <PreparedImportEntry>[];
    final issues = <ImportIssue>[];
    var dataRowCount = 0;
    for (
      var index = mapping.headerRowIndex + 1;
      index < document.rows.length;
      index++
    ) {
      final row = document.rows[index];
      if (row.every(
        (value) => value == null || value.toString().trim().isEmpty,
      )) {
        continue;
      }
      dataRowCount++;
      if (missing.isNotEmpty) continue;
      try {
        final amountText = _value(row, mapping.columns[ImportField.amount]!);
        final type =
            mapping.fixedType ??
            _parseType(
              _value(row, mapping.columns[ImportField.type]!),
              amountText,
            );
        final category = _value(
          row,
          mapping.columns[ImportField.category]!,
        ).trim();
        if (category.isEmpty || category.length > 32) {
          throw const FormatException('分类名称长度需为1-32个字符');
        }
        final noteColumn = mapping.columns[ImportField.note];
        final rawNote = noteColumn == null ? '' : _value(row, noteColumn);
        final note = rawNote.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
        if (note.length > 1024) throw const FormatException('备注不能超过1024个字符');
        entries.add(
          PreparedImportEntry(
            type: type,
            categoryName: category,
            occurredAt: _parseDate(
              _object(row, mapping.columns[ImportField.occurredAt]!),
            ),
            amount: _parseAmount(amountText),
            sourceRowNumber: index + 1,
            note: note.isEmpty ? null : note,
          ),
        );
      } on Object catch (error) {
        issues.add(
          ImportIssue(rowNumber: index + 1, message: _friendlyError(error)),
        );
      }
    }
    return (entries: entries, issues: issues, dataRowCount: dataRowCount);
  }

  Future<ImportCommitResult> commit(ImportPreview preview) async {
    final startedAt = DateTime.now();
    final random = math.Random.secure();
    final colors = <String, int>{};
    final inputs = <BookkeepingImportInput>[
      for (final entry in preview.entries)
        BookkeepingImportInput(
          type: entry.type,
          categoryName: entry.categoryName,
          categoryColorValue: colors.putIfAbsent(
            _categoryKey(entry.type, entry.categoryName),
            () => _randomVividColor(random),
          ),
          amount: entry.amount,
          occurredAt: entry.occurredAt,
          note: entry.note,
        ),
    ];
    final result = await _repository.importBatch(inputs);
    _logger.info(
      'import_committed',
      fields: {
        'importedRows': result.importedCount,
        'skippedRows': preview.invalidCount,
        'createdCategories': result.createdCategoryCount,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
    return ImportCommitResult(
      importedCount: result.importedCount,
      skippedCount: preview.invalidCount,
      createdCategoryCount: result.createdCategoryCount,
    );
  }

  static String _value(List<Object?> row, int index) =>
      _object(row, index)?.toString() ?? '';

  static Object? _object(List<Object?> row, int index) =>
      index >= 0 && index < row.length ? row[index] : null;

  static EntryType _parseType(String raw, String amount) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.contains('支出') ||
        normalized == '支' ||
        normalized == 'expense' ||
        normalized == 'out') {
      return EntryType.expense;
    }
    if (normalized.contains('收入') ||
        normalized == '收' ||
        normalized == 'income' ||
        normalized == 'in') {
      return EntryType.income;
    }
    final amountValue = amount.trim();
    if (amountValue.startsWith('-')) return EntryType.expense;
    if (amountValue.startsWith('+')) return EntryType.income;
    throw const FormatException('无法识别收支类型');
  }

  static Money _parseAmount(String raw) {
    final normalized = raw
        .trim()
        .replaceAll(RegExp(r'[￥¥,，\s]'), '')
        .replaceFirst(RegExp(r'^[+-]'), '');
    final decimal = Decimal.tryParse(normalized);
    if (decimal == null) throw const FormatException('金额格式不正确');
    return Money.fromDecimal(decimal);
  }

  static LocalMinute _parseDate(Object? raw) {
    if (raw is DateTime) return LocalMinute.fromDateTime(raw);
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) throw const FormatException('时间为空');
    final normalized = value.replaceAll('/', '-').replaceFirst('T', ' ');
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{1,2})(?::\d{1,2})?)?$',
    ).firstMatch(normalized);
    if (match == null) throw const FormatException('时间格式不正确');
    final year = int.parse(match.group(1)!);
    AppDatePolicy.validateYear(year);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.tryParse(match.group(4) ?? '') ?? 0;
    final minute = int.tryParse(match.group(5) ?? '') ?? 0;
    String two(int part) => part.toString().padLeft(2, '0');
    try {
      return LocalMinute.parse(
        '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)} '
        '${two(hour)}:${two(minute)}',
      );
    } on FormatException {
      throw const FormatException('时间不是有效的本地日期时间');
    }
  }

  static int _randomVividColor(math.Random random) {
    final color = HSVColor.fromAHSV(
      1,
      random.nextDouble() * 360,
      0.68 + random.nextDouble() * 0.18,
      0.82 + random.nextDouble() * 0.14,
    ).toColor();
    return color.toARGB32();
  }

  static String _categoryKey(EntryType type, String name) =>
      '${type.databaseValue}\u0000${name.trim()}';

  static String _friendlyError(Object error) {
    if (error is FormatException) return error.message;
    if (error is ArgumentError) return error.message?.toString() ?? '数据不合法';
    return '该行数据无法解析';
  }
}
