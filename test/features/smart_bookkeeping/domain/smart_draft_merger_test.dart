import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_draft_merger.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const categories = [
    CategoryRow(
      id: 'expense-food',
      type: 0,
      name: '餐饮',
      iconCode: 'restaurant',
      colorValue: 0xFFFF0000,
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
    ),
    CategoryRow(
      id: 'income-salary',
      type: 1,
      name: '工资',
      iconCode: 'part_time',
      colorValue: 0xFF00FF00,
      sortOrder: 0,
      createdAt: 0,
      updatedAt: 0,
    ),
  ];
  final fallbackTime = LocalMinute.parse('2026-09-01 12:34');

  test('online AI fields take precedence and multiline note is normalized', () {
    final draft = SmartDraftMerger.merge(
      draftId: 'draft',
      imagePath: 'image.jpg',
      source: SmartBookkeepingSource.gallery,
      local: LocalOcrResult(
        rawText: '餐饮 10元',
        type: EntryType.expense,
        amount: Money.fromDecimal(Decimal.parse('10')),
        note: '本地备注',
      ),
      ai: AiRecognitionResult(
        type: EntryType.income,
        amount: Money.fromDecimal(Decimal.parse('20')),
        categoryId: 'income-salary',
        note: '线上\n备注',
        occurredAt: LocalMinute.parse('2026-08-31 09:00'),
        confidence: 0.9,
      ),
      categories: categories,
      onlineError: null,
      localError: null,
      fallbackTime: fallbackTime,
    );

    expect(draft.type, EntryType.income);
    expect(draft.amount?.minorUnits, 2000);
    expect(draft.categoryId, 'income-salary');
    expect(draft.note, '线上 备注');
    expect(draft.status, RecognitionStatus.completed);
    expect(draft.usedOnlineAi, isTrue);
  });

  test(
    'local OCR matches category and supplies deterministic fallback time',
    () {
      final draft = SmartDraftMerger.merge(
        draftId: 'draft',
        imagePath: 'image.jpg',
        source: SmartBookkeepingSource.camera,
        local: LocalOcrResult(
          rawText: '餐饮消费 15.50',
          amount: Money.fromDecimal(Decimal.parse('15.50')),
        ),
        ai: null,
        categories: categories,
        onlineError: const SmartRecognitionException('AI不可用'),
        localError: null,
        fallbackTime: fallbackTime,
      );

      expect(draft.type, EntryType.expense);
      expect(draft.categoryId, 'expense-food');
      expect(draft.occurredAt, fallbackTime);
      expect(draft.status, RecognitionStatus.completed);
      expect(draft.errorMessage, 'AI不可用，已使用本地识别结果');
      expect(draft.usedOnlineAi, isFalse);
    },
  );

  test('incomplete local result requires review and reports OCR failure', () {
    final draft = SmartDraftMerger.merge(
      draftId: 'draft',
      imagePath: 'image.jpg',
      source: SmartBookkeepingSource.camera,
      local: const LocalOcrResult(rawText: ''),
      ai: null,
      categories: categories,
      onlineError: null,
      localError: StateError('ocr failed'),
      fallbackTime: fallbackTime,
    );

    expect(draft.amount, isNull);
    expect(draft.categoryId, isNull);
    expect(draft.status, RecognitionStatus.needsReview);
    expect(draft.errorMessage, '本地OCR识别失败，请手动补充账单信息');
  });
}
