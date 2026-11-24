import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money_formatter.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_year_paging_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_slidable/flutter_slidable.dart';

/// Shared grouped transaction display used by the detail and search pages.
///
/// Keeping grouping, daily totals and row presentation here ensures both pages
/// render the same data and respond to display settings in the same way.
class BookkeepingRecordListController {
  _BookkeepingRecordListState? _state;

  void jumpToStart({bool waitForUserScrollBeforePrefetch = false}) =>
      _state?._jumpToStart(
        waitForUserScrollBeforePrefetch: waitForUserScrollBeforePrefetch,
      );

  void waitForUserScrollBeforePrefetch() {
    final state = _state;
    if (state != null) state._waitForUserScrollBeforePrefetch = true;
  }
}

class BookkeepingRecordList extends StatefulWidget {
  const BookkeepingRecordList({
    required this.pages,
    required this.onDelete,
    required this.timePrecision,
    required this.useGrouping,
    required this.incomeColor,
    required this.expenseColor,
    this.onTap,
    this.controller,
    this.onVisibleMonthChanged,
    this.onReachTop,
    this.onReachBottom,
    this.centerMonth,
    this.oldestFirst = false,
    this.padding = AppSpacing.pagePadding,
    super.key,
  });

  final List<LedgerMonthPage> pages;
  final ValueChanged<BookkeepingRecord> onDelete;
  final ValueChanged<BookkeepingRecord>? onTap;
  final TimePrecision timePrecision;
  final bool useGrouping;
  final Color incomeColor;
  final Color expenseColor;
  final BookkeepingRecordListController? controller;
  final ValueChanged<String>? onVisibleMonthChanged;
  final VoidCallback? onReachTop;
  final VoidCallback? onReachBottom;
  final String? centerMonth;

  /// Display the supplied months in chronological order in a single list.
  /// Each month's records must already be sorted from oldest to newest.
  final bool oldestFirst;
  final EdgeInsetsGeometry padding;

  @override
  State<BookkeepingRecordList> createState() => _BookkeepingRecordListState();
}

