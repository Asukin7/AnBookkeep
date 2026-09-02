import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:csv/csv.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:gbk_codec/gbk_codec.dart';

abstract final class TabularFileCodec {
  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxRows = 100000;

  static Future<TabularDocument> decode({
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('文件不能超过50MB');
    }
    final extension = fileName.split('.').last.toLowerCase();
    final result = await Isolate.run<(String, List<List<Object?>>)>(() async {
      if (extension == 'xlsx') return _decodeXlsx(bytes);
      if (extension == 'csv') return _decodeCsv(bytes);
      throw const FormatException('仅支持XLSX或CSV文件');
    });
    if (result.$2.length > maxRows + 10) {
      throw const FormatException('文件数据不能超过100,000行');
    }
    if (result.$2.isEmpty) throw const FormatException('文件中没有可读取的数据');
    return TabularDocument(
      fileName: fileName,
      sheetName: result.$1,
      rows: result.$2,
      detectedHeaderIndex: detectHeaderIndex(result.$2),
    );
  }

  static Future<(String, List<List<Object?>>)> _decodeXlsx(
    Uint8List bytes,
  ) async {
    final excel = await Excel.decodeBytesAsync(bytes);
    for (final name in excel.tables.keys) {
      final table = excel.tables[name];
      if (table == null) continue;
      final rows = <List<Object?>>[];
      for (final row in table.rows) {
        rows.add([for (final cell in row) _cellValue(cell?.value)]);
      }
      _trimEmptyTail(rows);
      if (rows.any((row) => row.any((value) => !_isBlank(value)))) {
        return (name, rows);
      }
    }
    return ('', <List<Object?>>[]);
  }

  static Object? _cellValue(CellValue? value) => switch (value) {
    null => null,
    IntCellValue(:final value) => value,
    DoubleCellValue(:final value) => value,
    BoolCellValue(:final value) => value,
    DateCellValue() => value.asDateTimeLocal(),
    DateTimeCellValue() => value.asDateTimeLocal(),
    TextCellValue() => value.toString(),
    TimeCellValue() => value.toString(),
    _ => value.toString(),
  };

  static (String, List<List<Object?>>) _decodeCsv(Uint8List bytes) {
    final text = _decodeText(bytes);
    final decoded = Csv().decode(text);
    final rows = <List<Object?>>[
      for (final row in decoded) List<Object?>.from(row),
    ];
    _trimEmptyTail(rows);
    return ('CSV', rows);
  }

  static String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    final source =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? bytes.sublist(3)
        : bytes;
    try {
      return utf8.decode(source);
    } on FormatException {
      return gbk_bytes.decode(source);
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var index = 0; index + 1 < bytes.length; index += 2) {
      units.add(
        littleEndian
            ? bytes[index] | (bytes[index + 1] << 8)
            : (bytes[index] << 8) | bytes[index + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static int detectHeaderIndex(List<List<Object?>> rows) {
    var bestIndex = 0;
    var bestScore = -1;
    final limit = rows.length < 10 ? rows.length : 10;
    for (var index = 0; index < limit; index++) {
      final matched = <ImportField>{};
      var nonEmpty = 0;
      for (final value in rows[index]) {
        if (_isBlank(value)) continue;
        nonEmpty++;
        final field = identifyHeader(value.toString());
        if (field != null) matched.add(field);
      }
      final score = matched.length * 10 + (nonEmpty > 1 ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  static Map<ImportField, int?> autoMap(List<Object?> header) {
    final mapping = <ImportField, int?>{
      for (final field in ImportField.values) field: null,
    };
    for (var index = 0; index < header.length; index++) {
      final field = identifyHeader(header[index]?.toString() ?? '');
      if (field != null && mapping[field] == null) mapping[field] = index;
    }
    return mapping;
  }

  static ImportField? identifyHeader(String raw) {
    final value = raw.toLowerCase().replaceAll(
      RegExp(r'[\s_\-（）()\[\]【】]'),
      '',
    );
    const names = <ImportField, List<String>>{
      ImportField.type: ['类型', '收支类型', '交易类型', 'type', 'incomeexpense'],
      ImportField.category: ['分类', '类别', '账单分类', 'category'],
      ImportField.occurredAt: [
        '时间',
        '日期',
        '记账时间',
        '交易时间',
        'date',
        'time',
        'datetime',
      ],
      ImportField.amount: ['金额', '数额', '交易金额', 'amount', 'money'],
      ImportField.note: [
        '备注',
        '说明',
        '描述',
        '摘要',
        'note',
        'remark',
        'description',
      ],
    };
    for (final entry in names.entries) {
      if (entry.value.any((name) => value == name || value.contains(name))) {
        return entry.key;
      }
    }
    return null;
  }

  static void _trimEmptyTail(List<List<Object?>> rows) {
    while (rows.isNotEmpty && rows.last.every(_isBlank)) {
      rows.removeLast();
    }
  }

  static bool _isBlank(Object? value) =>
      value == null || value.toString().trim().isEmpty;
}
