import 'dart:io';

import 'package:anbookkeep/core/logging/app_logger.dart';
import 'package:anbookkeep/features/smart_bookkeeping/application/recognition_cancellation.dart';
import 'package:anbookkeep/features/smart_bookkeeping/domain/recognition_result.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

final class ImagePreprocessor {
  ImagePreprocessor({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const _directoryName = 'smart_bookkeeping';
  static const _maxAge = Duration(hours: 24);
  static const maxSourceBytes = 25 * 1024 * 1024;
  static const maxPreparedBytes = 8 * 1024 * 1024;
  static const maxPixelCount = 40000000;
  static const maxDimension = 12000;
  static const _imageChannel = MethodChannel('com.an.anbookkeep/shared_images');

  final Uuid _uuid;

  Future<File> prepare(
    String sourcePath, {
    String? operationId,
    RecognitionCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final stopwatch = Stopwatch()..start();
    final source = File(sourcePath);
    if (!await source.exists()) {
      _log.error('image_prepare_missing_source', operationId: operationId);
      throw const FileSystemException('所选图片不存在');
    }
    final sourceBytes = await source.length();
    if (sourceBytes == 0) {
      throw const SmartRecognitionException('所选图片内容为空');
    }
    if (sourceBytes > maxSourceBytes) {
      throw const SmartRecognitionException('单张图片不能超过25MB');
    }
    await _validateImageDimensions(source.absolute.path);
    cancellation?.throwIfCancelled();
    _log.info(
      'image_prepare_started',
      operationId: operationId,
      fields: {'sourceBytes': sourceBytes},
    );
    final directory = await _temporaryDirectory();
    final targetPath =
        '${directory.path}${Platform.pathSeparator}${_uuid.v7()}.jpg';
    XFile? compressed;
    try {
      compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        targetPath,
        minWidth: 1920,
        minHeight: 1920,
        quality: 84,
        format: CompressFormat.jpeg,
        keepExif: false,
        autoCorrectionAngle: true,
      );
      cancellation?.throwIfCancelled();
      if (compressed != null &&
          await File(compressed.path).length() > maxPreparedBytes) {
        await File(compressed.path).delete();
        compressed = await FlutterImageCompress.compressAndGetFile(
          source.path,
          targetPath,
          minWidth: 1280,
          minHeight: 1280,
          quality: 68,
          format: CompressFormat.jpeg,
          keepExif: false,
          autoCorrectionAngle: true,
        );
        cancellation?.throwIfCancelled();
      }
    } on Object {
      final partial = File(targetPath);
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    if (compressed == null) {
      _log.error(
        'image_prepare_failed',
        operationId: operationId,
        fields: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
      throw const FileSystemException('图片处理失败');
    }
    final result = File(compressed.path);
    if (await result.length() > maxPreparedBytes) {
      await result.delete();
      throw const SmartRecognitionException('图片处理后仍然过大，请选择较小的图片');
    }
    _log.info(
      'image_prepare_completed',
      operationId: operationId,
      fields: {
        'sourceBytes': sourceBytes,
        'outputBytes': await result.length(),
        'elapsedMs': stopwatch.elapsedMilliseconds,
      },
    );
    return result;
  }

  Future<void> delete(String path) async {
    try {
      final file = File(path);
      final directory = await _temporaryDirectory();
      if (_isWithin(file, directory) && await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Temporary cleanup is best-effort and must not block bookkeeping.
    }
  }

  Future<void> cleanupExpired() async {
    try {
      final directory = await _temporaryDirectory();
      final cutoff = DateTime.now().subtract(_maxAge);
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) await entity.delete();
      }
    } on Object {
      // The OS may have already removed the cache directory.
    }
  }

  Future<Directory> _temporaryDirectory() async {
    final base = await getTemporaryDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}$_directoryName',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Future<void> _validateImageDimensions(String path) async {
    try {
      final result = await _imageChannel.invokeMapMethod<String, Object?>(
        'inspectImagePath',
        {'path': path},
      );
      if (result == null || result['valid'] != true) {
        throw const SmartRecognitionException('无法读取所选图片');
      }
      final width = result['width'] as int? ?? 0;
      final height = result['height'] as int? ?? 0;
      if (width > maxDimension ||
          height > maxDimension ||
          width * height > maxPixelCount) {
        throw const SmartRecognitionException('图片尺寸过大，请选择较小的图片');
      }
    } on MissingPluginException {
      // Unit tests and non-Android previews have no native image inspector.
    }
  }

  static bool _isWithin(File file, Directory directory) {
    final root = directory.absolute.path.toLowerCase();
    final target = file.absolute.path.toLowerCase();
    return target == root ||
        target.startsWith('$root${Platform.pathSeparator}');
  }
}

const _log = AppLogger('SmartBookkeeping');
