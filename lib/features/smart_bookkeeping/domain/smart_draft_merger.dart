import 'package:anbookkeep/core/database/app_database.dart';
import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/smart_bookkeeping_draft.dart';

/// Combines local OCR and online AI results without performing any I/O.
///
/// Keeping this policy separate from the recognition pipeline makes fallback
/// behavior deterministic and independently testable.
abstract final class SmartDraftMerger {
  static SmartBookkeepingDraft merge({
    required String draftId,
    required String imagePath,
    required SmartBookkeepingSource source,
    required LocalOcrResult local,
    required AiRecognitionResult? ai,
    required List<CategoryRow> categories,
    required SmartRecognitionException? onlineError,
    required Object? localError,
    LocalMinute? fallbackTime,
  }) {
    final type = ai?.type ?? local.type ?? EntryType.expense;
    final amount = ai?.amount ?? local.amount;
    final note = ai?.note.trim().isNotEmpty == true ? ai!.note : local.note;
    final occurredAt =
        ai?.occurredAt ?? local.occurredAt ?? fallbackTime ?? LocalMinute.now();
    final categoryId =
        ai?.categoryId ?? _matchLocalCategory(local.rawText, type, categories);
    final complete = amount != null && categoryId != null;

    return SmartBookkeepingDraft(
      id: draftId,
      source: source,
      imagePath: imagePath,
      type: type,
      amount: amount,
      categoryId: categoryId,
      note: note.replaceAll(RegExp(r'[\r\n]+'), ' ').trim(),
      occurredAt: occurredAt,
      confidence: ai?.confidence,
      status: complete
          ? RecognitionStatus.completed
          : RecognitionStatus.needsReview,
      errorMessage: onlineError != null
          ? '${onlineError.message}，已使用本地识别结果'
          : localError != null && ai == null
          ? '本地OCR识别失败，请手动补充账单信息'
          : null,
      usedOnlineAi: ai != null,
      onlineFailureGlobal: onlineError?.isGlobal ?? false,
    );
  }

  static String? _matchLocalCategory(
    String text,
    EntryType type,
    List<CategoryRow> categories,
  ) {
    for (final category in categories) {
      if (category.type == type.databaseValue && text.contains(category.name)) {
        return category.id;
      }
    }
    return null;
  }
}
