import 'package:flutter/material.dart';

class AppYearMonthWheel extends StatefulWidget {
  const AppYearMonthWheel({
    required this.initialYear,
    required this.initialMonth,
    required this.onChanged,
    this.showMonth = true,
    this.minYear = 2020,
    this.maxYear,
    this.height = 120,
    super.key,
  });

  final int initialYear;
  final int initialMonth;
  final ValueChanged<({int year, int month})> onChanged;
  final bool showMonth;
  final int minYear;
  final int? maxYear;
  final double height;

  @override
  State<AppYearMonthWheel> createState() => _AppYearMonthWheelState();
}

class _AppYearMonthWheelState extends State<AppYearMonthWheel> {
  late final int _maxYear = widget.maxYear ?? DateTime.now().year;
  late int _year = widget.initialYear.clamp(widget.minYear, _maxYear);
  late int _month = widget.initialMonth.clamp(1, 12);
  late final _yearController = FixedExtentScrollController(
    initialItem: _year - widget.minYear,
  );
  late final _monthController = FixedExtentScrollController(
    initialItem: _month - 1,
  );

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  void _notify() => widget.onChanged((year: _year, month: _month));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          Expanded(
            child: ListWheelScrollView.useDelegate(
              controller: _yearController,
              itemExtent: 40,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                _year = widget.minYear + index;
                _notify();
              },
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: _maxYear - widget.minYear + 1,
                builder: (context, index) =>
                    Center(child: Text('${widget.minYear + index}年')),
              ),
            ),
          ),
          if (widget.showMonth)
            Expanded(
              child: ListWheelScrollView.useDelegate(
                controller: _monthController,
                itemExtent: 40,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (index) {
                  _month = index + 1;
                  _notify();
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: 12,
                  builder: (context, index) =>
                      Center(child: Text('${index + 1}月')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
