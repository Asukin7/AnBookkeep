import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/features/data_transfer/application/data_export_service.dart';
import 'package:anbookkeep/features/data_transfer/domain/data_transfer_models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExportBillsPage extends ConsumerStatefulWidget {
  const ExportBillsPage({super.key});

  @override
  ConsumerState<ExportBillsPage> createState() => _ExportBillsPageState();
}

class _ExportBillsPageState extends ConsumerState<ExportBillsPage> {
  var _format = ExportFileFormat.xlsx;
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('导出账单'),
      ),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          AppCard(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('文件格式', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  AppSegmentedButton<ExportFileFormat>(
                    segments: const [
                      ButtonSegment(
                        value: ExportFileFormat.xlsx,
                        label: Text('XLSX'),
                      ),
                      ButtonSegment(
                        value: ExportFileFormat.csv,
                        label: Text('CSV'),
                      ),
                    ],
                    selected: {_format},
                    onSelectionChanged: (value) =>
                        setState(() => _format = value.single),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('导出内容', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('类型、分类、时间、金额、备注'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '时间格式：${settings.timePrecision == TimePrecision.date ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.bottomActionPadding,
          child: FilledButton(
            onPressed: _busy ? null : () => _export(settings),
            child: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('导出'),
          ),
        ),
      ),
    );
  }

  Future<void> _export(AppSettings settings) async {
    setState(() => _busy = true);
    try {
      final payload = await ref
          .read(dataExportServiceProvider)
          .build(
            format: _format,
            timePrecision: settings.timePrecision,
            themeColor: settings.themeColor,
          );
      if (!mounted) return;
      if (payload.recordCount == 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂无可导出的账单')));
        return;
      }
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存账单文件',
        fileName: payload.fileName,
        bytes: payload.bytes,
      );
      if (!mounted || uri == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出 ${payload.recordCount} 条账单')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appErrorMessage(error, fallback: '导出失败，请稍后重试'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
