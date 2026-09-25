import 'dart:async';

import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_year_paging_controller.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_record_list.dart';
import 'package:anbookkeep/features/search/data/search_provider.dart';
import 'package:anbookkeep/features/search/domain/search_criteria.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

String searchDateRangeText(DateTimeRange range) =>
    '${_searchDateText(range.start)} ~ ${_searchDateText(range.end)}';

String _searchDateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _keywordController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  SearchCriteria _criteria = SearchCriteria();
  String? _amountError;
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  LedgerYearPagingController? _pagingController;
  final _listController = BookkeepingRecordListController();
  bool _initialLoading = true;
  String? _loadError;
  bool _expanded = false;
  EntryType? _type;
  DateTimeRange? _dateRange;
  final _categoryIds = <String>{};

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_startSearch);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pagingController?.invalidate();
    _keywordController.dispose();
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  void _syncTextCriteria() {
    final previousCriteria = _criteria;
    final minResult = _parseMinor(_minController.text);
    final maxResult = _parseMinor(_maxController.text);
    String? error;
    if (!minResult.isValid || !maxResult.isValid) {
      error = '请输入有效金额';
    } else if (minResult.value != null &&
        maxResult.value != null &&
        minResult.value! > maxResult.value!) {
      error = '最小金额不能大于最大金额';
    }
    final errorChanged = error != _amountError;
    _amountError = error;
    _criteria = _criteria.copyWith(
      keyword: _keywordController.text.trim(),
      minAmountMinor: error == null ? minResult.value : null,
      maxAmountMinor: error == null ? maxResult.value : null,
      clearMinAmount: error != null || minResult.value == null,
      clearMaxAmount: error != null || maxResult.value == null,
    );
    if (errorChanged) setState(() {});
    if (error == null && _criteria != previousCriteria) _scheduleSearch();
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), _startSearch);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(ledgerChangeRevisionProvider, (previous, next) {
      if (previous != null && previous != next) unawaited(_startSearch());
    });
    final settings = ref.watch(appSettingsProvider);
    final categories = ref.watch(categoriesByTypeProvider(EntryType.expense));
    final incomeCategories = ref.watch(
      categoriesByTypeProvider(EntryType.income),
    );
    final availableCategories = switch (_type) {
      EntryType.expense => categories.asData?.value ?? const <CategoryRow>[],
      EntryType.income =>
        incomeCategories.asData?.value ?? const <CategoryRow>[],
      null => const <CategoryRow>[],
    };
    final useGrouping =
        settings.amountDisplayFormat == AmountDisplayFormat.grouped;
    final pages = _pagingController?.pages ?? const <LedgerMonthPage>[];
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: const Text('搜索'),
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
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keywordController,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => _syncTextCriteria(),
                    decoration: const InputDecoration(
                      hintText: '搜索备注',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.controlGap),
                IconButton(
                  tooltip: _expanded ? '收起筛选' : '展开筛选',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLow,
                  ),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded)
            _FilterPanel(
              type: _type,
              dateRange: _dateRange,
              categoryIds: _categoryIds,
              categories: availableCategories,
              minController: _minController,
              maxController: _maxController,
              amountError: _amountError,
              onTypeChanged: (value) {
                setState(() {
                  _type = value;
                  _categoryIds.clear();
                  _criteria = _criteria.copyWith(
                    type: value,
                    clearType: value == null,
                    categoryIds: const [],
                  );
                });
                _startSearch();
              },
              onDateRangeChanged: (value) {
                setState(() {
                  _dateRange = value;
                  _criteria = _criteria.copyWith(
                    startDate: value == null
                        ? null
                        : _searchDateText(value.start),
                    endDate: value == null ? null : _searchDateText(value.end),
                    clearDateRange: value == null,
                  );
                });
                _startSearch();
              },
              onCategoriesChanged: (value) {
                setState(() {
                  _categoryIds
                    ..clear()
                    ..addAll(value);
                  _criteria = _criteria.copyWith(categoryIds: value);
                });
                _startSearch();
              },
              onTextChanged: _syncTextCriteria,
              loadDateBounds: _loadDateBounds,
              onReset: _reset,
            ),
          Expanded(
            child: _initialLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _loadError != null
                ? Center(child: Text(_loadError!))
                : pages.isEmpty
                ? const Center(child: Text('暂无符合条件的账单'))
                : BookkeepingRecordList(
                    controller: _listController,
                    pages: pages,
                    centerMonth: _pagingController?.newestMonth,
                    onReachBottom: _loadOlderYear,
                    onDelete: _delete,
                    onTap: (record) async {
                      await context.push(
                        '${AppRoutes.bookkeeping}/${record.entry.id}/edit',
                      );
                      await _startSearch();
                    },
                    useGrouping: useGrouping,
                    timePrecision: settings.timePrecision,
                    incomeColor: settings.incomeColor,
                    expenseColor: settings.expenseColor,
                    padding: AppSpacing.pagePadding,
                  ),
          ),
        ],
      ),
    );
  }

  Future<AppDateBounds> _loadDateBounds() async {
    final dataRange = await ref
        .read(bookkeepingRepositoryProvider)
        .dataYearRange();
    return AppDatePolicy.pickerBounds(
      dataMinimumYear: dataRange?.minYear,
      dataMaximumYear: dataRange?.maxYear,
      anchorYears: [
        if (_dateRange != null) _dateRange!.start.year,
        if (_dateRange != null) _dateRange!.end.year,
      ],
    );
  }

  void _reset() {
    _keywordController.clear();
    _minController.clear();
    _maxController.clear();
    setState(() {
      _type = null;
      _dateRange = null;
      _categoryIds.clear();
      _amountError = null;
      _criteria = SearchCriteria();
    });
    _startSearch();
  }

  Future<void> _delete(BookkeepingRecord record) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除账单',
      message: '确定删除这笔账单吗？删除后无法恢复。',
      confirmLabel: '删除',
    );
    if (!confirmed) return;
    await ref.read(bookkeepingRepositoryProvider).delete(record.entry.id);
    if (mounted) await _startSearch();
  }

  Future<void> _startSearch() async {
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final criteria = _criteria;
    final repository = ref.read(bookkeepingRepositoryProvider);
    if (_pagingController == null && mounted) {
      setState(() {
        _initialLoading = true;
        _loadError = null;
      });
    }
    try {
      final initial = await loadInitialSearchYear(repository, criteria);
      if (!mounted || generation != _searchGeneration) return;
      if (initial == null) {
        _pagingController?.invalidate();
        setState(() {
          _pagingController = null;
          _initialLoading = false;
          _loadError = null;
        });
        return;
      }
      final nextController = LedgerYearPagingController(
        loadYear: (year) => loadSearchYear(repository, criteria, year),
        findOlderYear: (year) =>
            findOlderSearchYear(repository, criteria, year),
      );
      nextController.initializeWithRecords(
        initial.latestMonth,
        initial.records,
      );
      if (!mounted || generation != _searchGeneration) {
        nextController.invalidate();
        return;
      }
      _pagingController?.invalidate();
      setState(() {
        _pagingController = nextController;
        _initialLoading = false;
        _loadError = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      _listController.jumpToStart();
      await _loadOlderYear();
    } on Object catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      if (_pagingController == null) {
        setState(() {
          _initialLoading = false;
          _loadError = appErrorMessage(error, fallback: '搜索失败，请重试');
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '搜索刷新失败，请重试')),
          ),
        );
      }
    }
  }

  Future<void> _loadOlderYear() async {
    final controller = _pagingController;
    if (controller == null ||
        controller.isLoadingOlder ||
        !controller.hasOlder) {
      return;
    }
    try {
      final changed = await controller.loadOlder();
      if (changed && mounted && identical(controller, _pagingController)) {
        setState(() {});
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'load_older_search_year_failed',
        cause: error,
        stackTrace: stackTrace,
      );
      // Keep the visible results; the next scroll can retry.
    }
  }

  static ({bool isValid, int? value}) _parseMinor(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return (isValid: true, value: null);
    try {
      return (
        isValid: true,
        value: Money.fromDecimal(Decimal.parse(normalized)).minorUnits,
      );
    } on Object {
      return (isValid: false, value: null);
    }
  }
}

