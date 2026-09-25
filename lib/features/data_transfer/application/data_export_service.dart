import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:csv/csv.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return DataExportService(ref.watch(bookkeepingRepositoryProvider));
});

final class DataExportService {
  DataExportService(this._repository);

  static const _headers = ['类型', '分类', '时间', '金额', '备注'];
  static const _logger = AppLogger('DataExport');
  static const maxExportRecords = 100000;
  static const _queryPageSize = 2000;
  final BookkeepingRepository _repository;

  Future<ExportPayload> build({
    required ExportFileFormat format,
    required TimePrecision timePrecision,
    required Color themeColor,
  }) async {
    final startedAt = DateTime.now();
    final rows = await _loadRows(timePrecision);
    final themeColorValue = themeColor.toARGB32();
    final bytes = await Isolate.run(
      () => format == ExportFileFormat.csv
          ? _buildCsv(rows)
          : _buildXlsx(rows, themeColorValue),
    );
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
    _logger.info(
      'export_built',
      fields: {
        'format': format.name,
        'recordCount': rows.length,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
      },
    );
    return ExportPayload(
      fileName: '安安记账_账单_$stamp.${format.extension}',
      bytes: bytes,
      recordCount: rows.length,
    );
  }

  Future<List<List<Object?>>> _loadRows(TimePrecision timePrecision) async {
    final rows = <List<Object?>>[];
    for (var offset = 0; offset <= maxExportRecords; offset += _queryPageSize) {
      final remaining = maxExportRecords + 1 - offset;
      final records = await _repository.search(
        limit: remaining < _queryPageSize ? remaining : _queryPageSize,
        offset: offset,
      );
      for (final record in records) {
        rows.add([
          record.type.label,
          record.category.name,
          timePrecision == TimePrecision.date
              ? record.occurredAt.date
              : record.occurredAt.value,
          record.amount.toString(),
          record.entry.note ?? '',
        ]);
      }
      if (rows.length > maxExportRecords) {
        throw const DataTransferException('单次导出不能超过100,000条账单');
      }
      if (records.length < _queryPageSize) break;
    }
    return rows;
  }

  static Uint8List _buildCsv(List<List<Object?>> rows) {
    final encoded = Csv(addBom: true).encode([
      _headers,
      for (final row in rows) [for (final value in row) _safeCsvValue(value)],
    ]);
    return Uint8List.fromList(utf8.encode(encoded));
  }

  static Object? _safeCsvValue(Object? value) {
    if (value is! String || value.isEmpty) return value;
    final firstVisible = value.trimLeft();
    if (firstVisible.startsWith('=') ||
        firstVisible.startsWith('+') ||
        firstVisible.startsWith('-') ||
        firstVisible.startsWith('@') ||
        value.startsWith('\t') ||
        value.startsWith('\r')) {
      return "'$value";
    }
    return value;
  }

  static Uint8List _buildXlsx(List<List<Object?>> rows, int themeColorValue) {
    final excel = Excel.createExcel();
    excel.rename('Sheet1', '账单');
    excel.setDefaultSheet('账单');
    final sheet = excel['账单'];
    final rgb = themeColorValue.toRadixString(16).padLeft(8, '0');
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: ExcelColor.fromHexString(rgb),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final amountStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      verticalAlign: VerticalAlign.Center,
      numberFormat: NumFormat.custom(formatCode: '0.00'),
    );
    for (var column = 0; column < _headers.length; column++) {
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
        TextCellValue(_headers[column]),
        cellStyle: headerStyle,
      );
    }
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      for (var column = 0; column < row.length; column++) {
        final value = column == 3
            ? DoubleCellValue(double.parse(row[column]!.toString()))
            : TextCellValue(row[column]?.toString() ?? '');
        sheet.updateCell(
          CellIndex.indexByColumnRow(
            columnIndex: column,
            rowIndex: rowIndex + 1,
          ),
          value,
          cellStyle: column == 3 ? amountStyle : null,
        );
      }
    }
    sheet.freezePanes(rows: 1);
    sheet.setRowHeight(0, 28);
    const widths = [10.0, 16.0, 20.0, 14.0, 36.0];
    for (var index = 0; index < widths.length; index++) {
      sheet.setColumnWidth(index, widths[index]);
    }
    final bytes = excel.encode();
    if (bytes == null) throw StateError('XLSX文件生成失败');
    return Uint8List.fromList(bytes);
  }
}
