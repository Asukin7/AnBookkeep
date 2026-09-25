import 'package:anbookkeep/core/database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../drift/schema.dart';

void main() {
  test('schema version 1 matches the checked-in release baseline', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(1);
    final database = AppDatabase(connection);

    await verifier.migrateAndValidate(
      database,
      1,
      options: const ValidationOptions(validateDropped: true),
    );

    await database.close();
  });
}
