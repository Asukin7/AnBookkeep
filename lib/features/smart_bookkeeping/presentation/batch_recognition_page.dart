import 'dart:async';
import 'dart:io';

import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/money/money_formatter.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/save_occurrence.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/application/smart_bookkeeping_service.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

final class BatchRecognitionArgs {
  const BatchRecognitionArgs({
    required this.paths,
    this.source = SmartBookkeepingSource.gallery,
  });

  final List<String> paths;
  final SmartBookkeepingSource source;
}

class BatchRecognitionPage extends ConsumerStatefulWidget {
  const BatchRecognitionPage({required this.args, super.key});

  final BatchRecognitionArgs args;

  @override
  ConsumerState<BatchRecognitionPage> createState() =>
      _BatchRecognitionPageState();
}

class _BatchRecognitionPageState extends ConsumerState<BatchRecognitionPage> {
  late final String _batchId = const Uuid().v7().substring(0, 8);
  late final List<SmartBookkeepingDraft> _items = [
    for (var index = 0; index < widget.args.paths.length; index++)
      SmartBookkeepingDraft(
        id: 'queued-$index',
        source: widget.args.source,
        imagePath: widget.args.paths[index],
      ),
  ];
  final Map<int, CancelToken> _tokens = {};
  late final SmartBookkeepingService _service;
  var _nextIndex = 0;
  var _running = true;
  var _cancelled = false;
  var _saving = false;
  var _onlineAvailable = true;
  var _allowPop = false;

  int get _finishedCount => _items
      .where(
        (item) =>
            item.status != RecognitionStatus.queued &&
            item.status != RecognitionStatus.processing,
      )
      .length;

  @override
  void initState() {
    super.initState();
    _service = ref.read(smartBookkeepingServiceProvider);
    _log.info(
      'batch_recognition_started',
      operationId: _batchId,
      fields: {'imageCount': _items.length, 'workerCount': 2},
    );
    Future<void>.microtask(_runWorkers);
  }

