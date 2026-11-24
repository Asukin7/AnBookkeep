enum BookkeepingSearchOrder {
  timeDescending,
  timeAscending,
  amountDescending,
  amountAscending;

  bool get isAmount => this == amountDescending || this == amountAscending;

  BookkeepingSearchOrder get next => values[(index + 1) % values.length];
}
