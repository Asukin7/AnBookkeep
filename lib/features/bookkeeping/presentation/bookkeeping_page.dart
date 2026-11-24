import 'dart:async';
import 'dart:math' as math;

import 'package:anbookkeep/app/theme/app_spacing.dart';
import 'package:anbookkeep/app/theme/app_tokens.dart';
import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/datetime/app_date_policy.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/core/settings/app_settings.dart';
import 'package:anbookkeep/core/widgets/app_segmented_control.dart';
import 'package:anbookkeep/core/widgets/app_bottom_sheet.dart';
import 'package:anbookkeep/core/widgets/category_icon.dart';
import 'package:anbookkeep/features/bookkeeping/data/bookkeeping_repository.dart';
import 'package:anbookkeep/features/bookkeeping/domain/calculator.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/bookkeeping/domain/save_occurrence.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _calculatorKeyInset = 3.0;
const _categoryColumnCount = 4;
const _categoryTileExtent = 78.0;

class BookkeepingPage extends ConsumerStatefulWidget {
  const BookkeepingPage({
    this.transactionId,
    this.initialDraft,
    this.returnDraft = false,
    super.key,
  });

  final String? transactionId;
  final SmartBookkeepingDraft? initialDraft;
  final bool returnDraft;

  bool get isEditing => transactionId != null;

  @override
  ConsumerState<BookkeepingPage> createState() => _BookkeepingPageState();
}

class _BookkeepingPageState extends ConsumerState<BookkeepingPage> {
  final _noteController = TextEditingController();
  final _calculator = CalculatorController();
  final _categoryScrollController = ScrollController();

