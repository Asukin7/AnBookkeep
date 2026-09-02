import 'dart:convert';

import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:decimal/decimal.dart';

final class AiResponseParser {
  const AiResponseParser();

  AiRecognitionResult parse(
    String response, {
    required Map<String, EntryType> categoryTypes,
  }) {
    final object = _extractJsonObject(response);
    final decoded = jsonDecode(object);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI返回内容不是JSON对象');
    }
    final type = switch (decoded['type']?.toString().toLowerCase()) {
      'expense' => EntryType.expense,
      'income' => EntryType.income,
      _ => null,
    };
    final amount = _parseMoney(decoded['amount']);
    final requestedCategory = decoded['category_id']?.toString().trim();
    final categoryId =
        requestedCategory != null &&
            requestedCategory.isNotEmpty &&
            categoryTypes[requestedCategory] == type
        ? requestedCategory
        : null;
    final note = (decoded['note']?.toString() ?? '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    return AiRecognitionResult(
      type: type,
      amount: amount,
      categoryId: categoryId,
      note: note.length > 1024 ? note.substring(0, 1024) : note,
      occurredAt: _parseTime(decoded['occurred_at']),
      confidence: _parseConfidence(decoded['confidence']),
    );
  }

  static Money? _parseMoney(Object? source) {
    if (source == null) return null;
    final normalized = source
        .toString()
        .replaceAll(',', '')
        .replaceAll('￥', '');
    final value = Decimal.tryParse(normalized)?.abs();
    if (value == null || value > Money.maxValue) return null;
    return Money.fromDecimal(value);
  }

  static LocalMinute? _parseTime(Object? source) {
    if (source == null) return null;
    final normalized = source.toString().trim().replaceFirst('T', ' ');
    if (normalized.length >= 16) {
      try {
        return LocalMinute.parse(normalized.substring(0, 16));
      } on Object {
        return null;
      }
    }
    return null;
  }

  static double? _parseConfidence(Object? source) {
    final value = source is num
        ? source.toDouble()
        : double.tryParse(source?.toString() ?? '');
    return value?.clamp(0, 1).toDouble();
  }

  static String _extractJsonObject(String source) {
    final start = source.indexOf('{');
    if (start < 0) throw const FormatException('AI返回内容中没有JSON');
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < source.length; index++) {
      final char = source[index];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return source.substring(start, index + 1);
      }
    }
    throw const FormatException('AI返回的JSON不完整');
  }
}
