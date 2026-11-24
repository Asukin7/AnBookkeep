import 'dart:async';

import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
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
import 'package:anbookkeep/features/bookkeeping/domain/bookkeeping_search_order.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_record_list.dart';
import 'package:anbookkeep/features/search/data/search_provider.dart';
import 'package:anbookkeep/features/search/domain/search_criteria.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialCriteria});

  final SearchCriteria? initialCriteria;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _keywordController = TextEditingController();
  final _minController = TextEditingController();
  final _maxController = TextEditingController();
  late SearchCriteria _criteria;
  String? _amountError;
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  LedgerYearPagingController? _pagingController;
  _AmountSearchPaging? _amountPaging;
  BookkeepingSearchOrder _displayedOrder =
      BookkeepingSearchOrder.timeDescending;
  final _listController = BookkeepingRecordListController();
  final _amountListController = ScrollController(keepScrollOffset: false);
  bool _initialLoading = true;
  String? _loadError;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _amountListController.addListener(_prefetchAmountPage);
    final initial = widget.initialCriteria;
    _criteria = initial ?? SearchCriteria();
    if (initial != null) {
      _keywordController.text = initial.keyword;
      if (initial.minAmountMinor case final minimum?) {
        _minController.text = Money.fromMinorUnits(minimum).toString();
      }
      if (initial.maxAmountMinor case final maximum?) {
        _maxController.text = Money.fromMinorUnits(maximum).toString();
      }
    }
    Future<void>.microtask(_startSearch);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _pagingController?.invalidate();
    _amountListController.dispose();
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
      clearMinAmount: error == null && minResult.value == null,
      clearMaxAmount: error == null && maxResult.value == null,
    );
    if (errorChanged) setState(() {});
    if (error != null) {
      _searchDebounce?.cancel();
    } else if (errorChanged || _criteria != previousCriteria) {
      _scheduleSearch();
    }
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
    final availableCategories = switch (_criteria.type) {
      EntryType.expense => categories.asData?.value ?? const <CategoryRow>[],
      EntryType.income =>
        incomeCategories.asData?.value ?? const <CategoryRow>[],
      null => const <CategoryRow>[],
    };
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
            child: TextField(
              controller: _keywordController,
              textInputAction: TextInputAction.search,
              onChanged: (_) => _syncTextCriteria(),
              decoration: InputDecoration(
                hintText: '搜索备注',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: _expanded ? '收起筛选' : '展开筛选',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: _trailingActionStyle,
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
              ),
            ),
          ),
          _SearchFilterReveal(
            visible: _expanded,
            child: _FilterPanel(
              type: _criteria.type,
              startDate: _criteria.startDate,
              endDate: _criteria.endDate,
              categoryIds: _criteria.categoryIds.toSet(),
              categories: availableCategories,
              minController: _minController,
              maxController: _maxController,
              amountError: _amountError,
              order: _criteria.order,
              onTypeChanged: (value) {
                setState(() {
                  _criteria = _criteria.copyWith(
                    type: value,
                    clearType: value == null,
                    categoryIds: const [],
                  );
                });
                _startSearch();
              },
              onSelectStartDate: () => _selectDate(isStart: true),
              onSelectEndDate: () => _selectDate(isStart: false),
              onClearStartDate: () => _setDate(null, isStart: true),
              onClearEndDate: () => _setDate(null, isStart: false),
              onCategoriesChanged: (value) {
                setState(() {
                  _criteria = _criteria.copyWith(categoryIds: value);
                });
                _startSearch();
              },
              onTextChanged: _syncTextCriteria,
              onSort: _cycleSort,
              onReset: _reset,
            ),
          ),
          Expanded(child: _buildResults(settings)),
        ],
      ),
    );
  }

  Widget _buildResults(AppSettings settings) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_loadError case final error?) return Center(child: Text(error));
    final useGrouping =
        settings.amountDisplayFormat == AmountDisplayFormat.grouped;
    final amounts = _amountPaging?.records;
    if (amounts != null && amounts.isNotEmpty) {
      return ListView.separated(
        key: ValueKey(_displayedOrder),
        controller: _amountListController,
        padding: AppSpacing.pagePadding,
        itemCount: amounts.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppSpacing.controlGap),
        itemBuilder: (context, index) {
          final record = amounts[index];
          return AppCard(
            key: ValueKey(record.entry.id),
            clipBehavior: Clip.antiAlias,
            child: BookkeepingRecordTile(
              record: record,
              onDelete: _delete,
              onTap: _edit,
              showDate: true,
              useGrouping: useGrouping,
              timePrecision: settings.timePrecision,
              incomeColor: settings.incomeColor,
              expenseColor: settings.expenseColor,
            ),
          );
        },
      );
    }
    final pages = _pagingController?.pages ?? const <LedgerMonthPage>[];
    if (pages.isEmpty) {
      return const Center(child: Text('暂无符合条件的账单'));
    }
    return BookkeepingRecordList(
      key: ValueKey(_displayedOrder),
      controller: _listController,
      pages: pages,
      centerMonth: pages.first.month,
      oldestFirst: _displayedOrder == BookkeepingSearchOrder.timeAscending,
      onReachBottom: _loadNextYear,
      onDelete: _delete,
      onTap: _edit,
      useGrouping: useGrouping,
      timePrecision: settings.timePrecision,
      incomeColor: settings.incomeColor,
      expenseColor: settings.expenseColor,
    );
  }

  Future<void> _edit(BookkeepingRecord record) async {
    await context.push('${AppRoutes.bookkeeping}/${record.entry.id}/edit');
    if (mounted) await _startSearch();
  }

  Future<void> _selectDate({required bool isStart}) async {
    final dataRange = await ref
        .read(bookkeepingRepositoryProvider)
        .dataYearRange();
    if (!mounted) return;
    final start = DateTime.tryParse(_criteria.startDate ?? '');
    final end = DateTime.tryParse(_criteria.endDate ?? '');
    final bounds = AppDatePolicy.pickerBounds(
      dataMinimumYear: dataRange?.minYear,
      dataMaximumYear: dataRange?.maxYear,
      anchorYears: [if (start != null) start.year, if (end != null) end.year],
    );
    final date = await showDatePicker(
      context: context,
      helpText: isStart ? '开始时间' : '结束时间',
      initialDate: (isStart ? start ?? end : end ?? start) ?? DateTime.now(),
      firstDate: isStart ? bounds.firstDate : start ?? bounds.firstDate,
      lastDate: isStart ? end ?? bounds.lastDate : bounds.lastDate,
    );
    if (date == null || !mounted) return;
    _setDate(LocalMinute.fromDateTime(date).date, isStart: isStart);
  }

  void _setDate(String? date, {required bool isStart}) {
    final next = isStart
        ? _criteria.copyWith(startDate: date, clearStartDate: date == null)
        : _criteria.copyWith(endDate: date, clearEndDate: date == null);
    if (next == _criteria) return;
    setState(() => _criteria = next);
    unawaited(_startSearch());
  }

  void _cycleSort() {
    setState(() => _criteria = _criteria.copyWith(order: _criteria.order.next));
    unawaited(_startSearch());
  }

  void _reset() {
    _keywordController.clear();
    _minController.clear();
    _maxController.clear();
    setState(() {
      _amountError = null;
      _criteria = SearchCriteria();
    });
    unawaited(_startSearch());
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
    if (!mounted) return;
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final criteria = _criteria;
    final repository = ref.read(bookkeepingRepositoryProvider);
    if (_pagingController == null && _amountPaging == null) {
      setState(() {
        _initialLoading = true;
        _loadError = null;
      });
    }
    try {
      LedgerYearPagingController? nextTime;
      _AmountSearchPaging? nextAmount;
      if (criteria.order.isAmount) {
        nextAmount = _AmountSearchPaging(
          (after) => loadAmountSearchPage(repository, criteria, after: after),
        );
        await nextAmount.loadNext();
      } else {
        final initial = await loadInitialSearchYear(repository, criteria);
        if (initial != null) {
          nextTime = LedgerYearPagingController(
            loadYear: (year) => loadSearchYear(repository, criteria, year),
            findOlderYear: (year) =>
                findOlderSearchYear(repository, criteria, year),
            findNewerYear: (year) =>
                findNewerSearchYear(repository, criteria, year),
          )..initializeWithRecords(initial.anchorMonth, initial.records);
        }
      }
      if (!mounted || generation != _searchGeneration) return;
      _pagingController?.invalidate();
      setState(() {
        _pagingController = nextTime;
        _amountPaging = nextAmount;
        _displayedOrder = criteria.order;
        _initialLoading = false;
        _loadError = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _searchGeneration) return;
      if (nextTime != null) {
        _listController.jumpToStart();
        await _loadNextYear();
      } else if (_amountListController.hasClients) {
        _amountListController.jumpTo(0);
      }
    } on Object catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      if (_pagingController == null && _amountPaging == null) {
        setState(() {
          _initialLoading = false;
          _loadError = appErrorMessage(error, fallback: '搜索失败，请重试');
        });
      } else {
        if (criteria.order != _displayedOrder) {
          setState(() {
            _criteria = _criteria.copyWith(order: _displayedOrder);
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '搜索刷新失败，请重试')),
          ),
        );
      }
    }
  }

  Future<void> _loadNextYear() async {
    final controller = _pagingController;
    if (controller == null) return;
    try {
      final changed =
          await (_displayedOrder == BookkeepingSearchOrder.timeAscending
              ? controller.loadNewer()
              : controller.loadOlder());
      if (changed && mounted && identical(controller, _pagingController)) {
        setState(() {});
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'load_next_search_year_failed',
        cause: error,
        stackTrace: stackTrace,
      );
      // Keep the visible results; the next scroll can retry.
    }
  }

  void _prefetchAmountPage() {
    final controller = _amountPaging;
    if (controller == null || _amountListController.positions.length != 1) {
      return;
    }
    final position = _amountListController.position;
    if (position.hasContentDimensions &&
        position.extentAfter < position.viewportDimension) {
      unawaited(_loadNextAmountPage(controller));
    }
  }

  Future<void> _loadNextAmountPage(_AmountSearchPaging controller) async {
    try {
      final changed = await controller.loadNext();
      if (changed && mounted && identical(controller, _amountPaging)) {
        setState(() {});
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'load_next_search_amount_page_failed',
        cause: error,
        stackTrace: stackTrace,
      );
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

class _AmountSearchPaging {
  _AmountSearchPaging(this._loadPage);

  final Future<({List<BookkeepingRecord> records, bool hasMore})> Function(
    BookkeepingRecord? after,
  )
  _loadPage;
  final records = <BookkeepingRecord>[];
  bool _hasMore = true;
  bool _loading = false;

  Future<bool> loadNext() async {
    if (_loading || !_hasMore) return false;
    _loading = true;
    try {
      final page = await _loadPage(records.lastOrNull);
      records.addAll(page.records);
      _hasMore = page.hasMore;
      return page.records.isNotEmpty;
    } finally {
      _loading = false;
    }
  }
}

final _trailingActionStyle = IconButton.styleFrom(
  backgroundColor: Colors.transparent,
  alignment: Alignment.center,
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
);

class _SearchFilterReveal extends StatelessWidget {
  const _SearchFilterReveal({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.standard,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      layoutBuilder: (current, outgoing) => Stack(
        alignment: Alignment.topCenter,
        children: [
          for (final child in outgoing)
            ExcludeFocus(
              child: IgnorePointer(child: ExcludeSemantics(child: child)),
            ),
          ?current,
        ],
      ),
      child: visible ? child : null,
    );
  }
}

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.categoryIds,
    required this.categories,
    required this.minController,
    required this.maxController,
    required this.amountError,
    required this.order,
    required this.onTypeChanged,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
    required this.onClearStartDate,
    required this.onClearEndDate,
    required this.onCategoriesChanged,
    required this.onTextChanged,
    required this.onSort,
    required this.onReset,
  });

  final EntryType? type;
  final String? startDate;
  final String? endDate;
  final Set<String> categoryIds;
  final List<CategoryRow> categories;
  final TextEditingController minController;
  final TextEditingController maxController;
  final String? amountError;
  final BookkeepingSearchOrder order;
  final ValueChanged<EntryType?> onTypeChanged;
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectEndDate;
  final VoidCallback onClearStartDate;
  final VoidCallback onClearEndDate;
  final ValueChanged<Set<String>> onCategoriesChanged;
  final VoidCallback onTextChanged;
  final VoidCallback onSort;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
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
            _SearchFilterReveal(
              visible: type != null,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.componentGap),
                child: _ClearableFilterButton(
                  buttonKey: const ValueKey('search-category-button'),
                  label: '分类',
                  placeholder: '全部分类',
                  value: categoryIds.isEmpty
                      ? null
                      : '已选${categoryIds.length}项分类',
                  onSelect: () async {
                    final result = await showModalBottomSheet<Set<String>>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => _CategoryPicker(
                        categories: categories,
                        selected: categoryIds,
                      ),
                    );
                    if (result != null && context.mounted) {
                      onCategoriesChanged(result);
                    }
                  },
                  onClear: () => onCategoriesChanged(const {}),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _ClearableFilterButton(
                    buttonKey: const ValueKey('search-start-date-button'),
                    label: '开始时间',
                    value: startDate,
                    alignStart: true,
                    onSelect: onSelectStartDate,
                    onClear: onClearStartDate,
                  ),
                ),
                const SizedBox(width: AppSpacing.controlGap),
                Expanded(
                  child: _ClearableFilterButton(
                    buttonKey: const ValueKey('search-end-date-button'),
                    label: '结束时间',
                    value: endDate,
                    alignStart: true,
                    onSelect: onSelectEndDate,
                    onClear: onClearEndDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.componentGap),
            Row(
              children: [
                Expanded(
                  child: _AmountFilterField(
                    label: '最小金额',
                    controller: minController,
                    onChanged: onTextChanged,
                    error: amountError,
                  ),
                ),
                const SizedBox(width: AppSpacing.controlGap),
                Expanded(
                  child: _AmountFilterField(
                    label: '最大金额',
                    controller: maxController,
                    onChanged: onTextChanged,
                    error: amountError,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextButton.icon(
                    onPressed: onSort,
                    icon: const Icon(Icons.sort_rounded),
                    label: Text(
                      switch (order) {
                        BookkeepingSearchOrder.timeDescending => '时间倒序',
                        BookkeepingSearchOrder.timeAscending => '时间正序',
                        BookkeepingSearchOrder.amountDescending => '金额倒序',
                        BookkeepingSearchOrder.amountAscending => '金额正序',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.controlGap),
                Flexible(
                  child: TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text(
                      '重置条件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearableFilterButton extends StatelessWidget {
  const _ClearableFilterButton({
    required this.buttonKey,
    required this.label,
    required this.value,
    required this.onSelect,
    required this.onClear,
    this.placeholder,
    this.alignStart = false,
  });

  final Key buttonKey;
  final String label;
  final String? value;
  final String? placeholder;
  final bool alignStart;
  final VoidCallback onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final padding = alignStart
        ? EdgeInsetsDirectional.only(
            start: AppSpacing.md,
            end: value == null ? AppSpacing.md : AppSizes.control,
          )
        : EdgeInsets.symmetric(
            horizontal: value == null ? AppSpacing.xxs : AppSpacing.xl,
          );
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: buttonKey,
            style: FilledButton.styleFrom(
              foregroundColor: colors.onSurface,
              backgroundColor: colors.surfaceContainerLow,
              side: BorderSide.none,
              alignment: alignStart
                  ? AlignmentDirectional.centerStart
                  : Alignment.center,
              padding: padding,
            ),
            onPressed: onSelect,
            child: Text(
              value ?? placeholder ?? label,
              semanticsLabel: value == null ? null : '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (value != null)
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            width: AppSizes.control,
            child: _FilterClearButton(label: label, onPressed: onClear),
          ),
      ],
    );
  }
}

class _AmountFilterField extends StatelessWidget {
  const _AmountFilterField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.error,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: value.text.isEmpty
              ? null
              : _FilterClearButton(
                  label: label,
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                ),
        ),
      ),
    );
  }
}

class _FilterClearButton extends StatelessWidget {
  const _FilterClearButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '清除$label',
      onPressed: onPressed,
      style: _trailingActionStyle,
      icon: const Icon(Icons.close_rounded, size: AppSizes.iconAuxiliary),
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
