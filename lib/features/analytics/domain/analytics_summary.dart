final class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalMinor,
    required this.averageMinor,
    required this.recordCount,
  });

  factory AnalyticsSummary.fromAggregate({
    required int totalMinor,
    required int recordCount,
    required int denominator,
  }) => AnalyticsSummary(
    totalMinor: totalMinor,
    averageMinor: _roundedDivision(totalMinor, denominator),
    recordCount: recordCount,
  );

  final int totalMinor;
  final int averageMinor;
  final int recordCount;
}

int _roundedDivision(int value, int denominator) {
  if (denominator <= 0 || value == 0) return 0;
  final absolute = value.abs();
  final rounded = (absolute * 2 + denominator) ~/ (denominator * 2);
  return value.isNegative ? -rounded : rounded;
}
