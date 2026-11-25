import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('CategoryRow')
@TableIndex(name: 'categories_type_order', columns: {#type, #sortOrder})
@TableIndex(name: 'categories_type_name', columns: {#type, #name}, unique: true)
class Categories extends Table {
  TextColumn get id => text()();
  IntColumn get type =>
      integer().customConstraint('NOT NULL CHECK (type IN (0, 1))')();
  TextColumn get name => text().withLength(min: 1, max: 32)();
  TextColumn get iconCode => text().withLength(min: 1, max: 64)();
  IntColumn get colorValue => integer()();
  IntColumn get sortOrder => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TransactionRow')
@TableIndex(name: 'transactions_occurred_at', columns: {#occurredAt})
@TableIndex(
  name: 'transactions_type_occurred_at',
  columns: {#type, #occurredAt},
)
@TableIndex(name: 'transactions_category_id', columns: {#categoryId})
@TableIndex(name: 'transactions_amount_minor', columns: {#amountMinor})
class BookkeepingEntries extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()();
  IntColumn get type =>
      integer().customConstraint('NOT NULL CHECK (type IN (0, 1))')();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();
  IntColumn get amountMinor => integer().customConstraint(
    'NOT NULL CHECK (amount_minor BETWEEN 0 AND 99999999999)',
  )();
  TextColumn get note => text().withLength(max: 1024).nullable()();
  TextColumn get occurredAt => text().withLength(min: 16, max: 16)();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [Categories, BookkeepingEntries],
  include: {'backup_revision.drift'},
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  AppDatabase.defaults() : super(driftDatabase(name: 'anbookkeep'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _insertDefaultCategories();
      await _initializeBackupRevision();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await transaction(() async {
          await migrator.createTable(backupRevisions);
          await _initializeBackupRevision();
          for (final trigger in allSchemaEntities.whereType<Trigger>()) {
            await migrator.createTrigger(trigger);
          }
        });
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<void> _initializeBackupRevision() => customStatement(
    'INSERT INTO backup_revisions (id, revision) VALUES (1, 0)',
  );

  Future<void> _insertDefaultCategories() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await batch((batch) {
      batch.insertAll(categories, [
        for (final category in _defaultCategories)
          CategoriesCompanion.insert(
            id: category.id,
            type: category.type,
            name: category.name,
            iconCode: category.iconCode,
            colorValue: category.colorValue,
            sortOrder: category.sortOrder,
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }
}

const _defaultCategories = <_DefaultCategory>[
  _DefaultCategory('expense-food', 0, '餐饮', 'food', 0xFFFF7043, 0),
  _DefaultCategory('expense-shopping', 0, '购物', 'shopping', 0xFFEC407A, 1),
  _DefaultCategory('expense-clothing', 0, '服饰', 'checkroom', 0xFFAB47BC, 2),
  _DefaultCategory(
    'expense-transport',
    0,
    '交通',
    'directions_car',
    0xFF42A5F5,
    3,
  ),
  _DefaultCategory('expense-education', 0, '教育', 'education', 0xFF5C6BC0, 4),
  _DefaultCategory('expense-medical', 0, '医疗', 'medical', 0xFFEF5350, 5),
  _DefaultCategory('expense-relationship', 0, '情感', 'favorite', 0xFFF06292, 6),
  _DefaultCategory('expense-pet', 0, '宠物', 'pet', 0xFF8D6E63, 7),
  _DefaultCategory(
    'expense-communication',
    0,
    '通讯',
    'communication',
    0xFF26A69A,
    8,
  ),
  _DefaultCategory('expense-network', 0, '网络', 'wifi', 0xFF29B6F6, 9),
  _DefaultCategory(
    'expense-entertainment',
    0,
    '娱乐',
    'entertainment',
    0xFF7E57C2,
    10,
  ),
  _DefaultCategory('expense-travel', 0, '旅行', 'flight', 0xFF26C6DA, 11),
  _DefaultCategory('expense-housing', 0, '住房', 'housing', 0xFF78909C, 12),
  _DefaultCategory(
    'expense-utilities',
    0,
    '缴费',
    'reimbursement',
    0xFFFFA726,
    13,
  ),
  _DefaultCategory('expense-social', 0, '社交', 'handshake', 0xFF66BB6A, 14),
  _DefaultCategory('expense-transfer', 0, '转账', 'refund', 0xFF00897B, 15),
  _DefaultCategory('expense-red-packet', 0, '红包', 'wallet', 0xFFFF5252, 16),
  _DefaultCategory('expense-giving-gift', 0, '送礼', 'gift', 0xFFFF8A65, 17),
  _DefaultCategory(
    'expense-donation',
    0,
    '捐款',
    'volunteer_activism',
    0xFFD81B60,
    18,
  ),
  _DefaultCategory('expense-other', 0, '其他', 'other', 0xFF78909C, 19),
  _DefaultCategory('income-salary', 1, '工资', 'part_time', 0xFF26A69A, 0),
  _DefaultCategory('income-rent', 1, '房租', 'housing', 0xFF7CB342, 1),
  _DefaultCategory('income-red-packet', 1, '红包', 'wallet', 0xFFFF5252, 2),
  _DefaultCategory('income-gift', 1, '收礼', 'gift', 0xFFFF8A65, 3),
  _DefaultCategory('income-refund', 1, '退款', 'undo', 0xFF29B6F6, 4),
  _DefaultCategory('income-resale', 1, '转卖', 'loyalty', 0xFFAB47BC, 5),
  _DefaultCategory('income-investment', 1, '理财', 'investment', 0xFFFFB300, 6),
  _DefaultCategory('income-other', 1, '其他', 'other', 0xFF78909C, 7),
];

final class _DefaultCategory {
  const _DefaultCategory(
    this.id,
    this.type,
    this.name,
    this.iconCode,
    this.colorValue,
    this.sortOrder,
  );

  final String id;
  final int type;
  final String name;
  final String iconCode;
  final int colorValue;
  final int sortOrder;
}
