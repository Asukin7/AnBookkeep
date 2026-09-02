enum EntryType {
  expense(databaseValue: 0, label: '支出', direction: -1),
  income(databaseValue: 1, label: '收入', direction: 1);

  const EntryType({
    required this.databaseValue,
    required this.label,
    required this.direction,
  });

  final int databaseValue;
  final String label;
  final int direction;

  String get prefix => direction > 0 ? '+' : '-';

  static EntryType fromDatabase(int value) => switch (value) {
    0 => EntryType.expense,
    1 => EntryType.income,
    _ => throw ArgumentError.value(value, 'value', '未知的收支类型'),
  };
}