  @override
  void dispose() {
    _cancelled = true;
    for (final token in _tokens.values) {
      token.cancel('页面已关闭');
    }
    for (final item in _items) {
      unawaited(_service.deleteTemporaryImage(item.imagePath));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final expenseCategories =
        ref.watch(categoriesByTypeProvider(EntryType.expense)).asData?.value ??
        const [];
    final incomeCategories =
        ref.watch(categoriesByTypeProvider(EntryType.income)).asData?.value ??
        const [];
    final categoryNames = {
      for (final category in [...expenseCategories, ...incomeCategories])
        category.id: category.name,
    };
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_allowPop) unawaited(_onBack());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: _saving ? null : _onBack,
            style: IconButton.styleFrom(backgroundColor: Colors.transparent),
          ),
          title: const Text('批量图片记账'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageHorizontal,
                AppSpacing.pageTop,
                AppSpacing.pageHorizontal,
                AppSpacing.controlGap,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    child: LinearProgressIndicator(
                      value: _items.isEmpty
                          ? 0
                          : _finishedCount / _items.length,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.controlGap),
                  Text(
                    _running
                        ? '正在识别 $_finishedCount/${_items.length}'
                        : '识别完成 $_finishedCount/${_items.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageHorizontal,
                  0,
                  AppSpacing.pageHorizontal,
                  AppSpacing.pageBottom,
                ),
                itemCount: _items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.controlGap),
                itemBuilder: (context, index) =>
                    _buildItem(index, categoryNames, settings: settings),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: AppSpacing.bottomActionPadding,
            child: _running
                ? OutlinedButton(
                    onPressed: _cancelRemaining,
                    child: const Text('取消剩余识别'),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _discard,
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.componentGap),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _saveAll,
                          child: Text(_saving ? '保存中…' : '保存全部'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    int index,
    Map<String, String> categoryNames, {
    required AppSettings settings,
  }) {
    final item = _items[index];
    return AppCard(
      clipBehavior: Clip.antiAlias,
      child: Slidable(
        key: ValueKey(item.id),
        enabled: !_running && !_saving,
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.24,
          children: [
            SlidableAction(
              onPressed: _saving ? null : (_) => _confirmRemove(index),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: '删除',
            ),
          ],
        ),
        child: InkWell(
          onTap:
              !_saving &&
                  (item.status == RecognitionStatus.completed ||
                      item.status == RecognitionStatus.needsReview)
              ? () => _edit(index)
              : null,
          child: Padding(
            padding: AppSpacing.compactCardPadding,
            child: Row(
              children: [
                Tooltip(
                  message: '预览图片',
                  child: InkWell(
                    onTap: _saving ? null : () => _previewImage(item.imagePath),
                    borderRadius: BorderRadius.circular(AppRadii.compact),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.compact),
                      child: Image.file(
                        File(item.imagePath),
                        width: 68,
                        height: 68,
                        cacheWidth: 192,
                        cacheHeight: 192,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 68,
                          height: 68,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.componentGap),
                Expanded(
                  child: _itemDescription(
                    item,
                    categoryNames,
                    settings: settings,
                  ),
                ),
                if (item.status == RecognitionStatus.processing)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                else if (!_running)
                  IconButton(
                    tooltip: '重新识别',
                    onPressed: () => _retry(index),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemDescription(
    SmartBookkeepingDraft item,
    Map<String, String> categoryNames, {
    required AppSettings settings,
  }) {
    final style = Theme.of(context).textTheme;
    final statusTitle = switch (item.status) {
      RecognitionStatus.queued => '等待识别',
      RecognitionStatus.processing => '正在识别',
      RecognitionStatus.failed => '识别失败',
      RecognitionStatus.cancelled => '已取消',
      RecognitionStatus.needsReview => '需要补充',
      RecognitionStatus.completed => item.type!.label,
    };
    final metadata = [
      if (item.categoryId != null) categoryNames[item.categoryId] ?? '分类待核对',
      if (item.occurredAt != null) item.occurredAt!.value,
    ].join(' · ');
    final amountColor = item.type == EntryType.income
        ? settings.incomeColor
        : settings.expenseColor;
    final hasAmount = item.type != null && item.amount != null;
    final titleLabel = item.status == RecognitionStatus.completed
        ? item.type!.label
        : statusTitle;
    final note = item.note.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                titleLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.titleSmall,
              ),
            ),
            if (hasAmount) ...[
              const SizedBox(width: AppSpacing.controlGap),
              Text(
                MoneyFormatter.format(
                  item.amount!,
                  prefix: item.type!.prefix,
                  useGrouping:
                      settings.amountDisplayFormat ==
                      AmountDisplayFormat.grouped,
                ),
                style: style.titleSmall!.copyWith(color: amountColor),
              ),
            ],
          ],
        ),
        if (item.errorMessage != null || metadata.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            item.errorMessage ?? metadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.bodySmall,
          ),
        ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.bodySmall,
          ),
        ],
      ],
    );
  }

  Future<void> _runWorkers() async {
    await Future.wait([_worker(), _worker()]);
    if (!mounted) return;
    _log.info(
      'batch_recognition_completed',
      operationId: _batchId,
      fields: {
        'imageCount': _items.length,
        'finishedCount': _finishedCount,
        'cancelled': _cancelled,
        'onlineAvailable': _onlineAvailable,
      },
    );
    setState(() => _running = false);
  }

  Future<void> _worker() async {
    while (!_cancelled) {
      final index = _nextIndex++;
      if (index >= _items.length) return;
      await _process(index);
    }
  }

  Future<void> _process(int index) async {
    if (!mounted || index >= _items.length) return;
    final sourcePath = _items[index].imagePath;
    _log.info(
      'batch_item_started',
      operationId: _batchId,
      fields: {'item': index + 1, 'total': _items.length},
    );
    setState(() {
      _items[index] = _items[index].copyWith(
        status: RecognitionStatus.processing,
      );
    });
    final token = CancelToken();
    _tokens[index] = token;
    try {
      final result = await _service.recognize(
        sourcePath: sourcePath,
        source: widget.args.source,
        cancelToken: token,
        allowOnline: _onlineAvailable,
      );
      if (mounted && index < _items.length) {
        setState(() {
          _items[index] = result;
          if (result.onlineFailureGlobal) {
            _onlineAvailable = false;
            _log.warning(
              'batch_online_ai_disabled_for_remaining_items',
              operationId: _batchId,
              fields: {'item': index + 1},
            );
          }
        });
        _log.info(
          'batch_item_completed',
          operationId: _batchId,
          fields: {
            'item': index + 1,
            'status': result.status.name,
            'usedOnlineAi': result.usedOnlineAi,
          },
        );
        if (sourcePath != result.imagePath) {
          await _service.deleteTemporaryImage(sourcePath);
        }
      }
    } on SmartRecognitionException catch (error) {
      _log.warning(
        error.message == '识别已取消' ? 'batch_item_cancelled' : 'batch_item_failed',
        operationId: _batchId,
        fields: {'item': index + 1},
      );
      if (!mounted || index >= _items.length) return;
      setState(() {
        _items[index] = SmartBookkeepingDraft(
          id: _items[index].id,
          source: widget.args.source,
          imagePath: sourcePath,
          status: error.message == '识别已取消'
              ? RecognitionStatus.cancelled
              : RecognitionStatus.failed,
          errorMessage: error.message,
        );
      });
    } finally {
      _tokens.remove(index);
    }
  }

