import 'dart:typed_data';

import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';

enum ExportFileFormat {
  xlsx('XLSX', 'xlsx'),
  csv('CSV', 'csv');

  const ExportFileFormat(this.label, this.extension);
  final String label;
  final String extension;
}

enum ImportField {
  type('类型', true),
  category('分类', true),
  occurredAt('时间', true),
  amount('金额', true),
  note('备注', false);

  const ImportField(this.label, this.required);
  final String label;
  final bool required;
}

final class DataTransferException implements UserFacingException {
  const DataTransferException(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

final class ExportPayload {
  const ExportPayload({
    required this.fileName,
    required this.bytes,
    required this.recordCount,
  });

  final String fileName;
  final Uint8List bytes;
  final int recordCount;
}

final class TabularDocument {
  const TabularDocument({
    required this.fileName,
    required this.sheetName,
    required this.rows,
    required this.detectedHeaderIndex,
  });

  final String fileName;
  final String sheetName;
  final List<List<Object?>> rows;
  final int detectedHeaderIndex;
}

final class ImportMapping {
  const ImportMapping({
    required this.headerRowIndex,
    required this.columns,
    this.fixedType,
  });

  final int headerRowIndex;
  final Map<ImportField, int?> columns;
  final EntryType? fixedType;

  ImportMapping copyWith({
    int? headerRowIndex,
    Map<ImportField, int?>? columns,
    EntryType? fixedType,
    bool clearFixedType = false,
  }) => ImportMapping(
    headerRowIndex: headerRowIndex ?? this.headerRowIndex,
    columns: columns ?? this.columns,
    fixedType: clearFixedType ? null : fixedType ?? this.fixedType,
  );
}

final class PreparedImportEntry {
  const PreparedImportEntry({
    required this.type,
    required this.categoryName,
    required this.occurredAt,
    required this.amount,
    required this.sourceRowNumber,
    this.note,
  });

  final EntryType type;
  final String categoryName;
  final LocalMinute occurredAt;
  final Money amount;
  final int sourceRowNumber;
  final String? note;
}

final class ImportIssue {
  const ImportIssue({required this.rowNumber, required this.message});
  final int rowNumber;
  final String message;
}

final class ImportPreview {
  const ImportPreview({
    required this.entries,
    required this.issues,
    required this.dataRowCount,
    required this.missingMappingFields,
    required this.newCategoryCount,
  });

  final List<PreparedImportEntry> entries;
  final List<ImportIssue> issues;
  final int dataRowCount;
  final Set<ImportField> missingMappingFields;
  final int newCategoryCount;
  int get validCount => entries.length;
  int get invalidCount => issues.length;
  bool get canImport => entries.isNotEmpty && missingMappingFields.isEmpty;
}

final class ImportCommitResult {
  const ImportCommitResult({
    required this.importedCount,
    required this.skippedCount,
    required this.createdCategoryCount,
  });

  final int importedCount;
  final int skippedCount;
  final int createdCategoryCount;
}
