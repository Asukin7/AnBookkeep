import 'dart:async';
import 'dart:io';

import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/core/money/money.dart';
import 'package:anbookkeep/features/bookkeeping/domain/entry_type.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:decimal/decimal.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';

final class LocalOcrService {
  LocalOcrService({PaddleOcr? ocr}) : _ocr = ocr ?? PaddleOcr();

  final PaddleOcr _ocr;
  Future<void>? _initialization;
  Future<void> _recognitionTail = Future<void>.value();

  Future<LocalOcrResult> recognize(File image, {String? operationId}) async {
    final previous = _recognitionTail;
    final release = Completer<void>();
    _recognitionTail = release.future;
    await previous;
    try {
      return await _recognizeExclusive(image, operationId: operationId);
    } finally {
      release.complete();
    }
  }

  Future<LocalOcrResult> _recognizeExclusive(
    File image, {
    String? operationId,
  }) async {
    final stopwatch = Stopwatch()..start();
    _log.info(
      'local_ocr_started',
      operationId: operationId,
      fields: {'engine': 'paddle_ocr_v6'},
    );
    try {
      final initialization = Stopwatch()..start();
      await _ensureInitialized();
      _log.debug(
        'local_ocr_engine_ready',
        operationId: operationId,
        fields: {'elapsedMs': initialization.elapsedMilliseconds},
      );
      final recognized = await _ocr.recognize(image.absolute.path);
      final rawText = recognized.results
          .map((region) => region.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');
      _log.sensitiveDebug(
        'local_ocr_raw_text',
        operationId: operationId,
        content: rawText,
      );
      final result = parse(rawText);
      _log.info(
        'local_ocr_completed',
        operationId: operationId,
        fields: {
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'detectionMs': recognized.detectionTimeMs,
          'recognitionMs': recognized.recognitionTimeMs,
          'regionCount': recognized.results.length,
          'textChars': result.rawText.length,
          'textLines': result.rawText.isEmpty
              ? 0
              : result.rawText.split('\n').length,
          'hasType': result.type != null,
          'hasAmount': result.amount != null,
          'hasNote': result.note.isNotEmpty,
          'hasTime': result.occurredAt != null,
        },
      );
      return result;
    } on Object catch (error, stackTrace) {
      _log.error(
        'local_ocr_failed',
        operationId: operationId,
        cause: error,
        stackTrace: stackTrace,
        fields: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
      rethrow;
    }
  }

  Future<void> _ensureInitialized() async {
    final existing = _initialization;
    if (existing != null) return existing;
    final initialization = _ocr.init(
      config: const PaddleOcrConfig(),
      engine: const EngineConfig(numThreads: 4),
    );
    _initialization = initialization;
    try {
      await initialization;
    } on Object {
      if (identical(_initialization, initialization)) _initialization = null;
      rethrow;
    }
  }

  LocalOcrResult parse(String rawText) {
    final normalized = rawText.replaceAll('\r', '').trim();
    return LocalOcrResult(
      rawText: normalized,
      type: _extractType(normalized),
      amount: _extractAmount(normalized),
      note: _extractNote(normalized),
      occurredAt: _extractTime(normalized),
    );
  }

  static EntryType? _extractType(String text) {
    if (RegExp(r'收款|已到账|收入|转入|退款成功|退款到账').hasMatch(text) ||
        RegExp(r'(^|\s)\+\s*￥?\d').hasMatch(text)) {
      return EntryType.income;
    }
    if (RegExp(r'付款|支付成功|已支付|实付|支出|转出|消费').hasMatch(text) ||
        RegExp(r'(^|\s)-\s*￥?\d').hasMatch(text)) {
      return EntryType.expense;
    }
    return null;
  }

  static Money? _extractAmount(String text) {
    final compact = text.replaceAll(RegExp(r'[ ,，]'), '');
    final patterns = <RegExp>[
      RegExp(
        r'(?:实付|付款|支付|收款|收入|到账|退款|金额)[^\d]{0,8}[+\-]?[￥¥]?\s*(\d+(?:\.\d{1,2})?)',
      ),
      RegExp(r'[+\-]?[￥¥]\s*(\d+(?:\.\d{1,2})?)'),
      RegExp(r'(\d+(?:\.\d{1,2})?)\s*元'),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(compact)) {
        final value = Decimal.tryParse(match.group(1)!);
        if (value == null || value < Decimal.zero || value > Money.maxValue) {
          continue;
        }
        return Money.fromDecimal(value);
      }
    }
    return null;
  }

  static String _extractNote(String text) {
    final ignored = RegExp(
      r'微信支付|支付宝|支付成功|付款成功|收款成功|交易成功|账单详情|交易详情|交易时间|创建时间|付款时间|收款时间|订单号|商户单号|交易单号|支付方式|当前状态|￥|¥',
    );
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.length < 2 || line.length > 80) continue;
      if (ignored.hasMatch(line)) continue;
      if (RegExp(r'^[-+￥¥\d.,:：/\s]+$').hasMatch(line)) continue;
      final normalized = line.replaceAll(RegExp(r'\s+'), ' ');
      return normalized.length > 80 ? normalized.substring(0, 80) : normalized;
    }
    return '';
  }

  static LocalMinute? _extractTime(String text) {
    final dateMatch = RegExp(r'(20\d{2})[-/.年](\d{1,2})[-/.月](\d{1,2})日?')
        .firstMatch(text);
    if (dateMatch == null) return null;
    final timeMatch = RegExp(r'([01]?\d|2[0-3])[:：](\d{2})')
        .firstMatch(text.substring(dateMatch.end));
    final now = DateTime.now();
    final hour = timeMatch == null ? now.hour : int.parse(timeMatch.group(1)!);
    final minute = timeMatch == null
        ? now.minute
        : int.parse(timeMatch.group(2)!);
    String two(int part) => part.toString().padLeft(2, '0');
    try {
      return LocalMinute.parse(
        '${dateMatch.group(1)!}-${two(int.parse(dateMatch.group(2)!))}-'
        '${two(int.parse(dateMatch.group(3)!))} ${two(hour)}:${two(minute)}',
      );
    } on FormatException {
      return null;
    }
  }
}

const _log = AppLogger('SmartBookkeeping');