  void _cancelRemaining() {
    _log.info(
      'batch_recognition_cancel_requested',
      operationId: _batchId,
      fields: {'finishedCount': _finishedCount, 'total': _items.length},
    );
    _cancelled = true;
    for (final token in _tokens.values) {
      token.cancel('用户取消');
    }
    setState(() {
      for (var index = _nextIndex; index < _items.length; index++) {
        _items[index] = _items[index].copyWith(
          status: RecognitionStatus.cancelled,
        );
      }
    });
  }

  Future<void> _retry(int index) async {
    if (_saving) return;
    if (_running) return;
    setState(() => _running = true);
    await _process(index);
    if (mounted) setState(() => _running = false);
  }

  Future<void> _edit(int index) async {
    if (_saving) return;
    final updated = await context.push<SmartBookkeepingDraft>(
      AppRoutes.bookkeeping,
      extra: BookkeepingDraftPageArgs(draft: _items[index], returnDraft: true),
    );
    if (updated != null && mounted) setState(() => _items[index] = updated);
  }

  Future<void> _remove(int index) async {
    final item = _items[index];
    await _service.deleteTemporaryImage(item.imagePath);
    if (mounted) setState(() => _items.removeAt(index));
  }

  Future<void> _confirmRemove(int index) async {
    if (_saving) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除识别项',
      message: '确定删除这张图片及其识别结果吗？删除后无法恢复。',
      confirmLabel: '删除',
    );
    if (confirmed && mounted && index < _items.length) await _remove(index);
  }

  Future<void> _previewImage(String path) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: IconButton(
                  tooltip: '关闭预览',
                  onPressed: () => Navigator.pop(dialogContext),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAll() async {
    if (_saving) return;
    if (_items.isEmpty) {
      _message('没有可保存的账单');
      return;
    }
    final invalid = _items.where((item) => !item.isComplete).length;
    if (invalid > 0) {
      _message('还有$invalid条账单需要补充或移除');
      return;
    }
    setState(() => _saving = true);
    _log.info(
      'batch_save_started',
      operationId: _batchId,
      fields: {'itemCount': _items.length},
    );
    try {
      final precision = ref.read(appSettingsProvider).timePrecision;
      await ref.read(bookkeepingRepositoryProvider).createBatch([
        for (final item in _items)
          BookkeepingCreateInput(
            type: item.type!,
            categoryId: item.categoryId!,
            amount: item.amount!,
            occurredAt: occurrenceForSave(
              selected: item.occurredAt!,
              precision: precision,
              isEditing: false,
            ),
            note: item.note,
          ),
      ]);
      _log.info(
        'batch_save_completed',
        operationId: _batchId,
        fields: {'itemCount': _items.length},
      );
      if (mounted) await _complete(true);
    } on Object catch (error, stackTrace) {
      _log.error(
        'batch_save_failed',
        operationId: _batchId,
        cause: error,
        stackTrace: stackTrace,
        fields: {'itemCount': _items.length},
      );
      if (mounted) {
        setState(() => _saving = false);
        _message(appErrorMessage(error, fallback: '批量保存失败，请重试'));
      }
    }
  }

  Future<void> _onBack() async {
    if (_saving) {
      _message('正在保存账单，请稍候');
      return;
    }
    if (!_running) {
      await _discard();
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: '停止批量识别',
      message: '确定停止识别并放弃本批次吗？',
      confirmLabel: '放弃',
    );
    if (confirmed && mounted) {
      _cancelRemaining();
      await _complete();
    }
  }

  Future<void> _discard() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '放弃批量记账',
      message: '当前识别结果尚未保存，确定放弃吗？',
      confirmLabel: '放弃',
    );
    if (confirmed && mounted) await _complete();
  }

  Future<void> _complete([bool? result]) async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

const _log = AppLogger('SmartBookkeeping');
