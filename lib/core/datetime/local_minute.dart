final class LocalMinute implements Comparable<LocalMinute> {
  const LocalMinute._(this.value);

  static final RegExp _pattern = RegExp(
    r'^\d{4}-(0[1-9]|1[0-2])-([0-2]\d|3[01]) ([01]\d|2[0-3]):[0-5]\d$',
  );

  final String value;

  factory LocalMinute.now() => LocalMinute.fromDateTime(DateTime.now());

  factory LocalMinute.fromDateTime(DateTime dateTime) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return LocalMinute._(
      '${dateTime.year.toString().padLeft(4, '0')}-'
      '${twoDigits(dateTime.month)}-${twoDigits(dateTime.day)} '
      '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}',
    );
  }

  factory LocalMinute.parse(String value) {
    if (!_pattern.hasMatch(value)) {
      throw FormatException('记账时间格式必须为 yyyy-MM-dd HH:mm', value);
    }

    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed == null || LocalMinute.fromDateTime(parsed).value != value) {
      throw FormatException('记账时间不是有效的本地日期时间', value);
    }
    return LocalMinute._(value);
  }

  String get yearMonth => value.substring(0, 7);
  String get date => value.substring(0, 10);
  String get time => value.substring(11, 16);

  DateTime toDateTime() => DateTime.parse(value.replaceFirst(' ', 'T'));

  @override
  int compareTo(LocalMinute other) => value.compareTo(other.value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LocalMinute && value == other.value;

  @override
  int get hashCode => value.hashCode;
}