  EntryType _type = EntryType.expense;
  String? _selectedCategoryId;
  String? _positionedCategoryId;
  LocalMinute _occurredAt = LocalMinute.now();
  bool _isSaving = false;
  bool _isLoading = false;
  bool _isPickingOccurredAt = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _isLoading = true;
      Future<void>.microtask(_loadExisting);
    } else if (widget.initialDraft != null) {
      final draft = widget.initialDraft!;
      _type = draft.type ?? EntryType.expense;
      _selectedCategoryId = draft.categoryId;
      _noteController.text = draft.note;
      _occurredAt = draft.occurredAt ?? LocalMinute.now();
      if (draft.amount != null) _calculator.setAmount(draft.amount!.value);
      Future<void>.microtask(() {
        if (mounted) _showMessage('AI识别结果，请核对');
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesByTypeProvider(_type));
    final settings = ref.watch(appSettingsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          style: IconButton.styleFrom(backgroundColor: Colors.transparent),
        ),
        title: SizedBox(
          width: 188,
          height: AppSizes.segmentedControl,
          child: _TypeToggle(
            selected: _type,
            onChanged: (type) => _changeType(type == EntryType.expense ? 0 : 1),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _loadError != null
          ? Center(child: Text(_loadError!))
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: AppSpacing.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 246,
                      child: categories.when(
                        data: _buildCategoryGrid,
                        loading: () => const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                        error: (error, stackTrace) =>
                            const Center(child: Text('分类加载失败')),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.componentGap),
                    TextField(
                      controller: _noteController,
                      maxLength: 1024,
                      minLines: 1,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: '备注',
                        counterText: '',
                        suffixIcon: Semantics(
                          button: true,
                          label: '选择历史备注',
                          child: IconButton(
                            tooltip: '历史备注',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.transparent,
                            ),
                            onPressed: _selectHistoricalNote,
                            icon: const Icon(Icons.history_rounded),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.componentGap),
                    _CalculatorDisplay(state: _calculator.state),
                    const SizedBox(height: AppSpacing.controlGap),
                    _calculatorActionKeyboard(settings.timePrecision),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCategoryGrid(List<CategoryRow> categories) {
    _positionSelectedCategory(categories);
    return GridView.builder(
      controller: _categoryScrollController,
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _categoryColumnCount,
        mainAxisExtent: _categoryTileExtent,
        mainAxisSpacing: AppSpacing.xxs,
        crossAxisSpacing: AppSpacing.xxs,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final selected = category.id == _selectedCategoryId;
        final color = Color(category.colorValue);
        return InkWell(
          borderRadius: BorderRadius.circular(AppRadii.control),
          onTap: () => setState(() {
            _selectedCategoryId = category.id;
            _positionedCategoryId = category.id;
          }),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CategoryIcon(
                code: category.iconCode,
                color: color,
                size: AppSizes.categoryIcon,
                selected: selected,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? color : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _positionSelectedCategory(List<CategoryRow> categories) {
    final selectedId = _selectedCategoryId;
    if (selectedId == null || selectedId == _positionedCategoryId) return;
    final index = categories.indexWhere(
      (category) => category.id == selectedId,
    );
    if (index < 0) return;
    _positionedCategoryId = selectedId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _selectedCategoryId != selectedId ||
          !_categoryScrollController.hasClients) {
        return;
      }
      final position = _categoryScrollController.position;
      final row = index ~/ _categoryColumnCount;
      final rowBottom = (row + 1) * _categoryTileExtent + row * AppSpacing.xxs;
      final offset = (rowBottom - position.viewportDimension).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _categoryScrollController.jumpTo(offset);
    });
  }

  void _changeType(int index) {
    final nextType = index == 0 ? EntryType.expense : EntryType.income;
    if (nextType == _type) return;
    setState(() {
      _type = nextType;
      _selectedCategoryId = null;
      _positionedCategoryId = null;
      _calculator.press('AC');
    });
  }

  void _pressCalculatorKey(String key) {
    if (_isSaving) return;
    final hasOperator = RegExp(r'[+\-×÷]')
        .hasMatch(_calculator.state.expression);
    final saveMode = !hasOperator || _calculator.state.isCommitted;
    if (key == '=' && saveMode) {
      _save();
      return;
    }
    setState(() => _calculator.press(key));
  }

  Widget _calculatorActionKeyboard(TimePrecision precision) {
    final state = _calculator.state;
    final hasOperator = RegExp(r'[+\-×÷]').hasMatch(state.expression);
    final saveMode = !hasOperator || state.isCommitted;
    return CalculatorKeyboard(
      dateLabel: _occurredAt.date,
      onDateTap: _selectDate,
      time: precision == TimePrecision.minute
          ? (label: _occurredAt.time, onTap: _selectTime)
          : null,
      onPressed: _pressCalculatorKey,
      saveMode: saveMode,
    );
  }

  Future<void> _loadExisting() async {
    try {
      final record = await ref
          .read(bookkeepingRepositoryProvider)
          .getById(widget.transactionId!);
      if (!mounted) return;
      if (record == null) {
        setState(() {
          _isLoading = false;
          _loadError = '账单不存在或已被删除';
        });
        return;
      }
      setState(() {
        _type = record.type;
        _selectedCategoryId = record.category.id;
        _noteController.text = record.entry.note ?? '';
        _occurredAt = record.occurredAt;
        _calculator.setAmount(record.amount.value);
        _isLoading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = appErrorMessage(error, fallback: '账单加载失败，请重试');
        });
      }
    }
  }

  Future<void> _selectDate() => _pickOccurredAt((current) async {
    final dataRange = await ref
        .read(bookkeepingRepositoryProvider)
        .dataYearRange();
    if (!mounted) return null;
    final bounds = AppDatePolicy.pickerBounds(
      dataMinimumYear: dataRange?.minYear,
      dataMaximumYear: dataRange?.maxYear,
      anchorYears: [current.year],
    );
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: bounds.firstDate,
      lastDate: bounds.lastDate,
    );
    if (date == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      current.hour,
      current.minute,
    );
  });

  Future<void> _selectTime() => _pickOccurredAt((current) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return null;
    return DateTime(
      current.year,
      current.month,
      current.day,
      time.hour,
      time.minute,
    );
  });

  Future<void> _pickOccurredAt(
    Future<DateTime?> Function(DateTime current) pick,
  ) async {
    if (_isPickingOccurredAt) return;
    _isPickingOccurredAt = true;
    try {
      final value = await pick(_occurredAt.toDateTime());
      if (value == null || !mounted) return;
      setState(() => _occurredAt = LocalMinute.fromDateTime(value));
    } on Object catch (error) {
      if (mounted) {
        _showMessage(appErrorMessage(error, fallback: '无法选择记账时间，请重试'));
      }
    } finally {
      _isPickingOccurredAt = false;
    }
  }

  Future<void> _selectHistoricalNote() async {
    final settings = ref.read(appSettingsProvider);
    int? amountMinor;
    final calculatorState = _calculator.state;
    if (calculatorState.hasInput &&
        !calculatorState.isError &&
        calculatorState.result != null) {
      try {
        amountMinor = Money.fromDecimal(calculatorState.result!).minorUnits;
      } on ArgumentError {
        amountMinor = null;
      }
    }
    final occurredAt = _occurredAt.toDateTime();
    final notes = ref
        .read(bookkeepingRepositoryProvider)
        .getHistoricalNotes(
          smartSort: settings.historyNoteSmartSort,
          categoryId: _selectedCategoryId,
          amountMinor: amountMinor,
          minuteOfDay: settings.timePrecision == TimePrecision.minute
              ? occurredAt.hour * 60 + occurredAt.minute
              : null,
        );
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AppBottomSheetLayout(
        title: '历史备注',
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: FutureBuilder(
              future: notes,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: Text('历史备注加载失败')),
                  );
                }
                final values = snapshot.data ?? const [];
                if (values.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: Text('暂无历史备注')),
                  );
                }
                return SingleChildScrollView(
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final note in values)
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            textStyle: Theme.of(context).textTheme.labelMedium,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadii.compact,
                              ),
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => Navigator.pop(context, note.value),
                          child: Text(note.value),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _noteController
      ..text = selected
      ..selection = TextSelection.collapsed(offset: selected.length);
  }

  Future<void> _save() async {
    if (_selectedCategoryId == null) {
      _showMessage('请选择分类');
      return;
    }
    if (_calculator.state.isError) {
      _showMessage('金额计算错误');
      return;
    }
    if (!_calculator.state.hasInput || _calculator.state.result == null) {
      _showMessage('请输入金额');
      return;
    }

    late final Money amount;
    try {
      amount = Money.fromDecimal(_calculator.state.result!);
    } on ArgumentError catch (error) {
      _showMessage(error.message?.toString() ?? '金额超出允许范围');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(bookkeepingRepositoryProvider);
      final settings = ref.read(appSettingsProvider);
      final occurredAt = occurrenceForSave(
        selected: _occurredAt,
        precision: settings.timePrecision,
        isEditing: widget.isEditing,
      );
      if (widget.returnDraft && widget.initialDraft != null) {
        final updatedDraft = SmartBookkeepingDraft(
          id: widget.initialDraft!.id,
          source: widget.initialDraft!.source,
          imagePath: widget.initialDraft!.imagePath,
          type: _type,
          amount: amount,
          categoryId: _selectedCategoryId,
          note: _noteController.text.trim(),
          occurredAt: occurredAt,
          confidence: widget.initialDraft!.confidence,
          status: RecognitionStatus.completed,
          errorMessage: widget.initialDraft!.errorMessage,
          usedOnlineAi: widget.initialDraft!.usedOnlineAi,
          onlineFailureGlobal: widget.initialDraft!.onlineFailureGlobal,
        );
        if (mounted) Navigator.pop(context, updatedDraft);
        return;
      } else if (widget.isEditing) {
        await repository.update(
          id: widget.transactionId!,
          type: _type,
          categoryId: _selectedCategoryId!,
          amount: amount,
          occurredAt: occurredAt,
          note: _noteController.text,
        );
      } else {
        await repository.create(
          type: _type,
          categoryId: _selectedCategoryId!,
          amount: amount,
          occurredAt: occurredAt,
          note: _noteController.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showMessage(appErrorMessage(error, fallback: '保存失败，请重试'));
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CalculatorDisplay extends StatelessWidget {
  const _CalculatorDisplay({required this.state});

  final CalculatorState state;

  @override
  Widget build(BuildContext context) {
    final hasOperator = RegExp(r'[+\-×÷]').hasMatch(state.expression);
    final equation = hasOperator
        ? (state.isCommitted ? state.equation : state.expression)
        : '';
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: 68,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            state.isError ? '错误' : equation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.numeric(textTheme.bodyLarge),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            state.isError ? '请使用退格键恢复' : '￥${state.displayAmount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.numeric(textTheme.headlineSmall),
          ),
        ],
      ),
    );
  }
}

