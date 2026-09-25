import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_theme.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/money/money_formatter.dart';
import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_card.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/core/widgets/app_dialog.dart';
import 'package:anbookkeep/core/widgets/app_year_month_wheel.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/analytics/data/analytics_repository.dart';
import 'package:anbookkeep/features/analytics/domain/analytics_summary.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _metricSelectorArrowWidth = AppSizes.iconAuxiliary;
const _metricSelectorVerticalInset = 2.0;
const _amountAxisReservedSize = 36.0;

enum _AnalyticsDimension { expense, income, balance }

enum _AnalyticsPeriod { month, year, all }

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  _AnalyticsDimension _dimension = _AnalyticsDimension.expense;
  _AnalyticsPeriod _period = _AnalyticsPeriod.month;
  DateTime _selectedDate = DateTime.now();
  bool _barChart = false;
  bool _progressView = false;
  Future<Map<_AnalyticsDimension, AnalyticsDataset>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<_AnalyticsDimension, AnalyticsDataset>> _load() async {
    final repository = ref.read(analyticsRepositoryProvider);
    final granularity = switch (_period) {
      _AnalyticsPeriod.month => AnalyticsGranularity.day,
      _AnalyticsPeriod.year => AnalyticsGranularity.month,
      _AnalyticsPeriod.all => AnalyticsGranularity.year,
    };
    String? startDate;
    String? endDate;
    if (_period != _AnalyticsPeriod.all) {
      final year = _selectedDate.year.toString().padLeft(4, '0');
      if (_period == _AnalyticsPeriod.year) {
        startDate = '$year-01-01';
        endDate = '$year-12-31';
      } else {
        final month = _selectedDate.month.toString().padLeft(2, '0');
        final lastDay = DateTime(
          _selectedDate.year,
          _selectedDate.month + 1,
          0,
        ).day;
        startDate = '$year-$month-01';
        endDate = '$year-$month-${lastDay.toString().padLeft(2, '0')}';
      }
    }
    final values = await Future.wait([
      for (final dimension in _AnalyticsDimension.values)
        repository.load(
          type: _dimensionType(dimension),
          granularity: granularity,
          startDate: startDate,
          endDate: endDate,
        ),
    ]);
    return {
      for (var index = 0; index < _AnalyticsDimension.values.length; index++)
        _AnalyticsDimension.values[index]: values[index],
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(ledgerChangeRevisionProvider, (previous, next) {
      if (previous != null && previous != next) {
        final future = _load();
        setState(() {
          _future = future;
        });
      }
    });
    final settings = ref.watch(appSettingsProvider);
    final useGrouping =
        settings.amountDisplayFormat == AmountDisplayFormat.grouped;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: SizedBox(
          width: 240,
          height: AppSizes.segmentedControl,
          child: AppSegmentedButton<_AnalyticsDimension>(
            compact: true,
            segments: const [
              ButtonSegment(
                value: _AnalyticsDimension.expense,
                label: Text('支出'),
              ),
              ButtonSegment(
                value: _AnalyticsDimension.income,
                label: Text('收入'),
              ),
              ButtonSegment(
                value: _AnalyticsDimension.balance,
                label: Text('结余'),
              ),
            ],
            selected: {_dimension},
            onSelectionChanged: (value) {
              setState(() => _dimension = value.first);
            },
          ),
        ),
      ),
      body: FutureBuilder<Map<_AnalyticsDimension, AnalyticsDataset>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                appErrorMessage(snapshot.error!, fallback: '统计加载失败，请重试'),
              ),
            );
          }
          final dataset = snapshot.data?[_dimension];
          final hasDimensionData = (dataset?.recordCount ?? 0) > 0;
          return ListView(
            padding: AppSpacing.pagePadding,
            children: [
              _AnalyticsSummaryCard(
                dataset: dataset,
                dimension: _dimension,
                period: _period,
                selectedDate: _selectedDate,
                hasData: hasDimensionData,
                onPeriodTap: _selectPeriod,
                useGrouping: useGrouping,
                incomeColor: settings.incomeColor,
                expenseColor: settings.expenseColor,
              ),
              if (hasDimensionData) ...[
                const SizedBox(height: AppSpacing.componentGap),
                _TrendCard(
                  values: dataset!.trendMinorByKey,
                  dimension: _dimension,
                  period: _period,
                  selectedDate: _selectedDate,
                  barChart: _barChart,
                  onToggle: () => setState(() => _barChart = !_barChart),
                  useGrouping: useGrouping,
                ),
                if (_dimension != _AnalyticsDimension.balance) ...[
                  const SizedBox(height: AppSpacing.componentGap),
                  _CategoryCard(
                    items: dataset.categories,
                    dimension: _dimension,
                    progressView: _progressView,
                    onToggle: () =>
                        setState(() => _progressView = !_progressView),
                    useGrouping: useGrouping,
                    incomeColor: settings.incomeColor,
                    expenseColor: settings.expenseColor,
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _selectPeriod() async {
    final dataRange = await ref
        .read(bookkeepingRepositoryProvider)
        .dataYearRange();
    if (!mounted) return;
    final bounds = AppDatePolicy.pickerBounds(
      dataMinimumYear: dataRange?.minYear,
      dataMaximumYear: dataRange?.maxYear,
      anchorYears: [_selectedDate.year],
    );
    final result = await showModalBottomSheet<(_AnalyticsPeriod, DateTime)>(
      context: context,
      builder: (context) => _PeriodSheet(
        period: _period,
        date: _selectedDate,
        minYear: bounds.minYear,
        maxYear: bounds.maxYear,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _period = result.$1;
      _selectedDate = result.$2;
      _future = _load();
    });
  }
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({
    required this.period,
    required this.date,
    required this.minYear,
    required this.maxYear,
  });

  final _AnalyticsPeriod period;
  final DateTime date;
  final int minYear;
  final int maxYear;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late _AnalyticsPeriod period = widget.period;
  late int selectedYear = widget.date.year.clamp(
    widget.minYear,
    widget.maxYear,
  );
  late int selectedMonth = widget.date.month;
  DateTime get date => DateTime(selectedYear, selectedMonth);

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetLayout(
      title: '时间范围',
      actions: AppDialogActions(
        onCancel: () => Navigator.pop(context),
        onConfirm: () => Navigator.pop(context, (period, date)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSegmentedButton<_AnalyticsPeriod>(
            segments: const [
              ButtonSegment(value: _AnalyticsPeriod.month, label: Text('月')),
              ButtonSegment(value: _AnalyticsPeriod.year, label: Text('年')),
              ButtonSegment(value: _AnalyticsPeriod.all, label: Text('全部')),
            ],
            selected: {period},
            onSelectionChanged: (values) =>
                setState(() => period = values.first),
          ),
          if (period != _AnalyticsPeriod.all) ...[
            const SizedBox(height: AppSpacing.componentGap),
            AppYearMonthWheel(
              initialYear: selectedYear,
              initialMonth: selectedMonth,
              minYear: widget.minYear,
              maxYear: widget.maxYear,
              showMonth: period == _AnalyticsPeriod.month,
              height: 116,
              onChanged: (value) {
                selectedYear = value.year;
                selectedMonth = value.month;
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _AnalyticsSummaryCard extends StatelessWidget {
  const _AnalyticsSummaryCard({
    required this.dataset,
    required this.dimension,
    required this.period,
    required this.selectedDate,
    required this.hasData,
    required this.onPeriodTap,
    required this.useGrouping,
    required this.incomeColor,
    required this.expenseColor,
  });

  final AnalyticsDataset? dataset;
  final _AnalyticsDimension dimension;
  final _AnalyticsPeriod period;
  final DateTime selectedDate;
  final bool hasData;
  final VoidCallback onPeriodTap;
  final bool useGrouping;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    final denominator = switch (period) {
      _AnalyticsPeriod.month => DateTime(
        selectedDate.year,
        selectedDate.month + 1,
        0,
      ).day,
      _AnalyticsPeriod.year => 12,
      _AnalyticsPeriod.all => dataset?.yearCount ?? 0,
    };
    final summary = AnalyticsSummary.fromAggregate(
      totalMinor: dataset?.totalMinor ?? 0,
      recordCount: dataset?.recordCount ?? 0,
      denominator: denominator,
    );
    final labels = switch (dimension) {
      _AnalyticsDimension.expense => ('总支出', '日均'),
      _AnalyticsDimension.income => ('总收入', '日均'),
      _AnalyticsDimension.balance => ('总结余', '日均'),
    };
    final averageLabel = period == _AnalyticsPeriod.month
        ? '日均'
        : period == _AnalyticsPeriod.year
        ? '月均'
        : '年均';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBackground = isDark
        ? AppColors.darkCardBackground
        : AppColors.lightCardBackground;
    final glowStart = Color.alphaBlend(
      theme.colorScheme.primary.withAlpha(
        isDark ? AppAlpha.glowDark : AppAlpha.glowLight,
      ),
      cardBackground,
    );
    final periodLabel = switch (period) {
      _AnalyticsPeriod.month => '${selectedDate.year}年${selectedDate.month}月',
      _AnalyticsPeriod.year => '${selectedDate.year}年',
      _AnalyticsPeriod.all => '全部',
    };
    return AppCard(
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [glowStart, cardBackground],
        stops: const [0.0, 0.62],
      ),
      clipBehavior: Clip.antiAlias,
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
                      onTap: onPeriodTap,
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
                              periodLabel,
                              style: theme.textTheme.titleSmall,
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
                _SummaryMetric(
                  label: labels.$1,
                  value: hasData
                      ? _amount(summary.totalMinor, useGrouping)
                      : '-',
                  color: _signedAmountColor(
                    summary.totalMinor,
                    incomeColor,
                    expenseColor,
                    theme.colorScheme.onSurface,
                  ),
                ),
                _SummaryMetric(
                  label: averageLabel,
                  value: hasData
                      ? _amount(summary.averageMinor, useGrouping)
                      : '-',
                  color: _signedAmountColor(
                    summary.averageMinor,
                    incomeColor,
                    expenseColor,
                    theme.colorScheme.onSurface,
                  ),
                ),
                _SummaryMetric(
                  label: '总笔数',
                  value: hasData ? '${summary.recordCount}' : '-',
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
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

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.values,
    required this.dimension,
    required this.period,
    required this.selectedDate,
    required this.barChart,
    required this.onToggle,
    required this.useGrouping,
  });
  final Map<String, int> values;
  final _AnalyticsDimension dimension;
  final _AnalyticsPeriod period;
  final DateTime selectedDate;
  final bool barChart;
  final VoidCallback onToggle;
  final bool useGrouping;

  @override
  Widget build(BuildContext context) {
    final keys = switch (period) {
      _AnalyticsPeriod.month => [
        for (
          var day = 1;
          day <= DateTime(selectedDate.year, selectedDate.month + 1, 0).day;
          day++
        )
          day.toString().padLeft(2, '0'),
      ],
      _AnalyticsPeriod.year => [
        for (var month = 1; month <= 12; month++)
          month.toString().padLeft(2, '0'),
      ],
      _AnalyticsPeriod.all => values.keys.toList()..sort(),
    };
    final spots = [
      for (var i = 0; i < keys.length; i++)
        FlSpot(i.toDouble(), (values[keys[i]] ?? 0).toDouble() / 100),
    ];
    final maxY = spots.map((e) => e.y).fold<double>(0, (a, b) => a > b ? a : b);
    final minY = spots.map((e) => e.y).fold<double>(0, (a, b) => a < b ? a : b);
    final chartMinY = minY < 0 ? minY * 1.15 : 0.0;
    final chartMaxY = maxY > 0 ? maxY * 1.15 : 1.0;
    final yInterval = (chartMaxY - chartMinY) / 5;
    final averageY = spots.isEmpty
        ? 0.0
        : spots.fold<double>(0, (sum, spot) => sum + spot.y) / spots.length;
    final visibleXIndexes = _sampleAxisIndexes(keys.length, maxCount: 12);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final titles = FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: yInterval,
          reservedSize: _amountAxisReservedSize,
          minIncluded: false,
          maxIncluded: false,
          getTitlesWidget: (value, meta) => Text(
            _compactAxisAmount(value),
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (value != index.toDouble() ||
                index < 0 ||
                index >= keys.length ||
                !visibleXIndexes.contains(index)) {
              return const SizedBox.shrink();
            }
            return Text(
              _axisPeriodLabel(keys[index]),
              style: theme.textTheme.labelSmall,
            );
          },
        ),
      ),
    );
    final extraLines = ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: averageY,
          color: primary.withAlpha(AppAlpha.selectedFill),
          strokeWidth: 1.2,
          dashArray: [6, 4],
        ),
      ],
    );
    return AppCard(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          children: [
            Row(
              children: [
                Text('趋势分析', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: onToggle,
                  icon: Icon(
                    barChart
                        ? Icons.show_chart_rounded
                        : Icons.bar_chart_rounded,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 210,
              child: barChart
                  ? BarChart(
                      BarChartData(
                        minY: chartMinY,
                        maxY: chartMaxY,
                        titlesData: titles,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        extraLinesData: extraLines,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            fitInsideHorizontally: true,
                            fitInsideVertically: true,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              if (groupIndex < 0 || groupIndex >= keys.length) {
                                return null;
                              }
                              final minor = values[keys[groupIndex]] ?? 0;
                              return BarTooltipItem(
                                '${_trendLabel(period, keys[groupIndex])}\n'
                                '${_trendAmount(minor, dimension, useGrouping)}',
                                Theme.of(context).textTheme.labelSmall!
                                    .copyWith(color: Colors.white),
                              );
                            },
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < spots.length; i++)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: spots[i].y,
                                  color: primary,
                                  width: 12,
                                  borderRadius: spots[i].y >= 0
                                      ? const BorderRadius.only(
                                          topLeft: Radius.circular(4),
                                          topRight: Radius.circular(4),
                                        )
                                      : const BorderRadius.only(
                                          bottomLeft: Radius.circular(4),
                                          bottomRight: Radius.circular(4),
                                        ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: chartMinY,
                        maxY: chartMaxY,
                        titlesData: titles,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        extraLinesData: extraLines,
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            fitInsideHorizontally: true,
                            fitInsideVertically: true,
                            getTooltipItems: (touchedSpots) => [
                              for (final spot in touchedSpots)
                                _lineTooltipItem(
                                  spot,
                                  keys,
                                  values,
                                  period,
                                  dimension,
                                  useGrouping,
                                  Theme.of(context).textTheme.labelSmall!
                                      .copyWith(color: Colors.white),
                                ),
                            ],
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            color: primary,
                            dotData: const FlDotData(show: false),
                            isCurved: true,
                            curveSmoothness: 0.28,
                            preventCurveOverShooting: true,
                            isStrokeCapRound: true,
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  primary.withAlpha(AppAlpha.selectedFill),
                                  primary.withAlpha(0),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({
    required this.items,
    required this.dimension,
    required this.progressView,
    required this.onToggle,
    required this.useGrouping,
    required this.incomeColor,
    required this.expenseColor,
  });
  final List<AnalyticsCategoryTotal> items;
  final _AnalyticsDimension dimension;
  final bool progressView;
  final VoidCallback onToggle;
  final bool useGrouping;
  final Color incomeColor;
  final Color expenseColor;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  int? _touchedSectionIndex;

  @override
  void didUpdateWidget(_CategoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dimension != widget.dimension ||
        !identical(oldWidget.items, widget.items)) {
      _touchedSectionIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <(AnalyticsCategoryTotal, int)>[
      for (final item in widget.items) (item, item.amountMinor),
    ];
    final pieItems = items.length <= 9
        ? items
        : [
            ...items.take(9),
            (
              items.skip(9).first.$1,
              items.skip(9).fold(0, (sum, item) => sum + item.$2),
            ),
          ];
    final total = items.fold<int>(0, (sum, item) => sum + item.$2);
    final touchedIndex =
        _touchedSectionIndex != null &&
            _touchedSectionIndex! >= 0 &&
            _touchedSectionIndex! < pieItems.length
        ? _touchedSectionIndex
        : null;
    final hasOther = items.length > 9;
    final pieLabels = [
      for (var i = 0; i < pieItems.length; i++)
        hasOther && i == 9 ? '其他' : pieItems[i].$1.name,
    ];
    final pieColors = [
      for (var i = 0; i < pieItems.length; i++)
        hasOther && i == 9
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Color(pieItems[i].$1.colorValue),
    ];
    return AppCard(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          children: [
            Row(
              children: [
                Text('分类分析', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: widget.onToggle,
                  icon: Icon(
                    widget.progressView
                        ? Icons.donut_large_rounded
                        : Icons.view_list_rounded,
                  ),
                ),
              ],
            ),
            if (!widget.progressView) ...[
              SizedBox(
                height: 220,
                child: Stack(
                  children: [
                    PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (!mounted) return;
                            final index =
                                response?.touchedSection?.touchedSectionIndex;
                            final next =
                                index != null &&
                                    index >= 0 &&
                                    index < pieItems.length
                                ? index
                                : null;
                            if (_touchedSectionIndex != next) {
                              setState(() => _touchedSectionIndex = next);
                            }
                          },
                        ),
                        sectionsSpace: 0,
                        centerSpaceRadius: 46,
                        sections: [
                          for (var i = 0; i < pieItems.length; i++)
                            PieChartSectionData(
                              value: pieItems[i].$2.toDouble(),
                              title: total == 0
                                  ? '0%'
                                  : '${(pieItems[i].$2 * 100 / total).toStringAsFixed(0)}%',
                              color: pieColors[i],
                              radius: touchedIndex == i ? 64 : 58,
                              titleStyle: Theme.of(context)
                                  .textTheme
                                  .labelSmall!
                                  .copyWith(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
                    if (touchedIndex != null)
                      Positioned(
                        top: AppSpacing.xxs,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .inverseSurface
                                    .withAlpha(AppAlpha.overlayStrong),
                                borderRadius: BorderRadius.circular(
                                  AppRadii.compact,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.componentGap,
                                  vertical: AppSpacing.controlGap,
                                ),
                                child: Text(
                                  '${pieLabels[touchedIndex]}\n'
                                  '${_trendAmount(pieItems[touchedIndex].$2, widget.dimension, widget.useGrouping)} · '
                                  '${total == 0 ? '0.00' : (pieItems[touchedIndex].$2 * 100 / total).toStringAsFixed(2)}%',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onInverseSurface,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.controlGap),
              Align(
                alignment: Alignment.center,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: AppSpacing.componentGap,
                  runSpacing: AppSpacing.controlGap,
                  children: [
                    for (var i = 0; i < pieItems.length; i++)
                      _CategoryLegend(
                        color: pieColors[i],
                        text:
                            '${pieLabels[i]} ${_trendAmount(pieItems[i].$2, widget.dimension, widget.useGrouping)}'
                            '(${total == 0 ? '0.00' : (pieItems[i].$2 * 100 / total).toStringAsFixed(2)}%)',
                      ),
                  ],
                ),
              ),
            ],
            if (widget.progressView)
              for (var i = 0; i < items.length; i++)
                _CategoryRow(
                  item: items[i],
                  total: total,
                  color: Color(items[i].$1.colorValue),
                  useGrouping: widget.useGrouping,
                  amountColor: items[i].$1.type == EntryType.income
                      ? widget.incomeColor
                      : widget.expenseColor,
                ),
          ],
        ),
      ),
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSpacing.xs,
          height: AppSpacing.xs,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(text, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.item,
    required this.total,
    required this.color,
    required this.useGrouping,
    required this.amountColor,
  });
  final (AnalyticsCategoryTotal, int) item;
  final int total;
  final Color color;
  final bool useGrouping;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    final double percent = total == 0 ? 0 : item.$2 / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.controlGap),
      child: Row(
        children: [
          CategoryIcon(
            code: item.$1.iconCode,
            color: color,
            size: AppSizes.categoryIcon,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.$1.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${MoneyFormatter.formatMinorUnits(item.$2, prefix: item.$1.type == EntryType.income ? '+' : '-', useGrouping: useGrouping)}(${(percent * 100).toStringAsFixed(2)}%)',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: amountColor),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.controlGap),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  child: LinearProgressIndicator(
                    value: percent,
                    color: color,
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Set<int> _sampleAxisIndexes(int count, {required int maxCount}) {
  if (count <= 0) return const {};
  if (count <= maxCount) {
    return {for (var index = 0; index < count; index++) index};
  }
  return {
    for (var slot = 0; slot < maxCount; slot++)
      (slot * (count - 1) / (maxCount - 1)).round(),
  };
}

String _axisPeriodLabel(String value) =>
    int.tryParse(value)?.toString() ?? value;

String _compactAxisAmount(double value) {
  final normalized = value.abs() < .5 ? 0.0 : value;
  final absolute = normalized.abs();
  if (absolute >= 10000) return '${_oneDecimal(normalized / 10000)}w';
  if (absolute >= 1000) return '${_oneDecimal(normalized / 1000)}k';
  return normalized.round().toString();
}

String _oneDecimal(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

EntryType? _dimensionType(_AnalyticsDimension dimension) => switch (dimension) {
  _AnalyticsDimension.expense => EntryType.expense,
  _AnalyticsDimension.income => EntryType.income,
  _AnalyticsDimension.balance => null,
};

String _trendLabel(_AnalyticsPeriod period, String key) => switch (period) {
  _AnalyticsPeriod.month => '${int.parse(key)}日',
  _AnalyticsPeriod.year => '${int.parse(key)}月',
  _AnalyticsPeriod.all => '$key年',
};

String _trendAmount(
  int minor,
  _AnalyticsDimension dimension,
  bool useGrouping,
) {
  final signedMinor = dimension == _AnalyticsDimension.expense ? -minor : minor;
  return _amount(signedMinor, useGrouping);
}

LineTooltipItem _lineTooltipItem(
  LineBarSpot spot,
  List<String> keys,
  Map<String, int> values,
  _AnalyticsPeriod period,
  _AnalyticsDimension dimension,
  bool useGrouping,
  TextStyle textStyle,
) {
  final index = spot.x.round().clamp(0, keys.length - 1).toInt();
  final key = keys[index];
  return LineTooltipItem(
    '${_trendLabel(period, key)}\n'
    '${_trendAmount(values[key] ?? 0, dimension, useGrouping)}',
    textStyle,
  );
}

String _amount(int minor, bool useGrouping) {
  if (minor == 0) return '￥0.00';
  return MoneyFormatter.formatMinorUnits(
    minor,
    prefix: minor > 0 ? '+' : '-',
    useGrouping: useGrouping,
  );
}

Color _signedAmountColor(
  int minor,
  Color incomeColor,
  Color expenseColor,
  Color zeroColor,
) => minor > 0
    ? incomeColor
    : minor < 0
    ? expenseColor
    : zeroColor;
