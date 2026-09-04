import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A lightweight in-process signal emitted after bills are persisted.
///
/// Screens keep ownership of their paging state and decide how much data to
/// refresh when the revision changes.
final class LedgerChangeNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void notifyChanged() => state++;
}

final ledgerChangeRevisionProvider =
    NotifierProvider<LedgerChangeNotifier, int>(LedgerChangeNotifier.new);