class _BookkeepingRecordListState extends State<BookkeepingRecordList> {
  final _scrollController = ScrollController();
  final _viewportKey = GlobalKey();
  final _centerSliverKey = GlobalKey();
  final _itemKeys = <String, GlobalKey>{};
  bool _visibilityCheckScheduled = false;
  bool _waitForUserScrollBeforePrefetch = false;
  bool _prefetchTriggeredInCurrentGesture = false;
  String? _reportedMonth;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(BookkeepingRecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller?._state == this) {
        oldWidget.controller?._state = null;
      }
      widget.controller?._state = this;
    }
    _scheduleVisibilityCheck();
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centerMonth =
        widget.centerMonth ?? widget.pages.firstOrNull?.month ?? '';
    final newerEntries = <_LedgerListEntry>[];
    final centerAndOlderEntries = <_LedgerListEntry>[];
    final newerPages = widget.oldestFirst
        ? const <LedgerMonthPage>[]
        : (widget.pages
              .where((page) => page.month.compareTo(centerMonth) > 0)
              .toList()
            ..sort((left, right) => left.month.compareTo(right.month)));
    for (final page in newerPages) {
      for (final day in page.days.reversed) {
        newerEntries.add(_LedgerListEntry.day(page.month, day));
      }
    }
    final mainPages = widget.oldestFirst
        ? widget.pages.reversed
        : widget.pages.where((page) => page.month.compareTo(centerMonth) <= 0);
    for (final page in mainPages) {
      for (final day in page.days) {
        centerAndOlderEntries.add(_LedgerListEntry.day(page.month, day));
      }
    }
    final entries = [...newerEntries, ...centerAndOlderEntries];
    final liveKeys = entries.map((entry) => entry.key).toSet();
    _itemKeys.removeWhere((key, value) => !liveKeys.contains(key));
    for (final entry in entries) {
      _itemKeys.putIfAbsent(entry.key, GlobalKey.new);
    }
    final newerIndexesByKey = <Key, int>{
      for (var index = 0; index < newerEntries.length; index++)
        _itemKeys[newerEntries[index].key]!: index,
    };
    final centerIndexesByKey = <Key, int>{
      for (var index = 0; index < centerAndOlderEntries.length; index++)
        _itemKeys[centerAndOlderEntries[index].key]!: index,
    };
    final resolvedPadding = widget.padding.resolve(Directionality.of(context));
    final horizontalPadding = EdgeInsets.only(
      left: resolvedPadding.left,
      right: resolvedPadding.right,
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          _prefetchTriggeredInCurrentGesture = false;
        }
        final userInitiated =
            notification is ScrollUpdateNotification &&
                notification.dragDetails != null ||
            notification is OverscrollNotification &&
                notification.dragDetails != null;
        final scrollDelta = switch (notification) {
          ScrollUpdateNotification() => notification.scrollDelta,
          OverscrollNotification() => notification.overscroll,
          _ => null,
        };
        final direction = scrollDelta == null || scrollDelta == 0
            ? null
            : scrollDelta < 0
            ? _PrefetchDirection.newer
            : _PrefetchDirection.older;
        _checkPrefetch(
          notification.metrics,
          userInitiated: userInitiated,
          direction: direction,
        );
        _scheduleVisibilityCheck();
        return false;
      },
      child: CustomScrollView(
        key: _viewportKey,
        controller: _scrollController,
        center: _centerSliverKey,
        physics: const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
        slivers: [
          SliverPadding(
            padding: horizontalPadding,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildEntry(newerEntries[index]),
                childCount: newerEntries.length,
                findChildIndexCallback: (key) => newerIndexesByKey[key],
              ),
            ),
          ),
          SliverPadding(
            key: _centerSliverKey,
            padding: resolvedPadding,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => centerAndOlderEntries.isEmpty
                    ? const _EmptyLedger()
                    : _buildEntry(centerAndOlderEntries[index]),
                childCount: centerAndOlderEntries.isEmpty
                    ? 1
                    : centerAndOlderEntries.length,
                findChildIndexCallback: (key) => centerIndexesByKey[key],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(_LedgerListEntry entry) {
    return BookkeepingDayGroup(
      key: _itemKeys[entry.key]!,
      date: entry.day.date,
      records: entry.day.records,
      onDelete: widget.onDelete,
      onTap: widget.onTap,
      timePrecision: widget.timePrecision,
      useGrouping: widget.useGrouping,
      incomeColor: widget.incomeColor,
      expenseColor: widget.expenseColor,
    );
  }

  void _checkPrefetch(
    ScrollMetrics? metrics, {
    bool userInitiated = false,
    _PrefetchDirection? direction,
  }) {
    if (!mounted) return;
    if (!userInitiated || _prefetchTriggeredInCurrentGesture) return;
    if (_waitForUserScrollBeforePrefetch) {
      _waitForUserScrollBeforePrefetch = false;
    }
    final value =
        metrics ??
        (_scrollController.hasClients ? _scrollController.position : null);
    if (value == null || value.viewportDimension <= 0) return;
    final threshold = value.viewportDimension * 1.5;
    if (direction == _PrefetchDirection.newer &&
        value.extentBefore < threshold) {
      _prefetchTriggeredInCurrentGesture = true;
      widget.onReachTop?.call();
    }
    if (direction == _PrefetchDirection.older &&
        value.extentAfter < threshold) {
      _prefetchTriggeredInCurrentGesture = true;
      widget.onReachBottom?.call();
    }
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (mounted) _reportVisibleMonth();
    });
  }

  void _reportVisibleMonth() {
    final anchor = _firstVisibleAnchor();
    if (anchor == null || anchor.month == _reportedMonth) return;
    _reportedMonth = anchor.month;
    widget.onVisibleMonthChanged?.call(anchor.month);
  }

  _VisibleAnchor? _firstVisibleAnchor() {
    final viewportContext = _viewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached) return null;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    for (final page in widget.pages) {
      final keys = [for (final day in page.days) '${page.month}:${day.date}'];
      for (final itemKey in keys) {
        final context = _itemKeys[itemKey]?.currentContext;
        final box = context?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        if (bottom > viewportTop + .5 && top < viewportBottom) {
          return _VisibleAnchor(page.month);
        }
      }
    }
    return null;
  }

  void _jumpToStart({bool waitForUserScrollBeforePrefetch = false}) {
    _waitForUserScrollBeforePrefetch = waitForUserScrollBeforePrefetch;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        0.0.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }
  }
}

