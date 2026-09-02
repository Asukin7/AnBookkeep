import 'dart:async';

import 'package:anbookkeep/app/router/app_router.dart';
import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/money/money_formatter.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/core/widgets/app_year_month_wheel.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_year_paging_controller.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/presentation/bookkeeping_record_list.dart';
import 'package:anbookkeep/features/smart_bookkeeping/presentation/smart_bookkeeping_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _metricSelectorArrowWidth = AppSizes.iconAuxiliary;
const _metricSelectorVerticalInset = 2.0;
const _quickActionButtonSize = 56.0;
const _quickActionImageDistance =
    _quickActionButtonSize + AppSpacing.componentGap;
const _quickActionCameraDistance =
    _quickActionImageDistance +
    _quickActionButtonSize +
    AppSpacing.componentGap;
const _quickActionStackHeight =
    _quickActionCameraDistance + _quickActionButtonSize;
const _quickActionRotationTurns = 1.125; // 360° + 45°
const _quickActionAnimationDuration = Duration(milliseconds: 360);

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage>
    with TickerProviderStateMixin {
  String? _selectedMonth;
  String? _visibleMonth;
  late LedgerYearPagingController _pagingController;
  final _listController = BookkeepingRecordListController();
  bool _initialLoading = true;
  String? _loadError;
  Timer? _quickActionTimer;
  bool _quickActionLongPressed = false;
  bool _quickActionsExpanded = false;
  late final AnimationController _quickActionRotationController;
  late final AnimationController _quickActionPopController;

  @override
  void initState() {
    super.initState();
    _quickActionRotationController = AnimationController(
      vsync: this,
      duration: _quickActionAnimationDuration,
    );
    _quickActionPopController = AnimationController(
      vsync: this,
      duration: _quickActionAnimationDuration,
      reverseDuration: _quickActionAnimationDuration,
    );
    _pagingController = _createPagingController();
    Future<void>.microtask(_loadInitialYear);
  }

  @override
  void dispose() {
    _quickActionTimer?.cancel();
    _quickActionRotationController.dispose();
    _quickActionPopController.dispose();
    _pagingController.invalidate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final month =
        _visibleMonth ??
        _selectedMonth ??
        _pagingController.newestMonth ??
        LocalMinute.now().yearMonth;
    final monthPage = _pagingController.pageFor(month);
    return Scaffold(
      appBar: _buildAppBar(context),
      body: SafeArea(
        top: false,
        child: _initialLoading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : _loadError != null
            ? Center(child: Text(_loadError!))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageHorizontal,
                      AppSpacing.pageTop,
                      AppSpacing.pageHorizontal,
                      AppSpacing.componentGap,
                    ),
                    child: _AnalysisCard(
                      month: month,
                      records:
                          monthPage?.records ?? const <BookkeepingRecord>[],
                      useGrouping:
                          settings.amountDisplayFormat ==
                          AmountDisplayFormat.grouped,
                      incomeColor: settings.incomeColor,
                      expenseColor: settings.expenseColor,
                      onMonthTap: () => _selectMonth(month),
                      onTap: () => context.push(AppRoutes.analytics),
                    ),
                  ),
                  Expanded(
                    child: BookkeepingRecordList(
                      controller: _listController,
                      pages: _pagingController.pages,
                      centerMonth:
                          _selectedMonth ?? _pagingController.newestMonth,
                      onVisibleMonthChanged: (value) {
                        if (_visibleMonth != value) {
                          setState(() => _visibleMonth = value);
                        }
                      },
                      onReachTop: _loadNewerYear,
                      onReachBottom: _loadOlderYear,
                      onDelete: _delete,
                      onTap: (record) async {
                        await context.push(
                          '${AppRoutes.bookkeeping}/${record.entry.id}/edit',
                        );
                        await _refreshAfterMutation();
                      },
                      timePrecision: settings.timePrecision,
                      useGrouping:
                          settings.amountDisplayFormat ==
                          AmountDisplayFormat.grouped,
                      incomeColor: settings.incomeColor,
                      expenseColor: settings.expenseColor,
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: SizedBox(
        width: _quickActionButtonSize,
        height: _quickActionStackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            _AnimatedQuickActionButton(
              controller: _quickActionPopController,
              distance: _quickActionCameraDistance,
              icon: Icons.camera_alt_outlined,
              label: '拍照记账',
              onPressed: _openCameraBookkeeping,
            ),
            _AnimatedQuickActionButton(
              controller: _quickActionPopController,
              distance: _quickActionImageDistance,
              icon: Icons.image_outlined,
              label: '图片记账',
              onPressed: _openImageBookkeeping,
            ),
            Positioned(
              bottom: 0,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) {
                  _quickActionLongPressed = false;
                  _quickActionTimer?.cancel();
                  _quickActionTimer = Timer(
                    const Duration(milliseconds: 200),
                    () {
                      if (!mounted || _quickActionsExpanded) return;
                      _quickActionLongPressed = true;
                      _expandQuickActions();
                    },
                  );
                },
                onPointerUp: (_) => _quickActionTimer?.cancel(),
                onPointerCancel: (_) => _quickActionTimer?.cancel(),
                child: Semantics(
                  button: true,
                  excludeSemantics: true,
                  label: _quickActionsExpanded ? '收起AI记账' : '记账',
                  onTap: _activateMainQuickAction,
                  onLongPress: _expandQuickActions,
                  child: FloatingActionButton(
                    shape: const CircleBorder(),
                    onPressed: _activateMainQuickAction,
                    child: RotationTransition(
                      turns:
                          Tween<double>(
                            begin: 0,
                            end: _quickActionRotationTurns,
                          ).animate(
                            CurvedAnimation(
                              parent: _quickActionRotationController,
                              curve: Curves.easeInOutCubic,
                            ),
                          ),
                      child: const Icon(Icons.add_rounded),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LedgerYearPagingController _createPagingController() {
    final repository = ref.read(bookkeepingRepositoryProvider);
    return LedgerYearPagingController(
      loadYear: repository.getYear,
      findOlderYear: repository.previousDataYear,
      findNewerYear: repository.nextDataYear,
    );
  }

  void _activateMainQuickAction() {
    _quickActionTimer?.cancel();
    if (_quickActionLongPressed) {
      _quickActionLongPressed = false;
      return;
    }
    if (_quickActionsExpanded) {
      _collapseQuickActions();
    } else {
      _openBookkeeping();
    }
  }

  Future<void> _loadInitialYear() async {
    try {
      final repository = ref.read(bookkeepingRepositoryProvider);
      final month =
          await repository.latestMonth() ?? LocalMinute.now().yearMonth;
      await _pagingController.initialize(month);
      if (!mounted) return;
      setState(() {
        _visibleMonth = month;
        _initialLoading = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      _listController.jumpToStart();
      await _prefetchAroundCurrent();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _initialLoading = false;
          _loadError = appErrorMessage(error, fallback: '账单加载失败，请重试');
        });
      }
    }
  }

  Future<void> _prefetchAroundCurrent() async {
    await _loadOlderYear();
    await _loadNewerYear();
  }

  Future<void> _loadNewerYear() async {
    final controller = _pagingController;
    if (controller.isLoadingNewer || !controller.hasNewer) return;
    try {
      final changed = await controller.loadNewer();
      if (!changed || !mounted || !identical(controller, _pagingController)) {
        return;
      }
      setState(() {});
    } on Object catch (error, stackTrace) {
      _log.error(
        'load_newer_year_failed',
        cause: error,
        stackTrace: stackTrace,
      );
      // Keep the current page stable; the next scroll can retry.
    }
  }

  Future<void> _loadOlderYear() async {
    final controller = _pagingController;
    if (controller.isLoadingOlder || !controller.hasOlder) return;
    try {
      final changed = await controller.loadOlder();
      if (changed && mounted && identical(controller, _pagingController)) {
        setState(() {});
      }
    } on Object catch (error, stackTrace) {
      _log.error(
        'load_older_year_failed',
        cause: error,
        stackTrace: stackTrace,
      );
      // Keep the current page stable; the next scroll can retry.
    }
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        tooltip: '设置',
        onPressed: () async {
          await context.push(AppRoutes.settings);
          await _refreshAfterMutation();
        },
        style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        icon: const Icon(Icons.menu_rounded),
      ),
      actions: [
        IconButton(
          tooltip: '搜索',
          onPressed: () async {
            await context.push(AppRoutes.search);
            await _refreshAfterMutation();
          },
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }

  Future<void> _selectMonth(String currentMonth) async {
    final parts = currentMonth.split('-');
    final selectedYear = int.parse(parts[0]);
    final selectedMonth = int.parse(parts[1]);
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _MonthWheelSheet(
        initialYear: selectedYear,
        initialMonth: selectedMonth,
      ),
    );
    if (result != null && mounted) {
      await _showMonth(result, selectedMonth: result, rejectEmptyMonth: true);
    }
  }

  Future<void> _showMonth(
    String month, {
    String? selectedMonth,
    bool rejectEmptyMonth = false,
  }) async {
    final nextController = _createPagingController();
    try {
      await nextController.initialize(month);
      if (!mounted) return;
      if (rejectEmptyMonth &&
          (nextController.pageFor(month)?.records.isEmpty ?? true)) {
        nextController.invalidate();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('该月份暂无账单')));
        return;
      }
      final isUserSelectedMonth = selectedMonth != null;
      if (isUserSelectedMonth) {
        _listController.waitForUserScrollBeforePrefetch();
      }
      _pagingController.invalidate();
      setState(() {
        _pagingController = nextController;
        _selectedMonth = selectedMonth;
        _visibleMonth = month;
        _loadError = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      _listController.jumpToStart(
        waitForUserScrollBeforePrefetch: isUserSelectedMonth,
      );
      if (!isUserSelectedMonth) {
        await _prefetchAroundCurrent();
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '月份加载失败，请重试')),
          ),
        );
      }
    }
  }

  Future<void> _refreshAfterMutation() async {
    if (!mounted || _initialLoading) return;
    try {
      if (_selectedMonth == null) {
        final repository = ref.read(bookkeepingRepositoryProvider);
        final latest =
            await repository.latestMonth() ?? LocalMinute.now().yearMonth;
        if (latest != _pagingController.newestMonth) {
          await _showMonth(latest);
          return;
        }
      }
      await _pagingController.refreshLoaded();
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appErrorMessage(error, fallback: '账单刷新失败，请重试')),
          ),
        );
      }
    }
  }

  Future<void> _openBookkeeping() async {
    await context.push(AppRoutes.bookkeeping);
    await _refreshAfterMutation();
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
    await _refreshAfterMutation();
  }

  Future<void> _openCameraBookkeeping() async {
    await _collapseQuickActions();
    if (!mounted) return;
    await SmartBookkeepingLauncher.camera(context, ref);
    await _refreshAfterMutation();
  }

  Future<void> _openImageBookkeeping() async {
    await _collapseQuickActions();
    if (!mounted) return;
    await SmartBookkeepingLauncher.gallery(context, ref);
    await _refreshAfterMutation();
  }

  Future<void> _expandQuickActions() async {
    if (_quickActionsExpanded) return;
    setState(() => _quickActionsExpanded = true);
    await Future.wait([
      _quickActionRotationController.forward(),
      _quickActionPopController.forward(),
    ]);
  }

  Future<void> _collapseQuickActions() async {
    if (!_quickActionsExpanded &&
        _quickActionRotationController.isDismissed &&
        _quickActionPopController.isDismissed) {
      return;
    }
    if (mounted) setState(() => _quickActionsExpanded = false);
    await Future.wait([
      _quickActionRotationController.reverse(),
      _quickActionPopController.reverse(),
    ]);
  }
}

