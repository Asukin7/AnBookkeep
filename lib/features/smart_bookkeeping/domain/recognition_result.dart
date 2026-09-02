import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/errors/app_error_message.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';

final class LocalOcrResult {
  const LocalOcrResult({
    required this.rawText,
    this.type,
    this.amount,
    this.note = '',
    this.occurredAt,
  });

  final String rawText;
  final EntryType? type;
  final Money? amount;
  final String note;
  final LocalMinute? occurredAt;
}

final class AiRecognitionResult {
  const AiRecognitionResult({
    this.type,
    this.amount,
    this.categoryId,
    this.note = '',
    this.occurredAt,
    this.confidence,
  });

  final EntryType? type;
  final Money? amount;
  final String? categoryId;
  final String note;
  final LocalMinute? occurredAt;
  final double? confidence;
}

final class SmartRecognitionException implements UserFacingException {
  const SmartRecognitionException(this.message, {this.isGlobal = false});

  @override
  final String message;
  final bool isGlobal;

  @override
  String toString() => message;
}
