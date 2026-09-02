import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

enum AppLogLevel {
  debug(500),
  info(800),
  warning(900),
  error(1000);

  const AppLogLevel(this.value);

  final int value;
}

/// Project-wide structured logging entry point.
///
/// Event names should be stable `snake_case` identifiers. Pass diagnostic
/// context through [fields], but never rely only on callers for privacy: known
/// sensitive field names are redacted before output.
final class AppLogger {
  const AppLogger(this.module);

  static const _rootName = 'AnBookkeep';
  static const _redacted = '<redacted>';
  static const _sensitiveChunkSize = 2800;
  static final RegExp _sensitiveField = RegExp(
    r'api[_-]?key|authorization|password|secret|token|prompt|ocr[_-]?text|raw[_-]?text|note|amount|image[_-]?path|source[_-]?path|file[_-]?path|response|request[_-]?body|message',
    caseSensitive: false,
  );

  /// Debug builds retain lifecycle logs. Release builds only retain warnings
  /// and errors to keep runtime overhead and log volume low.
  static AppLogLevel minimumLevel = kReleaseMode
      ? AppLogLevel.warning
      : AppLogLevel.debug;

  final String module;

  void debug(
    String event, {
    String? operationId,
    Map<String, Object?> fields = const {},
  }) => _write(
    AppLogLevel.debug,
    event,
    operationId: operationId,
    fields: fields,
  );

  void info(
    String event, {
    String? operationId,
    Map<String, Object?> fields = const {},
  }) =>
      _write(AppLogLevel.info, event, operationId: operationId, fields: fields);

  void warning(
    String event, {
    String? operationId,
    Map<String, Object?> fields = const {},
  }) => _write(
    AppLogLevel.warning,
    event,
    operationId: operationId,
    fields: fields,
  );

  /// Logs the runtime type of [cause], never its potentially sensitive text.
  void error(
    String event, {
    String? operationId,
    Object? cause,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) => _write(
    AppLogLevel.error,
    event,
    operationId: operationId,
    fields: {...fields, if (cause != null) 'errorType': cause.runtimeType},
    stackTrace: stackTrace,
  );

  /// Outputs sensitive diagnostic content only in debug builds.
  ///
  /// This is intended for payloads such as OCR text, rendered prompts, and raw
  /// AI responses. Content is split into Logcat-safe chunks and is never
  /// emitted in profile or release builds.
  void sensitiveDebug(
    String event, {
    required String content,
    String? operationId,
  }) {
    if (!kDebugMode || AppLogLevel.debug.value < minimumLevel.value) return;
    final codePoints = content.runes.toList(growable: false);
    final partCount = codePoints.isEmpty
        ? 1
        : (codePoints.length + _sensitiveChunkSize - 1) ~/ _sensitiveChunkSize;
    for (var part = 0; part < partCount; part++) {
      final start = part * _sensitiveChunkSize;
      final end = start + _sensitiveChunkSize < codePoints.length
          ? start + _sensitiveChunkSize
          : codePoints.length;
      final chunk = codePoints.isEmpty
          ? '<empty>'
          : String.fromCharCodes(codePoints.sublist(start, end));
      final operation = operationId == null || operationId.isEmpty
          ? ''
          : ' operation=${_safeValue(operationId)}';
      developer.log(
        '$event | sensitive=true$operation part=${part + 1}/$partCount\n$chunk',
        name: '$_rootName.$module',
        level: AppLogLevel.debug.value,
      );
    }
  }

  void _write(
    AppLogLevel level,
    String event, {
    required String? operationId,
    required Map<String, Object?> fields,
    StackTrace? stackTrace,
  }) {
    if (level.value < minimumLevel.value) return;
    final details = <String>[
      if (operationId != null && operationId.isNotEmpty)
        'operation=${_safeValue(operationId)}',
      for (final entry in fields.entries)
        '${entry.key}=${_safeField(entry.key, entry.value)}',
    ];
    developer.log(
      details.isEmpty ? event : '$event | ${details.join(' ')}',
      name: '$_rootName.$module',
      level: level.value,
      stackTrace: stackTrace,
    );
  }

  static String _safeField(String key, Object? value) {
    if (_sensitiveField.hasMatch(key)) return _redacted;
    return _safeValue(value);
  }

  static String _safeValue(Object? value) {
    if (value == null) return 'null';
    if (value is Iterable) return '<${value.length} items>';
    if (value is Map) return '<${value.length} entries>';
    final singleLine = value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
    return singleLine.length <= 160
        ? singleLine
        : '${singleLine.substring(0, 160)}…';
  }
}
