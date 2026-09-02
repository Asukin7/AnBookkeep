import 'package:anbookkeep/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('creates all default expense and income categories', () async {
    final rows = await database.select(database.categories).get();

    expect(rows.where((row) => row.type == 0), hasLength(20));
    expect(rows.where((row) => row.type == 1), hasLength(8));
  });
}
