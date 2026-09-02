import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';

enum SmartBookkeepingSource { camera, gallery }

enum RecognitionStatus {
  queued,
  processing,
  completed,
  needsReview,
  failed,
  cancelled,
}

final class SmartBookkeepingDraft {
  const SmartBookkeepingDraft({
    required this.id,
    required this.source,
    required this.imagePath,
    this.type,
    this.amount,
    this.categoryId,
    this.note = '',
    this.occurredAt,
    this.confidence,
    this.status = RecognitionStatus.queued,
    this.errorMessage,
    this.usedOnlineAi = false,
    this.onlineFailureGlobal = false,
  });

  final String id;
  final SmartBookkeepingSource source;
  final String imagePath;
  final EntryType? type;
  final Money? amount;
  final String? categoryId;
  final String note;
  final LocalMinute? occurredAt;
  final double? confidence;
  final RecognitionStatus status;
  final String? errorMessage;
  final bool usedOnlineAi;
  final bool onlineFailureGlobal;

  bool get isComplete =>
      type != null &&
      amount != null &&
      categoryId != null &&
      occurredAt != null;

  SmartBookkeepingDraft copyWith({
    EntryType? type,
    Money? amount,
    String? categoryId,
    String? note,
    LocalMinute? occurredAt,
    double? confidence,
    RecognitionStatus? status,
    String? errorMessage,
    bool? usedOnlineAi,
    bool? onlineFailureGlobal,
  }) {
    return SmartBookkeepingDraft(
      id: id,
      source: source,
      imagePath: imagePath,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      occurredAt: occurredAt ?? this.occurredAt,
      confidence: confidence ?? this.confidence,
      status: status ?? this.status,
      errorMessage: errorMessage,
      usedOnlineAi: usedOnlineAi ?? this.usedOnlineAi,
      onlineFailureGlobal: onlineFailureGlobal ?? this.onlineFailureGlobal,
    );
  }
}

final class BookkeepingDraftPageArgs {
  const BookkeepingDraftPageArgs({
    required this.draft,
    this.returnDraft = false,
  });

  final SmartBookkeepingDraft draft;
  final bool returnDraft;
}