const _log = AppLogger('Detail');

class _AnimatedQuickActionButton extends StatelessWidget {
  const _AnimatedQuickActionButton({
    required this.controller,
    required this.distance,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final AnimationController controller;
  final double distance;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      bottom: distance,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final value = animation.value;
          return IgnorePointer(
            ignoring: value < 0.999,
            child: ExcludeSemantics(
              excluding: value == 0,
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, distance * (1 - value)),
                  child: Transform.scale(
                    scale: 0.82 + value * 0.18,
                    child: child,
                  ),
                ),
              ),
            ),
          );
        },
        child: FloatingActionButton(
          heroTag: label,
          tooltip: label,
          shape: const CircleBorder(),
          onPressed: onPressed,
          child: Icon(icon),
        ),
      ),
    );
  }
}

class _MonthWheelSheet extends StatefulWidget {
  const _MonthWheelSheet({
    required this.initialYear,
    required this.initialMonth,
  });

  final int initialYear;
  final int initialMonth;

  @override
  State<_MonthWheelSheet> createState() => _MonthWheelSheetState();
}

class _MonthWheelSheetState extends State<_MonthWheelSheet> {
  late int _year = widget.initialYear.clamp(2020, DateTime.now().year);
  late int _month = widget.initialMonth.clamp(1, 12);
  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    return AppBottomSheetLayout(
      title: '选择月份',
      actions: AppDialogActions(
        onCancel: () => Navigator.pop(context),
        onConfirm: () => Navigator.pop(
          context,
          '$_year-${_month.toString().padLeft(2, '0')}',
        ),
      ),
      child: AppYearMonthWheel(
        initialYear: _year,
        initialMonth: _month,
        maxYear: currentYear,
        height: 132,
        onChanged: (value) {
          _year = value.year;
          _month = value.month;
        },
      ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.month,
    required this.records,
    required this.useGrouping,
    required this.incomeColor,
    required this.expenseColor,
    required this.onMonthTap,
    required this.onTap,
  });