enum _PrefetchDirection { newer, older }

final class _LedgerListEntry {
  const _LedgerListEntry.day(this.month, this.day);

  final String month;
  final LedgerDayGroup day;
  String get key => '$month:${day.date}';
}

final class _VisibleAnchor {
  const _VisibleAnchor(this.month);

  final String month;
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 180, child: Center(child: Text('暂无账单')));
  }
}

class BookkeepingDayGroup extends StatelessWidget {
  const BookkeepingDayGroup({
    required this.date,
    required this.records,
    required this.onDelete,
    required this.timePrecision,
    required this.useGrouping,
    required this.incomeColor,
    required this.expenseColor,
    this.onTap,
    super.key,
  });

  final String date;
  final List<BookkeepingRecord> records;
  final ValueChanged<BookkeepingRecord> onDelete;
  final ValueChanged<BookkeepingRecord>? onTap;
  final TimePrecision timePrecision;
  final bool useGrouping;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    var income = 0;
    var expense = 0;
    for (final record in records) {
      if (record.type == EntryType.income) {
        income += record.entry.amountMinor;
      } else {
        expense += record.entry.amountMinor;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.componentGap),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.controlGap,
            ),
            child: Row(
              children: [
                Text(
                  '$date ${_weekday(LocalMinute.parse('$date 00:00').toDateTime())}',
                ),
                const Spacer(),
                Text(
                  '${MoneyFormatter.formatMinorUnits(income, prefix: '+', useGrouping: useGrouping)} · '
                  '${MoneyFormatter.formatMinorUnits(expense, prefix: '-', useGrouping: useGrouping)}',
                  style: AppTypography.numeric(
                    Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          AppCard(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final record in records)
                  BookkeepingRecordTile(
                    record: record,
                    onDelete: onDelete,
                    onTap: onTap,
                    timePrecision: timePrecision,
                    useGrouping: useGrouping,
                    incomeColor: incomeColor,
                    expenseColor: expenseColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BookkeepingRecordTile extends StatelessWidget {
  const BookkeepingRecordTile({
    required this.record,
    required this.onDelete,
    required this.timePrecision,
    required this.useGrouping,
    required this.incomeColor,
    required this.expenseColor,
    this.onTap,
    this.showDate = false,
    super.key,
  });

  final BookkeepingRecord record;
  final ValueChanged<BookkeepingRecord> onDelete;
  final ValueChanged<BookkeepingRecord>? onTap;
  final TimePrecision timePrecision;
  final bool useGrouping;
  final Color incomeColor;
  final Color expenseColor;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final amountColor = record.type == EntryType.income
        ? incomeColor
        : expenseColor;
    return Slidable(
      key: ValueKey(record.entry.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.24,
        children: [
          SlidableAction(
            onPressed: (_) => onDelete(record),
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: '删除',
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        leading: CategoryIcon(
          code: record.category.iconCode,
          color: Color(record.category.colorValue),
          size: AppSizes.categoryIcon,
        ),
        title: Text(
          record.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: switch ((showDate, timePrecision)) {
          (true, TimePrecision.minute) => Text(record.occurredAt.value),
          (true, TimePrecision.date) => Text(record.occurredAt.date),
          (false, TimePrecision.minute) => Text(record.occurredAt.time),
          (false, TimePrecision.date) => null,
        },
        trailing: Text(
          MoneyFormatter.format(
            record.amount,
            prefix: record.type.prefix,
            useGrouping: useGrouping,
          ),
          textAlign: TextAlign.right,
          style: AppTypography.numeric(Theme.of(context).textTheme.labelLarge)
              .copyWith(color: amountColor),
        ),
        onTap: onTap == null ? null : () => onTap!(record),
      ),
    );
  }
}

String _weekday(DateTime date) => switch (date.weekday) {
  DateTime.monday => '星期一',
  DateTime.tuesday => '星期二',
  DateTime.wednesday => '星期三',
  DateTime.thursday => '星期四',
  DateTime.friday => '星期五',
  DateTime.saturday => '星期六',
  _ => '星期日',
};