class CalculatorKeyboard extends StatelessWidget {
  const CalculatorKeyboard({
    required this.onPressed,
    required this.dateLabel,
    required this.onDateTap,
    required this.saveMode,
    this.time,
    super.key,
  });

  final ValueChanged<String> onPressed;
  final String dateLabel;
  final VoidCallback onDateTap;
  final ({String label, VoidCallback onTap})? time;
  final bool saveMode;

  @override
  Widget build(BuildContext context) {
    final clock = time;
    return Column(
      children: [
        _CalculatorRow(
          leading: clock == null
              ? _CalculatorButton(
                  label: dateLabel,
                  semanticsLabel: '选择记账日期 $dateLabel',
                  primary: false,
                  onPressed: onDateTap,
                )
              : _CalculatorDateTimeKey(
                  dateLabel: dateLabel,
                  onDateTap: onDateTap,
                  time: clock,
                ),
          leadingFlex: 2,
          keys: const [('←', 1), ('÷', 1)],
          onPressed: onPressed,
        ),
        _CalculatorRow(
          keys: const [('7', 1), ('8', 1), ('9', 1), ('×', 1)],
          onPressed: onPressed,
        ),
        _CalculatorRow(
          keys: const [('4', 1), ('5', 1), ('6', 1), ('-', 1)],
          onPressed: onPressed,
        ),
        _CalculatorRow(
          keys: const [('1', 1), ('2', 1), ('3', 1), ('+', 1)],
          onPressed: onPressed,
        ),
        _CalculatorRow(
          keys: const [('0', 2), ('.', 1), ('=', 1)],
          equalsLabel: saveMode ? '保存' : null,
          onPressed: onPressed,
        ),
      ],
    );
  }
}