  final String month;
  final List<BookkeepingRecord> records;
  final bool useGrouping;
  final Color incomeColor;
  final Color expenseColor;
  final VoidCallback onMonthTap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var incomeMinor = 0;
    var expenseMinor = 0;
    for (final record in records) {
      if (record.type == EntryType.income) {
        incomeMinor += record.entry.amountMinor;
      } else {
        expenseMinor += record.entry.amountMinor;
      }
    }
    final balance = incomeMinor - expenseMinor;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBackground = isDark
        ? AppColors.darkCardBackground
        : AppColors.lightCardBackground;
    final glowStart = Color.alphaBlend(
      colorScheme.primary.withAlpha(
        isDark ? AppAlpha.glowDark : AppAlpha.glowLight,
      ),
      cardBackground,
    );
    return AppCard(
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [glowStart, cardBackground],
        stops: const [0.0, 0.62],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        onTap: onMonthTap,
                        child: Padding(
                          // Balance the trailing arrow so the date text,
                          // rather than the combined control, is column-centered.
                          padding: const EdgeInsets.only(
                            left: _metricSelectorArrowWidth,
                            top: _metricSelectorVerticalInset,
                            bottom: _metricSelectorVerticalInset,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _monthLabel(month),
                                style: textTheme.titleSmall,
                              ),
                              const Icon(
                                Icons.arrow_drop_down_rounded,
                                size: _metricSelectorArrowWidth,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: AppSpacing.componentGap),
              Row(
                children: [
                  _Metric(
                    label: '收入',
                    value: records.isEmpty
                        ? '-'
                        : MoneyFormatter.formatMinorUnits(
                            incomeMinor,
                            prefix: '+',
                            useGrouping: useGrouping,
                          ),
                    color: incomeColor,
                  ),
                  _Metric(
                    label: '支出',
                    value: records.isEmpty
                        ? '-'
                        : MoneyFormatter.formatMinorUnits(
                            expenseMinor,
                            prefix: '-',
                            useGrouping: useGrouping,
                          ),
                    color: expenseColor,
                  ),
                  _Metric(
                    label: '结余',
                    value: records.isEmpty ? '-' : _formatBalance(balance),
                    color: balance > 0
                        ? incomeColor
                        : balance < 0
                        ? expenseColor
                        : colorScheme.onSurface,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _monthLabel(String value) {
    final parts = value.split('-');
    return '${parts[0]}年${int.parse(parts[1])}月';
  }

  String _formatBalance(int balance) {
    if (balance == 0) return '￥0.00';
    return MoneyFormatter.formatMinorUnits(
      balance,
      prefix: balance > 0 ? '+' : '-',
      useGrouping: useGrouping,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
