import 'package:anbookkeep/features/bookkeeping/application/ledger_change_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notifyChanged increments the ledger change revision', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(ledgerChangeRevisionProvider), 0);

    container.read(ledgerChangeRevisionProvider.notifier).notifyChanged();

    expect(container.read(ledgerChangeRevisionProvider), 1);
  });
}