class _CalculatorDateTimeKey extends StatelessWidget {
  const _CalculatorDateTimeKey({
    required this.dateLabel,
    required this.onDateTap,
    required this.time,
  });

  final String dateLabel;
  final VoidCallback onDateTap;
  final ({String label, VoidCallback onTap}) time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final style = DefaultTextStyle.of(context).style
        .merge(AppTypography.calculator(theme.textTheme))
        .copyWith(
          inherit: false,
          color: colors.onSurface,
          fontSize: theme.textTheme.bodySmall?.fontSize,
          height: 1.15,
        );
    final label = '$dateLabel ${time.label}';
    const padding = EdgeInsets.symmetric(horizontal: AppSpacing.xs);

    Widget target(String label, VoidCallback onTap) => Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStatePropertyAll(
          colors.primary.withAlpha(AppAlpha.pressed),
        ),
      ),
    );

    return Material(
      key: const ValueKey('calculator-date-time-key'),
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.control),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: style),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout();
          final space = painter
              .getBoxesForSelection(
                TextSelection(
                  baseOffset: dateLabel.length,
                  extentOffset: dateLabel.length + 1,
                ),
              )
              .single;
          final available = constraints.deflate(padding);
          final scale = math.min(
            1.0,
            math.min(
              available.maxWidth / painter.width,
              available.maxHeight / painter.height,
            ),
          );
          // Split the hit targets at the space in the centered label.
          final split =
              (constraints.maxWidth - painter.width * scale) / 2 +
              (space.left + space.right) * scale / 2;
          painter.dispose();

          return Stack(
            fit: StackFit.expand,
            children: [
              Row(
                textDirection: TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: split,
                    child: target('选择记账日期 $dateLabel', onDateTap),
                  ),
                  Expanded(child: target('选择记账时分 ${time.label}', time.onTap)),
                ],
              ),
              IgnorePointer(
                child: ExcludeSemantics(
                  child: Padding(
                    padding: padding,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: style,
                        textScaler: textScaler,
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CalculatorRow extends StatelessWidget {
  const _CalculatorRow({
    required this.keys,
    required this.onPressed,
    this.leading,
    this.leadingFlex = 1,
    this.equalsLabel,
  });

  final List<(String, int)> keys;
  final ValueChanged<String> onPressed;
  final Widget? leading;
  final int leadingFlex;
  final String? equalsLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.calculatorRow,
      child: Row(
        children: [
          if (leading != null)
            Expanded(
              flex: leadingFlex,
              child: Padding(
                padding: const EdgeInsets.all(_calculatorKeyInset),
                child: leading,
              ),
            ),
          for (final key in keys)
            Expanded(
              flex: key.$2,
              child: Padding(
                padding: const EdgeInsets.all(_calculatorKeyInset),
                child: _CalculatorButton(
                  label: key.$1 == '=' ? (equalsLabel ?? '=') : key.$1,
                  primary: key.$1 == '=',
                  repeatable: key.$1 == '←',
                  onPressed: () => onPressed(key.$1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalculatorButton extends StatefulWidget {
  const _CalculatorButton({
    required this.label,
    required this.primary,
    required this.onPressed,
    this.repeatable = false,
    this.semanticsLabel,
  });

  final String label;
  final bool primary;
  final bool repeatable;
  final String? semanticsLabel;
  final VoidCallback onPressed;

  @override
  State<_CalculatorButton> createState() => _CalculatorButtonState();
}

class _CalculatorButtonState extends State<_CalculatorButton> {
  Timer? _repeatTimer;
  bool _didRepeat = false;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _startRepeating() {
    if (!widget.repeatable) return;
    _repeatTimer?.cancel();
    _didRepeat = false;
    _repeatTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _didRepeat = true;
      widget.onPressed();
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        widget.onPressed();
      });
    });
  }

  void _stopRepeating() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _handlePressed() {
    if (_didRepeat) {
      _didRepeat = false;
      return;
    }
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final calculatorStyle = AppTypography.calculator(theme.textTheme);
    final button = widget.primary
        ? FilledButton(
            onPressed: widget.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              minimumSize: const Size.fromHeight(AppSizes.calculatorButton),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              side: BorderSide.none,
              padding: EdgeInsets.zero,
              textStyle: calculatorStyle,
            ),
            child: Text(widget.label),
          )
        : TextButton(
            onPressed: widget.repeatable ? _handlePressed : widget.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: colors.onSurface,
              backgroundColor: colors.surfaceContainerLow,
              overlayColor: colors.primary.withAlpha(AppAlpha.pressed),
              side: BorderSide.none,
              minimumSize: const Size.fromHeight(AppSizes.calculatorButton),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              textStyle: calculatorStyle,
            ),
            child: Text(
              widget.label,
              semanticsLabel: widget.semanticsLabel,
              textAlign: TextAlign.center,
              style: calculatorStyle.copyWith(color: colors.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
    if (!widget.repeatable) return button;
    return Listener(
      onPointerDown: (_) => _startRepeating(),
      onPointerUp: (_) => _stopRepeating(),
      onPointerCancel: (_) => _stopRepeating(),
      child: button,
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.selected, required this.onChanged});

  final EntryType selected;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppSegmentedButton<EntryType>(
      compact: true,
      segments: const [
        ButtonSegment(value: EntryType.expense, label: Text('支出')),
        ButtonSegment(value: EntryType.income, label: Text('收入')),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}
