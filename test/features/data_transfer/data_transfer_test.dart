import 'dart:convert';
import 'dart:typed_data';

import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/data_transfer/application/data_export_service.dart';
import 'package:anbookkeep/features/data_transfer/application/data_import_service.dart';
import 'package:anbookkeep/features/data_transfer/data/tabular_file_codec.dart';
import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BookkeepingRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = BookkeepingRepository(database);
  });

  tearDown(() => database.close());

  test('detects a header within the first ten rows and maps common names', () async {
    final text =
        '安安记账导入模板\r\n说明,,,,\r\n收支类型,账单分类,日期,交易金额,说明\r\n支出,餐饮,2026-08-31,12.3,午餐';
    final document = await TabularFileCodec.decode(
      fileName: 'sample.csv',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );

    expect(document.detectedHeaderIndex, 2);
    final mapping = TabularFileCodec.autoMap(document.rows[2]);
    expect(mapping[ImportField.type], 0);
    expect(mapping[ImportField.category], 1);
    expect(mapping[ImportField.occurredAt], 2);
    expect(mapping[ImportField.amount], 3);
    expect(mapping[ImportField.note], 4);
  });

  test(
    'imports both types, stores date-only at midnight and creates category',
    () async {
      final document = TabularDocument(
        fileName: 'sample.csv',
        sheetName: 'CSV',
        detectedHeaderIndex: 0,
        rows: const [
          ['类型', '分类', '时间', '金额', '备注'],
          ['支出', '新分类', '2026-08-30', '￥1,234.567', '测试'],
          ['收入', '新分类', '2026/08/31 09:10:59', '+20', ''],
        ],
      );
      final service = DataImportService(repository);
      final preview = await service.preview(
        document,
        service.autoMapping(document),
      );

      expect(preview.validCount, 2);
      expect(preview.invalidCount, 0);
      expect(preview.newCategoryCount, 2);
      expect(
        preview.entries.first.occurredAt,
        LocalMinute.parse('2026-08-30 00:00'),
      );
      expect(preview.entries.first.amount.toString(), '1234.57');

      final result = await service.commit(preview);
      expect(result.importedCount, 2);
      expect(result.createdCategoryCount, 2);
      final records = await repository.search();
      expect(records, hasLength(2));
      expect(
        records.map((record) => record.type).toSet(),
        EntryType.values.toSet(),
      );
    },
  );

  test('rejects an invalid minute instead of normalizing it', () async {
    final document = TabularDocument(
      fileName: 'invalid-time.csv',
      sheetName: 'CSV',
      detectedHeaderIndex: 0,
      rows: const [
        ['类型', '分类', '时间', '金额'],
        ['支出', '餐饮', '2026-08-20 10:99', '12.30'],
      ],
    );
    final service = DataImportService(repository);

    final preview = await service.preview(
      document,
      service.autoMapping(document),
    );

    expect(preview.validCount, 0);
    expect(preview.invalidCount, 1);
    expect(preview.issues.single.message, contains('有效'));
  });

  test(
    'exports fixed columns and respects date precision in CSV and XLSX',
    () async {
      await repository.create(
        type: EntryType.expense,
        categoryId: 'expense-food',
        amount: Money.fromDecimal(Decimal.parse('12.34')),
        occurredAt: LocalMinute.parse('2026-08-31 13:20'),
        note: '含,逗号',
      );
      final service = DataExportService(repository);
      final csv = await service.build(
        format: ExportFileFormat.csv,
        timePrecision: TimePrecision.date,
        themeColor: const Color(0xFF22AA88),
      );
      final csvDocument = await TabularFileCodec.decode(
        fileName: csv.fileName,
        bytes: csv.bytes,
      );
      expect(csvDocument.rows.first, ['类型', '分类', '时间', '金额', '备注']);
      expect(csvDocument.rows[1][2], '2026-08-31');
      expect(csvDocument.rows[1][4], '含,逗号');

      final xlsx = await service.build(
        format: ExportFileFormat.xlsx,
        timePrecision: TimePrecision.minute,
        themeColor: const Color(0xFF22AA88),
      );
      final xlsxDocument = await TabularFileCodec.decode(
        fileName: xlsx.fileName,
        bytes: xlsx.bytes,
      );
      expect(xlsxDocument.sheetName, '账单');
      expect(xlsxDocument.rows[1][2], '2026-08-31 13:20');
      expect(xlsxDocument.rows[1][3], 12.34);
    },
  );

  test('neutralizes spreadsheet formulas in CSV text fields', () async {
    await repository.create(
      type: EntryType.expense,
      categoryId: 'expense-food',
      amount: Money.zero,
      occurredAt: LocalMinute.parse('2026-08-31 13:20'),
      note: '=HYPERLINK("https://example.invalid")',
    );
    final payload = await DataExportService(repository).build(
      format: ExportFileFormat.csv,
      timePrecision: TimePrecision.minute,
      themeColor: const Color(0xFF22AA88),
    );

    final decoded = await TabularFileCodec.decode(
      fileName: payload.fileName,
      bytes: payload.bytes,
    );

    expect(decoded.rows[1][4], startsWith("'="));
  });

  test('recognizes a normalized English income-expense header', () {
    expect(TabularFileCodec.identifyHeader('Income-Expense'), ImportField.type);
  });

  test('rejects cells whose text exceeds the import safety limit', () async {
    final csv =
        '类型,分类,时间,金额,备注\n支出,餐饮,2026-09-08,1,${'a' * (TabularFileCodec.maxCellTextLength + 1)}';

    await expectLater(
      TabularFileCodec.decode(
        fileName: 'oversized-cell.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
      ),
      throwsA(isA<DataTransferException>()),
    );
  });

  test(
    'rejects XLSX archives with too many worksheets before parsing',
    () async {
      final archive = Archive();
      for (var index = 0; index <= TabularFileCodec.maxWorksheets; index++) {
        archive.addFile(
          ArchiveFile.string('xl/worksheets/sheet$index.xml', '<worksheet/>'),
        );
      }
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      await expectLater(
        TabularFileCodec.decode(fileName: 'too-many-sheets.xlsx', bytes: bytes),
        throwsA(
          isA<DataTransferException>().having(
            (error) => error.message,
            'message',
            contains('工作表'),
          ),
        ),
      );
    },
  );
}
