import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/data_transfer/application/data_import_service.dart';
import 'package:anbookkeep/features/data_transfer/data/tabular_file_codec.dart';
import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ImportBillsPage extends ConsumerStatefulWidget {
  const ImportBillsPage({super.key});

  @override
  ConsumerState<ImportBillsPage> createState() => _ImportBillsPageState();
}

class _ImportBillsPageState extends ConsumerState<ImportBillsPage> {
  TabularDocument? _document;
  ImportMapping? _mapping;
  ImportPreview? _preview;
  bool _busy = false;
  int _previewGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('导入账单'),
      ),
      body: document == null ? _buildPicker() : _buildMapping(document),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.bottomActionPadding,
          child: FilledButton(
            onPressed: _busy
                ? null
                : document == null
                ? _pickFile
                : (_preview?.canImport ?? false)
                ? _confirmImport
                : null,
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    document == null
                        ? '选择文件'
                        : '导入 ${_preview?.validCount ?? 0} 条',
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPicker() => ListView(
    padding: AppSpacing.pagePadding,
    children: [
      AppCard(
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '支持 XLSX 和 CSV',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('导入后不会自动去重；重复导入同一文件会产生重复账单。'),
              const SizedBox(height: AppSpacing.xs),
              const Text('文件只有日期时，将按当天 00:00 保存。'),
              const SizedBox(height: AppSpacing.xs),
              const Text('未找到的分类会按收支类型自动创建。'),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildMapping(TabularDocument document) {
    final mapping = _mapping!;
    final header = document.rows[mapping.headerRowIndex];
    final preview = _preview;
    return ListView(
      padding: AppSpacing.pagePadding,
      children: [
        AppCard(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.fileName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<int>(
                  key: ValueKey('header-${mapping.headerRowIndex}'),
                  initialValue: mapping.headerRowIndex,
                  decoration: const InputDecoration(labelText: '表头所在行'),
                  items: [
                    for (
                      var index = 0;
                      index < document.rows.length && index < 10;
                      index++
                    )
                      DropdownMenuItem(
                        value: index,
                        child: Text(
                          '第 ${index + 1} 行 · ${_rowSummary(document.rows[index])}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final next = ImportMapping(
                      headerRowIndex: value,
                      columns: TabularFileCodec.autoMap(document.rows[value]),
                    );
                    setState(() => _mapping = next);
                    _refreshPreview();
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                _TypeMappingField(
                  header: header,
                  mapping: mapping,
                  onChanged: (column, fixedType) {
                    final columns = {
                      ...mapping.columns,
                      ImportField.type: column,
                    };
                    _setMapping(
                      ImportMapping(
                        headerRowIndex: mapping.headerRowIndex,
                        columns: columns,
                        fixedType: fixedType,
                      ),
                    );
                  },
                ),
                for (final field in ImportField.values.where(
                  (field) => field != ImportField.type,
                )) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _ColumnMappingField(
                    field: field,
                    header: header,
                    value: mapping.columns[field],
                    onChanged: (value) => _setMapping(
                      mapping.copyWith(
                        columns: {...mapping.columns, field: value},
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.componentGap),
        AppCard(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: preview == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '导入预览',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (preview.missingMappingFields.isNotEmpty)
                        Text(
                          '请完成必填映射：${preview.missingMappingFields.map((field) => field.label).join('、')}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else ...[
                        Text(
                          '共 ${preview.dataRowCount} 行 · 可导入 ${preview.validCount} 行 · 跳过 ${preview.invalidCount} 行',
                        ),
                        Text('将自动创建 ${preview.newCategoryCount} 个分类'),
                        if (preview.entries.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          for (final entry in preview.entries.take(10))
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs,
                              ),
                              child: Text(
                                '${entry.type.label} · ${entry.categoryName} · ${entry.occurredAt.value} · ${entry.amount}',
                              ),
                            ),
                        ],
                        if (preview.issues.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '无法导入的行',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          for (final issue in preview.issues.take(20))
                            Text('第 ${issue.rowNumber} 行：${issue.message}'),
                        ],
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv'],
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final fileLength = await file.length();
      if (fileLength > TabularFileCodec.maxFileBytes) {
        throw const DataTransferException('文件不能超过50MB');
      }
      final bytes = await file.readAsBytes();
      final document = await TabularFileCodec.decode(
        fileName: file.name,
        bytes: bytes,
      );
      final mapping = ref.read(dataImportServiceProvider).autoMapping(document);
      if (!mounted) return;
      setState(() {
        _document = document;
        _mapping = mapping;
      });
      await _refreshPreview();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appErrorMessage(error, fallback: '文件读取失败，请检查文件格式')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMapping(ImportMapping mapping) {
    setState(() {
      _mapping = mapping;
      _preview = null;
    });
    _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final document = _document;
    final mapping = _mapping;
    if (document == null || mapping == null) return;
    final generation = ++_previewGeneration;
    try {
      final preview = await ref
          .read(dataImportServiceProvider)
          .preview(document, mapping);
      if (!mounted ||
          generation != _previewGeneration ||
          !identical(_mapping, mapping)) {
        return;
      }
      setState(() => _preview = preview);
    } on Object catch (error, stackTrace) {
      _log.error('import_preview_failed', cause: error, stackTrace: stackTrace);
      if (!mounted || generation != _previewGeneration) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('导入预览生成失败，请检查字段映射')));
    }
  }

  Future<void> _confirmImport() async {
    final preview = _preview!;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '确认导入',
      message:
          '将导入 ${preview.validCount} 条账单，自动创建 ${preview.newCategoryCount} 个分类。'
          '${preview.invalidCount > 0 ? '另有 ${preview.invalidCount} 行无效数据会被跳过。' : ''}'
          '\n当前版本不会自动去重。',
      confirmLabel: '导入',
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(dataImportServiceProvider).commit(preview);
      if (!mounted) return;
      ref.read(ledgerChangeRevisionProvider.notifier).notifyChanged();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            '已导入 ${result.importedCount} 条账单\n'
            '新建 ${result.createdCategoryCount} 个分类\n'
            '跳过 ${result.skippedCount} 行',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('完成'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appErrorMessage(error, fallback: '导入失败，请稍后重试'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _rowSummary(List<Object?> row) {
    final values = row
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .take(3)
        .join(' / ');
    return values.length > 28 ? '${values.substring(0, 28)}…' : values;
  }
}

class _ColumnMappingField extends StatelessWidget {
  const _ColumnMappingField({
    required this.field,
    required this.header,
    required this.value,
    required this.onChanged,
  });

  final ImportField field;
  final List<Object?> header;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      key: ValueKey('${field.name}-$value'),
      initialValue: value ?? (field.required ? null : -1),
      decoration: InputDecoration(
        labelText: '${field.label}${field.required ? ' *' : ''}',
      ),
      items: [
        if (!field.required)
          const DropdownMenuItem(value: -1, child: Text('不导入')),
        for (var index = 0; index < header.length; index++)
          DropdownMenuItem(
            value: index,
            child: Text(_columnName(header, index)),
          ),
      ],
      onChanged: (next) => onChanged(next == -1 ? null : next),
    );
  }
}

class _TypeMappingField extends StatelessWidget {
  const _TypeMappingField({
    required this.header,
    required this.mapping,
    required this.onChanged,
  });

  final List<Object?> header;
  final ImportMapping mapping;
  final void Function(int? column, EntryType? fixedType) onChanged;

  @override
  Widget build(BuildContext context) {
    final value = mapping.fixedType != null
        ? 'fixed:${mapping.fixedType!.name}'
        : mapping.columns[ImportField.type] == null
        ? null
        : 'column:${mapping.columns[ImportField.type]}';
    return DropdownButtonFormField<String>(
      key: ValueKey('type-$value'),
      initialValue: value,
      decoration: const InputDecoration(labelText: '类型 *'),
      items: [
        const DropdownMenuItem(value: 'fixed:expense', child: Text('固定为支出')),
        const DropdownMenuItem(value: 'fixed:income', child: Text('固定为收入')),
        for (var index = 0; index < header.length; index++)
          DropdownMenuItem(
            value: 'column:$index',
            child: Text(_columnName(header, index)),
          ),
      ],
      onChanged: (next) {
        if (next == null) return;
        if (next == 'fixed:expense') return onChanged(null, EntryType.expense);
        if (next == 'fixed:income') return onChanged(null, EntryType.income);
        onChanged(int.parse(next.split(':').last), null);
      },
    );
  }
}

String _columnName(List<Object?> header, int index) {
  final text = header[index]?.toString().trim() ?? '';
  return '${_spreadsheetColumnName(index)}列 · ${text.isEmpty ? '空表头' : text}';
}

String _spreadsheetColumnName(int index) {
  var value = index + 1;
  var result = '';
  while (value > 0) {
    value--;
    result = String.fromCharCode(65 + value % 26) + result;
    value ~/= 26;
  }
  return result;
}

const _log = AppLogger('DataImportPage');