const _log = AppLogger('Search');

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.type,
    required this.dateRange,
    required this.categoryIds,
    required this.categories,
    required this.minController,
    required this.maxController,
    required this.amountError,
    required this.onTypeChanged,
    required this.onDateRangeChanged,
    required this.onCategoriesChanged,
    required this.onTextChanged,
    required this.loadDateBounds,
    required this.onReset,
  });

  final EntryType? type;
  final DateTimeRange? dateRange;
  final Set<String> categoryIds;
  final List<CategoryRow> categories;
  final TextEditingController minController;
  final TextEditingController maxController;
  final String? amountError;
  final ValueChanged<EntryType?> onTypeChanged;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final ValueChanged<Set<String>> onCategoriesChanged;
  final VoidCallback onTextChanged;
  final Future<AppDateBounds> Function() loadDateBounds;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        0,
        AppSpacing.pageHorizontal,
        AppSpacing.componentGap,
      ),
      child: Padding(
        padding: AppSpacing.compactCardPadding,
        child: Column(
          children: [
            AppSegmentedButton<EntryType?>(
              segments: const [
                ButtonSegment(value: null, label: Text('全部')),
                ButtonSegment(value: EntryType.expense, label: Text('支出')),
                ButtonSegment(value: EntryType.income, label: Text('收入')),
              ],
              selected: {type},
              onSelectionChanged: (values) => onTypeChanged(values.first),
            ),
            const SizedBox(height: AppSpacing.componentGap),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('search-date-range-button'),
                style: FilledButton.styleFrom(
                  foregroundColor: colorScheme.onSurface,
                  backgroundColor: colorScheme.surfaceContainerLow,
                  side: BorderSide.none,
                ),
                onPressed: () async {
                  final bounds = await loadDateBounds();
                  if (!context.mounted) return;
                  final value = await showDateRangePicker(
                    context: context,
                    firstDate: bounds.firstDate,
                    lastDate: bounds.lastDate,
                    initialDateRange: dateRange,
                  );
                  if (value != null) onDateRangeChanged(value);
                },
                child: Text(
                  dateRange == null ? '全部时间' : searchDateRangeText(dateRange!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (type != null) ...[
              const SizedBox(height: AppSpacing.controlGap),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('search-category-button'),
                  style: FilledButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    backgroundColor: colorScheme.surfaceContainerLow,
                    side: BorderSide.none,
                  ),
                  onPressed: () async {
                    final result = await showModalBottomSheet<Set<String>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => _CategoryPicker(
                        categories: categories,
                        selected: categoryIds,
                      ),
                    );
                    if (result != null) onCategoriesChanged(result);
                  },
                  child: Text(
                    categoryIds.isEmpty ? '全部分类' : '已选${categoryIds.length}项分类',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.componentGap),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onTextChanged(),
                    decoration: InputDecoration(
                      labelText: '最小金额',
                      errorText: amountError,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.controlGap),
                Expanded(
                  child: TextField(
                    controller: maxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => onTextChanged(),
                    decoration: InputDecoration(
                      labelText: '最大金额',
                      errorText: amountError,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('重置所有条件'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.categories, required this.selected});

  final List<CategoryRow> categories;
  final Set<String> selected;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  late final _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: AppBottomSheetLayout(
        title: '选择分类',
        expandContent: true,
        actions: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('确认'),
          ),
        ),
        child: ListView.builder(
          itemCount: widget.categories.length,
          itemBuilder: (context, index) {
            final category = widget.categories[index];
            return CheckboxListTile(
              value: _selected.contains(category.id),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selected.add(category.id);
                } else {
                  _selected.remove(category.id);
                }
              }),
              secondary: CategoryIcon(
                code: category.iconCode,
                color: Color(category.colorValue),
                size: AppSizes.categoryIconLarge,
              ),
              title: Text(category.name),
            );
          },
        ),
      ),
    );
  }
}
