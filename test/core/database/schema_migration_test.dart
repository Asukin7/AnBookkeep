import 'package:anbookkeep/core/database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../drift/schema.dart';

void main() {
  test('version 1 ledger is migrated with revision tracking', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(1);
    final database = AppDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(
      database,
      2,
      options: const ValidationOptions(validateDropped: true),
    );

    expect(await database.readBackupRevision().getSingle(), 0);
    await database.customStatement('''
      INSERT INTO categories (
        id, type, name, icon_code, color_value, sort_order, created_at, updated_at
      ) VALUES ('c1', 0, '餐饮', 'food', 0, 0, 0, 0)
    ''');
    await database.customStatement('''
      INSERT INTO transactions (
        id, type, category_id, amount_minor, note, occurred_at, created_at, updated_at
      ) VALUES ('t1', 0, 'c1', 100, NULL, '2026-11-25 08:30', 0, 0)
    ''');
    expect(await database.readBackupRevision().getSingle(), 1);
    await database.customStatement(
      "UPDATE categories SET color_value = 1 WHERE id = 'c1'",
    );
    await database.customStatement(
      "UPDATE transactions SET amount_minor = 100 WHERE id = 't1'",
    );
    expect(await database.readBackupRevision().getSingle(), 1);
    await database.customStatement(
      "UPDATE categories SET name = '早餐' WHERE id = 'c1'",
    );
    await database.customStatement("DELETE FROM transactions WHERE id = 't1'");
    expect(await database.readBackupRevision().getSingle(), 3);
  });
}
